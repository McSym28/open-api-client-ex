defmodule OpenAPIClient.Plugs.RequestTypedDecoder do
  @moduledoc """
  A plug for decoding `:body_params`, `:path_params`, `:query_params`, `:req_headers` and `:req_cookies`
  using types provided by the `oapi_generator` library

  Accepts the following `opts`:
  * `:typed_decoder` - Module that implements `OpenAPIClient.TypedDecoder` behaviour.
  Default value obtained through a call to `OpenAPIClient.Utils.get_config(conn, :typed_decoder, OpenAPIClient.TypedDecoder)`
  * `:body_reader` - MFA to read `:body_params`. By default the `OpenAPIClient.State.read_body_params/2` is
  being called, which currently removes the `"_json"` for JSON parser (and possible `"_body"` key).

  """

  @behaviour Plug

  alias OpenAPIClient.Error

  @type option :: {:typed_decoder, module()} | {:body_reader, {module(), atom(), list()}}
  @type options :: [option()]

  @impl Plug
  @spec init(options()) :: options()
  def init(opts), do: opts

  @impl Plug
  @spec call(Plug.Conn.t(), options()) :: Plug.Conn.t()
  def call(conn, opts) do
    %Plug.Conn{
      path_params: path_params,
      query_params: query_params,
      req_headers: headers,
      req_cookies: cookies
    } =
      conn =
      conn
      |> Plug.Conn.fetch_query_params()
      |> Plug.Conn.fetch_cookies()

    %OpenAPIClient.State{
      request_path: request_path,
      method: method,
      request_parameter_types: parameter_types
    } = state = OpenAPIClient.get_state(conn)

    typed_decoder =
      Keyword.get_lazy(opts, :typed_decoder, fn ->
        OpenAPIClient.Utils.get_config(
          conn,
          :typed_decoder,
          OpenAPIClient.TypedDecoder
        )
      end)

    path_rest = [{request_path, method}]

    path_params = Map.new(path_params, fn {key, value} -> {{key, :path}, value} end)
    query_params = Map.new(query_params, fn {key, value} -> {{key, :query}, value} end)
    headers = Map.new(headers, fn {key, value} -> {{String.downcase(key), :header}, value} end)
    cookies = Map.new(cookies, fn {key, value} -> {{key, :cookie}, value} end)

    parameter_types =
      Enum.map(parameter_types, fn
        {{_name_atom, :header} = parameter_key, {name, type}} ->
          {parameter_key, {String.downcase(name), type}}

        {{_name_atom, :header} = parameter_key, {name, type, default}} ->
          {parameter_key, {String.downcase(name), type, default}}

        other ->
          other
      end)

    path_params
    |> Map.merge(query_params)
    |> Map.merge(headers)
    |> Map.merge(cookies)
    |> Enum.flat_map(fn {{name, location}, value} ->
      parameter_types
      |> find_parameter(name, location)
      |> case do
        {_, {name, type}} ->
          [{{:parameter, location, name}, type, value}]

        {_, {name, type, _default}} ->
          [{{:parameter, location, name}, type, value}]

        nil ->
          []
      end
    end)
    |> then(fn parameters ->
      case state do
        %OpenAPIClient.State{request_types: []} ->
          parameters

        %OpenAPIClient.State{} ->
          {mod, fun, args} =
            Keyword.get(opts, :body_reader, {OpenAPIClient, :read_body_params, []})

          case apply(mod, fun, [conn, opts | args]) do
            {:ok, body, _conn} when not is_nil(body) ->
              {content_type, type} =
                conn
                |> OpenAPIClient.State.get_request_type()
                |> case do
                  {:ok, {content_type, type}} -> {content_type, type}
                  {:error, _} -> {nil, :unknown}
                end

              [{{:request_body, content_type}, type, body} | parameters]

            _ ->
              parameters
          end
      end
    end)
    |> Enum.reduce_while(conn, fn {path_prefix, type, value}, conn ->
      value
      |> typed_decoder.decode(type, [path_prefix | path_rest], typed_decoder)
      |> case do
        {:ok, decoded_value} ->
          conn_new =
            case path_prefix do
              {:request_body, _content_type} ->
                %OpenAPIClient.State{} = state = OpenAPIClient.get_state(conn)
                state_new = %OpenAPIClient.State{state | request_body: decoded_value}
                OpenAPIClient.set_state(conn, state_new)

              {:parameter, location, name} ->
                parameter_types
                |> find_parameter(name, location)
                |> case do
                  nil ->
                    conn

                  {{name_atom, _location}, _parameter_type} ->
                    map_key =
                      case location do
                        :path -> :request_path_params
                        :query -> :request_query_params
                        :header -> :request_headers
                        :cookie -> :request_cookies
                      end

                    %OpenAPIClient.State{} = state = OpenAPIClient.get_state(conn)

                    state_new =
                      update_in(
                        state,
                        [Access.key!(map_key)],
                        &Map.put(&1, name_atom, decoded_value)
                      )

                    OpenAPIClient.set_state(conn, state_new)
                end
            end

          {:cont, conn_new}

        {:error, %Error{} = error} ->
          conn_new =
            OpenAPIClient.set_state_result(
              conn,
              {:error, %Error{error | conn: conn, plug: __MODULE__}}
            )

          {:halt, conn_new}
      end
    end)
  end

  defp find_parameter(parameter_types, name, location) do
    Enum.find_value(parameter_types, fn
      {{_name_atom, ^location}, {^name, _type, _default}} = parameter -> parameter
      {{_name_atom, ^location}, {^name, _type}} = parameter -> parameter
      _ -> nil
    end)
  end
end

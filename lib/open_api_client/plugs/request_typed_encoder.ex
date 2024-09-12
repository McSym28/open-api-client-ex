defmodule OpenAPIClient.Plugs.RequestTypedEncoder do
  @moduledoc """
  A plug for encoding `:request_body`, `:request_headers`, `:request_path_params` and `:request_query_params`
  using types provided by the `oapi_generator` library

  Accepts the following `opts`:
  * `:typed_encoder` - Module that implements `OpenAPIClient.Client.TypedEncoder` behaviour.
  Default value obtained through a call to `OpenAPIClient.Utils.get_config(conn, :typed_encoder, OpenAPIClient.Client.TypedEncoder)`
  * `:body_reader` - MFA to read `:request_body` from `OpenApiClient.State`. By default the `OpenAPIClient.State.read_body/2` is
  being called.

  """

  @behaviour Plug

  alias OpenAPIClient.Error

  @type option :: {:typed_encoder, module()} | {:body_reader, {module(), atom(), list()}}
  @type options :: [option()]

  @impl Plug
  @spec init(options()) :: options()
  def init(opts), do: opts

  @impl Plug
  @spec call(Plug.Conn.t(), options()) :: Plug.Conn.t()
  def call(conn, opts) do
    %OpenAPIClient.State{
      request_path: request_path,
      method: method,
      request_parameter_types: parameter_types,
      request_headers: headers,
      request_query_params: query_params,
      request_path_params: path_params
    } = OpenAPIClient.get_state(conn)

    typed_encoder =
      Keyword.get_lazy(opts, :typed_encoder, fn ->
        OpenAPIClient.Utils.get_config(
          conn,
          :typed_encoder,
          OpenAPIClient.Client.TypedEncoder
        )
      end)

    path_rest = [{request_path, method}]

    headers = Map.new(headers, fn {key, value} -> {{key, :header}, value} end)
    query_params = Map.new(query_params, fn {key, value} -> {{key, :query}, value} end)
    path_params = Map.new(path_params, fn {key, value} -> {{key, :path}, value} end)

    headers
    |> Map.merge(query_params)
    |> Map.merge(path_params)
    |> Enum.flat_map(fn {{name_atom, location}, value} ->
      parameter_types
      |> List.keyfind({name_atom, location}, 0)
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
      {mod, fun, args} = Keyword.get(opts, :body_reader, {OpenAPIClient.State, :read_body, []})

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
    end)
    |> Enum.reduce_while(conn, fn {path_prefix, type, value}, conn ->
      value
      |> typed_encoder.encode(type, [path_prefix | path_rest], typed_encoder)
      |> case do
        {:ok, encoded_value} ->
          conn_new =
            case path_prefix do
              {:request_body, _content_type} ->
                %OpenAPIClient.State{} = state = OpenAPIClient.get_state(conn)
                state_new = %OpenAPIClient.State{state | request_body: encoded_value}
                OpenAPIClient.set_state(conn, state_new)

              {:parameter, :path = location, name} ->
                parameter_types
                |> Enum.find_value(fn
                  {{name_atom, ^location}, {^name, _type, _default}} -> name_atom
                  {{name_atom, ^location}, {^name, _type}} -> name_atom
                  _ -> nil
                end)
                |> case do
                  nil ->
                    conn

                  name_atom ->
                    %Plug.Conn{request_path: request_path} = conn

                    request_path_new =
                      String.replace(request_path, "{#{name_atom}}", to_string(encoded_value))

                    %Plug.Conn{conn | request_path: request_path_new}
                end
                |> update_conn_map(:path_params, name, to_string(encoded_value))
                |> update_conn_map(:params, name, to_string(encoded_value))

              {:parameter, :query = _location, name} ->
                conn
                |> update_conn_map(:query_params, name, to_string(encoded_value))
                # |> then(fn %Plug.Conn{query_params: query_params} = conn ->
                #   %Plug.Conn{conn | query_string: Plug.Conn.Query.encode(query_params)}
                # end)
                |> update_conn_map(:params, name, to_string(encoded_value))

              {:parameter, :header = _location, name} ->
                Plug.Conn.put_req_header(conn, String.downcase(name), to_string(encoded_value))
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

  defp update_conn_map(conn, map_key, key, value),
    do:
      update_in(
        conn,
        [Access.key!(map_key)],
        fn
          %Plug.Conn.Unfetched{} -> %{key => value}
          map -> Map.put(map, key, value)
        end
      )
end

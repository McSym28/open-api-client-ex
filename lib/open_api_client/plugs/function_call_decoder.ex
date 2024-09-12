defmodule OpenAPIClient.Plugs.FunctionCallDecoder do
  @moduledoc """
  A plug for decoding the function call.
  """

  @behaviour Plug

  @impl Plug
  @spec init(opts :: Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @impl Plug
  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(conn, _opts) do
    %OpenAPIClient.State{
      request_parameter_types: parameter_types,
      request_parameter_args: parameter_args,
      request_headers: headers,
      request_path_params: path_params,
      request_query_params: query_params,
      request_custom_params: custom_params
    } = state = OpenAPIClient.get_state(conn)

    headers = Map.new(headers, fn {key, value} -> {{key, :header}, value} end)
    query_params = Map.new(query_params, fn {key, value} -> {{key, :query}, value} end)
    path_params = Map.new(path_params, fn {key, value} -> {{key, :path}, value} end)
    custom_params = Map.new(custom_params, fn {key, value} -> {{key, :custom}, value} end)

    parameters =
      headers
      |> Map.merge(query_params)
      |> Map.merge(path_params)
      |> Map.merge(custom_params)

    {function_args, function_opts} =
      parameter_types
      |> Enum.reduce(parameters, fn {{name_atom, location}, parameter_type}, parameters ->
        parameters
        |> Map.fetch({name_atom, location})
        |> case do
          {:ok, _value} ->
            parameters

          :error ->
            parameter_type
            |> case do
              {_name, _type, default} when is_function(default, 0) -> {:ok, default.()}
              {_name, _type, default} when not is_nil(default) -> {:ok, default}
              _ -> :error
            end
            |> case do
              {:ok, default} -> Map.put(parameters, {name_atom, location}, default)
              :error -> parameters
            end
        end
      end)
      |> Enum.map(fn {{name_atom, _location}, value} -> {name_atom, value} end)
      |> Keyword.split(parameter_args)

    parameter_args_indexed = Enum.with_index(parameter_args)

    function_args_sorted =
      parameter_args
      |> Enum.map(&{&1, nil})
      |> Keyword.merge(function_args)
      |> Enum.sort_by(fn {name_atom, _value} ->
        Keyword.fetch!(parameter_args_indexed, name_atom)
      end)

    function_args_new =
      case state do
        %OpenAPIClient.State{request_types: []} ->
          function_args_sorted

        %OpenAPIClient.State{request_body: request_body} ->
          function_args_sorted ++ [body: request_body]
      end

    state_new = %OpenAPIClient.State{
      state
      | function_args: function_args_new,
        function_opts: function_opts
    }

    OpenAPIClient.set_state(conn, state_new)
  end
end

defmodule OpenAPIClient.Plugs.FunctionCallEncoder do
  @moduledoc """
  A plug for encoding the function call.
  """

  @behaviour Plug

  @impl Plug
  @spec init(opts :: Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @impl Plug
  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(conn, _opts) do
    %OpenAPIClient.State{
      function_args: function_args,
      function_opts: function_opts,
      request_parameter_types: parameter_types
    } = state = OpenAPIClient.get_state(conn)

    {body, function_args} = Keyword.pop(function_args, :body)

    passed_parameters =
      function_opts
      |> Keyword.merge(function_args)
      |> Map.new()

    parameter_types
    |> Enum.reduce(%OpenAPIClient.State{state | request_body: body}, fn {{name_atom, location},
                                                                         parameter_type},
                                                                        state ->
      passed_parameters
      |> Map.fetch(name_atom)
      |> case do
        {:ok, value} ->
          {:ok, value}

        :error ->
          case parameter_type do
            {_name, _type, default} when is_function(default, 0) -> {:ok, default.()}
            {_name, _type, default} when not is_nil(default) -> {:ok, default}
            _ -> :error
          end
      end
      |> case do
        {:ok, value} ->
          case location do
            :path -> update_state_map(state, :request_path_params, name_atom, value)
            :query -> update_state_map(state, :request_query_params, name_atom, value)
            :header -> update_state_map(state, :request_headers, name_atom, value)
            :cookie -> update_state_map(state, :request_cookies, name_atom, value)
            :custom -> update_state_map(state, :request_custom_params, name_atom, value)
            _ -> state
          end

        :error ->
          state
      end
    end)
    |> then(&OpenAPIClient.set_state(conn, &1))
  end

  defp update_state_map(state, map_key, key, value),
    do: update_in(state, [Access.key!(map_key)], &Map.put(&1, key, value))
end

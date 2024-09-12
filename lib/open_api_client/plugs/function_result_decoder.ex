defmodule OpenAPIClient.Plugs.FunctionResultDecoder do
  @moduledoc """
  A plug for decoding the function call's result.
  """

  @behaviour Plug

  @impl Plug
  @spec init(opts :: Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @impl Plug
  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(conn, _opts) do
    %OpenAPIClient.State{response_body: response_body} = OpenAPIClient.get_state(conn)

    conn
    |> OpenAPIClient.State.get_response_type()
    |> case do
      {:ok, {response_status_code, _content_type, type}} ->
        is_success =
          case response_status_code do
            status_code when is_integer(status_code) ->
              status_code >= 200 and status_code < 300

            "2XX" ->
              true

            true ->
              true

            _else ->
              false
          end

        case {is_success, type} do
          {true, :null} ->
            :ok

          {true, _type} ->
            {:ok, response_body}

          {false, :null} ->
            :error

          {false, _type} ->
            {:error, response_body}
        end

      {:error, _} = error ->
        error
    end
    |> then(&OpenAPIClient.set_state_result(conn, &1))
  end
end

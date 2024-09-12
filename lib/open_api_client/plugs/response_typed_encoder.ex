defmodule OpenAPIClient.Plugs.ResponseTypedEncoder do
  @moduledoc """
  A plug for encoding `:response_body` using types provided by the `oapi_generator` library

  The response type is selected based on the `:status` and State's `:response_types`

  Accepts the following `opts`:
  * `:typed_encoder` - Module that implements `OpenAPIClient.TypedEncoder` behaviour. Default value obtained through a call to `OpenAPIClient.Utils.get_config(conn, :typed_encoder, OpenAPIClient.TypedEncoder)`

  """

  @behaviour Plug

  alias OpenAPIClient.Error

  @type option :: {:typed_encoder, module()}
  @type options :: [option()]

  @impl Plug
  @spec init(options()) :: options()
  def init(opts), do: opts

  @impl Plug
  @spec call(Plug.Conn.t(), options()) :: Plug.Conn.t()
  def call(%Plug.Conn{request_path: request_path} = conn, opts) do
    with %OpenAPIClient.State{method: method, response_body: body} = state when not is_nil(body) <-
           OpenAPIClient.get_state(conn),
         {:ok, {status_code, content_type, type}} when type != :null <-
           OpenAPIClient.State.get_response_type(conn) do
      typed_encoder =
        Keyword.get_lazy(opts, :typed_encoder, fn ->
          OpenAPIClient.Utils.get_config(
            conn,
            :typed_encoder,
            OpenAPIClient.TypedEncoder
          )
        end)

      case typed_encoder.encode(
             body,
             type,
             [
               {:response_body, status_code, content_type},
               {request_path, method}
             ],
             typed_encoder
           ) do
        {:ok, encoded_body} ->
          state_new = %OpenAPIClient.State{state | response_body: encoded_body}
          OpenAPIClient.set_state(conn, state_new)

        {:error, %Error{} = error} ->
          OpenAPIClient.set_state_result(
            conn,
            {:error, %Error{error | conn: conn, plug: __MODULE__}}
          )
      end
    else
      _ ->
        conn
    end
  end
end

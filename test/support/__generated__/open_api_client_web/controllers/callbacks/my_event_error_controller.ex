defmodule OpenAPIClientWeb.Callbacks.MyEventErrorController do
  use OpenAPIClientWeb, :controller

  plug(OpenAPIClient.Plugs.CallbackInitializer,
    implementation: {:mock, OpenAPIClient.CallbacksMock},
    behaviour: OpenAPIClient.Callbacks,
    function_name: :my_event_error
  )

  plug(OpenAPIClient.Plugs.RequestTypedDecoder)
  plug(OpenAPIClient.Plugs.FunctionCallDecoder)
  plug(OpenAPIClient.Plugs.FunctionCall)
  plug(OpenAPIClient.Plugs.FunctionResultEncoder)
  plug(OpenAPIClient.Plugs.ResponseTypedEncoder)
  plug(OpenAPIClient.Plugs.ResponseSerializers, serializers: [json: [json_encoder: Jason]])

  @spec my_event_error(conn :: Plug.Conn.t(), params :: Plug.Conn.params()) :: Plug.Conn.t()
  def my_event_error(conn, _params) do
    Plug.Conn.send_resp(conn)
  end
end

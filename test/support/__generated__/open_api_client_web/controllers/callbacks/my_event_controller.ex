defmodule OpenAPIClientWeb.Callbacks.MyEventController do
  use OpenAPIClientWeb, :controller

  plug(OpenAPIClient.Plugs.CallbackInitializer,
    implementation: OpenAPIClient.CallbacksMock,
    behaviour: OpenAPIClient.Callbacks,
    function_name: :my_event
  )

  plug(OpenAPIClient.Plugs.RequestTypedDecoder)
  plug(OpenAPIClient.Plugs.FunctionCallDecoder)
  plug(OpenAPIClient.Plugs.FunctionCall)
  plug(OpenAPIClient.Plugs.FunctionResultEncoder)
  plug(OpenAPIClient.Plugs.ResponseTypedEncoder)
  plug(OpenAPIClient.Plugs.ResponseSerializers, serializers: [json: [json_encoder: Jason]])

  def my_event(conn, _params) do
    Plug.Conn.send_resp(conn)
  end
end

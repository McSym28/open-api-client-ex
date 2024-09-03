defmodule OpenAPIClientWeb.Callbacks.MyEventController do
  use OpenAPIClientWeb, :controller

  plug(OpenAPIClientWeb.Plugs.Callback,
    implementation: OpenAPIClient.CallbacksMock,
    behaviour: OpenAPIClient.Callbacks,
    function_name: :my_event,
    profile: :test
  )

  def my_event(conn, _params) do
    response_status_code = OpenAPIClientWeb.Plugs.Callback.get_response_status_code(conn)
    response_body = OpenAPIClientWeb.Plugs.Callback.get_response_body(conn)
    Plug.Conn.send_resp(conn, response_status_code, response_body)
  end
end

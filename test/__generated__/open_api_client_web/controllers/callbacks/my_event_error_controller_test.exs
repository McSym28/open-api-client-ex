defmodule OpenAPIClientWeb.Callbacks.MyEventErrorControllerTest do
  use OpenAPIClientWeb.ConnCase

  import Mox

  @behaviour_module OpenAPIClient.CallbacksMock
  @client OpenAPIClientMock

  setup :verify_on_exit!

  describe "my_event_error/2" do
    test "[200] processes a request, decodes CallbackRequest from request's body and encodes CallbackResponse from response's body",
         %{conn: conn} do
      expect(@client, :callback, &OpenAPIClient.callback/1)

      expect(@behaviour_module, :my_event_error, fn body ->
        assert %OpenAPIClient.CallbackRequest{message: "Some event happened"} == body
        {:ok, %OpenAPIClient.CallbackResponse{acknowledged: true}}
      end)

      conn =
        conn
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> post("/__test__/callbacks/my_event_error?", %{"message" => "Some event happened"})

      assert ["application/json"] == Plug.Conn.get_resp_header(conn, "content-type")

      assert encoded_body = response(conn, 200)
      assert {:ok, encoded_body} == Jason.encode(%{"acknowledged" => true})
    end
  end
end

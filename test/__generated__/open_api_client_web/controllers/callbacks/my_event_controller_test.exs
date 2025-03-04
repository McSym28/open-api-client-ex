defmodule OpenAPIClientWeb.Callbacks.MyEventControllerTest do
  use OpenAPIClientWeb.ConnCase

  import Mox

  @behaviour_module OpenAPIClient.CallbacksMock
  @client OpenAPIClientMock

  setup :verify_on_exit!

  describe "my_event/2" do
    test "[200] processes a request, decodes CallbackRequest from request's body and encodes CallbackResponse from response's body",
         %{conn: conn} do
      expect(@client, :callback, &OpenAPIClient.callback/1)

      expect(@behaviour_module, :my_event, fn x_required_callback_query,
                                              x_required_callback_header,
                                              body,
                                              opts ->
        assert "required-callback-query" == x_required_callback_query
        assert "required_callback_header" == x_required_callback_header
        assert %OpenAPIClient.CallbackRequest{message: "Some event happened"} == body
        assert {:ok, "optional-callback-query"} == Keyword.fetch(opts, :x_optional_callback_query)

        assert {:ok, "optional_callback_header"} ==
                 Keyword.fetch(opts, :x_optional_callback_header)

        assert {:ok, 1} == Keyword.fetch(opts, :x_optional_callback_cookie)
        {:ok, %OpenAPIClient.CallbackResponse{acknowledged: true}}
      end)

      assert {:ok, body_encoded} = Jason.encode(%{"message" => "Some event happened"})

      conn =
        conn
        |> Plug.Conn.put_req_header("x-required-callback-header", "required_callback_header")
        |> Plug.Conn.put_req_header("x-optional-callback-header", "optional_callback_header")
        |> Plug.Conn.put_req_header("cookie", "X-Optional-Callback-Cookie=1")
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> post(
          "/__test__/callbacks/my_event?X-Optional-Callback-Query=optional-callback-query&X-Required-Callback-Query=required-callback-query",
          body_encoded
        )

      assert ["application/json"] == Plug.Conn.get_resp_header(conn, "content-type")

      assert encoded_body = response(conn, 200)
      assert {:ok, encoded_body} == Jason.encode(%{"acknowledged" => true})
    end
  end
end

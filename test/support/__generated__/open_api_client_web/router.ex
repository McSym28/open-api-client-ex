defmodule OpenAPIClientWeb.Router do
  use OpenAPIClientWeb, :router

  scope "/__test__", OpenAPIClientWeb do
    scope "/callbacks", Callbacks do
      scope "/my_event_error" do
        post("/", MyEventErrorController, :my_event_error)
      end

      scope "/my_event" do
        post("/", MyEventController, :my_event)
      end
    end
  end
end

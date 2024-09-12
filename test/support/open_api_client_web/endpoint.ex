defmodule OpenAPIClientWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :open_api_client_ex

  plug(Plug.Parsers,
    parsers: [:json],
    json_decoder: Phoenix.json_library()
  )

  plug(OpenAPIClientWeb.Router)
end

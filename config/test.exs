import Config

# Print only warnings and errors during test
config :logger, level: :warning

config :oapi_generator,
  default: [
    processor: OpenAPIClient.Generator.Processor,
    renderer: OpenAPIClient.Generator.Renderer,
    output: [
      base_module: OpenAPIClient,
      location: "test/support"
    ]
  ]

config :open_api_client_ex,
  json_library: Jason,
  default: [
    base_url: "https://example.com"
  ]

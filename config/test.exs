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
  client_pipeline: OpenAPIClient.TestClientPipeline,
  default: [
    base_url: "https://example.com",
    client_pipeline: {Application, :get_env, [:open_api_client_ex, :client_pipeline]}
  ]

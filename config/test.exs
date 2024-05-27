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
  "$base": [
    client_pipeline: OpenAPIClient.TestClientPipeline,
    httpoison: OpenAPIClient.HTTPoisonMock,
    decoders: [
      {"application/json", {Jason, :decode, []}}
    ],
    encoders: [
      {"application/json", {Jason, :encode, []}}
    ]
  ],
  default: [
    base_url: "https://example.com",
    test_location: "test/open_api_client"
  ]

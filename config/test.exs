import Config

# Print only warnings and errors during test
config :logger, level: :warning

config :oapi_generator,
  test: [
    processor: OpenAPIClient.Generator.Processor,
    renderer: OpenAPIClient.Generator.Renderer,
    output: [
      base_module: OpenAPIClient,
      location: "test/support",
      schema_subdirectory: "schemas"
    ]
  ]

config :open_api_client_ex,
  "$base": [
    client_pipeline: OpenAPIClient.BasicHTTPoisonPipeline,
    httpoison: OpenAPIClient.HTTPoisonMock,
    decoders: [
      {"application/json", {Jason, :decode, []}}
    ],
    encoders: [
      {"application/json", {Jason, :encode, []}}
    ]
  ],
  test: [
    base_url: "https://example.com",
    test_location: "test/open_api_client",
    schemas: [
      {{"TestSchema", :t},
       [
         fields: [
           {"Enum", [enum: [options: [{"ENUM_1", [value: :enum1]}, {"ENUM_2", [value: :enum2]}]]]}
         ]
       ]}
    ]
  ]

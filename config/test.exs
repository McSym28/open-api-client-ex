import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :open_api_client_ex, OpenAPIClientWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "n+/5UaboabFOImD8Npfjubvr120z8ijGokr7osJnSIxP7f5gUp6cwkILDkbR84Fr",
  server: false

# Initialize plugs at runtime for faster test compilation
# Use Jason for JSON parsing in Phoenix
config :phoenix,
  plug_init_mode: :runtime,
  json_library: Jason

# Print only warnings and errors during test
config :logger, level: :warning

config :oapi_generator,
  test: [
    processor: OpenAPIClient.Generator.Processor,
    renderer: OpenAPIClient.Generator.Renderer,
    output: [
      base_module: OpenAPIClient,
      location: "test/support/__generated__/open_api_client",
      schema_subdirectory: "schemas"
    ],
    naming: [
      rename: [
        {~r/^TestRequestSchema([^\.].+)$/, "TestRequestSchema.\\1"}
      ]
    ]
  ]

config :open_api_client_ex,
  "$base": [
    httpoison: OpenAPIClient.HTTPoisonMock,
    client: OpenAPIClient.ClientMock
  ],
  test: [
    base_url: "https://example.com",
    test_location: "test/__generated__/open_api_client",
    operations: [
      {:*, [params: []]},
      {{[:*], [:delete]}, []},
      {{["/non_existing", ~r/non-matching-regex/], [:*]}, []},
      {{"/test/{path-param}", :get},
       [
         params: [
           {{"X-Required-Header", :header}, [name: "required_header"]},
           {{"X-Optional-Header", :header},
            [
              name: "optional_header",
              default: {Application, :get_env, [:open_api_client_ex, :required_header]},
              example: "some_optional_header"
            ]},
           {{"X-Date-Header-With-Default", :header},
            [
              name: "date_header_with_default",
              default: {:const, ~D[2024-01-23]}
            ]},
           {{"required_new_param", :custom},
            [
              spec: %{
                "schema" => %{"type" => "string"},
                "description" => "Required additional parameter",
                "required" => true
              }
            ]},
           {{"optional_new_param", :custom},
            [
              spec: %{
                "schema" => %{"type" => "string"},
                "description" => "Optional additional parameter"
              }
            ]},
           {{"optional_header_new_param", :custom},
            [
              spec: %{
                "schema" => %{"type" => "string"},
                "description" => "Optional additional header parameter",
                "in" => "header"
              }
            ]},
           {{"optional_new_param_with_default", :custom},
            [
              spec: %{
                "schema" => %{"type" => "string"},
                "description" => "Optional additional parameter"
              },
              default: {:const, "new_param_value"},
              example: "new_param_value"
            ]}
         ]
       ]},
      {{"/test", :post},
       [
         params: [
           {{"X-String-Header", :header}, [name: "string_header"]},
           {:*, [enum: [strict: true]]}
         ]
       ]}
    ],
    schemas: [
      {:*, [fields: []]},
      {{[:*], [:non_existing_type, "non_existing_type"]}, []},
      {{[NonExisting, "NonExisting", ~r/non-matching-regex/], [:*]}, []},
      {{"TestSchema", :t},
       [
         fields: [
           {"Enum", [enum: [options: [{"ENUM_1", [value: :enum1]}, {"ENUM_2", [value: :enum2]}]]]}
         ]
       ]},
      {{"TestRequestSchema", :t},
       [
         fields: [
           {"StrictEnum", [enum: [strict: true], example: "STRICT_ENUM_2"]},
           {:*, [enum: [strict: true]]}
         ]
       ]}
    ]
  ]

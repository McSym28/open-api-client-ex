import Config

# Print only warnings and errors during test
config :logger, level: :warning

config :oapi_generator,
  test: [
    processor: OpenAPIClient.Generator.Processor,
    renderer: OpenAPIClient.Generator.Renderer,
    output: [
      base_module: OpenAPIClient,
      location: "test/support/__generated__",
      schema_subdirectory: "schemas"
    ],
    naming: [
      rename: [
        {~r/^TestRequestSchema([^\.].+)$/, "TestRequestSchema.\\1"}
      ]
    ]
  ]

config :open_api_client_ex,
  test: [
    base_url: "https://example.com",
    test_location: "test/open_api_client/__generated__",
    operations: [
      {:*, [params: []]},
      {{[:*], [:delete]}, []},
      {{["/non_existing", ~r/non-matching-regex/], [:*]}, []},
      {{"/test", :get},
       [
         params: [
           {{"X-Required-Header", :header}, [name: "required_header"]},
           {{"X-Optional-Header", :header},
            [
              name: "optional_header",
              default: {Application, :get_env, [:open_api_client_ex, :required_header]},
              example: "some_optional_header"
            ]}
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
           {"StrictEnum", [enum: [strict: true], example: "STRICT_ENUM_2"]}
         ]
       ]}
    ]
  ]

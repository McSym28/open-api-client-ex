defmodule OpenAPIClient.Generator.Field do
  @type t :: %__MODULE__{
          field: OpenAPI.Processor.Schema.Field.t() | nil,
          old_name: String.t(),
          enforce: boolean(),
          enum_options: [OpenAPIClient.Schema.enum_option()],
          enum_strict: boolean(),
          enum_type: OpenAPI.Processor.Type.t(),
          extra: boolean(),
          examples: list()
        }

  @enforce_keys [:old_name]
  defstruct field: nil,
            old_name: nil,
            enforce: false,
            enum_options: [],
            enum_strict: false,
            enum_type: nil,
            extra: false,
            examples: []
end

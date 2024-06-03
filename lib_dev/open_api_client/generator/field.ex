defmodule OpenAPIClient.Generator.Field do
  @type t :: %__MODULE__{
          field: OpenAPI.Processor.Schema.Field.t() | nil,
          old_name: String.t(),
          enforce: boolean(),
          enum_options: [OpenAPIClient.Schema.enum_option()],
          enum_strict: boolean(),
          type: OpenAPI.Processor.Type.t(),
          extra: boolean(),
          examples: list()
        }

  @enforce_keys [:old_name, :type]
  defstruct field: nil,
            old_name: nil,
            enforce: false,
            enum_options: [],
            enum_strict: false,
            type: nil,
            extra: false,
            examples: []
end

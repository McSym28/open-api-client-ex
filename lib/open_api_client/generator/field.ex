if Mix.env() in [:dev, :test] do
  defmodule OpenAPIClient.Generator.Field do
    alias OpenAPIClient.Generator.SchemaType

    @type t :: %__MODULE__{
            field: OpenAPI.Processor.Schema.Field.t() | nil,
            old_name: String.t(),
            enforce: boolean(),
            extra: boolean(),
            schema_type: SchemaType.t() | nil
          }

    @enforce_keys [:old_name]
    defstruct field: nil,
              old_name: nil,
              enforce: false,
              extra: false,
              schema_type: nil
  end
end

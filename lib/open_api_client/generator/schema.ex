if Mix.env() in [:dev, :test] do
  defmodule OpenAPIClient.Generator.Schema do
    @type t :: %__MODULE__{
            fields: [OpenAPIClient.Generator.Field.t()],
            schema_fields: OpenAPIClient.Schema.schema_type(),
            schema: OpenAPI.Processor.Schema.t()
          }

    @enforce_keys [:fields]
    defstruct fields: [], schema_fields: [], schema: nil
  end
end

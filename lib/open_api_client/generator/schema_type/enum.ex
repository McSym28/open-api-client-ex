if Mix.env() in [:dev, :test] do
  defmodule OpenAPIClient.Generator.SchemaType.Enum do
    @type t :: %__MODULE__{
            options: [OpenAPIClient.Schema.enum_option()],
            strict: boolean(),
            type: OpenAPI.Processor.Type.t()
          }

    defstruct options: [],
              strict: false,
              type: nil
  end
end

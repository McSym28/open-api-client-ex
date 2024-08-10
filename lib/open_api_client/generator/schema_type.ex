if Mix.env() in [:dev, :test] do
  defmodule OpenAPIClient.Generator.SchemaType do
    @type t :: %__MODULE__{
            enum: OpenAPIClient.Generator.SchemaType.t(),
            examples: list(),
            default: term()
          }

    defstruct enum: nil,
              examples: [],
              default: nil
  end
end

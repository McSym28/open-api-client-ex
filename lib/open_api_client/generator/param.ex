if Mix.env() in [:dev, :test] do
  defmodule OpenAPIClient.Generator.Param do
    alias OpenAPIClient.Generator.SchemaType

    @type t :: %__MODULE__{
            param: OpenAPI.Processor.Operation.Param.t(),
            old_name: String.t(),
            config: OpenAPIClient.Generator.Utils.operation_param_config(),
            static: boolean(),
            schema_type: SchemaType.t() | nil
          }

    @enforce_keys [:param, :old_name]
    defstruct param: nil, old_name: nil, config: [], static: false, schema_type: nil
  end
end

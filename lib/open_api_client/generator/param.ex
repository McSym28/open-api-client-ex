if Mix.env() in [:dev, :test] do
  defmodule OpenAPIClient.Generator.Param do
    @type t :: %__MODULE__{
            param: OpenAPI.Processor.Operation.Param.t(),
            old_name: String.t(),
            default: term(),
            config: OpenAPIClient.Generator.Utils.operation_param_config(),
            static: boolean(),
            examples: list()
          }

    @enforce_keys [:param, :old_name]
    defstruct param: nil, old_name: nil, default: nil, config: [], static: false, examples: []
  end
end

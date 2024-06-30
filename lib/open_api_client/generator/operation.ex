if Mix.env() in [:dev, :test] do
  defmodule OpenAPIClient.Generator.Operation do
    @type t :: %__MODULE__{
            config: OpenAPIClient.Generator.Utils.operation_config(),
            spec: OpenAPI.Spec.Path.Operation.t(),
            params: [OpenAPIClient.Generator.Param.t()],
            param_renamings: %{String.t() => String.t()}
          }

    @enforce_keys [:config, :spec, :params, :param_renamings]
    defstruct config: [], spec: nil, params: [], param_renamings: %{}
  end
end

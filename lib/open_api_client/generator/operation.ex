if Mix.env() in [:dev, :test] do
  defmodule OpenAPIClient.Generator.Operation do
    @type t :: %__MODULE__{
            config: OpenAPIClient.Generator.Utils.operation_config(),
            spec: OpenAPI.Spec.Path.Operation.t(),
            params: [OpenAPIClient.Generator.Param.t()],
            param_renamings: %{
              {String.t(), OpenAPI.Processor.Operation.Param.location()} => String.t()
            },
            type: :operation | :callback | :webhook,
            normalized_request_path: String.t() | URI.t(),
            non_operation_parameters: map()
          }

    @enforce_keys [
      :config,
      :spec,
      :params,
      :param_renamings,
      :type,
      :normalized_request_path,
      :non_operation_parameters
    ]
    defstruct [
      :normalized_request_path,
      config: [],
      spec: nil,
      params: [],
      param_renamings: %{},
      type: :operation,
      non_operation_parameters: %{}
    ]
  end
end

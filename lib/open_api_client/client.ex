defmodule OpenAPIClient.Client do
  alias OpenAPIClient.Client.Operation
  alias OpenAPIClient.Utils

  @type step :: module() | {module(), term()} | {module(), atom(), [term()]}
  @type pipeline :: step() | [step(), ...]

  @spec perform(Operation.t(), pipeline()) :: {:ok, term()} | {:error, term()}
  def perform(operation, pipeline) do
    normalized_pipeline = normalize_pipeline(pipeline)

    operation
    |> put_request_content_type_header()
    |> Pluggable.run(normalized_pipeline)
    |> case do
      %Operation{result: result} when not is_nil(result) -> result
      %Operation{response_body: response_body} -> {:ok, response_body}
    end
  end

  defp normalize_pipeline(pipeline) when is_list(pipeline) do
    Enum.map(pipeline, &normalize_step/1)
  end

  defp normalize_pipeline(pipeline) do
    normalize_pipeline([pipeline])
  end

  defp normalize_step(module) when is_atom(module) do
    normalize_step({module, []})
  end

  defp normalize_step({module, function_or_opts}) when is_atom(module) do
    true = Utils.is_module?(module)

    if Utils.does_implement_behaviour?(module, Pluggable) do
      {module, function_or_opts}
    else
      normalize_step({module, function_or_opts, []})
    end
  end

  defp normalize_step({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args) do
    true = Utils.is_module?(module) and function_exported?(module, function, length(args) + 1)
    fn operation -> apply(module, function, [operation | args]) end
  end

  defp put_request_content_type_header(%Operation{request_types: [type | _]} = operation) do
    {content_type, _body_type} = type
    Operation.put_request_header(operation, "Content-Type", content_type)
  end

  defp put_request_content_type_header(operation), do: operation
end

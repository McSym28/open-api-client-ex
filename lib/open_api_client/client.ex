defmodule OpenAPIClient.Client do
  alias OpenAPIClient.Client.Operation
  alias OpenAPIClient.Utils

  @type step :: module() | {module(), term()} | {module(), atom(), [term()]}
  @type pipeline :: step() | [step(), ...]

  @spec perform(Operation.t(), pipeline()) :: {:ok, term()} | {:error, term()}
  def perform(operation, pipeline) do
    pipeline
    |> normalize_pipeline()
    |> then(&Pluggable.run(operation, &1))
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
end

defmodule OpenAPIClient.Client do
  alias OpenAPIClient.Client.Operation
  alias OpenAPIClient.Utils

  @type step :: module() | {module(), term()} | {module(), atom(), [term()]}
  @type pipeline :: step() | nonempty_list(step())

  @spec perform(Operation.t(), pipeline()) :: :ok | {:ok, term()} | :error | {:error, term()}
  def perform(operation, pipeline) do
    normalized_pipeline = normalize_pipeline(pipeline)

    operation
    |> put_request_content_type_header()
    |> Pluggable.run(normalized_pipeline)
    |> case do
      %Operation{result: result} when not is_nil(result) ->
        result

      %Operation{response_body: response_body} = operation ->
        case Operation.get_response_type(operation) do
          {:ok, {response_status_code, type}} ->
            is_success =
              case response_status_code do
                status_code when is_integer(status_code) ->
                  status_code >= 200 and status_code < 300

                "2XX" ->
                  true

                :default ->
                  true

                _else ->
                  false
              end

            case {is_success, type} do
              {true, :null} ->
                :ok

              {true, _type} ->
                {:ok, response_body}

              {false, :null} ->
                :error

              {false, _type} ->
                {:error, response_body}
            end

          {:error, _} = error ->
            error
        end
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

  defp put_request_content_type_header(%Operation{request_types: request_types} = operation) do
    request_types
    |> Enum.reduce_while(nil, fn
      {"application/json", _type} = body, _acc_type -> {:halt, body}
      body, nil -> {:cont, body}
      _body, acc_type -> {:cont, acc_type}
    end)
    |> case do
      {content_type, _body_type} ->
        Operation.put_request_header(operation, "Content-Type", content_type)

      nil ->
        operation
    end
  end
end

defmodule OpenAPIClient.Client do
  alias OpenAPIClient.Client.Operation
  alias OpenAPIClient.Utils

  @type step :: module() | {module(), term()} | {module(), atom(), [term()]}
  @type pipeline :: step() | nonempty_list(step())

  @spec perform(Operation.t(), pipeline() | nil) ::
          :ok | {:ok, term()} | :error | {:error, term()}
  def perform(%Operation{request_headers: request_headers} = operation, pipeline) do
    normalized_pipeline =
      normalize_pipeline(pipeline || OpenAPIClient.Utils.get_config(operation, :client_pipeline))

    request_headers_new =
      Map.new(request_headers, fn {key, value} -> {String.downcase(key), value} end)

    %{operation | request_headers: request_headers_new}
    |> put_request_content_type_header()
    |> Pluggable.run(normalized_pipeline)
    |> case do
      %Operation{result: result} when not is_nil(result) ->
        result

      %Operation{response_body: response_body} = operation ->
        case Operation.get_response_type(operation) do
          {:ok, {response_status_code, _content_type, type}} ->
            is_success =
              case response_status_code do
                status_code when is_integer(status_code) ->
                  status_code >= 200 and status_code < 300

                "2XX" ->
                  true

                :default ->
                  !Utils.get_config(operation, :default_status_code_as_failure)

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

  defp put_request_content_type_header(%Operation{request_body: nil} = operation), do: operation

  defp put_request_content_type_header(operation) do
    case Operation.get_request_header(operation, "Content-Type") do
      {:ok, _content_type} -> operation
      :error -> put_most_suitable_request_content_type_header(operation)
    end
  end

  defp put_most_suitable_request_content_type_header(
         %Operation{request_body: request_body, request_types: request_types} = operation
       ) do
    encoders = Utils.get_config(operation, :encoders, [])

    request_body_struct =
      case request_body do
        %struct{} -> struct
        _ -> nil
      end

    request_types
    |> Enum.reduce_while({nil, nil}, fn {content_type, schema}, acc ->
      has_encoder = List.keymember?(encoders, content_type, 0)

      is_schema_struct =
        case schema do
          {^request_body_struct, schema_type} when is_atom(schema_type) -> true
          _ -> false
        end

      case {is_schema_struct, has_encoder, acc} do
        {true, true, _} ->
          {:halt, {:exact, content_type}}

        {true, false, {tag, _}} when tag in [:first, :with_encoder] ->
          {:cont, {:schema_struct, content_type}}

        {false, true, {tag, _}} when tag in [:first] ->
          {:cont, {:with_encoder, content_type}}

        {false, false, {nil, _}} ->
          {:cont, {:first, content_type}}

        {_, _, acc} ->
          {:cont, acc}
      end
    end)
    |> case do
      {nil, _} ->
        operation

      {_tag, content_type} ->
        Operation.put_request_header(operation, "Content-Type", content_type)
    end
  end
end

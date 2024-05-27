defmodule OpenAPIClient.Client.Steps.RequestBodyContentTypeEncoder do
  @moduledoc """
  `Pluggable` step implementation for encoding `Operation.request_body` based on the `"Content-Type"` header
  """

  @behaviour Pluggable

  alias OpenAPIClient.Client.{Error, Operation}

  @type options :: []

  @impl true
  @spec init(options()) :: options()
  def init(opts), do: opts

  @impl true
  @spec call(Operation.t(), options()) :: Operation.t()
  def call(%Operation{request_body: nil} = operation, _opts), do: operation

  def call(%Operation{request_body: body} = operation, _opts) do
    case Operation.get_request_header(operation, "Content-Type") do
      {:ok, content_type} ->
        operation
        |> OpenAPIClient.Utils.get_config(:encoders, [])
        |> List.keyfind(content_type, 0)
        |> case do
          {_, {module, function, args}}
          when is_atom(module) and is_atom(function) and is_list(args) ->
            case apply(module, function, List.insert_at(args, 0, body)) do
              {:ok, encoded_body} ->
                %Operation{operation | request_body: encoded_body}

              {:error, error} ->
                Operation.set_result(
                  operation,
                  {:error,
                   Error.new(
                     message:
                       "Error while encoding request body using encoder for \"Content-Type\" #{inspect(content_type)}",
                     operation: operation,
                     source: error,
                     reason: :request_body_content_type_encode_failed,
                     step: __MODULE__
                   )}
                )
            end

          _ ->
            Operation.set_result(
              operation,
              {:error,
               Error.new(
                 message: "Encoder not configured for \"Content-Type\" #{inspect(content_type)}",
                 operation: operation,
                 reason: :encoder_not_configured,
                 step: __MODULE__
               )}
            )
        end

      _ ->
        operation
    end
  end
end

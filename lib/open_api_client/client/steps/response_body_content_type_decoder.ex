defmodule OpenAPIClient.Client.Steps.ResponseBodyContentTypeDecoder do
  @moduledoc """
  `Pluggable` step implementation for decoding `Operation.response_body` based on the `"Content-Type"` header
  """

  @behaviour Pluggable

  alias OpenAPIClient.Client.{Error, Operation}

  @type options :: []

  @impl true
  @spec init(options()) :: options()
  def init(opts), do: opts

  @impl true
  @spec call(Operation.t(), options()) :: Operation.t()
  def call(%Operation{response_body: nil} = operation, _opts), do: operation

  def call(%Operation{response_body: body} = operation, _opts) do
    case Operation.get_response_header(operation, "Content-Type") do
      {:ok, content_type} ->
        operation
        |> OpenAPIClient.Utils.get_config(:decoders, [])
        |> List.keyfind(content_type, 0)
        |> case do
          {_, {module, function, args}}
          when is_atom(module) and is_atom(function) and is_list(args) ->
            case apply(module, function, List.insert_at(args, 0, body)) do
              {:ok, decoded_body} ->
                %Operation{operation | response_body: decoded_body}

              {:error, error} ->
                Operation.set_result(
                  operation,
                  {:error,
                   Error.new(
                     message:
                       "Error while decoding request body using decoder for \"Content-Type\" #{inspect(content_type)}",
                     operation: operation,
                     source: error,
                     reason: :response_body_content_type_decode_failed,
                     step: __MODULE__
                   )}
                )
            end

          _ ->
            Operation.set_result(
              operation,
              {:error,
               Error.new(
                 message: "Decoder not configured for \"Content-Type\" #{inspect(content_type)}",
                 operation: operation,
                 reason: :decoder_not_configured,
                 step: __MODULE__
               )}
            )
        end

      _ ->
        operation
    end
  end
end

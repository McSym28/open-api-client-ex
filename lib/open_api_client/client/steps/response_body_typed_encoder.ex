defmodule OpenAPIClient.Client.Steps.ResponseBodyTypedEncoder do
  @moduledoc """
  `Pluggable` step implementation for encoding `Operation.response_body` using types provided by the `oapi_generator` library

  The response type is selected based on the `Operation.response_status_code` and `Operation.response_types`

  Accepts the following `opts`:
  * `:typed_encoder` - Module that implements `OpenAPIClient.Client.TypedEncoder` behaviour. Default value obtained through a call to `OpenAPIClient.Utils.get_config(operation, :typed_encoder, OpenAPIClient.Client.TypedEncoder)`

  """

  @behaviour Pluggable

  alias OpenAPIClient.Client.{Error, Operation}

  @type option :: [{:typed_encoder, module()}]
  @type options :: [option()]

  @impl Pluggable
  @spec init(options()) :: options()
  def init(opts), do: opts

  @impl Pluggable
  @spec call(Operation.t(), options()) :: Operation.t()
  def call(%Operation{response_body: nil} = operation, _opts), do: operation

  def call(%Operation{response_body: body} = operation, opts) do
    typed_encoder =
      Keyword.get_lazy(opts, :typed_encoder, fn ->
        OpenAPIClient.Utils.get_config(
          operation,
          :typed_encoder,
          OpenAPIClient.Client.TypedEncoder
        )
      end)

    case Operation.get_response_type(operation) do
      {:ok, {status_code, content_type, type}} when type != :null ->
        case typed_encoder.encode(
               body,
               type,
               [
                 {:response_body, status_code, content_type},
                 {operation.request_path, operation.request_method}
               ],
               typed_encoder
             ) do
          {:ok, encoded_body} ->
            %Operation{operation | response_body: encoded_body}

          {:error, %Error{} = error} ->
            Operation.set_result(
              operation,
              {:error, %Error{error | operation: operation, step: __MODULE__}}
            )
        end

      _ ->
        operation
    end
  end
end

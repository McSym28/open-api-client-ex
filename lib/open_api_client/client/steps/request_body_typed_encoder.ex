defmodule OpenAPIClient.Client.Steps.RequestBodyTypedEncoder do
  @moduledoc """
  `Pluggable` step implementation for encoding `Operation.request_body` using types provided by the `oapi_generator` library

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
  def call(%Operation{request_body: nil} = operation, _opts), do: operation

  def call(%Operation{request_body: request_body} = operation, opts) do
    typed_encoder =
      Keyword.get_lazy(opts, :typed_encoder, fn ->
        OpenAPIClient.Utils.get_config(
          operation,
          :typed_encoder,
          OpenAPIClient.Client.TypedEncoder
        )
      end)

    {content_type, type} = get_type(operation)

    case typed_encoder.encode(
           request_body,
           type,
           [{:request_body, content_type}, {operation.request_url, operation.request_method}],
           typed_encoder
         ) do
      {:ok, encoded_body} ->
        %Operation{operation | request_body: encoded_body}

      {:error, %Error{} = error} ->
        Operation.set_result(
          operation,
          {:error, %Error{error | operation: operation, step: __MODULE__}}
        )
    end
  end

  defp get_type(%Operation{request_types: types} = operation) do
    case Operation.get_request_header(operation, "Content-Type") do
      {:ok, content_type} -> List.keyfind(types, content_type, 0, {content_type, :unknown})
      :error -> {nil, :unknown}
    end
  end
end

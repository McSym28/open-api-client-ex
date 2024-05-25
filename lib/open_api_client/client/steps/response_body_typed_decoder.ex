defmodule OpenAPIClient.Client.Steps.ResponseBodyTypedDecoder do
  @moduledoc """
  `Pluggable` step implementation for decoding `Operation.response_body` using types provided by the `oapi_generator` library

  The response type is selected based on the `Operation.response_status_code` and `Operation.response_types`

  Accepts the following `opts`:
  * `:typed_decoder` - Module that implements `OpenAPIClient.Client.TypedDecoder` behaviour. Default value obtained through a call to `Application.get_env(:open_api_client_ex, :typed_encoder, OpenAPIClient.Client.TypedDecoder)`

  """

  @behaviour Pluggable

  alias OpenAPIClient.Client.{Error, Operation, TypedDecoder}

  @type option :: [{:typed_decoder, module()}]
  @type options :: [option()]

  @impl true
  @spec init(options()) :: options()
  def init(opts), do: opts

  @impl true
  @spec call(Operation.t(), options()) :: Operation.t()
  def call(%Operation{response_body: nil} = operation, _opts), do: operation

  def call(%Operation{response_body: body} = operation, opts) do
    typed_decoder =
      Keyword.get_lazy(opts, :typed_decoder, fn ->
        Application.get_env(:open_api_client_ex, :typed_decoder, TypedDecoder)
      end)

    case Operation.get_response_type(operation) do
      {:ok, {_, type}} when type != :null ->
        case typed_decoder.decode(body, type) do
          {:ok, decoded_body} ->
            %Operation{operation | response_body: decoded_body}

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

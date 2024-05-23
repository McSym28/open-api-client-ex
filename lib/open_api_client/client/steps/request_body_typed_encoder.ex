defmodule OpenAPIClient.Client.Steps.RequestBodyTypedEncoder do
  @moduledoc """
  `Pluggable` step implementation for encoding `Operation.request_body` using types provided by the `oapi_generator` library

  Accepts the following `opts`:
  * `:typed_encoder` - Module that implements `OpenAPIClient.Client.TypedEncoder` behaviour. Default value obtained through a call to `Application.get_env(:open_api_client_ex, :typed_encoder, OpenAPIClient.Client.TypedEncoder)`

  """

  @behaviour Pluggable

  alias OpenAPIClient.Client.{Error, Operation, TypedEncoder}

  @type option :: [{:typed_encoder, module()}]
  @type options :: [option()]

  @impl true
  @spec init(options()) :: options()
  def init(opts), do: opts

  @impl true
  @spec call(Operation.t(), options()) :: Operation.t()
  def call(%Operation{request_body: nil} = operation, _opts), do: operation

  def call(%Operation{request_body: request_body} = operation, opts) do
    typed_encoder =
      Keyword.get_lazy(opts, :typed_encoder, fn ->
        Application.get_env(:open_api_client_ex, :typed_encoder, TypedEncoder)
      end)

    case typed_encoder.encode(request_body) do
      {:ok, encoded_body} ->
        %Operation{operation | request_body: encoded_body}

      {:error, %Error{} = error} ->
        Operation.set_result(
          operation,
          {:error, %Error{error | operation: operation, step: __MODULE__}}
        )
    end
  end
end

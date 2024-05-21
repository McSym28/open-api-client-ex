defmodule OpenAPIClient.Client.Steps.RequestBodyTypedEncoder do
  @moduledoc """
  `Pluggable` step implementation for encoding `Operation.request_body` using types provided by the `oapi_generator` library
  """

  @behaviour Pluggable

  alias OpenAPIClient.Client.Operation
  alias OpenAPIClient.Client.TypedEncoder

  @type options :: []

  @impl true
  @spec init(options()) :: options()
  def init(opts), do: opts

  @impl true
  @spec call(Operation.t(), options()) :: Operation.t()
  def call(%Operation{request_body: nil} = operation, _opts), do: operation

  def call(%Operation{request_body: request_body} = operation, _opts) do
    case TypedEncoder.encode(request_body) do
      {:ok, encoded_body} ->
        %Operation{operation | request_body: encoded_body}

      {:error, message} ->
        %Operation{operation | result: {:error, {:request_body_typed_encoder, message}}}
        |> Pluggable.Token.halt()
    end
  end
end

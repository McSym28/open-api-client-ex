defmodule OpenAPIClient.Client.Steps.RequestBodyTypedEncoder do
  @behaviour Pluggable

  alias OpenAPIClient.Client.Operation
  alias OpenAPIClient.Client.TypedEncoder

  @impl true
  def init(opts), do: opts

  @impl true
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

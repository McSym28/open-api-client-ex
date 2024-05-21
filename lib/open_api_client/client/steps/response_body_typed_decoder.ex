defmodule OpenAPIClient.Client.Steps.ResponseBodyTypedDecoder do
  @behaviour Pluggable

  alias OpenAPIClient.Client.Operation
  alias OpenAPIClient.Client.TypedDecoder

  @impl true
  def init(opts) do
    opts
  end

  @impl true
  def call(%Operation{response_type: nil} = operation, _opts), do: operation

  def call(%Operation{response_body: body, response_type: response_type} = operation, _opts) do
    case TypedDecoder.decode(body, response_type) do
      {:ok, decoded_body} ->
        %Operation{operation | response_body: decoded_body}

      {:error, message} ->
        %Operation{operation | result: {:error, {:response_body_typed_decoder, message}}}
        |> Pluggable.Token.halt()
    end
  end
end

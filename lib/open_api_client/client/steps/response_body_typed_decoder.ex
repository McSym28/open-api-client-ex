defmodule OpenAPIClient.Client.Steps.ResponseBodyTypedDecoder do
  @behaviour Pluggable

  alias OpenAPIClient.Client.Operation
  alias OpenAPIClient.Client.TypedDecoder

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Operation{response_body: nil} = operation, _opts), do: operation

  def call(%Operation{response_body: body} = operation, _opts) do
    response_type = get_response_type(operation)

    case TypedDecoder.decode(body, response_type) do
      {:ok, decoded_body} ->
        %Operation{operation | response_body: decoded_body}

      {:error, message} ->
        %Operation{operation | result: {:error, {:response_body_typed_decoder, message}}}
        |> Pluggable.Token.halt()
    end
  end

  defp get_response_type(%Operation{response_types: types, response_status_code: status_code}) do
    case List.keyfind(types, status_code, 0) do
      {_, type} -> type
      _ -> :unknown
    end
  end
end

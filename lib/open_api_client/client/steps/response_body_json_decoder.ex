defmodule OpenAPIClient.Client.Steps.RequestBodyJSONDecoder do
  @behaviour Pluggable

  alias OpenAPIClient.Client.Operation

  @impl true
  def init(opts) do
    opts
  end

  @impl true
  def call(%Operation{response_body: nil} = operation, _opts), do: operation

  def call(%Operation{response_body: body} = operation, opts) do
    case Operation.get_request_header(operation, "Content-Type") do
      {:ok, "application/json"} ->
        json_library =
          Keyword.get_lazy(opts, :json_library, fn ->
            Application.get_env(:open_api_client_ex, :json_library)
          end)

        if json_library do
          case json_library.decode(body) do
            {:ok, decoded_body} ->
              %Operation{operation | response_body: decoded_body}

            {:error, message} ->
              %Operation{operation | result: {:error, {:response_body_json_decoder, message}}}
              |> Pluggable.Token.halt()
          end
        else
          %Operation{
            operation
            | result: {:error, {:response_body_json_decoder, :json_library_not_set}}
          }
          |> Pluggable.Token.halt()
        end

      _ ->
        operation
    end
  end
end

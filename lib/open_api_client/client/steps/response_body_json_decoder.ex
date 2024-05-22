defmodule OpenAPIClient.Client.Steps.ResponseBodyJSONDecoder do
  @moduledoc """
  `Pluggable` step implementation for JSON-decoding `Operation.response_body`

  Decoding is performed only when response's `"Content-Type"` header is equal to `"application/json"`.

  Accepts the following `opts`:
  * `:json_library` - JSON library module. Default value obtained through a call to `Application.get_env(:open_api_client_ex, :json_library)`

  """

  @behaviour Pluggable

  alias OpenAPIClient.Client.Operation

  @type option :: {:json_library, module()}
  @type options :: [option()]

  @impl true
  @spec init(options()) :: options()
  def init(opts), do: opts

  @impl true
  @spec call(Operation.t(), options()) :: Operation.t()
  def call(%Operation{response_body: nil} = operation, _opts), do: operation

  def call(%Operation{response_body: body} = operation, opts) do
    case Operation.get_response_header(operation, "Content-Type") do
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

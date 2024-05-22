defmodule OpenAPIClient.Client.Steps.RequestBodyJSONEncoder do
  @moduledoc """
  `Pluggable` step implementation for JSON-encoding `Operation.request_body`

  Encoding is performed only when request's `"Content-Type"` header is equal to `"application/json"`.

  Accepts the following `opts`:
  * `:json_library` - JSON library module. Default value obtained through a call to `Application.get_env(:open_api_client_ex, :json_library)`

  """

  @behaviour Pluggable

  alias OpenAPIClient.Client.{Error, Operation}

  @type option :: {:json_library, module()}
  @type options :: [option()]

  @impl true
  @spec init(options()) :: options()
  def init(opts), do: opts

  @impl true
  @spec call(Operation.t(), options()) :: Operation.t()
  def call(%Operation{request_body: nil} = operation, _opts), do: operation

  def call(%Operation{request_body: body} = operation, opts) do
    case Operation.get_request_header(operation, "Content-Type") do
      {:ok, "application/json"} ->
        json_library =
          Keyword.get_lazy(opts, :json_library, fn ->
            Application.get_env(:open_api_client_ex, :json_library)
          end)

        if json_library do
          case json_library.encode(body) do
            {:ok, encoded_body} ->
              %Operation{operation | request_body: encoded_body}

            {:error, error} ->
              Operation.set_result(
                operation,
                {:error,
                 Error.new(
                   message: "Error while JSON-encoding request body",
                   operation: operation,
                   source: error,
                   reason: :request_body_json_encode_failed,
                   step: __MODULE__
                 )}
              )
          end
        else
          Operation.set_result(
            operation,
            {:error,
             Error.new(
               message: "JSON library not set",
               operation: operation,
               reason: :json_library_not_set,
               step: __MODULE__
             )}
          )
        end

      _ ->
        operation
    end
  end
end

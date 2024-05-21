defmodule OpenAPIClient.Client.Operation do
  @type t :: %__MODULE__{
          halted: boolean(),
          assigns: map(),
          request_body: term(),
          request_headers: %{String.t() => String.t()},
          response_body: term(),
          response_headers: %{String.t() => String.t()},
          response_type: OpenAPIClient.Schema.type() | nil,
          result: {:ok, term()} | {:error, term()} | nil
        }

  @derive Pluggable.Token
  defstruct halted: false,
            assigns: %{},
            request_headers: %{},
            request_body: nil,
            response_headers: %{},
            response_body: nil,
            response_type: nil,
            result: nil

  @type external_headers ::
          [{String.t(), String.t()}] | keyword(String.t()) | %{String.t() => String.t()}

  @spec get_request_header(t(), String.t()) :: {:ok, String.t()} | :error
  def get_request_header(%__MODULE__{request_headers: headers}, header_name) do
    get_header(headers, header_name)
  end

  @spec put_request_header(t(), String.t(), String.t()) :: t()
  def put_request_header(operation, header_name, header_value) do
    put_request_headers(operation, [{header_name, header_value}])
  end

  @spec put_request_headers(t(), external_headers()) :: t()
  def put_request_headers(%__MODULE__{request_headers: headers} = operation, new_headers) do
    %__MODULE__{operation | request_headers: put_headers(headers, new_headers)}
  end

  @spec get_response_header(t(), String.t()) :: {:ok, String.t()} | :error
  def get_response_header(%__MODULE__{response_headers: headers}, header_name) do
    get_header(headers, header_name)
  end

  @spec put_response_header(t(), String.t(), String.t()) :: t()
  def put_response_header(operation, header_name, header_value) do
    put_response_headers(operation, [{header_name, header_value}])
  end

  @spec put_response_headers(t(), external_headers()) :: t()
  def put_response_headers(%__MODULE__{response_headers: headers} = operation, new_headers) do
    %__MODULE__{operation | response_headers: put_headers(headers, new_headers)}
  end

  defp get_header(headers, header_name) do
    Map.fetch(headers, String.downcase(header_name))
  end

  defp put_headers(headers, new_headers) do
    new_headers_map =
      Map.new(new_headers, fn {name, value} ->
        {name |> to_string() |> String.downcase(), value}
      end)

    Map.merge(headers, new_headers_map)
  end
end

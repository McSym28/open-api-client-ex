defmodule OpenAPIClient.Client.Operation do
  @type url :: String.t() | URI.t()
  @type method :: :get | :put | :post | :delete | :options | :head | :patch | :trace
  @type query_params :: %{String.t() => String.t()}
  @type headers :: %{String.t() => String.t()}
  @type content_type :: String.t()
  @type request_schema :: {content_type(), OpenAPIClient.Schema.type()}
  @type response_status_code :: integer() | String.t() | :default
  @type response_schema :: {content_type(), OpenAPIClient.Schema.type()}
  @type response_type :: {response_status_code(), [response_schema()] | :null}
  @type external_headers :: [{String.t(), String.t()}] | keyword(String.t()) | headers()
  @type result :: {:ok, term()} | {:error, term()}

  alias OpenAPIClient.Client.Error

  @type t :: %__MODULE__{
          halted: boolean(),
          assigns: map(),
          request_base_url: url(),
          request_url: url(),
          request_method: method(),
          request_query_params: query_params(),
          request_headers: headers(),
          request_body: term() | nil,
          request_types: [request_schema()],
          response_body: term() | nil,
          response_headers: headers(),
          response_status_code: integer() | nil,
          response_types: [response_type()],
          result: result() | nil
        }

  @derive Pluggable.Token
  @enforce_keys [:request_base_url, :request_url, :request_method]
  defstruct [
    :request_base_url,
    :request_url,
    :request_method,
    :request_body,
    :response_body,
    :response_status_code,
    :result,
    halted: false,
    assigns: %{private: %{}},
    request_query_params: %{},
    request_headers: %{},
    request_types: [],
    response_headers: %{},
    response_types: []
  ]

  @spec set_result(t(), result()) :: t()
  def set_result(operation, result) do
    %__MODULE__{operation | result: result}
    |> Pluggable.Token.halt()
  end

  @spec get_request_header(t(), String.t()) :: {:ok, String.t()} | :error
  def get_request_header(%__MODULE__{request_headers: headers}, header_name) do
    get_header(headers, header_name)
  end

  @spec get_request_content_type_header_media_type(t()) ::
          {:ok, String.t()} | {:error, :not_found | :invalid_format}
  def get_request_content_type_header_media_type(%__MODULE__{request_headers: headers}) do
    get_content_type_header_media_type(headers)
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

  @spec get_response_content_type_header_media_type(t()) ::
          {:ok, String.t()} | {:error, :not_found | :invalid_format}
  def get_response_content_type_header_media_type(%__MODULE__{response_headers: headers}) do
    get_content_type_header_media_type(headers)
  end

  @spec put_response_header(t(), String.t(), String.t()) :: t()
  def put_response_header(operation, header_name, header_value) do
    put_response_headers(operation, [{header_name, header_value}])
  end

  @spec put_response_headers(t(), external_headers()) :: t()
  def put_response_headers(%__MODULE__{response_headers: headers} = operation, new_headers) do
    %__MODULE__{operation | response_headers: put_headers(headers, new_headers)}
  end

  @spec put_private(t(), atom(), term()) :: t()
  def put_private(operation, key, value) do
    put_private(operation, %{key => value})
  end

  @spec put_private(t(), map() | list({term(), term()})) :: t()
  def put_private(%__MODULE__{assigns: %{private: private}} = operation, map) when is_map(map) do
    put_in(operation, [Access.key!(:assigns), :private], Map.merge(private, map))
  end

  def put_private(operation, list) when is_list(list) do
    put_private(operation, Map.new(list))
  end

  @spec get_response_type(t()) ::
          {:ok, {response_status_code(), content_type() | nil, OpenAPIClient.Schema.type()}}
          | {:error, Error.t()}
  def get_response_type(
        %__MODULE__{response_types: types, response_status_code: status_code} = operation
      ) do
    types
    |> Enum.reduce_while(
      {:unknown, nil},
      fn
        {^status_code, _} = type, _current ->
          {:halt, {:exact, type}}

        {<<digit::utf8, "XX">>, _} = type, _current
        when (digit - ?0) * 100 <= status_code and (digit - ?0 + 1) * 100 > status_code ->
          {:cont, {:range, type}}

        {:default, _} = type, {:unknown, _} ->
          {:cont, {:default, type}}

        _, current ->
          {:cont, current}
      end
    )
    |> elem(1)
    |> case do
      {status_code, :null} ->
        {:ok, {status_code, nil, :null}}

      {status_code, schemas} ->
        case get_response_content_type_header_media_type(operation) do
          {:ok, content_type} ->
            case List.keyfind(schemas, content_type, 0) do
              {_, type} ->
                {:ok, {status_code, content_type, type}}

              _ ->
                {:error,
                 Error.new(
                   message: "Unexpected `Content-Type` HTTP header",
                   operation: operation,
                   reason: :unexpected_content_type
                 )}
            end

          {:error, :not_found} ->
            {:error,
             Error.new(
               message: "Missing `Content-Type` HTTP header",
               operation: operation,
               reason: :missing_content_type
             )}

          {:error, :invalid_format} ->
            {:error,
             Error.new(
               message: "`Content-Type` HTTP header invalid format",
               operation: operation,
               reason: :content_type_invalid_format
             )}
        end

      nil ->
        {:error,
         Error.new(
           message: "Unexpected HTTP status code",
           operation: operation,
           reason: :unexpected_status_code
         )}
    end
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

  defp get_content_type_header_media_type(headers) do
    with {:get, {:ok, content_type}} <- {:get, get_header(headers, "Content-Type")},
         {:parse, {:ok, {type, subtype, _parameters}}} <-
           {:parse, parse_content_type_header(content_type)} do
      media_type = "#{type}/#{subtype}"
      {:ok, media_type}
    else
      {:get, :error} -> {:error, :not_found}
      {:parse, _} -> {:error, :invalid_format}
    end
  end

  @spec parse_content_type_header(String.t()) ::
          {:ok, {String.t(), String.t(), %{String.t() => String.t()}}}
          | {:error,
             :empty_string
             | {:invalid_media_type_format, String.t()}
             | {:invalid_parameter_format, String.t()}}
  def parse_content_type_header(value) do
    with {:initial_split, [media_type | rest]} <-
           {:initial_split, String.split(value, ";", trim: true)},
         {:parse_media_type, {:ok, {type, subtype}}} <-
           {:parse_media_type, media_type |> String.trim() |> parse_content_type_media_type()},
         {:parse_parameters, {:ok, parameter_map}} <-
           {:parse_parameters,
            Enum.reduce_while(rest, {:ok, %{}}, fn parameter, {:ok, parameter_map} ->
              parameter
              |> String.trim()
              |> parse_content_type_parameter()
              |> case do
                {:ok, :empty_string} ->
                  {:cont, {:ok, parameter_map}}

                {:ok, {key, value}} ->
                  {:cont, {:ok, Map.put(parameter_map, key, value)}}

                error ->
                  {:halt, error}
              end
            end)} do
      {:ok, {type, subtype, parameter_map}}
    else
      {:initial_split, []} -> {:error, :empty_string}
      {_tag, error} -> error
    end
  end

  defp parse_content_type_media_type(""), do: {:error, :empty_string}

  defp parse_content_type_media_type(value) do
    value
    |> String.split("/")
    |> case do
      [type, subtype] -> {:ok, {type, subtype}}
      _ -> {:error, {:invalid_media_type_format, value}}
    end
  end

  defp parse_content_type_parameter(""), do: {:ok, :empty_string}

  defp parse_content_type_parameter(value) do
    value
    |> String.split("=")
    |> case do
      [key, value] -> {:ok, {key, value}}
      _ -> {:error, {:invalid_parameter_format, value}}
    end
  end
end

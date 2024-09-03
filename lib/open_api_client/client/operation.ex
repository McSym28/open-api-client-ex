defmodule OpenAPIClient.Client.Operation do
  alias OpenAPIClient.Schema

  @type url :: String.t() | URI.t()
  @type method :: :get | :put | :post | :delete | :options | :head | :patch | :trace
  @type common_parameter_location :: :path | :header | :query | :cookie
  @type custom_parameter_location :: :custom
  @type parameter_location :: common_parameter_location() | custom_parameter_location()
  @type parameter_key :: {String.t(), parameter_location()}
  @type parameters :: %{parameter_key() => String.t()}
  @type parameter_type_key :: {atom(), parameter_location()}
  @type content_type :: String.t()
  @type request_schema :: {content_type(), Schema.type()}
  @type response_status_code :: integer() | String.t() | boolean()
  @type response_schema :: {content_type(), Schema.type()}
  @type response_type :: {response_status_code(), [response_schema()] | :null}
  @type external_parameters ::
          [{{String.t(), parameter_location()}, String.t()}]
          | %{{String.t(), parameter_location()} => String.t()}
  @type result :: {:ok, term()} | {:error, term()}

  alias OpenAPIClient.Client.Error

  @type t :: %__MODULE__{
          halted: boolean(),
          assigns: map(),
          request_base_url: url(),
          request_path: url(),
          request_path_mask: url() | nil,
          request_method: method(),
          request_parameters: parameters(),
          request_parameter_types: [{parameter_type_key(), Schema.field_type()}],
          request_parameter_args: [atom()],
          request_body: term() | nil,
          request_types: [request_schema()],
          response_body: term() | nil,
          response_parameters: parameters(),
          response_status_code: integer() | nil,
          response_types: [response_type()],
          result: result() | nil
        }

  @derive Pluggable.Token
  @enforce_keys [:request_base_url, :request_path, :request_method]
  defstruct [
    :request_base_url,
    :request_path,
    :request_path_mask,
    :request_method,
    :request_body,
    :response_body,
    :response_status_code,
    :result,
    halted: false,
    assigns: %{private: %{}},
    request_parameters: %{},
    request_parameter_types: [],
    request_parameter_args: [],
    request_types: [],
    response_parameters: %{},
    response_types: []
  ]

  @spec set_result(t(), result()) :: t()
  def set_result(operation, result) do
    %__MODULE__{operation | result: result}
    |> Pluggable.Token.halt()
  end

  @spec get_request_parameter(t(), String.t(), common_parameter_location()) ::
          {:ok, String.t()} | :error
  def get_request_parameter(%__MODULE__{request_parameters: parameters}, name, location) do
    get_parameter(parameters, name, location)
  end

  @spec get_request_content_type(t()) ::
          {:ok, String.t()} | {:error, :not_found | :invalid_format}
  def get_request_content_type(%__MODULE__{request_parameters: parameters}) do
    get_content_type(parameters)
  end

  @spec put_request_parameter(t(), String.t(), common_parameter_location(), String.t()) :: t()
  def put_request_parameter(operation, name, location, value) do
    put_request_parameters(operation, [{{name, location}, value}])
  end

  @spec put_request_parameters(t(), external_parameters()) :: t()
  def put_request_parameters(
        %__MODULE__{request_parameters: parameters} = operation,
        new_parameters
      ) do
    %__MODULE__{operation | request_parameters: put_parameters(parameters, new_parameters)}
  end

  @spec get_response_parameter(t(), String.t(), common_parameter_location()) ::
          {:ok, String.t()} | :error
  def get_response_parameter(%__MODULE__{response_parameters: parameters}, name, location) do
    get_parameter(parameters, name, location)
  end

  @spec get_response_content_type(t()) ::
          {:ok, String.t()} | {:error, :not_found | :invalid_format}
  def get_response_content_type(%__MODULE__{response_parameters: parameters}) do
    get_content_type(parameters)
  end

  @spec put_response_parameter(t(), String.t(), common_parameter_location(), String.t()) :: t()
  def put_response_parameter(operation, name, location, value) do
    put_response_parameters(operation, [{{name, location}, value}])
  end

  @spec put_response_parameters(t(), external_parameters()) :: t()
  def put_response_parameters(
        %__MODULE__{response_parameters: parameters} = operation,
        new_parameters
      ) do
    %__MODULE__{operation | response_parameters: put_parameters(parameters, new_parameters)}
  end

  @spec get_private(t(), atom()) :: term()
  @spec get_private(t(), atom(), term()) :: term()
  def get_private(%__MODULE__{assigns: %{private: private}} = _operation, key, default \\ nil) do
    Map.get(private, key, default)
  end

  @spec put_private(t(), atom(), term()) :: t()
  def put_private(operation, key, value) do
    put_private(operation, %{key => value})
  end

  @spec put_private(t(), map() | list({term(), term()})) :: t()
  def put_private(operation, map) when is_map(map) do
    update_in(operation, [Access.key!(:assigns), :private], &Map.merge(&1, map))
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
    status_code_exact = get_private(operation, :__status_code__)

    types
    |> Enum.reduce_while(
      {:unknown, nil},
      fn
        {^status_code_exact, _} = type, _current ->
          {:halt, {:exact, type}}

        {^status_code, _} = type, _current ->
          {:halt, {:exact, type}}

        {<<digit::utf8, "XX">>, _} = type, _current
        when (digit - ?0) * 100 <= status_code and (digit - ?0 + 1) * 100 > status_code ->
          {:cont, {:range, type}}

        {default, _} = type, {:unknown, _} when is_boolean(default) ->
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
        case get_response_content_type(operation) do
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

  defp get_parameter(parameters, name, :header = location) do
    do_get_parameter(parameters, String.downcase(name), location)
  end

  defp get_parameter(parameters, name, location) do
    do_get_parameter(parameters, name, location)
  end

  defp do_get_parameter(parameters, name, location) do
    Map.fetch(parameters, {name, location})
  end

  defp put_parameters(parameters, new_parameters) do
    Enum.reduce(new_parameters, parameters, fn {{name, location}, value}, acc ->
      put_parameter(acc, name, location, value)
    end)
  end

  defp put_parameter(parameters, name, location, value) when not is_binary(name),
    do: put_parameter(parameters, to_string(name), location, value)

  defp put_parameter(parameters, name, :header = location, value),
    do: do_put_parameter(parameters, String.downcase(name), location, value)

  defp put_parameter(parameters, name, location, value),
    do: do_put_parameter(parameters, name, location, value)

  defp do_put_parameter(parameters, name, location, value) do
    Map.put(parameters, {name, location}, value)
  end

  defp get_content_type(parameters) do
    with {:get, {:ok, content_type}} <-
           {:get, get_parameter(parameters, "Content-Type", :header)},
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

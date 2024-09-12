defmodule OpenAPIClient.State do
  alias OpenAPIClient.Schema
  alias OpenAPIClient.Error

  @type url :: String.t() | URI.t()
  @type method :: :get | :put | :post | :delete | :options | :head | :patch | :trace
  @type common_parameter_location :: :path | :header | :query | :cookie
  @type custom_parameter_location :: :custom
  @type parameter_location :: common_parameter_location() | custom_parameter_location()
  @type parameters :: %{atom() => term()}
  @type parameter_type_key :: {atom(), parameter_location()}
  @type content_type :: String.t()
  @type request_schema :: {content_type(), Schema.type()}
  @type response_status_code :: integer() | String.t() | boolean()
  @type response_schema :: {content_type(), Schema.type()}
  @type response_type :: {response_status_code(), [response_schema()] | :null}
  @type result :: :ok | {:ok, term()} | :error | {:error, term()}

  @type t :: %__MODULE__{
          function_call: {module(), atom()},
          function_args: keyword(),
          function_opts: keyword(),
          method: method(),
          profile: atom(),
          request_base_url: url(),
          request_path: url(),
          request_path_mask: url() | nil,
          request_headers: parameters(),
          request_query_params: parameters(),
          request_path_params: parameters(),
          request_custom_params: parameters(),
          request_parameter_types: [{parameter_type_key(), Schema.field_type()}],
          request_parameter_args: [atom()],
          request_body: term() | nil,
          request_types: [request_schema()],
          response_body: term() | nil,
          response_headers: parameters(),
          response_status_code: response_status_code() | nil,
          response_types: [response_type()],
          result: result() | nil
        }

  @enforce_keys [:request_base_url, :request_path, :method]
  defstruct [
    :function_call,
    :method,
    :profile,
    :request_base_url,
    :request_path,
    :request_path_mask,
    :request_body,
    :response_body,
    :response_status_code,
    :result,
    function_args: [],
    function_opts: [],
    request_headers: %{},
    request_query_params: %{},
    request_path_params: %{},
    request_custom_params: %{},
    request_parameter_types: [],
    request_parameter_args: [],
    request_types: [],
    response_headers: %{},
    response_types: []
  ]

  @spec parse_method(conn :: Plug.Conn.t()) :: method()
  def parse_method(%Plug.Conn{method: method}),
    do: method |> String.downcase() |> do_parse_method()

  @spec get_request_type(conn :: Plug.Conn.t()) ::
          {:ok, {content_type() | nil, OpenAPIClient.Schema.type()}}
          | {:error, Error.t()}
  def get_request_type(%Plug.Conn{req_headers: headers} = conn) do
    conn
    |> OpenAPIClient.get_state()
    |> case do
      %__MODULE__{request_types: types} ->
        select_type(conn, headers, types)

      _ ->
        {:error,
         Error.new(
           message: "OpenAPIClient not set up",
           conn: conn,
           reason: :open_api_client_not_set_up
         )}
    end
  end

  @spec get_response_type(conn :: Plug.Conn.t()) ::
          {:ok, {response_status_code(), content_type() | nil, OpenAPIClient.Schema.type()}}
          | {:error, Error.t()}
  def get_response_type(%Plug.Conn{resp_headers: headers} = conn) do
    conn
    |> select_response_type()
    |> case do
      {status_code, :null} ->
        {:ok, {status_code, nil, :null}}

      {status_code, schemas} ->
        case select_type(conn, headers, schemas) do
          {:ok, {content_type, type}} -> {:ok, {status_code, content_type, type}}
          {:error, _} = error -> error
        end

      nil ->
        {:error,
         Error.new(
           message: "Unexpected HTTP status code",
           conn: conn,
           reason: :unexpected_status_code
         )}
    end
  end

  @spec read_body(conn :: Plug.Conn.t(), opts :: Plug.opts()) :: {:ok, term(), Plug.Conn.t()}
  def read_body(conn, _opts) do
    case OpenAPIClient.get_state(conn) do
      %__MODULE__{request_body: body} -> {:ok, body, conn}
      nil -> {:ok, nil, conn}
    end
  end

  defp select_type(conn, headers, schemas) do
    case OpenAPIClient.Utils.get_content_type(headers) do
      {:ok, content_type} ->
        case List.keyfind(schemas, content_type, 0) do
          {_, type} ->
            {:ok, {content_type, type}}

          _ ->
            {:error,
             Error.new(
               message: "Unexpected `Content-Type` HTTP header",
               conn: conn,
               reason: :unexpected_content_type
             )}
        end

      {:error, :not_found} ->
        {:error,
         Error.new(
           message: "Missing `Content-Type` HTTP header",
           conn: conn,
           reason: :missing_content_type
         )}

      {:error, :invalid_format} ->
        {:error,
         Error.new(
           message: "`Content-Type` HTTP header invalid format",
           conn: conn,
           reason: :content_type_invalid_format
         )}
    end
  end

  defp select_response_type(%Plug.Conn{status: status_code} = conn) do
    conn
    |> OpenAPIClient.get_state()
    |> case do
      %__MODULE__{response_types: types, response_status_code: status_code_exact} ->
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

      _ ->
        nil
    end
  end

  defp do_parse_method("get"), do: :get
  defp do_parse_method("put"), do: :put
  defp do_parse_method("post"), do: :post
  defp do_parse_method("delete"), do: :delete
  defp do_parse_method("options"), do: :options
  defp do_parse_method("head"), do: :head
  defp do_parse_method("patch"), do: :patch
  defp do_parse_method("trace"), do: :trace
  defp do_parse_method("connect"), do: :connect
end

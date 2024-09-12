defmodule OpenAPIClient.Plugs.ResponseSerializers do
  defmodule SerializeError do
    @moduledoc """
    Error raised when the response body is malformed.
    """

    defexception exception: nil, plug_status: 400

    def message(%{exception: exception}) do
      exception
      |> Exception.message()
      |> String.replace(~r/\brequest\b/, "response")
    end
  end

  @moduledoc """
  A plug for serializing the response body.

  It invokes a list of `:serializers`, which are activated based on the
  response content-type.

  See documentation for `OpenAPIClient.Plugs.Serializers`.

  Accepts the same `opts` as `OpenAPIClient.Plugs.Serializers`.

  """

  @behaviour Plug

  @impl Plug
  @spec init(opts :: Keyword.t()) :: Plug.opts()
  def init(opts) do
    opts
    |> Keyword.put_new(:body_reader, {__MODULE__, :read_body, []})
    |> OpenAPIClient.Plugs.Serializers.init()
  end

  @impl Plug
  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(%Plug.Conn{resp_headers: resp_headers, status: status_code} = original_conn, opts) do
    with {"content-type", ct} <- List.keyfind(resp_headers, "content-type", 0),
         conn <-
           %Plug.Conn{original_conn | method: "POST"}
           |> Plug.Conn.put_req_header("content-type", ct)
           |> OpenAPIClient.Plugs.Serializers.call(opts) do
      %OpenAPIClient.State{request_body: response_body} = OpenAPIClient.get_state(conn)
      Plug.Conn.resp(original_conn, status_code, response_body)
    else
      _ -> original_conn
    end
  rescue
    e in OpenAPIClient.Plugs.Serializers.SerializeError -> raise SerializeError, exception: e
  end

  def call(conn, _opts), do: conn

  @spec read_body(conn :: Plug.Conn.t(), opts :: Plug.opts()) :: {:ok, term(), Plug.Conn.t()}
  def read_body(conn, _opts) do
    case OpenAPIClient.get_state(conn) do
      %OpenAPIClient.State{response_body: body} -> {:ok, body, conn}
      _ -> {:ok, nil, conn}
    end
  end
end

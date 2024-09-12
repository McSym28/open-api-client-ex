defmodule OpenAPIClient.Plugs.ResponseParsers do
  defmodule TooLargeError do
    @moduledoc """
    Error raised when the response is too large.
    """

    defexception message:
                   "the response is too large. If you are willing to process " <>
                     "larger responses, please give a :length to Plug.Parsers",
                 plug_status: 413
  end

  defmodule ParseError do
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
  A plug for parsing the response body.

  It invokes a list of `:parsers`, which are activated based on the
  response content-type.

  See documentation for [`Plug.Parsers`](https://hexdocs.pm/plug/Plug.Parsers.html).

  Accepts the same `opts` as [`Plug.Parsers`](https://hexdocs.pm/plug/Plug.Parsers.html#module-options).

  Additionally, it is possible to pass an MFA `:body_writer` to change the way the parsed body
  is being stored in `Plug.Conn`. By default the `OpenAPIClient.Plugs.ResponseParsers.write_body/3` is
  being called, which currently removes the `"_json"` for JSON parser.

  """

  @behaviour Plug

  @impl Plug
  @spec init(opts :: Keyword.t()) :: Plug.opts()
  def init(opts) do
    {body_writer, opts} = Keyword.pop(opts, :body_writer, {__MODULE__, :write_body, []})

    parsers_opts =
      opts
      |> Keyword.put_new(:body_reader, {__MODULE__, :read_body, []})
      |> Plug.Parsers.init()

    {body_writer, parsers_opts}
  end

  @impl Plug
  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(%Plug.Conn{resp_body: nil} = conn, _opts), do: conn

  def call(%Plug.Conn{resp_headers: resp_headers} = original_conn, {body_writer, opts}) do
    with {"content-type", ct} <- List.keyfind(resp_headers, "content-type", 0),
         %Plug.Conn{body_params: body_params} <-
           %Plug.Conn{
             original_conn
             | method: "POST",
               body_params: %Plug.Conn.Unfetched{aspect: :body_params}
           }
           |> Plug.Conn.put_req_header("content-type", ct)
           |> Plug.Parsers.call(opts),
         {module, fun, args} <- body_writer do
      apply(module, fun, [original_conn, opts, body_params | args])
    else
      _ -> original_conn
    end
  rescue
    Plug.Parsers.RequestTooLargeError -> raise TooLargeError
    e in Plug.Parsers.ParseError -> raise ParseError, exception: e
  end

  @spec read_body(Plug.Conn.t(), Plug.opts()) :: {:ok, binary() | iodata(), Plug.Conn.t()}
  def read_body(%Plug.Conn{resp_body: body} = conn, _opts), do: {:ok, body, conn}

  @spec write_body(Plug.Conn.t(), Plug.opts(), Plug.Conn.params()) :: Plug.Conn.t()
  def write_body(conn, opts, %{"_json" => terms}), do: write_body(conn, opts, terms)

  def write_body(conn, _opts, body) do
    %OpenAPIClient.State{} = state = OpenAPIClient.get_state(conn)
    state_new = %OpenAPIClient.State{state | response_body: body}
    OpenAPIClient.set_state(conn, state_new)
  end
end

defmodule OpenAPIClient.Plugs.FunctionCall do
  @moduledoc """
  A plug for performing the function call.

  Accepts the following `opts`:
  * `:client` - Module that implements `OpenAPIClient` behaviour.
  Default value obtained through a call to `OpenAPIClient.Utils.get_config(conn, :client, OpenAPIClient)`

  """

  @behaviour Plug

  @type option :: {:client, module()}
  @type options :: [option()]

  @impl Plug
  @spec init(opts :: options()) :: options()
  def init(opts), do: opts

  @impl Plug
  @spec call(Plug.Conn.t(), options()) :: Plug.Conn.t()
  def call(conn, opts) do
    client =
      Keyword.get_lazy(opts, :client, fn ->
        OpenAPIClient.Utils.get_config(conn, :client, OpenAPIClient)
      end)

    client.callback(conn)
  end
end

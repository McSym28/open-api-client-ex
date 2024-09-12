defmodule OpenAPIClient.Plugs.Serializers.URLENCODED do
  @moduledoc """
  Serializes urlencoded request body.
  """

  @behaviour OpenAPIClient.Plugs.Serializers

  @impl OpenAPIClient.Plugs.Serializers
  def init(opts) do
    Keyword.pop(opts, :body_reader, {OpenAPIClient.State, :read_body, []})
  end

  @impl OpenAPIClient.Plugs.Serializers
  def serialize(
        conn,
        "application",
        "x-www-form-urlencoded",
        _headers,
        {{mod, fun, args}, opts}
      ) do
    {:ok, body, conn} = apply(mod, fun, [conn, opts | args])

    if body do
      {:ok, Plug.Conn.Query.encode(body), conn}
    else
      {:ok, nil, conn}
    end
  end

  def serialize(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end
end

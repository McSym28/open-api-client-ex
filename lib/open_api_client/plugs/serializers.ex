defmodule OpenAPIClient.Plugs.Serializers do
  defmodule SerializeError do
    @moduledoc """
    Error raised when the request body is malformed.
    """

    defexception exception: nil, plug_status: 400

    def message(%{exception: exception}) do
      "malformed request, a #{inspect(exception.__struct__)} exception was raised " <>
        "with message #{inspect(Exception.message(exception))}"
    end
  end

  @moduledoc """
  A plug for serializing the request body.

  It invokes a list of `:serializers`, which are activated based on the
  request content-type. Custom serializers are also supported by defining
  a module that implements the behaviour defined by this module.

  Once a connection goes through this plug, it will have OpenAPIClient.State's
  `:request_body` set to a binary/iodata serializer by one of the serializers
  listed in `:serializers`.

  This plug will raise `Plug.Parsers.UnsupportedMediaTypeError` by default if
  the request cannot be serialized by any of the given types and the MIME type has
  not been explicitly accepted with the `:pass` option.

  Serializers may raise a `OpenAPIClient.Plugs.Serializers.SerializeError` if the
  request has a malformed body.

  This plug only serializes the body if the request method is one of the following:

    * `POST`
    * `PUT`
    * `PATCH`
    * `DELETE`

  For requests with a different request method, this plug will not be a noop.

  ## Options

    * `:serializers` - a list of modules or atoms of built-in serializer to be
      invoked for serializing. These modules need to implement the behaviour
      outlined in this module.

    * `:pass` - an optional list of MIME type strings that are allowed
      to pass through. Any mime not handled by a serializer and not explicitly
      listed in `:pass` will `raise UnsupportedMediaTypeError`. For example:

        * `["*/*"]` - never raises
        * `["text/html", "application/*"]` - doesn't raise for those values
        * `[]` - always raises (default)

  All other options given to this Plug are forwarded to the serializers.

  ## Examples

      plug OpenAPIClient.Plugs.Serializers,
           serializers: [:urlencoded, :multipart],
           pass: ["text/*"]

  Any other option given to OpenAPIClient.Plugs.Serializers is forwarded to the underlying
  serializers. Therefore, you can use a JSON serializer and pass the `:json_encoder`
  option at the root:

      plug OpenAPIClient.Plugs.Serializers,
           serializers: [:urlencoded, :json],
           json_encoder: Jason

  Or directly to the serializer itself:

      plug OpenAPIClient.Plugs.Serializers,
           serializers: [:urlencoded, {:json, json_encoder: Jason}]

  It is also possible to pass the `:json_encoder` as a `{module, function, args}` tuple,
  useful for passing options to the JSON encoder:

      plug OpenAPIClient.Plugs.Serializers,
           serializers: [:json],
           json_encoder: {Jason, :encode!, [[floats: :decimals]]}

  ## Built-in serializers

  Plug ships with the following serializers:

    * `OpenAPIClient.Plugs.Serializers.URLENCODED` - serializes `application/x-www-form-urlencoded`
      requests (can be used as `:urlencoded` as well in the `:serializers` option)
    * `OpenAPIClient.Plugs.Serializers.JSON` - serializes `application/json` requests with the given
      `:json_encoder` (can be used as `:json` as well in the `:serializers` option)

  """

  @callback init(opts :: keyword()) :: Plug.opts()

  @doc """
  Attempts to serialize the connection's request body given the content-type type,
  subtype, and its parameters.

  The arguments are:

    * the `Plug.Conn` connection
    * `type`, the content-type type (e.g., `"x-sample"` for the
      `"x-sample/json"` content-type)
    * `subtype`, the content-type subtype (e.g., `"json"` for the
      `"x-sample/json"` content-type)
    * `params`, the content-type parameters (e.g., `%{"foo" => "bar"}`
      for the `"text/plain; foo=bar"` content-type)

  This function should return:

    * `{:ok, body, conn}` if the serializer is able to handle the given
      content-type; `body` should be a binary/iodata
    * `{:next, conn}` if the next serializer should be invoked

  """
  @callback serialize(
              conn :: Plug.Conn.t(),
              type :: binary,
              subtype :: binary,
              params :: Plug.Conn.Utils.params(),
              opts :: Plug.opts()
            ) ::
              {:ok, binary() | iodata(), Plug.Conn.t()}
              | {:next, Plug.Conn.t()}

  @behaviour Plug
  @methods ~w(POST PUT PATCH DELETE)

  @impl Plug
  def init(opts) do
    {serializers, opts} = Keyword.pop(opts, :serializers)
    {pass, opts} = Keyword.pop(opts, :pass, [])

    unless serializers do
      raise ArgumentError,
            "OpenAPIClient.Plugs.Serializers expects a set of serializers to be given in :serializers"
    end

    {convert_serializers(serializers, opts), pass}
  end

  defp convert_serializers(serializers, root_opts) do
    for serializer <- serializers do
      {serializer, opts} =
        case serializer do
          {serializer, opts} when is_atom(serializer) and is_list(opts) ->
            {serializer, Keyword.merge(root_opts, opts)}

          serializer when is_atom(serializer) ->
            {serializer, root_opts}
        end

      module =
        case Atom.to_string(serializer) do
          "Elixir." <> _ -> serializer
          reference -> Module.concat(OpenAPIClient.Plugs.Serializers, String.upcase(reference))
        end

      {module, module.init(opts)}
    end
  end

  @impl Plug
  def call(%Plug.Conn{method: method, req_headers: req_headers} = conn, options)
      when method in @methods do
    with %OpenAPIClient.State{request_body: body} when not is_nil(body) <-
           OpenAPIClient.get_state(conn),
         {"content-type", ct} <- List.keyfind(req_headers, "content-type", 0) do
      {serializers, pass} = options

      case Plug.Conn.Utils.content_type(ct) do
        {:ok, type, subtype, params} ->
          reduce(
            conn,
            serializers,
            type,
            subtype,
            params,
            pass
          )

        :error ->
          reduce(conn, serializers, ct, "", %{}, pass)
      end
    else
      _ ->
        conn
    end
  end

  def call(conn, _opts), do: conn

  defp reduce(
         conn,
         [{serializer, options} | rest],
         type,
         subtype,
         params,
         pass
       ) do
    case serializer.serialize(conn, type, subtype, params, options) do
      {:ok, body, conn} ->
        %OpenAPIClient.State{} = state = OpenAPIClient.get_state(conn)
        state_new = %OpenAPIClient.State{state | request_body: body}
        OpenAPIClient.set_state(conn, state_new)

      {:next, conn} ->
        reduce(conn, rest, type, subtype, params, pass)
    end
  end

  defp reduce(conn, [], type, subtype, _params, pass) do
    if accepted_mime?(type, subtype, pass) do
      conn
    else
      raise Plug.Parsers.UnsupportedMediaTypeError, media_type: "#{type}/#{subtype}"
    end
  end

  defp accepted_mime?(_type, _subtype, ["*/*"]),
    do: true

  defp accepted_mime?(type, subtype, pass),
    do: "#{type}/#{subtype}" in pass || "#{type}/*" in pass
end

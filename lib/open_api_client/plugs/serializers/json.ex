defmodule OpenAPIClient.Plugs.Serializers.JSON do
  @moduledoc """
  Serializes JSON request body.
  """

  @behaviour OpenAPIClient.Plugs.Serializers

  @impl OpenAPIClient.Plugs.Serializers
  def init(opts) do
    {body_reader, opts} =
      Keyword.pop(opts, :body_reader, {OpenAPIClient.State, :read_body, []})

    {encoder, opts} = Keyword.pop(opts, :json_encoder)
    encoder = validate_encoder!(encoder)
    {body_reader, encoder, opts}
  end

  defp validate_encoder!(nil) do
    raise ArgumentError, "JSON serializer expects a :json_encoder option"
  end

  defp validate_encoder!({module, fun, args} = mfa)
       when is_atom(module) and is_atom(fun) and is_list(args) do
    arity = length(args) + 1

    if Code.ensure_compiled(module) != {:module, module} do
      raise ArgumentError,
            "invalid :json_encoder option. The module #{inspect(module)} is not " <>
              "loaded and could not be found"
    end

    if not function_exported?(module, fun, arity) do
      raise ArgumentError,
            "invalid :json_encoder option. The module #{inspect(module)} must " <>
              "implement #{fun}/#{arity}"
    end

    mfa
  end

  defp validate_encoder!(encoder) when is_atom(encoder) do
    validate_encoder!({encoder, :encode!, []})
  end

  defp validate_encoder!(encoder) do
    raise ArgumentError,
          "the :json_encoder option expects a module, or a three-element " <>
            "tuple in the form of {module, function, extra_args}, got: #{inspect(encoder)}"
  end

  @impl OpenAPIClient.Plugs.Serializers
  def serialize(
        conn,
        "application",
        subtype,
        _headers,
        {{mod, fun, args}, encoder, opts}
      ) do
    if subtype == "json" or String.ends_with?(subtype, "+json") do
      apply(mod, fun, [conn, opts | args]) |> encode(encoder, opts)
    else
      {:next, conn}
    end
  end

  def serialize(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  defp encode({:ok, nil, conn}, _encoder, _opts), do: {:ok, nil, conn}

  defp encode({:ok, body, conn}, {module, fun, args}, _opts) do
    try do
      encoded_body = apply(module, fun, [body | args])
      {:ok, encoded_body, conn}
    rescue
      e -> raise OpenAPIClient.Plugs.Serializers.SerializeError, exception: e
    end
  end
end

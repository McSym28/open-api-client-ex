defmodule OpenAPIClient do
  @type plug :: module() | {module(), Plug.opts()} | (Plug.Conn.t() -> Plug.Conn.t())
  @type pipeline :: plug() | nonempty_list(plug())

  @callback operation(state :: OpenAPIClient.State.t(), pipeline :: pipeline()) ::
              OpenAPIClient.State.result()
  @callback callback(conn :: Plug.Conn.t()) :: Plug.Conn.t()

  @optional_callbacks operation: 2, callback: 1

  @behaviour __MODULE__

  @impl __MODULE__
  def operation(
        %OpenAPIClient.State{
          method: method,
          request_base_url: base_url,
          request_path: request_path
        } = state,
        pipeline
      ) do
    %OpenAPIClient.State{result: result} =
      nil
      |> Plug.Conn.Adapter.conn(
        method |> Atom.to_string() |> String.upcase(),
        URI.merge(base_url, request_path),
        {0, 0, 0, 0},
        []
      )
      |> set_state(state)
      |> put_request_content_type_header(state)
      |> Plug.run(OpenAPIClient.Utils.normalize_pipeline(pipeline))
      |> get_state()

    result
  end

  @impl __MODULE__
  def callback(conn) do
    %OpenAPIClient.State{
      function_call: {module, function_name},
      function_args: function_args,
      function_opts: function_opts
    } = state = OpenAPIClient.get_state(conn)

    function_result =
      apply(
        module,
        function_name,
        Keyword.values(function_args) ++
          if(Enum.empty?(function_opts), do: [], else: [function_opts])
      )

    state_new = %OpenAPIClient.State{state | result: function_result}
    OpenAPIClient.set_state(conn, state_new)
  end

  @spec get_state(conn :: Plug.Conn.t()) :: OpenAPIClient.State.t() | nil
  def get_state(%Plug.Conn{private: private} = _conn) do
    Map.get(private, :open_api_client_ex)
  end

  @spec set_state(conn :: Plug.Conn.t(), state :: OpenAPIClient.State.t()) :: Plug.Conn.t()
  def set_state(conn, state) do
    Plug.Conn.put_private(conn, :open_api_client_ex, state)
  end

  @spec set_state_result(conn :: Plug.Conn.t(), result :: OpenAPIClient.State.result()) ::
          Plug.Conn.t()
  def set_state_result(conn, result) do
    conn
    |> get_state()
    |> case do
      %OpenAPIClient.State{} = state ->
        set_state(conn, %OpenAPIClient.State{state | result: result})

      nil ->
        conn
    end
    |> Plug.Conn.halt()
  end

  @spec read_body_params(conn :: Plug.Conn.t(), opts :: Plug.opts()) ::
          {:ok, term(), Plug.Conn.t()}
  def read_body_params(%Plug.Conn{body_params: %Plug.Conn.Unfetched{}} = conn, _opts),
    do: {:ok, nil, conn}

  def read_body_params(%Plug.Conn{body_params: %{"_json" => terms}} = conn, _opts),
    do: {:ok, terms, conn}

  def read_body_params(%Plug.Conn{body_params: %{"_body" => terms}} = conn, _opts),
    do: {:ok, terms, conn}

  def read_body_params(%Plug.Conn{body_params: body_params} = conn, _opts),
    do: {:ok, body_params, conn}

  defp put_request_content_type_header(conn, %OpenAPIClient.State{
         function_args: args,
         request_types: types
       }) do
    with {:ok, body} <- Keyword.fetch(args, :body),
         {content_type, _type} <-
           Enum.find(
             types,
             fn {_content_type, type} -> request_type_match?(body, type) end
           ) do
      Plug.Conn.put_req_header(conn, "content-type", content_type)
    else
      _ -> conn
    end
  end

  defp request_type_match?(nil, :null), do: true
  defp request_type_match?(%struct{}, {struct, type}) when is_atom(type), do: true
  defp request_type_match?(map, :map) when is_map(map), do: true
  defp request_type_match?(_result, _type), do: false
end

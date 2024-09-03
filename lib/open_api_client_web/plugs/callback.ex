if Code.ensure_loaded?(Plug.Conn) do
  defmodule OpenAPIClientWeb.Plugs.Callback do
    alias OpenAPIClient.Client.{Error, Operation}
    alias OpenAPIClient.Utils

    @behaviour Plug

    @type option :: [
            {:implementation, module()}
            | {:behaviour, module()}
            | {:function_name, atom()}
            | {:profile, atom()}
            | {:callback_pipeline, OpenAPIClient.Client.pipeline()}
          ]
    @type options :: [option()]

    @impl Plug
    def init(opts) do
      implementation =
        opts
        |> Keyword.fetch(:implementation)
        |> case do
          {:ok, implementation} ->
            if OpenAPIClient.Utils.is_module?(implementation) do
              implementation
            else
              raise("`#{inspect(implementation)}` is not a module")
            end

          :error ->
            raise("`:implementation` is not set")
        end

      function_name =
        opts
        |> Keyword.fetch(:function_name)
        |> case do
          {:ok, function_name} ->
            :exports
            |> implementation.module_info()
            |> Enum.any?(fn
              {^function_name, _arity} -> true
              {_function_name, _arity} -> false
            end)
            |> if do
              function_name
            else
              raise(
                "`#{inspect(implementation)}` does not export function `#{inspect(function_name)}`"
              )
            end

          :error ->
            raise("`:function_name` is not set")
        end

      behaviour =
        opts
        |> Keyword.fetch(:behaviour)
        |> case do
          {:ok, behaviour} ->
            cond do
              not OpenAPIClient.Utils.does_implement_behaviour?(implementation, behaviour) ->
                raise(
                  "`#{inspect(implementation)}` does not implement behaviour `#{inspect(behaviour)}`"
                )

              not function_exported?(behaviour, :behaviour_info, 1) ->
                raise("`#{inspect(behaviour)}` is not a behaviour")

              :callbacks
              |> behaviour.behaviour_info()
              |> Enum.any?(fn
                {^function_name, _arity} -> true
                {_function_name, _arity} -> false
              end) ->
                behaviour

              :else ->
                raise(
                  "`#{inspect(behaviour)}` does not have function `#{inspect(function_name)}`"
                )
            end

          :error ->
            (implementation.module_info(:attributes) || [])
            |> Keyword.get(:behaviour, [])
            |> Enum.flat_map(fn behaviour ->
              if function_exported?(behaviour, :behaviour_info, 1) and
                   :callbacks
                   |> behaviour.behaviour_info()
                   |> Enum.any?(fn
                     {^function_name, _arity} -> true
                     {_function_name, _arity} -> false
                   end) do
                [behaviour]
              else
                []
              end
            end)
            |> case do
              [behaviour] -> behaviour
              _ -> raise("`:behaviour` is not set")
            end
        end

      unless OpenAPIClient.Utils.does_implement_behaviour?(behaviour, OpenAPIClient.Callback) do
        raise(
          "`#{inspect(behaviour)}` does not implement behaviour `#{inspect(OpenAPIClient.Callback)}`"
        )
      end

      profile =
        opts
        |> Keyword.fetch(:profile)
        |> case do
          {:ok, profile} -> profile
          :error -> raise("`:profile` is not set")
        end

      normalized_pipeline =
        opts
        |> Keyword.get_lazy(:callback_pipeline, fn ->
          Utils.get_config(profile, :callback_pipeline)
        end)
        |> Utils.normalize_pipeline()

      [
        implementation: implementation,
        function_name: function_name,
        behaviour: behaviour,
        profile: profile,
        callback_pipeline: normalized_pipeline
      ]
    end

    @impl Plug
    def call(
          %Plug.Conn{req_headers: request_headers} = conn,
          opts
        ) do
      implementation = Keyword.fetch!(opts, :implementation)
      function_name = Keyword.fetch!(opts, :function_name)
      behaviour = Keyword.fetch!(opts, :behaviour)
      profile = Keyword.fetch!(opts, :profile)
      callback_pipeline = Keyword.fetch!(opts, :callback_pipeline)

      %URI{path: request_path} = uri = conn |> Plug.Conn.request_url() |> URI.parse()

      %Plug.Conn{query_params: request_query_params, req_cookies: request_cookies} =
        conn_new =
        conn
        |> Plug.Conn.fetch_query_params()
        |> Plug.Conn.fetch_cookies()

      request_parameters =
        Enum.concat([
          Enum.map(request_headers, fn {name, value} -> {{name, :header}, value} end),
          Enum.map(request_query_params, fn {name, value} -> {{name, :query}, value} end),
          Enum.map(request_cookies, fn {name, value} -> {{name, :cookie}, value} end)
        ])

      %Operation{response_parameters: response_parameters} =
        operation =
        %Operation{
          request_method: parse_method(conn),
          request_path: request_path,
          request_base_url: %URI{uri | path: nil, query: nil, fragment: nil} |> URI.to_string()
        }
        |> Operation.put_request_parameters(request_parameters)
        |> struct!(behaviour.__functions__(function_name))
        |> Operation.put_private(
          __call__: {implementation, function_name},
          __profile__: profile,
          __conn__: conn_new
        )
        |> add_request_body(conn_new)
        |> Pluggable.run(callback_pipeline)

      {response_status_code, response_body} =
        operation
        |> case do
          %Operation{result: result, response_status_code: status_code} when not is_nil(result) ->
            {status_code, result}

          %Operation{response_body: body, response_status_code: status_code} ->
            {status_code, body}
        end

      conn_new = Operation.get_private(operation, :__conn__, conn_new)

      response_parameters
      |> Enum.reduce(
        conn_new,
        fn
          {{name, :header}, value}, conn -> Plug.Conn.put_resp_header(conn, name, value)
          {{name, :cookie}, value}, conn -> Plug.Conn.put_resp_cookie(conn, name, value)
          _, conn -> conn
        end
      )
      |> put_private(:response_status_code, response_status_code)
      |> put_private(:response_body, response_body)
    end

    defp parse_method(%Plug.Conn{method: method}),
      do: method |> String.downcase() |> parse_method()

    defp parse_method("get"), do: :get
    defp parse_method("put"), do: :put
    defp parse_method("post"), do: :post
    defp parse_method("delete"), do: :delete
    defp parse_method("options"), do: :options
    defp parse_method("head"), do: :head
    defp parse_method("patch"), do: :patch
    defp parse_method("trace"), do: :trace
    defp parse_method("connect"), do: :connect

    defp add_request_body(operation, %Plug.Conn{body_params: %Plug.Conn.Unfetched{}} = conn) do
      conn
      |> Plug.Conn.read_body()
      |> case do
        {:ok, body, conn_new} ->
          %Operation{operation | request_body: body}
          |> Operation.put_private(__conn__: conn_new)

        {:more, _, _conn} ->
          Operation.set_result(
            operation,
            {:error,
             Error.new(
               message: "Request body is too long",
               operation: operation,
               reason: :request_body_too_long,
               step: __MODULE__
             )}
          )

        {:error, reason} ->
          Operation.set_result(
            operation,
            {:error,
             Error.new(
               message: "Request body read error",
               operation: operation,
               reason: :request_body_read_error,
               source: reason,
               step: __MODULE__
             )}
          )
      end
    end

    defp add_request_body(operation, %Plug.Conn{body_params: body} = _conn),
      do: %Operation{operation | request_body: body}

    defp put_private(%Plug.Conn{private: %{open_api_client_ex: %{} = map}} = conn, key, nil) do
      map_new = Map.delete(map, key)
      Plug.Conn.put_private(conn, :open_api_client_ex, map_new)
    end

    defp put_private(%Plug.Conn{private: %{open_api_client_ex: %{} = map}} = conn, key, value) do
      map_new = Map.put(map, key, value)
      Plug.Conn.put_private(conn, :open_api_client_ex, map_new)
    end

    defp put_private(conn, _key, nil), do: conn

    defp put_private(conn, key, value) do
      conn
      |> Plug.Conn.put_private(:open_api_client_ex, %{})
      |> put_private(key, value)
    end

    @spec get_response_status_code(conn :: Plug.Conn.t(), default :: term()) :: term()
    def get_response_status_code(conn, default \\ nil)

    def get_response_status_code(
          %Plug.Conn{private: %{open_api_client_ex: %{response_status_code: status_code}}} =
            _conn,
          _default
        ),
        do: status_code

    def get_response_status_code(_conn, default), do: default

    @spec get_response_body(conn :: Plug.Conn.t(), default :: term()) :: term()
    def get_response_body(conn, default \\ nil)

    def get_response_body(
          %Plug.Conn{private: %{open_api_client_ex: %{response_body: body}}} = _conn,
          _default
        ),
        do: body

    def get_response_body(_conn, default), do: default
  end
end

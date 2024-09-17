defmodule OpenAPIClient.Plugs.CallbackInitializer do
  @moduledoc """
  A plug for initializing the callback processing.

  It should be the first plug in `:open_api_client_ex` pipeline and run after the `Plug.Parsers` plug.
  """

  @behaviour Plug

  @type option ::
          {:implementation, module() | {:mock, module()}}
          | {:behaviour, module()}
          | {:function_name, atom()}
  @type options :: [option()]

  @impl Plug
  @spec init(opts :: options()) :: options()
  def init(opts) do
    {implementation, implementation_loaded?} =
      opts
      |> Keyword.fetch(:implementation)
      |> case do
        {:ok, {:mock, implementation}} ->
          {implementation, is_module?(implementation)}

        {:ok, implementation} ->
          if is_module?(implementation) do
            {implementation, true}
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
          if implementation_loaded? do
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
          else
            function_name
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
            not is_module?(behaviour) ->
              raise("`#{inspect(behaviour)}` is not a module")

            implementation_loaded? and
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
              raise("`#{inspect(behaviour)}` does not have function `#{inspect(function_name)}`")
          end

        :error ->
          if implementation_loaded? do
            (implementation.module_info(:attributes) || [])
            |> Keyword.get(:behaviour, [])
            |> Enum.flat_map(fn behaviour ->
              if is_module?(behaviour) and function_exported?(behaviour, :behaviour_info, 1) and
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
          else
            []
          end
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

    [
      implementation: implementation,
      function_name: function_name,
      behaviour: behaviour
    ]
  end

  @impl Plug
  @spec call(conn :: Plug.Conn.t(), opts :: options()) :: Plug.Conn.t()
  def call(conn, opts) do
    implementation = Keyword.fetch!(opts, :implementation)
    function_name = Keyword.fetch!(opts, :function_name)
    behaviour = Keyword.fetch!(opts, :behaviour)

    %URI{path: request_path} = uri = conn |> Plug.Conn.request_url() |> URI.parse()
    request_base_url = %URI{uri | path: nil, query: nil, fragment: nil} |> URI.to_string()

    %OpenAPIClient.State{
      request_base_url: request_base_url,
      request_path: request_path,
      method: OpenAPIClient.State.parse_method(conn),
      function_call: {implementation, function_name}
    }
    |> struct!(behaviour.__functions__(function_name))
    |> then(&OpenAPIClient.set_state(conn, &1))
  end

  # Taken from https://elixirforum.com/t/is-it-possible-to-detect-if-code-is-executing-at-compile-time/57728/11
  defp compiling?() do
    case Process.get(:elixir_compiler_pid) do
      nil -> false
      pid when is_pid(pid) -> true
    end
  end

  defp is_module?(atom) do
    if compiling?() do
      match?({:module, _module}, Code.ensure_compiled(atom))
    else
      OpenAPIClient.Utils.is_module?(atom)
    end
  end
end

defmodule OpenAPIClient.Utils do
  @spec is_module?(atom()) :: boolean()
  def is_module?(atom) when is_atom(atom) do
    Code.ensure_loaded(atom)
    function_exported?(atom, :module_info, 1)
  end

  @spec does_implement_behaviour?(module(), atom()) :: boolean()
  def does_implement_behaviour?(module, behaviour) when is_atom(behaviour) do
    (module.module_info(:attributes) || [])
    |> Keyword.get(:behaviour, [])
    |> Enum.member?(behaviour)
  end

  @spec get_config(OpenAPIClient.Client.Operation.t() | atom(), atom(), term()) :: term()
  @spec get_config(OpenAPIClient.Client.Operation.t() | atom(), atom()) :: term()
  def get_config(operation_or_profile, key, default \\ nil)

  def get_config(
        %OpenAPIClient.Client.Operation{assigns: %{private: %{__profile__: profile}}},
        key,
        default
      ) do
    get_config(profile, key, default)
  end

  def get_config(profile, key, default) do
    app_data = Process.get(:open_api_client_ex)

    case get_in(app_data, [:config_cache, profile]) do
      nil ->
        :open_api_client_ex
        |> Application.get_env(:"$base", [])
        |> config_merge(Application.get_env(:open_api_client_ex, profile, []))
        |> tap(
          &Process.put(
            :open_api_client_ex,
            put_in(app_data || %{}, [Access.key(:config_cache, %{}), profile], &1)
          )
        )
        |> Keyword.get(key, default)

      config ->
        Keyword.get(config, key, default)
    end
  end

  @spec config_merge(list(), list()) :: list()
  def config_merge(config1, []) when is_list(config1), do: config1
  def config_merge([], config2) when is_list(config2), do: config2

  def config_merge(config1, config2) when is_list(config1) and is_list(config2),
    do: do_merge(config2, [], config1)

  defp do_merge([{key, value2} | tail], acc, rest) do
    case List.keyfind(rest, key, 0) do
      {^key, value1} ->
        acc = [{key, deep_merge(key, value1, value2)} | acc]
        rest = List.keydelete(rest, key, 0)
        do_merge(tail, acc, rest)

      nil ->
        do_merge(tail, [{key, value2} | acc], rest)
    end
  end

  defp do_merge([], acc, rest) do
    rest ++ :lists.reverse(acc)
  end

  defp deep_merge(_key, value1, value2) do
    if is_key_value_list?(value1) and is_key_value_list?(value2) do
      config_merge(value1, value2)
    else
      value2
    end
  end

  defp is_key_value_list?([]), do: true

  defp is_key_value_list?([{_, _} | _] = list) do
    Enum.all?(list, fn
      {_, _} -> true
      _ -> false
    end)
  end

  defp is_key_value_list?(_), do: false
end

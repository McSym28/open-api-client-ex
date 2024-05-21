defmodule OpenAPIClient.Generator.Utils do
  @spec operation_config(atom(), String.t() | URI.t(), OpenAPI.Processor.Operation.method()) ::
          keyword()
  def operation_config(profile, url, method) do
    :open_api_client_ex
    |> Application.get_env(profile, [])
    |> Keyword.get(:operations, [])
    |> Enum.flat_map(fn {pattern, config} ->
      if pattern_match?(pattern, url, method) do
        [config]
      else
        []
      end
    end)
    |> Enum.reduce([], &merge_config/2)
  end

  @doc """
  Return AST representation of a function call

  ## Examples

      iex> Application |> #{__MODULE__}.ast_function_call(:get_all_env, []) |> Macro.to_string()
      "Application.get_all_env()"
      iex> :application |> #{__MODULE__}.ast_function_call(:get_all_env, []) |> Macro.to_string()
      ":application.get_all_env()"
      iex> IO.Stream |> #{__MODULE__}.ast_function_call(:black, []) |> Macro.to_string()
      "IO.Stream.black()"

  """
  @spec ast_function_call(module(), atom(), list()) :: Macro.t()
  def ast_function_call(module, function, args)
      when is_atom(module) and is_atom(function) and is_list(args) do
    {{:., [], [ast_module(module), function]}, [], args}
  end

  @spec ensure_ets_table(atom()) :: :ets.table()
  def ensure_ets_table(name) do
    case :ets.whereis(name) do
      :undefined -> :ets.new(name, [:set, :public, :named_table])
      tid -> tid
    end
  end

  defp pattern_match?(pattern, url, method) do
    case pattern do
      :all ->
        true

      {%Regex{} = regex, pattern_method}
      when pattern_method == :all or pattern_method == method ->
        Regex.match?(regex, url)

      {^url, pattern_method} when pattern_method == :all or pattern_method == method ->
        true

      _ ->
        false
    end
  end

  defp merge_config([], list2) when is_list(list2), do: list2
  defp merge_config(list1, []) when is_list(list1), do: list1

  defp merge_config([{key1, _} | _] = list1, [{key2, _} | _] = list2)
       when is_atom(key1) and is_atom(key2),
       do: Keyword.merge(list1, list2, fn _, v1, v2 -> merge_config(v1, v2) end)

  defp merge_config([{_, _} | _] = list1, [{_, _} | _] = list2) do
    list1
    |> Map.new()
    |> merge_config(Map.new(list2))
    |> Keyword.new()
  end

  defp merge_config(%{} = map1, %{} = map2),
    do: Map.merge(map1, map2, fn _, v1, v2 -> merge_config(v1, v2) end)

  defp merge_config(_v1, v2), do: v2

  defp ast_module(module) when is_atom(module) do
    case Macro.classify_atom(module) do
      :identifier ->
        module

      :alias ->
        {:__aliases__, [alias: false], module |> Module.split() |> Enum.map(&String.to_atom/1)}
    end
  end
end

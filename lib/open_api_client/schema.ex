defmodule OpenAPIClient.Schema do
  @typedoc "Type annotation produced by [OpenAPI](https://github.com/aj-foster/open-api-generator)"
  @type non_array_type() ::
          :binary
          | :boolean
          | :integer
          | :map
          | :number
          | {:string, atom()}
          | :unknown
          | {:union, [type()]}
          | {:enum, [{atom(), String.t()} | :not_strict]}
          | {module(), atom()}
  @type type() :: non_array_type() | [non_array_type()]

  @callback to_map(struct :: struct()) :: map()
  @callback from_map(map :: map()) :: struct()
  @callback __fields__(atom()) :: %{optional(String.t()) => type()}

  defp enum_conversion(value, renamings, reverse) do
    clauses =
      Enum.map(renamings, fn
        {key, value} when reverse -> quote(do: (unquote(value) -> unquote(key))) |> hd()
        {key, value} -> quote(do: (unquote(key) -> unquote(value))) |> hd()
        :not_strict -> quote(do: (value -> value)) |> hd()
      end)

    quote do
      case unquote(value) do
        unquote(clauses)
      end
    end
  end

  @type enum_renamings :: [{atom(), String.t()} | :not_strict]

  @spec enum_to_map(term(), enum_renamings()) :: Macro.t()
  defmacro enum_to_map(value, renamings) do
    enum_conversion(value, renamings, false)
  end

  @spec enum_from_map(term(), enum_renamings()) :: Macro.t()
  defmacro enum_from_map(value, renamings) do
    enum_conversion(value, renamings, true)
  end

  defp enum_clauses(clauses, to_map) do
    Enum.map(clauses, fn
      {key, value} when to_map -> quote(do: (unquote(key) -> unquote(value))) |> hd()
      {key, value} -> quote(do: (unquote(value) -> unquote(key))) |> hd()
      :not_strict -> quote(do: (value -> value)) |> hd()
    end)
  end

  defp to_map_type(variable, {:enum, clauses}) do
    quote do
      case unquote(variable) do
        unquote(enum_clauses(clauses, true))
      end
    end
  end

  defp to_map_type(variable, enum: clauses) do
    quote do
      Enum.map(unquote(variable), unquote({:fn, [], enum_clauses(clauses, true)}))
    end
  end

  defp to_map_type(variable, {module, _type}) when is_atom(module) do
    if Macro.classify_atom(module) == :alias do
      quote do
        unquote(module).to_map(unquote(variable))
      end
    else
      to_map_type(variable, :unknown)
    end
  end

  defp to_map_type(variable, [{module, _type}]) when is_atom(module) do
    if Macro.classify_atom(module) == :alias do
      quote do
        Enum.map(unquote(variable), &unquote(module).to_map/1)
      end
    else
      to_map_type(variable, [:unknown])
    end
  end

  defp to_map_type(variable, _type), do: variable

  defmacro to_map(value, struct, fields) do
    {struct_pairs, map_pairs} =
      fields
      |> Macro.expand(__CALLER__)
      |> elem(2)
      |> Enum.map(fn {name, {old_name, type}} ->
        variable = Macro.var(name, nil)

        {
          {name, variable},
          {old_name, to_map_type(variable, type)}
        }
      end)
      |> Enum.unzip()

    quote do
      %unquote(struct){unquote_splicing(struct_pairs)} = unquote(value)
      %{unquote_splicing(map_pairs)}
    end
  end
end

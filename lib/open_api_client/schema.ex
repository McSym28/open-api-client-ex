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
          | {:union, [type]}
          | {module, atom}
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
end

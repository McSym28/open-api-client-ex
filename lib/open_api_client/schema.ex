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

  @callback to_map(struct :: struct() | map()) :: map()
  @callback from_map(map :: map(), atom()) :: struct() | map()
  @callback __fields__(atom()) :: %{optional(String.t()) => type()}

  defp enum_clauses(clauses, to_map) do
    Enum.map(clauses, fn
      {key, value} when to_map -> quote(do: (unquote(key) -> unquote(value))) |> hd()
      {key, value} -> quote(do: (unquote(value) -> unquote(key))) |> hd()
      :not_strict -> quote(do: (value -> value)) |> hd()
    end)
  end

  defp map_type(variable, {:enum, clauses}, to_map) do
    quote do
      case unquote(variable) do
        unquote(enum_clauses(clauses, to_map))
      end
    end
  end

  defp map_type(variable, [enum: clauses], to_map) do
    quote do
      Enum.map(unquote(variable), unquote({:fn, [], enum_clauses(clauses, to_map)}))
    end
  end

  defp map_type(variable, {module, _type}, to_map) when is_atom(module) do
    if Macro.classify_atom(module) == :alias do
      function = if to_map, do: :to_map, else: :from_map

      quote do
        unquote(module).unquote(function)(unquote(variable))
      end
    else
      map_type(variable, :unknown, to_map)
    end
  end

  defp map_type(variable, [{module, _type}], to_map) when is_atom(module) do
    if Macro.classify_atom(module) == :alias do
      function = if to_map, do: :to_map, else: :from_map

      quote do
        Enum.map(unquote(variable), &(unquote(module).unquote(function) / 1))
      end
    else
      map_type(variable, [:unknown], to_map)
    end
  end

  defp map_type(variable, _type, _to_map), do: variable

  defmacro to_map(value, fields, struct) do
    clauses =
      fields
      |> Macro.expand(__CALLER__)
      |> elem(2)
      |> Enum.map(fn {name, {old_name, type}} ->
        variable = Macro.var(name, nil)

        {
          {name, variable},
          {old_name, map_type(variable, type, true)}
        }
      end)

    if struct do
      {struct_pairs, map_pairs} = Enum.unzip(clauses)

      quote do
        %unquote(struct){unquote_splicing(struct_pairs)} = unquote(value)
        %{unquote_splicing(map_pairs)}
      end
    else
      clauses =
        clauses
        |> Enum.map(fn {{name, variable}, {old_name, new_value}} ->
          quote(
            do:
              ({unquote(old_name), unquote(variable)} ->
                 [{unquote(name), unquote(new_value)}])
          )
          |> hd()
        end)
        |> Kernel.++(quote(do: (_ -> [])))

      quote do
        unquote(value)
        |> Enum.flat_map(unquote({:fn, [], clauses}))
        |> Map.new()
      end
    end
  end

  defmacro from_map(value, fields, struct) do
    clauses =
      fields
      |> Macro.expand(__CALLER__)
      |> elem(2)
      |> Enum.map(fn {name, {old_name, type}} ->
        variable = Macro.var(name, nil)

        quote(
          do:
            ({unquote(old_name), unquote(variable)} ->
               [{unquote(name), unquote(map_type(variable, type, false))}])
        )
        |> hd()
      end)
      |> Kernel.++(quote(do: (_ -> [])))

    if struct do
      quote do
        unquote(value)
        |> Enum.flat_map(unquote({:fn, [], clauses}))
        |> then(&struct(unquote(struct), &1))
      end
    else
      quote do
        unquote(value)
        |> Enum.flat_map(unquote({:fn, [], clauses}))
        |> Map.new()
      end
    end
  end
end

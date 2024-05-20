defmodule OpenAPIClient.Client.TypedDecoder do
  @doc """
  Manually decode a response

  This function takes a parsed response and decodes it using the given type. It is intended for
  use in testing scenarios only. For regular API requests, use `decode_response/2` as part of the
  client stack.

  Shamelessly stolen from https://github.com/aj-foster/open-api-github

  ## Examples

      iex> #{__MODULE__}.decode("", :null)
      {:ok, nil}
      iex> #{__MODULE__}.decode(nil, {:string, :generic})
      {:ok, nil}
      iex> #{__MODULE__}.decode(true, :boolean)
      {:ok, true}
      iex> #{__MODULE__}.decode("true", :boolean)
      {:ok, true}
      iex> #{__MODULE__}.decode("false", :boolean)
      {:ok, false}
      iex> #{__MODULE__}.decode(1, :boolean)
      {:error, :invalid_boolean}
      iex> #{__MODULE__}.decode(1, :integer)
      {:ok, 1}
      iex> #{__MODULE__}.decode("1", :integer)
      {:ok, 1}
      iex> #{__MODULE__}.decode("1!", :integer)
      {:error, :invalid_integer}
      iex> #{__MODULE__}.decode(1, :number)
      {:ok, 1}
      iex> #{__MODULE__}.decode(1.0, :number)
      {:ok, 1.0}
      iex> #{__MODULE__}.decode("1", :number)
      {:ok, 1.0}
      iex> #{__MODULE__}.decode("1.0", :number)
      {:ok, 1.0}
      iex> #{__MODULE__}.decode("1.0!", :number)
      {:error, :invalid_number}
      iex> #{__MODULE__}.decode("2024-02-03", {:string, :date})
      {:ok, ~D[2024-02-03]}
      iex> #{__MODULE__}.decode("2024-01-01T12:34:56Z", {:string, :date_time})
      {:ok, ~U[2024-01-01 12:34:56Z]}
      iex> #{__MODULE__}.decode("12:34:56Z", {:string, :time})
      {:ok, ~T[12:34:56]}
      iex> #{__MODULE__}.decode("stirng", {:string, :generic})
      {:ok, "stirng"}
      iex> #{__MODULE__}.decode(1, {:string, :generic})
      {:ok, "1"}

  """
  @spec decode(term(), OpenAPIClient.Schema.type()) :: {:ok, term()} | {:error, term()}
  def decode(value, type) do
    do_decode(value, type)
  end

  defp do_decode(nil, _), do: {:ok, nil}
  defp do_decode("", :null), do: {:ok, nil}

  defp do_decode(value, :boolean) when is_boolean(value), do: {:ok, value}
  defp do_decode("true", :boolean), do: {:ok, true}
  defp do_decode("false", :boolean), do: {:ok, false}
  defp do_decode(_value, :boolean), do: {:error, :invalid_boolean}

  defp do_decode(value, :integer) when is_integer(value), do: {:ok, value}

  defp do_decode(value, :integer) when is_binary(value) do
    case Integer.parse(value) do
      {decoded_value, ""} -> {:ok, decoded_value}
      _ -> {:error, :invalid_integer}
    end
  end

  defp do_decode(_value, :integer), do: {:error, :invalid_integer}

  defp do_decode(value, :number) when is_number(value), do: {:ok, value}

  defp do_decode(value, :number) when is_binary(value) do
    case Float.parse(value) do
      {decoded_value, ""} -> {:ok, decoded_value}
      _ -> {:error, :invalid_number}
    end
  end

  defp do_decode(_value, :number), do: {:error, :invalid_number}

  defp do_decode(value, {:string, string_format})
       when not is_binary(value) and string_format in [:date, :date_time, :time],
       do: {:error, :invalid_datetime_string}

  defp do_decode(value, {:string, :date}), do: Date.from_iso8601(value)

  defp do_decode(value, {:string, :date_time}) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _} = error -> error
    end
  end

  defp do_decode(value, {:string, :time}), do: Time.from_iso8601(value)

  defp do_decode(value, {:string, _} = type) when is_number(value) or is_atom(value),
    do: do_decode(to_string(value), type)

  defp do_decode(value, {:string, _}) when not is_binary(value),
    do: {:error, :invalid_string}

  defp do_decode(value, {:union, types}) do
    case choose_union(value, types) do
      {:ok, type} -> do_decode(value, type)
      {:error, _} = error -> error
    end
  end

  defp do_decode(value, [_type]) when not is_list(value), do: {:error, :invalid_list}

  defp do_decode(value, [type]) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item_value, index}, {:ok, acc} ->
      case do_decode(item_value, type) do
        {:ok, decoded_value} -> {:cont, {:ok, [decoded_value | acc]}}
        {:error, message} -> {:halt, {:error, {index, message}}}
      end
    end)
    |> case do
      {:ok, decoded_value} -> {:ok, Enum.reverse(decoded_value)}
      {:error, _} = error -> error
    end
  end

  defp do_decode(value, {module, type}) when is_atom(module) and is_atom(type) do
    (module.module_info(:attributes) || [])
    |> Keyword.get(:behaviour, [])
    |> Enum.member?(OpenAPIClient.Schema)
    |> if do
      fields = module.__fields__(type)

      value
      |> Enum.reduce_while({:ok, %{}}, fn {name, field_value}, {:ok, acc} ->
        case Map.fetch(fields, name) do
          {:ok, field_type} ->
            case do_decode(field_value, field_type) do
              {:ok, decoded_value} -> {:cont, {:ok, Map.put(acc, name, decoded_value)}}
              {:error, message} -> {:halt, {:error, {name, message}}}
            end

          :error ->
            {:cont, {:ok, acc}}
        end
      end)
      |> case do
        {:ok, decoded_value} -> {:ok, module.from_map(decoded_value)}
        {:error, _} = error -> error
      end
    else
      do_decode(value, nil)
    end
  end

  defp do_decode(value, :map) when not is_map(value), do: {:error, :invalid_map}

  defp do_decode(value, _type), do: {:ok, value}

  #
  # Union Type Handlers
  #

  defp choose_union(nil, [_type, :null]), do: {:ok, :null}
  defp choose_union(nil, [:null, _type]), do: {:ok, :null}
  defp choose_union(_value, [type, :null]), do: {:ok, type}
  defp choose_union(_value, [:null, type]), do: {:ok, type}

  defp choose_union(%{}, [:map, {:string, :generic}]), do: {:ok, :map}
  defp choose_union(_value, [:map, {:string, :generic}]), do: {:ok, {:string, :generic}}

  defp choose_union(value, [:number, {:string, :generic}]) when is_number(value),
    do: {:ok, :number}

  defp choose_union(_value, [:number, {:string, :generic}]), do: {:ok, {:string, :generic}}

  defp choose_union(value, [{:string, :generic}, [string: :generic]])
       when is_list(value) or is_binary(value) do
    cond do
      is_list(value) -> {:ok, [string: :generic]}
      is_binary(value) -> {:ok, {:string, :generic}}
    end
  end

  defp choose_union(value, [:integer, {:string, :generic}, [string: :generic], :null])
       when is_nil(value) or is_integer(value) or is_binary(value) or is_list(value) do
    cond do
      is_nil(value) -> {:ok, :null}
      is_integer(value) -> {:ok, :integer}
      is_binary(value) -> {:ok, {:string, :generic}}
      is_list(value) -> {:ok, [string: :generic]}
    end
  end

  defp choose_union(value, [
         :map,
         {:string, :generic},
         [{:string, :generic}]
       ])
       when is_binary(value) or is_map(value) or is_list(value) do
    cond do
      is_binary(value) -> {:ok, {:string, :generic}}
      is_map(value) -> {:ok, :map}
      is_list(value) -> {:ok, [string: :generic]}
    end
  end

  defp choose_union(value, [
         :map,
         {:string, :generic},
         [:map],
         [{:string, :generic}]
       ])
       when is_binary(value) or is_map(value) or is_list(value) do
    cond do
      is_binary(value) ->
        {:ok, {:string, :generic}}

      is_map(value) ->
        {:ok, :map}

      is_list(value) ->
        case value do
          [%{} | _] -> {:ok, [:map]}
          _else -> {:ok, [string: :generic]}
        end
    end
  end

  defp choose_union(_value, types) do
    {:error, :unsupported_union}
  end
end

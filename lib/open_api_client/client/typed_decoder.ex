defmodule OpenAPIClient.Client.TypedDecoder do
  alias OpenAPIClient.Utils
  alias OpenAPIClient.Client.Error

  @doc """
  Manually decode a response

  This function takes a parsed response and decodes it using the given type. It is intended for
  use in testing scenarios only. For regular API requests, use `decode_response/2` as part of the
  client stack.

  Taken from [GitHub REST API Client for Elixir library](https://github.com/aj-foster/open-api-github)

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
      iex> {:error, %OpenAPIClient.Client.Error{reason: reason}} = #{__MODULE__}.decode(1, :boolean)
      iex> reason
      :invalid_boolean
      iex> #{__MODULE__}.decode(1, :integer)
      {:ok, 1}
      iex> #{__MODULE__}.decode("1", :integer)
      {:ok, 1}
      iex> {:error, %OpenAPIClient.Client.Error{reason: reason}} = #{__MODULE__}.decode("1!", :integer)
      iex> reason
      :invalid_integer
      iex> #{__MODULE__}.decode(1, :number)
      {:ok, 1}
      iex> #{__MODULE__}.decode(1.0, :number)
      {:ok, 1.0}
      iex> #{__MODULE__}.decode("1", :number)
      {:ok, 1.0}
      iex> #{__MODULE__}.decode("1.0", :number)
      {:ok, 1.0}
      iex> {:error, %OpenAPIClient.Client.Error{reason: reason}} = #{__MODULE__}.decode("1.0!", :number)
      iex> reason
      :invalid_number
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
  @spec decode(term(), OpenAPIClient.Schema.type()) :: {:ok, term()} | {:error, Error.t()}
  def decode(value, type) do
    decode(value, type, [])
  end

  @spec decode(term(), OpenAPIClient.Schema.type(), list()) :: {:ok, term()} | {:error, Error.t()}
  defp decode(nil, _, _), do: {:ok, nil}
  defp decode("", :null, _), do: {:ok, nil}

  defp decode(value, :boolean, _) when is_boolean(value), do: {:ok, value}
  defp decode("true", :boolean, _), do: {:ok, true}
  defp decode("false", :boolean, _), do: {:ok, false}

  defp decode(_value, :boolean, path),
    do:
      {:error,
       Error.new(
         message: "Error while parsing boolean",
         reason: :invalid_boolean,
         source: path
       )}

  defp decode(value, :integer, _) when is_integer(value), do: {:ok, value}

  defp decode(value, :integer, path) when is_binary(value) do
    case Integer.parse(value) do
      {decoded_value, ""} ->
        {:ok, decoded_value}

      _ ->
        {:error,
         Error.new(
           message: "Error while parsing integer from string",
           reason: :invalid_integer,
           source: path
         )}
    end
  end

  defp decode(_value, :integer, path),
    do:
      {:error,
       Error.new(
         message: "Error while parsing integer",
         reason: :invalid_integer,
         source: path
       )}

  defp decode(value, :number, _) when is_number(value), do: {:ok, value}

  defp decode(value, :number, path) when is_binary(value) do
    case Float.parse(value) do
      {decoded_value, ""} ->
        {:ok, decoded_value}

      _ ->
        {:error,
         Error.new(
           message: "Error while parsing number from string",
           reason: :invalid_number,
           source: path
         )}
    end
  end

  defp decode(_value, :number, path),
    do:
      {:error,
       Error.new(
         message: "Error while parsing number",
         reason: :invalid_number,
         source: path
       )}

  defp decode(%Date{} = value, {:string, :date}, _), do: {:ok, value}
  defp decode(%DateTime{} = value, {:string, :date}, _), do: {:ok, DateTime.to_date(value)}
  defp decode(%DateTime{} = value, {:string, :date_time}, _), do: {:ok, value}
  defp decode(%Time{} = value, {:string, :time}, _), do: {:ok, value}
  defp decode(%DateTime{} = value, {:string, :time}, _), do: {:ok, DateTime.to_time(value)}

  defp decode(value, {:string, string_format}, path)
       when not is_binary(value) and string_format in [:date, :date_time, :time],
       do:
         {:error,
          Error.new(
            message: "Invalid format for date/time value",
            reason: :invalid_datetime_string,
            source: path
          )}

  defp decode(value, {:string, :date}, path) do
    case Date.from_iso8601(value) do
      {:ok, decoded_value} ->
        {:ok, decoded_value}

      {:error, reason} ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} ->
            {:ok, DateTime.to_date(datetime)}

          {:error, _} ->
            {:error,
             Error.new(
               message: "Error while parsing date value from string",
               reason: reason,
               source: path
             )}
        end
    end
  end

  defp decode(value, {:string, :date_time}, path) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}

      {:error, reason} ->
        {:error,
         Error.new(
           message: "Error while parsing date-time value from string",
           reason: reason,
           source: path
         )}
    end
  end

  defp decode(value, {:string, :time}, path) do
    case Time.from_iso8601(value) do
      {:ok, decoded_value} ->
        {:ok, decoded_value}

      {:error, reason} ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} ->
            {:ok, DateTime.to_time(datetime)}

          {:error, _} ->
            {:error,
             Error.new(
               message: "Error while parsing time value from string",
               reason: reason,
               source: path
             )}
        end
    end
  end

  defp decode(value, {:string, _} = type, path) when is_number(value) or is_atom(value),
    do: decode(to_string(value), type, path)

  defp decode(value, {:string, _}, path) when not is_binary(value),
    do:
      {:error,
       Error.new(
         message: "Error while parsing string",
         reason: :invalid_string,
         source: path
       )}

  defp decode(value, {:union, types}, path) do
    case choose_union(value, types) do
      {:ok, type} -> decode(value, type)
      {:error, error} -> {:error, %Error{error | source: path}}
    end
  end

  defp decode(value, [_type], path) when not is_list(value),
    do:
      {:error,
       Error.new(
         message: "Error while parsing list",
         reason: :invalid_list,
         source: path
       )}

  defp decode(value, [type], path) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item_value, index}, {:ok, acc} ->
      case decode(item_value, type, [[index] | path]) do
        {:ok, decoded_value} -> {:cont, {:ok, [decoded_value | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, decoded_value} -> {:ok, Enum.reverse(decoded_value)}
      {:error, _} = error -> error
    end
  end

  defp decode(value, {module, type}, path)
       when is_atom(module) and is_atom(type) and is_map(value) do
    if Utils.is_module?(module) and Utils.does_implement_behaviour?(module, OpenAPIClient.Schema) do
      fields = module.__fields__(type)

      value
      |> Enum.reduce_while({:ok, %{}}, fn {name, field_value}, {:ok, acc} ->
        case Map.fetch(fields, name) do
          {:ok, field_type} ->
            case decode(field_value, field_type, [name | path]) do
              {:ok, decoded_value} -> {:cont, {:ok, Map.put(acc, name, decoded_value)}}
              {:error, _} = error -> {:halt, error}
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
      decode(value, :unknown, path)
    end
  end

  defp decode(value, :map, path) when not is_map(value),
    do:
      {:error,
       Error.new(
         message: "Error while parsing map",
         reason: :invalid_map,
         source: path
       )}

  defp decode(value, _type, _), do: {:ok, value}

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

  defp choose_union(_value, _types) do
    {:error,
     Error.new(
       message: "Error while parsing union type",
       reason: :unsupported_union
     )}
  end
end

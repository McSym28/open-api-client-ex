defmodule OpenAPIClient.Client.TypedDecoder do
  alias OpenAPIClient.Utils
  alias OpenAPIClient.Client.Error

  @type result :: {:ok, term()} | {:error, Error.t()}
  @type path ::
          list(
            OpenAPIClient.Schema.type()
            | OpenAPIClient.Schema.schema_type()
            | nonempty_list(non_neg_integer())
            | {OpenAPIClient.Client.Operation.url(), OpenAPIClient.Client.Operation.method()}
          )

  @callback decode(value :: term(), type :: OpenAPIClient.Schema.type()) :: result()
  @callback decode(
              value :: term(),
              type :: OpenAPIClient.Schema.type(),
              path :: path(),
              caller_module :: module()
            ) ::
              result()

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour OpenAPIClient.Client.TypedDecoder

      @impl OpenAPIClient.Client.TypedDecoder
      def decode(value, type) do
        decode(value, type, [type], __MODULE__)
      end
    end
  end

  @behaviour __MODULE__

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
  @impl __MODULE__
  def decode(value, type) do
    decode(value, type, [type], __MODULE__)
  end

  @impl __MODULE__
  def decode(nil, _, _, _), do: {:ok, nil}
  def decode("", :null, _, _), do: {:ok, nil}

  def decode(value, :boolean, _, _) when is_boolean(value), do: {:ok, value}
  def decode("true", :boolean, _, _), do: {:ok, true}
  def decode("false", :boolean, _, _), do: {:ok, false}

  def decode(_value, :boolean, path, _),
    do:
      {:error,
       Error.new(
         message: "Error while decoding boolean",
         reason: :invalid_boolean,
         source: path
       )}

  def decode(value, :integer, _, _) when is_integer(value), do: {:ok, value}

  def decode(value, :integer, path, _) when is_binary(value) do
    case Integer.parse(value) do
      {decoded_value, ""} ->
        {:ok, decoded_value}

      _ ->
        {:error,
         Error.new(
           message: "Error while decoding integer from string",
           reason: :invalid_integer,
           source: path
         )}
    end
  end

  def decode(_value, :integer, path, _),
    do:
      {:error,
       Error.new(
         message: "Error while decoding integer",
         reason: :invalid_integer,
         source: path
       )}

  def decode(value, :number, _, _) when is_number(value), do: {:ok, value}

  def decode(value, :number, path, _) when is_binary(value) do
    case Float.parse(value) do
      {decoded_value, ""} ->
        {:ok, decoded_value}

      _ ->
        {:error,
         Error.new(
           message: "Error while decoding number from string",
           reason: :invalid_number,
           source: path
         )}
    end
  end

  def decode(_value, :number, path, _),
    do:
      {:error,
       Error.new(
         message: "Error while decoding number",
         reason: :invalid_number,
         source: path
       )}

  def decode(%Date{} = value, {:string, :date}, _, _), do: {:ok, value}
  def decode(%DateTime{} = value, {:string, :date}, _, _), do: {:ok, DateTime.to_date(value)}
  def decode(%DateTime{} = value, {:string, :date_time}, _, _), do: {:ok, value}
  def decode(%Time{} = value, {:string, :time}, _, _), do: {:ok, value}
  def decode(%DateTime{} = value, {:string, :time}, _, _), do: {:ok, DateTime.to_time(value)}

  def decode(value, {:string, string_format}, path, _)
      when not is_binary(value) and string_format in [:date, :date_time, :time],
      do:
        {:error,
         Error.new(
           message: "Invalid format for date/time value",
           reason: :invalid_datetime_string,
           source: path
         )}

  def decode(value, {:string, :date}, path, _) do
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
               message: "Error while decoding date value from string",
               reason: reason,
               source: path
             )}
        end
    end
  end

  def decode(value, {:string, :date_time}, path, _) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}

      {:error, reason} ->
        {:error,
         Error.new(
           message: "Error while decoding date-time value from string",
           reason: reason,
           source: path
         )}
    end
  end

  def decode(value, {:string, :time}, path, _) do
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
               message: "Error while decoding time value from string",
               reason: reason,
               source: path
             )}
        end
    end
  end

  def decode(value, {:string, _} = type, path, caller_module)
      when is_number(value) or is_atom(value),
      do: caller_module.decode(to_string(value), type, path, caller_module)

  def decode(value, {:string, _}, path, _) when not is_binary(value),
    do:
      {:error,
       Error.new(
         message: "Error while decoding string",
         reason: :invalid_string,
         source: path
       )}

  def decode(_value, {:union, types}, path, _caller_module),
    do:
      {:error,
       Error.new(
         message: "Error while decoding union type `#{inspect(types)}`",
         reason: :unsupported_type,
         source: path
       )}

  def decode(value, [type], path, caller_module) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item_value, index}, {:ok, acc} ->
      case caller_module.decode(item_value, type, [[index] | path], caller_module) do
        {:ok, decoded_value} -> {:cont, {:ok, [decoded_value | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, decoded_value} -> {:ok, Enum.reverse(decoded_value)}
      {:error, _} = error -> error
    end
  end

  def decode(_value, [_type], path, _),
    do:
      {:error,
       Error.new(
         message: "Error while decoding list",
         reason: :invalid_list,
         source: path
       )}

  def decode(value, {:enum, enum_options}, path, _) do
    enum_options
    |> Enum.find_value(fn
      ^value -> {:ok, value}
      {new_value, ^value} -> {:ok, new_value}
      :not_strict -> {:ok, value}
      _ -> nil
    end)
    |> case do
      {:ok, new_value} ->
        {:ok, new_value}

      nil ->
        {:error,
         Error.new(
           message: "Error while decoding enum",
           reason: :invalid_enum,
           source: path
         )}
    end
  end

  def decode(value, {module, type}, path, caller_module)
      when is_atom(module) and is_atom(type) and is_map(value) do
    if Utils.is_module?(module) and Utils.does_implement_behaviour?(module, OpenAPIClient.Schema) do
      fields =
        type
        |> module.__fields__()
        |> Map.new(fn {new_name, {old_name, type}} -> {old_name, {new_name, type}} end)

      is_struct = function_exported?(module, :__struct__, 0)

      value
      |> Enum.reduce_while({:ok, %{}}, fn {old_name, field_value}, {:ok, acc} ->
        case Map.fetch(fields, old_name) do
          {:ok, {new_name, field_type}} ->
            case caller_module.decode(
                   field_value,
                   field_type,
                   [{old_name, field_type} | path],
                   caller_module
                 ) do
              {:ok, decoded_value} -> {:cont, {:ok, Map.put(acc, new_name, decoded_value)}}
              {:error, _} = error -> {:halt, error}
            end

          :error ->
            {:cont, {:ok, acc}}
        end
      end)
      |> case do
        {:ok, decoded_value} when is_struct -> {:ok, struct(module, decoded_value)}
        {:ok, decoded_value} -> {:ok, decoded_value}
        {:error, _} = error -> error
      end
    else
      caller_module.decode(value, :unknown, path, caller_module)
    end
  end

  def decode(value, :map, path, _) when not is_map(value),
    do:
      {:error,
       Error.new(
         message: "Error while decoding map",
         reason: :invalid_map,
         source: path
       )}

  def decode(value, _type, _, _), do: {:ok, value}
end

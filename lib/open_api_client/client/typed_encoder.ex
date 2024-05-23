defmodule OpenAPIClient.Client.TypedEncoder do
  alias OpenAPIClient.Utils
  alias OpenAPIClient.Client.Error

  @type result :: {:ok, term()} | {:error, Error.t()}
  @type path :: list(String.t() | nonempty_list(integer()))

  @callback encode(value :: term(), type :: OpenAPIClient.Schema.type()) :: result()
  @callback encode(
              value :: term(),
              type :: OpenAPIClient.Schema.type(),
              path :: path(),
              calling_module :: module()
            ) :: result()

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour OpenAPIClient.Client.TypedEncoder

      @impl OpenAPIClient.Client.TypedEncoder
      def encode(value, type) do
        encode(value, type, [], __MODULE__)
      end
    end
  end

  @behaviour __MODULE__

  @impl __MODULE__
  def encode(value, type) do
    encode(value, type, [], __MODULE__)
  end

  @impl __MODULE__
  def encode(nil, _, _, _), do: {:ok, nil}
  def encode("", :null, _, _), do: {:ok, nil}

  def encode(value, :boolean, _, _) when is_boolean(value), do: {:ok, value}

  def encode(_value, :boolean, path, _),
    do:
      {:error,
       Error.new(
         message: "Error while encoding boolean",
         reason: :invalid_boolean,
         source: path
       )}

  def encode(value, :integer, _, _) when is_integer(value), do: {:ok, value}

  def encode(_value, :integer, path, _),
    do:
      {:error,
       Error.new(
         message: "Error while encoding integer",
         reason: :invalid_integer,
         source: path
       )}

  def encode(value, :number, _, _) when is_number(value), do: {:ok, value}

  def encode(_value, :number, path, _),
    do:
      {:error,
       Error.new(
         message: "Error while encoding number",
         reason: :invalid_number,
         source: path
       )}

  def encode(%Date{} = value, {:string, :date}, _, _), do: {:ok, value}
  def encode(%DateTime{} = value, {:string, :date}, _, _), do: {:ok, DateTime.to_date(value)}
  def encode(%DateTime{} = value, {:string, :date_time}, _, _), do: {:ok, value}
  def encode(%Time{} = value, {:string, :time}, _, _), do: {:ok, value}
  def encode(%DateTime{} = value, {:string, :time}, _, _), do: {:ok, DateTime.to_time(value)}

  def encode(value, {:string, string_format}, path, _)
      when not is_binary(value) and string_format in [:date, :date_time, :time],
      do:
        {:error,
         Error.new(
           message: "Invalid format for date/time value",
           reason: :invalid_datetime_string,
           source: path
         )}

  def encode(value, {:string, _}, path, _) when not is_binary(value),
    do:
      {:error,
       Error.new(
         message: "Error while encoding string",
         reason: :invalid_string,
         source: path
       )}

  def encode(value, [_type], path, _) when not is_list(value),
    do:
      {:error,
       Error.new(
         message: "Error while encoding list",
         reason: :invalid_list,
         source: path
       )}

  def encode(value, [type], path, calling_module) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item_value, index}, {:ok, acc} ->
      case calling_module.encode(item_value, type, [[index] | path], calling_module) do
        {:ok, encoded_value} -> {:cont, {:ok, [encoded_value | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, encoded_value} -> {:ok, Enum.reverse(encoded_value)}
      {:error, _} = error -> error
    end
  end

  def encode(value, {:enum, enum_options}, path, _calling_module) do
    enum_options
    |> Enum.find_value(fn
      ^value -> {:ok, value}
      {^value, old_value} -> {:ok, old_value}
      :not_strict -> {:ok, value}
      _ -> nil
    end)
    |> case do
      {:ok, new_value} ->
        {:ok, new_value}

      nil ->
        {:error,
         Error.new(
           message: "Error while encoding enum",
           reason: :invalid_enum,
           source: path
         )}
    end
  end

  def encode(value, {module, type}, path, calling_module)
      when is_atom(module) and is_atom(type) and is_map(value) do
    if Utils.is_module?(module) and Utils.does_implement_behaviour?(module, OpenAPIClient.Schema) do
      fields = module.__fields__(type)

      value
      |> module.to_map(type)
      |> Enum.reduce_while({:ok, %{}}, fn {name, field_value}, {:ok, acc} ->
        case Map.fetch(fields, name) do
          {:ok, field_type} ->
            case calling_module.encode(field_value, field_type, [name | path], calling_module) do
              {:ok, encoded_value} -> {:cont, {:ok, Map.put(acc, name, encoded_value)}}
              {:error, _} = error -> {:halt, error}
            end

          :error ->
            {:cont, {:ok, acc}}
        end
      end)
    else
      calling_module.encode(value, :unknown, path, calling_module)
    end
  end

  def encode(value, :map, path, _) when not is_map(value),
    do:
      {:error,
       Error.new(
         message: "Error while encoding map",
         reason: :invalid_map,
         source: path
       )}

  def encode(value, _type, path, calling_module) when is_struct(value) do
    calling_module.encode(value, :unknown, path, calling_module)
  end

  def encode(value, _, _, _) do
    {:ok, value}
  end
end

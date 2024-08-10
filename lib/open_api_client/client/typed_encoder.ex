defmodule OpenAPIClient.Client.TypedEncoder do
  alias OpenAPIClient.Utils
  alias OpenAPIClient.Client.Error

  @type result :: {:ok, term()} | {:error, Error.t()}
  @type path ::
          list(
            String.t()
            | nonempty_list(non_neg_integer())
            | {:parameter, atom(), String.t()}
            | {:request_body, OpenAPIClient.Client.Operation.content_type() | nil}
            | {:response_body, OpenAPIClient.Client.Operation.response_status_code(),
               OpenAPIClient.Client.Operation.content_type() | nil}
            | {OpenAPIClient.Client.Operation.url(), OpenAPIClient.Client.Operation.method()}
          )

  @callback encode(
              value :: term(),
              type :: OpenAPIClient.Schema.type(),
              path :: path(),
              caller_module :: module()
            ) :: result()

  @behaviour __MODULE__

  @doc """
  Encode a value of a specific type

  ## Examples

      iex> #{__MODULE__}.encode(1, :integer, [], #{__MODULE__})
      {:ok, 1}
      iex> #{__MODULE__}.encode(1, :number, [], #{__MODULE__})
      {:ok, 1}
      iex> #{__MODULE__}.encode(1.0, :number, [], #{__MODULE__})
      {:ok, 1.0}
      iex> #{__MODULE__}.encode(~D[2024-02-03], {:string, :date}, [], #{__MODULE__})
      {:ok, ~D[2024-02-03]}
      iex> #{__MODULE__}.encode("string", {:string, :generic}, [], #{__MODULE__})
      {:ok, "string"}

  Base implementation is copied from [GitHub REST API Client for Elixir library](https://github.com/aj-foster/open-api-github)

  """
  @impl __MODULE__
  def encode(nil, _, _, _), do: {:ok, nil}

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

  def encode(_value, {:string, string_format}, path, _)
      when string_format in [:date, :date_time, :time],
      do:
        {:error,
         Error.new(
           message: "Invalid format for date/time value",
           reason: :invalid_datetime_format,
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

  def encode(_value, {:union, types}, path, _caller_module),
    do:
      {:error,
       Error.new(
         message: "Error while encoding union type `#{inspect(types)}`",
         reason: :unsupported_type,
         source: path
       )}

  def encode(value, [type], path, caller_module) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item_value, index}, {:ok, acc} ->
      case caller_module.encode(item_value, type, [[index] | path], caller_module) do
        {:ok, encoded_value} -> {:cont, {:ok, [encoded_value | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, encoded_value} -> {:ok, Enum.reverse(encoded_value)}
      {:error, _} = error -> error
    end
  end

  def encode(_value, [_type], path, _),
    do:
      {:error,
       Error.new(
         message: "Error while encoding list",
         reason: :invalid_list,
         source: path
       )}

  def encode(value, {:enum, enum_options}, path, _) do
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

  def encode(value, {module, type}, path, caller_module)
      when is_atom(module) and is_atom(type) and is_struct(value) do
    caller_module.encode(Map.from_struct(value), {module, type}, path, caller_module)
  end

  def encode(value, {module, type}, path, caller_module)
      when is_atom(module) and is_atom(type) and is_map(value) do
    if Utils.is_module?(module) and Utils.does_implement_behaviour?(module, OpenAPIClient.Schema) do
      fields =
        type
        |> module.__fields__()
        |> Map.new()

      value
      |> Enum.reduce_while({:ok, %{}}, fn {new_name, field_value}, {:ok, acc} ->
        case Map.fetch(fields, new_name) do
          {:ok, {old_name, field_type}} ->
            case caller_module.encode(
                   field_value,
                   field_type,
                   [old_name | path],
                   caller_module
                 ) do
              {:ok, encoded_value} -> {:cont, {:ok, Map.put(acc, old_name, encoded_value)}}
              {:error, _} = error -> {:halt, error}
            end

          :error ->
            {:cont, {:ok, acc}}
        end
      end)
    else
      caller_module.encode(value, :unknown, path, caller_module)
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

  def encode(value, _type, path, caller_module) when is_struct(value) do
    caller_module.encode(Map.from_struct(value), :unknown, path, caller_module)
  end

  def encode(value, _, _, _) do
    {:ok, value}
  end
end

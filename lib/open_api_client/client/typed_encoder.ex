defmodule OpenAPIClient.Client.TypedEncoder do
  alias OpenAPIClient.Utils
  alias OpenAPIClient.Client.Error

  @type result :: {:ok, term()} | {:error, Error.t()}
  @type path :: list(String.t() | nonempty_list(integer()))

  @callback encode(value :: term()) :: result()
  @callback encode(value :: term(), path :: path(), calling_module :: module()) :: result()

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour OpenAPIClient.Client.TypedEncoder

      @impl OpenAPIClient.Client.TypedEncoder
      def encode(value) do
        encode(value, [], __MODULE__)
      end
    end
  end

  @behaviour __MODULE__

  @impl __MODULE__
  def encode(value) do
    encode(value, [], __MODULE__)
  end

  @impl __MODULE__
  def encode(%module{} = value, _, _) do
    if Utils.is_module?(module) and Utils.does_implement_behaviour?(module, OpenAPIClient.Schema) do
      {:ok, module.to_map(value)}
    else
      {:ok, Map.from_struct(value)}
    end
  end

  def encode(value, path, calling_module) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item_value, index}, {:ok, acc} ->
      case calling_module.encode(item_value, [[index] | path], calling_module) do
        {:ok, encoded_value} -> {:cont, {:ok, [encoded_value | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, encoded_value} -> {:ok, Enum.reverse(encoded_value)}
      {:error, _} = error -> error
    end
  end

  def encode(value, _, _) do
    {:ok, value}
  end
end

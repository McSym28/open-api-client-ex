defmodule OpenAPIClient.Client.TypedEncoder do
  alias OpenAPIClient.Utils
  alias OpenAPIClient.Client.Error

  @spec encode(term()) :: {:ok, term()} | {:error, Error.t()}
  def encode(value) do
    encode(value, [])
  end

  @spec encode(term(), list()) :: {:ok, term()} | {:error, Error.t()}
  def encode(%module{} = value, _) do
    if Utils.is_module?(module) and Utils.does_implement_behaviour?(module, OpenAPIClient.Schema) do
      {:ok, module.to_map(value)}
    else
      {:ok, Map.from_struct(value)}
    end
  end

  def encode(value, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item_value, index}, {:ok, acc} ->
      case encode(item_value, [[index] | path]) do
        {:ok, encoded_value} -> {:cont, {:ok, [encoded_value | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, encoded_value} -> {:ok, Enum.reverse(encoded_value)}
      {:error, _} = error -> error
    end
  end

  def encode(value, _) do
    {:ok, value}
  end
end

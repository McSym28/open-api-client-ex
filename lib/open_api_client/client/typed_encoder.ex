defmodule OpenAPIClient.Client.TypedEncoder do
  alias OpenAPIClient.Utils

  @spec encode(term()) :: {:ok, term()} | {:error, term()}
  def encode(%module{} = value) do
    if Utils.is_module?(module) and Utils.does_implement_behaviour?(module, OpenAPIClient.Schema) do
      {:ok, module.to_map(value)}
    else
      {:ok, Map.from_struct(value)}
    end
  end

  def encode(value) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item_value, index}, {:ok, acc} ->
      case encode(item_value) do
        {:ok, encoded_value} -> {:cont, {:ok, [encoded_value | acc]}}
        {:error, message} -> {:halt, {:error, {index, message}}}
      end
    end)
    |> case do
      {:ok, encoded_value} -> {:ok, Enum.reverse(encoded_value)}
      {:error, _} = error -> error
    end
  end

  def encode(value) do
    {:ok, value}
  end
end

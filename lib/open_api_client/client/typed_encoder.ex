defmodule OpenAPIClient.Client.TypedEncoder do
  @spec encode(term()) :: {:ok, term()} | {:error, term()}
  def encode(%module{} = value) do
    (module.module_info(:attributes) || [])
    |> Keyword.get(:behaviour, [])
    |> Enum.member?(OpenAPIClient.Schema)
    |> if do
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

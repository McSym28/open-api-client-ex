defmodule OpenAPIClient.Generator.Utils do
  @operation_url_pattern_rank_multiplicand 10

  @operation_url_pattern_rank_any 0
  @operation_url_pattern_rank_regex 1
  @operation_url_pattern_rank_exact 2

  @operation_method_pattern_rank_any 0
  @operation_method_pattern_rank_exact 1

  @spec operation_config(
          OpenAPI.Processor.State.t(),
          String.t() | URI.t(),
          OpenAPI.Processor.Operation.method()
        ) ::
          keyword()
  def operation_config(state, url, method) do
    url = to_string(url)

    state
    |> get_config(:operations, [])
    |> Enum.flat_map(fn {pattern, config} ->
      case operation_pattern_rank(pattern, url, method) do
        {:ok, {url_rank, method_rank}} ->
          [{url_rank * @operation_url_pattern_rank_multiplicand + method_rank, config}]

        :error ->
          []
      end
    end)
    |> Enum.sort_by(fn {rank, _config} -> rank end)
    |> Enum.reduce([], fn {_rank, config}, acc ->
      OpenAPIClient.Utils.config_merge(acc, config)
    end)
  end

  @spec ensure_ets_table(atom()) :: :ets.table()
  def ensure_ets_table(name) do
    case :ets.whereis(name) do
      :undefined -> :ets.new(name, [:set, :public, :named_table])
      tid -> tid
    end
  end

  @spec get_config(
          OpenAPI.Processor.State.t() | OpenAPI.Renderer.State.t() | String.t(),
          atom()
        ) :: term()
  @spec get_config(
          OpenAPI.Processor.State.t() | OpenAPI.Renderer.State.t() | atom(),
          atom(),
          term()
        ) :: term()
  def get_config(state, key, default \\ nil)

  def get_config(%OpenAPI.Processor.State{profile: profile}, key, default) do
    get_config(profile, key, default)
  end

  def get_config(%OpenAPI.Renderer.State{profile: profile}, key, default) do
    get_config(profile, key, default)
  end

  def get_config(profile, key, default) when is_atom(profile) do
    OpenAPIClient.Utils.get_config(profile, key, default)
  end

  @spec get_oapi_generator_config(
          OpenAPI.Processor.State.t() | OpenAPI.Renderer.State.t(),
          atom()
        ) :: term()
  @spec get_oapi_generator_config(
          OpenAPI.Processor.State.t() | OpenAPI.Renderer.State.t(),
          atom(),
          term()
        ) :: term()
  def get_oapi_generator_config(state, key, default \\ nil)

  def get_oapi_generator_config(%OpenAPI.Processor.State{profile: profile}, key, default) do
    get_oapi_generator_config_profile(profile, key, default)
  end

  def get_oapi_generator_config(%OpenAPI.Renderer.State{profile: profile}, key, default) do
    get_oapi_generator_config_profile(profile, key, default)
  end

  defp get_oapi_generator_config_profile(profile, key, default) do
    :oapi_generator
    |> Application.get_env(profile, [])
    |> Keyword.get(:output, [])
    |> Keyword.get(key, default)
  end

  defp operation_pattern_rank(:*, _url, _method),
    do: {:ok, {@operation_url_pattern_rank_any, @operation_method_pattern_rank_any}}

  defp operation_pattern_rank({url_pattern, method_pattern}, url, method) do
    case {operation_url_pattern_rank(url_pattern, url),
          operation_method_pattern_rank(method_pattern, method)} do
      {{:ok, url_rank}, {:ok, method_rank}} -> {:ok, {url_rank, method_rank}}
      _ -> :error
    end
  end

  defp operation_url_pattern_rank([], _url), do: :error
  defp operation_url_pattern_rank(:*, _url), do: {:ok, @operation_url_pattern_rank_any}

  defp operation_url_pattern_rank([pattern | rest], url) do
    case operation_url_pattern_rank(pattern, url) do
      {:ok, rank} -> {:ok, rank}
      :error -> operation_url_pattern_rank(rest, url)
    end
  end

  defp operation_url_pattern_rank(%Regex{} = regex, url) do
    if Regex.match?(regex, url) do
      {:ok, @operation_url_pattern_rank_regex}
    else
      :error
    end
  end

  defp operation_url_pattern_rank(url, url), do: {:ok, @operation_url_pattern_rank_exact}
  defp operation_url_pattern_rank(_pattern, _url), do: :error

  defp operation_method_pattern_rank([], _method), do: :error
  defp operation_method_pattern_rank(:*, _method), do: {:ok, @operation_method_pattern_rank_any}

  defp operation_method_pattern_rank([pattern | rest], method) do
    case operation_method_pattern_rank(pattern, method) do
      {:ok, rank} -> {:ok, rank}
      :error -> operation_method_pattern_rank(rest, method)
    end
  end

  defp operation_method_pattern_rank(method, method),
    do: {:ok, @operation_method_pattern_rank_exact}

  defp operation_method_pattern_rank(_pattern, _method), do: :error
end

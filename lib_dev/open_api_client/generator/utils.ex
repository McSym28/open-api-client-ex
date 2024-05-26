defmodule OpenAPIClient.Generator.Utils do
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
      if type = pattern_matched_type(pattern, url, method) do
        [{type, config}]
      else
        []
      end
    end)
    |> Enum.sort_by(fn
      {:all, _} -> 0
      {:regex, _} -> 1
      {:exact, _} -> 2
    end)
    |> Enum.map(fn {_type, config} -> config end)
    |> Enum.reduce(&OpenAPIClient.Utils.config_merge(&2, &1))
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

  defp pattern_matched_type(pattern, url, method) do
    case pattern do
      :all ->
        :all

      {%Regex{} = regex, pattern_method}
      when pattern_method == :all or pattern_method == method ->
        if Regex.match?(regex, url) do
          :regex
        end

      {^url, pattern_method} when pattern_method == :all or pattern_method == method ->
        :exact
    end
  end
end

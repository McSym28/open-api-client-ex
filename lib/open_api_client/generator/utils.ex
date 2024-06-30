if Mix.env() in [:dev, :test] do
  defmodule OpenAPIClient.Generator.Utils do
    @operation_url_pattern_rank_multiplicand 10

    @operation_url_pattern_rank_any 0
    @operation_url_pattern_rank_regex 1
    @operation_url_pattern_rank_exact 2

    @operation_method_pattern_rank_any 0
    @operation_method_pattern_rank_exact 1

    @schema_module_pattern_rank_multiplicand 10

    @schema_module_pattern_rank_any 0
    @schema_module_pattern_rank_regex 1
    @schema_module_pattern_rank_exact 2

    @schema_type_pattern_rank_any 0
    @schema_type_pattern_rank_exact 1

    @type operation_param_config :: [
            {:name, String.t()}
            | {:default, {:profile_config, atom()} | {module(), atom(), list()}}
            | {:example, term()}
          ]
    @type operation_config :: [
            {:params,
             [
               {{String.t(), OpenAPI.Processor.Operation.Param.location()},
                operation_param_config()}
             ]}
          ]

    @type schema_field_enum_config :: [
            {:strict, boolean()} | {:options, [{term(), [{:value, atom()}]}]}
          ]
    @type schema_field_config :: [
            {:name, String.t()} | {:example, term()} | {:enum, schema_field_enum_config()}
          ]
    @type schema_config :: [{:fields, [{String.t(), schema_field_config()}]}]

    @spec operation_config(
            OpenAPI.Processor.State.t(),
            String.t() | URI.t(),
            OpenAPI.Processor.Operation.method()
          ) :: operation_config()
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

    @spec schema_config(
            OpenAPI.Processor.State.t(),
            String.t() | atom(),
            atom() | String.t()
          ) :: schema_config()
    def schema_config(state, module, type) do
      state
      |> get_config(:schemas, [])
      |> Enum.flat_map(fn {pattern, config} ->
        case schema_pattern_rank(pattern, module, type) do
          {:ok, {module_rank, type_rank}} ->
            [{module_rank * @schema_module_pattern_rank_multiplicand + type_rank, config}]

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

    defp schema_pattern_rank(:*, _module, _type),
      do: {:ok, {@schema_module_pattern_rank_any, @schema_type_pattern_rank_any}}

    defp schema_pattern_rank({module_pattern, type_pattern}, module, type) do
      case {schema_module_pattern_rank(module_pattern, module),
            schema_type_pattern_rank(type_pattern, type)} do
        {{:ok, module_rank}, {:ok, type_rank}} -> {:ok, {module_rank, type_rank}}
        _ -> :error
      end
    end

    defp schema_module_pattern_rank([], _module), do: :error
    defp schema_module_pattern_rank(:*, _module), do: {:ok, @schema_module_pattern_rank_any}

    defp schema_module_pattern_rank([pattern | rest], module) do
      case schema_module_pattern_rank(pattern, module) do
        {:ok, rank} -> {:ok, rank}
        :error -> schema_module_pattern_rank(rest, module)
      end
    end

    defp schema_module_pattern_rank(%Regex{} = regex, module) when is_atom(module),
      do: schema_module_pattern_rank(regex, atom_to_string(module))

    defp schema_module_pattern_rank(%Regex{} = regex, module) do
      if Regex.match?(regex, module) do
        {:ok, @schema_module_pattern_rank_regex}
      else
        :error
      end
    end

    defp schema_module_pattern_rank(module, module), do: {:ok, @schema_module_pattern_rank_exact}

    defp schema_module_pattern_rank(pattern, module) when is_binary(pattern) and is_atom(module),
      do: schema_module_pattern_rank(pattern, atom_to_string(module))

    defp schema_module_pattern_rank(pattern, module) when is_atom(pattern) and is_binary(module),
      do: schema_module_pattern_rank(atom_to_string(pattern), module)

    defp schema_module_pattern_rank(_pattern, _module), do: :error

    defp schema_type_pattern_rank([], _type), do: :error
    defp schema_type_pattern_rank(:*, _type), do: {:ok, @schema_type_pattern_rank_any}

    defp schema_type_pattern_rank([pattern | rest], type) do
      case schema_type_pattern_rank(pattern, type) do
        {:ok, rank} -> {:ok, rank}
        :error -> schema_type_pattern_rank(rest, type)
      end
    end

    defp schema_type_pattern_rank(type, type),
      do: {:ok, @schema_type_pattern_rank_exact}

    defp schema_type_pattern_rank(pattern, type) when is_binary(pattern) and is_atom(type),
      do: schema_type_pattern_rank(pattern, atom_to_string(type))

    defp schema_type_pattern_rank(pattern, type) when is_atom(pattern) and is_binary(type),
      do: schema_type_pattern_rank(atom_to_string(pattern), type)

    defp schema_type_pattern_rank(_pattern, _type), do: :error

    defp atom_to_string(atom) do
      if Macro.classify_atom(atom) == :alias do
        atom
        |> Module.split()
        |> Enum.join(".")
      else
        Atom.to_string(atom)
      end
    end
  end
end

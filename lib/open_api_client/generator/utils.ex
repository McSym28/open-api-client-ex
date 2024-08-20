if Mix.env() in [:dev, :test] do
  defmodule OpenAPIClient.Generator.Utils do
    alias OpenAPIClient.Generator.SchemaType

    @pattern_rank_any 0
    @pattern_rank_regex 1
    @pattern_rank_exact 2

    @tuple_pattern_rank_multiplicand 10

    @type any_pattern :: :*
    @type common_pattern :: any_pattern() | Regex.t()

    @type schema_type_enum_config :: [
            {:strict, boolean()} | {:options, [{term(), [{:value, atom()}]}]}
          ]
    @type schema_type_config_option ::
            {:name, String.t()}
            | {:default,
               {:const, term()} | {:profile_config, atom()} | {module(), atom(), list()}}
            | {:example, term()}
            | {:enum, schema_type_enum_config()}

    @type schema_type_config :: [schema_type_config_option()]

    @type operation_param_config :: schema_type_config()

    @type operation_new_param_config_option :: schema_type_config_option() | {:spec, map()}
    @type operation_new_param_config :: operation_new_param_config_option()

    @type operation_param_name_pattern ::
            common_pattern() | String.t() | list(operation_param_name_pattern())
    @type operation_param_location_pattern ::
            common_pattern()
            | OpenAPI.Processor.Operation.Param.location()
            | list(operation_param_location_pattern())

    @type operation_params_config :: [
            {any_pattern() | {operation_param_name_pattern(), operation_param_location_pattern()},
             operation_param_config()}
            | {{String.t(), :new}, operation_new_param_config()}
          ]

    @type operation_config :: [{:params, operation_params_config()}]

    @type schema_field_config :: schema_type_config()
    @type schema_field_name_pattern ::
            common_pattern() | String.t() | list(schema_field_name_pattern())
    @type schema_fields_config :: [{schema_field_name_pattern(), schema_field_config()}]
    @type schema_config :: [{:fields, schema_fields_config()}]

    @spec operation_config(
            OpenAPI.Processor.State.t(),
            String.t() | URI.t(),
            OpenAPI.Processor.Operation.method()
          ) :: operation_config()
    def operation_config(state, url, method) do
      url = to_string(url)

      state
      |> get_config(:operations, [])
      |> build_config({url, method})
    end

    @spec operation_param_config(
            operation_params_config(),
            String.t(),
            OpenAPI.Processor.Operation.Param.location()
          ) :: operation_param_config()
    def operation_param_config(config, name, location) do
      build_config(config, {name, location})
    end

    @spec schema_config(
            OpenAPI.Processor.State.t(),
            String.t() | atom(),
            atom() | String.t()
          ) :: schema_config()
    def schema_config(state, module, type) do
      state
      |> get_config(:schemas, [])
      |> build_config({module, type})
    end

    @spec schema_field_config(schema_fields_config(), String.t()) :: schema_field_config()
    def schema_field_config(config, name) do
      build_config(config, name)
    end

    @spec ensure_ets_table(atom()) :: :ets.table()
    def ensure_ets_table(name) do
      case :ets.whereis(name) do
        :undefined -> :ets.new(name, [:set, :public, :named_table])
        tid -> tid
      end
    end

    @spec get_config(
            OpenAPI.Processor.State.t()
            | OpenAPI.Renderer.State.t()
            | OpenAPIClient.Generator.TestRenderer.State.t()
            | String.t(),
            atom()
          ) :: term()
    @spec get_config(
            OpenAPI.Processor.State.t()
            | OpenAPI.Renderer.State.t()
            | OpenAPIClient.Generator.TestRenderer.State.t()
            | atom(),
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

    def get_config(
          %OpenAPIClient.Generator.TestRenderer.State{renderer_state: renderer_state},
          key,
          default
        ) do
      get_config(renderer_state, key, default)
    end

    def get_config(profile, key, default) when is_atom(profile) do
      OpenAPIClient.Utils.get_config(profile, key, default)
    end

    @spec get_oapi_generator_config(
            OpenAPI.Processor.State.t()
            | OpenAPI.Renderer.State.t()
            | OpenAPIClient.Generator.TestRenderer.State.t(),
            atom()
          ) :: term()
    @spec get_oapi_generator_config(
            OpenAPI.Processor.State.t()
            | OpenAPI.Renderer.State.t()
            | OpenAPIClient.Generator.TestRenderer.State.t(),
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

    def get_oapi_generator_config(
          %OpenAPIClient.Generator.TestRenderer.State{renderer_state: renderer_state},
          key,
          default
        ) do
      get_oapi_generator_config(renderer_state, key, default)
    end

    @spec schema_type_to_readable_type(
            OpenAPI.Renderer.State.t() | OpenAPIClient.Generator.TestRenderer.State.t(),
            OpenAPI.Processor.Type.t(),
            SchemaType.t()
          ) :: OpenAPIClient.Schema.type()
    def schema_type_to_readable_type(
          _state,
          {:enum, _},
          %SchemaType{enum: %SchemaType.Enum{options: enum_options, strict: true}}
        ),
        do: {:enum, enum_options}

    def schema_type_to_readable_type(
          _state,
          {:enum, _},
          %SchemaType{enum: %SchemaType.Enum{options: enum_options}}
        ),
        do: {:enum, enum_options ++ [:not_strict]}

    def schema_type_to_readable_type(
          state,
          {:array, {:enum, _} = enum},
          schema_type
        ),
        do: [schema_type_to_readable_type(state, enum, schema_type)]

    def schema_type_to_readable_type(
          %OpenAPIClient.Generator.TestRenderer.State{renderer_state: renderer_state},
          type,
          schema_type
        ),
        do: schema_type_to_readable_type(renderer_state, type, schema_type)

    def schema_type_to_readable_type(state, type, _schema_type),
      do: OpenAPI.Renderer.Util.to_readable_type(state, type)

    defp get_oapi_generator_config_profile(profile, key, default) do
      :oapi_generator
      |> Application.get_env(profile, [])
      |> Keyword.get(:output, [])
      |> Keyword.get(key, default)
    end

    defp build_config(config, value_or_tuple) when is_list(config) do
      config
      |> filter_config(value_or_tuple)
      |> Enum.sort_by(fn {rank, _config} -> rank end)
      |> Enum.reduce([], fn {_rank, config}, acc ->
        OpenAPIClient.Utils.config_merge(acc, config)
      end)
    end

    defp filter_config(pattern_config, {_first, _second} = tuple) do
      Enum.flat_map(pattern_config, fn {pattern, config} ->
        case tuple_pattern_rank(pattern, tuple) do
          {:ok, {first_rank, second_rank}} ->
            [{first_rank * @tuple_pattern_rank_multiplicand + second_rank, config}]

          :error ->
            []
        end
      end)
    end

    defp filter_config(pattern_config, value) do
      Enum.flat_map(pattern_config, fn {pattern, config} ->
        case pattern_rank(pattern, value) do
          {:ok, rank} -> [{rank, config}]
          :error -> []
        end
      end)
    end

    defp tuple_pattern_rank(:*, {_first, _second}),
      do: {:ok, {@pattern_rank_any, @pattern_rank_any}}

    defp tuple_pattern_rank({first_pattern, second_pattern}, {first, second}) do
      case {pattern_rank(first_pattern, first), pattern_rank(second_pattern, second)} do
        {{:ok, first_rank}, {:ok, second_rank}} -> {:ok, {first_rank, second_rank}}
        _ -> :error
      end
    end

    defp pattern_rank([], _value), do: :error
    defp pattern_rank(:*, _value), do: {:ok, @pattern_rank_any}
    defp pattern_rank(value, value), do: {:ok, @pattern_rank_exact}

    defp pattern_rank([pattern | rest], value) do
      case pattern_rank(pattern, value) do
        {:ok, rank} -> {:ok, rank}
        :error -> pattern_rank(rest, value)
      end
    end

    defp pattern_rank(%Regex{} = regex, value) when is_atom(value),
      do: pattern_rank(regex, atom_to_string(value))

    defp pattern_rank(%Regex{} = regex, value) do
      if Regex.match?(regex, value) do
        {:ok, @pattern_rank_regex}
      else
        :error
      end
    end

    defp pattern_rank(pattern, value) when is_binary(pattern) and is_atom(value),
      do: pattern_rank(pattern, atom_to_string(value))

    defp pattern_rank(pattern, value) when is_atom(pattern) and is_binary(value),
      do: pattern_rank(atom_to_string(pattern), value)

    defp pattern_rank(_pattern, _value), do: :error

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

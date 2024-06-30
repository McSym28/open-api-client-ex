if Mix.env() in [:dev, :test] do
  defmodule OpenAPIClient.Generator.Processor do
    use OpenAPI.Processor
    alias OpenAPI.Processor.{Operation.Param, Schema}
    alias Schema.Field
    alias OpenAPI.Spec.Path.Operation, as: OperationSpec
    alias OpenAPI.Spec.Path.Parameter, as: ParamSpec
    alias OpenAPI.Spec.Schema, as: SchemaSpec
    alias OpenAPI.Spec.RequestBody
    alias OpenAPIClient.Generator.Utils
    alias OpenAPIClient.Generator.Operation, as: GeneratorOperation
    alias OpenAPIClient.Generator.Param, as: GeneratorParam
    alias OpenAPIClient.Generator.Schema, as: GeneratorSchema
    alias OpenAPIClient.Generator.Field, as: GeneratorField
    require Logger

    @impl true
    def ignore_operation?(
          state,
          %OperationSpec{
            "$oag_path": request_path,
            "$oag_path_parameters": params_from_path,
            parameters: params_from_operation
          } = operation_spec
        ) do
      if OpenAPI.Processor.Ignore.ignore_operation?(state, operation_spec) do
        true
      else
        request_method = OpenAPI.Processor.Operation.request_method(state, operation_spec)

        operation_config = Utils.operation_config(state, request_path, request_method)
        param_configs = Keyword.get(operation_config, :params, [])

        {all_params, param_renamings} =
          (params_from_path ++ params_from_operation)
          |> Enum.reverse()
          |> Enum.map_reduce(%{}, fn %ParamSpec{required: required} = param_spec,
                                     param_renamings ->
            {_state, %Param{name: name, location: location, description: description} = param} =
              Param.from_spec(state, param_spec)

            {_, config} = List.keyfind(param_configs, {name, location}, 0, {name, []})

            name_new =
              Keyword.get_lazy(config, :name, fn -> snakesize_name(name) end)

            default =
              config
              |> Keyword.get(:default)
              |> generate_function_call(state)

            examples =
              config
              |> Keyword.fetch(:example)
              |> case do
                {:ok, value} -> [value]
                :error -> []
              end

            description_new =
              if name_new == name do
                description
              else
                ["[#{inspect(name)}]", description]
                |> Enum.reject(&is_nil/1)
                |> Enum.join(" ")
              end

            description_new =
              if default do
                [
                  description_new,
                  "Default value obtained through a call to `#{Macro.to_string(default)}`"
                ]
                |> Enum.reject(&is_nil/1)
                |> Enum.join(". ")
              else
                description_new
              end

            param_new = %Param{param | name: name_new, description: description_new}

            param_renamings_new = Map.put(param_renamings, {name, location}, name_new)

            generator_param_new =
              %GeneratorParam{
                param: param_new,
                old_name: name,
                default: default,
                config: config,
                static: is_nil(default) and (required or location == :path),
                examples: examples
              }
              |> append_param_example(param_spec, state)

            {generator_param_new, param_renamings_new}
          end)

        all_params =
          Enum.sort_by(all_params, fn %GeneratorParam{
                                        param: %Param{name: name, location: location}
                                      } ->
            location_integer =
              case location do
                :path -> 0
                :query -> 1
                :header -> 2
                _ -> 100
              end

            {location_integer, name}
          end)

        operations_table = Utils.ensure_ets_table(:operations)

        :ets.insert(
          operations_table,
          {{request_path, request_method},
           %GeneratorOperation{
             config: operation_config,
             spec: operation_spec,
             params: all_params,
             param_renamings: param_renamings
           }}
        )

        false
      end
    end

    @impl true
    def operation_docstring(
          state,
          %OperationSpec{"$oag_path": request_path, request_body: request_body} = operation_spec,
          query_params
        ) do
      request_method = OpenAPI.Processor.Operation.request_method(state, operation_spec)

      case :ets.lookup(:operations, {request_path, request_method}) do
        [{_, %GeneratorOperation{params: all_params}}] ->
          {static_params, dynamic_params} =
            all_params
            |> Enum.group_by(
              fn %GeneratorParam{static: static} -> static end,
              fn %GeneratorParam{param: param} -> param end
            )
            |> then(fn map -> {Map.get(map, true, []), Map.get(map, false, [])} end)

          body_param =
            case request_body do
              %RequestBody{description: description} ->
                [
                  %Param{
                    description: description,
                    location: :query,
                    name: "body",
                    value_type: :null
                  }
                ]

              _ ->
                []
            end

          client_pipeline_description =
            "Client pipeline for making a request. Default value obtained through a call to `OpenAPIClient.Utils.get_config(__operation__, :client_pipeline)}"

          additional_dynamic_params = [
            %Param{
              description: "Request's base URL. Default value is taken from `@base_url`",
              location: :header,
              name: "base_url",
              value_type: :null
            },
            %Param{
              description: client_pipeline_description,
              location: :header,
              name: "client_pipeline",
              value_type: :null
            }
          ]

          static_params = static_params ++ body_param
          dynamic_params = dynamic_params ++ additional_dynamic_params

          result =
            OpenAPI.Processor.Operation.docstring(
              state,
              operation_spec,
              static_params ++ dynamic_params
            )

          if length(static_params) > 0 do
            [%Param{name: name} | _] = dynamic_params

            result
            |> String.replace("## Options", "## Arguments", global: false)
            |> String.replace("  * `#{name}`:", "\n## Options\n\n  * `#{name}`:", global: false)
          else
            result
          end

        [] ->
          OpenAPI.Processor.Operation.docstring(
            state,
            operation_spec,
            query_params
          )
      end
    end

    @impl true
    def schema_module_and_type(state, schema) do
      {module, type} = OpenAPI.Processor.schema_module_and_type(state, schema)
      process_schema(state, %Schema{schema | module_name: module, type_name: type}, [])
      {module, type}
    end

    defp accumulate_schema_examples(nil, acc, _state), do: acc

    defp accumulate_schema_examples(
           %SchemaSpec{properties: properties, example: example},
           acc,
           state
         ) do
      Enum.reduce(
        properties,
        accumulate_schema_examples(example, acc, state),
        fn {name, property}, acc -> accumulate_schema_examples({name, property}, acc, state) end
      )
    end

    defp accumulate_schema_examples(map, acc, _state) when is_map(map) do
      Enum.reduce(
        map,
        acc,
        fn
          {_name, nil}, acc -> acc
          {name, example}, acc -> Map.update(acc, name, [example], &[example | &1])
        end
      )
    end

    defp accumulate_schema_examples({_name, %SchemaSpec{example: nil}}, acc, _state), do: acc

    defp accumulate_schema_examples(
           {_name,
            %SchemaSpec{
              type: "array",
              items: %SchemaSpec{type: "object"} = _items_spec
            }},
           acc,
           _state
         ) do
      acc
    end

    defp accumulate_schema_examples({name, %SchemaSpec{example: example}}, acc, _state) do
      Map.update(acc, name, [example], &[example | &1])
    end

    defp accumulate_schema_examples({_name, {:ref, _schema_path}}, acc, _state) do
      acc
    end

    def process_schema_examples(%GeneratorSchema{fields: fields} = schema, examples, state) do
      examples =
        Enum.reduce(examples, %{}, fn example, acc ->
          accumulate_schema_examples(example, acc, true)
        end)

      fields_new =
        Enum.map(fields, fn %GeneratorField{old_name: name} = field ->
          case Map.fetch(examples, name) do
            {:ok, field_examples} -> append_field_examples(field, field_examples, state)
            :error -> field
          end
        end)

      %GeneratorSchema{schema | fields: fields_new}
    end

    defp process_schema(
           %OpenAPI.Processor.State{schema_specs_by_ref: schema_specs_by_ref} = state,
           %Schema{ref: ref, fields: fields, module_name: module_name, type_name: type_name},
           examples
         ) do
      schemas_table = Utils.ensure_ets_table(:schemas)

      case :ets.lookup(schemas_table, ref) do
        [{_, %GeneratorSchema{}}] when examples == [] ->
          []

        [{_, %GeneratorSchema{} = generator_schema}] ->
          generator_schema_new = process_schema_examples(generator_schema, examples, state)
          :ets.insert(schemas_table, {ref, generator_schema_new})

        [] ->
          %SchemaSpec{properties: schema_properties} =
            schema_spec = Map.get(schema_specs_by_ref, ref)

          schema_config = Utils.schema_config(state, module_name, type_name)
          field_configs = Keyword.get(schema_config, :fields, [])

          generator_fields =
            Enum.map(fields, fn %Field{name: name} = field ->
              {_, config} = List.keyfind(field_configs, name, 0, {name, []})
              process_field(field, config, Map.get(schema_properties, name), state)
            end)

          extra_fields =
            state
            |> Utils.get_oapi_generator_config(:extra_fields, [])
            |> Enum.map(fn {key, _type} ->
              %GeneratorField{
                old_name: key,
                enforce: true,
                extra: true
              }
            end)

          generator_fields = generator_fields ++ extra_fields

          generator_schema =
            %GeneratorSchema{fields: generator_fields}
            |> process_schema_examples([schema_spec | examples], state)

          :ets.insert(schemas_table, {ref, generator_schema})
      end
    end

    defp process_field(%Field{type: {:enum, enum_values}} = field, config, schema_spec, state) do
      %GeneratorField{field: field_new} =
        generator_field =
        process_field(%Field{field | type: {:string, :generic}}, config, schema_spec, state)

      enum_config = Keyword.get(config, :enum, [])
      enum_options = Keyword.get(enum_config, :options, [])
      enum_strict = Keyword.get(enum_config, :strict, false)

      enum_type =
        with %SchemaSpec{} <- schema_spec,
             {_state, enum_type} <-
               OpenAPI.Processor.Type.from_schema(state, %SchemaSpec{schema_spec | enum: nil}) do
          enum_type
        else
          _ -> :unknown
        end

      {enum_values_new, enum_options} =
        Enum.map_reduce(enum_values, [], &process_enum_value(&1, &2, enum_options))

      type_new = {:enum, enum_values_new}
      field_new = %Field{field_new | type: type_new}

      %GeneratorField{
        generator_field
        | field: field_new,
          enum_options:
            Enum.sort_by(enum_options, fn
              {atom, _string} -> {0, atom}
              value -> {1, value}
            end),
          enum_strict: enum_strict,
          enum_type: enum_type
      }
    end

    defp process_field(
           %Field{type: {:array, {:enum, _} = enum_type}} = field,
           config,
           schema_spec,
           state
         ) do
      items_spec =
        case schema_spec do
          %SchemaSpec{type: "array", items: %SchemaSpec{} = items_spec} -> items_spec
          _ -> nil
        end

      %GeneratorField{field: %Field{type: type_new} = field_new} =
        generator_field =
        process_field(%Field{field | type: enum_type}, config, items_spec, state)

      %GeneratorField{generator_field | field: %Field{field_new | type: {:array, type_new}}}
    end

    defp process_field(
           %Field{name: name, required: required, nullable: nullable} = field,
           config,
           _schema_spec,
           _state
         ) do
      name_new = Keyword.get_lazy(config, :name, fn -> snakesize_name(name) end)
      field_new = %Field{field | name: name_new}

      examples =
        config
        |> Keyword.fetch(:example)
        |> case do
          {:ok, value} -> [value]
          :error -> []
        end

      %GeneratorField{
        field: field_new,
        old_name: name,
        enforce: required and not nullable,
        examples: examples
      }
    end

    defp process_enum_value(value, acc, options) do
      {_, config} = List.keyfind(options, value, 0, {value, []})

      value
      |> is_binary()
      |> if do
        {:ok,
         Keyword.get_lazy(config, :value, fn -> value |> snakesize_name() |> String.to_atom() end)}
      else
        Keyword.fetch(config, :value)
      end
      |> case do
        {:ok, new_value} -> {new_value, [{new_value, value} | acc]}
        :error -> {value, [value | acc]}
      end
    end

    defp append_field_examples(field, [], _state), do: field

    defp append_field_examples(
           %GeneratorField{old_name: name, field: %Field{type: {:array, schema_ref}}} = field,
           examples,
           state
         )
         when is_reference(schema_ref) do
      examples =
        Enum.flat_map(examples, fn
          list when is_list(list) ->
            list

          example ->
            Logger.warning(
              "Unknown example `#{inspect(example)}` for referenced array field `#{name}`"
            )
        end)

      append_referenced_field_examples(
        field,
        schema_ref,
        examples,
        true,
        state
      )
    end

    defp append_field_examples(
           %GeneratorField{field: %Field{type: schema_ref}} = field,
           examples,
           state
         )
         when is_reference(schema_ref) do
      append_referenced_field_examples(
        field,
        schema_ref,
        examples,
        false,
        state
      )
    end

    defp append_field_examples(
           %GeneratorField{examples: examples} = field,
           [example | rest],
           state
         ) do
      %GeneratorField{field | examples: [example | examples]}
      |> append_field_examples(rest, state)
    end

    defp append_referenced_field_examples(field, _schema_path, [], _is_array, _state), do: field

    defp append_referenced_field_examples(
           %GeneratorField{old_name: name} = field,
           schema_ref,
           examples,
           is_array,
           %OpenAPI.Processor.State{schemas_by_ref: schemas_by_ref} = state
         )
         when is_reference(schema_ref) do
      with %Schema{} = schema_by_ref <- Map.get(schemas_by_ref, schema_ref) do
        process_schema(state, schema_by_ref, examples)
      else
        _ ->
          Logger.warning(
            "Unknown schema reference `#{inspect(schema_ref)}` for referenced #{if is_array, do: "array "}field `#{name}`"
          )
      end

      field
    end

    defp append_referenced_field_examples(
           %GeneratorField{field: %Field{name: name}} = field,
           _schema_ref_or_path,
           schema_example,
           is_array,
           _state
         ) do
      Logger.warning(
        "Unknown schema example `#{inspect(schema_example)}` for referenced #{if is_array, do: "array "}field `#{name}`"
      )

      field
    end

    defp append_param_example(param, %ParamSpec{example: example, examples: examples}, state) do
      param
      |> append_param_example(example, state)
      |> then(fn param ->
        Enum.reduce(examples, param, fn
          {_key, %SchemaSpec.Example{value: example}}, param ->
            append_param_example(param, example, state)

          _, param ->
            param
        end)
      end)
    end

    defp append_param_example(param, nil, _state) do
      param
    end

    defp append_param_example(%GeneratorParam{examples: examples} = param, example, _state) do
      %GeneratorParam{param | examples: [example | examples]}
    end

    defp snakesize_name(name), do: Macro.underscore(name)

    defp generate_function_call({:profile_config, key}, state) when is_atom(key) do
      quote do
        OpenAPIClient.Utils.get_config(unquote(state.profile), unquote(key))
      end
    end

    defp generate_function_call({module, function, args}, _state)
         when is_atom(module) and is_atom(function) and is_list(args) do
      quote do
        unquote(module).unquote(function)(unquote_splicing(args))
      end
    end

    defp generate_function_call(nil, _state), do: nil
  end
end

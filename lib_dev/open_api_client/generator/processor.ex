defmodule OpenAPIClient.Generator.Processor do
  use OpenAPI.Processor
  alias OpenAPI.Processor.{Operation.Param, Schema}
  alias Schema.Field
  alias OpenAPI.Spec.Path.Operation, as: OperationSpec
  alias OpenAPI.Spec.Path.Parameter, as: ParamSpec
  alias OpenAPI.Spec.Schema, as: SchemaSpec
  alias OpenAPI.Spec.RequestBody
  alias SchemaSpec.Example
  alias OpenAPIClient.Generator.Utils
  alias OpenAPIClient.Generator.Operation, as: GeneratorOperation
  alias OpenAPIClient.Generator.Param, as: GeneratorParam
  alias OpenAPIClient.Generator.Schema, as: GeneratorSchema
  alias OpenAPIClient.Generator.Field, as: GeneratorField
  require Logger

  @extra_fields :oapi_generator
                |> Application.get_all_env()
                |> Enum.map(fn {key, options} -> {key, options[:output][:extra_fields]} end)
                |> Enum.filter(fn {_key, extra_fields} -> extra_fields end)
                |> Map.new()

  @impl true
  def ignore_operation?(
        %OpenAPI.Processor.State{profile: profile} = state,
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

      operation_config = Utils.operation_config(profile, request_path, request_method)
      param_configs = Keyword.get(operation_config, :params, [])

      {all_params, param_renamings} =
        (params_from_path ++ params_from_operation)
        |> Enum.reverse()
        |> Enum.map_reduce(%{}, fn %ParamSpec{required: required} = param_spec, param_renamings ->
          {_state, %Param{name: name, location: location, description: description} = param} =
            Param.from_spec(state, param_spec)

          {_, config} = List.keyfind(param_configs, {name, location}, 0, {name, []})

          default = Keyword.get(config, :default)

          name_new =
            Keyword.get_lazy(config, :name, fn -> snakesize_name(name) end)

          description_new =
            if name_new == name do
              description
            else
              Enum.join(["[#{inspect(name)}]", description], " ")
            end

          description_new =
            case default do
              {m, f, a} ->
                function_call_string =
                  quote do
                    unquote(m).unquote(f)(unquote_splicing(a))
                  end
                  |> Macro.to_string()

                Enum.join(
                  [
                    description_new,
                    "Default value obtained through a call to `#{function_call_string}`"
                  ],
                  ". "
                )

              _ ->
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
              static: is_nil(default) and (required or location == :path)
            }
            |> append_param_example(param_spec, state)

          {generator_param_new, param_renamings_new}
        end)

      all_params =
        Enum.sort_by(all_params, fn %GeneratorParam{param: %Param{name: name, location: location}} ->
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
        %OpenAPI.Processor.State{profile: profile} = state,
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

        client_pipeline_description = "Client pipeline for making a request"

        client_pipeline_description =
          :open_api_client_ex
          |> Application.get_env(profile, [])
          |> Keyword.get(:client_pipeline)
          |> case do
            {m, f, a} ->
              function_call_string =
                quote do
                  unquote(m).unquote(f)(unquote_splicing(a))
                end
                |> Macro.to_string()

              Enum.join(
                [
                  client_pipeline_description,
                  "Default value obtained through a call to `#{function_call_string}`"
                ],
                ". "
              )

            _ ->
              client_pipeline_description
          end

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
    process_schema(state, schema, nil)
    OpenAPI.Processor.schema_module_and_type(state, schema)
  end

  defp process_schema(
         %OpenAPI.Processor.State{schema_specs_by_ref: schema_specs_by_ref} = state,
         %Schema{ref: ref, fields: fields} = _schema,
         example
       ) do
    schemas_table = Utils.ensure_ets_table(:schemas)

    case :ets.lookup(schemas_table, ref) do
      [{_, %GeneratorSchema{}}] when is_nil(example) ->
        []

      [{_, %GeneratorSchema{fields: generator_fields} = generator_schema}] ->
        generator_fields_new =
          Enum.map(generator_fields, &append_field_example(&1, example, false, state))

        generator_schema_new = %GeneratorSchema{generator_schema | fields: generator_fields_new}
        :ets.insert(schemas_table, {ref, generator_schema_new})

      [] ->
        schema_spec = Map.get(schema_specs_by_ref, ref)

        {generator_fields, schema_fields} =
          Enum.map_reduce(fields, [], fn field, acc ->
            %GeneratorField{field: %Field{name: new_name}, old_name: old_name} =
              generator_field =
              field
              |> process_field()
              |> append_field_example(schema_spec, false, state)
              |> append_field_example(example, false, state)

            acc_new = [
              {String.to_atom(new_name), {old_name, field_to_type(generator_field)}} | acc
            ]

            {generator_field, acc_new}
          end)

        generator_fields =
          generator_fields ++
            Enum.map(@extra_fields, fn {key, type} ->
              %GeneratorField{
                old_name: key,
                type: type,
                enforce: true,
                extra: true
              }
            end)

        :ets.insert(
          schemas_table,
          {ref,
           %GeneratorSchema{
             fields: generator_fields,
             schema_fields: Enum.sort_by(schema_fields, fn {name, _} -> name end)
           }}
        )
    end
  end

  defp process_field(
         %Field{name: name, type: {:enum, enum_values}, required: required, nullable: nullable} =
           field
       ) do
    {enum_values_new, {enum_type, enum_options}} =
      Enum.map_reduce(enum_values, {nil, []}, &process_enum_value/2)

    name_new = snakesize_name(name)
    type_new = {:enum, enum_values_new}
    field_new = %Field{field | name: name_new, type: type_new}

    %GeneratorField{
      field: field_new,
      old_name: name,
      enum_options:
        Enum.sort_by(enum_options, fn
          {atom, _string} -> {0, atom}
          value -> {1, value}
        end),
      type: if(enum_type, do: {:union, [type_new, enum_type]}, else: type_new),
      enforce: required and not nullable
    }
  end

  defp process_field(
         %Field{
           name: name,
           type: {:array, {:enum, enum_values}},
           required: required,
           nullable: nullable
         } =
           field
       ) do
    {enum_values_new, {enum_type, enum_options}} =
      Enum.map_reduce(enum_values, {nil, []}, &process_enum_value/2)

    name_new = snakesize_name(name)
    type_new = {:array, {:enum, enum_values_new}}
    field_new = %Field{field | name: name_new, type: type_new}

    %GeneratorField{
      field: field_new,
      old_name: name,
      enum_options:
        Enum.sort_by(enum_options, fn
          {atom, _string} -> {0, atom}
          value -> {1, value}
        end),
      type: if(enum_type, do: {:array, {:union, [type_new, enum_type]}}, else: type_new),
      enforce: required and not nullable
    }
  end

  defp process_field(
         %Field{name: name, required: required, nullable: nullable, type: type} = field
       ) do
    name_new = snakesize_name(name)
    field_new = %Field{field | name: name_new}

    %GeneratorField{
      field: field_new,
      old_name: name,
      type: type,
      enforce: required and not nullable
    }
  end

  defp process_enum_value(enum_value, {_type, acc}) when is_binary(enum_value) do
    enum_atom = enum_value |> snakesize_name() |> String.to_atom()
    acc_new = [{enum_atom, enum_value} | acc]
    {enum_atom, {{:string, :generic}, acc_new}}
  end

  defp process_enum_value(enum_value, {type, acc})
       when is_number(enum_value) and (is_nil(type) or type in [:integer, :boolean]) do
    acc_new = [enum_value | acc]
    {enum_value, {:number, acc_new}}
  end

  defp process_enum_value(enum_value, {type, acc})
       when is_integer(enum_value) and (is_nil(type) or type in [:boolean]) do
    acc_new = [enum_value | acc]
    {enum_value, {:integer, acc_new}}
  end

  defp process_enum_value(enum_value, {type, acc}) when is_boolean(enum_value) do
    acc_new = [enum_value | acc]
    {enum_value, {type || :boolean, acc_new}}
  end

  defp process_enum_value(enum_value, {type, acc}) do
    acc_new = [enum_value | acc]
    {enum_value, {type, acc_new}}
  end

  defp append_field_example(
         %GeneratorField{old_name: name} = field,
         %SchemaSpec{properties: properties, example: schema_example},
         false,
         state
       ) do
    case Map.get(properties, name) do
      %SchemaSpec{
        type: "array",
        items:
          %SchemaSpec{
            type: "object",
            "$oag_last_ref_file": last_ref_file,
            "$oag_last_ref_path": last_ref_path
          } = _items_spec
      } ->
        append_referenced_field_example(
          field,
          {last_ref_file, last_ref_path},
          schema_example,
          true,
          state
        )

      %SchemaSpec{} = field_spec ->
        field
        |> append_field_example(field_spec, true, state)
        |> append_field_example(schema_example, false, state)

      {:ref, schema_path} ->
        append_referenced_field_example(
          field,
          schema_path,
          schema_example,
          false,
          state
        )
    end
  end

  defp append_field_example(%GeneratorField{old_name: name} = field, %{} = example, false, state) do
    append_field_example(field, Map.get(example, name), true, state)
  end

  defp append_field_example(
         %GeneratorField{field: %Field{name: name}} = field,
         example,
         false,
         state
       )
       when is_list(example) do
    {field_new, valid?} =
      Enum.reduce(example, {field, true}, fn
        map, {field, acc} when is_map(map) ->
          field_new = append_field_example(field, map, false, state)
          {field_new, acc}

        _, {field, _acc} ->
          {field, false}
      end)

    if not valid? do
      Logger.warning("Invalid schema example `#{inspect(example)}` for field `#{name}`")
    end

    field_new
  end

  defp append_field_example(field, %SchemaSpec{example: example}, true, state) do
    append_field_example(field, example, true, state)
  end

  defp append_field_example(%GeneratorField{} = field, nil, _is_field_spec, _state) do
    field
  end

  defp append_field_example(
         %GeneratorField{field: %Field{name: name}} = field,
         example,
         false,
         _state
       ) do
    Logger.warning("Unknown schema example `#{inspect(example)}` for field `#{name}`")
    field
  end

  defp append_field_example(%GeneratorField{examples: examples} = field, example, true, _state) do
    %GeneratorField{field | examples: [example | examples]}
  end

  defp append_referenced_field_example(field, _schema_path, nil, _is_array, _state), do: field

  defp append_referenced_field_example(
         %GeneratorField{old_name: name, field: %Field{name: field_name}} = field,
         schema_path,
         schema_example,
         is_array,
         %OpenAPI.Processor.State{
           schema_refs_by_path: schema_refs_by_path,
           schemas_by_ref: schemas_by_ref
         } = state
       )
       when is_map(schema_example) or is_list(schema_example) do
    with schema_ref when is_reference(schema_ref) <-
           Map.get(schema_refs_by_path, schema_path),
         %Schema{} = schema_by_ref <- Map.get(schemas_by_ref, schema_ref) do
      field_example =
        cond do
          is_map(schema_example) ->
            Map.get(schema_example, name)

          is_list(schema_example) ->
            {field_example, valid?} =
              Enum.flat_map_reduce(schema_example, true, fn
                map, acc when is_map(map) -> {Map.get(schema_example, name), acc}
                _, _acc -> {[], false}
              end)

            if not valid? do
              Logger.warning(
                "Invalid schema example `#{inspect(schema_example)}` for referenced #{if is_array, do: "array "}field `#{field_name}`"
              )
            end

            field_example
        end

      process_schema(state, schema_by_ref, field_example)
    else
      _ ->
        Logger.warning(
          "Unknown schema reference path `#{inspect(schema_path)}` for #{if is_array, do: "array "}field `#{field_name}`"
        )
    end

    field
  end

  defp append_referenced_field_example(
         %GeneratorField{field: %Field{name: name}} = field,
         _schema_path,
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
        {_key, %Example{value: example}}, param -> append_param_example(param, example, state)
        _, param -> param
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

  defp field_to_type(%GeneratorField{
         field: %Field{type: {:enum, _}},
         enum_options: enum_options,
         enum_strict: true
       }),
       do: {:enum, enum_options}

  defp field_to_type(%GeneratorField{field: %Field{type: {:enum, _}}, enum_options: enum_options}),
    do: {:enum, enum_options ++ [:not_strict]}

  defp field_to_type(
         %GeneratorField{field: %Field{type: {:array, {:enum, _} = enum}} = inner_field} = field
       ),
       do:
         {:array, field_to_type(%GeneratorField{field | field: %Field{inner_field | type: enum}})}

  defp field_to_type(%GeneratorField{field: %Field{type: type}}), do: type
end

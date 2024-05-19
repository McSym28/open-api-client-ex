defmodule OpenAPIGenerator.Processor do
  use OpenAPI.Processor
  alias OpenAPI.Processor.{Naming, Operation.Param, Schema}
  alias Schema.Field
  alias OpenAPIGenerator.Utils
  alias OpenAPIGenerator.Operation, as: GeneratorOperation
  alias OpenAPIGenerator.Param, as: GeneratorParam
  alias OpenAPIGenerator.Schema, as: GeneratorSchema
  alias OpenAPI.Spec.Path.Operation, as: OperationSpec
  alias OpenAPI.Spec.Path.Parameter, as: ParamSpec
  alias OpenAPIGenerator.Field, as: GeneratorField
  alias OpenAPI.Spec.RequestBody

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
        |> Enum.map_reduce(%{}, fn %ParamSpec{required: required} = param, param_renamings ->
          {_state, %Param{name: name, location: location, description: description} = param} =
            Param.from_spec(state, param)

          {_, config} = List.keyfind(param_configs, {name, location}, 0, {name, []})

          default = Keyword.get(config, :default)

          name_new =
            Keyword.get_lazy(config, :name, fn -> Naming.normalize_identifier(name) end)

          description_new =
            if name_new == name do
              description
            else
              Enum.join(["[#{inspect(name)}]", description], " ")
            end

          description_new =
            case default do
              {m, f, a} ->
                function_call_string = Utils.ast_function_call(m, f, a) |> Macro.to_string()

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

          generator_param_new = %GeneratorParam{
            param: param_new,
            old_name: name,
            default: default,
            config: config,
            static: is_nil(default) and (required or location == :path)
          }

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

        client_param = [
          %Param{
            description:
              "Client module for making a request. Default value is taken from `@default_client`",
            location: :header,
            name: "client",
            value_type: :null
          }
        ]

        static_params = static_params ++ body_param
        dynamic_params = dynamic_params ++ client_param

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
        |> String.replace(~r/\s+$/, "\n")

      [] ->
        OpenAPI.Processor.Operation.docstring(
          state,
          operation_spec,
          query_params
        )
    end
  end

  @impl true
  def schema_module_and_type(state, %Schema{ref: ref, fields: fields} = schema) do
    {fields_new, field_renamings} = Enum.map_reduce(fields, %{}, &process_field/2)

    fields_new =
      fields_new ++
        Enum.map(@extra_fields, fn {key, type} ->
          %GeneratorField{
            old_name: key,
            type: type,
            enforce: true,
            extra: true
          }
        end)

    schemas_table = Utils.ensure_ets_table(:schemas)

    :ets.insert(
      schemas_table,
      {ref, %GeneratorSchema{fields: fields_new, field_renamings: field_renamings}}
    )

    OpenAPI.Processor.schema_module_and_type(state, schema)
  end

  defp process_field(
         %Field{name: name, type: {:enum, enum_values}, required: required, nullable: nullable} =
           field,
         acc
       ) do
    {enum_values_new, {enum_type, enum_aliases}} =
      Enum.map_reduce(enum_values, {nil, %{}}, &process_enum_value/2)

    name_new = Naming.normalize_identifier(name)
    type_new = {:enum, enum_values_new}
    field_new = %Field{field | name: name_new, type: type_new}

    generator_field = %GeneratorField{
      field: field_new,
      old_name: name,
      enum_aliases: enum_aliases,
      type: if(enum_type, do: {:union, [type_new, enum_type]}, else: type_new),
      enforce: required and not nullable
    }

    acc_new = Map.put(acc, name, name_new)
    {generator_field, acc_new}
  end

  defp process_field(
         %Field{name: name, required: required, nullable: nullable, type: type} = field,
         acc
       ) do
    name_new = Naming.normalize_identifier(name)
    field_new = %Field{field | name: name_new}

    generator_field = %GeneratorField{
      field: field_new,
      old_name: name,
      type: type,
      enforce: required and not nullable
    }

    acc_new = Map.put(acc, name, name_new)
    {generator_field, acc_new}
  end

  defp process_enum_value(enum_value, {_type, acc}) when is_binary(enum_value) do
    enum_atom = enum_value |> Naming.normalize_identifier() |> String.to_atom()
    acc_new = Map.put(acc, enum_atom, enum_value)
    {enum_atom, {{:string, :generic}, acc_new}}
  end

  defp process_enum_value(enum_value, {type, acc})
       when is_number(enum_value) and (is_nil(type) or type in [:integer, :boolean]) do
    {enum_value, {:number, acc}}
  end

  defp process_enum_value(enum_value, {type, acc})
       when is_integer(enum_value) and (is_nil(type) or type in [:boolean]) do
    {enum_value, {:integer, acc}}
  end

  defp process_enum_value(enum_value, {type, acc}) when is_boolean(enum_value) do
    {enum_value, {type || :boolean, acc}}
  end

  defp process_enum_value(enum_value, {type, acc}) do
    {enum_value, {type, acc}}
  end
end

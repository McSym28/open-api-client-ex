defmodule OpenAPIGenerator.Processor do
  use OpenAPI.Processor
  alias OpenAPI.Spec.Path.Operation, as: OperationSpec
  alias OpenAPI.Spec.RequestBody
  alias OpenAPI.Processor.{Naming, Operation.Param}
  alias OpenAPIGenerator.Utils
  alias OpenAPI.Spec.Path.Parameter, as: ParamSpec
  alias OpenAPIGenerator.Operation, as: GeneratorOperation
  alias OpenAPIGenerator.Param, as: GeneratorParam

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
      operations_table = Utils.ensure_ets_table(:operations)

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
end

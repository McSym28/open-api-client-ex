defmodule OpenAPIGenerator.Processor do
  use OpenAPI.Processor
  alias OpenAPI.Spec.Path.Operation, as: OperationSpec
  alias OpenAPI.Spec.RequestBody
  alias OpenAPI.Processor.{Naming, Operation.Param}
  alias OpenAPIGenerator.Utils

  @impl true
  def operation_docstring(
        %OpenAPI.Processor.State{profile: profile} = state,
        %OperationSpec{
          "$oag_path": request_path,
          "$oag_path_parameters": params_from_path,
          parameters: params_from_operation,
          request_body: request_body
        } = operation_spec,
        _query_params
      ) do
    request_method = OpenAPI.Processor.Operation.request_method(state, operation_spec)

    operation_config = Utils.operation_config(profile, request_path, request_method)
    param_configs = Keyword.get(operation_config, :params, [])

    {required_params, optional_params} =
      (params_from_path ++ params_from_operation)
      |> Enum.flat_map(fn param_spec ->
        {_state,
         %Param{name: name, location: location, required: required, description: description} =
           param} = Param.from_spec(state, param_spec)

        if location in [:path, :query, :header] do
          {_, config} = List.keyfind(param_configs, {name, location}, 0, {name, []})
          name_new = Keyword.get_lazy(config, :name, fn -> Naming.normalize_identifier(name) end)

          description_new =
            if name_new == name do
              description
            else
              Enum.join(["[#{inspect(name)}]", description], " ")
            end

          default = Keyword.get(config, :default)

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

          required_new = required and is_nil(default)
          [%Param{param | name: name_new, required: required_new, description: description_new}]
        else
          []
        end
      end)
      |> Enum.sort_by(fn %Param{location: location} ->
        case location do
          :path -> 0
          :query -> 1
          :header -> 2
        end
      end)
      |> Enum.split_with(& &1.required)

    body_param =
      case request_body do
        %RequestBody{description: description} ->
          [
            %Param{
              description: description,
              location: :query,
              name: "body",
              required: true,
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
        required: false,
        value_type: :null
      }
    ]

    required_params = required_params ++ body_param
    optional_params = optional_params ++ client_param

    result =
      OpenAPI.Processor.Operation.docstring(
        state,
        operation_spec,
        required_params ++ optional_params
      )

    if length(required_params) > 0 do
      [%Param{name: name} | _] = optional_params

      result
      |> String.replace("## Options", "## Arguments", global: false)
      |> String.replace("  * `#{name}`:", "\n## Options\n\n  * `#{name}`:", global: false)
    else
      result
    end
    |> String.replace(~r/\s+$/, "\n")
  end
end

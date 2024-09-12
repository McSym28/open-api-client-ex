if Mix.env() in [:dev, :test] do
  defmodule OpenAPIClient.Generator.Renderer do
    defmacro __using__(_opts) do
      quote do
        use OpenAPI.Renderer

        @impl OpenAPI.Renderer
        defdelegate render(state, file), to: OpenAPIClient.Generator.Renderer

        @impl OpenAPI.Renderer
        defdelegate render_default_client(state, file), to: OpenAPIClient.Generator.Renderer

        @impl OpenAPI.Renderer
        defdelegate render_schema(state, file), to: OpenAPIClient.Generator.Renderer

        @impl OpenAPI.Renderer
        defdelegate render_schema_field_function(state, schemas),
          to: OpenAPIClient.Generator.Renderer

        @impl OpenAPI.Renderer
        defdelegate render_schema_struct(state, schemas), to: OpenAPIClient.Generator.Renderer

        @impl OpenAPI.Renderer
        defdelegate render_schema_types(state, schemas), to: OpenAPIClient.Generator.Renderer

        @impl OpenAPI.Renderer
        defdelegate render_moduledoc(state, file), to: OpenAPIClient.Generator.Renderer

        @impl OpenAPI.Renderer
        defdelegate render_operations(state, file), to: OpenAPIClient.Generator.Renderer

        @impl OpenAPI.Renderer
        defdelegate render_operation_spec(state, operation), to: OpenAPIClient.Generator.Renderer

        @impl OpenAPI.Renderer
        defdelegate render_operation_function(state, operation),
          to: OpenAPIClient.Generator.Renderer

        defoverridable render: 2,
                       render_moduledoc: 2,
                       render_default_client: 2,
                       render_operations: 2,
                       render_operation_spec: 2,
                       render_operation_function: 2,
                       render_schema: 2,
                       render_schema_field_function: 2,
                       render_schema_struct: 2,
                       render_schema_types: 2
      end
    end

    use OpenAPI.Renderer
    alias OpenAPI.Renderer.{File, Util}
    alias OpenAPI.Processor.{Operation, Schema}
    alias Operation.Param
    alias Schema.Field
    alias OpenAPIClient.Generator.Operation, as: GeneratorOperation
    alias OpenAPIClient.Generator.Param, as: GeneratorParam
    alias OpenAPIClient.Generator.Schema, as: GeneratorSchema
    alias OpenAPIClient.Generator.Field, as: GeneratorField
    alias OpenAPIClient.Generator.Utils
    alias OpenAPI.Spec.Path.Operation, as: OperationSpec
    alias OpenAPIClient.Generator.SchemaType
    require Logger

    @impl OpenAPI.Renderer
    def render(
          %OpenAPI.Renderer.State{schemas: schemas} = state,
          %File{operations: operations} = file
        ) do
      Enum.each(schemas, fn {schema_ref, schema} ->
        [
          {_,
           %GeneratorSchema{fields: generator_fields, schema_fields: schema_fields} =
             generator_schema}
        ] = :ets.lookup(:schemas, schema_ref)

        if length(schema_fields) == 0 do
          schema_fields =
            generator_fields
            |> Enum.flat_map(fn
              %GeneratorField{
                field: %Field{name: new_name, type: type},
                old_name: old_name,
                schema_type: schema_type
              } = _generator_field ->
                type_new = Utils.schema_type_to_readable_type(state, type, schema_type)

                field_type =
                  case schema_type do
                    %SchemaType{default: {_, _, _} = default} -> {old_name, type_new, default}
                    _ -> {old_name, type_new}
                  end

                [{String.to_atom(new_name), field_type}]

              _ ->
                []
            end)
            |> Enum.sort_by(fn {name, _} -> name end)

          :ets.insert(
            :schemas,
            {schema_ref,
             %GeneratorSchema{generator_schema | schema_fields: schema_fields, schema: schema}}
          )
        end
      end)

      Enum.each(operations, fn %Operation{
                                 request_path: request_path,
                                 request_method: request_method,
                                 responses: responses,
                                 request_body: request_body
                               } ->
        [
          {_,
           %GeneratorOperation{
             spec: %OperationSpec{
               request_body: spec_request_body,
               responses: spec_responses
             }
           }}
        ] =
          :ets.lookup(:operations, {request_path, request_method})

        Enum.each(request_body, fn {content_type, schema_type} ->
          %OpenAPI.Spec.Schema.Media{} = media = spec_request_body.content[content_type]
          update_schema_examples(schema_type, media, state)
        end)

        Enum.each(responses, fn {status_code, schemas} ->
          Enum.each(schemas, fn {content_type, schema_type} ->
            %OpenAPI.Spec.Response{content: content} = spec_responses[status_code]
            %OpenAPI.Spec.Schema.Media{} = media = content[content_type]
            update_schema_examples(schema_type, media, state)
          end)
        end)
      end)

      OpenAPI.Renderer.render(state, file)
    end

    @impl OpenAPI.Renderer
    def render_default_client(
          %OpenAPI.Renderer.State{implementation: implementation} = state,
          %File{operations: file_operations} = file
        ) do
      case OpenAPI.Renderer.render_default_client(state, file) do
        {:@, _, [{:default_client, _, _}] = _default_client_expression} ->
          {non_operations, operations} =
            Enum.split_with(file_operations, fn %Operation{
                                                  request_path: request_path,
                                                  request_method: request_method
                                                } ->
              [{_, %GeneratorOperation{type: operation_type}}] =
                :ets.lookup(:operations, {request_path, request_method})

              operation_type in [:callback, :webhook]
            end)

          base_url_expression =
            unless Enum.empty?(operations) do
              base_url = Utils.get_config(state, :base_url)

              if not is_binary(base_url) do
                throw("`:base_url` for profile `#{inspect(state.profile)}` is not set!")
              end

              quote(do: @base_url(unquote(base_url)))
            end

          callback_behaviour_expressions =
            case non_operations do
              [] ->
                []

              callbacks ->
                functions =
                  Enum.map(callbacks, fn %Operation{function_name: function_name} ->
                    {:const, function_name}
                  end)

                [
                  Util.put_newlines(quote(do: @behaviour(OpenAPIClient.Callback))),
                  quote(
                    do:
                      @type(
                        callback_functions ::
                          unquote(implementation.render_type(state, {:union, functions}))
                      )
                  )
                ]
            end

          [base_url_expression | callback_behaviour_expressions]
          |> Util.clean_list()
          |> case do
            [] -> []
            expressions -> Util.put_newlines(expressions)
          end

        result ->
          result
      end
    end

    @impl OpenAPI.Renderer
    def render_schema(state, %File{schemas: schemas} = file) do
      schemas_new =
        Enum.map(schemas, fn %Schema{ref: ref} = schema ->
          [{_, %GeneratorSchema{fields: all_fields}}] = :ets.lookup(:schemas, ref)

          fields_new =
            Enum.flat_map(all_fields, fn
              %GeneratorField{field: nil} -> []
              %GeneratorField{field: field} -> [field]
            end)

          %Schema{schema | fields: fields_new}
        end)

      file_new = %File{file | schemas: schemas_new}

      state
      |> OpenAPI.Renderer.render_schema(file_new)
      |> case do
        [] -> []
        list -> [Util.put_newlines(quote(do: @behaviour(OpenAPIClient.Schema))) | list]
      end
    end

    @impl OpenAPI.Renderer
    def render_schema_types(
          %OpenAPI.Renderer.State{implementation: implementation} = state,
          schemas
        ) do
      {schemas_new, types} =
        Enum.map_reduce(schemas, [], fn %Schema{ref: ref, type_name: type} = schema, types ->
          [{_, %GeneratorSchema{fields: all_fields}}] = :ets.lookup(:schemas, ref)

          fields_new =
            Enum.flat_map(all_fields, fn
              %GeneratorField{field: nil} ->
                []

              %GeneratorField{field: %Field{type: type} = field, schema_type: schema_type} =
                  _generator_field ->
                type_new = prepare_spec_type(type, schema_type)
                [%Field{field | type: type_new}]
            end)

          {%Schema{schema | fields: fields_new}, [{:const, type} | types]}
        end)

      case OpenAPI.Renderer.render_schema_types(state, schemas_new) do
        [] ->
          []

        schema_types ->
          Enum.map(schema_types, fn expression ->
            Macro.update_meta(expression, &Keyword.delete(&1, :end_of_expression))
          end) ++
            [
              Util.put_newlines(
                quote(
                  do: @type(types :: unquote(implementation.render_type(state, {:union, types})))
                )
              )
            ]
      end
    end

    @impl OpenAPI.Renderer
    def render_schema_struct(state, schemas) do
      {:defstruct, defstruct_metadata, [struct_fields]} =
        _struct_result = OpenAPI.Renderer.render_schema_struct(state, schemas)

      struct_fields = Enum.map(struct_fields, &{&1, {false, nil}})

      struct_fields_new =
        Enum.reduce(schemas, struct_fields, fn
          %Schema{ref: ref, output_format: :struct}, struct_fields ->
            [{_, %GeneratorSchema{fields: all_fields}}] = :ets.lookup(:schemas, ref)

            Enum.reduce(all_fields, struct_fields, fn
              %GeneratorField{
                field: %Field{name: name},
                enforce: true,
                schema_type: %SchemaType{default: default}
              },
              struct_fields ->
                name_atom = String.to_atom(name)
                List.keyreplace(struct_fields, name_atom, 0, {name_atom, {true, default}})

              _, struct_fields ->
                struct_fields
            end)

          _schema, struct_fields ->
            struct_fields
        end)

      enforced_keys_expression =
        struct_fields_new
        |> Enum.flat_map(fn
          {field, {true, nil}} -> [field]
          {_field, _} -> []
        end)
        |> case do
          [] -> nil
          list -> quote do: @enforce_keys(unquote(list))
        end

      defstruct_fields =
        struct_fields_new
        |> Enum.map(fn
          {field, {_, nil}} -> field
          {field, {false, _default}} -> field
          {field, {true, {_, _, _} = _default}} -> field
          {field, {true, default}} -> {field, default}
        end)
        |> Enum.sort_by(fn
          field when is_atom(field) -> false
          {_field, _default} -> true
        end)

      Util.clean_list([
        enforced_keys_expression,
        {:defstruct, defstruct_metadata, [defstruct_fields]}
      ])
    end

    @impl OpenAPI.Renderer
    def render_schema_field_function(state, schemas) do
      state
      |> OpenAPI.Renderer.render_schema_field_function(schemas)
      |> Enum.flat_map(fn
        {:@, _, [{:spec, _, [{:"::", [], [{:__fields__, _, _}, _]}]}]} ->
          [
            quote(do: @impl(OpenAPIClient.Schema)),
            quote(do: @spec(__fields__(types()) :: keyword(OpenAPIClient.Schema.field_type())))
          ]

        {:def, def_metadata,
         [{:__fields__, _fields_metadata, [type]} = fun_header, [do: _fields_clauses]]} ->
          %Schema{ref: ref} =
            Enum.find(schemas, fn %Schema{type_name: schema_type} -> schema_type == type end)

          [{_, %GeneratorSchema{schema_fields: schema_fields}}] = :ets.lookup(:schemas, ref)

          schema_fields_new =
            Enum.map(schema_fields, fn
              {new_name, {old_name, type}} ->
                {new_name, {old_name, type}}

              {new_name, {old_name, type, default}} ->
                {new_name,
                 quote(do: {unquote(old_name), unquote(type), fn -> unquote(default) end})}
            end)

          [
            {:def, def_metadata,
             [
               fun_header,
               [
                 do:
                   quote do
                     unquote(schema_fields_new)
                   end
               ]
             ]}
          ]

        {:def, _, [{:__fields__, _, [{:\\, _, _}]}]} = _fields_default_declaration ->
          []

        expression ->
          [expression]
      end)
    end

    @impl OpenAPI.Renderer
    def render_moduledoc(state, %File{operations: []} = file),
      do: OpenAPI.Renderer.render_moduledoc(state, file)

    def render_moduledoc(state, %File{operations: file_operations} = file) do
      state
      |> OpenAPI.Renderer.render_moduledoc(file)
      |> Macro.prewalk(fn
        {:moduledoc, moduledoc_attributes, [doc]} ->
          {non_operations, operations} =
            Enum.split_with(file_operations, fn %Operation{
                                                  request_path: request_path,
                                                  request_method: request_method
                                                } ->
              [{_, %GeneratorOperation{type: operation_type}}] =
                :ets.lookup(:operations, {request_path, request_method})

              operation_type in [:callback, :webhook]
            end)

          doc_new =
            String.replace(doc, ~r/^Provides\s+API\s+\w+\s+related/, fn _ ->
              operations_text =
                case operations do
                  [] -> nil
                  [_] -> "endpoint"
                  _ -> "endpoints"
                end

              non_operations_text =
                case non_operations do
                  [] -> nil
                  [_] -> "callback"
                  _ -> "callbacks"
                end

              [operations_text, non_operations_text]
              |> Enum.reject(&is_nil/1)
              |> Enum.join(" and ")
              |> then(&"Provides API #{&1} related")
            end)

          {:moduledoc, moduledoc_attributes, [doc_new]}

        expression ->
          expression
      end)
    end

    @impl OpenAPI.Renderer
    def render_operations(state, %File{operations: []} = file),
      do: OpenAPI.Renderer.render_operations(state, file)

    def render_operations(state, %File{operations: operations} = file) do
      test_renderer =
        Utils.get_config(state, :test_renderer, OpenAPIClient.Generator.TestRenderer)

      test_renderer_state = %OpenAPIClient.Generator.TestRenderer.State{
        implementation: test_renderer,
        renderer_state: state
      }

      operations_new =
        Enum.map(
          operations,
          fn %Operation{
               request_path: request_path,
               request_method: request_method,
               responses: responses
             } = operation ->
            [{_, %GeneratorOperation{config: operation_config}}] =
              :ets.lookup(:operations, {request_path, request_method})

            responses_new =
              Enum.map(
                responses,
                fn
                  {:default, schemas} ->
                    status_code =
                      !!Keyword.get(operation_config, :default_status_code_as_failure, true)

                    {status_code, schemas}

                  {status_code, schemas} ->
                    {status_code, schemas}
                end
              )

            %Operation{operation | responses: responses_new}
          end
        )

      file_new = %File{file | operations: operations_new}

      test_renderer.render(test_renderer_state, file_new)

      result = OpenAPI.Renderer.render_operations(state, file_new)

      operations_new
      |> Enum.reduce({[], []}, fn %Operation{
                                    function_name: function_name,
                                    request_path: request_path,
                                    request_method: request_method
                                  } = operation,
                                  {callbacks, callback_functions} ->
        [
          {_,
           %GeneratorOperation{
             type: operation_type,
             normalized_request_path: normalized_request_path
           } = generator_operation}
        ] =
          :ets.lookup(:operations, {request_path, request_method})

        if operation_type in [:callback, :webhook] do
          state
          |> do_render_operation_function(operation, generator_operation)
          |> Macro.prewalk([request_path_mask: normalized_request_path], fn
            {key, _value} = expression, function_acc
            when key in [
                   :request_parameter_types,
                   :request_types,
                   :response_types,
                   :response_parameter_types,
                   :profile
                 ] ->
              function_acc_new = [expression | function_acc]
              {expression, function_acc_new}

            {:function_args, value} = expression, function_acc ->
              value
              |> Keyword.keys()
              |> Kernel.--([:body])
              |> case do
                [] ->
                  {expression, function_acc}

                args ->
                  function_acc_new = [{:request_parameter_args, args} | function_acc]
                  {expression, function_acc_new}
              end

            expression, function_acc ->
              {expression, function_acc}
          end)
          |> case do
            {_, []} ->
              {callbacks, callback_functions}

            {_, expressions} ->
              function =
                quote(
                  do:
                    def(__functions__(unquote(function_name)),
                      do: unquote(Enum.reverse(expressions))
                    )
                )

              arity = Utils.get_function_arity(state, operation, generator_operation)
              callbacks_new = [{function_name, arity} | callbacks]
              callback_functions_new = [function | callback_functions]
              {callbacks_new, callback_functions_new}
          end
        else
          {callbacks, callback_functions}
        end
      end)
      |> case do
        {[], []} ->
          result

        {callbacks, callback_functions} ->
          Util.put_newlines(result) ++
            [
              Util.put_newlines(quote(do: @optional_callbacks(unquote(Enum.reverse(callbacks))))),
              quote(do: @doc(false)),
              quote(do: @impl(OpenAPIClient.Callback)),
              quote(
                do:
                  @spec(
                    __functions__(callback_functions()) :: [
                      OpenAPIClient.Callback.function_option()
                    ]
                  )
              )
              | Enum.reverse(callback_functions)
            ]
      end
    end

    @impl OpenAPI.Renderer
    def render_operation_spec(
          %OpenAPI.Renderer.State{implementation: implementation} = state,
          %Operation{
            function_name: function_name,
            responses: responses,
            request_path: request_path,
            request_method: request_method
          } = operation
        ) do
      [
        {_,
         %GeneratorOperation{
           params: all_params,
           type: operation_type,
           normalized_request_path: normalized_request_path
         }}
      ] =
        :ets.lookup(:operations, {request_path, request_method})

      {static_params, dynamic_params} =
        all_params
        |> Enum.group_by(
          fn %GeneratorParam{static: static} -> static end,
          fn %GeneratorParam{param: %Param{value_type: type} = param, schema_type: schema_type} ->
            type_new = prepare_spec_type(type, schema_type)
            %Param{param | value_type: type_new}
          end
        )
        |> then(fn map -> {Map.get(map, true, []), Map.get(map, false, [])} end)

      {responses_new, {atom_success, atom_failure}} =
        responses
        |> Enum.map(fn
          {true, schemas} -> {299, schemas}
          {false, schemas} -> {599, schemas}
          {"2XX", schemas} -> {298, schemas}
          other -> other
        end)
        |> List.keystore(
          598,
          0,
          {598, %{"application/json" => {:const, quote(do: OpenAPIClient.Error.t())}}}
        )
        |> Enum.map_reduce({false, false}, fn
          {status_code, schemas} = response, {_atom_success, atom_failure}
          when map_size(schemas) == 0 and is_integer(status_code) and status_code >= 200 and
                 status_code < 300 ->
            {response, {true, atom_failure}}

          {_status_code, schemas} = response, {atom_success, _atom_failure}
          when map_size(schemas) == 0 ->
            {response, {atom_success, true}}

          response, acc ->
            {response, acc}
        end)

      operation_new = %Operation{
        operation
        | request_path_parameters: static_params,
          responses: responses_new,
          request_path: normalized_request_path
      }

      {:@, attribute_metadata,
       [
         {:spec, spec_metadata,
          [
            {:"::", return_type_delimiter_metadata,
             [
               {^function_name, arguments_metadata, arguments},
               return_type
             ]}
          ]}
       ]} = OpenAPI.Renderer.render_operation_spec(state, operation_new)

      return_types = parse_spec_return_type(return_type, [])

      return_types =
        if atom_success and not Enum.member?(return_types, :ok) do
          [:ok | return_types]
        else
          return_types
        end

      return_types =
        if atom_failure and not Enum.member?(return_types, :error) do
          List.insert_at(return_types, -2, :error)
        else
          return_types
        end

      return_type_new = return_types |> Enum.reverse() |> Enum.reduce(&{:|, [], [&1, &2]})

      additional_params =
        if operation_type in [:callback, :webhook] do
          []
        else
          [
            {:base_url, quote(do: String.t() | URI.t())},
            {:pipeline, quote(do: OpenAPIClient.pipeline())}
          ]
        end

      opts_spec =
        dynamic_params
        |> Enum.map(fn %Param{name: name, value_type: type} ->
          {String.to_atom(name), implementation.render_type(state, type)}
        end)
        |> Kernel.++(additional_params)
        |> Enum.reverse()
        |> Enum.reduce(fn type, expression ->
          {:|, [], [type, expression]}
        end)

      arguments_new = List.replace_at(arguments, -1, [opts_spec])

      attribute_atom =
        if operation_type in [:callback, :webhook] do
          :callback
        else
          :spec
        end

      {:@, attribute_metadata,
       [
         {attribute_atom, spec_metadata,
          [
            {:"::", return_type_delimiter_metadata,
             [
               {function_name, arguments_metadata, arguments_new},
               return_type_new
             ]}
          ]}
       ]}
    end

    @impl OpenAPI.Renderer
    def render_operation_function(
          state,
          %Operation{request_path: request_path, request_method: request_method} = operation
        ) do
      [{_, %GeneratorOperation{type: operation_type} = generator_operation}] =
        :ets.lookup(:operations, {request_path, request_method})

      if operation_type in [:callback, :webhook] do
        []
      else
        do_render_operation_function(state, operation, generator_operation)
      end
    end

    def do_render_operation_function(
          state,
          %Operation{
            function_name: function_name,
            responses: responses
          } = operation,
          %GeneratorOperation{
            params: all_params,
            param_renamings: param_renamings,
            type: operation_type
          }
        ) do
      static_params =
        all_params
        |> Enum.flat_map(fn %GeneratorParam{param: param, static: static} ->
          if static do
            [param]
          else
            []
          end
        end)

      operation_new = %Operation{operation | request_path_parameters: static_params}

      operation_profile = Utils.get_config(state, :aliased_profile, state.profile)

      {:def, def_metadata,
       [
         {^function_name, _, _} = function_header,
         [do: {do_tag, do_metadata, do_expressions}]
       ]} = OpenAPI.Renderer.render_operation_function(state, operation_new)

      do_expressions_new =
        Enum.flat_map(
          do_expressions,
          fn
            {:=, _, [{:client, _, _} | _]} = _client_expression ->
              if operation_type in [:callback, :webhook] do
                []
              else
                client_pipeline_expression =
                  quote(
                    do:
                      pipeline =
                        opts[:pipeline] ||
                          OpenAPIClient.Utils.get_config(
                            unquote(operation_profile),
                            :operation_pipeline
                          )
                  )

                base_url_expression =
                  quote(do: base_url = opts[:base_url] || @base_url)

                [client_pipeline_expression, base_url_expression]
              end

            {:=, _, [{:query, _, _} | _]} = _query_expression ->
              []

            {{:., _, [{:client, _, _}, :request]} = _dot_expression, _dot_metadata,
             [
               {:%{}, _map_metadata, map_arguments}
             ]} = _call_expression ->
              state_assigns =
                Enum.reduce(
                  map_arguments,
                  [{:profile, operation_profile}, {:request_base_url, Macro.var(:base_url, nil)}],
                  fn
                    {:url, value}, acc ->
                      value_new =
                        String.replace(value, ~r/\{([^\}]+?)\}/, fn word ->
                          word
                          |> String.split(["{", "}"])
                          |> Enum.at(1)
                          |> then(fn old_name ->
                            name = Map.get(param_renamings, {old_name, :path}, old_name)
                            "{#{name}}"
                          end)
                        end)

                      [{:request_path, value_new} | acc]

                    {:method, value}, acc ->
                      parameters =
                        Enum.map(all_params, fn
                          %GeneratorParam{
                            param: %Param{name: name, location: location, value_type: type},
                            schema_type: %SchemaType{default: default} = schema_type,
                            old_name: old_name,
                            custom: is_custom
                          }
                          when not is_nil(default) ->
                            atom = String.to_atom(name)
                            location_new = if is_custom, do: :custom, else: location

                            type_new =
                              Utils.schema_type_to_readable_type(state, type, schema_type)

                            default_new =
                              case default do
                                {_, _, _} -> quote(do: fn -> unquote(default) end)
                                _ -> default
                              end

                            {{atom, location_new},
                             quote(
                               do: {unquote(old_name), unquote(type_new), unquote(default_new)}
                             )}

                          %GeneratorParam{
                            param: %Param{name: name, location: location, value_type: type},
                            schema_type: schema_type,
                            old_name: old_name,
                            custom: is_custom
                          } ->
                            atom = String.to_atom(name)
                            location_new = if is_custom, do: :custom, else: location

                            type_new =
                              Utils.schema_type_to_readable_type(state, type, schema_type)

                            {{atom, location_new}, {old_name, type_new}}
                        end)

                      acc_new =
                        if(Enum.empty?(parameters),
                          do: acc,
                          else: [{:request_parameter_types, parameters} | acc]
                        )

                      [{:method, value} | acc_new]

                    {:body, _value}, acc ->
                      acc

                    {:query, _}, acc ->
                      acc

                    {:request, value}, acc ->
                      [{:request_types, value} | acc]

                    {:response, _value}, acc ->
                      items =
                        responses
                        |> Enum.sort_by(fn
                          {status_code, _schemas} when is_integer(status_code) -> status_code
                          {<<digit::utf8, "XX">>, _schemas} -> (digit - ?0 + 1) * 100 - 2
                          {true, _schemas} -> 299
                          {false, _schemas} -> 599
                        end)
                        |> Enum.map(fn
                          {status_or_default, schemas} when map_size(schemas) == 0 ->
                            quote do
                              {unquote(status_or_default), :null}
                            end

                          {status_or_default, schemas} ->
                            schema_types =
                              Enum.map(schemas, fn {content_type, type} ->
                                quote do
                                  {unquote(content_type),
                                   unquote(Util.to_readable_type(state, type))}
                                end
                              end)

                            quote do
                              {unquote(status_or_default), unquote(schema_types)}
                            end
                        end)

                      [{:response_types, items} | acc]

                    {:opts, value}, acc ->
                      [{:function_opts, value} | acc]

                    {:args, value}, acc ->
                      [{:function_args, value} | acc]

                    {:call, {_module, _function}}, acc ->
                      [{:function_call, quote(do: {__MODULE__, unquote(function_name)})} | acc]
                  end
                )

              state_assigns =
                Enum.sort_by(
                  state_assigns,
                  fn
                    {:request_base_url = key, _} ->
                      {0, key}

                    {:request_path = key, _} ->
                      {1, key}

                    {:method = key, _} ->
                      {2, key}

                    {:profile = key, _} ->
                      {40, key}

                    {key, _} ->
                      key_string = Atom.to_string(key)

                      cond do
                        String.starts_with?(key_string, "request_") -> {10, key}
                        String.starts_with?(key_string, "response_") -> {20, key}
                        String.starts_with?(key_string, "function_") -> {30, key}
                        :else -> {50, key}
                      end
                  end
                )

              [
                quote(
                  do:
                    client =
                      opts[:client] ||
                        OpenAPIClient.Utils.get_config(
                          unquote(operation_profile),
                          :client,
                          OpenAPIClient
                        )
                ),
                quote(
                  do:
                    client.operation(
                      %OpenAPIClient.State{unquote_splicing(state_assigns)},
                      pipeline
                    )
                )
              ]

            expression ->
              [expression]
          end
        )

      {:def, def_metadata,
       [
         function_header,
         [do: {do_tag, do_metadata, do_expressions_new}]
       ]}
    end

    defp parse_spec_return_type({:|, _, [type, next]}, acc),
      do: parse_spec_return_type(next, [type | acc])

    defp parse_spec_return_type(type, acc), do: Enum.reverse([type | acc])

    defp prepare_spec_type({:enum, enum_options}, %SchemaType{
           enum: %SchemaType.Enum{strict: enum_strict, type: enum_type}
         }) do
      enum_options_new =
        enum_options
        |> Enum.map(fn
          number when is_number(number) and not is_integer(number) -> :number
          string when is_binary(string) -> {:string, :generic}
          other -> {:const, other}
        end)

      union_types =
        if not enum_strict && enum_type do
          if enum_type == :number do
            enum_options_new ++ [:number]
          else
            enum_options_new ++ [enum_type]
          end
        else
          enum_options_new
        end

      {:union, union_types}
    end

    defp prepare_spec_type({:array, {:enum, _} = enum_type}, schema_type) do
      enum_type_new = prepare_spec_type(enum_type, schema_type)
      {:array, enum_type_new}
    end

    defp prepare_spec_type(type, _schema_type), do: type

    defp update_schema_examples(
           schema_type,
           %OpenAPI.Spec.Schema.Media{example: example, examples: examples},
           %OpenAPI.Renderer.State{schemas: schemas} = _state
         ) do
      schema_type
      |> case do
        schema_ref when is_reference(schema_ref) -> {schema_ref, false}
        {:array, schema_ref} when is_reference(schema_ref) -> {schema_ref, true}
        _ -> nil
      end
      |> case do
        {schema_ref, is_array} ->
          [{_, %GeneratorSchema{} = generator_schema}] = :ets.lookup(:schemas, schema_ref)
          %Schema{} = schema = schemas[schema_ref]

          examples =
            Enum.flat_map(examples, fn
              {_key, %OpenAPI.Spec.Schema.Example{value: nil}} -> []
              {_key, %OpenAPI.Spec.Schema.Example{value: example}} -> [example]
            end)

          examples =
            if example do
              [example | examples]
            else
              examples
            end

          examples =
            if is_array do
              Enum.flat_map(examples, fn
                example when is_list(example) ->
                  example

                example ->
                  Logger.warning(
                    "Invalid array example `#{inspect(example)}` for schema `{#{schema.module_name}, #{schema.type_name}}`"
                  )

                  []
              end)
            else
              examples
            end

          generator_schema_new =
            OpenAPIClient.Generator.Processor.process_schema_examples(
              generator_schema,
              examples,
              %OpenAPI.Processor.State{schemas_by_ref: schemas}
            )

          :ets.insert(:schemas, {schema_ref, generator_schema_new})

        _ ->
          nil
      end
    end
  end
end

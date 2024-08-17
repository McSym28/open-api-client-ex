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
        defdelegate render_operations(state, file), to: OpenAPIClient.Generator.Renderer

        @impl OpenAPI.Renderer
        defdelegate render_operation_spec(state, operation), to: OpenAPIClient.Generator.Renderer

        @impl OpenAPI.Renderer
        defdelegate render_operation_function(state, operation),
          to: OpenAPIClient.Generator.Renderer

        defoverridable render: 2,
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

    @impl true
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
                [{String.to_atom(new_name), {old_name, type_new}}]

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

    @impl true
    def render_default_client(state, file) do
      case OpenAPI.Renderer.render_default_client(state, file) do
        {:@, _, [{:default_client, _, _}] = _default_client_expression} ->
          base_url = Utils.get_config(state, :base_url)

          if not is_binary(base_url) do
            throw("`:base_url` for profile `#{inspect(state.profile)}` is not set!")
          end

          Util.put_newlines(quote(do: @base_url(unquote(base_url))))

        result ->
          result
      end
    end

    @impl true
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

    @impl true
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

    @impl true
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

    @impl true
    def render_schema_field_function(state, schemas) do
      state
      |> OpenAPI.Renderer.render_schema_field_function(schemas)
      |> Enum.flat_map(fn
        {:@, _, [{:spec, _, [{:"::", [], [{:__fields__, _, _}, _]}]}]} ->
          [
            quote(do: @impl(OpenAPIClient.Schema)),
            quote(do: @spec(__fields__(types()) :: keyword(OpenAPIClient.Schema.schema_type())))
          ]

        {:def, def_metadata,
         [{:__fields__, _fields_metadata, [type]} = fun_header, [do: _fields_clauses]]} ->
          %Schema{ref: ref} =
            Enum.find(schemas, fn %Schema{type_name: schema_type} -> schema_type == type end)

          [{_, %GeneratorSchema{schema_fields: schema_fields}}] = :ets.lookup(:schemas, ref)

          [
            {:def, def_metadata,
             [
               fun_header,
               [
                 do:
                   quote do
                     unquote(schema_fields)
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

    @impl true
    def render_operations(state, %File{operations: []} = file),
      do: OpenAPI.Renderer.render_operations(state, file)

    def render_operations(state, %File{operations: operations} = file) do
      operations_new =
        Enum.map(operations, fn %Operation{
                                  request_path: request_path,
                                  request_method: request_method
                                } = operation ->
          [{_, %GeneratorOperation{param_renamings: param_renamings}}] =
            :ets.lookup(:operations, {request_path, request_method})

          request_path_new =
            String.replace(request_path, ~r/\{([[:word:]]+)\}/, fn word ->
              word
              |> String.split(["{", "}"])
              |> Enum.at(1)
              |> then(fn name ->
                name_new = Map.get(param_renamings, {name, :path}, name)
                "{#{name_new}}"
              end)
            end)

          %Operation{operation | request_path: request_path_new}
        end)

      file_new = %File{file | operations: operations_new}

      test_renderer =
        Utils.get_config(state, :test_renderer, OpenAPIClient.Generator.TestRenderer)

      test_renderer_state = %OpenAPIClient.Generator.TestRenderer.State{
        implementation: test_renderer,
        renderer_state: state
      }

      test_renderer.render(test_renderer_state, file_new)

      OpenAPI.Renderer.render_operations(state, file_new)
    end

    @impl true
    def render_operation_spec(
          %OpenAPI.Renderer.State{implementation: implementation} = state,
          %Operation{
            function_name: function_name,
            responses: responses,
            request_path: request_path,
            request_method: request_method
          } = operation
        ) do
      [{_, %GeneratorOperation{params: all_params}}] =
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
          {:default, schemas} ->
            status_code =
              if Utils.get_config(state, :default_status_code_as_failure) do
                599
              else
                299
              end

            {status_code, schemas}

          {"2XX", schemas} ->
            {298, schemas}

          other ->
            other
        end)
        |> List.keystore(
          598,
          0,
          {598, %{"application/json" => {:const, quote(do: OpenAPIClient.Client.Error.t())}}}
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
          responses: responses_new
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

      opts_spec =
        dynamic_params
        |> Enum.map(fn %Param{name: name, value_type: type} ->
          {String.to_atom(name), implementation.render_type(state, type)}
        end)
        |> Kernel.++([
          {:base_url, quote(do: String.t() | URI.t())},
          {:client_pipeline, quote(do: OpenAPIClient.Client.pipeline())}
        ])
        |> Enum.reverse()
        |> Enum.reduce(fn type, expression ->
          {:|, [], [type, expression]}
        end)

      arguments_new = List.replace_at(arguments, -1, [opts_spec])

      {:@, attribute_metadata,
       [
         {:spec, spec_metadata,
          [
            {:"::", return_type_delimiter_metadata,
             [
               {function_name, arguments_metadata, arguments_new},
               return_type_new
             ]}
          ]}
       ]}
    end

    @impl true
    def render_operation_function(
          state,
          %Operation{
            function_name: function_name,
            request_path: request_path,
            request_method: request_method,
            responses: responses
          } = operation
        ) do
      [{_, %GeneratorOperation{params: all_params}}] =
        :ets.lookup(:operations, {request_path, request_method})

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

      path = [{request_path, request_method}]

      {do_expressions_new, args} =
        Enum.flat_map_reduce(do_expressions, [], fn
          {:=, _, [{:client, _, _} | _]} = _client_expression, args ->
            {param_assignments, use_typed_encoder} =
              all_params
              |> Enum.flat_map_reduce(false, fn
                %GeneratorParam{
                  param: %Param{name: name, location: location, value_type: type},
                  schema_type: %SchemaType{default: default} = schema_type,
                  old_name: old_name,
                  new: is_new
                },
                use_typed_encoder
                when not is_nil(default) ->
                  atom = String.to_atom(name)
                  variable = Macro.var(atom, nil)
                  type_new = Utils.schema_type_to_readable_type(state, type, schema_type)

                  default_new =
                    case default do
                      _ when is_new ->
                        default

                      {_, _, _} ->
                        default

                      _ ->
                        typed_encoder =
                          Utils.get_config(
                            state,
                            :typed_encoder,
                            OpenAPIClient.Client.TypedEncoder
                          )

                        {:ok, default_new} =
                          typed_encoder.encode(
                            default,
                            type_new,
                            [{:parameter, location, old_name}, {request_path, request_method}],
                            typed_encoder
                          )

                        default_new
                    end

                  if not is_new and type_needs_typed_encoding?(type, schema_type) do
                    {[
                       quote(
                         do:
                           unquote(variable) =
                             case Keyword.fetch(opts, unquote(atom)) do
                               {:ok, value} ->
                                 {:ok, value_encoded} =
                                   typed_encoder.encode(
                                     value,
                                     unquote(type_new),
                                     [
                                       {:parameter, unquote(location), unquote(old_name)},
                                       {unquote(request_path), unquote(request_method)}
                                     ],
                                     typed_encoder
                                   )

                                 value_encoded

                               :error ->
                                 unquote(default_new)
                             end
                       )
                     ], true}
                  else
                    {[
                       quote(
                         do:
                           unquote(variable) =
                             Keyword.get_lazy(opts, unquote(atom), fn -> unquote(default_new) end)
                       )
                     ], use_typed_encoder}
                  end

                %GeneratorParam{
                  param: %Param{name: name, location: location, value_type: type},
                  schema_type: schema_type,
                  static: true,
                  old_name: old_name,
                  new: false
                },
                use_typed_encoder ->
                  if type_needs_typed_encoding?(type, schema_type) do
                    atom = String.to_atom(name)
                    variable = Macro.var(atom, nil)
                    type_new = Utils.schema_type_to_readable_type(state, type, schema_type)

                    {[
                       quote(
                         do:
                           {:ok, unquote(variable)} =
                             typed_encoder.encode(
                               unquote(variable),
                               unquote(type_new),
                               [
                                 {:parameter, unquote(location), unquote(old_name)},
                                 {unquote(request_path), unquote(request_method)}
                               ],
                               typed_encoder
                             )
                       )
                     ], true}
                  else
                    {[], use_typed_encoder}
                  end

                %GeneratorParam{
                  param: %Param{value_type: type},
                  schema_type: schema_type,
                  new: false
                },
                use_typed_encoder ->
                  if type_needs_typed_encoding?(type, schema_type) do
                    {[], true}
                  else
                    {[], use_typed_encoder}
                  end

                _, use_typed_encoder ->
                  {[], use_typed_encoder}
              end)

            client_pipeline_expression =
              quote do
                client_pipeline = Keyword.get(opts, :client_pipeline)
              end

            base_url_expression =
              quote do: base_url = opts[:base_url] || @base_url

            param_assignments_new =
              if use_typed_encoder do
                [
                  quote(
                    do:
                      typed_encoder =
                        OpenAPIClient.Utils.get_config(
                          unquote(operation_profile),
                          :typed_encoder,
                          OpenAPIClient.Client.TypedEncoder
                        )
                  )
                  | param_assignments
                ]
              else
                param_assignments
              end

            client_expression_new = [
              client_pipeline_expression,
              base_url_expression | param_assignments_new
            ]

            {client_expression_new, args}

          {:=, _, [{:query, _, _} | _]} = _query_expression, args ->
            query_value =
              all_params
              |> Enum.filter(fn
                %GeneratorParam{param: %Param{location: :query}, new: false} -> true
                _ -> false
              end)
              |> render_params_parse(path, state)

            query_expression_new =
              if query_value do
                [quote(do: query_params = unquote(query_value))]
              else
                []
              end

            {query_expression_new, args}

          {{:., _, [{:client, _, _}, :request]} = _dot_expression, _dot_metadata,
           [
             {:%{}, _map_metadata, map_arguments}
           ]} = _call_expression,
          [] ->
            headers_value =
              all_params
              |> Enum.filter(fn
                %GeneratorParam{param: %Param{location: :header}, new: false} -> true
                _ -> false
              end)
              |> render_params_parse(path, state)

            private_assigns =
              all_params
              |> Enum.flat_map_reduce([], fn
                %GeneratorParam{
                  static: static,
                  new: true,
                  schema_type: %SchemaType{default: default},
                  param: %Param{name: name}
                },
                opts_keys
                when static or not is_nil(default) ->
                  atom = String.to_atom(name)
                  {[quote(do: {unquote(atom), unquote(Macro.var(atom, nil))})], opts_keys}

                %GeneratorParam{new: true, param: %Param{name: name}}, opts_keys ->
                  atom = String.to_atom(name)
                  {[], [atom | opts_keys]}

                _, opts_keys ->
                  {[], opts_keys}
              end)
              |> case do
                {[], []} ->
                  %{}

                {[], opts_keys} ->
                  %{__params__: quote(do: Keyword.take(opts, unquote(Enum.reverse(opts_keys))))}

                {new_params, []} ->
                  %{__params__: new_params}

                {new_params, opts_keys} ->
                  %{
                    __params__:
                      quote(
                        do:
                          opts
                          |> Keyword.take(unquote(Enum.reverse(opts_keys)))
                          |> Keyword.merge(unquote(new_params))
                      )
                  }
              end
              |> Map.put(:__profile__, operation_profile)

            {operation_assigns, private_assigns} =
              Enum.flat_map_reduce(map_arguments, private_assigns, fn
                {:url, value}, acc ->
                  {[{:request_url, value}], acc}

                {:method, value}, acc ->
                  {[
                     {:request_method, value}
                     | if(headers_value,
                         do: [{:request_headers, Macro.var(:headers, nil)}],
                         else: []
                       )
                   ], acc}

                {:body, value}, acc ->
                  {[{:request_body, value}], acc}

                {:query, _}, acc ->
                  {[{:request_query_params, Macro.var(:query_params, nil)}], acc}

                {:request, value}, acc ->
                  {[{:request_types, value}], acc}

                {:response, _value}, acc ->
                  items =
                    responses
                    |> Enum.sort_by(fn
                      {status_code, _schemas} when is_integer(status_code) ->
                        status_code

                      {<<digit::utf8, "XX">>, _schemas} ->
                        (digit - ?0 + 1) * 100 - 2

                      {:default, _schemas} ->
                        if Utils.get_config(state, :default_status_code_as_failure) do
                          599
                        else
                          299
                        end
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
                              {unquote(content_type), unquote(Util.to_readable_type(state, type))}
                            end
                          end)

                        quote do
                          {unquote(status_or_default), unquote(schema_types)}
                        end
                    end)

                  {[{:response_types, items}], acc}

                {:opts, value}, acc ->
                  acc_new = Map.put(acc, :__opts__, value)
                  {[], acc_new}

                {:args, []}, acc ->
                  {[], acc}

                {:args, args}, acc ->
                  acc_new = Map.put(acc, :__args__, args)
                  {[], acc_new}

                {:call, {_module, _function}}, acc ->
                  acc_new =
                    Map.put(acc, :__call__, quote(do: {__MODULE__, unquote(function_name)}))

                  {[], acc_new}
              end)

            operation_assigns = [
              {:request_base_url, Macro.var(:base_url, nil)} | operation_assigns
            ]

            operation =
              quote do
                %OpenAPIClient.Client.Operation{unquote_splicing(operation_assigns)}
              end

            {args, private_assigns_new} =
              private_assigns
              |> Map.pop(:__args__, [])
              |> case do
                {[], private_assigns} ->
                  {[], private_assigns}

                {args, private_assigns} ->
                  private_assigns_new =
                    Map.put(private_assigns, :__args__, quote(do: initial_args))

                  {args, private_assigns_new}
              end

            operation =
              quote do
                unquote(operation)
                |> OpenAPIClient.Client.Operation.put_private(
                  unquote(
                    private_assigns_new
                    |> Map.to_list()
                    |> Enum.sort_by(fn {key, _} -> key end)
                  )
                )
              end

            call_expression_new =
              if headers_value do
                [quote(do: headers = unquote(headers_value))]
              else
                []
              end ++
                [
                  quote(
                    do:
                      client =
                        OpenAPIClient.Utils.get_config(
                          unquote(operation_profile),
                          :client,
                          OpenAPIClient.Client
                        )
                  ),
                  quote(
                    do:
                      unquote(operation)
                      |> client.perform(client_pipeline)
                  )
                ]

            {call_expression_new, args}

          expression, args ->
            {[expression], args}
        end)

      do_expressions_new =
        if Enum.empty?(args) do
          do_expressions_new
        else
          [Util.put_newlines(quote(do: initial_args = unquote(args))) | do_expressions_new]
        end

      {:def, def_metadata,
       [
         function_header,
         [do: {do_tag, do_metadata, do_expressions_new}]
       ]}
    end

    defp render_params_parse([], _typed_encoder_path, _state), do: nil

    defp render_params_parse(params, path, state) do
      {static_params, dynamic_params} =
        params
        |> Enum.group_by(fn %GeneratorParam{
                              static: static,
                              schema_type: %SchemaType{default: default}
                            } ->
          static or not is_nil(default)
        end)
        |> then(fn map -> {Map.get(map, true, []), Map.get(map, false, [])} end)

      static_params =
        Enum.map(static_params, fn %GeneratorParam{param: %Param{name: name}, old_name: old_name} ->
          {old_name, name |> String.to_atom() |> Macro.var(nil)}
        end)

      {dynamic_params, param_renamings} =
        Enum.map_reduce(dynamic_params, [], fn %GeneratorParam{
                                                 param: %Param{
                                                   name: name,
                                                   location: location,
                                                   value_type: type
                                                 },
                                                 old_name: old_name,
                                                 schema_type: schema_type
                                               },
                                               param_renamings ->
          param_renamings_new =
            [
              {:->, [],
               [
                 [{String.to_atom(name), Macro.var(:value, nil)}],
                 if type_needs_typed_encoding?(type, schema_type) do
                   type_new = Utils.schema_type_to_readable_type(state, type, schema_type)

                   quote do
                     {:ok, value_new} =
                       typed_encoder.encode(
                         value,
                         unquote(type_new),
                         [
                           {:parameter, unquote(location), unquote(old_name)},
                           unquote(path)
                         ],
                         typed_encoder
                       )

                     {unquote(old_name), value_new}
                   end
                 else
                   {old_name, Macro.var(:value, nil)}
                 end
               ]}
              | param_renamings
            ]

          {String.to_atom(name), param_renamings_new}
        end)

      dynamic_params =
        if length(dynamic_params) > 0 do
          dynamic_params = quote(do: opts |> Keyword.take(unquote(dynamic_params)))

          dynamic_params =
            if length(param_renamings) > 0 do
              quote do
                unquote(dynamic_params)
                |> Enum.map(unquote({:fn, [], param_renamings}))
              end
            else
              dynamic_params
            end

          quote do
            unquote(dynamic_params)
            |> Map.new()
          end
        end

      case {length(static_params) > 0, not is_nil(dynamic_params)} do
        {true, false} ->
          quote do: %{unquote_splicing(static_params)}

        {false, true} ->
          dynamic_params

        {true, true} ->
          quote do
            unquote(dynamic_params)
            |> Map.merge(%{unquote_splicing(static_params)})
          end
      end
    end

    defp type_needs_typed_encoding?(:boolean, _schema_type), do: false
    defp type_needs_typed_encoding?(:integer, _schema_type), do: false
    defp type_needs_typed_encoding?({:integer, :int32}, _schema_type), do: false
    defp type_needs_typed_encoding?({:integer, :int64}, _schema_type), do: false
    defp type_needs_typed_encoding?(:number, _schema_type), do: false
    defp type_needs_typed_encoding?({:number, :float}, _schema_type), do: false
    defp type_needs_typed_encoding?({:number, :double}, _schema_type), do: false
    defp type_needs_typed_encoding?({:string, :generic}, _schema_type), do: false

    defp type_needs_typed_encoding?({:enum, enum_values}, %SchemaType{
           enum: %SchemaType.Enum{type: enum_type}
         })
         when enum_type in [:boolean, :integer, :number] do
      check_function =
        case enum_type do
          :boolean -> &is_boolean/1
          :integer -> &is_integer/1
          :number -> &is_number/1
        end

      not Enum.all?(enum_values, check_function)
    end

    defp type_needs_typed_encoding?(
           {:enum, _} = type,
           %SchemaType{enum: %SchemaType.Enum{type: {enum_base_type, _} = enum_type} = enum} =
             schema_type
         )
         when enum_base_type in [:boolean, :integer, :number] do
      if type_needs_typed_encoding?(enum_type, nil) do
        true
      else
        enum_new = %SchemaType.Enum{enum | type: enum_base_type}
        schema_type_new = %SchemaType{schema_type | enum: enum_new}
        type_needs_typed_encoding?(type, schema_type_new)
      end
    end

    defp type_needs_typed_encoding?(_type, _schema_type), do: true

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

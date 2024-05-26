defmodule OpenAPIClient.Generator.Renderer do
  use OpenAPI.Renderer
  alias OpenAPI.Renderer.{File, Util}
  alias OpenAPI.Processor.{Operation, Schema}
  alias Schema.Field
  alias Operation.Param
  alias OpenAPIClient.Generator.Operation, as: GeneratorOperation
  alias OpenAPIClient.Generator.Param, as: GeneratorParam
  alias OpenAPIClient.Generator.Schema, as: GeneratorSchema
  alias OpenAPIClient.Generator.Field, as: GeneratorField
  alias OpenAPIClient.Generator.Utils
  alias OpenAPIClient.Client.TypedDecoder
  import Mox

  @test_example_url "https://example.com"

  defmodule ExampleSchemaFieldsAgent do
    use Agent

    @spec start_link() :: Agent.on_start()
    def start_link() do
      Agent.start_link(fn -> {nil, []} end)
    end

    @spec update(Agent.agent(), reference()) :: :ok
    def update(pid, ref) do
      Agent.update(pid, fn
        {^ref, _} = state ->
          state

        _ ->
          [{_, %GeneratorSchema{schema_fields: schema_fields}}] = :ets.lookup(:schemas, ref)
          {ref, schema_fields}
      end)
    end

    @spec get(Agent.agent()) :: keyword(OpenAPIClient.Schema.schema_type())
    def get(pid), do: Agent.get(pid, fn {_ref, schema_fields} -> schema_fields end)
  end

  @impl true
  def render(%OpenAPI.Renderer.State{schemas: schemas} = state, file) do
    Enum.each(schemas, fn {schema_ref, _schema} ->
      [
        {_,
         %GeneratorSchema{fields: generator_fields, schema_fields: schema_fields} =
           generator_schema}
      ] = :ets.lookup(:schemas, schema_ref)

      if length(schema_fields) == 0 do
        schema_fields =
          generator_fields
          |> Enum.flat_map(fn
            %GeneratorField{field: %Field{name: new_name}, old_name: old_name} = generator_field ->
              [{String.to_atom(new_name), {old_name, field_to_type(generator_field, state)}}]

            _ ->
              []
          end)
          |> Enum.sort_by(fn {name, _} -> name end)

        :ets.insert(
          :schemas,
          {schema_ref, %GeneratorSchema{generator_schema | schema_fields: schema_fields}}
        )
      end
    end)

    OpenAPI.Renderer.Module.render(state, file)
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
  def render_schema_types(state, schemas) do
    {schemas_new, types} =
      Enum.map_reduce(schemas, [], fn %Schema{ref: ref, type_name: type} = schema, types ->
        [{_, %GeneratorSchema{fields: all_fields}}] = :ets.lookup(:schemas, ref)

        fields_new =
          Enum.flat_map(all_fields, fn
            %GeneratorField{field: nil} -> []
            %GeneratorField{field: field, type: type} -> [%Field{field | type: type}]
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
              quote(do: @type(types :: unquote(Util.to_type(state, {:union, types}))))
            )
          ]
    end
  end

  @impl true
  def render_schema_struct(state, schemas) do
    struct_result = OpenAPI.Renderer.render_schema_struct(state, schemas)

    enforced_keys_expression =
      Enum.reduce_while(schemas, nil, fn
        %Schema{ref: ref, output_format: :struct}, _acc ->
          [{_, %GeneratorSchema{fields: all_fields}}] = :ets.lookup(:schemas, ref)

          enforced_keys =
            Enum.flat_map(all_fields, fn
              %GeneratorField{field: %Field{name: name}, enforce: true} -> [String.to_atom(name)]
              _ -> []
            end)

          enforced_keys_expression =
            if length(enforced_keys) > 0 do
              quote do: @enforce_keys(unquote(Enum.sort(enforced_keys)))
            end

          {:halt, enforced_keys_expression}

        _schema, acc ->
          {:cont, acc}
      end)

    Util.clean_list([
      enforced_keys_expression,
      struct_result
    ])
  end

  @impl true
  def render_schema_field_function(state, schemas) do
    state
    |> OpenAPI.Renderer.render_schema_field_function(schemas)
    |> Enum.flat_map(fn
      {:@, _attribute_metadata, [{:spec, spec_metadata, [{:"::", [], [{:__fields__, _, _}, _]}]}]} ->
        [
          {:@, [], [{:impl, [], [true]}]},
          {:@, [],
           [
             {:spec, spec_metadata,
              [
                {:"::", [],
                 [
                   {:__fields__, [], [quote(do: types())]},
                   quote(do: keyword(OpenAPIClient.Schema.schema_type()))
                 ]}
              ]}
           ]}
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

      expression ->
        [expression]
    end)
  end

  @impl true
  def render_operations(
        %OpenAPI.Renderer.State{
          schemas: schemas,
          implementation: implementation
        } = state,
        %File{module: module, operations: operations} = file
      ) do
    schema_fields_agent =
      if length(operations) > 0 do
        {:ok, schema_fields_agent} = ExampleSchemaFieldsAgent.start_link()

        Mox.defmock(ExampleSchema, for: OpenAPIClient.Schema)
        Mox.defmock(ExampleTypedDecoder, for: TypedDecoder)

        stub(ExampleSchema, :__fields__, fn _type ->
          ExampleSchemaFieldsAgent.get(schema_fields_agent)
        end)

        stub(ExampleTypedDecoder, :decode, fn value, type ->
          apply(ExampleTypedDecoder, :decode, [value, type, [], ExampleTypedDecoder])
        end)

        stub(ExampleTypedDecoder, :decode, fn
          value, {module, type}, path, _caller_module
          when is_atom(module) and is_atom(type) and is_map(value) ->
            with :alias <- Macro.classify_atom(module),
                 %Schema{ref: schema_ref, output_format: output_format} <-
                   Enum.find_value(schemas, fn
                     {_ref, %Schema{module_name: module_name, type_name: ^type} = schema} ->
                       if generate_module_name(module_name, state) == module do
                         schema
                       else
                         nil
                       end

                     _ ->
                       nil
                   end) do
              ExampleSchemaFieldsAgent.update(schema_fields_agent, schema_ref)

              case TypedDecoder.decode(value, {ExampleSchema, type}, path, ExampleTypedDecoder) do
                {:ok, decoded_value} when output_format == :struct ->
                  decoded_value =
                    quote do
                      %unquote(module){
                        unquote_splicing(
                          decoded_value
                          |> Map.to_list()
                          |> Enum.sort_by(fn {name, _value} -> name end)
                        )
                      }
                    end

                  {:ok, decoded_value}

                {:ok, decoded_value} ->
                  quote do
                    {:ok,
                     %{
                       unquote_splicing(
                         decoded_value
                         |> Map.to_list()
                         |> Enum.sort_by(fn {name, _value} -> name end)
                       )
                     }}
                  end

                {:error, _} = error ->
                  error
              end
            else
              _ ->
                TypedDecoder.decode(value, {module, type}, path, ExampleTypedDecoder)
            end

          value, type, path, _caller_module ->
            TypedDecoder.decode(value, type, path, ExampleTypedDecoder)
        end)

        schema_fields_agent
      end

    {operations_new, operation_tests} =
      Enum.map_reduce(operations, [], fn %Operation{
                                           request_path: request_path,
                                           request_method: request_method,
                                           request_body: request_body,
                                           function_name: function_name
                                         } = operation,
                                         acc ->
        [{_, %GeneratorOperation{params: params, param_renamings: param_renamings}}] =
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

        operation_new = %Operation{operation | request_path: request_path_new}

        acc_new =
          case generate_operation_test_functions(operation_new, state) do
            [] ->
              acc

            test_functions ->
              arity =
                Enum.reduce(
                  params,
                  if(length(request_body) == 0, do: 1, else: 2),
                  fn %GeneratorParam{static: static}, arity ->
                    arity + if(static, do: 1, else: 0)
                  end
                )

              describe_message = "#{function_name}/#{arity}"

              describe_block =
                quote do
                  describe unquote(describe_message) do
                    (unquote_splicing(test_functions))
                  end
                end

              [describe_block | acc]
          end

        {operation_new, acc_new}
      end)

    if schema_fields_agent do
      Agent.stop(schema_fields_agent)
    end

    if length(operation_tests) != 0 do
      test_module =
        module
        |> generate_module_name(state)
        |> Module.split()
        |> List.update_at(-1, &"#{&1}Test")
        |> Module.concat()

      test_ast =
        quote do
          defmodule unquote(test_module) do
            use ExUnit.Case, async: true
            import Mox

            @httpoison OpenAPIClient.HTTPoisonMock

            setup do
              Mox.defmock(@httpoison, for: HTTPoison.Base)
              :ok
            end

            setup :verify_on_exit!

            unquote_splicing(Enum.reverse(operation_tests))
          end
        end

      %File{file | ast: test_ast}
      |> then(&%File{&1 | contents: implementation.format(state, &1)})
      |> then(fn file ->
        base_location = Utils.get_oapi_generator_config(state, :location, "")

        test_base_location = Utils.get_config(state, :test_location, "test")

        location =
          state
          |> implementation.location(file)
          |> Path.split()
          |> List.update_at(-1, fn filename -> Path.basename(filename, ".ex") <> "_test.exs" end)
          |> Path.join()
          |> then(&Path.join([test_base_location, Path.relative_to(&1, base_location)]))

        %File{file | location: location}
      end)
      |> then(&implementation.write(state, &1))
    end

    file_new = %File{file | operations: operations_new}
    OpenAPI.Renderer.Operation.render_all(state, file_new)
  end

  @impl true
  def render_operation_spec(
        state,
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
        fn %GeneratorParam{param: param} -> param end
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
     ]} = OpenAPI.Renderer.Operation.render_spec(state, operation_new)

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
        {String.to_atom(name), Util.to_type(state, type)}
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
        %OpenAPI.Renderer.State{profile: profile} = state,
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

    {:def, def_metadata,
     [
       {^function_name, _, _} = function_header,
       [do: {do_tag, do_metadata, do_expressions}]
     ]} = OpenAPI.Renderer.Operation.render_function(state, operation_new)

    do_expressions_new =
      Enum.flat_map(do_expressions, fn
        {:=, _, [{:client, _, _} | _]} = _client_expression ->
          param_assignments =
            all_params
            |> Enum.flat_map(fn
              %GeneratorParam{default: {m, f, a}, param: %Param{name: name}} ->
                atom = String.to_atom(name)
                variable = Macro.var(atom, nil)

                [
                  quote(
                    do:
                      unquote(variable) =
                        Keyword.get_lazy(opts, unquote(atom), fn ->
                          unquote(m).unquote(f)(unquote_splicing(a))
                        end)
                  )
                ]

              _ ->
                []
            end)

          client_pipeline_expression =
            case Utils.get_config(state, :client_pipeline) do
              {m, f, a} ->
                quote do:
                        client_pipeline =
                          Keyword.get_lazy(opts, :client_pipeline, fn ->
                            unquote(m).unquote(f)(unquote_splicing(a))
                          end)

              _ ->
                quote do: client_pipeline = opts[:client_pipeline]
            end

          base_url_expression =
            quote do: base_url = opts[:base_url] || @base_url

          [client_pipeline_expression, base_url_expression | param_assignments]

        {:=, _, [{:query, _, _} | _]} = _query_expression ->
          query_value =
            all_params
            |> Enum.filter(fn %GeneratorParam{param: %Param{location: location}} ->
              location == :query
            end)
            |> render_params_parse()

          if query_value do
            [quote(do: query_params = unquote(query_value))]
          else
            []
          end

        {{:., _, [{:client, _, _}, :request]} = _dot_expression, _dot_metadata,
         [
           {:%{}, _map_metadata, map_arguments}
         ]} = _call_expression ->
          headers_value =
            all_params
            |> Enum.filter(fn %GeneratorParam{param: %Param{location: location}} ->
              location == :header
            end)
            |> render_params_parse()

          {operation_assigns, private_assigns} =
            Enum.flat_map_reduce(map_arguments, %{__profile__: profile}, fn
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
                {[], Map.put(acc, :__opts__, value)}

              {:args, args}, acc ->
                {[],
                 Map.update(
                   acc,
                   :__info__,
                   quote(do: {nil, nil, unquote(args)}),
                   fn {:{}, [], [m, f, _a]} ->
                     quote do: {unquote(m), unquote(f), unquote(args)}
                   end
                 )}

              {:call, {_module, function}}, acc ->
                {[],
                 Map.update(
                   acc,
                   :__info__,
                   quote(do: {__MODULE__, unquote(function), nil}),
                   fn {:{}, [], [_m, _f, a]} ->
                     quote do: {__MODULE__, unquote(function), unquote(a)}
                   end
                 )}
            end)

          operation_assigns = [
            {:request_base_url, Macro.var(:base_url, nil)} | operation_assigns
          ]

          operation =
            quote do
              %OpenAPIClient.Client.Operation{unquote_splicing(operation_assigns)}
            end

          operation =
            if map_size(private_assigns) != 0 do
              quote do
                unquote(operation)
                |> OpenAPIClient.Client.Operation.put_private(
                  unquote(Map.to_list(private_assigns))
                )
              end
            else
              operation
            end

          [
            quote do
              unquote(operation)
              |> OpenAPIClient.Client.perform(unquote(Macro.var(:client_pipeline, nil)))
            end
          ]

        expression ->
          [expression]
      end)

    {:def, def_metadata,
     [
       function_header,
       [do: {do_tag, do_metadata, do_expressions_new}]
     ]}
  end

  defp render_params_parse([]), do: nil

  defp render_params_parse(params) do
    {static_params, dynamic_params} =
      params
      |> Enum.group_by(fn %GeneratorParam{static: static, default: default} ->
        static or not is_nil(default)
      end)
      |> then(fn map -> {Map.get(map, true, []), Map.get(map, false, [])} end)

    static_params =
      Enum.map(static_params, fn %GeneratorParam{param: %Param{name: name}, old_name: old_name} ->
        {old_name, name |> String.to_atom() |> Macro.var(nil)}
      end)

    {dynamic_params, param_renamings} =
      Enum.map_reduce(dynamic_params, [], fn %GeneratorParam{
                                               param: %Param{name: name},
                                               old_name: old_name
                                             },
                                             param_renamings ->
        param_renamings_new =
          [
            {:->, [],
             [
               [{String.to_atom(name), Macro.var(:value, nil)}],
               {old_name, Macro.var(:value, nil)}
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
      else
        nil
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

  defp parse_spec_return_type({:|, _, [type, next]}, acc),
    do: parse_spec_return_type(next, [type | acc])

  defp parse_spec_return_type(type, acc), do: Enum.reverse([type | acc])

  defp field_to_type(
         %GeneratorField{
           field: %Field{type: {:enum, _}},
           enum_options: enum_options,
           enum_strict: true
         },
         _state
       ),
       do: {:enum, enum_options}

  defp field_to_type(
         %GeneratorField{field: %Field{type: {:enum, _}}, enum_options: enum_options},
         _state
       ),
       do: {:enum, enum_options ++ [:not_strict]}

  defp field_to_type(
         %GeneratorField{field: %Field{type: {:array, {:enum, _} = enum}} = inner_field} = field,
         state
       ),
       do:
         {:array,
          field_to_type(%GeneratorField{field | field: %Field{inner_field | type: enum}}, state)}

  defp field_to_type(%GeneratorField{field: %Field{type: type}}, state),
    do: Util.to_readable_type(state, type)

  defp generate_operation_test_functions(%Operation{responses: []}, _state), do: []

  defp generate_operation_test_functions(
         %Operation{
           module_name: module_name,
           function_name: function_name,
           request_path: request_path,
           request_method: request_method,
           request_body: request_body,
           responses: responses
         },
         state
       ) do
    module_name = generate_module_name(module_name, state)

    {request_content_type, request_schema} = select_example_schema(request_body)
    {request_encoded, request_decoded} = generate_schema_example(request_schema, state)

    request_schema_test_message =
      if request_schema_test_message = test_message_schema(request_schema, state) do
        "encodes #{request_schema_test_message} from request's body"
      end

    {exact_responses, non_exact_responses} =
      Enum.split_with(responses, fn {status_code, _} -> is_integer(status_code) end)

    non_exact_responses
    |> Map.new()
    |> Enum.reduce(
      Map.new(exact_responses),
      fn {status_code, schemas}, responses ->
        status_code_range =
          case status_code do
            <<digit::utf8, "XX">> ->
              digit = digit - ?0
              ((digit + 1) * 100 - 1)..(digit * 100)

            :default ->
              if Utils.get_config(state, :default_status_code_as_failure) do
                599..400
              else
                299..200
              end
          end

        status_code_new =
          Enum.find(status_code_range, fn code -> not Map.has_key?(responses, code) end)

        Map.put(responses, status_code_new, schemas)
      end
    )
    |> Enum.sort_by(fn {status_code, _} -> status_code end)
    |> Enum.map(fn {status_code, schemas} ->
      {response_content_type, response_schema} = select_example_schema(schemas)
      {response_encoded, response_decoded} = generate_schema_example(response_schema, state)

      response_schema_test_message =
        if response_schema_test_message = test_message_schema(response_schema, state) do
          "encodes #{response_schema_test_message} from response's body"
        end

      [{_, %GeneratorOperation{params: all_params}}] =
        :ets.lookup(:operations, {request_path, request_method})

      expected_result_tag =
        if status_code >= 200 and status_code < 300 do
          :ok
        else
          :error
        end

      test_parameters =
        [
          Enum.map(all_params, &{:param, &1}),
          {:request_body, {request_content_type, request_encoded, request_decoded}},
          {:response_body, {response_content_type, response_encoded, response_decoded}}
        ]
        |> List.flatten()
        |> Enum.reduce(
          %{
            httpoison_request_arguments: [
              request_method,
              @test_example_url |> URI.merge(request_path) |> URI.to_string(),
              quote(do: _),
              quote(do: _),
              quote(do: _)
            ],
            call_arguments: [],
            call_opts: [base_url: @test_example_url],
            httpoison_request_query_params_assigned: false,
            httpoison_request_assertions: [],
            httpoison_response_fields: [{:status_code, status_code}],
            expected_result: expected_result_tag
          },
          fn
            {:param,
             %GeneratorParam{
               param: %Param{name: name, location: location},
               old_name: old_name,
               static: static
             } = param},
            acc ->
              param_example = example(param, state)

              acc_new =
                if static do
                  Map.update!(acc, :call_arguments, &[param_example | &1])
                else
                  Map.update!(acc, :call_opts, &[{String.to_atom(name), param_example} | &1])
                end

              case location do
                :path ->
                  acc_new
                  |> Map.update!(
                    :httpoison_request_arguments,
                    &List.update_at(&1, 1, fn url ->
                      String.replace(url, "{#{name}}", to_string(param_example))
                    end)
                  )

                :query ->
                  acc_new
                  |> Map.update!(
                    :httpoison_request_arguments,
                    &List.replace_at(&1, 4, quote(do: options))
                  )
                  |> Map.replace!(:httpoison_request_query_params_assigned, true)
                  |> Map.update!(
                    :httpoison_request_assertions,
                    &[
                      quote(do: assert(unquote(param_example) == query_params[unquote(old_name)]))
                      | &1
                    ]
                  )

                :header ->
                  acc_new
                  |> Map.update!(
                    :httpoison_request_arguments,
                    &List.replace_at(&1, 3, quote(do: headers))
                  )
                  |> Map.update!(
                    :httpoison_request_assertions,
                    &[
                      quote(
                        do:
                          assert(
                            {_, unquote(param_example)} ==
                              List.keyfind(headers, unquote(old_name), 0)
                          )
                      )
                      | &1
                    ]
                  )

                _ ->
                  acc_new
              end

            {:request_body, {nil, _, _}}, acc ->
              acc

            {:request_body, {content_type, body_encoded, body_decoded}}, acc ->
              acc_new =
                acc
                |> Map.update!(
                  :httpoison_request_arguments,
                  &List.replace_at(&1, 3, quote(do: headers))
                )
                |> Map.update!(
                  :httpoison_request_assertions,
                  &[
                    quote(
                      do:
                        assert(
                          {_, unquote(content_type)} ==
                            List.keyfind(headers, "Content-Type", 0)
                        )
                    )
                    | &1
                  ]
                )

              acc_new =
                acc_new
                |> Map.update!(
                  :httpoison_request_arguments,
                  &List.replace_at(&1, 2, quote(do: body))
                )

              if content_type == "application/json" do
                acc_new
                |> Map.update!(
                  :httpoison_request_assertions,
                  &[
                    quote do
                      assert unquote(body_encoded) == body |> Jason.decode!()
                    end
                    | &1
                  ]
                )
              else
                acc_new
                |> Map.update!(
                  :httpoison_request_assertions,
                  &[
                    quote do
                      assert to_string(unquote(body_encoded)) == body
                    end
                    | &1
                  ]
                )
              end
              |> Map.update!(:call_arguments, &[body_decoded | &1])

            {:response_body, {nil, _, _}}, acc ->
              acc

            {:response_body, {content_type, body_encoded, body_decoded}}, acc ->
              acc_new =
                acc
                |> Map.update!(
                  :httpoison_response_fields,
                  &[{:headers, quote(do: [{"Content-Type", unquote(content_type)}])} | &1]
                )

              if content_type == "application/json" do
                acc_new
                |> Map.update!(
                  :httpoison_response_fields,
                  &[{:body, quote(do: unquote(body_encoded) |> Jason.encode!())} | &1]
                )
              else
                acc_new
                |> Map.update!(
                  :httpoison_response_fields,
                  &[{:body, quote(do: unquote(body_encoded) |> to_string())} | &1]
                )
              end
              |> Map.replace!(
                :expected_result,
                {expected_result_tag, body_decoded}
              )
          end
        )

      test_message =
        ["performs a request", request_schema_test_message, response_schema_test_message]
        |> Enum.reject(&is_nil/1)
        |> Enum.split(-1)
        |> case do
          {[], [last_message]} ->
            last_message

          {comma_separated_messages, [last_message]} ->
            comma_separated_messages
            |> Enum.join(", ")
            |> then(&"#{&1} and #{last_message}")
        end
        |> then(&"[#{status_code}] #{&1}")

      quote do
        test unquote(test_message) do
          expect(
            @httpoison,
            :request,
            unquote(
              {:fn, [],
               [
                 {:->, [],
                  [
                    test_parameters[:httpoison_request_arguments],
                    quote do
                      unquote_splicing(
                        if(test_parameters[:httpoison_request_query_params_assigned],
                          do: [quote(do: query_params = options[:params])],
                          else: []
                        )
                      )

                      unquote_splicing(
                        Enum.reverse(test_parameters[:httpoison_request_assertions])
                      )

                      {:ok,
                       %HTTPoison.Response{
                         unquote_splicing(
                           Enum.reverse(test_parameters[:httpoison_response_fields])
                         )
                       }}
                    end
                  ]}
               ]}
            )
          )

          assert unquote(test_parameters[:expected_result]) ==
                   unquote(module_name).unquote(function_name)(
                     unquote_splicing(
                       Enum.reverse([
                         test_parameters[:call_opts] | test_parameters[:call_arguments]
                       ])
                     )
                   )
        end
      end
    end)
  end

  defp example(:null, _state), do: nil
  defp example(:boolean, _state), do: true
  defp example(:integer, _state), do: 1
  defp example(:number, _state), do: 1.0
  defp example({:string, :date}, _state), do: "2024-01-02"
  defp example({:string, :date_time}, _state), do: "2024-01-02T01:23:45Z"
  defp example({:string, :time}, _state), do: "01:23:45"
  defp example({:string, :uri}, _state), do: "http://example.com"
  defp example({:string, _}, _state), do: "string"
  defp example({:array, type}, state), do: [example(type, state)]
  defp example({:const, value}, _state), do: value
  defp example({:enum, [{_atom, value} | _]}, _state), do: value
  defp example({:enum, [value | _]}, _state), do: value
  defp example({:union, [type | _]}, state), do: example(type, state)
  defp example(type, _state) when type in [:any, :map], do: %{"a" => "b"}
  defp example(%GeneratorField{examples: [value | _]}, _state), do: value

  defp example(
         %GeneratorField{field: %Field{type: {:array, {:enum, _}}}, enum_options: enum_options},
         state
       ),
       do: example({:array, {:enum, enum_options}}, state)

  defp example(
         %GeneratorField{field: %Field{type: {:enum, _}}, enum_options: enum_options},
         state
       ),
       do: example({:enum, enum_options}, state)

  defp example(%GeneratorField{field: %Field{type: type}}, state), do: example(type, state)

  defp example(%GeneratorSchema{fields: all_fields}, state) do
    all_fields
    |> Enum.flat_map(fn
      %GeneratorField{field: nil} -> []
      %GeneratorField{old_name: name} = field -> [{name, example(field, state)}]
    end)
    |> Map.new()
  end

  defp example(schema_ref, state) when is_reference(schema_ref) do
    [{_, schema}] = :ets.lookup(:schemas, schema_ref)
    example(schema, state)
  end

  defp example(%GeneratorParam{param: %Param{value_type: type}}, state), do: example(type, state)

  defp select_example_schema([]), do: {nil, :null}

  defp select_example_schema(schemas) when is_map(schemas),
    do: schemas |> Map.to_list() |> select_example_schema()

  defp select_example_schema([body | _]), do: body

  defp generate_schema_example(:null, _state), do: {nil, nil}

  defp generate_schema_example(schema_ref, %OpenAPI.Renderer.State{schemas: schemas} = state)
       when is_reference(schema_ref) do
    [{_, generator_schema}] = :ets.lookup(:schemas, schema_ref)

    %Schema{module_name: module, type_name: type, output_format: _output_format} =
      Map.fetch!(schemas, schema_ref)

    example_encoded = example(generator_schema, state)

    module = generate_module_name(module, state)

    {:ok, example_decoded} =
      apply(ExampleTypedDecoder, :decode, [example_encoded, {module, type}])

    example_encoded =
      if is_map(example_encoded) do
        quote do
          %{unquote_splicing(Enum.sort_by(example_encoded, fn {name, _value} -> name end))}
        end
      else
        example_encoded
      end

    {example_encoded, example_decoded}
  end

  defp generate_schema_example(type, state) do
    example_encoded = example(type, state)
    {:ok, example_decoded} = apply(ExampleTypedDecoder, :decode, [example_encoded, type])

    example_encoded =
      if is_map(example_encoded) do
        quote do
          %{unquote_splicing(Enum.sort_by(example_encoded, fn {name, _value} -> name end))}
        end
      else
        example_encoded
      end

    {example_encoded, example_decoded}
  end

  defp generate_module_name(module_name, state) do
    Module.concat(Utils.get_oapi_generator_config(state, :base_module, ""), module_name)
  end

  defp test_message_schema(schema, state) do
    case Util.to_readable_type(state, schema) do
      [{module, _type}] ->
        if Macro.classify_atom(module) == :alias do
          module
          |> Module.split()
          |> Enum.join(".")
          |> then(&"array of #{&1}")
        else
          nil
        end

      [:map] ->
        "array of maps"

      {module, _type} ->
        if Macro.classify_atom(module) == :alias do
          module
          |> Module.split()
          |> Enum.join(".")
        else
          nil
        end

      :map ->
        "map"

      _ ->
        nil
    end
  end
end

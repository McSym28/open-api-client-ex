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

  @impl true
  def render_default_client(%OpenAPI.Renderer.State{profile: profile} = state, file) do
    case OpenAPI.Renderer.render_default_client(state, file) do
      {:@, _, [{:default_client, _, _}] = _default_client_expression} ->
        base_url =
          :open_api_client_ex |> Application.fetch_env!(profile) |> Keyword.fetch!(:base_url)

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
  def render_operation(
        state,
        %Operation{request_path: request_path, request_method: request_method} = operation
      ) do
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

    operation_new = %Operation{operation | request_path: request_path_new}

    OpenAPI.Renderer.Operation.render(state, operation_new)
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
        {:default, schemas} -> {299, schemas}
        {"2XX", schemas} -> {298, schemas}
        other -> other
      end)
      |> List.keystore(
        999,
        0,
        {999, %{"application/json" => {:const, quote(do: OpenAPIClient.Client.Error.t())}}}
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
          request_method: request_method
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
            :open_api_client_ex
            |> Application.get_env(profile, [])
            |> Keyword.get(:client_pipeline)
            |> case do
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

              {:response, value}, acc ->
                {[{:response_types, value}], acc}

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
end

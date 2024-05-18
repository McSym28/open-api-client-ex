defmodule OpenAPIGenerator.Renderer do
  use OpenAPI.Renderer
  alias OpenAPI.Renderer.{File, Util}
  alias OpenAPI.Processor.{Naming, Operation, Schema}
  alias Schema.Field
  alias Operation.Param
  alias OpenAPIGenerator.Utils
  alias OpenAPIGenerator.Operation, as: GeneratorOperation
  alias OpenAPIGenerator.Param, as: GeneratorParam

  @schema_renamings_key :schema_renamings
  @extra_fields :oapi_generator
                |> Application.get_all_env()
                |> Enum.map(fn {key, options} -> {key, options[:output][:extra_fields]} end)
                |> Enum.filter(fn {_key, extra_fields} -> extra_fields end)
                |> Map.new()

  defmodule RenderedField do
    defstruct old_name: nil, enforce: false, enum_aliases: %{}, enum_type: nil
  end

  @impl true
  def render_schema(
        %OpenAPI.Renderer.State{profile: profile} = state,
        %File{module: _module, schemas: schemas} = file
      ) do
    extra_fields = Map.get(@extra_fields, profile, [])

    {schemas_new, renamings} =
      Enum.map_reduce(schemas, %{}, &process_schema(&1, &2, extra_fields))

    file_new = %File{file | schemas: schemas_new}
    Process.put(@schema_renamings_key, renamings)
    result = OpenAPI.Renderer.render_schema(state, file_new)
    Process.delete(@schema_renamings_key)
    result
  end

  @impl true
  def render_schema_types(state, schemas) do
    schemas_new =
      case Process.get(@schema_renamings_key) do
        renamings when is_map(renamings) and map_size(renamings) > 0 ->
          Enum.map(schemas, fn %Schema{ref: ref, fields: fields} = schema ->
            with field_renamings when is_map(renamings) <- Map.get(renamings, ref) do
              fields_new =
                Enum.map(fields, fn field ->
                  with %Field{name: name, type: {:enum, _} = type} <- field,
                       %RenderedField{enum_type: enum_type} when not is_nil(enum_type) <-
                         Map.get(field_renamings, name) do
                    %Field{field | type: {:union, [type, enum_type]}}
                  else
                    _ -> field
                  end
                end)

              %Schema{schema | fields: fields_new}
            else
              _ -> schema
            end
          end)

        _ ->
          schemas
      end

    OpenAPI.Renderer.render_schema_types(state, schemas_new)
  end

  @impl true
  def render_schema_struct(state, schemas) do
    struct_result = OpenAPI.Renderer.render_schema_struct(state, schemas)

    with renamings when is_map(renamings) <- Process.get(@schema_renamings_key),
         enforced_keys when enforced_keys != [] <-
           renamings
           |> Enum.map(fn {_schema_ref, field_renamings} ->
             Enum.flat_map(field_renamings, fn {name, %RenderedField{enforce: enforce}} ->
               if(enforce, do: [String.to_atom(name)], else: [])
             end)
           end)
           |> List.flatten() do
      enforced_keys_result =
        quote do
          @enforce_keys unquote(enforced_keys)
        end

      OpenAPI.Renderer.Util.put_newlines([enforced_keys_result, struct_result])
    else
      _ -> struct_result
    end
  end

  @impl true
  def render_schema_field_function(state, schemas) do
    fields_result = OpenAPI.Renderer.render_schema_field_function(state, schemas)

    case Process.get(@schema_renamings_key) do
      renamings when is_map(renamings) and map_size(renamings) > 0 ->
        Enum.map(fields_result, fn statement ->
          with {:def, def_metadata,
                [{:__fields__, fields_metadata, [schema_type]}, [do: field_clauses]]} <-
                 statement,
               schema_ref when not is_nil(schema_ref) <-
                 Enum.find_value(schemas, fn %Schema{type_name: type_name, ref: ref} ->
                   if(schema_type == type_name, do: ref)
                 end),
               field_renamings when is_map(renamings) <- Map.get(renamings, schema_ref) do
            field_clauses_new =
              Enum.map(field_clauses, fn {name, type} ->
                string_name = Atom.to_string(name)

                with %RenderedField{old_name: old_name, enum_aliases: enum_aliases} <-
                       Map.get(field_renamings, string_name) do
                  type_new =
                    case type do
                      {:enum, _} -> {:enum, enum_aliases}
                      _ -> type
                    end

                  if name == old_name do
                    {name, type_new}
                  else
                    {name, {old_name, type_new}}
                  end
                else
                  _ -> {name, type}
                end
              end)

            {:def, def_metadata,
             [{:__fields__, fields_metadata, [schema_type]}, [do: field_clauses_new]]}
          else
            _ -> statement
          end
        end)

      _ ->
        fields_result
    end
  end

  @impl true
  def render_operation(
        state,
        %Operation{request_path: request_path, request_method: request_method} = operation
      ) do
    case :ets.lookup(:operations, {request_path, request_method}) do
      [{_, %GeneratorOperation{param_renamings: param_renamings}}] ->
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

      [] ->
        OpenAPI.Renderer.Operation.render(state, operation)
    end
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
    case :ets.lookup(:operations, {request_path, request_method}) do
      [{_, %GeneratorOperation{params: all_params}}] ->
        {static_params, dynamic_params} =
          all_params
          |> Enum.group_by(
            fn %GeneratorParam{static: static} -> static end,
            fn %GeneratorParam{param: param} -> param end
          )
          |> then(fn map -> {Map.get(map, true, []), Map.get(map, false, [])} end)

        responses_new =
          List.keystore(
            responses,
            999,
            0,
            {999, %{"application/json" => {:const, {:client, quote(do: term())}}}}
          )

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

        opts_spec =
          dynamic_params
          |> Enum.map(fn %Param{name: name, value_type: type} ->
            {String.to_atom(name), Util.to_type(state, type)}
          end)
          |> Kernel.++([{:client, quote(do: module())}])
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
                 return_type
               ]}
            ]}
         ]}

      [] ->
        OpenAPI.Renderer.Operation.render_spec(state, operation)
    end
  end

  @impl true
  def render_operation_function(
        state,
        %Operation{
          function_name: function_name,
          request_path: request_path,
          request_method: request_method
        } = operation
      ) do
    case :ets.lookup(:operations, {request_path, request_method}) do
      [{_, %GeneratorOperation{params: all_params}}] ->
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
           [do: {do_tag, do_metadata, do_statements}]
         ]} = OpenAPI.Renderer.Operation.render_function(state, operation_new)

        do_statements_new =
          Enum.flat_map(do_statements, fn
            {:=, _, [{:client, _, _} | _]} = client_statement ->
              param_assignments =
                all_params
                |> Enum.flat_map(fn
                  %GeneratorParam{default: {m, f, a}, param: %Param{name: name}} ->
                    [
                      {:=, [],
                       [
                         {String.to_atom(name), [], nil},
                         {{:., [], [{:__aliases__, [alias: false], [:Keyword]}, :get_lazy]}, [],
                          [
                            {:opts, [], nil},
                            String.to_atom(name),
                            {:fn, [],
                             [
                               {:->, [],
                                [
                                  [],
                                  Utils.ast_function_call(m, f, a)
                                ]}
                             ]}
                          ]}
                       ]}
                    ]

                  _ ->
                    []
                end)

              [client_statement | param_assignments]

            {:=, _, [{:query, _, _} | _]} = _query_statement ->
              query_value =
                all_params
                |> Enum.filter(fn %GeneratorParam{param: %Param{location: location}} ->
                  location == :query
                end)
                |> render_params_parse()

              if query_value do
                [{:=, [], [{:query, [], nil}, query_value]}]
              else
                []
              end

            {{:., _, [{:client, _, _}, :request]} = dot_statement, dot_metadata,
             [
               {:%{}, map_metadata, map_arguments}
             ]} = call_statement ->
              headers_value =
                all_params
                |> Enum.filter(fn %GeneratorParam{param: %Param{location: location}} ->
                  location == :header
                end)
                |> render_params_parse()

              if headers_value do
                map_arguments_new =
                  Enum.flat_map(map_arguments, fn
                    {:opts, _} = arg -> [{:headers, {:headers, [], nil}} | [arg]]
                    arg -> [arg]
                  end)

                call_statement_new =
                  {dot_statement, dot_metadata, [{:%{}, map_metadata, map_arguments_new}]}

                [{:=, [], [{:headers, [], nil}, headers_value]}, call_statement_new]
              else
                [call_statement]
              end

            statement ->
              [statement]
          end)

        {:def, def_metadata,
         [
           function_header,
           [do: {do_tag, do_metadata, do_statements_new}]
         ]}

      [] ->
        OpenAPI.Renderer.Operation.render_function(state, operation)
    end
  end

  defp process_schema(%Schema{ref: ref, fields: fields} = schema, acc, extra_fields) do
    {fields_new, field_renamings} = Enum.map_reduce(fields, %{}, &process_field/2)
    schema_new = %Schema{schema | fields: fields_new}

    field_renamings =
      Enum.reduce(extra_fields, field_renamings, fn {key, _type}, acc ->
        Map.put(acc, key, %RenderedField{old_name: key, enforce: true})
      end)

    acc_new = Map.put(acc, ref, field_renamings)
    {schema_new, acc_new}
  end

  defp process_field(
         %Field{name: name, type: {:enum, enum_values}, required: required, nullable: nullable} =
           field,
         acc
       ) do
    {enum_values_new, {enum_type, enum_aliases}} =
      Enum.map_reduce(enum_values, {nil, %{}}, &process_enum_value/2)

    name_new = Naming.normalize_identifier(name)
    field_new = %Field{field | name: name_new, type: {:enum, enum_values_new}}

    rendered_field = %RenderedField{
      old_name: name,
      enum_aliases: enum_aliases,
      enum_type: enum_type,
      enforce: required and not nullable
    }

    acc_new = Map.put(acc, name_new, rendered_field)
    {field_new, acc_new}
  end

  defp process_field(%Field{name: name, required: required, nullable: nullable} = field, acc) do
    name_new = Naming.normalize_identifier(name)
    field_new = %Field{field | name: name_new}
    rendered_field = %RenderedField{old_name: name, enforce: required and not nullable}
    acc_new = Map.put(acc, name_new, rendered_field)
    {field_new, acc_new}
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
        if name != old_name do
          {old_name, {String.to_atom(name), [], nil}}
        else
          {String.to_atom(name), {String.to_atom(name), [], nil}}
        end
      end)

    {dynamic_params, {param_renamings, has_same_name}} =
      Enum.map_reduce(dynamic_params, {[], false}, fn %GeneratorParam{
                                                        param: %Param{name: name},
                                                        old_name: old_name
                                                      },
                                                      {param_renamings, has_same_name} ->
        if name != old_name do
          param_renamings_new =
            [
              {:->, [],
               [
                 [{String.to_atom(name), {:value, [], nil}}],
                 {old_name, {:value, [], nil}}
               ]}
              | param_renamings
            ]

          {String.to_atom(name), {param_renamings_new, has_same_name}}
        else
          {String.to_atom(name), {param_renamings, true}}
        end
      end)

    dynamic_params =
      if length(dynamic_params) > 0 do
        param_renamings =
          if has_same_name do
            param_renamings ++
              [
                {:->, [],
                 [
                   [{{:key, [], nil}, {:value, [], nil}}],
                   {{:key, [], nil}, {:value, [], nil}}
                 ]}
              ]
          else
            param_renamings
          end

        if length(param_renamings) > 0 do
          {:|>, [],
           [
             quote(do: opts |> Keyword.take(unquote(dynamic_params))),
             {{:., [], [{:__aliases__, [alias: false], [:Enum]}, :map]}, [],
              [{:fn, [], param_renamings}]}
           ]}
        else
          quote do: Keyword.take(opts, unquote(dynamic_params))
        end
      else
        nil
      end

    case {length(static_params) > 0, not is_nil(dynamic_params)} do
      {true, false} -> static_params
      {false, true} -> dynamic_params
      {true, true} -> {:++, [], [dynamic_params, static_params]}
    end
  end
end

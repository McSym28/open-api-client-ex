defmodule OpenAPIGenerator.Renderer do
  use OpenAPI.Renderer
  alias OpenAPI.Renderer.{File, Util}
  alias OpenAPI.Processor.{Naming, Operation, Schema}
  alias Schema.Field
  alias Operation.Param
  alias OpenAPIGenerator.Utils

  @schema_renamings_key :schema_renamings
  @param_renamings_key :param_renamings
  @extra_fields :oapi_generator
                |> Application.get_all_env()
                |> Enum.map(fn {key, options} -> {key, options[:output][:extra_fields]} end)
                |> Enum.filter(fn {_key, extra_fields} -> extra_fields end)
                |> Map.new()

  defmodule RenderedField do
    defstruct old_name: nil, enforce: false, enum_aliases: %{}, enum_type: nil
  end

  defmodule RenderedParam do
    defstruct old_name: nil, config: []
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
        %OpenAPI.Renderer.State{profile: profile} = state,
        %Operation{
          request_path: path,
          request_method: method,
          request_path_parameters: path_params,
          request_query_parameters: query_params,
          request_header_parameters: header_params
        } = operation
      ) do
    operation_config = Utils.operation_config(profile, path, method)
    param_configs = Keyword.get(operation_config, :params, [])

    path_new =
      String.replace(path, ~r/\{([[:word:]]+)\}/, fn word ->
        word
        |> String.split(["{", "}"])
        |> Enum.at(1)
        |> then(fn name ->
          {_, config} = List.keyfind(param_configs, {name, :path}, 0, {name, []})
          name_new = rename_param(config, name)
          "{#{name_new}}"
        end)
      end)

    process_param_fun = fn %Param{name: name, location: location} = param, acc ->
      {_, config} = List.keyfind(param_configs, {name, location}, 0, {name, []})
      name_new = rename_param(config, name)
      param_new = %Param{param | name: name_new}
      acc_new = Map.put(acc, {name_new, location}, %RenderedParam{old_name: name, config: config})
      {param_new, acc_new}
    end

    {path_params_new, renamings} =
      Enum.map_reduce(path_params, %{}, process_param_fun)

    {query_params_new, renamings} =
      Enum.map_reduce(query_params, renamings, process_param_fun)

    {header_params_new, renamings} =
      Enum.map_reduce(header_params, renamings, process_param_fun)

    operation_new = %Operation{
      operation
      | request_path: path_new,
        request_path_parameters: path_params_new,
        request_query_parameters: query_params_new,
        request_header_parameters: header_params_new
    }

    Process.put(@param_renamings_key, renamings)
    result = OpenAPI.Renderer.Operation.render(state, operation_new)
    Process.delete(@param_renamings_key)

    result
  end

  @impl true
  def render_operation_spec(
        state,
        %Operation{
          function_name: function_name,
          request_path_parameters: path_params,
          request_query_parameters: query_params,
          request_header_parameters: header_params,
          responses: responses
        } = operation
      ) do
    renamings = Process.get(@param_renamings_key)

    {static_params, dynamic_params} =
      [path_params, query_params, header_params]
      |> List.flatten()
      |> Enum.split_with(fn
        %Param{required: false, location: location} when location != :path -> false
        param -> is_nil(param_default(param, renamings))
      end)

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
  end

  @impl true
  def render_operation_function(
        state,
        %Operation{
          function_name: function_name,
          request_path_parameters: path_params,
          request_query_parameters: query_params,
          request_header_parameters: header_params
        } = operation
      ) do
    renamings = Process.get(@param_renamings_key)

    all_params =
      [path_params, query_params, header_params]
      |> List.flatten()

    static_params =
      Enum.filter(all_params, fn
        %Param{required: false, location: location} when location != :path -> false
        param -> is_nil(param_default(param, renamings))
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
              %Param{name: name} = param ->
                case param_default(param, renamings) do
                  {m, f, a} ->
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
                end
            end)

          [client_statement | param_assignments]

        {:=, _, [{:query, _, _} | _]} = _query_statement ->
          query_value = render_params_parse(query_params, renamings)

          if query_value do
            [{:=, [], [{:query, [], nil}, query_value]}]
          else
            []
          end

        {{:., _, [{:client, _, _}, :request]} = dot_statement, dot_metadata,
         [
           {:%{}, map_metadata, map_arguments}
         ]} = call_statement ->
          headers_value = render_params_parse(header_params, renamings)

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

  defp rename_param(config, name) do
    Keyword.get_lazy(config, :name, fn -> Naming.normalize_identifier(name) end)
  end

  defp param_default(%Param{name: name, location: location}, renamings) do
    case renamings && renamings[{name, location}] do
      %RenderedParam{config: config} when is_list(config) -> Keyword.get(config, :default)
      _ -> nil
    end
  end

  defp render_params_parse([], _renamings), do: nil

  defp render_params_parse([%Param{location: location} | _] = params, renamings) do
    {static_params, dynamic_params} =
      params
      |> Enum.sort_by(& &1.name)
      |> Enum.split_with(fn
        %Param{required: true} -> true
        param -> not is_nil(param_default(param, renamings))
      end)

    static_params =
      Enum.map(static_params, fn %Param{name: name} ->
        case renamings && renamings[{name, location}] do
          %RenderedParam{old_name: old_name} when name != old_name ->
            {old_name, {String.to_atom(name), [], nil}}

          _ ->
            {String.to_atom(name), {String.to_atom(name), [], nil}}
        end
      end)

    {dynamic_params, {param_renamings, has_same_name}} =
      Enum.map_reduce(dynamic_params, {[], false}, fn %Param{name: name},
                                                      {param_renamings, has_same_name} ->
        case renamings && renamings[{name, location}] do
          %RenderedParam{old_name: old_name} when name != old_name ->
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

          _ ->
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

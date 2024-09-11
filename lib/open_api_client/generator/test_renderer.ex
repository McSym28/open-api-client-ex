if Mix.env() in [:dev, :test] do
  defmodule OpenAPIClient.Generator.TestRenderer do
    defmacro __using__(_opts) do
      quote do
        @behaviour OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate render(state, file), to: OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate render_header(state, file), to: OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate module(state, file), to: OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate format(state, file), to: OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate location(state, file), to: OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate write(state, file), to: OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate render_operation(state, operation), to: OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate render_operation_test(
                      state,
                      operation,
                      request_schema,
                      response_schema
                    ),
                    to: OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate render_callback_controller_header(state, operation),
          to: OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate render_callback_controller_function(state, operation),
          to: OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate callback_module(state, file, operation, module_type),
          to: OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate callback_location(state, file, operation, module_type),
          to: OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate render_callback_header(state, operation),
          to: OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate render_callback(state, operation), to: OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate render_callback_scope(state, operation),
          to: OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate example(state, type, path), to: OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate decode_example(state, value, type, path),
          to: OpenAPIClient.Generator.TestRenderer

        defoverridable render: 2,
                       render_header: 2,
                       module: 2,
                       format: 2,
                       location: 2,
                       write: 2,
                       render_operation: 2,
                       render_operation_test: 4,
                       render_callback_controller_header: 2,
                       render_callback_controller_function: 2,
                       callback_module: 4,
                       callback_location: 4,
                       render_callback_header: 2,
                       render_callback: 2,
                       render_callback_scope: 2,
                       example: 3,
                       decode_example: 4
      end
    end

    alias OpenAPI.Processor.{Operation, Schema}
    alias Operation.Param
    alias Schema.Field
    alias OpenAPIClient.Generator.TestRenderer.State
    alias OpenAPI.Renderer.File, as: RendererFile
    alias OpenAPIClient.Generator.Operation, as: GeneratorOperation
    alias OpenAPIClient.Generator.Param, as: GeneratorParam
    alias OpenAPIClient.Generator.Schema, as: GeneratorSchema
    alias OpenAPIClient.Generator.Field, as: GeneratorField
    alias OpenAPIClient.Generator.Utils
    alias OpenAPI.Renderer.Util
    alias OpenAPIClient.Generator.SchemaType
    alias OpenAPIClient.Generator.TestRenderer.ExampleSchemaFieldsAgent
    import Mox

    @type type_example_path ::
            list(
              String.t()
              | nonempty_list(non_neg_integer())
              | {:parameter, atom(), String.t()}
              | {:request_body, OpenAPIClient.Client.Operation.content_type()}
              | {:response_body, OpenAPIClient.Client.Operation.response_status_code(),
                 OpenAPIClient.Client.Operation.content_type()}
              | {OpenAPIClient.Client.Operation.url(), OpenAPIClient.Client.Operation.method()}
            )

    @type callback_module_type :: :controller | :controller_test

    @callback render(state :: State.t(), file :: RendererFile.t()) :: :ok
    @callback render_header(state :: State.t(), file :: RendererFile.t()) :: Macro.t()
    @callback module(state :: State.t(), file :: RendererFile.t()) :: module()
    @callback format(state :: State.t(), file :: RendererFile.t()) :: iodata()
    @callback location(state :: State.t(), file :: RendererFile.t()) :: String.t()
    @callback write(state :: State.t(), file :: RendererFile.t()) :: :ok
    @callback render_operation(state :: State.t(), operation :: Operation.t()) :: Macro.t()
    @callback render_operation_test(
                state :: State.t(),
                operation :: Operation.t(),
                request_schema ::
                  {content_type :: String.t() | nil, schema :: OpenAPI.Processor.Type.t()},
                response_schema ::
                  {content_type :: String.t() | nil, schema :: OpenAPI.Processor.Type.t(),
                   status_code :: integer()}
              ) :: Macro.t()
    @callback render_callback_controller_header(state :: State.t(), operation :: Operation.t()) ::
                Macro.t()
    @callback render_callback_controller_function(state :: State.t(), operation :: Operation.t()) ::
                Macro.t()
    @callback callback_module(
                state :: State.t(),
                file :: RendererFile.t(),
                operation :: Operation.t(),
                module_type :: callback_module_type()
              ) :: module()
    @callback callback_location(
                state :: State.t(),
                file :: RendererFile.t(),
                operation :: Operation.t(),
                module_type :: callback_module_type()
              ) :: String.t()
    @callback render_callback_header(state :: State.t(), operation :: Operation.t()) :: Macro.t()
    @callback render_callback(state :: State.t(), operation :: Operation.t()) :: Macro.t()
    @callback render_callback_scope(state :: State.t(), operation :: Operation.t()) :: Macro.t()
    @callback example(
                state :: State.t(),
                type ::
                  OpenAPIClient.Schema.type()
                  | GeneratorParam.t()
                  | GeneratorSchema.t()
                  | GeneratorField.t()
                  | OpenAPI.Processor.Type.t(),
                path :: type_example_path()
              ) :: term()
    @callback decode_example(
                state :: State.t(),
                value :: term(),
                type ::
                  OpenAPIClient.Schema.type() | GeneratorSchema.t() | OpenAPI.Processor.Type.t(),
                path :: type_example_path()
              ) :: {:ok, term()} | {:error, OpenAPIClient.Client.Error.t()}

    @optional_callbacks render: 2,
                        render_header: 2,
                        module: 2,
                        format: 2,
                        location: 2,
                        write: 2,
                        render_operation: 2,
                        render_operation_test: 4,
                        render_callback_controller_header: 2,
                        render_callback_controller_function: 2,
                        callback_module: 4,
                        callback_location: 4,
                        render_callback_header: 2,
                        render_callback: 2,
                        render_callback_scope: 2,
                        example: 3,
                        decode_example: 4

    @test_example_url "https://example.com"

    @example_schema ExampleSchema
    @example_typed_decoder ExampleTypedDecoder

    @behaviour __MODULE__

    @impl __MODULE__
    def render(
          %State{implementation: implementation} = state,
          %RendererFile{operations: file_operations} = file
        ) do
      ensure_schema_fields_agent()

      stub(@example_typed_decoder, :decode, fn value, type, path, _caller_module ->
        implementation.decode_example(state, value, type, path)
      end)

      {non_operations, operations} =
        Enum.split_with(file_operations, fn %Operation{
                                              request_path: request_path,
                                              request_method: request_method
                                            } ->
          [{_, %GeneratorOperation{type: operation_type}}] =
            :ets.lookup(:operations, {request_path, request_method})

          operation_type in [:callback, :webhook]
        end)

      operations
      |> Enum.map(&implementation.render_operation(state, &1))
      |> Util.clean_list()
      |> case do
        [] ->
          :ok

        tests ->
          %RendererFile{file | ast: nil, contents: nil, location: nil}
          |> then(&%RendererFile{&1 | module: implementation.module(state, &1)})
          |> then(fn %RendererFile{module: module} = file ->
            header =
              state
              |> implementation.render_header(file)
              |> case do
                [] -> []
                expressions -> Util.put_newlines(expressions)
              end

            ast =
              quote do
                defmodule unquote(generate_module_name(state, module)) do
                  unquote_splicing(header)
                  unquote_splicing(tests)
                end
              end

            %RendererFile{file | ast: ast}
          end)
          |> then(&%RendererFile{&1 | contents: implementation.format(state, &1)})
          |> then(&%RendererFile{&1 | location: implementation.location(state, &1)})
          |> then(&implementation.write(state, &1))
      end

      non_operations
      |> Enum.map(fn %Operation{module_name: module_name} = operation ->
        %RendererFile{
          file
          | module: nil,
            ast: nil,
            contents: nil,
            location: nil,
            operations: [operation]
        }
        |> then(
          &%RendererFile{
            &1
            | module: implementation.callback_module(state, &1, operation, :controller)
          }
        )
        |> then(fn %RendererFile{module: module} = file ->
          header =
            state
            |> implementation.render_callback_controller_header(operation)
            |> case do
              [] -> []
              expressions -> Util.put_newlines(expressions)
            end

          function = implementation.render_callback_controller_function(state, operation)

          ast =
            quote do
              defmodule unquote(Module.concat([get_web_base_module(state), module])) do
                unquote_splicing(header)
                unquote(function)
              end
            end

          %RendererFile{file | ast: ast}
        end)
        |> then(&%RendererFile{&1 | contents: implementation.format(state, &1)})
        |> then(
          &%RendererFile{
            &1
            | location: implementation.callback_location(state, &1, operation, :controller)
          }
        )
        |> then(&implementation.write(state, &1))

        %RendererFile{
          file
          | module: nil,
            ast: nil,
            contents: nil,
            location: nil,
            operations: [operation]
        }
        |> then(
          &%RendererFile{
            &1
            | module: implementation.callback_module(state, &1, operation, :controller_test)
          }
        )
        |> then(fn %RendererFile{module: module} = file ->
          state
          |> implementation.render_callback(operation)
          |> case do
            nil ->
              file

            describe_ast ->
              header =
                state
                |> implementation.render_callback_header(operation)
                |> case do
                  [] -> []
                  expressions -> Util.put_newlines(expressions)
                end

              ast =
                quote do
                  defmodule unquote(Module.concat([get_web_base_module(state), module])) do
                    unquote_splicing(header)
                    unquote(describe_ast)
                  end
                end

              %RendererFile{file | ast: ast}
          end
        end)
        |> then(&%RendererFile{&1 | contents: implementation.format(state, &1)})
        |> then(
          &%RendererFile{
            &1
            | location: implementation.callback_location(state, &1, operation, :controller_test)
          }
        )
        |> then(&implementation.write(state, &1))

        route_scope = implementation.render_callback_scope(state, operation)

        update_router_test_scope(state, fn test_scopes ->
          module_scope_path =
            module_name
            |> Module.split()
            |> Enum.map_join("/", &Macro.underscore/1)
            |> then(&"/#{&1}")

          scoped_aliases = module_name |> Module.split() |> Enum.map(&String.to_atom/1)

          test_scopes
          |> Enum.map_reduce(false, fn
            expression, true ->
              {expression, true}

            {:scope, scope_metadata,
             [
               ^module_scope_path,
               {:__aliases__, _alias_metadata, ^scoped_aliases} = scope_alias,
               [
                 do: route_scopes
               ]
             ]},
            false ->
              route_scopes_new =
                route_scopes
                |> case do
                  {:__block__, _scopes_block_metadata, scopes_block_expressions} ->
                    scopes_block_expressions

                  {:scope, _, _} = single_scope ->
                    [single_scope]
                end
                |> Kernel.++([route_scope])

              expression_new =
                {:scope, scope_metadata,
                 [
                   module_scope_path,
                   scope_alias,
                   [
                     do: {:__block__, [], route_scopes_new}
                   ]
                 ]}

              {expression_new, true}

            expression, false ->
              {expression, false}
          end)
          |> case do
            {scopes, true} ->
              scopes

            {scopes, false} ->
              scopes ++
                [
                  quote(
                    do:
                      scope unquote(module_scope_path), unquote(module_name) do
                        unquote(route_scope)
                      end
                  )
                ]
          end
        end)
      end)

      :ok
    end

    @impl __MODULE__
    def module(_state, %RendererFile{module: module} = _file) do
      module
      |> Module.split()
      |> List.update_at(-1, &"#{&1}Test")
      |> Module.concat()
    end

    @impl __MODULE__
    def callback_module(
          state,
          _file,
          %Operation{module_name: module_name} = operation,
          :controller
        ) do
      Module.concat([module_name, get_controller_module_name(state, operation)])
    end

    def callback_module(
          %State{implementation: implementation} = state,
          file,
          operation,
          :controller_test
        ) do
      state
      |> implementation.callback_module(file, operation, :controller)
      |> Module.split()
      |> List.update_at(-1, &"#{&1}Test")
      |> Module.concat()
    end

    @impl __MODULE__
    def format(_state, %RendererFile{ast: nil} = _file), do: nil

    def format(_state, %RendererFile{ast: ast} = _file) do
      # All this effort just not to have parenthesis in `describe/*`, `test/*`, `pipeline/*` and `scope/*` calls
      ast
      |> OpenAPI.Renderer.Util.format_multiline_docs()
      |> Code.quoted_to_algebra(
        escape: false,
        locals_without_parens: [describe: :*, test: :*, pipeline: :*, scope: :*]
      )
      |> Inspect.Algebra.format(98)
    end

    @impl __MODULE__
    def location(
          %State{
            renderer_state:
              %OpenAPI.Renderer.State{implementation: renderer_implementaion} = renderer_state
          } = state,
          file
        ) do
      base_location = Utils.get_oapi_generator_config(state, :location, "")

      test_base_location = Utils.get_test_location(state)

      renderer_state
      |> renderer_implementaion.location(file)
      |> Path.split()
      |> List.update_at(-1, fn filename -> Path.basename(filename, ".ex") <> ".exs" end)
      |> Path.join()
      |> then(&Path.join([test_base_location, Path.relative_to(&1, base_location)]))
    end

    @impl __MODULE__
    def callback_location(state, %RendererFile{module: module}, _operation, :controller) do
      base_location =
        state
        |> Utils.get_web_location()
        |> Path.split()
        |> List.insert_at(-1, "controllers")
        |> Path.join()

      module
      |> Module.split()
      |> Enum.map(&Macro.underscore/1)
      |> List.update_at(-1, &"#{&1}.ex")
      |> then(&[base_location | &1])
      |> Path.join()
    end

    def callback_location(state, %RendererFile{module: module}, _operation, :controller_test) do
      base_location =
        state
        |> Utils.get_web_test_location()
        |> Path.split()
        |> List.insert_at(-1, "controllers")
        |> Path.join()

      module
      |> Module.split()
      |> Enum.map(&Macro.underscore/1)
      |> List.update_at(-1, &"#{&1}.exs")
      |> then(&[base_location | &1])
      |> Path.join()
    end

    @impl __MODULE__
    def write(_state, %RendererFile{contents: nil} = _file), do: :ok
    def write(_state, %RendererFile{contents: ""} = _file), do: :ok

    def write(
          %State{
            renderer_state:
              %OpenAPI.Renderer.State{implementation: renderer_implementaion} = renderer_state
          } = _state,
          file
        ),
        do: renderer_implementaion.write(renderer_state, file)

    @impl __MODULE__
    def render_operation(
          %State{implementation: implementation} = state,
          %Operation{
            request_path: request_path,
            request_method: request_method,
            request_body: request_body,
            function_name: function_name,
            responses: responses
          } = operation
        ) do
      {request_content_type, request_schema} =
        select_example_schema(state, request_body, :decoders)

      {exact_responses, non_exact_responses} =
        Enum.split_with(responses, fn {status_code, _} -> is_integer(status_code) end)

      non_exact_responses
      |> Enum.reduce(
        exact_responses,
        fn {status_code, schemas}, responses ->
          status_code_range =
            case status_code do
              <<digit::utf8, "XX">> ->
                digit = digit - ?0
                ((digit + 1) * 100 - 1)..(digit * 100)

              true ->
                299..200

              false ->
                599..400
            end

          status_code_new =
            Enum.find(status_code_range, fn code -> not List.keymember?(responses, code, 0) end)

          List.keystore(responses, status_code_new, 0, {status_code_new, schemas})
        end
      )
      |> Enum.sort_by(fn {status_code, _} -> status_code end)
      |> Enum.map(fn {status_code, schemas} ->
        {response_content_type, response_schema} =
          select_example_schema(state, schemas, :encoders)

        implementation.render_operation_test(
          state,
          operation,
          {request_content_type, request_schema},
          {response_content_type, response_schema, status_code}
        )
      end)
      |> case do
        [] ->
          []

        tests ->
          [{_, generator_operation}] =
            :ets.lookup(:operations, {request_path, request_method})

          arity = Utils.get_function_arity(state, operation, generator_operation)

          describe_message = "#{function_name}/#{arity}"

          quote do
            describe unquote(describe_message) do
              (unquote_splicing(tests))
            end
          end
      end
    end

    @impl __MODULE__
    def render_header(_state, _file) do
      [
        quote(do: use(ExUnit.Case, async: true)),
        quote(do: import(Mox)) |> Util.put_newlines(),
        quote(do: @httpoison(OpenAPIClient.HTTPoisonMock)),
        quote(do: @client(OpenAPIClient.ClientMock)) |> Util.put_newlines(),
        quote(do: setup(:verify_on_exit!))
      ]
    end

    @impl __MODULE__
    def render_callback_controller_header(
          state,
          %Operation{module_name: module_name, function_name: function_name} = _operation
        ) do
      behaviour_module = generate_module_name(state, module_name)

      behaviour_mock_module =
        behaviour_module
        |> Module.split()
        |> List.update_at(-1, &"#{&1}Mock")
        |> Module.concat()

      operation_profile =
        Utils.get_config(state, :aliased_profile, state.renderer_state.profile)

      web_base_module = get_web_base_module(state)

      [
        quote(do: use(unquote(web_base_module), :controller)) |> Util.put_newlines(),
        quote(
          do:
            plug(OpenAPIClientWeb.Plugs.Callback,
              implementation: unquote(behaviour_mock_module),
              behaviour: unquote(behaviour_module),
              function_name: unquote(function_name),
              profile: unquote(operation_profile)
            )
        )
      ]
    end

    @impl __MODULE__
    def render_callback_controller_function(
          _state,
          %Operation{function_name: function_name} = _operation
        ) do
      quote(
        do:
          def unquote(function_name)(conn, _params) do
            response_status_code =
              OpenAPIClientWeb.Plugs.Callback.get_response_status_code(conn)

            response_body = OpenAPIClientWeb.Plugs.Callback.get_response_body(conn)
            Plug.Conn.send_resp(conn, response_status_code, response_body)
          end
      )
    end

    @impl __MODULE__
    def render_callback_header(state, %Operation{module_name: module_name} = _operation) do
      web_base_module = get_web_base_module(state)

      behaviour_mock_module =
        state
        |> generate_module_name(module_name)
        |> Module.split()
        |> List.update_at(-1, &"#{&1}Mock")
        |> Module.concat()

      [
        quote(do: use(unquote(Module.concat([web_base_module, ConnCase]))))
        |> Util.put_newlines(),
        quote(do: import(Mox)) |> Util.put_newlines(),
        quote(do: @behaviour_module(unquote(behaviour_mock_module))) |> Util.put_newlines(),
        quote(do: setup(:verify_on_exit!))
      ]
    end

    @impl __MODULE__
    def render_callback(
          %State{implementation: implementation} = state,
          %Operation{
            request_path: request_path,
            request_method: request_method,
            module_name: module_name,
            function_name: function_name
          } = operation
        ) do
      operation_module = generate_module_name(state, module_name)

      state
      |> implementation.render_operation(operation)
      |> case do
        {:describe, _, [_describe_message, [do: {:__block__, _, tests}]]} ->
          tests_new =
            Enum.map(tests, fn {:test, _, [test_message, [do: test_body]]} ->
              test_body
              |> Macro.prewalk(%{}, fn
                {:assert, _,
                 [
                   {:==, _,
                    [
                      function_result,
                      {{:., _, [^operation_module, ^function_name]}, _, function_arg_values}
                    ]}
                 ]},
                acc ->
                  [{_, %GeneratorOperation{params: params}}] =
                    :ets.lookup(:operations, {request_path, request_method})

                  function_arg_names =
                    (Enum.flat_map(
                       params,
                       fn
                         %GeneratorParam{param: %Param{name: name}, static: true} ->
                           [String.to_atom(name)]

                         _param ->
                           []
                       end
                     ) ++ [:opts])
                    |> then(fn names ->
                      if Enum.count(function_arg_values) != Enum.count(names) do
                        List.insert_at(names, -2, :body)
                      else
                        names
                      end
                    end)

                  function_args =
                    function_arg_names
                    |> Enum.zip(function_arg_values)
                    |> Enum.map(fn
                      {:opts, opts} ->
                        variable = Macro.var(:opts, nil)

                        opts
                        |> Keyword.drop([:base_url, :client_pipeline])
                        |> Enum.map(fn {opt_key, opt_value} ->
                          quote(
                            do:
                              assert(
                                {:ok, unquote(opt_value)} ==
                                  Keyword.fetch(unquote(variable), unquote(opt_key))
                              )
                          )
                        end)
                        |> case do
                          [] -> {Macro.var(:_opts, nil), []}
                          asserts -> {variable, asserts}
                        end

                      {arg_name, arg_value} ->
                        variable = Macro.var(arg_name, nil)
                        {variable, [quote(do: assert(unquote(arg_value) == unquote(variable)))]}
                    end)

                  macro =
                    quote(
                      do:
                        expect(@behaviour_module, unquote(function_name), fn unquote_splicing(
                                                                               Enum.map(
                                                                                 function_args,
                                                                                 fn {key,
                                                                                     _asserts} ->
                                                                                   key
                                                                                 end
                                                                               )
                                                                             ) ->
                          unquote_splicing(
                            Enum.flat_map(function_args, fn {_key, asserts} -> asserts end)
                          )

                          unquote(function_result)
                        end)
                    )

                  acc_new = Map.put(acc, :callback_call_expect, macro)

                  {:ok, acc_new}

                {:expect, _,
                 [
                   {:@, _, [{:httpoison, _, _}]},
                   :request,
                   {:fn, _,
                    [
                      {:->, _,
                       [[request_method, _, _, _, _], {:__block__, _, expect_expressions}]}
                    ]}
                 ]},
                acc ->
                  acc_new =
                    expect_expressions
                    |> Enum.reduce(
                      acc,
                      fn
                        {:assert, _,
                         [
                           {:=, _,
                            [
                              {{:_, _, _}, query_param_value},
                              {{:., _, [{:__aliases__, _, [:List]}, :keyfind]}, _,
                               [
                                 {{:., _, [Access, :get]}, _, [{:options, _, _}, :params]},
                                 query_param_name,
                                 0
                               ]}
                            ]}
                         ]},
                        acc ->
                          Map.update(
                            acc,
                            :request_query_params,
                            %{query_param_name => query_param_value},
                            &Map.put(&1, query_param_name, query_param_value)
                          )

                        {:assert, _,
                         [
                           {:=, _,
                            [
                              {{:_, _, _}, header_param_value},
                              {{:., _, [{:__aliases__, _, [:List]}, :keyfind]}, _,
                               [
                                 {:headers, _, _},
                                 header_param_name,
                                 0
                               ]}
                            ]}
                         ]},
                        acc ->
                          Map.update(
                            acc,
                            :request_headers,
                            %{header_param_name => header_param_value},
                            &Map.put(&1, header_param_name, header_param_value)
                          )

                        {:assert, _,
                         [
                           {:==, _,
                            [
                              {:ok, request_content_type},
                              {:with, _,
                               [
                                 {:<-, _,
                                  [
                                    _,
                                    {{:., _,
                                      [
                                        {:__aliases__, _, [:List]},
                                        :keyfind
                                      ]}, _,
                                     [
                                       {:headers, _, _},
                                       "content-type",
                                       0
                                     ]}
                                  ]}
                                 | _
                               ]}
                            ]}
                         ]},
                        acc ->
                          Map.update(
                            acc,
                            :request_headers,
                            %{"content-type" => request_content_type},
                            &Map.put(&1, "content-type", request_content_type)
                          )

                        {:assert, _,
                         [
                           {:==, _,
                            [
                              {:ok, request_encoded_body},
                              {{:., _, _}, [], [{:body, _, _} | []]}
                            ]}
                         ]},
                        acc ->
                          Map.put(acc, :request_encoded_body, request_encoded_body)

                        {:assert, _,
                         [
                           {:=, _,
                            [
                              {:ok, {:body_encoded, _, _}},
                              response_encoded_body
                            ]}
                         ]},
                        acc ->
                          Map.put(acc, :response_encoded_body, response_encoded_body)

                        {:ok,
                         {:%, _,
                          [
                            {:__aliases__, _, [:HTTPoison, :Response]},
                            {:%{}, _, httpoison_response_args}
                          ]}},
                        acc ->
                          Enum.reduce(httpoison_response_args, acc, fn
                            {:status_code, response_status_code}, acc ->
                              Map.put(acc, :response_status_code, response_status_code)

                            {:headers, headers}, acc ->
                              Enum.reduce(headers, acc, fn
                                {key, value}, acc ->
                                  key_down = String.downcase(key)

                                  Map.update(
                                    acc,
                                    :response_headers,
                                    %{key_down => value},
                                    &Map.put(&1, key_down, value)
                                  )
                              end)

                            _, acc ->
                              acc
                          end)

                        _expression, acc ->
                          acc
                      end
                    )
                    |> Map.put(:request_method, request_method)

                  {:ok, acc_new}

                expression, acc ->
                  {expression, acc}
              end)
              |> case do
                {_expression, render_parameters} ->
                  query = URI.encode_query(render_parameters[:request_query_params] || [])

                  url =
                    module_name
                    |> Module.split()
                    |> List.insert_at(-1, Atom.to_string(function_name))
                    |> Enum.map_join("/", &Macro.underscore/1)
                    |> then(&"/__test__/#{&1}")
                    |> URI.parse()
                    |> struct!(query: query)
                    |> URI.to_string()

                  request_body = render_parameters[:request_encoded_body]
                  conn_call_args = [url] ++ if(request_body, do: [request_body], else: [])

                  request_headers = render_parameters[:request_headers] || %{}

                  conn_call =
                    if map_size(request_headers) > 0 do
                      request_headers
                      |> Enum.reverse()
                      |> Enum.reduce(Macro.var(:conn, nil), fn {name, value}, conn ->
                        quote(
                          do:
                            unquote(conn)
                            |> Plug.Conn.put_req_header(unquote(name), unquote(value))
                        )
                      end)
                      |> then(fn conn ->
                        quote(
                          do:
                            unquote(conn)
                            |> unquote(render_parameters[:request_method])(
                              unquote_splicing(conn_call_args)
                            )
                        )
                      end)
                    else
                      quote(
                        do:
                          unquote(render_parameters[:request_method])(
                            unquote_splicing([Macro.var(:conn, nil) | conn_call_args])
                          )
                      )
                    end

                  response_body = render_parameters[:response_encoded_body]

                  test_message_new =
                    test_message
                    |> String.replace(~r/performs(\s+a\s+request)/, "processes\\1")
                    |> String.replace(
                      ~r/encodes(\s+[\w\d\.]+\s+from\s+request\'s\s+body)/,
                      "decodes\\1"
                    )
                    |> String.replace(
                      ~r/decodes(\s+[\w\d\.]+\s+from\s+response\'s\s+body)/,
                      "encodes\\1"
                    )

                  quote do
                    test unquote(test_message_new), %{conn: conn} do
                      unquote(render_parameters[:callback_call_expect])

                      conn = unquote(conn_call)

                      unquote_splicing(
                        (render_parameters[:response_headers] || [])
                        |> Enum.map(fn {name, value} ->
                          quote(
                            do:
                              assert(
                                [unquote(value)] ==
                                  Plug.Conn.get_resp_header(conn, unquote(name))
                              )
                          )
                        end)
                        |> case do
                          [] -> []
                          asserts -> Util.put_newlines(asserts)
                        end
                      )

                      unquote_splicing(
                        if response_body do
                          [
                            quote(
                              do:
                                assert(
                                  encoded_body =
                                    response(
                                      conn,
                                      unquote(render_parameters[:response_status_code])
                                    )
                                )
                            ),
                            quote(do: assert({:ok, encoded_body} == unquote(response_body)))
                          ]
                        else
                          [
                            quote(
                              do:
                                assert(
                                  response(
                                    conn,
                                    unquote(render_parameters[:response_status_code])
                                  )
                                )
                            )
                          ]
                        end
                      )
                    end
                  end
              end
            end)

          quote(
            do:
              describe unquote("#{function_name}/2") do
                (unquote_splicing(tests_new))
              end
          )

        _ ->
          nil
      end
    end

    @impl __MODULE__
    def render_callback_scope(
          state,
          %Operation{
            request_path: request_path,
            request_method: request_method,
            function_name: function_name
          } = operation
        ) do
      [{_, %GeneratorOperation{config: operation_config}}] =
        :ets.lookup(:operations, {request_path, request_method})

      quote(
        do:
          scope unquote("/#{function_name}") do
            unquote_splicing(
              operation_config
              |> Keyword.get(:callback_controller_pipe_through, [])
              |> case do
                [] ->
                  []

                [pipeline] ->
                  [quote(do: pipe_through(unquote(pipeline))) |> Util.put_newlines()]

                pipelines ->
                  [quote(do: pipe_through(unquote(pipelines))) |> Util.put_newlines()]
              end
            )

            unquote(request_method)(
              "/",
              unquote(Module.concat([get_controller_module_name(state, operation)])),
              unquote(function_name)
            )
          end
      )
    end

    @impl __MODULE__
    def render_operation_test(
          %State{implementation: implementation} = state,
          %Operation{
            module_name: module_name,
            function_name: function_name,
            request_path: request_path,
            request_method: request_method
          } = _operation,
          {request_content_type, request_schema},
          {response_content_type, response_schema, status_code}
        ) do
      module_name = generate_module_name(state, module_name)

      typed_decoder =
        Utils.get_config(
          state,
          :typed_decoder,
          OpenAPIClient.Client.TypedDecoder
        )

      path = [{request_path, request_method}]

      {request_encoded, request_decoded} =
        generate_schema_example(state, request_schema, [
          {:request_body, request_content_type},
          {request_path, request_method}
        ])

      request_schema_test_message =
        if request_schema_test_message = test_message_schema(state, module_name, request_schema) do
          "encodes #{request_schema_test_message} from request's body"
        end

      {response_encoded, response_decoded} =
        generate_schema_example(state, response_schema, [
          {:response_body, status_code, response_content_type},
          {request_path, request_method}
        ])

      response_schema_test_message =
        if response_schema_test_message = test_message_schema(state, module_name, response_schema) do
          "decodes #{response_schema_test_message} from response's body"
        end

      [{_, %GeneratorOperation{params: all_params}}] =
        :ets.lookup(:operations, {request_path, request_method})

      expected_result_tag =
        if status_code >= 200 and status_code < 300 do
          :ok
        else
          :error
        end

      render_parameters =
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
            custom_params_assertions: [],
            custom_params_assertions_args: false,
            custom_params_assertions_opts: false,
            httpoison_request_assertions: [],
            httpoison_response_assignmets: [],
            httpoison_response_fields: [{:status_code, status_code}],
            expected_result: expected_result_tag
          },
          fn
            {:param,
             %GeneratorParam{
               param: %Param{name: name, location: location, value_type: type},
               old_name: old_name,
               static: static,
               schema_type: schema_type,
               custom: is_custom
             } = param},
            acc ->
              path_new = [{:parameter, location, old_name} | path]

              type_new = Utils.schema_type_to_readable_type(state, type, schema_type)

              param_example = implementation.example(state, param, path_new)

              {:ok, param_example_decoded} =
                typed_decoder.decode(
                  param_example,
                  type_new,
                  path_new,
                  typed_decoder
                )

              acc_new =
                if static do
                  Map.update!(acc, :call_arguments, &[param_example_decoded | &1])
                else
                  Map.update!(
                    acc,
                    :call_opts,
                    &[{String.to_atom(name), param_example_decoded} | &1]
                  )
                end

              if is_custom do
                acc_new
                |> Map.update!(
                  :custom_params_assertions,
                  &[
                    quote(
                      do:
                        assert(
                          {:ok, unquote(param_example_decoded)} ==
                            Keyword.fetch(
                              unquote(Macro.var(if(static, do: :args, else: :opts), nil)),
                              unquote(String.to_atom(name))
                            )
                        )
                    )
                    | &1
                  ]
                )
                |> Map.replace!(
                  if(static,
                    do: :custom_params_assertions_args,
                    else: :custom_params_assertions_opts
                  ),
                  true
                )
              else
                case location do
                  :path ->
                    acc_new
                    |> Map.update!(
                      :httpoison_request_arguments,
                      &List.update_at(&1, 1, fn url ->
                        String.replace(url, "{#{old_name}}", to_string(param_example))
                      end)
                    )

                  :query ->
                    acc_new
                    |> Map.update!(
                      :httpoison_request_arguments,
                      &List.replace_at(&1, 4, quote(do: options))
                    )
                    |> Map.update!(
                      :httpoison_request_assertions,
                      &[
                        quote(
                          do:
                            assert(
                              {_, unquote(to_string(param_example))} =
                                List.keyfind(options[:params], unquote(old_name), 0)
                            )
                        )
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
                              {_, unquote(to_string(param_example))} =
                                List.keyfind(headers, unquote(String.downcase(old_name)), 0)
                            )
                        )
                        | &1
                      ]
                    )

                  _ ->
                    acc_new
                end
              end

            {:request_body, {nil, _, _}}, acc ->
              acc

            {:request_body, {content_type, body_encoded, body_decoded}}, acc ->
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
                        {:ok, unquote(content_type)} ==
                          with {_, content_type_request} <-
                                 List.keyfind(headers, "content-type", 0),
                               {:ok, {media_type, media_subtype, _parameters}} =
                                 OpenAPIClient.Client.Operation.parse_content_type_header(
                                   content_type_request
                                 ) do
                            {:ok, "#{media_type}/#{media_subtype}"}
                          end
                      )
                  )
                  | &1
                ]
              )
              |> Map.update!(
                :httpoison_request_arguments,
                &List.replace_at(&1, 2, quote(do: body))
              )
              |> Map.update!(
                :httpoison_request_assertions,
                &[
                  quote do
                    assert {:ok, unquote(body_encoded)} ==
                             unquote(
                               apply_body_converter(
                                 state,
                                 Macro.var(:body, nil),
                                 content_type,
                                 :decoders
                               )
                             )
                  end
                  | &1
                ]
              )
              |> Map.update!(:call_arguments, &[body_decoded | &1])

            {:response_body, {nil, _, _}}, acc ->
              acc

            {:response_body, {content_type, body_encoded, body_decoded}}, acc ->
              acc
              |> Map.update!(
                :httpoison_response_fields,
                &[{:headers, quote(do: [{"Content-Type", unquote(content_type)}])} | &1]
              )
              |> Map.update!(
                :httpoison_response_assignmets,
                &[
                  quote do
                    assert {:ok, body_encoded} =
                             unquote(
                               apply_body_converter(
                                 state,
                                 body_encoded,
                                 content_type,
                                 :encoders
                               )
                             )
                  end
                  | &1
                ]
              )
              |> Map.update!(
                :httpoison_response_fields,
                &[{:body, Macro.var(:body_encoded, nil)} | &1]
              )
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

      custom_params_assertions_callback =
        render_parameters[:custom_params_assertions]
        |> Enum.reverse()
        |> case do
          [] ->
            quote(do: &OpenAPIClient.Client.perform/2)

          params ->
            {:fn, [],
             [
               {:->, [],
                [
                  [
                    Macro.var(:operation, nil),
                    Macro.var(:pipeline, nil)
                  ],
                  quote do
                    unquote_splicing(
                      Util.clean_list([
                        if(render_parameters[:custom_params_assertions_args],
                          do:
                            quote(
                              do:
                                args =
                                  OpenAPIClient.Client.Operation.get_private(operation, :__args__)
                            )
                        ),
                        if(render_parameters[:custom_params_assertions_opts],
                          do:
                            quote(
                              do:
                                opts =
                                  OpenAPIClient.Client.Operation.get_private(operation, :__opts__)
                            )
                        )
                      ])
                    )

                    unquote_splicing(params)
                    OpenAPIClient.Client.perform(operation, pipeline)
                  end
                ]}
             ]}
        end

      quote do
        test unquote(test_message) do
          expect(
            @client,
            :perform,
            unquote(custom_params_assertions_callback)
          )

          expect(
            @httpoison,
            :request,
            unquote(
              {:fn, [],
               [
                 {:->, [],
                  [
                    render_parameters[:httpoison_request_arguments],
                    quote do
                      unquote_splicing(
                        Enum.reverse(render_parameters[:httpoison_request_assertions])
                      )

                      unquote_splicing(
                        Enum.reverse(render_parameters[:httpoison_response_assignmets])
                      )

                      {:ok,
                       %HTTPoison.Response{
                         unquote_splicing(
                           Enum.reverse(render_parameters[:httpoison_response_fields])
                         )
                       }}
                    end
                  ]}
               ]}
            )
          )

          assert unquote(render_parameters[:expected_result]) ==
                   unquote(module_name).unquote(function_name)(
                     unquote_splicing(
                       Enum.reverse([
                         render_parameters[:call_opts] | render_parameters[:call_arguments]
                       ])
                     )
                   )
        end
      end
    end

    @impl __MODULE__
    def example(_state, :null, _path), do: nil
    def example(_state, :boolean, _path), do: true

    def example(%State{implementation: implementation} = state, {:boolean, _}, path),
      do: implementation.example(state, :boolean, path)

    def example(_state, :integer, _path), do: 1

    def example(%State{implementation: implementation} = state, {:integer, _}, path),
      do: implementation.example(state, :integer, path)

    def example(_state, :number, _path), do: 1.0

    def example(%State{implementation: implementation} = state, {:number, _}, path),
      do: implementation.example(state, :number, path)

    def example(_state, {:string, :date}, _path), do: "2024-01-02"
    def example(_state, {:string, :date_time}, _path), do: "2024-01-02T01:23:45Z"
    def example(_state, {:string, :time}, _path), do: "01:23:45"
    def example(_state, {:string, :uri}, _path), do: "http://example.com"
    def example(_state, {:string, _}, _path), do: "string"

    def example(%State{implementation: implementation} = state, {:array, type}, path),
      do: implementation.example(state, [type], path)

    def example(%State{implementation: implementation} = state, [type], path),
      do: [implementation.example(state, type, [[0] | path])]

    def example(_state, {:const, value}, _path), do: value
    def example(_state, {:enum, [{_atom, value} | _]}, _path), do: value
    def example(_state, {:enum, [value | _]}, _path), do: value
    def example(_state, type, _path) when type in [:any, :map], do: %{"a" => "b"}

    def example(%State{implementation: implementation} = state, {:union, [type | _]}, path),
      do: implementation.example(state, type, path)

    def example(%State{implementation: implementation} = state, {module, type}, path)
        when is_atom(module) and is_atom(type) do
      true =
        OpenAPIClient.Utils.is_module?(module) and
          OpenAPIClient.Utils.does_implement_behaviour?(module, OpenAPIClient.Schema)

      type
      |> module.__fields__()
      |> Map.new(fn field ->
        field
        |> case do
          {key, {old_name, type}} -> {key, {old_name, type}}
          {key, {old_name, type, _default}} -> {key, {old_name, type}}
        end
        |> case do
          {key, {old_name, type}} ->
            example_key = implementation.example(state, type, [key | path])
            {old_name, example_key}
        end
      end)
    end

    def example(
          state,
          %GeneratorField{field: %Field{type: type}, schema_type: schema_type},
          path
        ),
        do: schema_type_example(state, type, schema_type, path)

    def example(
          %State{implementation: implementation} = state,
          %GeneratorSchema{fields: all_fields},
          path
        ) do
      all_fields
      |> Enum.flat_map(fn
        %GeneratorField{field: nil} ->
          []

        %GeneratorField{old_name: name} = field ->
          example_field = implementation.example(state, field, [name | path])
          [{name, example_field}]
      end)
      |> Map.new()
    end

    def example(%State{implementation: implementation} = state, schema_ref, path)
        when is_reference(schema_ref) do
      [{_, schema}] = :ets.lookup(:schemas, schema_ref)
      implementation.example(state, schema, path)
    end

    def example(
          state,
          %GeneratorParam{param: %Param{value_type: type}, schema_type: schema_type},
          path
        ),
        do: schema_type_example(state, type, schema_type, path)

    def example(%State{implementation: implementation} = state, {:array, type}, path),
      do: [implementation.example(state, type, [[0] | path])]

    defp schema_type_example(_state, _type, %SchemaType{examples: [value | _]}, _path),
      do: value

    defp schema_type_example(
           state,
           type,
           %SchemaType{default: value} = schema_type,
           path
         )
         when not is_nil(value) and not is_tuple(value) do
      typed_encoder = Utils.get_config(state, :typed_encoder, OpenAPIClient.Client.TypedEncoder)
      type_new = Utils.schema_type_to_readable_type(state, type, schema_type)
      {:ok, value_encoded} = typed_encoder.encode(value, type_new, path, typed_encoder)
      value_encoded
    end

    defp schema_type_example(
           %State{implementation: implementation} = state,
           {:array, {:enum, _}},
           %SchemaType{enum: %SchemaType.Enum{options: enum_options}},
           path
         ),
         do: implementation.example(state, {:array, {:enum, enum_options}}, path)

    defp schema_type_example(
           %State{implementation: implementation} = state,
           {:enum, _},
           %SchemaType{enum: %SchemaType.Enum{options: enum_options}},
           path
         ),
         do: implementation.example(state, {:enum, enum_options}, path)

    defp schema_type_example(
           %State{implementation: implementation} = state,
           type,
           _schema_type,
           path
         ),
         do: implementation.example(state, type, path)

    @impl __MODULE__
    def decode_example(
          state,
          value,
          %GeneratorSchema{
            schema: %Schema{output_format: output_format, module_name: module, type_name: type}
          } = generator_schema,
          path
        ) do
      ExampleSchemaFieldsAgent.update(ensure_schema_fields_agent(), generator_schema)

      typed_decoder = Utils.get_config(state, :typed_decoder, OpenAPIClient.Client.TypedDecoder)

      case typed_decoder.decode(value, {@example_schema, type}, path, @example_typed_decoder) do
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
    end

    def decode_example(
          %State{
            implementation: implementation,
            renderer_state: %OpenAPI.Renderer.State{schemas: schemas}
          } = state,
          value,
          {module, type},
          path
        )
        when is_atom(module) and is_atom(type) and is_map(value) do
      with :alias <- Macro.classify_atom(module),
           %Schema{ref: schema_ref} <-
             Enum.find_value(schemas, fn
               {_ref, %Schema{module_name: module_name, type_name: ^type} = schema} ->
                 if generate_module_name(state, module_name) == module do
                   schema
                 end

               _ ->
                 nil
             end) do
        implementation.decode_example(state, value, schema_ref, path)
      else
        _ ->
          typed_decoder =
            Utils.get_config(state, :typed_decoder, OpenAPIClient.Client.TypedDecoder)

          typed_decoder.decode(value, {module, type}, path, @example_typed_decoder)
      end
    end

    def decode_example(
          %State{implementation: implementation} = state,
          value,
          {:union, [type | _]},
          path
        ),
        do: implementation.decode_example(state, value, type, path)

    def decode_example(
          %State{implementation: implementation} = state,
          value,
          schema_ref,
          path
        )
        when is_reference(schema_ref) do
      [{_, %GeneratorSchema{schema: %Schema{module_name: module} = schema} = generator_schema}] =
        :ets.lookup(:schemas, schema_ref)

      module_new = generate_module_name(state, module)
      schema_new = %Schema{schema | module_name: module_new}
      generator_schema_new = %GeneratorSchema{generator_schema | schema: schema_new}
      implementation.decode_example(state, value, generator_schema_new, path)
    end

    def decode_example(
          %State{implementation: implementation} = state,
          value,
          [type],
          path
        ) do
      value
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {item_value, index}, {:ok, acc} ->
        case implementation.decode_example(state, item_value, type, [[index] | path]) do
          {:ok, decoded_value} -> {:cont, {:ok, [decoded_value | acc]}}
          {:error, _} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, decoded_value} -> {:ok, Enum.reverse(decoded_value)}
        {:error, _} = error -> error
      end
    end

    def decode_example(
          %State{implementation: implementation} = state,
          value,
          {:array, type},
          path
        ) do
      implementation.decode_example(state, value, [type], path)
    end

    def decode_example(state, value, type, path) do
      typed_decoder = Utils.get_config(state, :typed_decoder, OpenAPIClient.Client.TypedDecoder)
      typed_decoder.decode(value, type, path, @example_typed_decoder)
    end

    @spec clear_router_test_routes(State.t()) :: :ok | {:error, term()}
    def clear_router_test_routes(state), do: update_router_test_scope(state, fn _ -> [] end)

    defp update_router_test_scope(%State{implementation: implementation} = state, update_fun) do
      router_location =
        state
        |> Utils.get_web_location()
        |> Path.split()
        |> List.insert_at(-1, "controllers")
        |> Path.join()

      with {:ok, binary} <- File.read(router_location),
           {:ok,
            {:defmodule, defmodule_metadata,
             [
               defmodule_name,
               [do: {:__block__, block_metadata, defmodule_expressions}]
             ]}} <- Code.string_to_quoted(binary) do
        defmodule_expressions_new =
          Enum.map(
            defmodule_expressions,
            fn
              {:scope, test_scope_metadata,
               [
                 "/__test__",
                 test_scope_alias,
                 [
                   do: scopes
                 ]
               ]} ->
                scopes_new =
                  scopes
                  |> case do
                    {:__block__, _scopes_block_metadata, scopes_block_expressions} ->
                      scopes_block_expressions

                    {:scope, _, _} = single_scope ->
                      [single_scope]
                  end
                  |> update_fun.()

                {:scope, test_scope_metadata,
                 [
                   "/__test__",
                   test_scope_alias,
                   [
                     do: {:__block__, [], scopes_new}
                   ]
                 ]}

              expression ->
                expression
            end
          )

        ast =
          {:defmodule, defmodule_metadata,
           [
             defmodule_name,
             [do: {:__block__, block_metadata, defmodule_expressions_new}]
           ]}

        %RendererFile{
          ast: ast,
          contents: nil,
          location: router_location,
          module: Macro.expand(defmodule_name, __ENV__),
          operations: [],
          schemas: []
        }
        |> then(&%RendererFile{&1 | contents: implementation.format(state, &1)})
        |> then(&implementation.write(state, &1))
      end
    end

    defp select_example_schema(_state, [], _converter_key), do: {nil, :null}

    defp select_example_schema(state, schemas, converter_key) do
      converters = Utils.get_config(state, converter_key, [])

      Enum.reduce_while(schemas, {nil, :null}, fn {content_type, schema},
                                                  {current_content_type, _} = acc ->
        case List.keyfind(converters, content_type, 0) do
          {_content_type, _mfa} -> {:halt, {content_type, schema}}
          nil when is_nil(current_content_type) -> {:cont, {content_type, schema}}
          _ -> {:cont, acc}
        end
      end)
    end

    defp generate_schema_example(_state, :null, _path),
      do: {nil, nil}

    defp generate_schema_example(
           %State{
             implementation: implementation,
             renderer_state: %OpenAPI.Renderer.State{schemas: schemas}
           } = state,
           schema_ref,
           path
         )
         when is_reference(schema_ref) do
      [{_, generator_schema}] = :ets.lookup(:schemas, schema_ref)

      %Schema{module_name: module, type_name: type} = schema = Map.fetch!(schemas, schema_ref)
      module = generate_module_name(state, module)
      schema_new = %Schema{schema | module_name: module}
      generator_schema_new = %GeneratorSchema{generator_schema | schema: schema_new}

      example_encoded = implementation.example(state, generator_schema_new, path)

      {:ok, example_decoded} =
        apply(@example_typed_decoder, :decode, [
          example_encoded,
          {module, type},
          path,
          @example_typed_decoder
        ])

      example_encoded = sort_encoded_example(example_encoded)
      {example_encoded, example_decoded}
    end

    defp generate_schema_example(%State{implementation: implementation} = state, type, path) do
      example_encoded = implementation.example(state, type, path)

      {:ok, example_decoded} =
        apply(@example_typed_decoder, :decode, [
          example_encoded,
          type,
          path,
          @example_typed_decoder
        ])

      example_encoded = sort_encoded_example(example_encoded)
      {example_encoded, example_decoded}
    end

    defp sort_encoded_example(map) when is_map(map) do
      items =
        map
        |> Enum.sort_by(fn {name, _value} -> name end)
        |> Enum.map(fn {name, value} -> {name, sort_encoded_example(value)} end)

      quote do
        %{unquote_splicing(items)}
      end
    end

    defp sort_encoded_example(value), do: value

    defp generate_module_name(state, module_name) do
      Module.concat(Utils.get_oapi_generator_config(state, :base_module, ""), module_name)
    end

    defp test_message_schema(
           %State{renderer_state: renderer_state} = _state,
           parent_module_name,
           schema
         ) do
      case Util.to_readable_type(renderer_state, schema) do
        [{module, _type}] ->
          if Macro.classify_atom(module) == :alias do
            module
            |> test_message_schema_module_name(parent_module_name)
            |> then(&"array of #{&1}")
          end

        [:map] ->
          "array of maps"

        {module, _type} ->
          if Macro.classify_atom(module) == :alias do
            test_message_schema_module_name(module, parent_module_name)
          end

        :map ->
          "map"

        _ ->
          nil
      end
    end

    defp test_message_schema_module_name(module_name, parent_module_name) do
      parent_module_name_parts = Module.split(parent_module_name)

      module_name
      |> Module.split()
      |> test_message_schema_module_name_acc(parent_module_name_parts, [])
      |> Enum.join(".")
    end

    defp test_message_schema_module_name_acc([], _, acc), do: Enum.reverse(acc)

    defp test_message_schema_module_name_acc(
           [part | module_name_rest],
           [part | parent_module_name_rest],
           []
         ),
         do: test_message_schema_module_name_acc(module_name_rest, parent_module_name_rest, [])

    defp test_message_schema_module_name_acc([part | module_name_rest], parent_module_name, acc),
      do: test_message_schema_module_name_acc(module_name_rest, parent_module_name, [part | acc])

    defp apply_body_converter(state, body, content_type, converter_key) do
      {_, {module, function, args}} =
        state |> Utils.get_config(converter_key) |> List.keyfind!(content_type, 0)

      quote do
        unquote(module).unquote(function)(unquote_splicing(List.insert_at(args, 0, body)))
      end
    end

    defp ensure_schema_fields_agent() do
      app_data = Process.get(:open_api_client_ex, [])

      app_data
      |> Map.get(:schema_fields_agent)
      |> case do
        pid when is_pid(pid) ->
          pid

        nil ->
          {:ok, pid} = ExampleSchemaFieldsAgent.start_link()

          Mox.defmock(@example_schema, for: OpenAPIClient.Schema)
          Mox.defmock(@example_typed_decoder, for: OpenAPIClient.Client.TypedDecoder)

          stub(@example_schema, :__fields__, fn _type ->
            %GeneratorSchema{schema_fields: schema_fields} = ExampleSchemaFieldsAgent.get(pid)
            schema_fields
          end)

          Process.put(:open_api_client_ex, Map.put(app_data, :schema_fields_agent, pid))

          pid
      end
    end

    defp get_controller_module_name(_state, %Operation{function_name: function_name} = _operation) do
      function_name
      |> Atom.to_string()
      |> OpenAPI.Processor.Naming.normalize_identifier(:camel)
      |> then(&"#{&1}Controller")
    end

    defp get_web_base_module(state) do
      state
      |> Utils.get_config(:web_base_module)
      |> case do
        nil ->
          state
          |> Utils.get_oapi_generator_config(:base_module, "")
          |> case do
            "Elixir." <> _rest = module -> Module.split(module)
            module when is_binary(module) and module != "" -> Module.split("Elixir." <> module)
            module when is_atom(module) -> Module.split(module)
          end
          |> List.update_at(0, &"#{&1}Web")
          |> Module.concat()

        "Elixir." <> _rest = module ->
          String.to_atom(module)

        module when is_binary(module) and module != "" ->
          String.to_atom("Elixir." <> module)

        module when is_atom(module) ->
          module
      end
    end
  end
end

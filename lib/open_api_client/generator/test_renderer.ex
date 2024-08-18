if Mix.env() in [:dev, :test] do
  defmodule OpenAPIClient.Generator.TestRenderer do
    defmacro __using__(_opts) do
      quote do
        @behaviour OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate render(state, file), to: OpenAPIClient.Generator.TestRenderer

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
        defdelegate example(state, type, path), to: OpenAPIClient.Generator.TestRenderer

        @impl OpenAPIClient.Generator.TestRenderer
        defdelegate decode_example(state, value, type, path),
          to: OpenAPIClient.Generator.TestRenderer

        defoverridable render: 2,
                       module: 2,
                       format: 2,
                       location: 2,
                       write: 2,
                       render_operation: 2,
                       render_operation_test: 4,
                       example: 3,
                       decode_example: 4
      end
    end

    alias OpenAPI.Processor.{Operation, Schema}
    alias Operation.Param
    alias Schema.Field
    alias OpenAPIClient.Generator.TestRenderer.State
    alias OpenAPI.Renderer.File
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

    @callback render(state :: State.t(), file :: File.t()) :: :ok
    @callback module(state :: State.t(), file :: File.t()) :: module()
    @callback format(state :: State.t(), file :: File.t()) :: iodata()
    @callback location(state :: State.t(), file :: File.t()) :: String.t()
    @callback write(state :: State.t(), file :: File.t()) :: :ok
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
                        module: 2,
                        format: 2,
                        location: 2,
                        write: 2,
                        render_operation: 2,
                        render_operation_test: 4,
                        example: 3,
                        decode_example: 4

    @test_example_url "https://example.com"

    @example_schema ExampleSchema
    @example_typed_decoder ExampleTypedDecoder

    @behaviour __MODULE__

    @impl __MODULE__
    def render(
          %State{implementation: implementation} = state,
          %File{operations: operations} = file
        ) do
      ensure_schema_fields_agent()

      stub(@example_typed_decoder, :decode, fn value, type, path, _caller_module ->
        implementation.decode_example(state, value, type, path)
      end)

      operations
      |> Enum.map(&implementation.render_operation(state, &1))
      |> Util.clean_list()
      |> case do
        [] ->
          :ok

        tests ->
          module = implementation.module(state, file)

          ast =
            quote do
              defmodule unquote(generate_module_name(state, module)) do
                use ExUnit.Case, async: true
                unquote(quote(do: import(Mox)) |> Util.put_newlines())

                @httpoison OpenAPIClient.HTTPoisonMock
                unquote(quote(do: @client(OpenAPIClient.ClientMock)) |> Util.put_newlines())

                setup :verify_on_exit!

                unquote_splicing(tests)
              end
            end

          file =
            %File{file | ast: ast, module: module, contents: nil, location: nil}
            |> then(&%File{&1 | contents: implementation.format(state, &1)})
            |> then(&%File{&1 | location: implementation.location(state, &1)})

          if file.contents != "" do
            implementation.write(state, file)
          else
            :ok
          end
      end
    end

    @impl __MODULE__
    def module(_state, %File{module: module} = _file) do
      module
      |> Module.split()
      |> List.update_at(-1, &"#{&1}Test")
      |> Module.concat()
    end

    @impl __MODULE__
    def format(_state, %File{ast: ast} = _file) do
      # All this effort just not to have parenthesis in `describe/*` calls
      ast
      |> OpenAPI.Renderer.Util.format_multiline_docs()
      |> Code.quoted_to_algebra(escape: false, locals_without_parens: [describe: :*])
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

      test_base_location = Utils.get_config(state, :test_location, "test")

      renderer_state
      |> renderer_implementaion.location(file)
      |> Path.split()
      |> List.update_at(-1, fn filename -> Path.basename(filename, ".ex") <> ".exs" end)
      |> Path.join()
      |> then(&Path.join([test_base_location, Path.relative_to(&1, base_location)]))
    end

    @impl __MODULE__
    def write(
          %State{
            renderer_state:
              %OpenAPI.Renderer.State{implementation: renderer_implementaion} = renderer_state
          } = _state,
          file
        ) do
      renderer_implementaion.write(renderer_state, file)
    end

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
          [{_, %GeneratorOperation{params: params}}] =
            :ets.lookup(:operations, {request_path, request_method})

          arity =
            Enum.reduce(
              params,
              if(length(request_body) == 0, do: 1, else: 2),
              fn %GeneratorParam{static: static}, arity ->
                arity + if(static, do: 1, else: 0)
              end
            )

          describe_message = "#{function_name}/#{arity}"

          quote do
            describe unquote(describe_message) do
              (unquote_splicing(tests))
            end
          end
      end
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

      operation_profile = Utils.get_config(state, :aliased_profile, state.renderer_state.profile)

      typed_decoder =
        OpenAPIClient.Utils.get_config(
          operation_profile,
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
        if request_schema_test_message = test_message_schema(state, request_schema) do
          "encodes #{request_schema_test_message} from request's body"
        end

      {response_encoded, response_decoded} =
        generate_schema_example(state, response_schema, [
          {:response_body, status_code, response_content_type},
          {request_path, request_method}
        ])

      response_schema_test_message =
        if response_schema_test_message = test_message_schema(state, response_schema) do
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
            new_params_assertions: [],
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
               new: is_new
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

              if is_new do
                Map.update!(
                  acc_new,
                  :new_params_assertions,
                  &[
                    quote(
                      do:
                        assert(
                          {_, unquote(param_example_decoded)} =
                            List.keyfind(params, unquote(String.to_atom(name)), 0)
                        )
                    )
                    | &1
                  ]
                )
              else
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
                    |> Map.update!(
                      :httpoison_request_assertions,
                      &[
                        quote(
                          do:
                            assert(
                              {_, unquote(param_example)} =
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
                              {_, unquote(param_example)} =
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

      new_params_assertions_callback =
        test_parameters[:new_params_assertions]
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
                    params = OpenAPIClient.Client.Operation.get_private(operation, :__params__)
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
            unquote(new_params_assertions_callback)
          )

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
                        Enum.reverse(test_parameters[:httpoison_request_assertions])
                      )

                      unquote_splicing(
                        Enum.reverse(test_parameters[:httpoison_response_assignmets])
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
      |> Map.new(fn {key, {old_name, type}} ->
        example_key = implementation.example(state, type, [key | path])
        {old_name, example_key}
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
             end),
           [{_, %GeneratorSchema{schema: schema} = generator_schema}] =
             :ets.lookup(:schemas, schema_ref) do
        schema_new = %Schema{schema | module_name: module}
        generator_schema_new = %GeneratorSchema{generator_schema | schema: schema_new}
        implementation.decode_example(state, value, generator_schema_new, path)
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

    def decode_example(state, value, type, path) do
      typed_decoder = Utils.get_config(state, :typed_decoder, OpenAPIClient.Client.TypedDecoder)
      typed_decoder.decode(value, type, path, @example_typed_decoder)
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

    defp test_message_schema(%State{renderer_state: renderer_state} = _state, schema) do
      case Util.to_readable_type(renderer_state, schema) do
        [{module, _type}] ->
          if Macro.classify_atom(module) == :alias do
            module
            |> Module.split()
            |> Enum.join(".")
            |> then(&"array of #{&1}")
          end

        [:map] ->
          "array of maps"

        {module, _type} ->
          if Macro.classify_atom(module) == :alias do
            module
            |> Module.split()
            |> Enum.join(".")
          end

        :map ->
          "map"

        _ ->
          nil
      end
    end

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
  end
end

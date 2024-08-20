defmodule OpenAPIClient.OperationsTest do
  use ExUnit.Case, async: true
  import Mox

  @httpoison OpenAPIClient.HTTPoisonMock
  @client OpenAPIClient.ClientMock

  setup :verify_on_exit!

  describe "get_test/3" do
    test "[200] performs a request and encodes TestSchema from response's body" do
      expect(@client, :perform, fn operation, pipeline ->
        params = OpenAPIClient.Client.Operation.get_private(operation, :__params__)
        assert {_, "string"} = List.keyfind(params, :optional_header_new_param, 0)
        assert {_, "string"} = List.keyfind(params, :optional_new_param, 0)
        assert {_, "new_param_value"} = List.keyfind(params, :optional_new_param_with_default, 0)
        assert {_, "string"} = List.keyfind(params, :required_new_param, 0)
        OpenAPIClient.Client.perform(operation, pipeline)
      end)

      expect(@httpoison, :request, fn :get, "https://example.com/test", _, headers, options ->
        assert {_, "2022-12-15"} = List.keyfind(options[:params], "date_query_with_default", 0)
        assert {_, "2024-01-02T01:23:45Z"} = List.keyfind(options[:params], "datetime_query", 0)
        assert {_, "optional-query"} = List.keyfind(options[:params], "optional_query", 0)
        assert {_, "ENUM_1"} = List.keyfind(options[:params], "X-Enum-Query", 0)
        assert {_, "ENUM_9"} = List.keyfind(options[:params], "X-Enum-Query-With-Default", 0)
        assert {_, 1} = List.keyfind(options[:params], "X-Integer-Non-Standard-Format-Query", 0)
        assert {_, 1} = List.keyfind(options[:params], "X-Integer-Standard-Format-Query", 0)
        assert {_, true} = List.keyfind(options[:params], "X-Static-Flag", 0)
        assert {_, "2024-01-23"} = List.keyfind(headers, "x-date-header-with-default", 0)
        assert {_, "optional_header"} = List.keyfind(headers, "x-optional-header", 0)
        assert {_, "required_header"} = List.keyfind(headers, "x-required-header", 0)

        assert {:ok, body_encoded} =
                 Jason.encode(%{
                   "Boolean" => true,
                   "DateTime" => "2024-01-23T01:23:45Z",
                   "Enum" => "ENUM_2",
                   "Integer" => 5,
                   "Number" => 7.0,
                   "String" => "another_string"
                 })

        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           headers: [{"Content-Type", "application/json"}],
           body: body_encoded
         }}
      end)

      assert {:ok,
              %OpenAPIClient.TestSchema{
                boolean: true,
                date_time: ~U[2024-01-23 01:23:45Z],
                enum: :enum2,
                integer: 5,
                number: 7.0,
                string: "another_string"
              }} ==
               OpenAPIClient.Operations.get_test("required_header", "string",
                 optional_new_param_with_default: "new_param_value",
                 optional_new_param: "string",
                 optional_header_new_param: "string",
                 optional_header: "optional_header",
                 date_header_with_default: ~D[2024-01-23],
                 x_static_flag: true,
                 x_integer_standard_format_query: 1,
                 x_integer_non_standard_format_query: 1,
                 x_enum_query_with_default: :enum_9,
                 x_enum_query: :enum_1,
                 optional_query: "optional-query",
                 datetime_query: ~U[2024-01-02 01:23:45Z],
                 date_query_with_default: ~D[2022-12-15],
                 base_url: "https://example.com"
               )
    end
  end

  describe "set_test/2" do
    test "[298] performs a request and encodes TestRequestSchema from request's body" do
      expect(@client, :perform, &OpenAPIClient.Client.perform/2)

      expect(@httpoison, :request, fn :post, "https://example.com/test", body, headers, _ ->
        assert {_, "string_header"} = List.keyfind(headers, "x-string-header", 0)

        assert {_, "CONFIG_STRICT_ENUM_1"} =
                 List.keyfind(headers, "x-config-strict-enum-header", 0)

        assert {:ok, "application/json"} ==
                 (with {_, content_type_request} <- List.keyfind(headers, "content-type", 0),
                       {:ok, {media_type, media_subtype, _parameters}} =
                         OpenAPIClient.Client.Operation.parse_content_type_header(
                           content_type_request
                         ) do
                    {:ok, "#{media_type}/#{media_subtype}"}
                  end)

        assert {:ok,
                %{
                  "ArrayEnum" => ["DYNAMIC_ENUM_1"],
                  "Child" => %{"String" => "nested_string_value"},
                  "EnumWithDefault" => "DEFAULT_ENUM",
                  "NumberEnum" => 2.0,
                  "StrictEnum" => "STRICT_ENUM_3"
                }} == Jason.decode(body)

        {:ok, %HTTPoison.Response{status_code: 298}}
      end)

      assert :ok ==
               OpenAPIClient.Operations.set_test(
                 %OpenAPIClient.TestRequestSchema{
                   array_enum: [:dynamic_enum_1],
                   child: %OpenAPIClient.TestRequestSchema.Child{string: "nested_string_value"},
                   enum_with_default: :default_enum,
                   number_enum: 2.0,
                   strict_enum: :strict_enum_3
                 },
                 x_config_strict_enum_header: :config_strict_enum_1,
                 string_header: "string_header",
                 base_url: "https://example.com"
               )
    end

    test "[299] performs a request and encodes TestRequestSchema from request's body" do
      expect(@client, :perform, &OpenAPIClient.Client.perform/2)

      expect(@httpoison, :request, fn :post, "https://example.com/test", body, headers, _ ->
        assert {_, "string_header"} = List.keyfind(headers, "x-string-header", 0)

        assert {_, "CONFIG_STRICT_ENUM_1"} =
                 List.keyfind(headers, "x-config-strict-enum-header", 0)

        assert {:ok, "application/json"} ==
                 (with {_, content_type_request} <- List.keyfind(headers, "content-type", 0),
                       {:ok, {media_type, media_subtype, _parameters}} =
                         OpenAPIClient.Client.Operation.parse_content_type_header(
                           content_type_request
                         ) do
                    {:ok, "#{media_type}/#{media_subtype}"}
                  end)

        assert {:ok,
                %{
                  "ArrayEnum" => ["DYNAMIC_ENUM_1"],
                  "Child" => %{"String" => "nested_string_value"},
                  "EnumWithDefault" => "DEFAULT_ENUM",
                  "NumberEnum" => 2.0,
                  "StrictEnum" => "STRICT_ENUM_3"
                }} == Jason.decode(body)

        {:ok, %HTTPoison.Response{status_code: 299}}
      end)

      assert :ok ==
               OpenAPIClient.Operations.set_test(
                 %OpenAPIClient.TestRequestSchema{
                   array_enum: [:dynamic_enum_1],
                   child: %OpenAPIClient.TestRequestSchema.Child{string: "nested_string_value"},
                   enum_with_default: :default_enum,
                   number_enum: 2.0,
                   strict_enum: :strict_enum_3
                 },
                 x_config_strict_enum_header: :config_strict_enum_1,
                 string_header: "string_header",
                 base_url: "https://example.com"
               )
    end

    test "[400] performs a request and encodes TestRequestSchema from request's body" do
      expect(@client, :perform, &OpenAPIClient.Client.perform/2)

      expect(@httpoison, :request, fn :post, "https://example.com/test", body, headers, _ ->
        assert {_, "string_header"} = List.keyfind(headers, "x-string-header", 0)

        assert {_, "CONFIG_STRICT_ENUM_1"} =
                 List.keyfind(headers, "x-config-strict-enum-header", 0)

        assert {:ok, "application/json"} ==
                 (with {_, content_type_request} <- List.keyfind(headers, "content-type", 0),
                       {:ok, {media_type, media_subtype, _parameters}} =
                         OpenAPIClient.Client.Operation.parse_content_type_header(
                           content_type_request
                         ) do
                    {:ok, "#{media_type}/#{media_subtype}"}
                  end)

        assert {:ok,
                %{
                  "ArrayEnum" => ["DYNAMIC_ENUM_1"],
                  "Child" => %{"String" => "nested_string_value"},
                  "EnumWithDefault" => "DEFAULT_ENUM",
                  "NumberEnum" => 2.0,
                  "StrictEnum" => "STRICT_ENUM_3"
                }} == Jason.decode(body)

        {:ok, %HTTPoison.Response{status_code: 400}}
      end)

      assert :error ==
               OpenAPIClient.Operations.set_test(
                 %OpenAPIClient.TestRequestSchema{
                   array_enum: [:dynamic_enum_1],
                   child: %OpenAPIClient.TestRequestSchema.Child{string: "nested_string_value"},
                   enum_with_default: :default_enum,
                   number_enum: 2.0,
                   strict_enum: :strict_enum_3
                 },
                 x_config_strict_enum_header: :config_strict_enum_1,
                 string_header: "string_header",
                 base_url: "https://example.com"
               )
    end
  end
end

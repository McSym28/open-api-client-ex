defmodule OpenAPIClient.OperationsTest do
  use ExUnit.Case, async: true
  import Mox

  @httpoison OpenAPIClient.HTTPoisonMock

  setup :verify_on_exit!

  describe "get_test/2" do
    test "[200] performs a request and encodes OpenAPIClient.TestSchema from response's body" do
      expect(@httpoison, :request, fn :get, "https://example.com/test", _, headers, options ->
        assert {_, "2024-01-02"} = List.keyfind(options[:params], "date_query_with_default", 0)
        assert {_, "2024-01-02T01:23:45Z"} = List.keyfind(options[:params], "datetime_query", 0)
        assert {_, "string"} = List.keyfind(options[:params], "optional_query", 0)
        assert {_, "2024-01-02"} = List.keyfind(headers, "x-date-header-with-default", 0)
        assert {_, "string"} = List.keyfind(headers, "x-optional-header", 0)
        assert {_, "string"} = List.keyfind(headers, "x-required-header", 0)

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
               OpenAPIClient.Operations.get_test("string",
                 optional_header: "string",
                 date_header_with_default: ~D[2024-01-02],
                 optional_query: "string",
                 datetime_query: ~U[2024-01-02 01:23:45Z],
                 date_query_with_default: ~D[2024-01-02],
                 base_url: "https://example.com"
               )
    end
  end

  describe "set_test/2" do
    test "[298] performs a request and encodes OpenAPIClient.TestRequestSchema from request's body" do
      expect(@httpoison, :request, fn :post, "https://example.com/test", body, headers, _ ->
        assert {_, "string"} = List.keyfind(headers, "x-string-header", 0)
        assert {_, "application/json"} = List.keyfind(headers, "content-type", 0)

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
                   array_enum: ["DYNAMIC_ENUM_1"],
                   child: %OpenAPIClient.TestRequestSchema.Child{string: "nested_string_value"},
                   enum_with_default: :default_enum,
                   number_enum: 2.0,
                   strict_enum: :strict_enum_3
                 },
                 string_header: "string",
                 base_url: "https://example.com"
               )
    end

    test "[299] performs a request and encodes OpenAPIClient.TestRequestSchema from request's body" do
      expect(@httpoison, :request, fn :post, "https://example.com/test", body, headers, _ ->
        assert {_, "string"} = List.keyfind(headers, "x-string-header", 0)
        assert {_, "application/json"} = List.keyfind(headers, "content-type", 0)

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
                   array_enum: ["DYNAMIC_ENUM_1"],
                   child: %OpenAPIClient.TestRequestSchema.Child{string: "nested_string_value"},
                   enum_with_default: :default_enum,
                   number_enum: 2.0,
                   strict_enum: :strict_enum_3
                 },
                 string_header: "string",
                 base_url: "https://example.com"
               )
    end

    test "[400] performs a request and encodes OpenAPIClient.TestRequestSchema from request's body" do
      expect(@httpoison, :request, fn :post, "https://example.com/test", body, headers, _ ->
        assert {_, "string"} = List.keyfind(headers, "x-string-header", 0)
        assert {_, "application/json"} = List.keyfind(headers, "content-type", 0)

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
                   array_enum: ["DYNAMIC_ENUM_1"],
                   child: %OpenAPIClient.TestRequestSchema.Child{string: "nested_string_value"},
                   enum_with_default: :default_enum,
                   number_enum: 2.0,
                   strict_enum: :strict_enum_3
                 },
                 string_header: "string",
                 base_url: "https://example.com"
               )
    end
  end
end

defmodule OpenAPIClient.Client.TypedEncoderTest do
  use ExUnit.Case, async: true
  alias OpenAPIClient.Client.TypedEncoder
  alias OpenAPIClient.TestSchema

  describe "encode/1" do
    test "successfully encodes schema" do
      assert {:ok,
              %{
                "Boolean" => false,
                "Integer" => 1,
                "Number" => 1.0,
                "String" => "string",
                "DateTime" => ~U[2024-01-02T01:23:45Z],
                "Enum" => "ENUM_1"
              }} ==
               TypedEncoder.encode(%TestSchema{
                 boolean: false,
                 integer: 1,
                 number: 1.0,
                 string: "string",
                 date_time: ~U[2024-01-02T01:23:45Z],
                 enum: :enum_1
               })
    end

    test "successfully encodes schema list" do
      assert {:ok,
              [
                %{
                  "Boolean" => false,
                  "Integer" => 1,
                  "Number" => 1.0,
                  "String" => "string",
                  "DateTime" => ~U[2024-01-02T01:23:45Z],
                  "Enum" => "ENUM_1"
                },
                %{
                  "Boolean" => true,
                  "Integer" => 2,
                  "Number" => 2.0,
                  "String" => "another_string",
                  "DateTime" => ~U[2025-02-03T12:34:56Z],
                  "Enum" => "ENUM_3"
                }
              ]} ==
               TypedEncoder.encode([
                 %TestSchema{
                   boolean: false,
                   integer: 1,
                   number: 1.0,
                   string: "string",
                   date_time: ~U[2024-01-02T01:23:45Z],
                   enum: :enum_1
                 },
                 %TestSchema{
                   boolean: true,
                   integer: 2,
                   number: 2.0,
                   string: "another_string",
                   date_time: ~U[2025-02-03T12:34:56Z],
                   enum: "ENUM_3"
                 }
               ])
    end
  end
end

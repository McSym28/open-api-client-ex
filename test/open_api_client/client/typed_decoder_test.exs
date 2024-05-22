defmodule OpenAPIClient.Client.TypedDecoderTest do
  use ExUnit.Case, async: true
  alias OpenAPIClient.Client.TypedDecoder
  alias OpenAPIClient.TestSchema

  doctest TypedDecoder

  describe "decode/2" do
    test "successfully decodes schema" do
      assert {:ok,
              %TestSchema{
                boolean: false,
                integer: 1,
                number: 1.0,
                string: "string",
                date_time: ~U[2024-01-02T01:23:45Z],
                enum: :enum_1
              }} ==
               TypedDecoder.decode(
                 %{
                   "Boolean" => false,
                   "Integer" => 1,
                   "Number" => 1.0,
                   "String" => "string",
                   "DateTime" => "2024-01-02T01:23:45Z",
                   "Enum" => "ENUM_1",
                   "Extra" => "some_data"
                 },
                 {TestSchema, :t}
               )
    end

    test "successfully decodes schema list" do
      assert {:ok,
              [
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
              ]} ==
               TypedDecoder.decode(
                 [
                   %{
                     "Boolean" => false,
                     "Integer" => 1,
                     "Number" => 1.0,
                     "String" => "string",
                     "DateTime" => "2024-01-02T01:23:45Z",
                     "Enum" => "ENUM_1",
                     "Extra" => "some_data"
                   },
                   %{
                     "Boolean" => true,
                     "Integer" => 2,
                     "Number" => 2.0,
                     "String" => "another_string",
                     "DateTime" => "2025-02-03T12:34:56Z",
                     "Enum" => "ENUM_3",
                     "OtherExtra" => "some_other_data"
                   }
                 ],
                 [{TestSchema, :t}]
               )
    end
  end
end

defmodule OpenAPIClient.Client.TypedDecoderTest do
  use ExUnit.Case, async: true
  alias OpenAPIClient.Client.{Error, TypedDecoder}
  alias OpenAPIClient.TestSchema

  doctest TypedDecoder

  @successful_conversions [
    {:null, "null from empty string", "", nil},
    {{:string, :generic}, "nil", nil, nil},
    {:boolean, true, true},
    {:boolean, "boolean as string `false`", "false", false},
    {:boolean, "boolean as string `true`", "true", true},
    {:integer, 3, 3},
    {:integer, "integer as string", "2", 2},
    {:number, 4.0, 4.0},
    {:number, "number as integer", 5, 5},
    {:number, "number as string", "6", 6.0},
    {{:string, :date}, "date", "2024-01-02", quote(do: ~D[2024-01-02])},
    {{:string, :date}, "date as date_time string", "2024-03-04T00:11:22Z",
     quote(do: ~D[2024-03-04])},
    {{:string, :date}, "date as `Date`", quote(do: ~D[2024-02-03]), quote(do: ~D[2024-02-03])},
    {{:string, :date}, "date as `DateTime`", quote(do: ~U[2024-03-04T00:11:22Z]),
     quote(do: ~D[2024-03-04])},
    {{:string, :date_time}, "date_time", "2024-04-05T01:23:45Z",
     quote(do: ~U[2024-04-05T01:23:45Z])},
    {{:string, :date_time}, "date_time as `DateTime`", quote(do: ~U[2024-05-06T11:22:33Z]),
     quote(do: ~U[2024-05-06T11:22:33Z])},
    {{:string, :time}, "time", "22:33:44", quote(do: ~T[22:33:44])},
    {{:string, :time}, "time as date_time string", "2024-03-04T00:11:22Z",
     quote(do: ~T[00:11:22])},
    {{:string, :time}, "time as `Time`", quote(do: ~T[12:23:34]), quote(do: ~T[12:23:34])},
    {{:string, :time}, "time as `DateTime`", quote(do: ~U[2024-06-07T23:44:55Z]),
     quote(do: ~T[23:44:55])},
    {{:string, :generic}, "string as number", 1, "1"},
    {{:string, :generic}, "string as atom", :string, "string"},
    {{:enum, [2, 3]}, "enum as number", 2, 2}
  ]

  @failed_conversions [
    {:boolean, "boolean as integer", 1, :invalid_boolean},
    {:integer, "integer as boolean", true, :invalid_integer},
    {:integer, "integer as string", "22T", :invalid_integer},
    {:number, "number as string", "!222", :invalid_number},
    {:number, "number as atom", :atom, :invalid_number},
    {{:string, :date}, "date as integer", 2, :invalid_datetime_string},
    {{:string, :date}, "date", "U2024-01-02", :invalid_format},
    {{:string, :date_time}, "date_time", "2024-04-05F01:23:45Z", :invalid_format},
    {{:string, :time}, "time", "01:23:45P", :invalid_format},
    {{:string, :generic}, "string as map", quote(do: %{"a" => "b"}), :invalid_string},
    {{:union, [:integer, {:string, :generic}]}, "union", 1, :unsupported_type},
    {[:integer], "list as string", "list", :invalid_list},
    {{:enum, [{:enum1, "ENUM1"}, {:enum2, "ENUM2"}]}, "enum", "ENUM3", :invalid_enum},
    {:map, "map as integer", 2, :invalid_map}
  ]

  describe "decode/2" do
    @successful_conversions
    |> Enum.map(fn
      {type, value, expected_value} -> {type, to_string(type), value, expected_value}
      {_type, _test_suffix, _value, _expected_value} = clause -> clause
    end)
    |> Enum.map(fn {type, test_suffix, value, expected_value} ->
      test "successfully decodes #{test_suffix}" do
        assert {:ok, unquote(expected_value)} ==
                 TypedDecoder.decode(unquote(value), unquote(type))
      end
    end)

    @failed_conversions
    |> Enum.map(fn
      {type, value, error_reason} -> {type, to_string(type), value, error_reason}
      {_type, _test_suffix, _value, _error_reason} = clause -> clause
    end)
    |> Enum.map(fn {type, test_suffix, value, error_reason} ->
      test "failed decoding #{test_suffix}" do
        assert {:error, %Error{reason: unquote(error_reason)}} =
                 TypedDecoder.decode(unquote(value), unquote(type))
      end
    end)

    test "successfully decodes schema" do
      assert {:ok,
              %TestSchema{
                boolean: false,
                integer: 1,
                number: 1.0,
                string: "string",
                date_time: ~U[2024-01-02T01:23:45Z],
                enum: :enum1
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
                  enum: :enum1
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

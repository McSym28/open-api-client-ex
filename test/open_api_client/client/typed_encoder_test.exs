defmodule OpenAPIClient.Client.TypedEncoderTest do
  use ExUnit.Case, async: true
  alias OpenAPIClient.Client.{Error, TypedEncoder}
  alias OpenAPIClient.TestSchema

  doctest TypedEncoder

  @successful_conversions [
    {{:string, :generic}, "nil", nil, nil},
    {:boolean, true, true},
    {:integer, 3, 3},
    {:number, 4.0, 4.0},
    {{:string, :date}, "date", quote(do: ~D[2024-01-02]), quote(do: ~D[2024-01-02])},
    {{:string, :date}, "date as `DateTime`", quote(do: ~U[2024-03-04T00:11:22Z]),
     quote(do: ~D[2024-03-04])},
    {{:string, :date_time}, "date_time", quote(do: ~U[2024-05-06T11:22:33Z]),
     quote(do: ~U[2024-05-06T11:22:33Z])},
    {{:string, :time}, "time", quote(do: ~T[12:23:34]), quote(do: ~T[12:23:34])},
    {{:string, :time}, "time as `DateTime`", quote(do: ~U[2024-06-07T23:44:55Z]),
     quote(do: ~T[23:44:55])},
    {{:string, :generic}, "string", "string", "string"},
    {{:enum, [2, 3]}, "enum as number", 2, 2},
    {:map, "map as struct",
     quote(
       do: %TestSchema{
         boolean: false,
         integer: 1,
         number: 1.0,
         string: "string",
         date_time: ~U[2024-01-02T01:23:45Z],
         enum: :enum1
       }
     ),
     quote(
       do: %{
         boolean: false,
         integer: 1,
         number: 1.0,
         string: "string",
         date_time: ~U[2024-01-02T01:23:45Z],
         enum: :enum1
       }
     )}
  ]

  @failed_conversions [
    {:boolean, "boolean as integer", 1, :invalid_boolean},
    {:integer, "integer as boolean", true, :invalid_integer},
    {:number, "number as string", "22", :invalid_number},
    {{:string, :date}, "date as integer", 2, :invalid_datetime_format},
    {{:string, :generic}, "string as integer", 5, :invalid_string},
    {{:union, [:integer, {:string, :generic}]}, "union", 1, :unsupported_type},
    {[:integer], "list as string", "list", :invalid_list},
    {{:enum, [{:enum1, "ENUM1"}, {:enum2, "ENUM2"}]}, "enum", :enum3, :invalid_enum},
    {:map, "map as integer", 2, :invalid_map}
  ]

  describe "encode/4" do
    @successful_conversions
    |> Enum.map(fn
      {type, value, expected_value} -> {type, to_string(type), value, expected_value}
      {_type, _test_suffix, _value, _expected_value} = clause -> clause
    end)
    |> Enum.map(fn {type, test_suffix, value, expected_value} ->
      test "successfully encodes #{test_suffix}" do
        assert {:ok, unquote(expected_value)} ==
                 TypedEncoder.encode(unquote(value), unquote(type), [], TypedEncoder)
      end
    end)

    @failed_conversions
    |> Enum.map(fn
      {type, value, error_reason} -> {type, to_string(type), value, error_reason}
      {_type, _test_suffix, _value, _error_reason} = clause -> clause
    end)
    |> Enum.map(fn {type, test_suffix, value, error_reason} ->
      test "failed encoding #{test_suffix}" do
        assert {:error, %Error{reason: unquote(error_reason)}} =
                 TypedEncoder.encode(unquote(value), unquote(type), [], TypedEncoder)
      end
    end)

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
               TypedEncoder.encode(
                 %TestSchema{
                   boolean: false,
                   integer: 1,
                   number: 1.0,
                   string: "string",
                   date_time: ~U[2024-01-02T01:23:45Z],
                   enum: :enum1
                 },
                 {TestSchema, :t},
                 [],
                 TypedEncoder
               )
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
               TypedEncoder.encode(
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
                 ],
                 [{TestSchema, :t}],
                 [],
                 TypedEncoder
               )
    end
  end
end

defmodule OpenAPIClient.Generator.ExampleGeneratorTest do
  use ExUnit.Case, async: true
  alias OpenAPIClient.Generator.ExampleGenerator
  alias OpenAPI.Processor.Schema.Field
  alias OpenAPI.Processor.Operation.Param
  alias OpenAPIClient.Generator.Param, as: GeneratorParam
  alias OpenAPIClient.Generator.Schema, as: GeneratorSchema
  alias OpenAPIClient.Generator.Field, as: GeneratorField
  alias OpenAPIClient.Generator.SchemaType

  doctest ExampleGenerator

  @integer_field %GeneratorField{
    field: %Field{name: "integer", type: :integer},
    old_name: "Integer",
    schema_type: %SchemaType{examples: [2, 3]}
  }
  @string_field %GeneratorField{
    field: %Field{name: "string", type: {:string, :generic}},
    old_name: "String",
    schema_type: %SchemaType{examples: ["string1", "string1"]}
  }
  @enum_field %GeneratorField{
    field: %Field{name: "enum", type: {:enum, ["ENUM1", "ENUM2"]}},
    old_name: "Enum",
    schema_type: %SchemaType{
      enum: %SchemaType.Enum{options: [enum1: "ENUM1", enum2: "ENUM2"], type: {:string, :generic}},
      examples: ["ENUM1", "ENUM2"]
    }
  }
  @array_enum_field %GeneratorField{
    field: %Field{name: "array_enum", type: {:array, {:enum, ["ENUM1", "ENUM2"]}}},
    old_name: "ArrayEnum",
    schema_type: %SchemaType{
      enum: %SchemaType.Enum{options: [enum1: "ENUM1", enum2: "ENUM2"], type: {:string, :generic}},
      examples: [["ENUM1", "ENUM2"]]
    }
  }
  @extra_field %GeneratorField{old_name: "Extra"}

  @schema %GeneratorSchema{
    fields: [@integer_field, @string_field, @enum_field, @array_enum_field, @extra_field]
  }

  @integer_param %GeneratorParam{
    param: %Param{name: "integer", location: :header, value_type: :integer},
    old_name: "Integer",
    schema_type: %SchemaType{examples: [2, 3]}
  }

  @clauses [
    {:null, {:pipe, quote(do: is_nil())}},
    {:boolean, {:pipe, quote(do: is_boolean())}},
    {{:boolean, "custom"}, "boolean with custom format", {:pipe, quote(do: is_boolean())}},
    {:integer, {:pipe, quote(do: is_integer())}},
    {{:integer, "int64"}, "integer with int64 format", {:pipe, quote(do: is_integer())}},
    {:number, {:pipe, quote(do: is_number())}},
    {{:number, "float"}, "number with float format", {:pipe, quote(do: is_number())}},
    {{:string, :date}, "date",
     {:pattern_pipe, quote(do: %Date{}), quote(do: Date.from_iso8601!())}},
    {{:string, :time}, "time",
     {:pattern_pipe, quote(do: %Time{}), quote(do: Time.from_iso8601!())}},
    {{:string, :date_time}, "date_time",
     {:pattern_pipe, quote(do: {:ok, %DateTime{}, _}), quote(do: DateTime.from_iso8601())}},
    {{:string, :uri}, "uri", {:pattern_pipe, quote(do: %URI{}), quote(do: URI.parse())}},
    {{:string, :generic}, "string", {:pipe, quote(do: is_binary())}},
    {{:array, :number}, "array of numbers", {:pipe, quote(do: Enum.all?(&is_number/1))}},
    {{:array, {:string, :generic}}, "array of strings",
     {:pipe, quote(do: Enum.all?(&is_binary/1))}},
    {{:const, 1}, "const integer", {:pipe, quote(do: is_integer())}},
    {{:enum, [3, 5, 1]}, "enum with integer", {:pipe, quote(do: is_integer())}},
    {{:enum, [enum1: "ENUM1", enum2: "ENUM2"]}, "enum with aliases",
     {:pipe, quote(do: is_binary())}},
    {:map, {:pipe, quote(do: is_map())}},
    {:any, {:pipe, quote(do: is_map())}},
    {quote(do: @integer_field), "integer field", {:pipe, quote(do: is_integer())}},
    {quote(do: @string_field), "string field", {:pipe, quote(do: is_binary())}},
    {quote(do: put_in(@integer_field, [Access.key!(:schema_type), Access.key!(:examples)], [])),
     "integer field without examples", {:pipe, quote(do: is_integer())}},
    {quote(do: put_in(@enum_field, [Access.key!(:schema_type), Access.key!(:examples)], [])),
     "enum field", {:pipe, quote(do: is_binary())}},
    {quote(
       do: put_in(@array_enum_field, [Access.key!(:schema_type), Access.key!(:examples)], [])
     ), "array of enums field", {:pipe, quote(do: Enum.all?(&is_binary/1))}},
    {quote(do: @schema), "schema", {:pipe, quote(do: is_map())}},
    {quote(do: @integer_param), "integer param", {:pipe, quote(do: is_integer())}}
  ]

  describe "generate/3" do
    @clauses
    |> Enum.map(fn
      {type, check} -> {type, to_string(type), check}
      {_type, _test_suffix, _check} = clause -> clause
    end)
    |> Enum.map(fn {type, test_suffix, check} ->
      check =
        case check do
          {:pattern_pipe, pattern, pipe} ->
            quote do:
                    assert(
                      unquote(pattern) =
                        unquote(type)
                        |> ExampleGenerator.generate([], ExampleGenerator)
                        |> unquote(pipe)
                    )

          {:pipe, pipe} ->
            quote do:
                    assert(
                      unquote(type)
                      |> ExampleGenerator.generate([], ExampleGenerator)
                      |> unquote(pipe)
                    )
        end

      test "generate example for #{test_suffix}" do
        unquote(check)
      end
    end)
  end
end

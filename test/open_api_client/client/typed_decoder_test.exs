defmodule OpenAPIClient.Client.TypedDecoderTest do
  use ExUnit.Case
  alias OpenAPIClient.Client.TypedDecoder
  doctest TypedDecoder

  defmodule TestSchema do
    @behaviour OpenAPIClient.Schema

    defstruct [:boolean, :integer, :number, :string, :datetime, :enum]

    @field_renamings %{
      boolean: "Boolean",
      integer: "Integer",
      number: "Number",
      string: "String",
      datetime: "DateTime",
      enum: "Enum"
    }

    @enum_field_renamings %{
      enum1: "ENUM_1",
      enum2: "ENUM_2"
    }

    @impl true
    def to_map(struct) do
      struct
      |> Map.from_struct()
      |> Map.new(fn
        {:enum = key, value} -> {@field_renamings[key], @enum_field_renamings[value] || value}
        {key, value} -> {@field_renamings[key], value}
      end)
    end

    @impl true
    def from_map(map) do
      fields =
        map
        |> Enum.flat_map(fn {key, value} ->
          case Enum.find(@field_renamings, fn {_new_name, old_name} -> old_name == key end) do
            {:enum = new_name, _old_name} ->
              [
                {new_name,
                 Enum.find_value(@enum_field_renamings, fn
                   {enum_atom, ^value} -> enum_atom
                   _ -> nil
                 end) || value}
              ]

            {new_name, _old_name} ->
              [{new_name, value}]

            _ ->
              []
          end
        end)

      struct(__MODULE__, fields)
    end

    @impl true
    def __fields__(:t) do
      %{
        "Boolean" => :boolean,
        "Integer" => :integer,
        "Number" => :number,
        "String" => {:string, :generic},
        "DateTime" => {:string, :date_time},
        "Enum" => {:enum, "ENUM_1", "ENUM_2"}
      }
    end
  end

  describe "decode/2" do
    test "successfully decodes schema" do
      assert {:ok,
              %TestSchema{
                boolean: false,
                integer: 1,
                number: 1.0,
                string: "string",
                datetime: ~U[2024-01-02T01:23:45Z],
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
                  datetime: ~U[2024-01-02T01:23:45Z],
                  enum: :enum1
                },
                %TestSchema{
                  boolean: true,
                  integer: 2,
                  number: 2.0,
                  string: "another_string",
                  datetime: ~U[2025-02-03T12:34:56Z],
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

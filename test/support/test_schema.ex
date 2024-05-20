defmodule OpenAPIClient.TestSchema do
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

defmodule OpenAPIClient.TestSchema do
  @moduledoc """
  Provides struct and type for a TestSchema
  """

  @behaviour OpenAPIClient.Schema

  require OpenAPIClient.Schema

  @type t :: %__MODULE__{
          boolean: boolean,
          date_time: DateTime.t(),
          enum: :enum_1 | :enum_2 | String.t(),
          integer: integer,
          number: number,
          string: String.t()
        }

  @enforce_keys [:boolean, :date_time, :enum, :integer, :number, :string]
  defstruct [:boolean, :date_time, :enum, :integer, :number, :string]

  @impl true
  def to_map(%__MODULE__{
        boolean: boolean,
        date_time: date_time,
        enum: enum,
        integer: integer,
        number: number,
        string: string
      }) do
    %{
      "Boolean" => boolean,
      "DateTime" => date_time,
      "Enum" =>
        OpenAPIClient.Schema.enum_to_map(enum, [
          {:enum_1, "ENUM_1"},
          {:enum_2, "ENUM_2"},
          :not_strict
        ]),
      "Integer" => integer,
      "Number" => number,
      "String" => string
    }
  end

  @impl true
  def from_map(%{} = map) do
    fields =
      Enum.flat_map(map, fn
        {"Boolean", boolean} ->
          [boolean: boolean]

        {"DateTime", date_time} ->
          [date_time: date_time]

        {"Enum", enum} ->
          [
            enum:
              OpenAPIClient.Schema.enum_from_map(enum, [
                {:enum_1, "ENUM_1"},
                {:enum_2, "ENUM_2"},
                :not_strict
              ])
          ]

        {"Integer", integer} ->
          [integer: integer]

        {"Number", number} ->
          [number: number]

        {"String", string} ->
          [string: string]

        _ ->
          []
      end)

    struct(__MODULE__, fields)
  end

  @doc false
  @impl true
  @spec __fields__(atom) :: %{optional(String.t()) => term()}
  def __fields__(type \\ :t)

  def __fields__(:t) do
    %{
      "Boolean" => :boolean,
      "DateTime" => {:string, :date_time},
      "Enum" => {:enum, [:enum_1, :enum_2]},
      "Integer" => :integer,
      "Number" => :number,
      "String" => {:string, :generic}
    }
  end
end

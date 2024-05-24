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
  @type types :: :t

  @enforce_keys [:boolean, :date_time, :enum, :integer, :number, :string]
  defstruct [:boolean, :date_time, :enum, :integer, :number, :string]

  @doc false
  @impl true
  @spec __fields__(types()) :: keyword(OpenAPIClient.Schema.schema_type())
  def __fields__(type \\ :t)

  def __fields__(:t) do
    [
      boolean: {"Boolean", :boolean},
      date_time: {"DateTime", {:string, :date_time}},
      enum: {"Enum", {:enum, [{:enum_1, "ENUM_1"}, {:enum_2, "ENUM_2"}, :not_strict]}},
      integer: {"Integer", :integer},
      number: {"Number", :number},
      string: {"String", {:string, :generic}}
    ]
  end
end

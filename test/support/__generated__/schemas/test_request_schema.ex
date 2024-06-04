defmodule OpenAPIClient.TestRequestSchema do
  @moduledoc """
  Provides struct and type for a TestRequestSchema
  """

  @behaviour OpenAPIClient.Schema

  @type t :: %__MODULE__{
          array_enum: [:dynamic_enum_1 | :dynamic_enum_2 | String.t()] | nil,
          child: OpenAPIClient.TestRequestSchema.Child.t() | nil,
          number_enum: 1 | number | nil,
          strict_enum: :strict_enum_1 | :strict_enum_2 | :strict_enum_3
        }
  @type types :: :t

  @enforce_keys [:strict_enum]
  defstruct [:array_enum, :child, :number_enum, :strict_enum]

  @doc false
  @impl OpenAPIClient.Schema
  @spec __fields__(types()) :: keyword(OpenAPIClient.Schema.schema_type())
  def __fields__(:t) do
    [
      array_enum:
        {"ArrayEnum",
         {:array,
          {:enum,
           [{:dynamic_enum_1, "DYNAMIC_ENUM_1"}, {:dynamic_enum_2, "DYNAMIC_ENUM_2"}, :not_strict]}}},
      child: {"Child", {OpenAPIClient.TestRequestSchema.Child, :t}},
      number_enum: {"NumberEnum", {:enum, [1, 2.0, 3.0, :not_strict]}},
      strict_enum:
        {"StrictEnum",
         {:enum,
          strict_enum_1: "STRICT_ENUM_1",
          strict_enum_2: "STRICT_ENUM_2",
          strict_enum_3: "STRICT_ENUM_3"}}
    ]
  end
end

defmodule OpenAPIClient.TestRequestSchema.Child do
  @moduledoc """
  Provides struct and type for a TestRequestSchema.Child
  """

  @behaviour OpenAPIClient.Schema

  @type t :: %__MODULE__{string: String.t() | nil}
  @type types :: :t

  defstruct [:string]

  @doc false
  @impl OpenAPIClient.Schema
  @spec __fields__(types()) :: keyword(OpenAPIClient.Schema.schema_type())
  @spec __fields__() :: keyword(OpenAPIClient.Schema.schema_type())
  def __fields__(type \\ :t)

  def __fields__(:t) do
    [string: {"String", {:string, :generic}}]
  end
end

defmodule OpenAPIClient.CallbackResponse do
  @moduledoc """
  Provides struct and type for a CallbackResponse
  """

  @behaviour OpenAPIClient.Schema

  @type t :: %__MODULE__{acknowledged: boolean}
  @type types :: :t

  @enforce_keys [:acknowledged]
  defstruct [:acknowledged]

  @doc false
  @impl OpenAPIClient.Schema
  @spec __fields__(types()) :: keyword(OpenAPIClient.Schema.field_type())
  def __fields__(:t) do
    [acknowledged: {"acknowledged", :boolean}]
  end
end

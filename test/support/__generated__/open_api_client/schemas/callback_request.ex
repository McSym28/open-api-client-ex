defmodule OpenAPIClient.CallbackRequest do
  @moduledoc """
  Provides struct and type for a CallbackRequest
  """

  @behaviour OpenAPIClient.Schema

  @type t :: %__MODULE__{message: String.t()}
  @type types :: :t

  @enforce_keys [:message]
  defstruct [:message]

  @doc false
  @impl OpenAPIClient.Schema
  @spec __fields__(types()) :: keyword(OpenAPIClient.Schema.field_type())
  def __fields__(:t) do
    [message: {"message", {:string, :generic}}]
  end
end

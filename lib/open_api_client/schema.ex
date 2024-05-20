defmodule OpenAPIClient.Schema do
  @callback to_map(struct :: struct()) :: map()
  @callback from_map(map :: map()) :: struct()
  @callback __fields__(atom()) :: %{optional(String.t()) => term()}
end

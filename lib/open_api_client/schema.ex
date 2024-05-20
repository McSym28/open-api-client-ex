defmodule OpenAPIClient.Schema do
  @typedoc "Type annotation produced by [OpenAPI](https://github.com/aj-foster/open-api-generator)"
  @type non_array_type() ::
          :binary
          | :boolean
          | :integer
          | :map
          | :number
          | {:string, atom()}
          | :unknown
          # | {:nullable, type}
          | {:union, [type]}
          | {module, atom}
  @type type() :: non_array_type() | [non_array_type()]

  @callback to_map(struct :: struct()) :: map()
  @callback from_map(map :: map()) :: struct()
  @callback __fields__(atom()) :: %{optional(String.t()) => term()}
end

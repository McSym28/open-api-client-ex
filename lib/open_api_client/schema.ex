defmodule OpenAPIClient.Schema do
  @typedoc "Type annotation produced by [OpenAPI](https://github.com/aj-foster/open-api-generator)"
  @type non_array_type ::
          :null
          | :binary
          | :boolean
          | :integer
          | :map
          | :number
          | {:string, atom()}
          | :unknown
          | {:union, [type()]}
          | {:enum, [integer() | number() | boolean() | {atom(), String.t()} | :not_strict]}
          | {module(), atom()}
  @type type :: non_array_type() | [non_array_type()]
  @type schema_type :: {String.t(), schema_type()}

  @callback __fields__(atom()) :: keyword(schema_type())
end

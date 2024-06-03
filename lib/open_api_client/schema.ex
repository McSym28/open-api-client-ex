defmodule OpenAPIClient.Schema do
  @type enum_option ::
          integer()
          | number()
          | boolean()
          | {atom(), String.t() | integer() | number() | boolean()}
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
          | {:enum, [enum_option | :not_strict]}
          | {module(), atom()}
  @type type :: non_array_type() | [non_array_type()]
  @type schema_type :: {String.t(), type()}

  @callback __fields__(atom()) :: keyword(schema_type())
end

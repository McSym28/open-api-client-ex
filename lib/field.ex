defmodule OpenAPIGenerator.Field do
  defstruct field: nil,
            old_name: nil,
            enforce: false,
            enum_aliases: %{},
            type: nil,
            extra: false,
            field_function_type: nil
end

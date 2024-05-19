defmodule OpenAPIGenerator.Field do
  defstruct field: nil,
            old_name: nil,
            enforce: false,
            enum_aliases: %{},
            type: nil,
            extra: false
end

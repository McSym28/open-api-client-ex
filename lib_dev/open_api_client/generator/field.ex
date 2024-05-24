defmodule OpenAPIClient.Generator.Field do
  defstruct field: nil,
            old_name: nil,
            enforce: false,
            enum_options: [],
            enum_strict: false,
            type: nil,
            extra: false,
            examples: []
end

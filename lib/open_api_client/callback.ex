defmodule OpenAPIClient.Callback do
  alias OpenAPIClient.{Schema, State}

  @type response_parameter_type_key :: {atom(), State.common_parameter_location()}
  @type function_option ::
          {:request_parameter_types, [{State.parameter_type_key(), Schema.field_type()}]}
          | {:request_types, [State.request_schema()]}
          | {:response_types, [State.response_type()]}
          | {:response_parameter_types, [{response_parameter_type_key(), Schema.field_type()}]}
          | {:request_parameter_args, [atom()]}
          | {:request_path_mask, State.url()}
          | {:profile, atom()}

  @callback __functions__(atom()) :: [function_option()]
end

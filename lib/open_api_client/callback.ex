defmodule OpenAPIClient.Callback do
  alias OpenAPIClient.Client.Operation
  alias OpenAPIClient.Schema

  @type response_parameter_type_key :: {atom(), Operation.common_parameter_location()}
  @type function_option ::
          {:request_parameter_types, [{Operation.parameter_type_key(), Schema.field_type()}]}
          | {:request_types, [Operation.request_schema()]}
          | {:response_types, [Operation.response_type()]}
          | {:response_parameter_types, [{response_parameter_type_key(), Schema.field_type()}]}
          | {:request_parameter_args, [atom()]}
          | {:request_path_mask, Operation.url()}

  @callback __functions__(atom()) :: [function_option()]
end

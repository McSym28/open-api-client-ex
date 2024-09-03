defmodule OpenAPIClient.Client.TestCallbackPipeline do
  use Pluggable.StepBuilder

  step OpenAPIClient.Client.Steps.RequestTypedDecoder
  step OpenAPIClient.Client.Steps.CallbackFunctionCall
  step OpenAPIClient.Client.Steps.ResponseBodyTypedEncoder
  step OpenAPIClient.Client.Steps.ResponseBodyContentTypeEncoder
end

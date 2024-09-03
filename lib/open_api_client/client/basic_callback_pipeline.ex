defmodule OpenAPIClient.Client.BasicCallbackPipeline do
  use Pluggable.StepBuilder

  step OpenAPIClient.Client.Steps.RequestTypedDecoder
  step OpenAPIClient.Client.Steps.CallbackFunctionCall
  step OpenAPIClient.Client.Steps.ResponseBodyTypedEncoder
end

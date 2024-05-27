defmodule OpenAPIClient.TestClientPipeline do
  use Pluggable.StepBuilder

  step OpenAPIClient.Client.Steps.RequestBodyTypedEncoder
  step OpenAPIClient.Client.Steps.RequestBodyContentTypeEncoder
  step OpenAPIClient.Client.Steps.HTTPoisonClient
  step OpenAPIClient.Client.Steps.ResponseBodyContentTypeDecoder
  step OpenAPIClient.Client.Steps.ResponseBodyTypedDecoder
end

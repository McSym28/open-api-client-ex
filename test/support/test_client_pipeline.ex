defmodule OpenAPIClient.TestClientPipeline do
  use Pluggable.StepBuilder

  step OpenAPIClient.Client.Steps.RequestBodyTypedEncoder
  step OpenAPIClient.Client.Steps.RequestBodyJSONEncoder
  step OpenAPIClient.Client.Steps.HTTPoisonClient, httpoison: OpenAPIClient.HTTPoisonMock
  step OpenAPIClient.Client.Steps.ResponseBodyJSONDecoder
  step OpenAPIClient.Client.Steps.ResponseBodyTypedDecoder
end

if Code.ensure_loaded?(HTTPoison) do
  defmodule OpenAPIClient.Client.BasicHTTPoisonPipeline do
    use Pluggable.StepBuilder

    step OpenAPIClient.Client.Steps.RequestTypedEncoder
    step OpenAPIClient.Client.Steps.RequestBodyContentTypeEncoder
    step OpenAPIClient.Client.Steps.HTTPoisonClient
    step OpenAPIClient.Client.Steps.ResponseBodyContentTypeDecoder
    step OpenAPIClient.Client.Steps.ResponseBodyTypedDecoder
  end
end

if Code.ensure_loaded?(Jason) and Code.ensure_loaded?(HTTPoison) do
  defmodule OpenApiClient.JasonHTTPoisonOperationPipeline do
    use Plug.Builder

    plug(OpenAPIClient.Plugs.FunctionCallEncoder)
    plug(OpenAPIClient.Plugs.RequestTypedEncoder)
    plug(OpenAPIClient.Plugs.Serializers, serializers: [{:json, json_encoder: Jason}])
    plug(OpenAPIClient.Plugs.HTTPoisonRequest)
    plug(OpenAPIClient.Plugs.ResponseParsers, parsers: [{:json, json_decoder: Jason}])
    plug(OpenAPIClient.Plugs.ResponseTypedDecoder)
    plug(OpenAPIClient.Plugs.FunctionResultDecoder)
  end
end

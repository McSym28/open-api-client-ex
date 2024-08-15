ExUnit.start()
Mox.defmock(OpenAPIClient.HTTPoisonMock, for: HTTPoison.Base)
Mox.defmock(OpenAPIClient.ClientMock, for: OpenAPIClient.Client)

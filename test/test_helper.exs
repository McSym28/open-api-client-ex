ExUnit.start()
Mox.defmock(OpenAPIClient.HTTPoisonMock, for: HTTPoison.Base)
Mox.defmock(OpenAPIClient.ClientMock, for: OpenAPIClient.Client)
Mox.defmock(OpenAPIClient.CallbacksMock, for: OpenAPIClient.Callbacks)

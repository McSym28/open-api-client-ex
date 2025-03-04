defmodule OpenAPIClient.Callbacks do
  @moduledoc """
  Provides API callbacks related to callbacks
  """

  @behaviour OpenAPIClient.Callback

  @type callback_functions :: :my_event | :my_event_error

  @doc """
  post `/{*request.body.callbackUrl*}`

  ## Arguments

    * `x_required_callback_query`: ["X-Required-Callback-Query"] Required callback query parameter
    * `x_required_callback_header`: ["X-Required-Callback-Header"] Required callback header parameter
    * `body`

  ## Options

    * `x_optional_callback_query`: ["X-Optional-Callback-Query"] Optional callback query parameter
    * `x_optional_callback_header`: ["X-Optional-Callback-Header"] Optional callback header parameter
    * `x_optional_callback_cookie`: ["X-Optional-Callback-Cookie"] Optional callback cookie parameter

  """
  @callback my_event(String.t(), String.t(), OpenAPIClient.CallbackRequest.t(), [
              {:x_optional_callback_query, String.t()}
              | {:x_optional_callback_header, String.t()}
              | {:x_optional_callback_cookie, integer}
            ]) :: {:ok, OpenAPIClient.CallbackResponse.t()} | {:error, OpenAPIClient.Error.t()}
  @doc """
  post `/{*request.body.callbackUrl*}/error`

  ## Arguments

    * `body`

  """
  @callback my_event_error(OpenAPIClient.CallbackRequest.t()) ::
              {:ok, OpenAPIClient.CallbackResponse.t()} | {:error, OpenAPIClient.Error.t()}

  @optional_callbacks my_event_error: 1, my_event: 4

  @doc false
  @impl OpenAPIClient.Callback
  @spec __functions__(callback_functions()) :: [OpenAPIClient.Callback.function_option()]
  def __functions__(:my_event_error) do
    [
      request_path_mask: "/{*request.body.callbackUrl*}/error",
      request_types: [{"application/json", {OpenAPIClient.CallbackRequest, :t}}],
      response_types: [{200, [{"application/json", {OpenAPIClient.CallbackResponse, :t}}]}],
      profile: :test
    ]
  end

  def __functions__(:my_event) do
    [
      request_path_mask: "/{*request.body.callbackUrl*}",
      request_parameter_types: [
        {{:x_required_callback_query, :query},
         {"X-Required-Callback-Query", {:string, :generic}}},
        {{:x_required_callback_header, :header},
         {"X-Required-Callback-Header", {:string, :generic}}},
        {{:x_optional_callback_query, :query},
         {"X-Optional-Callback-Query", {:string, :generic}}},
        {{:x_optional_callback_header, :header},
         {"X-Optional-Callback-Header", {:string, :generic}}},
        {{:x_optional_callback_cookie, :cookie}, {"X-Optional-Callback-Cookie", :integer}}
      ],
      request_types: [{"application/json", {OpenAPIClient.CallbackRequest, :t}}],
      response_types: [{200, [{"application/json", {OpenAPIClient.CallbackResponse, :t}}]}],
      request_parameter_args: [:x_required_callback_query, :x_required_callback_header],
      profile: :test
    ]
  end
end

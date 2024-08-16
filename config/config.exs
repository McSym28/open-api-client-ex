# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configures Elixir's Logger
config :logger, :console, format: "$time [$level] $message\n"

config :open_api_client_ex,
  "$base": [
    client_pipeline: OpenAPIClient.Client.BasicHTTPoisonPipeline,
    decoders: [
      {"application/json", {Jason, :decode, []}}
    ],
    encoders: [
      {"application/json", {Jason, :encode, []}}
    ]
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
if config_env() != :prod, do: import_config("#{config_env()}.exs")

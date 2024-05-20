defmodule OpenAPIClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :open_api_client_ex,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "lib_dev", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "lib_dev"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:oapi_generator, git: "../../../open-api-generator", branch: "behaviour_impl"}
    ]
  end
end

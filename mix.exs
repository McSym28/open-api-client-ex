defmodule OpenAPIClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :open_api_client_ex,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["test/support" | elixirc_paths(:dev)]
  defp elixirc_paths(:dev), do: ["lib_dev" | elixirc_paths(:prod)]
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
      {:pluggable, "~> 1.1"},
      {:oapi_generator,
       git: "../../../open-api-generator", branch: "behaviour_impl", only: [:dev, :test]},
      {:jason, "~> 1.4", only: [:dev, :test]},
      {:httpoison, "~> 2.2", only: [:dev, :test]},
      {:mox, "~> 1.1", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end
end

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
        "coveralls.html": :test,
        "test.generate": :test
      ],
      aliases: aliases()
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["test/support" | elixirc_paths(:dev)]
  defp elixirc_paths(_env), do: ["lib"]

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application, do: application(Mix.env())

  defp application(:test), do: [{:mod, {OpenAPIClient.Application, []}} | application(:dev)]
  defp application(_env), do: [extra_applications: [:logger, :runtime_tools]]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:pluggable, "~> 1.1"},
      {:oapi_generator,
       github: "McSym28/open-api-generator",
       ref: "6e5292042c953fce1c4ebcb8421c2b03d062a772",
       only: [:dev, :test]},
      {:jason, "~> 1.4", optional: true},
      {:httpoison, "~> 2.2", optional: true},
      {:mox, "~> 1.2", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:phoenix, "~> 1.7", only: :test, optional: true},
      {:bandit, "~> 1.5", only: :test, optional: true}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      "test.generate": [
        "cmd rm -rf test/support/__generated__/*",
        "cmd rm -rf test/open_api_client/__generated__/*",
        "api.gen test test/fixture/test.yaml"
      ]
    ]
  end
end

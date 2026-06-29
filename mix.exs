defmodule AshGrpc.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :ash_grpc,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "A gRPC extension for the Ash Framework.",
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ash, "~> 3.0"},
      {:spark, "~> 2.0"},
      {:grpc, "~> 0.9"},
      {:protobuf, "~> 0.13"},
      {:jason, "~> 1.4"},
      # optional: trace propagation in the client interceptor
      {:opentelemetry_api, "~> 1.3", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end

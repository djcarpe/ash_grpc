defmodule Mix.Tasks.AshGrpc.Proto do
  @moduledoc """
  Generate `.proto` files from resources **and** compile them to Elixir in one
  step. Combines `mix ash_grpc.gen_proto` + `mix ash_grpc.compile_proto`.

      mix ash_grpc.proto --domain MyApp.Domain

  ## Options

    * `--domain`     — one or more Ash domains to scan (repeatable)
    * `--resource`   — a specific resource module (repeatable)
    * `--proto-out`  — where to write `.proto` files (default: `priv/protos`)
    * `--elixir-out` — where to write `.pb.ex` files  (default: `lib/generated`)
    * `--import-path` — extra protoc import paths (repeatable, forwarded to compile step)
    * `--no-compile` — skip the protoc compilation step (generate .proto only)

  ## Examples

      # Full workflow: generate + compile
      mix ash_grpc.proto --domain MyApp.Domain --proto-out priv/protos --elixir-out lib

      # Generate only (useful without protoc installed)
      mix ash_grpc.proto --domain MyApp.Domain --no-compile
  """

  use Mix.Task

  @shortdoc "Generate and compile protos for AshGrpc resources (one step)"

  @impl true
  def run(argv) do
    {opts, _rest, _} =
      OptionParser.parse(argv,
        strict: [
          domain: :keep,
          resource: :keep,
          proto_out: :string,
          elixir_out: :string,
          import_path: :keep,
          no_compile: :boolean
        ],
        aliases: []
      )

    proto_out = opts[:proto_out] || "priv/protos"
    elixir_out = opts[:elixir_out] || "lib/generated"
    skip_compile = opts[:no_compile] || false

    domain_args = opts |> Keyword.get_values(:domain) |> Enum.flat_map(&["--domain", &1])
    resource_args = opts |> Keyword.get_values(:resource) |> Enum.flat_map(&["--resource", &1])
    import_args = opts |> Keyword.get_values(:import_path) |> Enum.flat_map(&["--import-path", &1])

    gen_argv = domain_args ++ resource_args ++ ["--out", proto_out]
    compile_argv = ["--in", proto_out, "--out", elixir_out] ++ import_args

    Mix.shell().info([:bright, "==> ash_grpc.gen_proto", :reset])
    Mix.Task.rerun("ash_grpc.gen_proto", gen_argv)

    unless skip_compile do
      Mix.shell().info([:bright, "\n==> ash_grpc.compile_proto", :reset])
      Mix.Task.rerun("ash_grpc.compile_proto", compile_argv)
    end
  end
end

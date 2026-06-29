defmodule Mix.Tasks.AshGrpc.GenProto do
  @moduledoc """
  Generate `.proto` files from resources using the `AshGrpc.Resource` extension.

      mix ash_grpc.gen_proto --domain MyApp.Units --out priv/protos

  Options:

    * `--domain`  — one or more Ash domains to scan (repeatable)
    * `--resource` — a specific resource (repeatable)
    * `--out`     — output directory (default: priv/protos)

  After generating, run `protoc` (or `protobuf`'s escript) to compile the
  `.proto` files into Elixir message/service modules, e.g.:

      protoc --elixir_out=plugins=grpc:./lib priv/protos/*.proto
  """
  use Mix.Task

  @shortdoc "Generate .proto files from AshGrpc resources"

  @impl true
  def run(argv) do
    Mix.Task.run("app.config")

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [domain: :keep, resource: :keep, out: :string],
        aliases: [o: :out]
      )

    out = opts[:out] || "priv/protos"
    File.mkdir_p!(out)

    resources =
      resources_from_domains(Keyword.get_values(opts, :domain)) ++
        Enum.map(Keyword.get_values(opts, :resource), &Module.concat([&1]))

    resources = Enum.uniq(resources)

    if resources == [] do
      Mix.shell().error("No resources found. Pass --domain or --resource.")
    else
      Enum.each(resources, fn resource ->
        if grpc_resource?(resource) do
          proto = AshGrpc.Proto.Generator.generate(resource)
          file = Path.join(out, "#{file_base(resource)}.proto")
          File.write!(file, proto)
          Mix.shell().info("Generated #{file}")
        end
      end)
    end
  end

  defp resources_from_domains(domains) do
    Enum.flat_map(domains, fn domain ->
      mod = Module.concat([domain])
      Ash.Domain.Info.resources(mod)
    end)
  end

  defp grpc_resource?(resource) do
    Spark.Dsl.is?(resource, Ash.Resource) and
      AshGrpc.Resource in Spark.extensions(resource)
  rescue
    _ -> false
  end

  defp file_base(resource) do
    resource |> Module.split() |> List.last() |> Macro.underscore()
  end
end

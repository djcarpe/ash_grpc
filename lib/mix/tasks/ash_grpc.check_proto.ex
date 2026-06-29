defmodule Mix.Tasks.AshGrpc.CheckProto do
  @moduledoc """
  Verify that the committed `.proto` files match what `AshGrpc.Proto.Generator`
  would produce from the current resources. Exits non-zero on any mismatch —
  use this in CI to catch uncommitted proto drift.

      mix ash_grpc.check_proto --domain MyApp.Domain

  ## Options

    * `--domain`   — one or more Ash domains to scan (repeatable)
    * `--resource` — a specific resource module (repeatable)
    * `--out`      — directory to check against (default: `priv/protos`)

  ## Example CI step

      - run: mix ash_grpc.check_proto --domain MyApp.Domain
        # Fails if a resource changed but proto was not regenerated
  """

  use Mix.Task

  @shortdoc "CI check: verify .proto files are in sync with resources"

  @impl true
  def run(argv) do
    Mix.Task.run("app.config")

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [domain: :keep, resource: :keep, out: :string],
        aliases: [o: :out]
      )

    out = opts[:out] || "priv/protos"

    resources =
      (resources_from_domains(Keyword.get_values(opts, :domain)) ++
         Enum.map(Keyword.get_values(opts, :resource), &Module.concat([&1])))
      |> Enum.uniq()
      |> Enum.filter(&grpc_resource?/1)

    if resources == [] do
      Mix.shell().error("No AshGrpc resources found. Pass --domain or --resource.")
      Mix.raise("no resources to check")
    end

    results =
      Enum.map(resources, fn resource ->
        expected = AshGrpc.Proto.Generator.generate(resource)
        path = Path.join(out, "#{file_base(resource)}.proto")

        cond do
          not File.exists?(path) ->
            Mix.shell().error("Missing:  #{path}")
            :stale

          File.read!(path) != expected ->
            Mix.shell().error("Stale:    #{path}")
            :stale

          true ->
            Mix.shell().info([:green, "✓ ", :reset, "OK: #{path}"])
            :ok
        end
      end)

    if Enum.any?(results, &(&1 == :stale)) do
      Mix.shell().error("\nProto files are out of sync. Regenerate with:\n\n  mix ash_grpc.gen_proto --domain <Domain> --out #{out}\n")
      Mix.raise("proto drift detected")
    end
  end

  defp resources_from_domains(domains) do
    Enum.flat_map(domains, fn d ->
      Ash.Domain.Info.resources(Module.concat([d]))
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

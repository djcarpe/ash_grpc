defmodule Mix.Tasks.AshGrpc.CompileProto do
  @moduledoc """
  Compile `.proto` files into Elixir modules using `protoc` + `protoc-gen-elixir`.

      mix ash_grpc.compile_proto
      mix ash_grpc.compile_proto --in priv/protos --out lib/generated

  Requires `protoc` on `$PATH` and the `protoc-gen-elixir` escript plugin:

      # Install protoc (system)
      pacman -S protobuf          # Arch
      brew install protobuf       # macOS
      apt install protobuf-compiler  # Ubuntu

      # Install the Elixir codegen plugin
      mix escript.install hex protobuf

  ## Options

    * `--in`  / `-i`  — directory containing `.proto` files (default: `priv/protos`)
    * `--out` / `-o`  — output directory for generated `.pb.ex` files (default: `lib/generated`)
    * `--import-path` — extra import search paths, e.g. for well-known types (repeatable)
    * `--plugin-flags` — raw flags forwarded to protoc, e.g. `--plugin-flags=grpc_elixir_out=lib`
                         (default: `--elixir_out=plugins=grpc:<out>`)

  ## Examples

      # Typical development usage
      mix ash_grpc.compile_proto --in priv/protos --out lib

      # Separate grpc plugin (protobuf >= 0.12 style)
      mix ash_grpc.compile_proto \\
        --in priv/protos \\
        --out lib \\
        --plugin-flags "--elixir_out=lib --grpc_elixir_out=lib"
  """

  use Mix.Task

  @shortdoc "Compile .proto files into Elixir with protoc"

  @impl true
  def run(argv) do
    {opts, _rest, _} =
      OptionParser.parse(argv,
        strict: [in: :string, out: :string, import_path: :keep, plugin_flags: :string],
        aliases: [i: :in, o: :out]
      )

    proto_dir = opts[:in] || "priv/protos"
    out_dir = opts[:out] || "lib/generated"
    extra_import_paths = Keyword.get_values(opts, :import_path)

    ensure_protoc!()
    File.mkdir_p!(out_dir)

    proto_files = Path.wildcard(Path.join(proto_dir, "**/*.proto"))

    if proto_files == [] do
      Mix.shell().error("No .proto files found in #{proto_dir}")
      Mix.raise("nothing to compile")
    end

    import_args = Enum.flat_map(extra_import_paths, &["--proto_path=#{&1}"])
    import_args = ["--proto_path=#{proto_dir}" | import_args]

    output_args =
      case opts[:plugin_flags] do
        nil -> ["--elixir_out=plugins=grpc:#{out_dir}"]
        flags -> String.split(flags, " ", trim: true)
      end

    args = import_args ++ output_args ++ proto_files

    Mix.shell().info([:cyan, "protoc ", :reset, Enum.join(args, " ")])

    case System.cmd("protoc", args, stderr_to_stdout: true) do
      {output, 0} ->
        unless String.trim(output) == "", do: Mix.shell().info(output)
        Mix.shell().info([:green, "✓ ", :reset, "Compiled #{length(proto_files)} file(s) → #{out_dir}"])

      {output, code} ->
        Mix.shell().error("protoc exited with code #{code}:\n#{output}")
        Mix.raise("protoc failed")
    end
  end

  defp ensure_protoc! do
    case System.find_executable("protoc") do
      nil ->
        Mix.shell().error("""
        protoc not found. Install it:

          Arch:   pacman -S protobuf
          macOS:  brew install protobuf
          Ubuntu: apt install -y protobuf-compiler

        Then install the Elixir codegen plugin:

          mix escript.install hex protobuf
        """)
        Mix.raise("protoc not installed")

      path ->
        Mix.shell().info("protoc: #{path}")
    end
  end
end

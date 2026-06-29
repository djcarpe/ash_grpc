defmodule AshGrpc.Resource.Info do
  @moduledoc "Introspection for the `grpc` DSL section."

  use Spark.InfoGenerator,
    extension: AshGrpc.Resource,
    sections: [:grpc]

  alias Spark.Dsl.Extension

  @doc "All configured methods."
  def methods(resource) do
    Extension.get_entities(resource, [:grpc])
  end

  @doc "Find a method by its DSL name."
  def method(resource, name) do
    Enum.find(methods(resource), &(&1.name == name))
  end

  @doc "Find a method by its wire `rpc_name`."
  def method_by_rpc(resource, rpc_name) do
    Enum.find(methods(resource), &(&1.rpc_name == rpc_name))
  end

  @doc "The proto package, falling back to the service_name prefix."
  def package!(resource) do
    case grpc_package(resource) do
      {:ok, pkg} when is_binary(pkg) ->
        pkg

      _ ->
        resource
        |> service_name!()
        |> String.split(".")
        |> Enum.drop(-1)
        |> Enum.join(".")
    end
  end

  def service_name!(resource) do
    grpc_service_name!(resource)
  end
end

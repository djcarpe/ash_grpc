defmodule AshGrpc.Resource.Transformers.SetMessageModules do
  @moduledoc """
  Computes the request/response protobuf message module names for each method
  when not explicitly given. These names match what the proto generator emits,
  so the dispatcher and the generated modules agree.

  Naming: `<message_namespace>.<RpcName>Request` / `...Response`.
  """
  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def after?(AshGrpc.Resource.Transformers.SetMethodDefaults), do: true
  def after?(_), do: false

  @impl true
  def transform(dsl_state) do
    module = Transformer.get_persisted(dsl_state, :module)
    namespace = Transformer.get_option(dsl_state, [:grpc], :message_namespace) || module

    methods = Transformer.get_entities(dsl_state, [:grpc])

    dsl_state =
      Enum.reduce(methods, dsl_state, fn method, acc ->
        updated = %{
          method
          | request: method.request || Module.concat(namespace, :"#{method.rpc_name}Request"),
            response: method.response || Module.concat(namespace, :"#{method.rpc_name}Response")
        }

        Transformer.replace_entity(acc, [:grpc], updated, fn existing ->
          existing.name == method.name
        end)
      end)

    {:ok, dsl_state}
  end
end

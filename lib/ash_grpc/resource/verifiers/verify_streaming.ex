defmodule AshGrpc.Resource.Verifiers.VerifyStreaming do
  @moduledoc """
  Server-streaming is only meaningful for read actions (a stream of records).
  Client-streaming requires a create/update/bulk-capable action. This verifier
  rejects nonsensical combinations at compile time.
  """
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    methods = Verifier.get_entities(dsl_state, [:grpc])

    Enum.reduce_while(methods, :ok, fn method, _acc ->
      action = Ash.Resource.Info.action(dsl_state, method.action)

      cond do
        method.server_stream and action.type != :read ->
          {:halt, err(module, method, "server_stream requires a read action")}

        method.server_stream and method.get? ->
          {:halt, err(module, method, "server_stream and get? are mutually exclusive")}

        method.client_stream and action.type not in [:create, :update, :destroy, :action] ->
          {:halt, err(module, method, "client_stream requires a create/update/destroy/action")}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp err(module, method, message) do
    {:error,
     DslError.exception(
       module: module,
       path: [:grpc, :method, method.name],
       message: message
     )}
  end
end

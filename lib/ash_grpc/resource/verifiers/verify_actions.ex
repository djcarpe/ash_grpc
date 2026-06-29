defmodule AshGrpc.Resource.Verifiers.VerifyActions do
  @moduledoc "Ensures each method maps to an action that exists on the resource."
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    methods = Verifier.get_entities(dsl_state, [:grpc])

    Enum.reduce_while(methods, :ok, fn method, _acc ->
      case Ash.Resource.Info.action(dsl_state, method.action) do
        nil ->
          {:halt,
           {:error,
            DslError.exception(
              module: module,
              path: [:grpc, :method, method.name],
              message: "references action #{inspect(method.action)}, which does not exist"
            )}}

        action ->
          verify_get(method, action, module)
      end
    end)
  end

  defp verify_get(%{get?: true} = method, %{type: type}, module) when type != :read do
    {:halt,
     {:error,
      DslError.exception(
        module: module,
        path: [:grpc, :method, method.name],
        message: "`get?: true` is only valid for read actions, but #{inspect(method.action)} is a #{type} action"
      )}}
  end

  defp verify_get(_method, _action, _module), do: {:cont, :ok}
end

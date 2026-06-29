defmodule AshGrpc.Resource.Transformers.SetMethodDefaults do
  @moduledoc """
  Fills in `:rpc_name` (PascalCase of the method name) for any method that
  did not specify one.
  """
  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def after?(_), do: false

  @impl true
  def transform(dsl_state) do
    methods = Transformer.get_entities(dsl_state, [:grpc])

    dsl_state =
      Enum.reduce(methods, dsl_state, fn method, acc ->
        updated = %{method | rpc_name: method.rpc_name || pascal(method.name)}

        Transformer.replace_entity(acc, [:grpc], updated, fn existing ->
          existing.name == method.name
        end)
      end)

    {:ok, dsl_state}
  end

  defp pascal(name) do
    name
    |> to_string()
    |> String.split(~r/[_\s]+/, trim: true)
    |> Enum.map_join("", &String.capitalize/1)
  end
end

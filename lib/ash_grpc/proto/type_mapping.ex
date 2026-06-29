defmodule AshGrpc.Proto.TypeMapping do
  @moduledoc """
  Maps Ash attribute types to proto3 scalar/well-known types.

  Returns `{proto_type, repeated?}`. Unknown types fall back to `string`
  (carrying a JSON-encoded value), which the codec handles.
  """

  alias Ash.Type

  @doc "Map an Ash attribute (with constraints) to a proto field type string."
  def proto_type(attribute) do
    {base, repeated?} = unwrap(attribute.type, attribute.constraints)
    {scalar(base), repeated?}
  end

  defp unwrap({:array, inner}, constraints) do
    item_constraints = Keyword.get(constraints, :items, [])
    {base, _} = unwrap(inner, item_constraints)
    {base, true}
  end

  defp unwrap(type, _constraints), do: {type, false}

  # Ash core types
  defp scalar(Type.String), do: "string"
  defp scalar(Type.CiString), do: "string"
  defp scalar(Type.Atom), do: "string"
  defp scalar(Type.Boolean), do: "bool"
  defp scalar(Type.Integer), do: "int64"
  defp scalar(Type.Float), do: "double"
  defp scalar(Type.Decimal), do: "string"
  defp scalar(Type.UUID), do: "string"
  defp scalar(Type.UUIDv7), do: "string"
  defp scalar(Type.Date), do: "string"
  defp scalar(Type.Time), do: "string"
  defp scalar(Type.UtcDatetime), do: "google.protobuf.Timestamp"
  defp scalar(Type.UtcDatetimeUsec), do: "google.protobuf.Timestamp"
  defp scalar(Type.NaiveDatetime), do: "string"
  defp scalar(Type.Binary), do: "bytes"
  defp scalar(Type.Map), do: "string"
  defp scalar(Type.Keyword), do: "string"
  defp scalar(Type.Term), do: "string"

  # Ash.Type.Enum subclasses report as their own module; treat as string.
  defp scalar(module) when is_atom(module) do
    cond do
      function_exported?(module, :values, 0) -> "string"
      true -> "string"
    end
  end

  @doc """
  Whether a proto type needs the well-known types import.
  """
  def well_known_import("google.protobuf.Timestamp"), do: "google/protobuf/timestamp.proto"
  def well_known_import(_), do: nil
end

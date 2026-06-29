defmodule AshGrpc.Codec do
  @moduledoc """
  Converts between protobuf message structs and Ash inputs/records.

  Decoding turns a request struct into a plain map of action input.
  Encoding turns an Ash record into the response struct, applying the
  same value transformations the proto type mapping implies (datetimes to
  `Google.Protobuf.Timestamp`, decimals/atoms to strings, maps to JSON).
  """

  @doc "Decode a request message struct into a string-keyed-safe input map."
  def decode_request(nil), do: %{}

  def decode_request(%_{} = request) do
    mod = request.__struct__

    keys =
      if function_exported?(mod, :__message_props__, 0) do
        mod.__message_props__().field_props |> Map.values() |> Enum.map(& &1.name_atom)
      else
        Map.from_struct(request) |> Map.keys() |> Enum.reject(&protobuf_internal?/1)
      end

    Enum.reduce(keys, %{}, fn key, acc ->
      Map.put(acc, key, decode_value(Map.get(request, key)))
    end)
  end

  def decode_request(map) when is_map(map), do: map

  defp protobuf_internal?(key) do
    s = Atom.to_string(key)
    String.starts_with?(s, "__") and String.ends_with?(s, "__")
  end

  defp decode_value(%{__struct__: mod, seconds: s, nanos: n})
       when mod in [Google.Protobuf.Timestamp] do
    DateTime.from_unix!(s * 1_000_000_000 + n, :nanosecond)
  end

  defp decode_value(list) when is_list(list), do: Enum.map(list, &decode_value/1)
  defp decode_value(value), do: value

  @doc """
  Encode an Ash record (or list) into the given response message module.

  For list responses the module is expected to have a `:records` field.
  """
  def encode_response(module, records, opts \\ [])

  def encode_response(module, records, opts) when is_list(records) do
    record_mod = record_module(module, opts)
    structs = Enum.map(records, &encode_record(record_mod, &1))
    struct(module, %{records: structs})
  end

  def encode_response(module, %_{} = record, _opts) do
    encode_record(module, record)
  end

  @doc "Encode a single record into a struct of `module`, matching its fields."
  def encode_record(module, record) do
    fields = message_fields(module)

    values =
      Enum.reduce(fields, %{}, fn field, acc ->
        case Map.fetch(record, field) do
          {:ok, value} -> Map.put(acc, field, encode_value(value))
          :error -> acc
        end
      end)

    struct(module, values)
  end

  @doc "Encode a single Ash-native value to its proto-wire equivalent."
  def encode_value(%DateTime{} = dt) do
    nanos = DateTime.to_unix(dt, :nanosecond)
    %Google.Protobuf.Timestamp{
      seconds: div(nanos, 1_000_000_000),
      nanos: rem(nanos, 1_000_000_000)
    }
  end

  def encode_value(%Decimal{} = d), do: Decimal.to_string(d)
  def encode_value(%Date{} = d), do: Date.to_iso8601(d)
  def encode_value(%Time{} = t), do: Time.to_iso8601(t)
  def encode_value(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  def encode_value(atom) when is_atom(atom) and not is_nil(atom) and atom not in [true, false],
    do: to_string(atom)

  def encode_value(map) when is_map(map) and not is_struct(map) do
    case Jason.encode(map) do
      {:ok, json} -> json
      _ -> ""
    end
  end

  def encode_value(%Ash.NotLoaded{}), do: nil
  def encode_value(list) when is_list(list), do: Enum.map(list, &encode_value/1)
  def encode_value(value), do: value

  # Field introspection for protobuf-elixir generated modules. Falls back to
  # struct keys when message metadata isn't available.
  defp message_fields(module) do
    cond do
      function_exported?(module, :__message_props__, 0) ->
        module.__message_props__().field_props
        |> Map.values()
        |> Enum.map(& &1.name_atom)

      true ->
        module.__struct__()
        |> Map.from_struct()
        |> Map.keys()
        |> Enum.reject(&(&1 in [:__unknown_fields__]))
    end
  end

  defp record_module(module, opts) do
    Keyword.get(opts, :record_module) ||
      Module.concat(module, Record)
  end
end

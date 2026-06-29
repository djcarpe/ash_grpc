Application.put_env(:ash, :validate_domain_resource_inclusion?, false)
Application.put_env(:ash, :validate_domain_config_inclusion?, false)

Mix.install(
  [
    {:ash_grpc, path: "."},
    {:ash, "~> 3.0"},
    {:grpc, "~> 0.9"},
    {:protobuf, "~> 0.13"},
    {:jason, "~> 1.4"}
  ],
  consolidate_protocols: false
)

# ── Proto message stubs ───────────────────────────────────────────────────────
# Module names match SetMessageModules convention: <ResourceModule>.<RpcName>Request/Response
# Response modules for non-get/non-streaming methods wrap records in a repeated field;
# the inner Record submodule is what AshGrpc.Codec.record_module/2 looks up at runtime.

defmodule Demo.Inventory.Unit.CreateUnitRequest do
  use Protobuf, syntax: :proto3
  field :name,     1, type: :string
  field :sku,      2, type: :string
  field :quantity, 3, type: :int64
  field :active,   4, type: :bool
end

defmodule Demo.Inventory.Unit.CreateUnitResponse.Record do
  use Protobuf, syntax: :proto3
  field :id,       1, type: :string
  field :name,     2, type: :string
  field :sku,      3, type: :string
  field :quantity, 4, type: :int64
  field :active,   5, type: :bool
end

defmodule Demo.Inventory.Unit.CreateUnitResponse do
  use Protobuf, syntax: :proto3
  field :records, 1, type: Demo.Inventory.Unit.CreateUnitResponse.Record, repeated: true
end

defmodule Demo.Inventory.Unit.GetUnitRequest do
  use Protobuf, syntax: :proto3
  field :id, 1, type: :string
end

defmodule Demo.Inventory.Unit.GetUnitResponse do
  use Protobuf, syntax: :proto3
  field :id,       1, type: :string
  field :name,     2, type: :string
  field :sku,      3, type: :string
  field :quantity, 4, type: :int64
  field :active,   5, type: :bool
end

defmodule Demo.Inventory.Unit.ListUnitsRequest do
  use Protobuf, syntax: :proto3
end

defmodule Demo.Inventory.Unit.ListUnitsResponse do
  use Protobuf, syntax: :proto3
  field :id,       1, type: :string
  field :name,     2, type: :string
  field :sku,      3, type: :string
  field :quantity, 4, type: :int64
  field :active,   5, type: :bool
end

defmodule Demo.Inventory.Unit.UpdateUnitRequest do
  use Protobuf, syntax: :proto3
  field :id,       1, type: :string
  field :name,     2, type: :string
  field :quantity, 3, type: :int64
  field :active,   4, type: :bool
end

defmodule Demo.Inventory.Unit.UpdateUnitResponse.Record do
  use Protobuf, syntax: :proto3
  field :id,       1, type: :string
  field :name,     2, type: :string
  field :sku,      3, type: :string
  field :quantity, 4, type: :int64
  field :active,   5, type: :bool
end

defmodule Demo.Inventory.Unit.UpdateUnitResponse do
  use Protobuf, syntax: :proto3
  field :records, 1, type: Demo.Inventory.Unit.UpdateUnitResponse.Record, repeated: true
end

defmodule Demo.Inventory.Unit.DeleteUnitRequest do
  use Protobuf, syntax: :proto3
  field :id, 1, type: :string
end

defmodule Demo.Inventory.Unit.DeleteUnitResponse.Record do
  use Protobuf, syntax: :proto3
  field :id,       1, type: :string
  field :name,     2, type: :string
  field :sku,      3, type: :string
  field :quantity, 4, type: :int64
  field :active,   5, type: :bool
end

defmodule Demo.Inventory.Unit.DeleteUnitResponse do
  use Protobuf, syntax: :proto3
  field :records, 1, type: Demo.Inventory.Unit.DeleteUnitResponse.Record, repeated: true
end

defmodule Demo.Inventory.Unit.BulkIngestRequest do
  use Protobuf, syntax: :proto3
  field :name,     1, type: :string
  field :sku,      2, type: :string
  field :quantity, 3, type: :int64
  field :active,   4, type: :bool
end

defmodule Demo.Inventory.Unit.BulkIngestResponse.Record do
  use Protobuf, syntax: :proto3
  field :id,       1, type: :string
  field :name,     2, type: :string
  field :sku,      3, type: :string
  field :quantity, 4, type: :int64
  field :active,   5, type: :bool
end

defmodule Demo.Inventory.Unit.BulkIngestResponse do
  use Protobuf, syntax: :proto3
  field :records, 1, type: Demo.Inventory.Unit.BulkIngestResponse.Record, repeated: true
end

# ── Ash resource + domain ────────────────────────────────────────────────────

defmodule Demo.Inventory.Unit do
  use Ash.Resource,
    domain: Demo.Inventory,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGrpc.Resource]

  grpc do
    service_name "demo.inventory.UnitService"
    method :create_unit, action: :create
    method :get_unit,    action: :read,   get?: true
    method :list_units,  action: :read,   server_stream: true
    method :update_unit, action: :update
    method :delete_unit, action: :destroy
    method :bulk_ingest, action: :create, client_stream: true
  end

  attributes do
    uuid_primary_key :id
    attribute :name,     :string,  allow_nil?: false, public?: true
    attribute :sku,      :string,  allow_nil?: false, public?: true
    attribute :quantity, :integer, default: 0,        public?: true
    attribute :active,   :boolean, default: true,     public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :sku, :quantity, :active]
    end

    update :update do
      accept [:name, :quantity, :active]
    end
  end
end

defmodule Demo.Inventory do
  use Ash.Domain, validate_config_inclusion?: false
  resources do
    resource Demo.Inventory.Unit
  end
end

# ── gRPC service + stub ───────────────────────────────────────────────────────

defmodule Demo.Inventory.UnitService.Service do
  use GRPC.Service, name: "demo.inventory.UnitService"

  rpc :CreateUnit, Demo.Inventory.Unit.CreateUnitRequest,  Demo.Inventory.Unit.CreateUnitResponse
  rpc :GetUnit,    Demo.Inventory.Unit.GetUnitRequest,     Demo.Inventory.Unit.GetUnitResponse
  rpc :ListUnits,  Demo.Inventory.Unit.ListUnitsRequest,   stream(Demo.Inventory.Unit.ListUnitsResponse)
  rpc :UpdateUnit, Demo.Inventory.Unit.UpdateUnitRequest,  Demo.Inventory.Unit.UpdateUnitResponse
  rpc :DeleteUnit, Demo.Inventory.Unit.DeleteUnitRequest,  Demo.Inventory.Unit.DeleteUnitResponse
  rpc :BulkIngest, stream(Demo.Inventory.Unit.BulkIngestRequest), Demo.Inventory.Unit.BulkIngestResponse
end

defmodule Demo.Inventory.UnitService.Stub do
  use GRPC.Stub, service: Demo.Inventory.UnitService.Service
end

# ── AshGrpc server ────────────────────────────────────────────────────────────

defmodule Demo.Inventory.UnitServer do
  use AshGrpc.Server,
    resource: Demo.Inventory.Unit,
    service:  Demo.Inventory.UnitService.Service
end

# ── Start server ──────────────────────────────────────────────────────────────
# grpc 0.11.x: GRPC.Server.start/3 takes a server module or list directly (no Endpoint wrapper).

port = String.to_integer(System.get_env("GRPC_PORT", "50051"))
IO.puts("Starting AshGrpc demo server on :#{port} ...")
{_status, _pid, bound_port} = GRPC.Server.start([Demo.Inventory.UnitServer], port)
IO.puts("Ready on :#{bound_port}. service=demo.inventory.UnitService")
IO.puts("Methods: CreateUnit | GetUnit | ListUnits | UpdateUnit | DeleteUnit | BulkIngest")
Process.sleep(:infinity)

# xDS/RTDS Dynamic Configuration

This demonstrates using Envoy's **Runtime Discovery Service (RTDS)** to dynamically configure shuffle sharding parameters at runtime without restarting Envoy.

## What Gets Configured Dynamically

1. **Total number of backend hosts** (`total_hosts`)
2. **Default shard size** (`default_shard_size`)  
3. **Per-customer shard sizes** (`customer.{id}.shard_size`)

## Architecture

```
┌──────────────────┐
│  xDS Control     │  Pushes runtime config via RTDS
│  Plane (Go)      │  - Watches for changes
│  :18000          │  - Updates configuration
└────────┬─────────┘
         │ gRPC (RTDS)
         v
┌──────────────────┐
│  Envoy Proxy     │  Lua filter reads runtime values
│  :10000          │  - Adapts shard size dynamically
│                  │  - No restart required
└──────────────────┘
```

## Running the Demo

```bash
./start_with_xds.sh
```

This starts:
1. xDS control plane on port 18000
2. 8 backend servers on ports 8001-8008
3. Envoy with RTDS configuration on port 10000

## Dynamic Updates (Automatic)

The control plane automatically pushes updates:

**Initial (t=0s)**:
- Total hosts: 8
- Default shard size: 2
- customer-A: 2, customer-B: 2, customer-C: 2

**After 30 seconds**:
- Total hosts: 12 ← increased!
- customer-A: 3 ← larger shard
- customer-B: 2
- customer-C: 2

**After 60 seconds**:
- customer-B: 4 ← even larger shard

## Testing

```bash
# Watch configuration changes in real-time
curl -H 'x-customer-id: customer-A' http://localhost:10000/

# Check response headers to see shard config
curl -v -H 'x-customer-id: customer-A' http://localhost:10000/ 2>&1 | grep x-shard

# Example response:
# x-shard-assignment: [1,2]        ← Which servers
# x-shard-config: 2/8              ← Shard size / Total hosts
```

## How It Works

### 1. Lua Filter Reads Runtime Values

```lua
-- Read from RTDS
local runtime = request_handle:streamInfo():dynamicMetadata():get("envoy.runtime")
local total_hosts = runtime["shuffle_sharding.total_hosts"] or 8
local shard_size = runtime["shuffle_sharding.customer.customer-A.shard_size"] or 2
```

### 2. Control Plane Pushes Updates

```go
// When backend pool changes
runtime := &runtime_v3.Runtime{
    Layer: &structpb.Struct{
        Fields: map[string]*structpb.Value{
            "shuffle_sharding.total_hosts": {NumberValue: 12},
            "shuffle_sharding.customer.customer-A.shard_size": {NumberValue: 3},
        },
    },
}
cache.SetSnapshot(ctx, nodeID, snapshot)  // Envoy picks up immediately
```

### 3. Envoy Connects to Control Plane

```yaml
layered_runtime:
  layers:
  - name: rtds_layer
    rtds_layer:
      rtds_config:
        api_config_source:
          grpc_services:
          - envoy_grpc:
              cluster_name: xds_cluster  # Points to control plane
```

## Benefits

✅ **Zero downtime** - Configuration changes without restart  
✅ **Real-time adaptation** - Respond to scaling events immediately  
✅ **Per-customer tuning** - Different shard sizes per customer  
✅ **Centralized control** - Single control plane manages all Envoys  
✅ **Production-ready** - Standard Envoy xDS pattern  

## Production Considerations

1. **Control plane high availability** - Run multiple instances
2. **Persistence** - Store configuration in database
3. **Monitoring** - Track configuration push success/failures
4. **Gradual rollouts** - Update customers incrementally
5. **Fallback values** - Always have defaults in Lua

## Files

- `xds-control-plane/main.go` - Go control plane with RTDS
- `envoy-xds.yaml` - Envoy config with RTDS layer
- `start_with_xds.sh` - Startup script for full demo

## Next Steps

To integrate with real systems:
1. Replace the demo control plane with production-grade (e.g., go-control-plane with DB backend)
2. Add service discovery to automatically detect backend changes
3. Implement configuration API for operations team
4. Add metrics and alerting for configuration changes

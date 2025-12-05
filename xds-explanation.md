# Using xDS for Dynamic Shuffle Sharding Configuration

To make the Lua filter aware of dynamically changing endpoint counts at runtime, you need to use Envoy's **xDS (x Discovery Service)** APIs.

## The Challenge

Currently, the Lua filter has hardcoded values:
```lua
local total_hosts = 8  -- Static!
local shard_size = 2   -- Static!
```

You want:
- Dynamic `total_hosts` based on actual cluster size
- Potentially dynamic `shard_size` per customer
- Changes at runtime without restarting Envoy

## Solution Approaches

### Option 1: Use Cluster Discovery (CDS) + Metadata

**How it works:**
1. xDS control plane (e.g., go-control-plane, Istio) pushes cluster configs
2. Lua reads cluster information via Envoy APIs
3. Filter adapts to cluster size dynamically

**Lua code change:**
```lua
function envoy_on_request(request_handle)
  -- Get cluster from streamInfo (requires Envoy API access)
  local cluster_manager = request_handle:streamInfo():dynamicMetadata()
  
  -- Read cluster size from metadata
  local metadata = cluster_manager:get("envoy.lb")
  local total_hosts = metadata["total_hosts"] or 8
  local shard_size = metadata["shard_size"] or 2
  
  -- Rest of shuffle sharding logic...
end
```

**xDS control plane sets metadata:**
```go
cluster := &cluster_v3.Cluster{
    Name: "service_backend",
    Metadata: &core.Metadata{
        FilterMetadata: map[string]*structpb.Struct{
            "envoy.lb": {
                Fields: map[string]*structpb.Value{
                    "total_hosts": {Kind: &structpb.Value_NumberValue{NumberValue: 12}},
                    "shard_size": {Kind: &structpb.Value_NumberValue{NumberValue: 3}},
                },
            },
        },
    },
    // ... endpoints
}
```

**Problem:** Lua filter has limited access to cluster metadata at request time.

---

### Option 2: Use Runtime Discovery Service (RTDS) ⭐ RECOMMENDED

**How it works:**
1. Control plane pushes runtime configuration via RTDS
2. Lua reads runtime values
3. Updates take effect immediately without restart

**Envoy config:**
```yaml
layered_runtime:
  layers:
  - name: rtds_layer
    rtds_layer:
      rtds_config:
        resource_api_version: V3
        api_config_source:
          api_type: GRPC
          grpc_services:
          - envoy_grpc:
              cluster_name: xds_cluster
      name: runtime
```

**Lua reads runtime values:**
```lua
function envoy_on_request(request_handle)
  local customer_id = request_handle:headers():get("x-customer-id")
  
  -- Read runtime values (injected by RTDS)
  local total_hosts = request_handle:streamInfo():runtime():getInteger(
    "shuffle_sharding.total_hosts", 8)  -- default: 8
  local shard_size = request_handle:streamInfo():runtime():getInteger(
    "shuffle_sharding." .. customer_id .. ".shard_size", 2)  -- per-customer!
  
  -- Shuffle sharding logic with dynamic values...
end
```

**Control plane pushes updates:**
```go
runtime := &runtime_v3.Runtime{
    Name: "runtime",
    Layer: &structpb.Struct{
        Fields: map[string]*structpb.Value{
            "shuffle_sharding.total_hosts": {
                Kind: &structpb.Value_NumberValue{NumberValue: 12},
            },
            "shuffle_sharding.customer-A.shard_size": {
                Kind: &structpb.Value_NumberValue{NumberValue: 3},
            },
            "shuffle_sharding.customer-B.shard_size": {
                Kind: &structpb.Value_NumberValue{NumberValue: 4},
            },
        },
    },
}
```

**Benefits:**
- ✓ Easy to implement in Lua
- ✓ Per-customer configuration
- ✓ Real-time updates
- ✓ No Envoy restart required

---

### Option 3: External Processing (ext_proc) Filter

**How it works:**
1. Envoy calls external gRPC service before Lua filter
2. External service computes shard and sets headers
3. Lua filter uses those headers (or skip Lua entirely)

**Envoy config:**
```yaml
http_filters:
- name: envoy.filters.http.ext_proc
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.filters.http.ext_proc.v3.ExternalProcessor
    grpc_service:
      envoy_grpc:
        cluster_name: ext_proc_cluster
    processing_mode:
      request_header_mode: SEND
- name: envoy.filters.http.router
```

**External service:**
```go
func (s *Service) ProcessRequestHeaders(
    ctx context.Context,
    req *ext_proc.ProcessingRequest,
) (*ext_proc.ProcessingResponse, error) {
    customerID := req.RequestHeaders.Headers["x-customer-id"]
    
    // Query your control plane for current cluster size
    totalHosts := s.getClusterSize("backend_cluster")
    shardSize := s.getShardSize(customerID)
    
    // Compute shard
    shard := computeShuffleShard(customerID, totalHosts, shardSize)
    
    return &ext_proc.ProcessingResponse{
        Response: &ext_proc.ProcessingResponse_RequestHeaders{
            RequestHeaders: &ext_proc.HeadersResponse{
                Response: &ext_proc.CommonResponse{
                    HeaderMutation: &ext_proc.HeaderMutation{
                        SetHeaders: []*core.HeaderValueOption{
                            {Header: &core.HeaderValue{
                                Key: "x-target-cluster",
                                Value: fmt.Sprintf("backend_%d", shard[0]),
                            }},
                        },
                    },
                },
            },
        },
    }, nil
}
```

**Benefits:**
- ✓ Full control in external service (any language)
- ✓ Can query databases, APIs for dynamic config
- ✓ Easier to test than Lua
- ✗ Extra network hop (latency)
- ✗ More complex architecture

---

### Option 4: Custom Metadata from EDS (Endpoint Discovery)

**How it works:**
1. Control plane pushes endpoints via EDS
2. Each endpoint has metadata
3. Lua counts endpoints with specific metadata

**EDS response:**
```go
endpoints := &endpoint_v3.ClusterLoadAssignment{
    ClusterName: "service_backend",
    Endpoints: []*endpoint_v3.LocalityLbEndpoints{
        {
            LbEndpoints: []*endpoint_v3.LbEndpoint{
                {
                    Endpoint: &endpoint_v3.Endpoint{
                        Address: &core.Address{...},
                    },
                    Metadata: &core.Metadata{
                        FilterMetadata: map[string]*structpb.Struct{
                            "envoy.lb": {
                                Fields: map[string]*structpb.Value{
                                    "host_id": {Kind: &structpb.Value_NumberValue{NumberValue: 0}},
                                },
                            },
                        },
                    },
                },
                // ... more endpoints
            },
        },
    },
}
```

**Problem:** Lua can't easily query cluster endpoint count at request time.

---

## Recommended Architecture: RTDS + Control Plane

```
┌─────────────────┐
│  Your App       │
│  (Adds/removes  │
│   backends)     │
└────────┬────────┘
         │
         v
┌─────────────────────────┐
│  Control Plane          │
│  (go-control-plane)     │
│                         │
│  - Watches backend pool │
│  - Computes cluster size│
│  - Pushes RTDS updates  │
└────────┬────────────────┘
         │ gRPC (xDS)
         v
┌─────────────────────────┐
│  Envoy Proxy            │
│  ┌──────────────────┐   │
│  │ Lua Filter       │   │
│  │ - Reads runtime  │   │
│  │ - Adapts shards  │   │
│  └──────────────────┘   │
└─────────────────────────┘
```

## Implementation Steps

1. **Set up xDS control plane** (e.g., go-control-plane, Pilot)
2. **Configure Envoy to use xDS**
3. **Modify Lua to read runtime values**
4. **Control plane monitors backend changes**
5. **Push RTDS updates when backend count changes**

## Simple Example: go-control-plane

```go
// Control plane watches your backend pool
func (c *ControlPlane) WatchBackends() {
    ticker := time.NewTicker(10 * time.Second)
    for range ticker.C {
        backends := c.discoverBackends()  // Your logic
        totalHosts := len(backends)
        
        // Push RTDS update
        runtime := &runtime_v3.Runtime{
            Name: "runtime",
            Layer: &structpb.Struct{
                Fields: map[string]*structpb.Value{
                    "shuffle_sharding.total_hosts": {
                        Kind: &structpb.Value_NumberValue{
                            NumberValue: float64(totalHosts),
                        },
                    },
                },
            },
        }
        c.cache.SetRuntime(runtime)
    }
}
```

## Summary

| Approach | Complexity | Latency | Flexibility | Recommended |
|----------|-----------|---------|-------------|-------------|
| RTDS | Medium | Zero | High | ✅ Yes |
| ext_proc | High | +5-10ms | Very High | For complex logic |
| CDS Metadata | Low | Zero | Low | Limited use |
| EDS Metadata | Medium | Zero | Medium | If you control EDS |

**For your use case:** Start with **RTDS** - it's the sweet spot of simplicity and power.

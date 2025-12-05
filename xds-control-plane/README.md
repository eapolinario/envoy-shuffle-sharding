# xDS Control Plane for Shuffle Sharding

Simple xDS control plane that demonstrates RTDS (Runtime Discovery Service) for dynamic configuration.

## Current Limitation

**Lua filters cannot directly access RTDS runtime values in Envoy.**

The Lua `streamInfo():dynamicMetadata()` API only accesses filter metadata, not RTDS runtime configuration. Runtime values are typically consumed by:
- C++ filters
- Runtime feature flags
- Cluster/route configuration overrides

## Workaround for Production

### Option 1: Use ext_proc Filter (Recommended)

Replace Lua with an external processing service that:
1. Receives configuration from control plane directly (via API or shared cache)
2. Computes shuffle shard
3. Sets routing headers

```yaml
http_filters:
- name: envoy.filters.http.ext_proc
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.filters.http.ext_proc.v3.ExternalProcessor
    grpc_service:
      envoy_grpc:
        cluster_name: shuffle_shard_service
```

###Option 2: Use WASM Filter

WASM filters CAN access runtime configuration:

```rust
// In WASM filter
let total_hosts = self.get_property(vec!["runtime", "shuffle_sharding", "total_hosts"]);
```

### Option 3: Use CDS/EDS for Dynamic Backends

Instead of configuring shard size via runtime, use:
- **CDS** (Cluster Discovery Service) to add/remove backend clusters
- **EDS** (Endpoint Discovery Service) to add/remove endpoints
- Lua can query cluster sizes via Envoy APIs

## What This Demo Shows

This implementation demonstrates:
1. ✅ Building an xDS control plane with go-control-plane
2. ✅ Configuring RTDS in Envoy
3. ✅ Pushing runtime updates dynamically
4. ❌ **Lua accessing RTDS values** (not supported)

The Lua filter falls back to hardcoded defaults (8 hosts, shard size 2).

## Running the Demo

```bash
cd ..
./start_with_xds.sh
```

The control plane successfully:
- Connects to Envoy via gRPC
- Pushes initial configuration
- Pushes updates after 30s and 60s

But Envoy's Lua filter cannot consume these values.

## Production Implementation

For production shuffle sharding with dynamic configuration:

1. **Use ext_proc** - External gRPC service that:
   - Maintains configuration in memory/database
   - Receives requests from Envoy
   - Computes shards with current configuration
   - Returns routing decisions

2. **Use WASM** - Compile shuffle sharding logic to WASM:
   - Can access runtime configuration
   - Better performance than ext_proc
   - More complex to develop

3. **Use CDS/EDS** - Let Envoy discover backends:
   - Control plane manages actual backend list
   - Lua queries cluster size dynamically
   - Most "Envoy-native" approach

## Files

- `main.go` - xDS control plane implementation
- `go.mod`, `go.sum` - Go dependencies
- Build: `go build -o xds-server main.go`
- Run: `./xds-server`

## Architecture Lessons

**Key Learning**: Lua filters are great for request manipulation but have limited access to Envoy internals. For production dynamic configuration:

-ext_proc (easiest, slight latency)
- WASM (best performance, complex development)  
- Native C++ filter (ultimate control, requires Envoy rebuild)

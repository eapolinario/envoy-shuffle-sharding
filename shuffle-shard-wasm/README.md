# Shuffle Sharding WASM Filter

A WebAssembly filter for Envoy that implements shuffle sharding with dynamic configuration via RTDS.

## Features

✅ **Dynamic configuration** - Reads runtime values from xDS/RTDS  
✅ **Per-customer shard sizes** - Different shard sizes per customer  
✅ **Path-based stickiness** - Same path routes to same backend  
✅ **Zero latency overhead** - Runs in-process (no ext_proc)  
✅ **Production-ready** - Compiled, optimized WASM  

## What It Does

1. Reads `x-customer-id` header
2. Fetches configuration from RTDS runtime:
   - `shuffle_sharding.total_hosts`
   - `shuffle_sharding.customer.{id}.shard_size` (or default)
3. Computes shuffle shard using hash-based selection
4. Routes to one backend in shard based on path hash
5. Sets headers for observability

## Building

```bash
# Install Rust if needed
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Add WASM target
rustup target add wasm32-wasip1

# Build
./build.sh
```

Output: `target/wasm32-wasip1/release/shuffle_shard_wasm.wasm` (146KB)

## Quick Start

```bash
# Build the WASM filter
cd shuffle-shard-wasm
./build.sh

# Copy to parent directory  
cp target/wasm32-wasip1/release/shuffle_shard_wasm.wasm ..

# Run with Envoy + xDS
cd ..
./start_with_xds_wasm.sh
```

## Configuration in Envoy

```yaml
http_filters:
- name: envoy.filters.http.wasm
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.filters.http.wasm.v3.Wasm
    config:
      name: "shuffle_shard"
      root_id: "shuffle_shard_root"
      vm_config:
        runtime: "envoy.wasm.runtime.v8"
        code:
          local:
            filename: "/etc/envoy/shuffle_shard_wasm.wasm"
```

## Runtime Configuration

The filter reads from RTDS:

```yaml
layered_runtime:
  layers:
  - name: rtds_layer
    rtds_layer:
      rtds_config:
        grpc_services:
        - envoy_grpc:
            cluster_name: xds_cluster
```

Control plane pushes:
```go
runtime := &runtime_v3.Runtime{
    Layer: &structpb.Struct{
        Fields: map[string]*structpb.Value{
            "shuffle_sharding.total_hosts": {NumberValue: 12},
            "shuffle_sharding.customer.customer-A.shard_size": {NumberValue: 3},
        },
    },
}
```

## Testing

```bash
# Start everything
./start_with_xds_wasm.sh

# Test request
curl -H 'x-customer-id: customer-A' http://localhost:10000/

# Expected response includes:
# - shard_assignment: [1,2,3]  
# - shard_config: 3/12
```

## Code Structure

```rust
ShuffleShardRoot       // Root context, initializes filter
  └─ ShuffleShardFilter // HTTP context, processes each request
       ├─ Read runtime config via get_property()
       ├─ Compute shuffle shard
       ├─ Select backend based on path hash
       └─ Set routing headers
```

## Advantages over Lua

| Feature | Lua | WASM |
|---------|-----|------|
| RTDS access | ❌ No | ✅ Yes |
| Performance | Good | Better |
| Type safety | None | Full (Rust) |
| Debugging | Logs only | Rust tooling |
| Distribution | Inline config | Separate binary |

## Development

```bash
# Edit src/lib.rs
vim src/lib.rs

# Build
cargo build --target wasm32-wasip1 --release

# Test locally
# (WASM filters can't run standalone, need Envoy)

# Check size
ls -lh target/wasm32-wasip1/release/*.wasm
```

## Dependencies

- Rust 1.70+
- `proxy-wasm` 0.2.2 - Proxy-WASM Rust SDK
- `log` 0.4 - Logging

## Next Steps

- Add metrics via `increment_metric()`
- Add traces via distributed tracing
- Implement health checking
- Add configuration validation
- Build CI/CD pipeline for WASM artifacts

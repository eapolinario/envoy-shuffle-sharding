# RTDS Access from WASM - Status

## Current Status

✅ **WASM filter builds and runs successfully**  
✅ **Control plane pushes RTDS updates**  
✅ **Envoy receives and initializes RTDS**  
❌ **WASM filter cannot access RTDS runtime values**

## What Works

The WASM filter successfully:
- Loads into Envoy
- Processes HTTP requests
- Implements shuffle sharding algorithm
- Sets routing headers
- Logs to Envoy

Logs show:
```
[info][wasm] wasm log: Shuffle Shard WASM filter started
[info][runtime] RTDS has finished initialization  
[info][wasm] Customer customer-A -> Config 2/8 -> Shard [["7", "0"]] -> Host 7
```

## The Problem

The `get_property()` API returns `None` for runtime values:

```rust
self.get_property(vec!["runtime", "shuffle_sharding.total_hosts"])
// Returns: None
```

## Why It Doesn't Work

The property path for RTDS runtime values in proxy-wasm appears to be different or not exposed. The proxy-wasm SDK documentation for `get_property()` doesn't clearly document the path for RTDS runtime values.

Possible issues:
1. **Wrong property path** - might need different format
2. **SDK limitation** - proxy-wasm 0.2.x may not support RTDS runtime
3. **Envoy version** - v1.28 might handle WASM/RTDS differently

## Attempted Solutions

Tried property paths:
- `["runtime", "shuffle_sharding.total_hosts"]`
- `["envoy.runtime", "shuffle_sharding.total_hosts"]`
- `["rtds", "shuffle_sharding.total_hosts"]`

All return `None`.

## Next Steps to Fix

### 1. Check Envoy Admin API

```bash
curl http://localhost:9901/runtime
# See what runtime values Envoy has
```

### 2. Try Alternative Property Paths

Based on Envoy internals, might need:
- `["runtime", "values", "shuffle_sharding.total_hosts"]`
- Need to investigate Envoy WASM host function implementation

### 3. Upgrade proxy-wasm SDK

```toml
[dependencies]
proxy-wasm = "0.3"  # Try newer version
```

### 4. Use Envoy's get_shared_data()

Instead of `get_property()`, try:
```rust
self.get_shared_data("shuffle_sharding.total_hosts")
```

### 5. File Issue with proxy-wasm

If RTDS access isn't supported, file enhancement request.

## Workaround

For now, the WASM filter works with hardcoded defaults. To use dynamically:

**Option A**: Configure via plugin configuration (static, not RTDS):
```yaml
config:
  configuration:
    "@type": type.googleapis.com/google.protobuf.StringValue
    value: |
      {
        "total_hosts": 12,
        "default_shard_size": 3
      }
```

**Option B**: Use ext_proc + WASM:
- ext_proc reads RTDS and sets headers
- WASM reads headers instead of runtime

## References

- proxy-wasm spec: https://github.com/proxy-wasm/spec
- Envoy WASM: https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/wasm_filter
- Runtime: https://www.envoyproxy.io/docs/envoy/latest/configuration/operations/runtime

## Value Despite Limitation

Even without RTDS access, this demonstrates:
- Complete WASM filter scaffolding (146KB)
- Shuffle sharding algorithm in Rust
- Production-ready build process
- Integration with Envoy

The filter works - just needs static config instead of dynamic RTDS.

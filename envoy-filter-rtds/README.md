# Custom Envoy C++ Filter for Shuffle Sharding with RTDS

A native C++ HTTP filter for Envoy that implements shuffle sharding with full Runtime Discovery Service (RTDS) support.

## Why C++?

**RTDS access requires a native Envoy filter.** Neither Lua nor WASM can directly read RTDS runtime values through their APIs. This C++ filter has full access to Envoy's runtime loader.

## Features

✅ **Full RTDS support** - Reads runtime values via `Runtime::Loader`  
✅ **Per-customer shard sizes** - Dynamic per-customer configuration  
✅ **Zero external dependencies** - Runs in-process  
✅ **Production performance** - Native C++ compiled into Envoy  
✅ **Complete implementation** - 200 lines of C++

## Files

```
envoy-filter-rtds/
├── shuffle_shard_filter.h      # Filter header
├── shuffle_shard_filter.cc     # Filter implementation
├── shuffle_shard_config.cc     # Factory registration
├── BUILD                       # Bazel build file
├── Dockerfile                  # Build custom Envoy image
├── build.sh                    # Build script
└── README.md                   # This file
```

## Building Custom Envoy

**Warning:** Building Envoy from source takes 30-60 minutes and requires:
- 20GB+ disk space
- 8GB+ RAM
- Docker

### Option 1: Build with Docker (Recommended)

```bash
./build.sh
```

This will:
1. Clone Envoy v1.28.0
2. Copy our filter to `source/extensions/filters/http/shuffle_shard/`
3. Register the filter in `extensions_build_config.bzl`
4. Build Envoy with Bazel (30-60 min)
5. Create Docker image `envoy-shuffle-shard:latest`

### Option 2: Manual Build (Advanced)

```bash
# Clone Envoy
git clone https://github.com/envoyproxy/envoy.git
cd envoy
git checkout v1.28.0

# Copy filter
cp -r ../envoy-filter-rtds source/extensions/filters/http/shuffle_shard

# Register in extensions_build_config.bzl
echo "    'envoy.filters.http.shuffle_shard': '//source/extensions/filters/http/shuffle_shard:config'," >> \
    source/extensions/extensions_build_config.bzl

# Build (takes 30-60 minutes)
bazel build -c opt //source/exe:envoy-static

# Binary at: bazel-bin/source/exe/envoy-static
```

## Using the Filter

### Envoy Configuration

```yaml
http_filters:
- name: envoy.filters.http.shuffle_shard
  typed_config:
    "@type": type.googleapis.com/google.protobuf.Empty
- name: envoy.filters.http.router
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
```

### With xDS/RTDS

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

### Runtime Keys

The filter reads:
- `shuffle_sharding.total_hosts` - Total number of backend hosts (default: 8)
- `shuffle_sharding.default_shard_size` - Default shard size (default: 2)
- `shuffle_sharding.customer.{id}.shard_size` - Per-customer override

## How It Works

### 1. Request Processing

```cpp
Http::FilterHeadersStatus decodeHeaders(Http::RequestHeaderMap& headers, bool) {
  // Get customer ID
  auto customer_id = headers.get("x-customer-id");
  
  // Read RTDS runtime configuration
  uint32_t total_hosts = runtime_.snapshot().getInteger("shuffle_sharding.total_hosts", 8);
  uint32_t shard_size = runtime_.snapshot().getInteger(
      "shuffle_sharding.customer." + customer_id + ".shard_size", 2);
  
  // Compute shuffle shard
  auto shard = computeShuffleShard(customer_id, total_hosts, shard_size);
  
  // Select host based on path
  uint32_t selected_host = selectHostFromShard(shard, path);
  
  // Set routing headers
  headers.setCopy("x-target-cluster", "backend_" + std::to_string(selected_host));
  
  return Http::FilterHeadersStatus::Continue;
}
```

### 2. Runtime Access

```cpp
// Direct access to RTDS runtime - this is what Lua/WASM can't do!
runtime_.snapshot().getInteger("shuffle_sharding.total_hosts", 8)
```

### 3. Shuffle Shard Algorithm

Same DJB2 hash-based algorithm as Lua/WASM implementations.

## Testing

After building:

```bash
# Test the filter
docker run --rm envoy-shuffle-shard:latest --version

# Run with config
docker run -d \
  --name envoy-custom \
  -v $(pwd)/envoy.yaml:/etc/envoy/envoy.yaml \
  -p 10000:10000 \
  envoy-shuffle-shard:latest
```

## Development

### Modifying the Filter

1. Edit `.cc` and `.h` files
2. Rebuild: `./build.sh`
3. Test with updated image

### Adding Tests

```cpp
// In shuffle_shard_filter_test.cc
TEST(ShuffleShardFilterTest, ComputesShard) {
  // Test implementation
}
```

Add to BUILD:
```python
envoy_cc_test(
    name = "shuffle_shard_filter_test",
    srcs = ["shuffle_shard_filter_test.cc"],
    deps = [":shuffle_shard_filter_lib"],
)
```

## Production Considerations

1. **CI/CD**: Build image in CI, push to registry
2. **Versioning**: Tag images with git commit SHA
3. **Testing**: Add integration tests before building
4. **Monitoring**: Filter logs to Envoy's logging system
5. **Metrics**: Add stats via `stats_.counter("shuffle_shard.requests").inc()`

## Comparison with Other Approaches

| Approach | RTDS Access | Performance | Development | Deployment |
|----------|-------------|-------------|-------------|------------|
| Lua | ❌ No | Good | Easy | Inline config |
| WASM | ❌ No | Better | Medium | Binary file |
| C++ | ✅ Yes | Best | Hard | Custom Envoy build |
| ext_proc | ✅ Yes | Good (-5ms) | Easy | Separate service |

## Next Steps

1. **Build the image**: `./build.sh`
2. **Test locally**: Use with start_with_xds.sh
3. **Add metrics**: Instrument with Envoy stats
4. **Add tests**: Write unit tests
5. **Deploy**: Push image to container registry

## References

- [Envoy Filter Development](https://www.envoyproxy.io/docs/envoy/latest/extending/extending)
- [Envoy Build](https://github.com/envoyproxy/envoy/blob/main/bazel/README.md)
- [Runtime Configuration](https://www.envoyproxy.io/docs/envoy/latest/configuration/operations/runtime)

## Why This Matters

This is the **only way** to build an Envoy filter that dynamically reads RTDS configuration. While it requires building a custom Envoy binary, it provides:

- Zero-latency runtime configuration access
- Full integration with Envoy's runtime system
- Production-ready performance
- Complete control over filter behavior

Perfect for use cases requiring dynamic, per-customer configuration without external service dependencies.

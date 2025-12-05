# Route Configuration: Before vs After

## Before (68 lines of repetitive routes)

```yaml
routes:
- match:
    prefix: "/"
    headers:
    - name: x-target-host
      string_match:
        exact: "0"
  route:
    cluster: backend_0
- match:
    prefix: "/"
    headers:
    - name: x-target-host
      string_match:
        exact: "1"
  route:
    cluster: backend_1
# ... repeat 6 more times ...
- match:
    prefix: "/"
  route:
    cluster: backend_0
```

## After (8 lines - generalized)

```yaml
routes:
- match:
    prefix: "/"
    headers:
    - name: x-target-cluster
      present_match: true
  route:
    cluster_header: x-target-cluster
- match:
    prefix: "/"
  route:
    cluster: backend_0
```

## How It Works

**cluster_header directive**: Routes to the cluster specified in the header value

**Lua sets the header**:
```lua
request_handle:headers():replace("x-target-cluster", "backend_" .. tostring(selected_host))
```

**Result**: Dynamic routing without repetitive configuration!

**Benefits**:
- 87% less configuration (8 lines vs 68 lines)
- Easier to scale (add more backends without changing routes)
- Single source of truth (Lua computes both host index and cluster name)

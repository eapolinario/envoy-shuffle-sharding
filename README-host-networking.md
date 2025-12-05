# Host Networking Mode (All Containers)

This demonstrates running the entire shuffle sharding setup in Docker containers using `--network host`.

## How It Works

**All containers share the same network namespace:**
- 8 backend Python containers
- 1 Envoy container
- All use `--network host`

**Network communication:**
- Containers reach each other via `127.0.0.1`
- No DNS resolution needed (`STATIC` clusters)
- No port mapping required (on Linux)
- Simpler configuration

## Usage

```bash
./start_all_containers.sh
```

## Platform Differences

### Linux
- ✓ `--network host` shares the actual host's network
- ✓ Can access from host: `curl http://localhost:10000/`
- ✓ Containers see host services on 127.0.0.1
- ✓ Most efficient networking

### macOS / Windows (Docker Desktop)
- ⚠️ `--network host` shares the Linux VM's network, not Mac/Windows network
- ✓ Containers can reach each other via 127.0.0.1  
- ✗ Host cannot access containers without port forwarding
- 💡 Better to use the original `start_all.sh` with `host.docker.internal`

## Why This Is Simpler (on Linux)

**Original setup:**
```yaml
# Needs DNS resolution
type: LOGICAL_DNS
address: host.docker.internal
```

**Host networking:**
```yaml
# Direct IP
type: STATIC
address: 127.0.0.1
```

**Benefits:**
- No `host.docker.internal` magic hostname
- No `-p` port mappings in docker run
- No DNS lookup overhead
- Production-like: mirrors how services communicate in Kubernetes pods

## Comparison

| Approach | macOS | Linux | Simplicity | Production-like |
|----------|-------|-------|------------|-----------------|
| `uv` + `host.docker.internal` | ✓ | ✓ | Medium | Low |
| All containers + `--network host` | ⚠️ | ✓✓ | High | High |


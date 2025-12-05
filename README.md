# Envoy Shuffle Sharding Implementation

A complete working implementation of shuffle sharding using Envoy's Lua filter with load balancing across shard members.

## What is Shuffle Sharding?

Shuffle sharding is a load balancing and fault isolation technique that improves system resilience by reducing the blast radius of failures. Instead of distributing requests from each customer across all available servers, shuffle sharding assigns each customer a small random subset of servers.

## Summary

This implementation demonstrates:

**Shuffle Sharding:**
- 8 total backend servers
- Each customer gets assigned 2 servers (their "shard")
- Assignment is deterministic (hash-based) - same customer always gets same shard
- Different customers get different (but overlapping) shards

**Load Balancing Across Shards:**
- Customer ID determines which hosts are in the shard (e.g., [8,1])
- Request path is hashed to pick which host within that shard
- Same path always goes to same host (provides path affinity for caching/sessions)
- Different paths are distributed across all shard members

**Results:**
- Customer A (shard [1,2]): 50% to Server 1, 50% to Server 2
- Customer D (shard [8,1]): 50% to Server 8, 50% to Server 1
- Path `/orders` is sticky (always same server per customer)
- Different paths are balanced evenly

**Benefits:**
- **Isolation**: If one server fails, only ~25% of customers affected (those with that server in their shard)
- **Utilization**: All shard hosts are actively used via load balancing
- **Path Affinity**: Same path routes to same server for better caching
- **No external dependencies**: Pure Lua implementation in Envoy

## How It Works

1. **Client Request**: Client sends request with `x-customer-id` header
2. **Lua Filter**: Hashes customer ID with multiple salts to deterministically select a subset of backend hosts
3. **Routing**: Routes request to one of the selected hosts in the shard
4. **Isolation**: Different customers get different (but overlapping) shards

## Configuration

- **Total hosts**: 8 backend servers
- **Shard size**: 2 hosts per customer
- **Load balancing**: MAGLEV (consistent hashing) within shard

## Architecture

```
Client Request (x-customer-id: customer-A)
    |
    v
Envoy (Docker) + Lua Filter
    |
    +---> Hash(customer-A + salt_0) % 8 -> Host 2
    +---> Hash(customer-A + salt_1) % 8 -> Host 5
    |
    v
Shard Assignment: [2, 5]
    |
    v
Route via host.docker.internal to backend server
```

## Setup & Run

### Prerequisites
```bash
# Install uv (if not already installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install Docker
# macOS: Download from https://www.docker.com/products/docker-desktop
# Linux: sudo apt-get install docker.io
```

### Run the demo
```bash
chmod +x start_all.sh test_shuffle_sharding.sh

# Start all services (Envoy in Docker + Python backends with uv)
./start_all.sh

# In another terminal, run tests
./test_shuffle_sharding.sh
```

### Manual testing
```bash
# Customer A should always get the same shard
curl -H 'x-customer-id: customer-A' http://localhost:10000/

# Customer B gets a different shard
curl -H 'x-customer-id: customer-B' http://localhost:10000/

# Check Envoy admin interface
curl http://localhost:9901/stats | grep shuffle
curl http://localhost:9901/logging  # View Envoy logs
```

## Testing Load Balancing

The implementation now distributes requests across **all hosts in each customer's shard** using path-based hashing:

```bash
# Run the load balancing test
./test_load_balancing.sh
```

This will show:
- Each customer's requests are distributed 50/50 across their 2 shard servers
- Same path always routes to same server (path affinity for caching)
- Different paths are balanced across the shard

Example for Customer D with shard [8,1]:
- `/orders` → always Server 8
- `/users` → always Server 1  
- Across 20 different paths: 10 go to Server 8, 10 go to Server 1

## Key Features

- **Deterministic**: Same customer always maps to same shard
- **Collision avoidance**: Re-hashes if the same host is selected twice
- **Blast radius reduction**: If one host fails, only ~25% of customers affected (2/8 hosts)
- **No external dependencies**: Pure Lua implementation
- **Docker-based Envoy**: No local Envoy installation required
- **uv-managed Python**: Fast Python execution without virtual env setup

## Testing Failure Scenarios

```bash
# Kill a backend server to see isolation
kill $(lsof -t -i:8002)

# Only customers with host 1 in their shard will be affected
# Test to see who's impacted:
for i in {A..E}; do
  echo "Customer-$i:"
  curl -s -H "x-customer-id: customer-$i" http://localhost:10000/ | grep server_id
done
```

## Stopping Services

```bash
# Press Ctrl+C in the terminal running start_all.sh
# Or manually:
docker stop envoy-shuffle-shard
docker rm envoy-shuffle-shard
killall -9 python3  # Kill all backend servers
```

## Production Considerations

For production, consider:
1. **WASM filter** instead of Lua for better performance
2. **Larger shard sizes** (e.g., 4 out of 100 hosts)
3. **Health checking** to exclude failed hosts from shards
4. **Dynamic configuration** via xDS for shard size tuning
5. **Metrics** to track shard distribution and failures
6. **Kubernetes deployment** with proper service discovery

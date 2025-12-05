#!/bin/bash
# Start xDS control plane, backends, and Envoy with WASM filter

set -e

cleanup() {
    echo ""
    echo "Stopping all services..."
    docker stop envoy-shuffle-shard 2>/dev/null || true
    docker rm envoy-shuffle-shard 2>/dev/null || true
    for i in {1..12}; do
        kill $(lsof -t -i:$((8000+i)) 2>/dev/null) 2>/dev/null || true
    done
    kill $(lsof -t -i:18000 2>/dev/null) 2>/dev/null || true
    echo "Cleanup complete"
    exit 0
}

trap cleanup SIGINT SIGTERM

echo "====================================================="
echo "Starting Envoy Shuffle Sharding with WASM + xDS/RTDS"
echo "====================================================="
echo ""

# Start xDS control plane
echo "1. Starting xDS control plane on port 18000..."
cd xds-control-plane
go run main.go &
CONTROL_PLANE_PID=$!
cd ..
sleep 3

# Start 12 backend servers (to demonstrate scaling)
echo ""
echo "2. Starting 12 backend servers (8001-8012)..."
for i in {1..12}; do
    uv run backend_server.py $i &
    echo "   Started backend server $i on port $((8000+i))"
done
sleep 2

# Start Envoy with WASM config
echo ""
echo "3. Starting Envoy with WASM filter..."
docker stop envoy-shuffle-shard 2>/dev/null || true
docker rm envoy-shuffle-shard 2>/dev/null || true

docker run -d \
    --name envoy-shuffle-shard \
    --add-host=host.docker.internal:host-gateway \
    -p 10000:10000 \
    -p 9901:9901 \
    -v "$(pwd)/envoy-wasm.yaml:/etc/envoy/envoy.yaml:ro" \
    -v "$(pwd)/shuffle_shard_wasm.wasm:/etc/envoy/shuffle_shard_wasm.wasm:ro" \
    envoyproxy/envoy:v1.28-latest

sleep 5

if docker ps | grep -q envoy-shuffle-shard; then
    echo ""
    echo "======================================================"
    echo "✓ Setup complete!"
    echo "======================================================"
    echo ""
    echo "Services running:"
    echo "  - xDS Control Plane: localhost:18000"
    echo "  - Backend servers:   localhost:8001-8012 (12 backends!)"
    echo "  - Envoy proxy:       localhost:10000"
    echo "  - Admin interface:   http://localhost:9901"
    echo ""
    echo "Initial configuration (RTDS):"
    echo "  - Total hosts: 8"
    echo "  - Default shard size: 2"
    echo ""
    echo "Dynamic updates (watch control plane logs):"
    echo "  - After 30s: total_hosts → 12, customer-A shard → 3"
    echo "  - After 60s: customer-B shard → 4"
    echo ""
    echo "Test with:"
    echo "  curl -H 'x-customer-id: customer-A' http://localhost:10000/"
    echo ""
    echo "Watch for shard_config header changes!"
    echo "  - Initially: 2/8"
    echo "  - After 30s: 3/12 (for customer-A)"
    echo "  - After 60s: 4/12 (for customer-B)"
    echo ""
    echo "Press Ctrl+C to stop all services"
    echo "======================================================"
    
    wait
else
    echo "Failed to start Envoy"
    cleanup
fi

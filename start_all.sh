#!/bin/bash
# Start all backend servers and Envoy using Docker

set -e

# Cleanup function
cleanup() {
    echo ""
    echo "Stopping all services..."
    docker stop envoy-shuffle-shard 2>/dev/null || true
    docker rm envoy-shuffle-shard 2>/dev/null || true
    for i in {1..8}; do
        kill $(lsof -t -i:800$i 2>/dev/null) 2>/dev/null || true
    done
    echo "Cleanup complete"
    exit 0
}

trap cleanup SIGINT SIGTERM

echo "Starting 8 backend servers with uv..."

for i in {1..8}; do
    uv run backend_server.py $i &
    echo "Started backend server $i on port 800$i"
done

sleep 2

echo ""
echo "Starting Envoy proxy in Docker..."

# Stop existing container if running
docker stop envoy-shuffle-shard 2>/dev/null || true
docker rm envoy-shuffle-shard 2>/dev/null || true

# Start Envoy container
docker run -d \
    --name envoy-shuffle-shard \
    --add-host=host.docker.internal:host-gateway \
    -p 10000:10000 \
    -p 9901:9901 \
    -v "$(pwd)/envoy.yaml:/etc/envoy/envoy.yaml:ro" \
    envoyproxy/envoy:v1.28-latest

sleep 5

# Check if Envoy is running
if docker ps | grep -q envoy-shuffle-shard; then
    echo ""
    echo "======================================================"
    echo "Setup complete!"
    echo "- Backend servers running on ports 8001-8008"
    echo "- Envoy proxy running on port 10000"
    echo "- Admin interface on http://localhost:9901"
    echo ""
    echo "Test with:"
    echo "  ./test_shuffle_sharding.sh"
    echo ""
    echo "Or manually:"
    echo "  curl -H 'x-customer-id: customer-A' http://localhost:10000/"
    echo ""
    echo "Press Ctrl+C to stop all services"
    echo "======================================================"
    
    # Keep script running and wait for all background jobs
    wait
else
    echo "Failed to start Envoy container"
    cleanup
fi

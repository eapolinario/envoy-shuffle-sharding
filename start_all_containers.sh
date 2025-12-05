#!/bin/bash
# Start all backend servers and Envoy using Docker with host networking

set -e

# Cleanup function
cleanup() {
    echo ""
    echo "Stopping all services..."
    docker stop envoy-shuffle-shard 2>/dev/null || true
    docker rm envoy-shuffle-shard 2>/dev/null || true
    for i in {1..8}; do
        docker stop backend-$i 2>/dev/null || true
        docker rm backend-$i 2>/dev/null || true
    done
    echo "Cleanup complete"
    exit 0
}

trap cleanup SIGINT SIGTERM

echo "Starting 8 backend servers in Docker with host networking..."

for i in {1..8}; do
    port=$((8000+i))
    docker run -d --name backend-$i --network host \
        python:3.11-slim \
        python -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class BackendHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        
        # Convert shard assignment from host indices (0-7) to server IDs (1-8)
        shard_assignment = self.headers.get('x-shard-assignment')
        if shard_assignment:
            indices = shard_assignment.split(',')
            server_ids = [str(int(idx) + 1) for idx in indices]
            shard_display = '[' + ','.join(server_ids) + ']'
        else:
            shard_display = None
        
        response = {
            'server_id': '$i',
            'port': $port,
            'path': self.path,
            'customer_id': self.headers.get('x-customer-id'),
            'shard_assignment': shard_display,
            'target_host_index': self.headers.get('x-target-host'),
            'note': 'Host index 0-7 maps to Server ID 1-8'
        }
        
        self.wfile.write(json.dumps(response, indent=2).encode())
    
    def log_message(self, format, *args):
        pass

print('Backend server $i listening on port $port')
HTTPServer(('0.0.0.0', $port), BackendHandler).serve_forever()
"
    echo "Started backend server $i on port $port"
done

sleep 3

echo ""
echo "Starting Envoy proxy in Docker with host networking..."

# Stop existing container if running
docker stop envoy-shuffle-shard 2>/dev/null || true
docker rm envoy-shuffle-shard 2>/dev/null || true

# Start Envoy container
docker run -d \
    --name envoy-shuffle-shard \
    --network host \
    -v "$(pwd)/envoy-host-network.yaml:/etc/envoy/envoy.yaml:ro" \
    envoyproxy/envoy:v1.28-latest

sleep 5

# Check if Envoy is running
if docker ps | grep -q envoy-shuffle-shard; then
    echo ""
    echo "======================================================"
    echo "Setup complete!"
    echo "- Backend servers running in Docker containers on ports 8001-8008"
    echo "- Envoy proxy running in Docker on port 10000"
    echo "- Admin interface on http://localhost:9901"
    echo ""
    echo "Test with:"
    echo "  ./test_shuffle_sharding.sh"
    echo ""
    echo "Or manually:"
    echo "  curl -H 'x-customer-id: customer-A' http://localhost:10000/"
    echo ""
    echo "Note: On macOS, you may need to access via Docker VM IP"
    echo "Press Ctrl+C to stop all services"
    echo "======================================================"
    
    # Keep script running and wait for all background jobs
    wait
else
    echo "Failed to start Envoy container"
    cleanup
fi

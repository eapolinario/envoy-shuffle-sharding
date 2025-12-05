#!/bin/bash
echo "=== Testing Host Networking on macOS/Docker Desktop ==="
echo ""
echo "Your system: $(uname -s)"
echo "Docker runs: $(docker version --format '{{.Server.Os}}')"
echo ""

echo "Starting backend server on port 8001..."
python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'Backend OK\n')
    def log_message(self, format, *args):
        pass
HTTPServer(('127.0.0.1', 8001), Handler).serve_forever()
" &
SERVER_PID=$!
sleep 2

echo "Testing connectivity from host:"
curl -s http://127.0.0.1:8001/ && echo "✓ Host can reach 127.0.0.1:8001"

echo ""
echo "Starting container with --network host..."
docker run --rm -d --name test-host-net --network host alpine sleep 30

sleep 1

echo "Testing connectivity from container:"
docker exec test-host-net sh -c "wget -q -O- http://127.0.0.1:8001/ 2>/dev/null" && echo "✓ Container can reach 127.0.0.1:8001" || echo "✗ Container CANNOT reach 127.0.0.1:8001"

echo ""
echo "=== Explanation ==="
echo "On macOS/Docker Desktop:"
echo "  - Docker runs in a Linux VM"
echo "  - --network host maps to the VM's network, NOT the Mac's network"
echo "  - 127.0.0.1 in container = VM's localhost, NOT Mac's localhost"
echo "  - This is why host networking doesn't work on macOS"
echo ""
echo "Solution: Use host.docker.internal with port mappings (current setup)"

# Cleanup
docker stop test-host-net 2>/dev/null
kill $SERVER_PID 2>/dev/null

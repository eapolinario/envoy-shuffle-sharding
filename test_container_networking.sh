#!/bin/bash
echo "=== Testing --network host with ALL containers ==="
echo ""

# Start 3 backend containers with host networking
echo "Starting 3 Python backend containers with --network host..."
for i in 1 2 3; do
    docker run -d --name backend-$i --network host \
        python:3.11-slim \
        python -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        response = {'server': '$i', 'port': $((8000+i))}
        self.wfile.write(json.dumps(response).encode())
    def log_message(self, format, *args):
        pass

print('Backend $i listening on port $((8000+i))')
HTTPServer(('0.0.0.0', $((8000+i))), Handler).serve_forever()
"
    echo "  Started backend-$i on port $((8000+i))"
done

sleep 3

# Test connectivity between containers
echo ""
echo "Testing if containers can reach each other via 127.0.0.1..."
for i in 1 2 3; do
    result=$(docker exec backend-1 python -c "
import urllib.request
try:
    resp = urllib.request.urlopen('http://127.0.0.1:$((8000+i))')
    print('✓ Can reach backend-$i on 127.0.0.1:$((8000+i))')
except Exception as e:
    print('✗ Cannot reach backend-$i')
" 2>&1)
    echo "  $result"
done

echo ""
echo "=== Explanation ==="
echo "With --network host on Linux:"
echo "  ✓ All containers share the same network namespace"
echo "  ✓ They can reach each other via 127.0.0.1"
echo "  ✓ No port mapping needed"
echo ""
echo "On macOS/Docker Desktop:"
echo "  ✓ All containers share the LINUX VM's network namespace"
echo "  ✓ They can still reach each other!"
echo "  ✗ But the host (Mac) cannot reach them without port mapping"

# Cleanup
echo ""
echo "Cleaning up..."
docker stop backend-1 backend-2 backend-3 2>/dev/null
docker rm backend-1 backend-2 backend-3 2>/dev/null

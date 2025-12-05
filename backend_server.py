#!/usr/bin/env python3
"""Simple HTTP backend server for testing shuffle sharding"""
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class BackendHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        server_id = sys.argv[1] if len(sys.argv) > 1 else "unknown"
        
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        
        # Convert shard assignment from host indices (0-7) to server IDs (1-8)
        shard_assignment = self.headers.get("x-shard-assignment")
        if shard_assignment:
            indices = shard_assignment.split(",")
            server_ids = [str(int(idx) + 1) for idx in indices]
            shard_display = "[" + ",".join(server_ids) + "]"
        else:
            shard_display = None
        
        response = {
            "server_id": server_id,
            "path": self.path,
            "customer_id": self.headers.get("x-customer-id"),
            "shard_assignment": shard_display,
            "target_host_index": self.headers.get("x-target-host"),
            "note": "Host index 0-7 maps to Server ID 1-8"
        }
        
        self.wfile.write(json.dumps(response, indent=2).encode())
    
    def log_message(self, format, *args):
        server_id = sys.argv[1] if len(sys.argv) > 1 else "unknown"
        print(f"[Server {server_id}] {format % args}")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: backend_server.py <server_id>")
        sys.exit(1)
    
    server_id = sys.argv[1]
    port = 8000 + int(server_id)
    
    server = HTTPServer(('127.0.0.1', port), BackendHandler)
    print(f"Backend server {server_id} listening on port {port}")
    server.serve_forever()

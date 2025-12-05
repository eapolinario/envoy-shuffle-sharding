#!/bin/bash
# Test script to demonstrate shuffle sharding with load balancing across shard members

echo "Testing Shuffle Sharding with Load Balancing"
echo "=============================================="
echo ""

customers=("customer-A" "customer-B" "customer-C" "customer-D")

for customer in "${customers[@]}"; do
    echo "Customer: $customer"
    
    # Get shard assignment from first request
    response=$(curl -s -H "x-customer-id: $customer" http://localhost:10000/)
    shard=$(echo "$response" | grep -o '"shard_assignment": "[^"]*"' | cut -d'"' -f4)
    echo "  Shard Assignment: $shard"
    
    # Test 20 different paths to see distribution
    echo "  Testing 20 different paths..."
    servers=$(for i in {1..20}; do 
        curl -s -H "x-customer-id: $customer" "http://localhost:10000/path$i" | grep -o '"server_id": "[^"]*"' | cut -d'"' -f4
    done | sort | uniq -c | awk '{print "Server " $2 ": " $1 " requests"}')
    
    echo "$servers" | sed 's/^/    /'
    
    # Test same path multiple times
    echo "  Testing /orders path 5 times (should be sticky)..."
    same_path=$(for i in {1..5}; do 
        curl -s -H "x-customer-id: $customer" "http://localhost:10000/orders" | grep -o '"server_id": "[^"]*"' | cut -d'"' -f4
    done | sort | uniq -c | awk '{print "Server " $2 ": " $1 " requests"}')
    
    echo "$same_path" | sed 's/^/    /'
    echo ""
done

echo "=============================================="
echo "Key observations:"
echo "1. Each customer gets their own shard (2 servers)"
echo "2. Requests are distributed across BOTH servers in the shard"
echo "3. Same path always routes to same server (sticky)"
echo "4. Different customers use different (but overlapping) shards"

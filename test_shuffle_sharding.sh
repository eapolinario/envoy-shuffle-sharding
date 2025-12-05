#!/bin/bash
# Test script to demonstrate shuffle sharding behavior

echo "Testing Shuffle Sharding with different customers..."
echo "======================================================"
echo ""

customers=("customer-A" "customer-B" "customer-C" "customer-D" "customer-E")

for customer in "${customers[@]}"; do
    echo "Customer: $customer"
    echo "Making 5 requests to see consistent shard assignment..."
    
    for i in {1..5}; do
        response=$(curl -s -H "x-customer-id: $customer" http://localhost:10000/)
        server_id=$(echo "$response" | grep -o '"server_id": "[^"]*"' | cut -d'"' -f4)
        shard=$(echo "$response" | grep -o '"shard_assignment": "[^"]*"' | cut -d'"' -f4)
        
        if [ $i -eq 1 ]; then
            echo "  Shard Assignment: [$shard]"
        fi
        echo "  Request $i -> Server $server_id"
    done
    echo ""
done

echo "======================================================"
echo "Notice how:"
echo "1. Each customer gets a consistent shard assignment"
echo "2. Different customers get different shards"
echo "3. Some overlap is expected (shuffle sharding property)"

#!/bin/bash
set -e

echo "Building shuffle-shard WASM filter..."
cargo build --target wasm32-wasip1 --release

echo ""
echo "✓ Build complete!"
echo ""
echo "WASM file: target/wasm32-wasip1/release/shuffle_shard_wasm.wasm"
echo "Size: $(du -h target/wasm32-wasip1/release/shuffle_shard_wasm.wasm | cut -f1)"
echo ""
echo "To use with Envoy, copy to parent directory:"
echo "  cp target/wasm32-wasip1/release/shuffle_shard_wasm.wasm .."

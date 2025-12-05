#!/bin/bash
# Build custom Envoy image with shuffle shard filter

set -e

echo "=========================================="
echo "Building Custom Envoy with Shuffle Shard Filter"
echo "=========================================="
echo ""
echo "⚠️  WARNING: This build takes 30-60 minutes and requires:"
echo "  - 20GB+ disk space"
echo "  - 8GB+ RAM"
echo "  - Docker"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Build cancelled"
    exit 1
fi

IMAGE_NAME="envoy-shuffle-shard:latest"

echo ""
echo "Building Docker image: $IMAGE_NAME"
echo "This will take 30-60 minutes..."
echo ""

docker build -t $IMAGE_NAME -f Dockerfile ..

echo ""
echo "=========================================="
echo "✓ Build complete!"
echo "=========================================="
echo ""
echo "Image: $IMAGE_NAME"
echo ""
echo "Test with:"
echo "  docker run --rm $IMAGE_NAME --version"
echo ""
echo "Use in docker-compose or scripts by referencing:"
echo "  image: $IMAGE_NAME"

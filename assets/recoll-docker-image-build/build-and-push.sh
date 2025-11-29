#!/usr/bin/env bash

# Build and push Recoll WebUI to my registry
#
# Usage: ./build-and-push.sh
#
# Note you need a registry of some sort.
# Mine is an internal 'distribution registry' (refer another job in this repo).

set -e

LOCAL_IMAGE="recoll-webui:latest"

# I like static and useful version tags.
# REGISTRY_IMAGE="registry.obs.int.jeddi.org/recoll-webui:latest"
REGISTRY_IMAGE="registry.obs.int.jeddi.org/recoll-webui:2025-11-29"

# Validate the build / push is successful by running:
# skopeo list-tags docker://registry.obs.int.jeddi.org/recoll-webui

echo "Building Docker image..."
docker build -t ${LOCAL_IMAGE} .

echo "Tagging for registry..."
docker tag ${LOCAL_IMAGE} ${REGISTRY_IMAGE}

echo "Pushing to registry with skopeo..."
skopeo copy \
    docker-daemon:${REGISTRY_IMAGE} \
    docker://${REGISTRY_IMAGE}

echo ""
echo "✓ Build complete!"
echo "✓ Image available at: ${REGISTRY_IMAGE}"
echo ""
echo "To test locally:"
echo "  docker run -p 8080:8080 -v /path/to/docs:/documents:ro ${LOCAL_IMAGE}"



#!/bin/bash

# Docker registry configuration
REGISTRY_URL="postech-a.kr-central-2.kcr.dev"
REGISTRY="${REGISTRY_URL}/chunghyun"

# Load registry credentials
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env.registry" ]; then
    source "$SCRIPT_DIR/.env.registry"
else
    echo "Error: $SCRIPT_DIR/.env.registry not found"
    echo "Create it with REGISTRY_USERNAME and REGISTRY_PASSWORD"
    exit 1
fi
IMAGE_NAME="affostruction"
VERSION="latest"
TARGET="b200"

usage() {
    echo "Usage: $0 [VERSION] [OPTIONS]"
    echo ""
    echo "Arguments:"
    echo "  VERSION       Image version tag (default: latest)"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo "  -n, --no-cache Build without cache"
    echo "  -p, --push    Push image to registry after build"
    echo "  -s, --skip-test Skip GPU test after build"
    echo "  -t, --target  GPU target: a6000 or b200 (default)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Build with tag 'latest' for b200"
    echo "  $0 v1.0               # Build with tag 'v1.0' for b200"
    echo "  $0 v1.0 --push        # Build and push"
    echo "  $0 v1.0 -t a6000      # Build for A6000 GPU"
}

# Parse arguments
NO_CACHE=""
PUSH=false
SKIP_TEST=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -n|--no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        -p|--push)
            PUSH=true
            shift
            ;;
        -s|--skip-test)
            SKIP_TEST=true
            shift
            ;;
        -t|--target)
            TARGET="$2"
            shift 2
            ;;
        *)
            if [[ ! "$1" =~ ^- ]]; then
                VERSION="$1"
            fi
            shift
            ;;
    esac
done

# Validate target
if [[ "$TARGET" != "a6000" && "$TARGET" != "b200" ]]; then
    echo "Error: Invalid target '$TARGET'. Use 'a6000' or 'b200'"
    exit 1
fi

# Set Dockerfile and tag based on target
if [[ "$TARGET" == "b200" ]]; then
    DOCKERFILE="docker/Dockerfile.b200"
    TAG="${REGISTRY}/${IMAGE_NAME}:${VERSION}-b200"
else
    DOCKERFILE="docker/Dockerfile"
    TAG="${REGISTRY}/${IMAGE_NAME}:${VERSION}"
fi

echo "Building image: ${TAG} (target: ${TARGET})"

# Build
docker build $NO_CACHE -t "$TAG" -f "$DOCKERFILE" .

if [ $? -ne 0 ]; then
    echo "Build failed"
    exit 1
fi

# Test
if [ "$SKIP_TEST" = false ]; then
    echo "Testing image..."
    docker run --gpus all --rm "$TAG" python -c "
import torch
print(f'PyTorch: {torch.__version__}')
print(f'CUDA available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'GPU: {torch.cuda.get_device_name(0)}')
"

    if [ $? -ne 0 ]; then
        echo "Test failed"
        exit 1
    fi
else
    echo "Skipping GPU test"
fi

echo "Build successful: ${TAG}"

# Push if requested
if [ "$PUSH" = true ]; then
    echo "Logging in to registry..."
    echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_URL" --username "$REGISTRY_USERNAME" --password-stdin

    echo "Pushing to registry..."
    docker push "$TAG"
    if [ $? -eq 0 ]; then
        echo "Push successful"
    else
        echo "Push failed"
        exit 1
    fi
fi

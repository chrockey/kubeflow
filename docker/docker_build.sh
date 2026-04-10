#!/bin/bash
set -euo pipefail

# Image name — keep in sync with the `image:` field in
# kubeflow/training-runtime.yaml.
IMAGE_NAME="kubeflow-train"

# Resolve paths and load .env from repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f "$REPO_ROOT/.env" ]; then
    echo "Error: $REPO_ROOT/.env not found"
    echo "Create it with REGISTRY_URL, REGISTRY_NAMESPACE,"
    echo "REGISTRY_USERNAME, REGISTRY_PASSWORD."
    exit 1
fi
set -a
source "$REPO_ROOT/.env"
set +a

: "${REGISTRY_URL:?REGISTRY_URL not set in .env}"
: "${REGISTRY_NAMESPACE:?REGISTRY_NAMESPACE not set in .env}"
: "${REGISTRY_USERNAME:?REGISTRY_USERNAME not set in .env}"
: "${REGISTRY_PASSWORD:?REGISTRY_PASSWORD not set in .env}"

# Args: $1 = tag (default "latest"), --push to push after build
VERSION="latest"
PUSH=false
for arg in "$@"; do
    case "$arg" in
        --push) PUSH=true ;;
        -h|--help)
            echo "Usage: $0 [VERSION] [--push]"
            exit 0
            ;;
        *) VERSION="$arg" ;;
    esac
done

TAG="${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${VERSION}"

echo "Building image: ${TAG}"
docker build -t "$TAG" -f "$SCRIPT_DIR/Dockerfile" "$REPO_ROOT"

if [ "$PUSH" = true ]; then
    echo "Logging in to ${REGISTRY_URL}..."
    echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_URL" \
        --username "$REGISTRY_USERNAME" --password-stdin
    echo "Pushing ${TAG}..."
    docker push "$TAG"
fi

echo "Done: ${TAG}"

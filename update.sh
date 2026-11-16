#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_WAS_RUNNING=false

cleanup() {
    local exit_code=$?
    trap - EXIT INT TERM

    if [[ "$DOCKER_WAS_RUNNING" == false ]]; then
        echo "Stopping Docker..."
        sudo systemctl stop docker.service docker.socket
    fi

    exit "$exit_code"
}

trap cleanup EXIT INT TERM

if systemctl is-active --quiet docker.service; then
    DOCKER_WAS_RUNNING=true
    echo "Docker is already running."
else
    echo "Starting Docker..."
    sudo systemctl start docker.service
fi

echo "Waiting for Docker..."

until docker info >/dev/null 2>&1; do
    sleep 0.2
done

cd "$PROJECT_DIR"

echo "Updating Speedify Browser & Torrent..."
docker compose build --pull --no-cache

echo "Update complete. The new image will be used on the next launch."

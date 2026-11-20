#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QA_UID="$(id -u qa)"
QA_GID="$(id -g qa)"
SHA="$(git -C "$ROOT" rev-parse --short HEAD)"
IMAGE="redcarlos/qa-agents:$SHA"

docker build \
  --build-arg "QA_UID=$QA_UID" \
  --build-arg "QA_GID=$QA_GID" \
  --tag "$IMAGE" \
  --file "$ROOT/docker/Dockerfile" \
  "$ROOT"

printf 'Built: %s\n' "$IMAGE"

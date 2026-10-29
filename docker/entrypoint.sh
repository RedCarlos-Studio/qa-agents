#!/bin/sh
set -eu

subscription="${CLAUDE_CODE_OAUTH_TOKEN:-}"
api="${ANTHROPIC_API_KEY:-}"

if [ -n "$subscription" ] && [ -n "$api" ]; then
    echo "ERROR: set only one Claude authentication variable." >&2
    exit 64
fi

if [ -z "$subscription" ] && [ -z "$api" ]; then
    echo "ERROR: Claude authentication is missing." >&2
    exit 64
fi

cd /work/repo
exec "$@"

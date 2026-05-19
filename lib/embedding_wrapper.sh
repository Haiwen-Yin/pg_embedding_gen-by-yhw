#!/bin/bash
#
# pg_embedding-gen: Embedding wrapper script
# Version: v1.0.0
# Author: yhw (Haiwen Yin)
#
# Wraps embedding_proxy.py for safe execution in PostgreSQL COPY FROM PROGRAM.
# Uses base64 encoding to avoid shell injection and special character issues.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROXY_SCRIPT="${SCRIPT_DIR}/embedding_proxy.py"
DEFAULT_CONFIG="/etc/pg_embedding-gen/config.json"

TEXT=""
MODEL=""
API_URL=""
CONFIG=""
LOG_FILE=""
LOG_LEVEL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --text)
            TEXT="$2"
            shift 2
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --api-url)
            API_URL="$2"
            shift 2
            ;;
        --config)
            CONFIG="$2"
            shift 2
            ;;
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        --log-level)
            LOG_LEVEL="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -z "$TEXT" ]]; then
    echo "Error: --text parameter required" >&2
    exit 1
fi

if [[ ! -f "$PROXY_SCRIPT" ]]; then
    echo "Error: proxy script not found: $PROXY_SCRIPT" >&2
    exit 1
fi

if [[ -z "$CONFIG" ]] && [[ -f "$DEFAULT_CONFIG" ]]; then
    CONFIG="$DEFAULT_CONFIG"
fi

TEXT_B64=$(printf '%s' "$TEXT" | base64 | tr -d '\n')

CMD=(python3 "$PROXY_SCRIPT" --text-base64 "$TEXT_B64")

if [[ -n "$MODEL" ]]; then
    CMD+=(--model "$MODEL")
fi

if [[ -n "$API_URL" ]]; then
    CMD+=(--api-url "$API_URL")
fi

if [[ -n "$CONFIG" ]]; then
    CMD+=(--config "$CONFIG")
fi

if [[ -n "$LOG_FILE" ]]; then
    CMD+=(--log-file "$LOG_FILE")
fi

if [[ -n "$LOG_LEVEL" ]]; then
    CMD+=(--log-level "$LOG_LEVEL")
fi

exec "${CMD[@]}"

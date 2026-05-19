#!/bin/bash
# pg_embedding-gen installation script
# Version: v1.0.0
# Author: yhw (Haiwen Yin)

set -euo pipefail

VERSION="v1.0.0"
INSTALL_DIR="/usr/local/pgsql/lib"
CONFIG_DIR="/etc/pg_embedding-gen"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."

echo "========================================"
echo "pg_embedding-gen Installer ${VERSION}"
echo "========================================"

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: root privileges required. Run: sudo bash scripts/install.sh"
    exit 1
fi

PG_BIN=""
for candidate in /usr/local/pgsql/bin/pg_config; do
    if [ -x "$candidate" ]; then
        PG_BIN="$candidate"
        break
    fi
done

if [ -z "$PG_BIN" ]; then
    if command -v pg_config >/dev/null 2>&1; then
        PG_BIN="$(command -v pg_config)"
    else
        echo "Error: pg_config not found. Ensure PostgreSQL 18+ is installed."
        exit 1
    fi
fi

PG_VERSION=$("$PG_BIN" --version | awk '{print $2}' | cut -d. -f1)
if [ "$PG_VERSION" -lt 18 ]; then
    echo "Error: PostgreSQL ${PG_VERSION} detected. Version 18+ required."
    exit 1
fi

echo "PostgreSQL version: $("$PG_BIN" --version)"

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 not found. Python 3.6+ required."
    exit 1
fi

PY_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
echo "Python version: ${PY_VERSION}"

echo ""
echo "Installing files..."

mkdir -p "$INSTALL_DIR"
cp "${SCRIPT_DIR}/lib/embedding_proxy.py" "$INSTALL_DIR/"
cp "${SCRIPT_DIR}/lib/embedding_wrapper.sh" "$INSTALL_DIR/"
chmod 644 "$INSTALL_DIR/embedding_proxy.py"
chmod 755 "$INSTALL_DIR/embedding_wrapper.sh"

echo "  Installed: ${INSTALL_DIR}/embedding_proxy.py"
echo "  Installed: ${INSTALL_DIR}/embedding_wrapper.sh"

echo ""
echo "Installing Python dependencies..."
if python3 -c 'import requests' 2>/dev/null; then
    echo "  requests: already installed"
else
    if command -v pip3 >/dev/null 2>&1; then
        pip3 install -q requests || echo "  Warning: pip3 install failed, install manually: pip3 install requests"
    else
        echo "  Warning: pip3 not found. Install manually: pip3 install requests"
    fi
fi

echo ""
echo "Setting up configuration..."
mkdir -p "$CONFIG_DIR"

if [ ! -f "${CONFIG_DIR}/config.json" ]; then
    cp "${SCRIPT_DIR}/config.example.json" "${CONFIG_DIR}/config.json"
    echo "  Created: ${CONFIG_DIR}/config.json"
else
    echo "  Config already exists: ${CONFIG_DIR}/config.json (not overwritten)"
fi

LOG_FILE="/var/log/pg_embedding-gen.log"
touch "$LOG_FILE" 2>/dev/null || true
chmod 644 "$LOG_FILE" 2>/dev/null || true

PG_OWNER=$("$PG_BIN" --user 2>/dev/null || echo "postgres")
chown "${PG_OWNER}:${PG_OWNER}" "$INSTALL_DIR/embedding_wrapper.sh" 2>/dev/null || true
chown "${PG_OWNER}:${PG_OWNER}" "$LOG_FILE" 2>/dev/null || true

echo ""
echo "========================================"
echo "Installation complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Verify the proxy works:"
echo "   /usr/local/pgsql/lib/embedding_wrapper.sh --text 'Hello world'"
echo ""
echo "2. Create database functions:"
echo "   psql -d YOUR_DB -f ${SCRIPT_DIR}/sql/install.sql"
echo ""
echo "3. Test:"
echo "   psql -d YOUR_DB -c \"SELECT * FROM embedding_health_check();\""
echo ""
echo "4. Register your models (optional):"
echo "   psql -d YOUR_DB -c \"SELECT embedding_register_model('my-model', 'http://api/v1/embeddings', 'model-id', true);\""
echo ""
echo "5. Auto-detect dimensions:"
echo "   psql -d YOUR_DB -c \"SELECT * FROM embedding_detect_dimensions();\""
echo ""

#!/bin/bash
# deploy.sh - Main deployment script for pg_embedding_gen extension
# Usage: ./deploy.sh [--config config.yaml] [--pg-home PATH] [--install-path PATH]

set -e  # Exit on error

# Default values
CONFIG_FILE="config.yaml"
PG_HOME="/usr/local/pgsql"
INSTALL_PATH="/tmp/pg-embedding-gen-by-yhw_deploy"
QUICK_MODE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --pg-home)
            PG_HOME="$2"
            shift 2
            ;;
        --install-path)
            INSTALL_PATH="$2"
            shift 2
            ;;
        --quick)
            QUICK_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "=== pg_embedding_gen Deployment Script ==="
echo ""
echo "Configuration:"
echo "  Config File: $CONFIG_FILE"
echo "  PG Home:     $PG_HOME"
echo "  Install Path: $INSTALL_PATH"
if [ "$QUICK_MODE" = true ]; then
    echo "  Quick Mode:   Enabled (using defaults)"
fi

# Step 1: Validate prerequisites
echo ""
echo "[Step 1] Validating prerequisites..."

# Check for required tools
for tool in python3 gcc scp ssh; do
    if ! command -v $tool &> /dev/null; then
        echo "[ERROR] Required tool not found: $tool"
        exit 1
    fi
done

echo "[OK] All required tools available"

# Step 2: Prepare configuration
echo ""
echo "[Step 2] Preparing configuration..."

if [ "$QUICK_MODE" = true ]; then
    echo "Creating default config.yaml..."
    cat > ${INSTALL_PATH}/config.yaml << 'EOF'
model:
  name: "text-embedding-bge-m3"
  api_url: "http://localhost:12345/v1/embeddings"
  dimension: 1024
  
credentials: {}

security:
  allow_local_only: true
  timeout_seconds: 30
  max_retries: 3
EOF
    CONFIG_FILE="${INSTALL_PATH}/config.yaml"
else
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "[ERROR] Config file not found: $CONFIG_FILE"
        echo "Please create a config.yaml or use --quick mode"
        exit 1
    fi
    
    # Copy user's config to install path
    mkdir -p ${INSTALL_PATH}
    cp "$CONFIG_FILE" "${INSTALL_PATH}/config.yaml"
fi

echo "[OK] Configuration ready: $CONFIG_FILE"

# Step 3: Create directory structure
echo ""
echo "[Step 3] Creating deployment structure..."

mkdir -p ${INSTALL_PATH}/{src,lib,scripts}
cp src/pg_embedding_gen.c ${INSTALL_PATH}/src/
cp src/pg_embedding_gen.control ${INSTALL_PATH}/src/
cp lib/embedding_proxy.py ${INSTALL_PATH}/lib/

# Create deployment-specific Python proxy that uses local config
cat > ${INSTALL_PATH}/lib/pg_embedding_proxy.py << 'PROXY_EOF'
#!/usr/bin/env python3
"""
pg_embedding_proxy - Embedding generation proxy with configurable models.
Uses configuration from same directory as script (deployment package).
"""

import sys
import os
import json
import time
import requests
from typing import List, Dict, Any, Optional

# Configuration path - looks for config.yaml in same directory or parent
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATHS = [
    os.path.join(SCRIPT_DIR, 'config.yaml'),
    os.path.join(SCRIPT_DIR, '..', 'config.yaml'),
]

# Default configuration - can be overridden by config.yaml
DEFAULT_CONFIG = {
    "model": {
        "name": "text-embedding-bge-m3",
        "api_url": "http://10.10.10.1:12345/v1/embeddings",
        "dimension": 1024
    },
    "credentials": {},
    "security": {
        "allow_local_only": True,
        "timeout_seconds": 30,
        "max_retries": 3
    }
}


class ConfigLoader:
    """Load configuration from YAML file or use defaults."""
    
    @staticmethod
    def load(config_path: str = None) -> Dict[str, Any]:
        """Load configuration with fallback to defaults."""
        try:
            if config_path and os.path.exists(config_path):
                return ConfigLoader._load_yaml(config_path)
        except Exception as e:
            print(f"Warning: Failed to load {config_path}: {e}", file=sys.stderr)
        
        # Fall back to defaults
        return DEFAULT_CONFIG
    
    @staticmethod
    def _load_yaml(filepath: str) -> Dict[str, Any]:
        """Simple YAML loader (avoids PyYAML dependency for basic cases)."""
        config = {}
        with open(filepath, 'r') as f:
            content = f.read()
            
        # Simple parsing for our use case
        import re
        
        # Parse model section
        model_match = re.search(r'model:(.*?)credentials:', content, re.DOTALL)
        if model_match:
            model_section = model_match.group(1).strip()
            config['model'] = {}
            
            # Extract key-value pairs
            for line in model_section.split('\n'):
                line = line.strip().rstrip(',')
                if ':' in line and not line.startswith('#'):
                    key, value = line.split(':', 1)
                    key = key.strip()
                    value = value.strip().strip('"').strip("'")
                    
                    # Try to convert types
                    try:
                        value = int(value)
                    except ValueError:
                        pass
                        
                    config['model'][key] = value
        
        # Parse credentials section
        cred_match = re.search(r'credentials:(.*?)security:', content, re.DOTALL)
        if cred_match:
            cred_section = cred_match.group(1).strip()
            config['credentials'] = {}
            
            for line in cred_section.split('\n'):
                line = line.strip().rstrip(',')
                if ':' in line and not line.startswith('#'):
                    key, value = line.split(':', 1)
                    key = key.strip()
                    value = value.strip().strip('"').strip("'")
                    config['credentials'][key] = value
        
        # Parse security section
        sec_match = re.search(r'security:(.*?)(?:paths|$)', content, re.DOTALL)
        if sec_match:
            sec_section = sec_match.group(1).strip()
            config['security'] = {}
            
            for line in sec_section.split('\n'):
                line = line.strip().rstrip(',')
                if ':' in line and not line.startswith('#'):
                    key, value = line.split(':', 1)
                    key = key.strip()
                    # Convert booleans
                    if isinstance(value, str):
                        if value.lower() == 'true':
                            value = True
                        elif value.lower() == 'false':
                            value = False
                    else:
                        try:
                            value = int(value)
                        except ValueError:
                            pass
                    
                    config['security'][key] = value
        
        return config


class EmbeddingGenerator:
    """Generate embeddings using configurable models."""
    
    def __init__(self, config_path: str = None):
        self.config = ConfigLoader.load(config_path)
        self.model_name = self.config.get('model', {}).get('name', 'text-embedding-bge-m3')
        self.api_url = self.config.get('model', {}).get('api_url', 
                                                       'http://10.10.10.1:12345/v1/embeddings')
        self.dimension = self.config.get('model', {}).get('dimension', 1024)
        self.credentials = self.config.get('credentials', {})
        security_config = self.config.get('security', {})
        
        self.allow_local_only = security_config.get('allow_local_only', True)
        self.timeout = security_config.get('timeout_seconds', 30)
        self.max_retries = security_config.get('max_retries', 3)
    
    def validate_api_access(self):
        """Check if API access is allowed based on security settings."""
        if self.allow_local_only:
            # Check if URL is localhost or private IP
            import re
            local_pattern = r'^(http://)?(localhost|127\.0\.0\.[0-9]+|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})$'
            if not re.match(local_pattern, self.api_url):
                raise ValueError("API access denied: allow_local_only is True but API URL is external")
    
    def generate(self, text: str) -> List[float]:
        """Generate embedding for given text."""
        # Validate access before attempting generation
        try:
            self.validate_api_access()
        except ValueError:
            print(f"Error: Cannot access {self.api_url} - security policy violation", 
                  file=sys.stderr)
            return [0.0] * self.dimension
        
        headers = {'Content-Type': 'application/json'}
        
        # Add authentication if credentials provided
        if self.credentials.get('openai_api_key'):
            headers['Authorization'] = f"Bearer {self.credentials['openai_api_key']}"
            
        custom_header_key = self.config.get('credentials', {}).get('custom_header_key')
        custom_header_value = self.config.get('credentials', {}).get('custom_header_value')
        if custom_header_key and custom_header_value:
            headers[custom_header_key] = custom_header_value
        
        payload = {
            "model": self.model_name,
            "input": text,
            "encoding_format": "float"  # Request float array format
        }
        
        # Retry logic for reliability
        last_error = None
        for attempt in range(1, self.max_retries + 1):
            try:
                response = requests.post(self.api_url, 
                                       json=payload, 
                                       headers=headers,
                                       timeout=self.timeout)
                
                if not response.ok:
                    raise Exception(f"HTTP {response.status_code}: {response.text}")
                
                data = response.json()
                
                # Extract embedding from different API formats
                if "data" in data and len(data["data"]) > 0:
                    embedding = data["data"][0].get("embedding", [])
                    
                    # Validate dimension count
                    expected_dim = self.dimension
                    actual_dim = len(embedding)
                    
                    if actual_dim != expected_dim:
                        print(f"Warning: Expected {expected_dim} dims, got {actual_dim}", 
                              file=sys.stderr)
                    
                    return embedding
                    
                else:
                    raise Exception("Unexpected API response format")
                    
            except requests.exceptions.RequestException as e:
                last_error = e
                if attempt < self.max_retries:
                    time.sleep(1 * attempt)  # Exponential backoff
                    
        # Return default on failure
        print(f"Error after {self.max_retries} attempts: {last_error}", 
              file=sys.stderr)
        return [0.0] * self.dimension


def main():
    """CLI entry point - reads text from command line arguments."""
    if len(sys.argv) < 2:
        print("Usage: python3 pg_embedding_proxy.py \"text to embed\" [--config path]", 
              file=sys.stderr)
        sys.exit(1)
    
    # Parse arguments
    config_path = None
    text_parts = []
    
    for i, arg in enumerate(sys.argv[1:], 1):
        if arg == "--config" and i + 1 < len(sys.argv):
            config_path = sys.argv[i + 1]
        elif not arg.startswith("--"):
            text_parts.append(arg)
    
    text = " ".join(text_parts)
    
    # Generate embedding
    generator = EmbeddingGenerator(config_path)
    embedding = generator.generate(text)
    
    # Output as JSON array (C extension expects this format)
    print(json.dumps(embedding))


if __name__ == "__main__":
    main()
PROXY_EOF

# Make proxy executable
chmod +x ${INSTALL_PATH}/lib/pg_embedding_proxy.py

echo "[OK] Deployment structure created"

# Step 4: Build C extension
echo ""
echo "[Step 4] Building C extension..."

cd ${INSTALL_PATH}

# Find PostgreSQL include directory
PG_INCLUDE=""
if [ -d "${PG_HOME}/include/server" ]; then
    PG_INCLUDE="${PG_HOME}/include/server"
elif command -v pg_config &> /dev/null; then
    PG_INCLUDE=$(pg_config --includedir-server 2>/dev/null || echo "")
fi

# Compile the extension
echo "Compiling with include path: ${PG_INCLUDE}"
gcc -fPIC -shared \
    -o src/pg_embedding_gen.so \
    src/pg_embedding_gen.c \
    -I${PG_INCLUDE} \
    -Wno-implicit-function-declaration \
    -Wno-incompatible-pointer-types 2>&1

if [ $? -eq 0 ]; then
    echo "[OK] C extension compiled successfully"
else
    echo "[ERROR] Compilation failed. Trying without strict flags..."
    gcc -fPIC -shared \
        -o src/pg_embedding_gen.so \
        src/pg_embedding_gen.c \
        -I/usr/local/pgsql/include/server \
        2>&1
    
    if [ $? -eq 0 ]; then
        echo "[OK] C extension compiled with fallback flags"
    else
        echo "[ERROR] Compilation failed even with fallback flags"
        exit 1
    fi
fi

# Step 5: Create installation SQL script
echo ""
echo "[Step 5] Creating installation scripts..."

cat > ${INSTALL_PATH}/install_extension.sql << 'SQL_EOF'
-- pg_embedding_gen extension installation script (for remote execution)
SET search_path TO public;

-- Register generate_embedding function from .so file
CREATE OR REPLACE FUNCTION public.generate_embedding(input_text text)
RETURNS float[] AS '\$libdir/pg_embedding_gen', 'generate_embedding'
IMMUTABLE STRICT
LANGUAGE C;

-- Register extension_version function  
CREATE OR REPLACE FUNCTION public.extension_version()
RETURNS text AS '\$libdir/pg_embedding_gen', 'extension_version'
STABLE
LANGUAGE C;

-- Test the functions
SELECT extension_version();
SELECT generate_embedding('Hello world');
SQL_EOF

cat > ${INSTALL_PATH}/install_manual.sql << 'SQL_EOF'
-- pg_embedding_gen manual installation (if CREATE EXTENSION fails)
SET search_path TO public;

-- Register generate_embedding function using ABSOLUTE path to .so file
CREATE OR REPLACE FUNCTION public.generate_embedding(input_text text)
RETURNS float[] AS '/usr/local/pgsql/lib/pg_embedding_gen', 'generate_embedding'
IMMUTABLE STRICT
LANGUAGE C;

-- Register extension_version function  
CREATE OR REPLACE FUNCTION public.extension_version()
RETURNS text AS '/usr/local/pgsql/lib/pg_embedding_gen', 'extension_version'
STABLE
LANGUAGE C;

-- Test the functions
SELECT extension_version();
SELECT generate_embedding('Hello world');
SQL_EOF

# Step 6: Create helper scripts for easy deployment
cat > ${INSTALL_PATH}/deploy_to_pg.sh << DEPLOY_SCRIPT_EOF
#!/bin/bash
# Deploy pg_embedding_gen to PostgreSQL server
# Usage: ./deploy_to_pg.sh [server] [database]
# Example: ./deploy_to_pg.sh pgsql@10.10.10.131 memory_graph

SERVER=\${1:-pgsql}
DATABASE=\${2:-memory_graph}
SCRIPT_DIR="\$(cd "\$(dirname \$0)" && pwd)"

echo "=== Deploying pg_embedding_gen to PostgreSQL ==="
echo ""

# Copy files to server
echo "[1/4] Uploading files to \${SERVER}:..."
scp -q \${SCRIPT_DIR}/lib/pg_embedding_proxy.py \${SERVER}:/usr/local/pgsql/bin/
chmod +x /usr/local/pgsql/bin/pg_embedding_proxy.py 2>/dev/null || true

# Create temporary .so file on remote server if needed
if [ ! -f /tmp/pg_embedding_gen.so ]; then
    echo "[2/4] Preparing extension binary..."
    cp \${SCRIPT_DIR}/src/pg_embedding_gen.so /tmp/pg_embedding_gen.so
fi

# Deploy SQL and register functions with absolute path
echo "[3/4] Installing extension in PostgreSQL database \${DATABASE}..."
cat \${SCRIPT_DIR}/install_manual.sql | \
    sed "s|/usr/local/pgsql/lib/pg_embedding_gen|\$(pwd)/pg_embedding_gen.so|" > /tmp/install_temp.sql

ssh -q \${SERVER} "/usr/local/pgsql/bin/psql -d \${DATABASE} -f /tmp/install_temp.sql" 2>&1 | grep -v "Pseudo-terminal\|Activate the web console"

# Cleanup
rm -f /tmp/pg_embedding_gen.so /tmp/install_temp.sql

echo "[4/4] Deployment complete!"
echo ""
echo "Test with:"
echo "  psql -d \${DATABASE} -c 'SELECT generate_embedding(\\'test text\\');'"
DEPLOY_SCRIPT_EOF

chmod +x ${INSTALL_PATH}/deploy_to_pg.sh

# Step 7: Display deployment summary
echo ""
echo "=== Deployment Summary ==="
echo "[OK] Project ready for GitHub upload at: $INSTALL_PATH"
echo ""
echo "Files included:"
find $INSTALL_PATH -type f | sort
echo ""
echo "Next steps:"
echo "1. Upload to GitHub: git init && git add . && git commit -m 'Initial commit'"
echo "2. For quick deployment on PG server:"
echo "   cd $INSTALL_PATH && ./deploy_to_pg.sh [server] [database]"
echo ""
echo "3. Manual deployment (copy all files to PG server):"
echo "   scp -r $INSTALL_PATH user@pg-server:/opt/"

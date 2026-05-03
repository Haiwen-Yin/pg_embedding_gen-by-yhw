# pg-embedding-gen-by-yhw - PostgreSQL Embedding Extension

## Project Overview

A production-ready PostgreSQL extension that generates text embeddings using configurable external models via a Python proxy.

### Key Features

- [OK] **Configurable Models**: Support for BGE-M3, OpenAI Ada, and custom models
- [OK] **Easy Deployment**: Automated scripts for one-click installation  
- [OK] **High Performance**: Native C extension with direct API access
- [OK] **Security First**: Local-only mode and configurable timeouts
- [OK] **GitHub Ready**: Complete project structure with documentation

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/yourusername/pg-embedding-gen-by-yhw.git
cd pg-embedding-gen-by-yhw

# 2. Configure your model
cp config.example.yaml config.yaml
# Edit config.yaml with your settings

# 3. Deploy to PostgreSQL server
./scripts/deploy.sh --quick
```

## Configuration

### Supported Models

| Model | Provider | Dimension | Example Config |
|-------|----------|-----------|----------------|
| BGE-M3 | Local/HuggingFace | 1024 | `name: text-embedding-bge-m3` |
| Ada-002 | OpenAI | 1536 | `api_url: https://api.openai.com/v1/embeddings` |
| nomic-v1.5 | HuggingFace | 768 | `name: sentence-transformers/nomic-embed-text-v1.5` |

### Configuration File Example

```yaml
# config.yaml
model:
  name: "text-embedding-bge-m3"
  api_url: "http://localhost:12345/v1/embeddings"
  dimension: 1024
  
credentials:
  openai_api_key: ""  # For OpenAI models

security:
  allow_local_only: true  # Restrict to localhost
  timeout_seconds: 30
```

## Usage in PostgreSQL

```sql
-- Generate embedding for text
SELECT generate_embedding('Hello world');

-- Check extension version
SELECT extension_version();

-- Get dimension count  
SELECT array_length(generate_embedding('test'), 1);
```

## Deployment Options

### Option 1: Quick Deploy (Recommended)
```bash
./scripts/deploy.sh --quick
```

### Option 2: Manual Deploy with Config
```bash
./scripts/deploy.sh --config config.yaml --pg-home /usr/local/pgsql
```

### Option 3: Remote Server Deployment
```bash
# After deploying locally, push to remote server
cd deploy && ./scripts/deploy_to_pg.sh user@remote-server database_name
```

## Project Structure

```
pg-embedding-gen-by-yhw/
├── README.md              # Project documentation
├── LICENSE                # Apache 2.0 License
├── config.example.yaml    # Configuration template
├── Makefile               # Build automation
│
├── src/                   # C extension source code
│   ├── pg_embedding_gen.c
│   └── pg-embedding-gen-by-yhw.control
│
├── lib/                   # Python proxy and utilities
│   └── embedding_proxy.py
│
├── scripts/               # Deployment automation
│   ├── deploy.sh          # Main deployment script
│   ├── install_extension.sql
│   └── test_extension.sql
│
└── docs/                  # Documentation (optional)
    └── getting-started.md
```

## Requirements

- PostgreSQL 18+ with development headers
- Python 3.8+ with `requests` library
- GCC compiler
- Network access to embedding API (or local model server)

### Install Dependencies

```bash
# Python dependencies
pip install requests

# PostgreSQL dev headers
sudo apt-get install postgresql-server-dev-all  # Ubuntu/Debian
# or: yum install postgresql-devel              # CentOS/RHEL
```

## Troubleshooting

### Common Issues

**1. Library loading error:**
```bash
# Ensure .so file is executable
chmod +x /usr/local/pgsql/lib/pg-embedding-gen-by-yhw.so
```

**2. API connection failed:**
```bash
# Test connectivity directly
curl http://localhost:12345/v1/embeddings -H "Content-Type: application/json" \
  -d '{"model": "text-embedding-bge-m3", "input": "test"}'
```

**3. Empty embedding returned:**
```bash
# Check Python proxy execution
python3 /usr/local/pgsql/bin/pg_embedding_proxy.py "test"
```

## License

Apache License, Version 2.0 - See [LICENSE](LICENSE) file for details.

---

**Version**: 0.1.0  
**PostgreSQL Compatibility**: 18+  
**Python Version**: 3.8+  

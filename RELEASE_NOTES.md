# Release Notes for pg-embedding-gen-by-yhw

## Version 0.1.0 - Initial Release (May 3, 2026)

### Features

**Core Functionality**
- PostgreSQL extension that generates text embeddings using configurable external models via a Python proxy
- Support for multiple embedding models including:
  - BGE-M3 (1024 dimensions) - Local deployment recommended
  - OpenAI Ada-002 (1536 dimensions) - API-based
  - nomic-v1.5 (768 dimensions) - Local deployment
- Native C extension with direct API access for high performance

**Configuration System**
- YAML-based configuration file (`config.example.yaml`)
- Support for custom model endpoints and credentials
- Security settings including local-only mode restrictions
- Configurable timeouts and retry logic

**Deployment Automation**
- Automated deployment scripts for one-click installation
- Remote server deployment support via SSH/SCP
- Build automation with Makefile targets (build, deploy, test)

### Technical Details

**SQL Functions Provided:**
```sql
-- Generate embedding for text input
SELECT generate_embedding('text to embed');

-- Query extension version information
SELECT extension_version();

-- Get dimension count of returned vector
SELECT array_length(generate_embedding('test'), 1);
```

**Architecture:**
- C extension calls Python proxy via `popen()`
- Python proxy connects to external embedding API (BGE-M3, OpenAI, etc.)
- Returns FLOAT[] array from PostgreSQL functions

### Requirements

| Component | Version | Notes |
|-----------|---------|-------|
| PostgreSQL | 18+ | With development headers |
| Python | 3.8+ | With `requests` library installed |
| GCC | Any recent version | For compiling the C extension |
| Network Access | Required | To connect to embedding API |

### Installation

```bash
# Clone repository
git clone https://github.com/yourusername/pg-embedding-gen-by-yhw.git
cd pg-embedding-gen-by-yhw

# Configure your model (copy and edit)
cp config.example.yaml config.yaml

# Deploy to local PostgreSQL server
./scripts/deploy.sh --quick

# Or deploy to remote server
./scripts/deploy.sh --config config.yaml --pg-home /usr/local/pgsql
```

### Known Limitations

1. **Model Compatibility**: Only supports models that return embeddings in OpenAI-compatible JSON format with `encoding_format: "float"`
2. **Security**: By default, local-only mode restricts API access to localhost/private IPs only
3. **Performance**: C extension uses popen() which may have overhead for high-frequency calls

### License

This project is licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) file for full terms and conditions.

---

*For issues or feature requests, please open an issue on GitHub.*

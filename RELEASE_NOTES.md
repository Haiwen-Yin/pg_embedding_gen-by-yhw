# pg_embedding-gen v1.0.0 Release Notes

**Release Date:** 2026-05-17

## Overview

First stable release of pg_embedding-gen — a multi-model embedding generation extension for PostgreSQL 18+. Generate text vector embeddings via SQL by calling any OpenAI-compatible `/v1/embeddings` API endpoint.

This is a complete rewrite from the original C extension to a pure SQL + Python approach using PostgreSQL 18's `COPY FROM PROGRAM` mechanism. No C compilation required.

## Highlights

### Multi-Model Support

Register and manage multiple embedding models entirely via SQL:

```sql
SELECT embedding_register_model('openai', 'https://api.openai.com/v1/embeddings', 'text-embedding-3-small', true);
SELECT embedding_register_model('local-bge', 'http://10.10.10.1:12345/v1/embeddings', 'text-embedding-bge-m3', false);
SELECT embedding_generate('Hello');               -- uses default
SELECT embedding_generate('Hello', 'local-bge');  -- uses named profile
```

### Auto-Detect Dimensions

Vector dimensions are automatically detected on first use and cached:

```sql
SELECT * FROM embedding_detect_dimensions();
--  name       | model_id                | dimensions | response_ms
-- ------------+-------------------------+------------+-------------
--  openai     | text-embedding-3-small  |       1536 |         210
--  local-bge  | text-embedding-bge-m3   |       1024 |         120
```

### Inline Calls (No Registration)

```sql
SELECT embedding_generate_model(
    'Hello world',
    'text-embedding-bge-m3',
    'http://10.10.10.1:12345/v1/embeddings'
);
```

### Reliability

- Base64-encoded input for shell-safe special character handling
- Automatic retry with exponential backoff on transient failures
- Proper `VOLATILE` function markers (not `IMMUTABLE`)
- Health check and vector validation functions
- Request logging and statistics

## Breaking Changes from C Extension (v0.1.0)

- Function `generate_embedding(text)` replaced by `embedding_generate(text)`
- C extension `pg_embedding_gen` replaced by SQL functions — no `CREATE EXTENSION` needed
- YAML config replaced by JSON config (and in-database config is preferred)
- `openai` and `pyyaml` Python dependencies removed — only `requests` required
- Minimum Python version lowered from 3.8 to 3.6

## Requirements

- PostgreSQL 18+
- Python 3.6+
- Python `requests` library

## Installation

```bash
cd pg_embedding-gen
sudo bash scripts/install.sh
psql -d your_database -f sql/install.sql
```

## Supported APIs

Any OpenAI-compatible `/v1/embeddings` endpoint, including:

- BGE-M3 via vLLM, Xinference, etc. (1024 dimensions)
- OpenAI text-embedding-3-small (1536d) / text-embedding-3-large (3072d)
- Ollama with OpenAI-compatible endpoint
- Any other vLLM / TGI / local model server

## Full Changelog

See [CHANGELOG.md](CHANGELOG.md).

# pg_embedding-gen

A multi-model embedding generation extension for PostgreSQL 18+, generating text vector embeddings via SQL functions by calling any OpenAI-compatible `/v1/embeddings` API endpoint.

No C extension compilation required — uses PostgreSQL 18's `COPY FROM PROGRAM` mechanism.

## Features

- **Multi-model support** — Register and switch between embedding models via SQL
- **Auto-detect dimensions** — Vector dimensions detected automatically on first use
- **Flexible configuration** — API URL and model ID configurable per profile, inline, or via database config
- **Any OpenAI-compatible API** — BGE-M3, OpenAI, Ollama, vLLM, Xinference, etc.
- **Shell-safe** — Base64-encoded input prevents injection and encoding issues
- **Retry with backoff** — Automatic retry on transient failures
- **Health check & validation** — Built-in API connectivity testing and vector validation
- **Similarity functions** — Cosine similarity and Euclidean distance
- **Logging & statistics** — Request logging, stats, and error tracking

## Requirements

- PostgreSQL 18+
- Python 3.6+
- Python `requests` library

## Quick Start

```bash
# Install files
sudo bash scripts/install.sh

# Create database functions
psql -d your_database -f sql/install.sql

# Generate an embedding
psql -d your_database -c "SELECT embedding_generate('Hello world');"
```

## Usage

### Generate Embeddings

```sql
-- Default model profile
SELECT embedding_generate('your text');

-- Named model profile
SELECT embedding_generate('your text', 'bge-m3');

-- Inline model_id + api_url (no registration needed)
SELECT embedding_generate_model(
    'your text',
    'text-embedding-bge-m3',
    'http://10.10.10.1:12345/v1/embeddings'
);
```

### Model Profile Management

```sql
-- List registered models
SELECT * FROM embedding_list_models();

-- Register a new model
SELECT embedding_register_model(
    'openai-small',                         -- profile name
    'https://api.openai.com/v1/embeddings', -- API URL
    'text-embedding-3-small',               -- model ID
    true,                                   -- set as default
    'OpenAI small embedding model'          -- description
);

-- Test a model (auto-detects dimensions)
SELECT * FROM embedding_test_model('openai-small');

-- Auto-detect dimensions for all registered models
SELECT * FROM embedding_detect_dimensions();

-- Set default model
SELECT embedding_set_default_model('openai-small');

-- Drop a model profile
SELECT embedding_drop_model('openai-small');
```

### Similarity

```sql
SELECT embedding_cosine_similarity(
    embedding_generate('The cat sat on the mat'),
    embedding_generate('A kitten was sitting on a rug')
);
```

### Health Check

```sql
-- Check default model
SELECT * FROM embedding_health_check();

-- Check specific model
SELECT * FROM embedding_health_check('bge-m3');
```

### Batch Generation

```sql
SELECT embedding_generate_batch(ARRAY['cat', 'dog', 'bird']);
SELECT embedding_generate_batch(ARRAY['cat', 'dog'], 'bge-m3');
```

### Update Table Column

```sql
UPDATE documents
SET embedding = embedding_generate(text)
WHERE embedding IS NULL;
```

## Three Call Modes

| Mode | Function | Use When |
|------|----------|----------|
| Default profile | `embedding_generate(text)` | Simplest, uses default model |
| Named profile | `embedding_generate(text, profile)` | Use a specific registered model |
| Inline | `embedding_generate_model(text, model_id, api_url)` | One-off call, no registration |

## Supported Models

Any OpenAI-compatible `/v1/embeddings` endpoint:

| Model | Dimensions | Endpoint |
|-------|-----------|----------|
| BGE-M3 | 1024 | vLLM / Xinference |
| text-embedding-3-small | 1536 | OpenAI |
| text-embedding-3-large | 3072 | OpenAI |
| nomic-embed-text | 768 | Ollama |
| mxbai-embed-large | 1024 | Ollama |

## Troubleshooting

```bash
# Test proxy directly
/usr/local/pgsql/lib/embedding_wrapper.sh --text 'Hello world'

# Check Python dependency
python3 -c "import requests; print(requests.__version__)"
```

## File Configuration (fallback)

`/etc/pg_embedding-gen/config.json`:

```json
{
    "api_url": "http://10.10.10.1:12345/v1/embeddings",
    "model": "text-embedding-bge-m3",
    "timeout": 30,
    "max_retries": 3,
    "log_level": "WARNING",
    "log_file": ""
}
```

## Project Structure

```
pg_embedding-gen/
├── lib/
│   ├── embedding_proxy.py      # Python proxy calling the API
│   └── embedding_wrapper.sh    # Shell wrapper for COPY FROM PROGRAM
├── sql/
│   └── install.sql             # SQL functions, tables, and management
├── scripts/
│   └── install.sh              # Installation script
├── config.example.json         # Example configuration
├── CHANGELOG.md
├── LICENSE
├── NOTICE
├── README.md
└── RELEASE_NOTES.md
```

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Author

yhw (Haiwen Yin)

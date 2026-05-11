# pg_embedding-gen - PostgreSQL Embedding Generation Extension

A text vector embedding generation tool for PostgreSQL, implemented via COPY FROM PROGRAM mechanism without requiring compiled C extensions.

## Version

v0.2.0

## Features

- ✅ No C extension compilation required, uses PostgreSQL 18's COPY FROM PROGRAM mechanism
- ✅ Supports multiple embedding models (OpenAI, Ollama, local models, etc.)
- ✅ Generate vectors directly via SQL functions
- ✅ Flexible configuration, easy to deploy
- ✅ Supports batch processing and asynchronous generation
- ✅ Comprehensive error handling and logging

## System Requirements

- PostgreSQL 18 or higher
- Python 3.8 or higher
- Required Python libraries (see requirements.txt)

## Installation

### Quick Install

```bash
# Extract the archive
unzip pg-embedding-gen-by-yhw-v0.2.0.zip

# Change directory
cd pg-embedding-gen-by-yhw-v0.2.0/pg_embedding-gen

# Run installation script
sudo bash scripts/install.sh
```

### Manual Installation

1. Copy files to PostgreSQL extension directory:
```bash
sudo cp lib/embedding_proxy.py /usr/local/pgsql/lib/
sudo cp lib/embedding_wrapper.sh /usr/local/pgsql/lib/
sudo chmod +x /usr/local/pgsql/lib/embedding_wrapper.sh
```

2. Install Python dependencies:
```bash
pip3 install -r requirements.txt
```

3. Configure config.yaml:
```bash
cp config.example.yaml /etc/pg_embedding-gen/config.yaml
# Edit config file, set your embedding model parameters
sudo vim /etc/pg_embedding-gen/config.yaml
```

4. Create database functions:
```bash
psql -d your_database -f sql/install.sql
```

## Usage Examples

### Generate Embedding Vectors

```sql
-- Single text generation
SELECT embedding_generate('your text content');

-- Use specified model
SELECT embedding_generate('your text content', 'openai-text-embedding-3-small');

-- Batch generation
SELECT id, text, embedding_generate(text) as vector 
FROM documents 
WHERE embedding IS NULL;
```

### Update Vector Column in Table

```sql
-- Update existing table
UPDATE documents 
SET embedding = embedding_generate(text)
WHERE embedding IS NULL;

-- Use WHERE clause for batch update
UPDATE documents 
SET embedding = embedding_generate(text)
WHERE id > 100 AND id <= 200;
```

### Check Embedding Status

```sql
-- View embedding statistics
SELECT * FROM embedding_stats();

-- View recent errors
SELECT * FROM embedding_errors() ORDER BY created_at DESC LIMIT 10;
```

## Configuration

Configuration file located at `/etc/pg_embedding-gen/config.yaml`, supports the following options:

```yaml
# Default model
default_model: "openai-text-embedding-3-small"

# OpenAI configuration
openai:
  api_key: "your-api-key"
  base_url: "https://api.openai.com/v1"
  timeout: 30

# Ollama configuration
ollama:
  base_url: "http://localhost:11434"
  timeout: 60

# General configuration
batch_size: 100
max_retries: 3
log_level: "INFO"
```

For detailed configuration, see `docs/model-configuration.md`.

## Supported Models

- OpenAI: text-embedding-3-small, text-embedding-3-large
- Ollama: nomic-embed-text, all-minilm, mxbai-embed-large
- Local models: sentence-transformers, etc.

For more model information, see `docs/model-configuration.md`.

## Performance Optimization

### Batch Processing

Use batch updates for better performance:

```sql
-- Batch update (1000 rows per batch)
DO $$
DECLARE
  batch_size INT := 1000;
  offset INT := 0;
  updated INT;
BEGIN
  LOOP
    UPDATE documents 
    SET embedding = embedding_generate(text)
    WHERE id > offset 
      AND id <= offset + batch_size
      AND embedding IS NULL;
    
    GET DIAGNOSTICS updated = ROW_COUNT;
    
    RAISE NOTICE 'Updated % rows from offset %', updated, offset;
    
    EXIT WHEN updated = 0;
    offset := offset + batch_size;
  END LOOP;
END $$;
```

### Index Optimization

Create indexes for vector columns:

```sql
-- If pgvector extension is installed
CREATE INDEX ON documents USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);
```

## Troubleshooting

### Permission Issues

Ensure PostgreSQL user has permission to execute scripts:

```bash
sudo chown postgres:postgres /usr/local/pgsql/lib/embedding_wrapper.sh
sudo chmod 755 /usr/local/pgsql/lib/embedding_wrapper.sh
```

### Python Module Not Found

Ensure Python dependencies are installed:

```bash
pip3 install openai requests pyyaml
```

### View Logs

View embedding proxy logs:

```bash
tail -f /var/log/pg_embedding-gen.log
```

## Contributing

Issues and Pull Requests are welcome!

## License

MIT License - see LICENSE file for details

## Author

yhw (Haiwen Yin)

## Changelog

See CHANGELOG.md for details

## Documentation

- [Installation Guide](docs/setup-guide.md)
- [Model Configuration](docs/model-configuration.md)

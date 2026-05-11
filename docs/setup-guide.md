# pg_embedding-gen Installation Guide

This guide will help you install and configure pg_embedding-gen on your PostgreSQL system.

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Installation Steps](#installation-steps)
3. [Configuration](#configuration)
4. [Verification](#verification)
5. [Uninstallation](#uninstallation)
6. [FAQ](#faq)

## System Requirements

### PostgreSQL

- **Version**: PostgreSQL 18 or higher
- **Reason**: Uses COPY FROM PROGRAM mechanism, requires PostgreSQL 18+

Check PostgreSQL version:
```bash
psql --version
```

### Python

- **Version**: Python 3.8 or higher
- **Required libraries**: openai, requests, pyyaml

Check Python version:
```bash
python3 --version
```

### Other Requirements

- Sufficient disk space (depends on model size)
- Write permission to PostgreSQL configuration directory
- Network connection (if using remote APIs)

## Installation Steps

### Method 1: Automatic Installation (Recommended)

Use the provided installation script:

```bash
# 1. Extract archive
unzip pg-embedding-gen-by-yhw-v0.2.0.zip

# 2. Change directory
cd pg-embedding-gen-by-yhw-v0.2.0/pg_embedding-gen

# 3. Run installation script
sudo bash scripts/install.sh
```

The installation script will automatically:
- Check system requirements
- Create necessary directories
- Copy files to correct locations
- Set file permissions
- Install Python dependencies
- Create configuration file

### Method 2: Manual Installation

If you need custom installation paths or encounter permission issues, install manually:

#### 1. Prepare Directories

```bash
sudo mkdir -p /usr/local/pgsql/lib
sudo mkdir -p /etc/pg_embedding-gen
sudo mkdir -p /var/log
```

#### 2. Copy Files

```bash
# Copy script files
sudo cp lib/embedding_proxy.py /usr/local/pgsql/lib/
sudo cp lib/embedding_wrapper.sh /usr/local/pgsql/lib/

# Set permissions
sudo chmod 644 /usr/local/pgsql/lib/embedding_proxy.py
sudo chmod 755 /usr/local/pgsql/lib/embedding_wrapper.sh
```

#### 3. Create Configuration File

```bash
sudo cp config.example.yaml /etc/pg_embedding-gen/config.yaml
```

#### 4. Install Python Dependencies

```bash
# Using pip
pip3 install openai requests pyyaml

# Or using system package manager (e.g., apt)
sudo apt-get install python3-pip python3-openai python3-requests python3-yaml
```

#### 5. Create Log File

```bash
sudo touch /var/log/pg_embedding-gen.log
sudo chmod 644 /var/log/pg_embedding-gen.log
sudo chown postgres:postgres /var/log/pg_embedding-gen.log
```

#### 6. Create Functions in Database

```bash
psql -d your_database -f sql/install.sql
```

## Configuration

### Edit Configuration File

Edit `/etc/pg_embedding-gen/config.yaml`:

```bash
sudo vim /etc/pg_embedding-gen/config.yaml
```

### Configure OpenAI

```yaml
openai:  
  api_key: "sk-you...here"  # Replace with your API key
  base_url: "https://api.openai.com/v1"  # Optional, use custom proxy
  timeout: 30  # Timeout (seconds)
```

### Configure Ollama

```yaml
ollama:
  base_url: "http://localhost:11434"  # Ollama service address
  timeout: 60  # Timeout (seconds)
```

### Configure Local Models

```yaml
local:
  model_path: "/path/to/model"  # Model file path
  device: "cpu"  # Device to use: cpu or cuda
  timeout: 60
```

### General Configuration

```yaml
general:
  batch_size: 100  # Batch processing size
  max_text_length: 8192  # Maximum text length
  log_level: "INFO"  # Log level: DEBUG, INFO, WARNING, ERROR
  log_file: "/var/log/pg_embedding-gen.log"  # Log file path
```

For more configuration options, see [model-configuration.md](model-configuration.md).

## Verification

### 1. Check Files

```bash
# Check if script files exist
ls -la /usr/local/pgsql/lib/embedding_wrapper.sh
ls -la /usr/local/pgsql/lib/embedding_proxy.py

# Check configuration file
ls -la /etc/pg_embedding-gen/config.yaml
```

### 2. Test Python Script

```bash
# Test Python proxy script
python3 /usr/local/pgsql/lib/embedding_proxy.py \
  --text "test text" \
  --config /etc/pg_embedding-gen/config.yaml
```

### 3. Test Shell Wrapper Script

```bash
# Test shell wrapper script
/usr/local/pgsql/lib/embedding_wrapper.sh \
  --text "test text" \
  --config /etc/pg_embedding-gen/config.yaml
```

### 4. Test in PostgreSQL

```sql
-- Connect to database
\c your_database

-- Test basic functionality
SELECT embedding_generate('test text');

-- Test with specified model
SELECT embedding_generate('test text', 'openai-text-embedding-3-small');

-- Check result dimensions
SELECT array_length(embedding_generate('test text'), 1);
```

### 5. Test Similarity Calculation

```sql
-- Calculate similarity between two texts
WITH texts AS (
  SELECT 
    embedding_generate('cat is an animal') as vec1,
    embedding_generate('dog is an animal') as vec2
)
SELECT embedding_cosine_similarity(vec1, vec2) as similarity
FROM texts;
```

## Uninstallation

### Remove Functions from Database

```sql
DROP FUNCTION IF EXISTS embedding_generate(text);
DROP FUNCTION IF EXISTS embedding_generate_model(text, text);
DROP FUNCTION IF EXISTS embedding_generate_batch(text[], text);
DROP FUNCTION IF EXISTS embedding_cosine_similarity(float8[], float8[]);
DROP FUNCTION IF EXISTS embedding_euclidean_distance(float8[], float8[]);
DROP FUNCTION IF EXISTS embedding_stats();
DROP FUNCTION IF EXISTS embedding_errors(int);
DROP FUNCTION IF EXISTS embedding_cleanup_logs(int);

-- Drop log table
DROP TABLE IF EXISTS embedding_logs;
```

### Remove Files from System

```bash
# Delete script files
sudo rm /usr/local/pgsql/lib/embedding_proxy.py
sudo rm /usr/local/pgsql/lib/embedding_wrapper.sh

# Delete configuration (optional)
sudo rm /etc/pg_embedding-gen/config.yaml
sudo rmdir /etc/pg_embedding-gen

# Delete logs (optional)
sudo rm /var/log/pg_embedding-gen.log
```

## FAQ

### Q1: Installation script reports insufficient permissions

**A**: Ensure you run the installation script with sudo:
```bash
sudo bash scripts/install.sh
```

### Q2: PostgreSQL version too low

**A**: pg_embedding-gen requires PostgreSQL 18 or higher to support COPY FROM PROGRAM. Please upgrade PostgreSQL or use an older version (v0.1.0).

### Q3: Python module not found

**A**: Install Python dependencies manually:
```bash
pip3 install openai requests pyyaml
```

### Q4: OpenAI API connection fails

**A**: Check:
1. API key is correct
2. Network connection is working
3. If proxy server is needed
4. base_url in configuration file is correct

### Q5: Timeout when generating embeddings

**A**: Increase timeout setting in configuration file:
```yaml
openai:
  timeout: 60  # Increase to 60 seconds
```

### Q6: Function executes but returns no results

**A**: Check PostgreSQL logs:
```bash
# View PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-18-main.log
```

View embedding proxy logs:
```bash
sudo tail -f /var/log/pg_embedding-gen.log
```

### Q7: Batch updates are slow

**A**: Use batch processing (see performance optimization section in README.md), or increase batch_size in configuration file.

### Q8: Permission errors

**A**: Ensure file permissions are correct:
```bash
sudo chown postgres:postgres /usr/local/pgsql/lib/embedding_wrapper.sh
sudo chmod 755 /usr/local/pgsql/lib/embedding_wrapper.sh
sudo chown postgres:postgres /var/log/pg_embedding-gen.log
sudo chmod 644 /var/log/pg_embedding-gen.log
```

## Getting Help

If you encounter other issues:

1. Check log files
2. View PostgreSQL error logs
3. See [README.md](../README.md) for more information
4. Submit an issue to the project repository

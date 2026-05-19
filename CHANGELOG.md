# Changelog

All notable changes to pg_embedding-gen are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-05-17

First stable release. Complete rewrite from the original C extension to a pure SQL + Python approach using PostgreSQL 18's `COPY FROM PROGRAM` mechanism.

### Added

- **Multi-model profile system** — `embedding_model_profiles` table to register multiple models with different API URLs and model IDs
- `embedding_register_model()` — Register new model profiles via SQL
- `embedding_list_models()` — List all registered model profiles with dimensions
- `embedding_set_default_model()` — Switch the default model profile
- `embedding_drop_model()` — Remove a model profile
- `embedding_test_model()` — Test a model profile: call API, auto-detect dimensions, return status
- `embedding_detect_dimensions()` — Auto-detect dimensions for one or all model profiles
- `embedding_dimension_cache` table — Caches auto-detected dimensions per unique model+url combination
- `embedding_generate(text, profile_name)` overloaded function — Generate embedding using a named model profile
- `embedding_generate_model(text, model_id, api_url)` — Generate embedding with inline model_id and api_url (no registration needed)
- Base64-encoded text input for shell-safe special character handling
- Automatic retry with exponential backoff on transient failures (configurable)
- In-database configuration table (`pg_embedding_gen_config`) with SQL management functions
- `embedding_health_check()` / `embedding_health_check(profile)` — API connectivity testing with response time
- `embedding_validate_vector()` — Vector validation (dimension, NaN, Infinity, norm)
- `embedding_set_config()` / `embedding_get_config()` — Runtime configuration
- `embedding_cosine_similarity()` / `embedding_euclidean_distance()` — Similarity and distance functions
- Vector dimension auto-detection and validation (range: 16–8192)
- `embedding_generate_batch()` — Batch embedding generation
- `embedding_stats()` / `embedding_errors()` / `embedding_cleanup_logs()` — Logging and statistics
- `--api-url` parameter in wrapper and proxy scripts for per-call endpoint selection
- JSON config file as fallback (`/etc/pg_embedding-gen/config.json`)

### Changed

- Replaced C extension with pure SQL + Python approach (no compilation needed)
- Replaced `openai` / `pyyaml` Python dependencies with `requests` only
- Python 3.6+ compatibility (previously required 3.8+ due to openai library)
- API-calling functions correctly marked `VOLATILE` (were incorrectly `IMMUTABLE`)
- Shell wrapper uses `exec` instead of capturing output (cleaner process management)
- Error handling: proper WARNING + NULL instead of silent `[0.0]` fallback
- Default model configuration moved from flat config keys to `embedding_model_profiles` table

### Removed

- C extension (`pg_embedding_gen.c`, `pg_embedding_gen.so`) — replaced by SQL + Python
- `openai` Python library dependency
- `pyyaml` Python library dependency
- YAML config format (replaced with JSON)
- Hard-coded model prefix handling (`openai-`, `ollama-`)
- Local model stub (`_generate_local` returning `[0.0] * 768`)
- MIT license (changed to Apache 2.0)

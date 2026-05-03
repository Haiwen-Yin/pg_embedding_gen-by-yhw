-- Extension registration for pg_embedding_gen

-- Register the extension in PostgreSQL
CREATE EXTENSION IF NOT EXISTS pg_embedding_gen;

-- Verify extension is installed correctly
SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_embedding_gen';

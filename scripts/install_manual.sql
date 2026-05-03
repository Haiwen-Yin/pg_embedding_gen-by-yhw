-- pg-embedding-gen-by-yhw manual installation (if CREATE EXTENSION fails)
SET search_path TO public;

-- Register generate_embedding function using ABSOLUTE path to .so file
CREATE OR REPLACE FUNCTION public.generate_embedding(input_text text)
RETURNS float[] AS '/usr/local/pgsql/lib/pg-embedding-gen-by-yhw', 'generate_embedding'
IMMUTABLE STRICT
LANGUAGE C;

-- Register extension_version function  
CREATE OR REPLACE FUNCTION public.extension_version()
RETURNS text AS '/usr/local/pgsql/lib/pg-embedding-gen-by-yhw', 'extension_version'
STABLE
LANGUAGE C;

-- Test the functions
SELECT extension_version();
SELECT generate_embedding('Hello world');

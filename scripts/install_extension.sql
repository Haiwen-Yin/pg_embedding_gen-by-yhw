-- pg-embedding-gen-by-yhw extension installation script (for remote execution)
SET search_path TO public;

-- Register generate_embedding function from .so file
CREATE OR REPLACE FUNCTION public.generate_embedding(input_text text)
RETURNS float[] AS '\$libdir/pg-embedding-gen-by-yhw', 'generate_embedding'
IMMUTABLE STRICT
LANGUAGE C;

-- Register extension_version function  
CREATE OR REPLACE FUNCTION public.extension_version()
RETURNS text AS '\$libdir/pg-embedding-gen-by-yhw', 'extension_version'
STABLE
LANGUAGE C;

-- Test the functions
SELECT extension_version();
SELECT generate_embedding('Hello world');

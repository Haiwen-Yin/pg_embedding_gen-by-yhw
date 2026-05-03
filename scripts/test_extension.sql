-- pg_embedding_gen extension test suite
-- Run this to verify functionality after installation

-- Set search path
SET search_path TO public;

-- Test 1: Check version information
SELECT 'Test 1: Extension Version' as test_name,
       extension_version() as result
UNION ALL
SELECT 'Expected:', '1.0.0 (Configurable Models)';

-- Test 2: Generate embedding for short text
SELECT 'Test 2: Short Text Embedding' as test_name, 
       array_length(generate_embedding('hello'), 1) as dimensions;

-- Test 3: Generate embedding for longer text  
SELECT 'Test 3: Longer Text Embedding' as test_name,
       array_length(generate_embedding('This is a longer sentence to test the embedding generation properly'), 1) as dimensions;

-- Test 4: Check first few values of embedding
SELECT 'Test 4: Sample Values (First 5)' as test_name,
       (generate_embedding('test'))[1:5] as sample_values;

-- Test 5: Verify embedding is not all zeros
SELECT 'Test 5: Non-Zero Verification' as test_name,
       EXISTS(SELECT 1 FROM generate_embedding('test') WHERE value != 0) as has_nonzero;

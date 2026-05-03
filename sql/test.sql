-- pg_embedding_gen Extension Tests
-- Run after installing the extension

\echo '=== Testing pg_embedding_gen Extension ==='

-- Test 1: Check if extension is loaded
SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_embedding_gen';

-- Test 2: Generate embedding from text
\echo '--- Test 2: Generate Embedding ---'
SELECT generate_embedding('这是一个中文测试句子');

-- Test 3: Verify response format (should be JSON array of floats)
\echo '--- Test 3: Response Format Check ---'
SELECT length(generate_embedding('test')) > 100 AS has_substantial_vector;

-- Test 4: Generate multiple embeddings and compare similarity
\echo '--- Test 4: Similarity Calculation (MVP placeholder) ---'
SELECT vector_similarity(
    generate_embedding('hello world'),
    generate_embedding('hi there')
) AS similarity_score;

\echo '=== All tests completed ==='

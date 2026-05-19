-- pg_embedding-gen SQL Installation Script
-- Version: v1.0.0
-- Author: yhw (Haiwen Yin)
--
-- Multi-model embedding generation via PostgreSQL COPY FROM PROGRAM.
-- Supports any OpenAI-compatible /v1/embeddings API endpoint.
-- Dimensions are auto-detected on first use per model.

-- ============================================
-- Global configuration table
-- ============================================

CREATE TABLE IF NOT EXISTS pg_embedding_gen_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

INSERT INTO pg_embedding_gen_config (key, value, description) VALUES
    ('default_profile', 'bge-m3',
     'Name of the default model profile to use'),
    ('timeout', '30',
     'HTTP request timeout in seconds'),
    ('max_retries', '3',
     'Maximum retry attempts on transient failure'),
    ('log_level', 'WARNING',
     'Proxy log level: DEBUG/INFO/WARNING/ERROR'),
    ('log_file', '',
     'Proxy log file path (empty = stderr only)')
ON CONFLICT (key) DO NOTHING;

-- ============================================
-- Model profiles table
-- ============================================

CREATE TABLE IF NOT EXISTS embedding_model_profiles (
    name TEXT PRIMARY KEY,
    api_url TEXT NOT NULL,
    model_id TEXT NOT NULL,
    dimensions int,
    is_default boolean DEFAULT false,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

COMMENT ON TABLE embedding_model_profiles IS 'Registered embedding model profiles with connection info and auto-detected dimensions';

INSERT INTO embedding_model_profiles (name, api_url, model_id, dimensions, is_default, description) VALUES
    ('bge-m3',
     'http://10.10.10.1:12345/v1/embeddings',
     'text-embedding-bge-m3',
     NULL,
     true,
     'BGE-M3 multilingual embedding model (auto-detect dimensions)')
ON CONFLICT (name) DO NOTHING;

-- ============================================
-- Dimension cache table (auto-populated)
-- ============================================

CREATE TABLE IF NOT EXISTS embedding_dimension_cache (
    profile_name TEXT NOT NULL,
    model_id TEXT NOT NULL,
    api_url TEXT NOT NULL,
    dimensions int NOT NULL,
    detected_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (profile_name, model_id, api_url)
);

COMMENT ON TABLE embedding_dimension_cache IS 'Auto-detected embedding dimensions, populated on first call per unique model+url combination';
-- ============================================
-- Core embedding generation function
-- ============================================

CREATE OR REPLACE FUNCTION embedding_generate_model(
    input_text TEXT,
    model TEXT DEFAULT NULL,
    api_url TEXT DEFAULT NULL
)
RETURNS float8[]
LANGUAGE plpgsql
VOLATILE
AS $func$
DECLARE
    wrapper_path TEXT := '/usr/local/pgsql/lib/embedding_wrapper.sh';
    effective_model TEXT;
    effective_api_url TEXT;
    resolved_profile TEXT;
    cmd TEXT;
    result TEXT;
    vec float8[];
    dim int;
BEGIN
    IF input_text IS NULL OR input_text = '' THEN
        RAISE WARNING 'embedding_generate: input text is NULL or empty';
        RETURN NULL;
    END IF;

    IF api_url IS NOT NULL AND model IS NOT NULL THEN
        effective_api_url := api_url;
        effective_model := model;
        resolved_profile := '_inline';
    ELSIF model IS NOT NULL THEN
        SELECT p.api_url, p.model_id
        INTO effective_api_url, effective_model
        FROM embedding_model_profiles p
        WHERE p.name = model;

        IF effective_api_url IS NOT NULL THEN
            resolved_profile := model;
        ELSE
            effective_api_url := (SELECT value FROM pg_embedding_gen_config WHERE key = 'api_url');
            effective_model := model;
            resolved_profile := '_inline';
        END IF;

        IF effective_api_url IS NULL THEN
            RAISE WARNING 'embedding_generate: no api_url found for model profile "%"', model;
            RETURN NULL;
        END IF;
    ELSE
        SELECT p.api_url, p.model_id, p.name
        INTO effective_api_url, effective_model, resolved_profile
        FROM embedding_model_profiles p
        WHERE p.is_default = true
        LIMIT 1;

        IF effective_api_url IS NULL THEN
            SELECT p.api_url, p.model_id, p.name
            INTO effective_api_url, effective_model, resolved_profile
            FROM embedding_model_profiles p
            WHERE p.name = (SELECT value FROM pg_embedding_gen_config WHERE key = 'default_profile')
            LIMIT 1;
        END IF;

        IF effective_api_url IS NULL THEN
            RAISE WARNING 'embedding_generate: no default model profile configured';
            RETURN NULL;
        END IF;
    END IF;

    cmd := wrapper_path
        || ' --text ' || quote_literal(input_text)
        || ' --model ' || quote_literal(effective_model)
        || ' --api-url ' || quote_literal(effective_api_url);

    IF EXISTS (SELECT 1 FROM pg_embedding_gen_config WHERE key = 'log_file' AND value != '') THEN
        cmd := cmd || ' --log-file ' || quote_literal(
            (SELECT value FROM pg_embedding_gen_config WHERE key = 'log_file')
        );
        cmd := cmd || ' --log-level ' || quote_literal(
            COALESCE((SELECT value FROM pg_embedding_gen_config WHERE key = 'log_level'), 'WARNING')
        );
    END IF;

    DROP TABLE IF EXISTS _pg_emb_temp;
    CREATE TEMP TABLE _pg_emb_temp (vec_line TEXT) ON COMMIT DROP;

    EXECUTE 'COPY _pg_emb_temp FROM PROGRAM ' || quote_literal(cmd);

    SELECT vec_line INTO result FROM _pg_emb_temp LIMIT 1;

    IF result IS NULL OR result = '' OR result = 'ERROR' THEN
        RAISE WARNING 'embedding_generate: API call returned no valid result';
        RETURN NULL;
    END IF;

    vec := string_to_array(result, ',')::float8[];
    dim := array_length(vec, 1);

    IF dim IS NULL OR dim = 0 THEN
        RAISE WARNING 'embedding_generate: parsed vector has zero dimensions';
        RETURN NULL;
    END IF;

    IF dim < 16 OR dim > 8192 THEN
        RAISE WARNING 'embedding_generate: unexpected vector dimension %', dim;
        RETURN NULL;
    END IF;

    PERFORM embedding_cache_dimension(resolved_profile, effective_model, effective_api_url, dim);

    RETURN vec;
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'embedding_generate failed: %', SQLERRM;
        RETURN NULL;
END;
$func$;

-- ============================================
-- Convenience wrappers
-- ============================================

CREATE OR REPLACE FUNCTION embedding_generate(
    input_text TEXT DEFAULT NULL
)
RETURNS float8[]
LANGUAGE sql
VOLATILE
AS $$
    SELECT embedding_generate_model(input_text, NULL, NULL);
$$;

CREATE OR REPLACE FUNCTION embedding_generate(
    input_text TEXT,
    profile_name TEXT
)
RETURNS float8[]
LANGUAGE sql
VOLATILE
AS $$
    SELECT embedding_generate_model(input_text, profile_name, NULL);
$$;

-- ============================================
-- Batch embedding
-- ============================================

CREATE OR REPLACE FUNCTION embedding_generate_batch(
    texts TEXT[],
    profile_name TEXT DEFAULT NULL
)
RETURNS SETOF float8[]
LANGUAGE plpgsql
VOLATILE
AS $func$
DECLARE
    i int;
    vec float8[];
BEGIN
    FOR i IN 1..COALESCE(array_length(texts, 1), 0) LOOP
        vec := embedding_generate_model(texts[i], profile_name, NULL);
        IF vec IS NOT NULL THEN
            RETURN NEXT vec;
        END IF;
    END LOOP;
    RETURN;
END;
$func$;

-- ============================================
-- Dimension cache helper
-- ============================================

CREATE OR REPLACE FUNCTION embedding_cache_dimension(
    p_profile_name TEXT,
    p_model_id TEXT,
    p_api_url TEXT,
    p_dimensions int
)
RETURNS void
LANGUAGE sql
VOLATILE
AS $func$
    INSERT INTO embedding_dimension_cache (profile_name, model_id, api_url, dimensions, detected_at)
    VALUES (p_profile_name, p_model_id, p_api_url, p_dimensions, NOW())
    ON CONFLICT (profile_name, model_id, api_url)
    DO UPDATE SET dimensions = EXCLUDED.dimensions, detected_at = NOW();
$func$;
-- ============================================
-- Model profile management
-- ============================================

CREATE OR REPLACE FUNCTION embedding_register_model(
    p_name TEXT,
    p_api_url TEXT,
    p_model_id TEXT,
    p_is_default boolean DEFAULT false,
    p_description TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
AS $func$
DECLARE
    v_dim int;
BEGIN
    IF p_name IS NULL OR p_api_url IS NULL OR p_model_id IS NULL THEN
        RAISE EXCEPTION 'embedding_register_model: name, api_url, and model_id are required';
    END IF;

    IF p_is_default THEN
        UPDATE embedding_model_profiles SET is_default = false WHERE is_default = true;
    END IF;

    v_dim := (SELECT dimensions FROM embedding_dimension_cache
              WHERE profile_name = p_name AND model_id = p_model_id AND api_url = p_api_url
              LIMIT 1);

    INSERT INTO embedding_model_profiles (name, api_url, model_id, dimensions, is_default, description, updated_at)
    VALUES (p_name, p_api_url, p_model_id, v_dim, p_is_default, p_description, NOW())
    ON CONFLICT (name) DO UPDATE
    SET api_url = EXCLUDED.api_url,
        model_id = EXCLUDED.model_id,
        is_default = EXCLUDED.is_default,
        description = COALESCE(EXCLUDED.description, embedding_model_profiles.description),
        dimensions = COALESCE(v_dim, embedding_model_profiles.dimensions),
        updated_at = NOW();

    IF p_is_default THEN
        PERFORM embedding_set_config('default_profile', p_name);
    END IF;

    RETURN p_name;
END;
$func$;

CREATE OR REPLACE FUNCTION embedding_list_models()
RETURNS TABLE (
    name TEXT,
    api_url TEXT,
    model_id TEXT,
    dimensions int,
    is_default boolean,
    description TEXT,
    updated_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE sql
VOLATILE
AS $func$
    SELECT name, api_url, model_id, dimensions, is_default, description, updated_at
    FROM embedding_model_profiles
    ORDER BY is_default DESC, name;
$func$;

CREATE OR REPLACE FUNCTION embedding_set_default_model(
    p_name TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
AS $func$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM embedding_model_profiles WHERE name = p_name) THEN
        RAISE EXCEPTION 'embedding_set_default_model: model profile "%" does not exist', p_name;
    END IF;

    UPDATE embedding_model_profiles SET is_default = false WHERE is_default = true;
    UPDATE embedding_model_profiles SET is_default = true, updated_at = NOW() WHERE name = p_name;
    PERFORM embedding_set_config('default_profile', p_name);

    RETURN p_name;
END;
$func$;

CREATE OR REPLACE FUNCTION embedding_drop_model(
    p_name TEXT
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
AS $func$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM embedding_model_profiles WHERE name = p_name) THEN
        RAISE NOTICE 'embedding_drop_model: model profile "%" does not exist', p_name;
        RETURN false;
    END IF;

    DELETE FROM embedding_dimension_cache WHERE profile_name = p_name;
    DELETE FROM embedding_model_profiles WHERE name = p_name;

    IF EXISTS (SELECT 1 FROM pg_embedding_gen_config WHERE key = 'default_profile' AND value = p_name) THEN
        UPDATE pg_embedding_gen_config SET value = '', updated_at = NOW() WHERE key = 'default_profile';
        UPDATE embedding_model_profiles SET is_default = true
        WHERE name = (SELECT name FROM embedding_model_profiles LIMIT 1)
        AND NOT EXISTS (SELECT 1 FROM embedding_model_profiles WHERE is_default = true);
    END IF;

    RETURN true;
END;
$func$;

-- ============================================
-- Model testing & dimension auto-detection
-- ============================================

CREATE OR REPLACE FUNCTION embedding_test_model(
    p_name TEXT
)
RETURNS TABLE (
    status TEXT,
    model_id TEXT,
    api_url TEXT,
    vector_dimension int,
    response_ms int,
    sample_value float8
)
LANGUAGE plpgsql
VOLATILE
AS $func$
DECLARE
    v_api_url TEXT;
    v_model_id TEXT;
    start_ts TIMESTAMP WITH TIME ZONE;
    end_ts TIMESTAMP WITH TIME ZONE;
    vec float8[];
    dim int;
    elapsed_ms int;
BEGIN
    SELECT p.api_url, p.model_id INTO v_api_url, v_model_id
    FROM embedding_model_profiles p
    WHERE p.name = p_name;

    IF v_api_url IS NULL THEN
        RETURN QUERY SELECT
            'NOT_FOUND'::TEXT,
            p_name,
            NULL::TEXT,
            NULL::int,
            NULL::int,
            NULL::float8;
        RETURN;
    END IF;

    start_ts := clock_timestamp();
    vec := embedding_generate_model('embedding dimension test probe', v_model_id, v_api_url);
    end_ts := clock_timestamp();

    IF vec IS NULL THEN
        RETURN QUERY SELECT
            'ERROR'::TEXT,
            v_model_id,
            v_api_url,
            NULL::int,
            NULL::int,
            NULL::float8;
        RETURN;
    END IF;

    dim := array_length(vec, 1);
    elapsed_ms := extract(epoch from (end_ts - start_ts)) * 1000;

    UPDATE embedding_model_profiles
    SET dimensions = dim, updated_at = NOW()
    WHERE name = p_name AND (dimensions IS NULL OR dimensions != dim);

    PERFORM embedding_cache_dimension(p_name, v_model_id, v_api_url, dim);

    RETURN QUERY SELECT
        'OK'::TEXT,
        v_model_id,
        v_api_url,
        dim,
        elapsed_ms,
        vec[1];
END;
$func$;

CREATE OR REPLACE FUNCTION embedding_detect_dimensions(
    p_name TEXT DEFAULT NULL
)
RETURNS TABLE (
    profile_name TEXT,
    model_id TEXT,
    dimensions int,
    response_ms int
)
LANGUAGE plpgsql
VOLATILE
AS $func$
DECLARE
    v_record RECORD;
    start_ts TIMESTAMP WITH TIME ZONE;
    end_ts TIMESTAMP WITH TIME ZONE;
    vec float8[];
    dim int;
    elapsed_ms int;
BEGIN
    FOR v_record IN
        SELECT p.name, p.api_url, p.model_id
        FROM embedding_model_profiles p
        WHERE p_name IS NULL OR p.name = p_name
        ORDER BY p.is_default DESC, p.name
    LOOP
        start_ts := clock_timestamp();
        vec := embedding_generate_model('dimension detection probe', v_record.model_id, v_record.api_url);
        end_ts := clock_timestamp();

        IF vec IS NOT NULL THEN
            dim := array_length(vec, 1);
            elapsed_ms := extract(epoch from (end_ts - start_ts)) * 1000;

            UPDATE embedding_model_profiles
            SET dimensions = dim, updated_at = NOW()
            WHERE name = v_record.name;

            PERFORM embedding_cache_dimension(v_record.name, v_record.model_id, v_record.api_url, dim);

            profile_name := v_record.name;
            model_id := v_record.model_id;
            dimensions := dim;
            response_ms := elapsed_ms;
            RETURN NEXT;
        ELSE
            profile_name := v_record.name;
            model_id := v_record.model_id;
            dimensions := NULL;
            response_ms := NULL;
            RETURN NEXT;
        END IF;
    END LOOP;
    RETURN;
END;
$func$;

-- ============================================
-- Similarity / distance functions
-- ============================================

CREATE OR REPLACE FUNCTION embedding_cosine_similarity(
    vec1 float8[],
    vec2 float8[]
)
RETURNS float8
LANGUAGE plpgsql
IMMUTABLE
STRICT
AS $func$
DECLARE
    dot_product float8 := 0;
    norm1 float8 := 0;
    norm2 float8 := 0;
    i int;
    n int;
BEGIN
    n := array_length(vec1, 1);
    IF n IS NULL OR n != array_length(vec2, 1) THEN
        RAISE WARNING 'embedding_cosine_similarity: dimension mismatch';
        RETURN NULL;
    END IF;

    FOR i IN 1..n LOOP
        dot_product := dot_product + vec1[i] * vec2[i];
        norm1 := norm1 + vec1[i] * vec1[i];
        norm2 := norm2 + vec2[i] * vec2[i];
    END LOOP;

    IF norm1 = 0 OR norm2 = 0 THEN
        RETURN NULL;
    END IF;

    RETURN dot_product / (sqrt(norm1) * sqrt(norm2));
END;
$func$;

CREATE OR REPLACE FUNCTION embedding_euclidean_distance(
    vec1 float8[],
    vec2 float8[]
)
RETURNS float8
LANGUAGE plpgsql
IMMUTABLE
STRICT
AS $func$
DECLARE
    distance float8 := 0;
    i int;
    n int;
BEGIN
    n := array_length(vec1, 1);
    IF n IS NULL OR n != array_length(vec2, 1) THEN
        RAISE WARNING 'embedding_euclidean_distance: dimension mismatch';
        RETURN NULL;
    END IF;

    FOR i IN 1..n LOOP
        distance := distance + power(vec1[i] - vec2[i], 2);
    END LOOP;

    RETURN sqrt(distance);
END;
$func$;

-- ============================================
-- Configuration management
-- ============================================

CREATE OR REPLACE FUNCTION embedding_set_config(
    p_key TEXT,
    p_value TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
AS $func$
BEGIN
    IF p_key IS NULL OR p_value IS NULL THEN
        RAISE EXCEPTION 'embedding_set_config: key and value must not be NULL';
    END IF;

    INSERT INTO pg_embedding_gen_config (key, value, updated_at)
    VALUES (p_key, p_value, NOW())
    ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value, updated_at = NOW();

    RETURN p_value;
END;
$func$;

CREATE OR REPLACE FUNCTION embedding_get_config(
    p_key TEXT DEFAULT NULL
)
RETURNS TABLE (key TEXT, value TEXT, description TEXT)
LANGUAGE sql
VOLATILE
AS $func$
    SELECT key, value, description
    FROM pg_embedding_gen_config
    WHERE p_key IS NULL OR key = p_key
    ORDER BY key;
$func$;

-- ============================================
-- Health check & validation
-- ============================================

CREATE OR REPLACE FUNCTION embedding_health_check(
    p_profile_name TEXT
)
RETURNS TABLE (
    status TEXT,
    model TEXT,
    api_url TEXT,
    vector_dimension int,
    response_ms int
)
LANGUAGE plpgsql
VOLATILE
AS $func$
DECLARE
    v_model TEXT;
    v_api_url TEXT;
    v_profile TEXT;
    start_ts TIMESTAMP WITH TIME ZONE;
    end_ts TIMESTAMP WITH TIME ZONE;
    vec float8[];
    dim int;
    elapsed_ms int;
BEGIN
    IF p_profile_name IS NOT NULL THEN
        SELECT p.model_id, p.api_url INTO v_model, v_api_url
        FROM embedding_model_profiles p
        WHERE p.name = p_profile_name;
        v_profile := p_profile_name;
    ELSE
        SELECT p.model_id, p.api_url, p.name INTO v_model, v_api_url, v_profile
        FROM embedding_model_profiles p
        WHERE p.is_default = true
        LIMIT 1;

        IF v_api_url IS NULL THEN
            SELECT p.model_id, p.api_url, p.name INTO v_model, v_api_url, v_profile
            FROM embedding_model_profiles p
            WHERE p.name = (SELECT value FROM pg_embedding_gen_config WHERE key = 'default_profile')
            LIMIT 1;
        END IF;
    END IF;

    IF v_api_url IS NULL THEN
        RETURN QUERY SELECT
            'NO_MODEL'::TEXT,
            NULL::TEXT,
            NULL::TEXT,
            NULL::int,
            NULL::int;
        RETURN;
    END IF;

    start_ts := clock_timestamp();
    vec := embedding_generate_model('health check test', v_model, v_api_url);
    end_ts := clock_timestamp();

    IF vec IS NULL THEN
        RETURN QUERY SELECT
            'ERROR'::TEXT,
            v_model,
            v_api_url,
            NULL::int,
            NULL::int;
        RETURN;
    END IF;

    dim := array_length(vec, 1);
    elapsed_ms := extract(epoch from (end_ts - start_ts)) * 1000;

    UPDATE embedding_model_profiles
    SET dimensions = dim, updated_at = NOW()
    WHERE name = v_profile AND (dimensions IS NULL OR dimensions != dim);

    PERFORM embedding_cache_dimension(v_profile, v_model, v_api_url, dim);

    RETURN QUERY SELECT
        'OK'::TEXT,
        v_model,
        v_api_url,
        dim,
        elapsed_ms;
END;
$func$;

CREATE OR REPLACE FUNCTION embedding_health_check()
RETURNS TABLE (
    status TEXT,
    model TEXT,
    api_url TEXT,
    vector_dimension int,
    response_ms int
)
LANGUAGE sql
VOLATILE
AS $$
    SELECT * FROM embedding_health_check(NULL::TEXT);
$$;

CREATE OR REPLACE FUNCTION embedding_validate_vector(
    vec float8[],
    expected_dim int DEFAULT NULL
)
RETURNS TABLE (
    is_valid boolean,
    dimension int,
    has_nan boolean,
    has_inf boolean,
    norm float8
)
LANGUAGE plpgsql
IMMUTABLE
AS $func$
DECLARE
    dim int;
    v_has_nan boolean := false;
    v_has_inf boolean := false;
    v_norm float8 := 0;
    i int;
BEGIN
    IF vec IS NULL THEN
        RETURN QUERY SELECT false, NULL::int, false, false, NULL::float8;
        RETURN;
    END IF;

    dim := array_length(vec, 1);

    IF dim IS NULL OR dim = 0 THEN
        RETURN QUERY SELECT false, 0, false, false, 0.0;
        RETURN;
    END IF;

    FOR i IN 1..dim LOOP
        IF vec[i] = 'NaN'::float8 THEN v_has_nan := true; END IF;
        IF vec[i] = 'Infinity'::float8 OR vec[i] = '-Infinity'::float8 THEN
            v_has_inf := true;
        END IF;
        v_norm := v_norm + vec[i] * vec[i];
    END LOOP;

    v_norm := sqrt(v_norm);

    RETURN QUERY SELECT
        (NOT v_has_nan AND NOT v_has_inf
         AND (expected_dim IS NULL OR dim = expected_dim))::boolean,
        dim,
        v_has_nan,
        v_has_inf,
        v_norm;
END;
$func$;
-- ============================================
-- Logging table & functions
-- ============================================

CREATE TABLE IF NOT EXISTS embedding_logs (
    id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    profile_name TEXT,
    model TEXT,
    text_length int,
    vector_dimension int,
    elapsed_ms int,
    status TEXT NOT NULL,
    error_message TEXT
);

CREATE INDEX IF NOT EXISTS idx_embedding_logs_status
    ON embedding_logs (status);
CREATE INDEX IF NOT EXISTS idx_embedding_logs_created_at
    ON embedding_logs (created_at);

CREATE OR REPLACE FUNCTION embedding_log(
    p_profile_name TEXT,
    p_model TEXT,
    p_text_length int,
    p_vector_dimension int,
    p_elapsed_ms int,
    p_status TEXT,
    p_error_message TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE sql
VOLATILE
AS $func$
    INSERT INTO embedding_logs (profile_name, model, text_length, vector_dimension, elapsed_ms, status, error_message)
    VALUES (p_profile_name, p_model, p_text_length, p_vector_dimension, p_elapsed_ms, p_status, p_error_message);
$func$;

CREATE OR REPLACE FUNCTION embedding_stats()
RETURNS TABLE (
    total_requests bigint,
    successful_requests bigint,
    failed_requests bigint,
    most_used_model TEXT,
    avg_vector_dimension float8,
    avg_elapsed_ms float8
)
LANGUAGE sql
VOLATILE
AS $func$
    SELECT
        COUNT(*) AS total_requests,
        COUNT(*) FILTER (WHERE status = 'success') AS successful_requests,
        COUNT(*) FILTER (WHERE status = 'error') AS failed_requests,
        (SELECT model FROM embedding_logs
         WHERE status = 'success'
         GROUP BY model
         ORDER BY COUNT(*) DESC
         LIMIT 1) AS most_used_model,
        AVG(vector_dimension) FILTER (WHERE status = 'success') AS avg_vector_dimension,
        AVG(elapsed_ms) FILTER (WHERE status = 'success') AS avg_elapsed_ms
    FROM embedding_logs;
$func$;

CREATE OR REPLACE FUNCTION embedding_errors(
    limit_count int DEFAULT 10
)
RETURNS TABLE (
    created_at TIMESTAMP WITH TIME ZONE,
    profile_name TEXT,
    model TEXT,
    error_message TEXT
)
LANGUAGE sql
VOLATILE
AS $func$
    SELECT created_at, profile_name, model, error_message
    FROM embedding_logs
    WHERE status = 'error'
    ORDER BY created_at DESC
    LIMIT limit_count;
$func$;

CREATE OR REPLACE FUNCTION embedding_cleanup_logs(
    days_to_keep int DEFAULT 30
)
RETURNS bigint
LANGUAGE sql
VOLATILE
AS $func$
    WITH deleted AS (
        DELETE FROM embedding_logs
        WHERE created_at < NOW() - (days_to_keep || ' days')::interval
        RETURNING 1
    )
    SELECT COUNT(*) FROM deleted;
$func$;

-- ============================================
-- Comments
-- ============================================

COMMENT ON TABLE pg_embedding_gen_config IS 'Global configuration for pg_embedding-gen extension';
COMMENT ON TABLE embedding_model_profiles IS 'Registered embedding model profiles with connection info and auto-detected dimensions';
COMMENT ON TABLE embedding_dimension_cache IS 'Auto-detected embedding dimensions, populated on first call per unique model+url combination';

COMMENT ON FUNCTION embedding_generate(TEXT) IS 'Generate text embedding using default model profile (VOLATILE: calls external API)';
COMMENT ON FUNCTION embedding_generate(TEXT, TEXT) IS 'Generate text embedding using named model profile (VOLATILE: calls external API)';
COMMENT ON FUNCTION embedding_generate_model(TEXT, TEXT, TEXT) IS 'Generate text embedding with model_id and api_url (VOLATILE: calls external API)';
COMMENT ON FUNCTION embedding_generate_batch(TEXT[], TEXT) IS 'Generate embedding vectors for multiple texts';
COMMENT ON FUNCTION embedding_cache_dimension(TEXT, TEXT, TEXT, int) IS 'Cache auto-detected dimension for a model+url combination';
COMMENT ON FUNCTION embedding_register_model(TEXT, TEXT, TEXT, boolean, TEXT) IS 'Register a new model profile with API URL and model ID';
COMMENT ON FUNCTION embedding_list_models() IS 'List all registered model profiles';
COMMENT ON FUNCTION embedding_set_default_model(TEXT) IS 'Set a model profile as the default';
COMMENT ON FUNCTION embedding_drop_model(TEXT) IS 'Remove a model profile';
COMMENT ON FUNCTION embedding_test_model(TEXT) IS 'Test a model profile: call API, auto-detect dimensions, return status';
COMMENT ON FUNCTION embedding_detect_dimensions(TEXT) IS 'Auto-detect dimensions for one or all model profiles';
COMMENT ON FUNCTION embedding_cosine_similarity(float8[], float8[]) IS 'Calculate cosine similarity between two vectors (IMMUTABLE)';
COMMENT ON FUNCTION embedding_euclidean_distance(float8[], float8[]) IS 'Calculate Euclidean distance between two vectors (IMMUTABLE)';
COMMENT ON FUNCTION embedding_health_check(TEXT) IS 'Test API connectivity and return health status for a model profile';
COMMENT ON FUNCTION embedding_validate_vector(float8[], int) IS 'Validate a vector: check dimension, NaN, Inf, and norm';
COMMENT ON FUNCTION embedding_set_config(TEXT, TEXT) IS 'Set a global configuration parameter';
COMMENT ON FUNCTION embedding_get_config(TEXT) IS 'Get global configuration parameter(s)';
COMMENT ON FUNCTION embedding_stats() IS 'Get embedding generation statistics';
COMMENT ON FUNCTION embedding_errors(int) IS 'Get recent error messages';
COMMENT ON FUNCTION embedding_cleanup_logs(int) IS 'Delete logs older than N days';

-- ============================================
-- Installation complete
-- ============================================

DO $$
BEGIN
    RAISE NOTICE 'pg_embedding-gen v1.0.0 installed successfully!';
    RAISE NOTICE 'Multi-model support enabled.';
    RAISE NOTICE 'Try: SELECT embedding_generate(''Hello world'');';
    RAISE NOTICE 'List models: SELECT * FROM embedding_list_models();';
    RAISE NOTICE 'Register new: SELECT embedding_register_model(''my-model'', ''http://api/v1/embeddings'', ''model-id'');';
    RAISE NOTICE 'Auto-detect: SELECT * FROM embedding_detect_dimensions();';
END $$;

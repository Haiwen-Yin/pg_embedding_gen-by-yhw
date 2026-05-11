-- pg_embedding-gen SQL 安装脚本
-- 版本: v0.2.0
-- 作者: yhw

-- ============================================
-- 创建嵌入函数
-- ============================================

-- 主要嵌入生成函数
CREATE OR REPLACE FUNCTION embedding_generate(text text DEFAULT NULL)
RETURNS float8[] AS $$
BEGIN
    RETURN embedding_generate_model(text, NULL);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 使用指定模型的嵌入生成函数
CREATE OR REPLACE FUNCTION embedding_generate_model(text text, model text DEFAULT NULL)
RETURNS float8[] AS $$
DECLARE
    wrapper_path text := '/usr/local/pgsql/lib/embedding_wrapper.sh';
    config_file text := '/etc/pg_embedding-gen/config.yaml';
    cmd text;
    result text;
    vec float8[];
BEGIN
    -- 检查输入
    IF text IS NULL OR text = '' THEN
        RAISE WARNING '输入文本为空';
        RETURN NULL;
    END IF;
    
    -- 构建命令
    IF model IS NOT NULL THEN
        cmd := wrapper_path || ' --text ' || quote_literal(text) || ' --model ' || quote_literal(model) || ' --' || quote_literal(config_file);
    ELSE
        cmd := wrapper_path || ' --text ' || quote_literal(text) || ' --' || quote_literal(config_file);
    END IF;
    
    -- 使用 COPY FROM PROGRAM 执行
    CREATE TEMP TABLE temp_embedding (vec text) ON COMMIT DROP;
    EXECUTE 'COPY temp_embedding FROM PROGRAM ' || quote_literal(cmd);
    
    -- 读取结果
    SELECT vec INTO result FROM temp_embedding LIMIT 1;
    
    -- 解析向量
    vec := string_to_array(result, ',')::float8[];
    
    RETURN vec;
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING '生成嵌入失败: %', SQLERRM;
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- 批量嵌入生成函数
CREATE OR REPLACE FUNCTION embedding_generate_batch(texts text[], model text DEFAULT NULL)
RETURNS float8[][] AS $$
DECLARE
    results float8[][] := '{}';
    vec float8[];
    i int;
BEGIN
    FOR i IN 1..array_length(texts, 1) LOOP
        vec := embedding_generate_model(texts[i], model);
        results = results || vec;
    END LOOP;
    
    RETURN results;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 辅助函数
-- ============================================

-- 计算余弦相似度
CREATE OR REPLACE FUNCTION embedding_cosine_similarity(vec1 float8[], vec2 float8[])
RETURNS float8 AS $$
DECLARE
    dot_product float8 := 0;
    norm1 float8 := 0;
    norm2 float8 := 0;
    i int;
BEGIN
    IF vec1 IS NULL OR vec2 IS NULL THEN
        RETURN NULL;
    END IF;
    
    IF array_length(vec1, 1) != array_length(vec2, 1) THEN
        RAISE WARNING '向量维度不匹配';
        RETURN NULL;
    END IF;
    
    FOR i IN 1..array_length(vec1, 1) LOOP
        dot_product := dot_product + (vec1[i] * vec2[i]);
        norm1 := norm1 + (vec1[i] * vec1[i]);
        norm2 := norm2 + (vec2[i] * vec2[i]);
    END LOOP;
    
    IF norm1 = 0 OR norm2 = 0 THEN
        RETURN NULL;
    END IF;
    
    RETURN dot_product / (sqrt(norm1) * sqrt(norm2));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 计算欧几里得距离
CREATE OR REPLACE FUNCTION embedding_euclidean_distance(vec1 float8[], vec2 float8[])
RETURNS float8 AS $$
DECLARE
    distance float8 := 0;
    i int;
BEGIN
    IF vec1 IS NULL OR vec2 IS NULL THEN
        RETURN NULL;
    END IF;
    
    IF array_length(vec1, 1) != array_length(vec2, 1) THEN
        RAISE WARNING '向量维度不匹配';
        RETURN NULL;
    END IF;
    
    FOR i IN 1..array_length(vec1, 1) LOOP
        distance := distance + power(vec1[i] - vec2[i], 2);
    END LOOP;
    
    RETURN sqrt(distance);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================
-- 统计和错误处理函数
-- ============================================

-- 嵌入统计表（如果不存在）
CREATE TABLE IF NOT EXISTS embedding_logs (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP DEFAULT NOW(),
    model text,
    text_length int,
    vector_dimension int,
    status text,
    error_message text
);

-- 获取统计信息
CREATE OR REPLACE FUNCTION embedding_stats()
RETURNS TABLE (
    total_requests bigint,
    successful_requests bigint,
    failed_requests bigint,
    most_used_model text,
    avg_vector_dimension float8
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(*) as total_requests,
        COUNT(*) FILTER (WHERE status = 'success') as successful_requests,
        COUNT(*) FILTER (WHERE status = 'error') as failed_requests,
        (SELECT model FROM embedding_logs 
         WHERE status = 'success' 
         GROUP BY model 
         ORDER BY COUNT(*) DESC 
         LIMIT 1) as most_used_model,
        AVG(vector_dimension) FILTER (WHERE status = 'success') as avg_vector_dimension
    FROM embedding_logs;
END;
$$ LANGUAGE plpgsql;

-- 获取最近的错误
CREATE OR REPLACE FUNCTION embedding_errors(limit_count int DEFAULT 10)
RETURNS TABLE (
    created_at timestamp,
    model text,
    error_message text
) AS $$
BEGIN
    RETURN QUERY
    SELECT created_at, model, error_message
    FROM embedding_logs
    WHERE status = 'error'
    ORDER BY created_at DESC
    LIMIT limit_count;
END;
$$ LANGUAGE plpgsql;

-- 清理旧日志
CREATE OR REPLACE FUNCTION embedding_cleanup_logs(days_to_keep int DEFAULT 30)
RETURNS bigint AS $$
DECLARE
    deleted_count bigint;
BEGIN
    DELETE FROM embedding_logs 
    WHERE created_at < NOW() - (days_to_keep || ' days')::interval;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 安装完成
-- ============================================

-- 创建函数说明注释
COMMENT ON FUNCTION embedding_generate(text) IS '生成文本嵌入向量';
COMMENT ON FUNCTION embedding_generate_model(text, text) IS '使用指定模型生成文本嵌入向量';
COMMENT ON FUNCTION embedding_generate_batch(text[], text) IS '批量生成文本嵌入向量';
COMMENT ON FUNCTION embedding_cosine_similarity(float8[], float8[]) IS '计算两个向量的余弦相似度';
COMMENT ON FUNCTION embedding_euclidean_distance(float8[], float8[]) IS '计算两个向量的欧几里得距离';
COMMENT ON FUNCTION embedding_stats() IS '获取嵌入生成的统计信息';
COMMENT ON FUNCTION embedding_errors(int) IS '获取最近的错误信息';
COMMENT ON FUNCTION embedding_cleanup_logs(int) IS '清理指定天数之前的日志';

-- 完成
DO $$
BEGIN
    RAISE NOTICE 'pg_embedding-gen v0.2.0 安装完成！';
    RAISE NOTICE '可以使用 embedding_generate() 函数生成嵌入向量';
    RAISE NOTICE '使用 SELECT embedding_stats(); 查看统计信息';
END $$;

# pg_embedding-gen 模型配置指南

本指南详细说明如何配置各种嵌入模型。

以支持的主要模型：
- OpenAI 模型
- Ollama 本地模型
- 本地 Transformer 模型

## 目录

1. [OpenAI 模型配置](#openai-模型配置)
2. [Ollama 模型配置](#ollama-模型型配置)
3. [本地模型配置](#本地模型配置)
4. [高级配置](#高级配置)
5. [性能优化](#性能优化)
6. [故障排除](#故障排除)

## OpenAI 模型配置

### 支持的模型

OpenAI 提供以下嵌入模型：

| 模型名称 | 向量维度 | 最大 token | 价格 (1K tokens) |
|---------|---------|-----------|-----------------|
| text-embedding-3-small | 1536 | 8191 | $0.00002 |
| text-embedding-3-large | 3072 | 8191 | $0.00013 |
| text-embedding-ada-002 | 1536 | 8191 | $0.0001 |

### 配置示例

编辑 `/etc/pg_embedding-gen/config.yaml`：

```yaml
# OpenAI 配置
openai:
  # API 密钥（必需）
  api_key: "sk-your-api-key-here"
  
  # API 基础 URL（可选，用于代理）
  # 默认: https://api.openai.com/v1
  base_url: "https://api.openai.com/v1"
  
  # 请求超时时间（秒）
  # 默认: 30
  timeout: 30
  
  # 最大重试次数
  # 默认: 3
  max_retries: 3
  
  # 组织 ID（可选）
  organization: "your-org-id"
```

### 使用代理服务器

如果需要通过代理访问 OpenAI API：

```yaml
openai:
  api_key: "sk-your-api-key"
  base_url: "https://your-proxy.com/v1"
  timeout: 30
```

### 使用示例

```sql
-- 使用默认模型
SELECT embedding_generate('测试文本');

-- 指定模型
SELECT embedding_generate('测试文本', 'openai-text-embedding-3-small');

-- 使用大模型
SELECT embedding_generate('测试文本', 'openai-text-embedding-3-large');
```

## Ollama 模型配置

Ollama 允许你在本地运行各种开源嵌入模型。

### 支持的模型

常用 Ollama 嵌入模型：

| 模型名称 | 向量维度 | 说明 |
|---------|---------|------|
| nomic-embed-text | 768 | 通用嵌入模型 |
| all-minilm | 384 | 轻量级模型 |
| mxbai-embed-large | 1024 | 大型嵌入模型 |

### 安装 Ollama

```bash
# 安装 Ollama
curl -fsSL https://ollama.com/install.sh | sh

# 拉取嵌入模型
ollama pull nomic-embed-text
ollama pull all-minilm
ollama pull mxbai-embed-large

# 启动 Ollama 服务
ollama serve
```

### 配置示例

```yaml
# Ollama 配置
ollama:
  # Ollama 服务地址
  # 默认: http://localhost:11434
  base_url: "http://localhost:11434"
  
  # 请求超时时间（秒）
  # 默认: 60
  timeout: 60
  
  # 最大重试次数
  # 默认: 3
  max_retries: 3
```

### 使用示例

```sql
-- 使用 Ollama 模型
SELECT embedding_generate('测试文本', 'ollama-nomic-embed-text');
SELECT embedding_generate('测试文本', 'ollama-all-minilm');
SELECT embedding_generate('测试文本', 'ollama-mxbai-embed-large');
```

## 本地模型配置

可以使用本地运行的 Transformer 模型，如 sentence-transformers。

### 安装依赖

```bash
# 安装 sentence-transformers
pip3 install sentence-transformers torch
```

### 配置示例

```yaml
# 本地模型配置
local:
  # 模型路径或 Hugging Face 模型名称
  # 示例: "all-MiniLM-L6-v2", "paraphrase-multilingual-MiniLM-L12-v2"
  model_path: "all-MiniLM-L6-v2"
  
  # 使用的设备：cpu 或 cuda
  # 默认: cpu
  device: "cpu"
  
  # 请求超时时间（秒）
  # 默认: 60
  timeout: 60
  
  # 批处理大小
  # 默认: 32
  batch_size: 32
```

### 支持的本地模型

推荐的多语言模型：

| 模型名称 | 向量维度 | 语言支持 |
|---------|---------|---------|
| all-MiniLM-L6-v2 | 384 | 多语言（主要英文） |
| paraphrase-multilingual-MiniLM-L12-v2 | 384 | 50+ 语言 |
| intfloat/multilingual-e5-large | 1024 | 100+ 语言 |

### 使用示例

```sql
-- 使用本地模型
SELECT embedding_generate('测试文本', 'local-all-MiniLM-L6-v2');
SELECT embedding_generate('测试文本', 'local-paraphrase-multilingual-MiniLM-L12-v2');
```

## 高级配置

### 向量维度验证

在配置文件中定义模型的向量维度，用于验证：

```yaml
# 向量维度（用于验证）
vector_dimensions:
  openai-text-embedding-3-small: 1536
  openai-text-embedding-3-large: 3072
  ollama-nomic-embed-text: 768
  ollama-all-minilm: 384
  ollama-mxbai-embed-large: 1024
  local-all-MiniLM-L6-v2: 384
```

### 缓存配置

启用缓存可以减少重复请求：

```yaml
# 缓存配置
cache:
  # 是否启用缓存
  # 默认: false
  enabled: true
  
  # 最大缓存条目数
  # 默认: 1000
  max_size: 1000
  
  # 缓存过期时间（秒）
  # 默认: 3600 (1小时)
  ttl: 3600
```

### 文本长度限制

限制输入文本的最大长度：

```yaml
# 通用配置
general:
  # 最大文本长度（字符数）
  # 默认: 8192
  max_text_length: 8192
```

## 性能优化

### 1. 批处理配置

增加批处理大小可以提高吞吐量：

```yaml
general:
  batch_size: 100  # 默认: 100
```

### 2. 超时调整

根据网络和模型响应时间调整超时：

```yaml
openai:
  timeout: 30  # 快速网络可以减少

ollama:
  timeout: 60  # 本地模型可能需要更长时间

local:
  timeout: 120  # 大型本地模型需要更多时间
```

### 3. 连接池配置

对于高并发场景，可以配置连接池：

```yaml
openai:
  # 最大连接数
  max_connections: 10
  
  # 连接超时
  connection_timeout: 10
```

### 4. 使用更快的模型

根据应用场景选择合适的模型：

- **快速/低维**: text-embedding-3-small (OpenAI), all- minilm (Ollama)
- **高质量/高维**: text-embedding-3-large (OpenAI), mxbai-embed-large (Ollama)
- **多语言**: paraphrase-multilingual-MiniLM-L12-v2

### 5. 预加载模型

对于本地模型，预加载可以减少首次请求延迟：

```bash
# 预加载 Ollama 模型
ollama run nomic-embed-text /dev/null

# 预加载 sentence-transformers 模型
python3 -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"
```

## 故障排除

### 问题 1: OpenAI API 连接超时

**原因**: 网络问题或 API 服务不稳定

**解决方案**:
1. 增加超时时间
2. 使用代理服务器
3. 检查网络连接
4. 实现 API 速率限制

### 问题 2: Ollama 服务未启动

**原因**: Ollama 服务未运行

**解决方案**:
```bash
# 检查 Ollama 服务状态
curl http://localhost:11434/api/tags

# 启动服务
ollama serve
```

### 问题 3: 本地模型加载失败

**原因**: 模型文件损坏或路径错误

**解决方案**:
```bash
# 重新下载模型
pip3 install --upgrade sentence-transformers

# 清除缓存
rm -rf ~/.cache/torch/sentence_transformers/

# 测试模型加载
python3 -c "from sentence_transformers import SentenceTransformer; print(SentenceTransformer('all-MiniLM-L6-v2').encode('test').shape)"
```

### 问题 4: 内存不足

**原因**: 模型太大，超出系统内存

**解决方案**:
1. 使用较小的模型
2. 增加 CPU 而不是 GPU
3. 增加系统交换空间
4. 减少批处理大小

### 问题 5: 向量维度不匹配

**原因**: 查询和索引使用不同维度的模型

**解决方案**:
```sql
-- 检查向量维度
SELECT 
  id, 
  array_length(embedding, 1) as dimension 
FROM documents 
LIMIT 5;

-- 确保所有向量使用相同模型
```

## 模型选择建议

根据应用场景选择合适的模型：

| 应用场景 | 推荐模型 | 维度 | 原因 |
|---------|---------|------|------|
| 通用搜索 | text-embedding-3-small | 1536 | 平衡性能和质量 |
| 高精度匹配 | text-embedding-3-large | 3072 | 更好的语义理解 |
| 低延迟 | all-minilm | 384 | 快速且低维度 |
| 多语言支持 | paraphrase-multilingual-MiniLM-L12-v2 | 384 | 支持 50+ 语言 |
| 私有部署 | nomic-embed-text | 768 | 可在本地运行 |

## 参考

- [OpenAI 嵌入文档](https://platform.openai.com/docs/guides/embeddings)
- [Ollama 文档](https://ollama.com/)
- [Sentence Transformers 文档](https://www.sbert.net/)
- [Hugging Face 模型库](https://huggingface.co/models?pipeline_tag=sentence-similarity)

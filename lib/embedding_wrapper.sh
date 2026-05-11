#!/bin/bash
#
# pg_embedding-gen 嵌入包装脚本
# 版本: v0.2.0
# 作者: yhw
#
# 此脚本用于包装 embedding_proxy.py，确保在 PostgreSQL COPY FROM PROGRAM 中正确执行

set -euo pipefail

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROXY_SCRIPT="${SCRIPT_DIR}/embedding_proxy.py"

# 默认配置文件
DEFAULT_CONFIG="/etc/pg_embedding-gen/config.yaml"

# 解析参数
TEXT=""
MODEL=""
CONFIG=""

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --text)
            TEXT="$2"
            shift 2
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --*)
            # 假设是配置文件（以 -- 开头，但不是已知选项）
            # PostgreSQL 可能会传递一些额外参数
            CONFIG="${1#--}"
            shift
            ;;
        *)
            # 位置参数，可能是配置文件
            if [[ -f "$1" ]] && [[ "$1" == *.yaml ]]; then
                CONFIG="$1"
            fi
            shift
            ;;
    esac
done

# 使用默认配置（如果未指定）
if [[ -z "$CONFIG" ]]; then
    CONFIG="$DEFAULT_CONFIG"
fi

# 检查必需的参数
if [[ -z "$TEXT" ]]; then
    echo "错误: 缺少 --text 参数" >&2
    exit 1
fi

# 检查文件存在
if [[ ! -f "$PROXY_SCRIPT" ]]; then
    echo "错误: 嵌入代理脚本不存在: $PROXY_SCRIPT" >&2
    exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
    echo "错误: 配置文件不存在: $CONFIG" >&2
    exit 1
fi

# 构建 Python 命令
PYTHON_CMD=(python3 "$PROXY_SCRIPT" --text "$TEXT")

if [[ -n "$MODEL" ]]; then
    PYTHON_CMD+=(--model "$MODEL")
fi

PYTHON_CMD+=(--config "$CONFIG")

# 执行并捕获输出
# 使用子 shell 来处理输出，确保 flush
OUTPUT=$("${PYTHON_CMD[@]}" 2>&1)
EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
    echo "$OUTPUT" >&2
    exit $EXIT_CODE
fi

# 输出结果
echo "$OUTPUT"

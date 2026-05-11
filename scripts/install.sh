#!/bin/bash
# pg_embedding-gen 安装脚本

set -e

VERSION="v0.2.0"
AUTHOR="yhw"
INSTALL_DIR="/usr/local/pgsql/lib"
CONFIG_DIR="/etc/pg_embedding-gen"
LOG_DIR="/var/log"

echo "========================================"
echo "pg_embedding-gen 安装脚本"
echo "版本: $VERSION"
echo "作者: $AUTHOR"
echo "========================================"

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "错误：请使用 root 权限运行此脚本"
    echo "使用: sudo bash scripts/install.sh"
    exit 1
fi

# 检查 PostgreSQL 版本
if ! command -v psql &> /dev/null; then
    echo "错误：未找到 PostgreSQL，请先安装 PostgreSQL 18 或更高版本"
    exit 1
fi

PG_VERSION=$(psql --version | awk '{print $3}' | cut -d. -f1)
if [ "$PG_VERSION" -lt 18 ]; then
    echo "警告：检测到 PostgreSQL $PG_VERSION，推荐使用 PostgreSQL 18 或更高版本"
    echo "按 Ctrl+C 取消，或继续安装（可能无法正常工作）"
    read -r -p "继续安装？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 检查 Python 版本
if ! command -v python3 &> /dev/null; then
    echo "错误：未找到 Python 3，请先安装 Python 3.8 或更高版本"
    exit 1
fi

PY_VERSION=$(python3 --version | awk '{print $2}' | cut -d. -f1-2)
echo "检测到 Python $PY_VERSION"

# 创建安装目录
echo "创建安装目录..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$LOG_DIR"

# 复制文件
echo "复制文件..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
cp "$SCRIPT_DIR/lib/embedding_proxy.py" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/lib/embedding_wrapper.sh" "$INSTALL_DIR/"

# 设置权限
echo "设置文件权限..."
chmod 644 "$INSTALL_DIR/embedding_proxy.py"
chmod 755 "$INSTALL_DIR/embedding_wrapper.sh"
chown postgres:postgres "$INSTALL_DIR/embedding_wrapper.sh" || true

# 复制配置文件
if [ ! -f "$CONFIG_DIR/config.yaml" ]; then
    cp "$SCRIPT_DIR/config.example.yaml" "$CONFIG_DIR/config.yaml"
    echo "已创建默认配置文件: $CONFIG_DIR/config.yaml"
    echo "请编辑此文件以配置你的嵌入模型"
else
    echo "配置文件已存在，跳过: $CONFIG_DIR/config.yaml"
fi

# 安装 Python 依赖
echo "安装 Python 依赖..."
if command -v pip3 &> /dev/null; then
    pip3 install -q openai requests pyyaml || {
        echo "警告：pip3 安装失败，请手动安装依赖"
        echo "运行: pip3 install openai requests pyyaml"
    }
else
    echo "警告：未找到 pip3，请手动安装 Python 依赖"
    echo "运行: pip3 install openai requests pyyaml"
fi

# 创建日志文件
touch "$LOG_DIR/pg_embedding-gen.log"
chmod 644 "$LOG_DIR/pg_embedding-gen.log"
chown postgres:postgres "$LOG_DIR/pg_embedding-gen.log" || true

echo ""
echo "========================================"
echo "安装完成！"
echo "========================================"
echo ""
echo "后续步骤："
echo ""
echo "1. 编辑配置文件:"
echo "   sudo vim $CONFIG_DIR/config.yaml"
echo ""
echo "2. 在数据库中创建函数:"
echo "   psql -d your_database -f $SCRIPT_DIR/sql/install.sql"
echo ""
echo "3. 测试安装:"
echo "   SELECT embedding_generate('测试文本');"
echo ""
echo "更多信息请参考 README.md"
echo ""

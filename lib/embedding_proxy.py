#!/usr/bin/env python3
"""
pg_embedding-gen 嵌入代理
版本: v0.2.0
作者: yhw

用于生成文本嵌入向量的 Python 代理脚本
支持 OpenAI、Ollama 和本地模型
"""

import sys
import os
import json
import argparse
import yaml
import logging
from typing import List, Optional, Dict, Any
from datetime import datetime

try:
    import openai
    import requests
except ImportError as e:
    sys.stderr.write(f"错误: 缺少必需的 Python 库: {e}\n")
    sys.stderr.write("请运行: pip3 install openai requests pyyaml\n")
    sys.exit(1)


class EmbeddingProxy:
    """嵌入代理类"""
    
    def __init__(self, config_path: str):
        """初始化代理"""
        self.config = self._load_config(config_path)
        self._setup_logging()
        
    def _load_config(self, config_path: str) -> Dict[str, Any]:
        """加载配置文件"""
        if not os.path.exists(config_path):
            sys.stderr.write(f"错误: 配置文件不存在: {config_path}\n")
            sys.exit(1)
            
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                return yaml.safe_load(f)
        except Exception as e:
            sys.stderr.write(f"错误: 加载配置文件失败: {e}\n")
            sys.exit(1)
    
    def _setup_logging(self):
        """设置日志"""
        log_config = self.config.get('general', {})
        log_level = getattr(logging, log_config.get('log_level', 'INFO'))
        log_file = log_config.get('log_file', '/var/log/pg_embedding-gen.log')
        
        # 设置格式
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        
        # 文件处理器
        try:
            file_handler = logging.FileHandler(log_file)
            file_handler.setLevel(log_level)
            file_handler.setFormatter(formatter)
            
            self.logger = logging.getLogger('embedding_proxy')
            self.logger.setLevel(log_level)
            self.logger.addHandler(file_handler)
        except Exception as e:
            # 如果无法写入日志文件，使用 stderr
            self.logger = logging.getLogger('embedding_proxy')
            self.logger.setLevel(log_level)
            handler = logging.StreamHandler(sys.stderr)
            handler.setLevel(log_level)
            handler.setFormatter(formatter)
            self.logger.addHandler(handler)
    
    def generate(self, text: str, model: Optional[str] = None) -> List[float]:
        """生成嵌入向量"""
        if not model:
            model = self.config.get('default_model', 'openai-text-embedding-3-small')
        
        self.logger.info(f"生成嵌入: model={model}, text_length={len(text)}")
        
        try:
            if model.startswith('openai'):
                return self._generate_openai(text, model)
            elif model.startswith('ollama'):
                return self._generate_ollama(text, model)
            else:
                return self._generate_local(text, model)
        except Exception as e:
            self.logger.error(f"生成嵌入失败: {e}")
            raise
    
    def _generate_openai(self, text: str, model: str) -> List[float]:
        """使用 OpenAI 生成嵌入"""
        openai_config = self.config.get('openai', {})
        api_key = openai_config.get('api_key', '')
        base_url = openai_config.get('base_url', 'https://api.openai.com/v1')
        timeout = openai_config.get('timeout', 30)
        
        if not api_key:
            raise ValueError("OpenAI API key 未配置")
        
        client = openai.OpenAI(
            api_key=api_key,
            base_url=base_url,
            timeout=timeout
        )
        
        response = client.embeddings.create(
            model=model.replace('openai-', ''),
            input=text
        )
        
        return response.data[0].embedding
    
    def _generate_ollama(self, text: str, model: str) -> List[float]:
        """使用 Ollama 生成嵌入"""
        ollama_config = self.config.get('ollama', {})
        base_url = ollama_config.get('base_url', 'http://localhost:11434')
        timeout = ollama_config.get('timeout', 60)
        
        url = f"{base_url}/api/embeddings"
        payload = {
            "model": model.replace('ollama-', ''),
            "prompt": text
        }
        
        response = requests.post(url, json=payload, timeout=timeout)
        response.raise_for_status()
        
        data = response.json()
        return data.get('embedding', [])
    
    def _generate_local(self, text: str, model: str) -> List[float]:
        """使用本地模型生成嵌入"""
        # 这里可以集成 sentence-transformers 或其他本地模型
        # 为简化，目前返回一个示例向量
        sys.stderr.write(f"警告: 本地模型支持尚未完全实现: {model}\n")
        
        # 返回一个模拟向量（实际应该使用真正的模型）
        return [0.0] * 768


def main():
    """主函数"""
    parser = argparse.ArgumentParser(description='pg_embedding-gen 嵌入代理')
    parser.add_argument('--text', required=True, help='要生成嵌入的文本')
    parser.add_argument('--model', help='嵌入模型名称')
    parser.add_argument('--config', help='配置文件路径')
    
    # 兼容 PostgreSQL COPY FROM PROGRAM 的参数格式
    parser.add_argument('config_pos', nargs='?', help='配置文件路径（位置参数）')
    
    args = parser.parse_args()
    
    # 确定配置文件路径
    config_path = args.config or args.config_pos
    if not config_path:
        config_path = '/etc/pg_embedding-gen/config.yaml'
    
    # 创建代理
    proxy = EmbeddingProxy(config_path)
    
    # 生成嵌入
    try:
        embedding = proxy.generate(args.text, args.model)
        
        # 输出向量（逗号分隔）
        output = ','.join(map(str, embedding))
        print(output, flush=True)
        
    except Exception as e:
        sys.stderr.write(f"错误: {e}\n")
        sys.exit(1)


if __name__ == '__main__':
    main()

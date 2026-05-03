#!/usr/bin/env python3
"""
pg_embedding_proxy - Embedding generation proxy with configurable models.

This script connects to PostgreSQL C extension via popen() and provides
embedding functionality for various models (BGE-M3, OpenAI, etc.).
"""

import sys
import os
import json
import time
import requests
from typing import List, Dict, Any, Optional

# Default configuration - can be overridden by config.yaml
DEFAULT_CONFIG = {
    "model": {
        "name": "text-embedding-bge-m3",
        "api_url": "http://10.10.10.1:12345/v1/embeddings",
        "dimension": 1024
    },
    "credentials": {},
    "security": {
        "allow_local_only": True,
        "timeout_seconds": 30,
        "max_retries": 3
    }
}


class ConfigLoader:
    """Load configuration from YAML file or use defaults."""
    
    @staticmethod
    def load(config_path: str = None) -> Dict[str, Any]:
        """Load configuration with fallback to defaults."""
        try:
            if config_path and os.path.exists(config_path):
                return ConfigLoader._load_yaml(config_path)
        except Exception as e:
            print(f"Warning: Failed to load {config_path}: {e}", file=sys.stderr)
        
        # Fall back to defaults
        return DEFAULT_CONFIG
    
    @staticmethod
    def _load_yaml(filepath: str) -> Dict[str, Any]:
        """Simple YAML loader (avoids PyYAML dependency for basic cases)."""
        config = {}
        with open(filepath, 'r') as f:
            content = f.read()
            
        # Simple parsing for our use case
        import re
        
        # Parse model section
        model_match = re.search(r'model:(.*?)credentials:', content, re.DOTALL)
        if model_match:
            model_section = model_match.group(1).strip()
            config['model'] = {}
            
            # Extract key-value pairs
            for line in model_section.split('\n'):
                line = line.strip().rstrip(',')
                if ':' in line and not line.startswith('#'):
                    key, value = line.split(':', 1)
                    key = key.strip()
                    value = value.strip().strip('"').strip("'")
                    
                    # Try to convert types
                    try:
                        value = int(value)
                    except ValueError:
                        pass
                        
                    config['model'][key] = value
        
        # Parse credentials section
        cred_match = re.search(r'credentials:(.*?)security:', content, re.DOTALL)
        if cred_match:
            cred_section = cred_match.group(1).strip()
            config['credentials'] = {}
            
            for line in cred_section.split('\n'):
                line = line.strip().rstrip(',')
                if ':' in line and not line.startswith('#'):
                    key, value = line.split(':', 1)
                    key = key.strip()
                    value = value.strip().strip('"').strip("'")
                    config['credentials'][key] = value
        
        # Parse security section
        sec_match = re.search(r'security:(.*?)(?:paths|$)', content, re.DOTALL)
        if sec_match:
            sec_section = sec_match.group(1).strip()
            config['security'] = {}
            
            for line in sec_section.split('\n'):
                line = line.strip().rstrip(',')
                if ':' in line and not line.startswith('#'):
                    key, value = line.split(':', 1)
                    key = key.strip()
                    # Convert booleans
                    if isinstance(value, str):
                        if value.lower() == 'true':
                            value = True
                        elif value.lower() == 'false':
                            value = False
                    else:
                        try:
                            value = int(value)
                        except ValueError:
                            pass
                    
                    config['security'][key] = value
        
        return config


class EmbeddingGenerator:
    """Generate embeddings using configurable models."""
    
    def __init__(self, config_path: str = None):
        self.config = ConfigLoader.load(config_path)
        self.model_name = self.config.get('model', {}).get('name', 'text-embedding-bge-m3')
        self.api_url = self.config.get('model', {}).get('api_url', 
                                                       'http://10.10.10.1:12345/v1/embeddings')
        self.dimension = self.config.get('model', {}).get('dimension', 1024)
        self.credentials = self.config.get('credentials', {})
        security_config = self.config.get('security', {})
        
        self.allow_local_only = security_config.get('allow_local_only', True)
        self.timeout = security_config.get('timeout_seconds', 30)
        self.max_retries = security_config.get('max_retries', 3)
    
    def validate_api_access(self):
        """Check if API access is allowed based on security settings."""
        if self.allow_local_only:
            # Check if URL is localhost or private IP
            import re
            local_pattern = r'^(http://)?(localhost|127\.0\.0\.[0-9]+|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})$'
            if not re.match(local_pattern, self.api_url):
                raise ValueError("API access denied: allow_local_only is True but API URL is external")
    
    def generate(self, text: str) -> List[float]:
        """Generate embedding for given text."""
        # Validate access before attempting generation
        try:
            self.validate_api_access()
        except ValueError:
            print(f"Error: Cannot access {self.api_url} - security policy violation", 
                  file=sys.stderr)
            return [0.0] * self.dimension
        
        headers = {'Content-Type': 'application/json'}
        
        # Add authentication if credentials provided
        if self.credentials.get('openai_api_key'):
            headers['Authorization'] = f"Bearer {self.credentials['openai_api_key']}"
            
        custom_header_key = self.config.get('credentials', {}).get('custom_header_key')
        custom_header_value = self.config.get('credentials', {}).get('custom_header_value')
        if custom_header_key and custom_header_value:
            headers[custom_header_key] = custom_header_value
        
        payload = {
            "model": self.model_name,
            "input": text,
            "encoding_format": "float"  # Request float array format
        }
        
        # Retry logic for reliability
        last_error = None
        for attempt in range(1, self.max_retries + 1):
            try:
                response = requests.post(self.api_url, 
                                       json=payload, 
                                       headers=headers,
                                       timeout=self.timeout)
                
                if not response.ok:
                    raise Exception(f"HTTP {response.status_code}: {response.text}")
                
                data = response.json()
                
                # Extract embedding from different API formats
                if "data" in data and len(data["data"]) > 0:
                    embedding = data["data"][0].get("embedding", [])
                    
                    # Validate dimension count
                    expected_dim = self.dimension
                    actual_dim = len(embedding)
                    
                    if actual_dim != expected_dim:
                        print(f"Warning: Expected {expected_dim} dims, got {actual_dim}", 
                              file=sys.stderr)
                    
                    return embedding
                    
                else:
                    raise Exception("Unexpected API response format")
                    
            except requests.exceptions.RequestException as e:
                last_error = e
                if attempt < self.max_retries:
                    time.sleep(1 * attempt)  # Exponential backoff
                    
        # Return default on failure
        print(f"Error after {self.max_retries} attempts: {last_error}", 
              file=sys.stderr)
        return [0.0] * self.dimension


def main():
    """CLI entry point - reads text from command line arguments."""
    if len(sys.argv) < 2:
        print("Usage: python3 pg_embedding_proxy.py \"text to embed\" [--config path]", 
              file=sys.stderr)
        sys.exit(1)
    
    # Parse arguments
    config_path = None
    text_parts = []
    
    for i, arg in enumerate(sys.argv[1:], 1):
        if arg == "--config" and i + 1 < len(sys.argv):
            config_path = sys.argv[i + 1]
        elif not arg.startswith("--"):
            text_parts.append(arg)
    
    text = " ".join(text_parts)
    
    # Generate embedding
    generator = EmbeddingGenerator(config_path)
    embedding = generator.generate(text)
    
    # Output as JSON array (C extension expects this format)
    print(json.dumps(embedding))


if __name__ == "__main__":
    main()

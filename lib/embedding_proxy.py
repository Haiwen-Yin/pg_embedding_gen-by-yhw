#!/usr/bin/env python3
"""
pg_embedding-gen: Embedding proxy for PostgreSQL
Version: v1.0.0
Author: yhw (Haiwen Yin)

Generates text embedding vectors by calling an OpenAI-compatible API.
Supports base64-encoded input for safe passage through shell from PostgreSQL.
Supports any OpenAI-compatible /v1/embeddings endpoint.
"""

import sys
import os
import json
import base64
import argparse
import time
import logging

try:
    import requests
except ImportError:
    sys.stderr.write("Error: 'requests' library required.\n")
    sys.stderr.write("Install: pip3 install requests\n")
    sys.exit(1)

DEFAULT_API_URL = "http://10.10.10.1:12345/v1/embeddings"
DEFAULT_MODEL = "text-embedding-bge-m3"
DEFAULT_TIMEOUT = 30
DEFAULT_MAX_RETRIES = 3
DEFAULT_RETRY_DELAY = 1.0
CONFIG_PATH = "/etc/pg_embedding-gen/config.json"

logger = None


def setup_logging(log_file=None, log_level="WARNING"):
    global logger
    logger = logging.getLogger("embedding_proxy")
    level = getattr(logging, log_level.upper(), logging.WARNING)
    logger.setLevel(level)

    if logger.handlers:
        for h in list(logger.handlers):
            logger.removeHandler(h)

    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

    handler_set = False
    if log_file:
        try:
            fh = logging.FileHandler(log_file)
            fh.setLevel(level)
            fh.setFormatter(formatter)
            logger.addHandler(fh)
            handler_set = True
        except (IOError, OSError):
            pass

    if not handler_set:
        sh = logging.StreamHandler(sys.stderr)
        sh.setLevel(level)
        sh.setFormatter(formatter)
        logger.addHandler(sh)


def load_config(config_path):
    if not os.path.exists(config_path):
        return {}
    try:
        with open(config_path, 'r') as f:
            return json.load(f)
    except (IOError, ValueError, OSError):
        return {}


def call_embedding_api(texts, api_url, model, timeout, max_retries):
    payload = {
        "model": model,
        "input": texts,
        "encoding_format": "float"
    }

    last_error = None
    for attempt in range(max_retries):
        try:
            resp = requests.post(api_url, json=payload, timeout=timeout)
            resp.raise_for_status()
            data = resp.json()

            if "data" not in data or not isinstance(data["data"], list):
                raise ValueError("Unexpected API response: missing 'data' array")

            if len(data["data"]) == 0:
                raise ValueError("Unexpected API response: empty 'data' array")

            results = []
            for item in data["data"]:
                emb = item.get("embedding")
                if not emb or not isinstance(emb, list):
                    raise ValueError("Unexpected API response: missing 'embedding' field")
                results.append(emb)

            if len(results) != len(texts):
                raise ValueError(
                    "Response count mismatch: sent {}, got {}".format(
                        len(texts), len(results)
                    )
                )

            return results

        except requests.exceptions.Timeout as e:
            last_error = e
            if logger:
                logger.warning("Attempt %d/%d timed out", attempt + 1, max_retries)
        except requests.exceptions.ConnectionError as e:
            last_error = e
            if logger:
                logger.warning(
                    "Attempt %d/%d connection error: %s",
                    attempt + 1, max_retries, str(e)[:200]
                )
        except requests.exceptions.HTTPError as e:
            last_error = e
            if logger:
                logger.warning(
                    "Attempt %d/%d HTTP error: %s",
                    attempt + 1, max_retries, str(e)[:200]
                )
            if resp.status_code is not None and 400 <= resp.status_code < 500:
                break
        except (ValueError, KeyError) as e:
            last_error = e
            if logger:
                logger.warning(
                    "Attempt %d/%d parse error: %s",
                    attempt + 1, max_retries, str(e)
                )
            break
        except Exception as e:
            last_error = e
            if logger:
                logger.warning(
                    "Attempt %d/%d error: %s",
                    attempt + 1, max_retries, str(e)[:200]
                )

        if attempt < max_retries - 1:
            delay = DEFAULT_RETRY_DELAY * (2 ** attempt)
            if logger:
                logger.info("Retrying in %.1f seconds", delay)
            time.sleep(delay)

    raise RuntimeError(
        "Embedding generation failed after {} attempt(s): {}".format(
            max_retries, last_error
        )
    )


def generate_embeddings(texts, api_url, model, timeout, max_retries):
    if len(texts) == 0:
        return []

    if len(texts) == 1:
        return call_embedding_api(texts, api_url, model, timeout, max_retries)

    try:
        results = call_embedding_api(texts, api_url, model, timeout, max_retries)
        if len(results) == len(texts):
            return results
    except Exception:
        pass

    if logger:
        logger.info("Batch API failed, falling back to individual requests")

    results = []
    last_err = None
    for t in texts:
        try:
            r = call_embedding_api([t], api_url, model, timeout, max_retries)
            results.extend(r)
        except Exception as e:
            last_err = e
            results.append(None)

    if all(r is None for r in results):
        raise RuntimeError(
            "All individual requests failed: {}".format(last_err)
        )

    return results


def main():
    parser = argparse.ArgumentParser(
        description='pg_embedding-gen embedding proxy v1.0.0'
    )

    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument('--text', help='Single text to embed (plain text)')
    input_group.add_argument(
        '--text-base64',
        help='Single text to embed (base64 encoded, preferred for shell safety)'
    )
    input_group.add_argument(
        '--batch-base64',
        help='JSON array of texts (base64 encoded, for batch processing)'
    )

    parser.add_argument(
        '--model', default=None,
        help='Model ID sent to API (default: {})'.format(DEFAULT_MODEL)
    )
    parser.add_argument(
        '--api-url', default=None,
        help='API endpoint URL (default: {})'.format(DEFAULT_API_URL)
    )
    parser.add_argument(
        '--timeout', type=int, default=None,
        help='Request timeout in seconds'
    )
    parser.add_argument(
        '--max-retries', type=int, default=None,
        help='Maximum retry attempts'
    )
    parser.add_argument('--config', default=None, help='Config file path (JSON)')

    parser.add_argument(
        '--log-file', default=None,
        help='Log file path (default: stderr only)'
    )
    parser.add_argument(
        '--log-level', default='WARNING',
        choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
        help='Log level (default: WARNING)'
    )

    args = parser.parse_args()

    setup_logging(args.log_file, args.log_level)

    config = {}
    if args.config:
        config = load_config(args.config)
    elif os.path.exists(CONFIG_PATH):
        config = load_config(CONFIG_PATH)

    api_url = args.api_url or config.get('api_url', DEFAULT_API_URL)
    model = args.model or config.get('model', DEFAULT_MODEL)
    timeout = args.timeout or config.get('timeout', DEFAULT_TIMEOUT)
    max_retries = args.max_retries or config.get('max_retries', DEFAULT_MAX_RETRIES)

    if logger:
        logger.debug(
            "Config: api_url=%s model=%s timeout=%d retries=%d",
            api_url, model, timeout, max_retries
        )

    if args.text:
        texts = [args.text]
    elif args.text_base64:
        try:
            decoded = base64.b64decode(args.text_base64)
            texts = [decoded.decode('utf-8')]
        except Exception as e:
            sys.stderr.write("Error: base64 decode failed: {}\n".format(e))
            sys.exit(1)
    elif args.batch_base64:
        try:
            decoded = base64.b64decode(args.batch_base64)
            texts = json.loads(decoded.decode('utf-8'))
            if not isinstance(texts, list):
                raise ValueError("Batch input must be a JSON array")
            if len(texts) == 0:
                raise ValueError("Batch input array is empty")
        except Exception as e:
            sys.stderr.write(
                "Error: batch base64 decode failed: {}\n".format(e)
            )
            sys.exit(1)
    else:
        sys.stderr.write("Error: no input provided\n")
        sys.exit(1)

    try:
        results = generate_embeddings(texts, api_url, model, timeout, max_retries)

        for i, embedding in enumerate(results):
            if embedding is None:
                print("ERROR", flush=True)
            else:
                print(','.join(map(str, embedding)), flush=True)

    except Exception as e:
        sys.stderr.write("Error: {}\n".format(e))
        sys.exit(1)


if __name__ == '__main__':
    main()

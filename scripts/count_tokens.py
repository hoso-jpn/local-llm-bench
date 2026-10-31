#!/usr/bin/env python3
"""プロンプト素材のトークン数を、モデル自身の tokenizer で数える。
使い方: uv run --with transformers --with jinja2 python scripts/count_tokens.py /data/tokenizers/Qwen3.8-Flash-Next bench/prompts/*.txt
"""
import sys
from transformers import AutoTokenizer

tok = AutoTokenizer.from_pretrained(sys.argv[1])
for path in sys.argv[2:]:
    text = open(path, encoding="utf-8").read()
    n = len(tok.encode(text, add_special_tokens=False))
    print(f"{path}: {len(text):,} chars, {n:,} tokens ({len(text)/n:.2f} chars/token)")

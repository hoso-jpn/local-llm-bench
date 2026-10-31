#!/usr/bin/env bash
# Qwen3.8-Flash-Next の公式 tokenizer（重みなし、数MB）を取得し、GGUF に入っている tokenizer と一致するかを確かめる。
# Strata のパックの tokenizer は transformers の形式ではないため、計測スクリプトのトークン数の基準にはこちらを使う。
# 使い方: bash scripts/fetch_tokenizer.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DEST=/data/tokenizers/Qwen3.8-Flash-Next
sudo mkdir -p "$DEST" && sudo chown "$USER" "$DEST"
uv run --with huggingface_hub python - "$DEST" <<'PY'
import sys
from huggingface_hub import snapshot_download
p = snapshot_download("Qwen/Qwen3.8-Flash-Next", local_dir=sys.argv[1],
                      allow_patterns=["tokenizer*", "vocab*", "merges*", "special_tokens_map.json",
                                      "chat_template*", "config.json", "generation_config.json"])
print("downloaded:", p)
PY
ls -la "$DEST"
echo "== GGUF の tokenizer と比べる（FreeToken 付属の tok_compare.py。0 differing なら一致） =="
docker run --rm --network none --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v /data/strata/models/IQ3_XXS:/gguf:ro -v "$DEST":/hf:ro seedcore-freetoken:127aa0a920ce-cu130-v1 \
  sh -c 'cd /opt/freetoken-src && PYTHONPATH=python python scripts/gguf_check/tok_compare.py /gguf/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf /hf'

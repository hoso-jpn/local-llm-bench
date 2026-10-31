#!/usr/bin/env bash
# FreeToken を Docker で起動する（ホストの 127.0.0.1:8081 に公開）。
# 使い方:
#   bash configs/freetoken/run.sh gguf-iq3_xxs    # トラックA：Strata と同じ GGUF。prefix cache なし
#   bash configs/freetoken/run.sh nvfp4           # トラックB：NVFP4（前回記事の構成を v0.2.0 で）
# 環境変数:
#   FT_IMAGE   イメージ（既定 v0.2.0）。前回記事の 0.1.2 なら seedcore-freetoken:4b94bdc38a46-cu130-v1
#   FT_STATS=1 expert キャッシュの hit 率をログに出す（--moe-collect-stats。decode が少し遅くなる）
#   FT_CACHE   prefix cache（naive | radix）。トラックCでは radix
#   FT_EXTRA   追加の ft serve 引数
# 前提: Strata など他のエンジンが止まっていること。
set -eu
MODE="${1:?gguf-iq3_xxs か nvfp4 を指定}"; NAME="${2:-freetoken-bench}"
IMG="${FT_IMAGE:-seedcore-freetoken:127aa0a920ce-cu130-v1}"
if docker ps --format '{{.Names}}' | grep -Eq 'strata|freetoken'; then
  echo "別のエンジンが動いています。先に止めてください:" >&2; docker ps --format '  {{.Names}}' | grep -E 'strata|freetoken' >&2; exit 1
fi
case "$MODE" in
  gguf-iq3_xxs)
    MOUNT=(-v /data/strata/models/IQ3_XXS:/models:ro)
    MODEL=/models/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf
    SERVED=qwen3.8-flash-next-iq3_xxs
    CACHE="${FT_CACHE:-naive}" ;;
  nvfp4)
    MOUNT=(-v /data/freetoken-flash-next/models/Qwen3.8-Flash-Next-NVFP4:/models:ro)
    MODEL=/models
    SERVED=qwen3.8-flash-next-nvfp4
    CACHE="${FT_CACHE:-radix}" ;;
  *) echo "未知のモード: $MODE" >&2; exit 1 ;;
esac
# 前回記事（0.1.2）の起動オプションを v0.2.0 の名前で引き継ぐ（seedcore-ops/docs/FREETOKEN-MEMORY.md）
ARGS=(--model-path "$MODEL" --served-model-name "$SERVED" --host 0.0.0.0 --port 8080
      --moe-strategy offload --moe-cache-auto --memory-ratio 0.88
      --max-running-requests 1 --max-seq-len-override 32768
      --max-prefill-length 2048 --kv-reserve-tokens 32768 --moe-cpu-threads 16
      --cache-type "$CACHE" --enable-cache-report)
[ "${FT_STATS:-0}" = 1 ] && ARGS+=(--moe-collect-stats)
# shellcheck disable=SC2206
[ -n "${FT_EXTRA:-}" ] && ARGS+=($FT_EXTRA)
# JIT でコンパイルしたカーネル（Triton、tvm-ffi）をホストに残し、2回目以降の起動を速くする。
# 初回起動では CUDA graph の取り込みに約190秒かかった（2026-10-31）。版ごとに分ける。
CACHE_DIR="/data/freetoken-bench/cache/${IMG##*:}"
sudo mkdir -p "$CACHE_DIR"
docker run -d --name "$NAME" --gpus device=0 -p 127.0.0.1:8081:8080 \
  --memory 118g --memory-swap 118g --shm-size 64m --ipc host --ulimit memlock=-1 \
  -v "$CACHE_DIR:/root/.cache" -e TRITON_CACHE_DIR=/root/.cache/triton \
  "${MOUNT[@]}" "$IMG" ft serve "${ARGS[@]}"
echo "起動中: $NAME（$MODE、$IMG）"
echo "ft serve ${ARGS[*]}"
echo "準備完了を待つ: until curl -sf http://127.0.0.1:8081/health >/dev/null; do sleep 5; done; echo ready"

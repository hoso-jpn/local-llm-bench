#!/usr/bin/env bash
# FreeToken を Docker で起動する（ホストの 127.0.0.1:8081 に公開）。
# 使い方:
#   bash configs/freetoken/run.sh gguf-iq3_xxs    # トラックA：Strata と同じ GGUF。prefix cache なし
#   bash configs/freetoken/run.sh nvfp4           # トラックB：NVFP4（前回記事の構成を v0.2.0 で）
# 環境変数:
#   FT_IMAGE   イメージ（既定 v0.2.0）。前回記事の 0.1.2 なら seedcore-freetoken:4b94bdc38a46-cu130-v1
#   FT_STATS=1 expert キャッシュの hit 率をログに出す（--moe-collect-stats。decode が少し遅くなる）
#   FT_CACHE   prefix cache（naive | radix）。トラックCでは radix
#   FT_PREFILL prefill のチャンク（既定 8192。前回記事とトラックA本計測は 2048。results/2026-11-01_trackA_ft_prefill8192/）
#   FT_CTX     コンテキスト長（既定 32768）。KV キャッシュもこの長さぶん確保する（その分 expert のスロットが減る）
#   FT_STRATEGY       MoE の戦略（既定 offload）。hybrid にすると、キャッシュにない expert の一部を CPU で計算する（Issue #9）
#   FT_HYBRID_FETCH   hybrid のとき --moe-hybrid-max-fetch に渡す値（既定 -1 = auto。ft bench bw の結果から決まる。0 = すべて CPU）
#   FT_EXTRA   追加の ft serve 引数
# 前提: Strata など他のエンジンが止まっていること。
set -eu
MODE="${1:?gguf-iq3_xxs か nvfp4 を指定}"; NAME="${2:-freetoken-bench}"
IMG="${FT_IMAGE:-seedcore-freetoken:127aa0a920ce-cu130-v1}"
if docker ps --format '{{.Names}}' | grep -Eq 'strata|freetoken'; then
  echo "別のエンジンが動いています。先に止めてください:" >&2; docker ps --format '  {{.Names}}' | grep -E 'strata|freetoken' >&2; exit 1
fi
EXTRA_MODE=()
case "$MODE" in
  gguf-iq3_xxs)
    MOUNT=(-v /data/strata/models/IQ3_XXS:/models:ro)
    MODEL=/models/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_XXS-00001-of-00002.gguf
    SERVED=qwen3.8-flash-next-iq3_xxs
    CACHE="${FT_CACHE:-naive}" ;;
  nvfp4)
    # RadixArk/Qwen3.8-Flash-Next-NVFP4（Hugging Face 形式、ModelOpt の W4A4）。前回記事と同じファイル。
    # v0.2.0 の checkpoint_diagnose で PASS（results/2026-11-01_env/nvfp4_diagnose.txt）。画像エンコーダーを含むので text-only で起動する
    MOUNT=(-v /data/freetoken-flash-next/models/Qwen3.8-Flash-Next-NVFP4:/models:ro)
    MODEL=/models
    SERVED=qwen3.8-flash-next-nvfp4
    EXTRA_MODE=(--text-model-only)
    CACHE="${FT_CACHE:-radix}" ;;
  *) echo "未知のモード: $MODE" >&2; exit 1 ;;
esac
# 前回記事（0.1.2）の起動オプションを v0.2.0 の名前で引き継ぐ（seedcore-ops/docs/FREETOKEN-MEMORY.md）。
# ただし prefill のチャンクは、2026-11-01 の感度確認を受けて 2048 から 8192 に変えた
ARGS=(--model-path "$MODEL" --served-model-name "$SERVED" --host 0.0.0.0 --port 8080
      --moe-strategy "${FT_STRATEGY:-offload}" --moe-cache-auto --memory-ratio 0.88
      --max-running-requests 1 --max-seq-len-override "${FT_CTX:-32768}"
      --max-prefill-length "${FT_PREFILL:-8192}" --kv-reserve-tokens "${FT_CTX:-32768}" --moe-cpu-threads 16
      --cache-type "$CACHE" --enable-cache-report)
ARGS+=("${EXTRA_MODE[@]}")
case "${FT_STRATEGY:-offload}" in
  offload) ;;
  hybrid)  ARGS+=(--moe-hybrid-max-fetch "${FT_HYBRID_FETCH:--1}") ;;
  *) echo "FT_STRATEGY は offload か hybrid: ${FT_STRATEGY}" >&2; exit 1 ;;
esac
[ "${FT_STATS:-0}" = 1 ] && ARGS+=(--moe-collect-stats)
# shellcheck disable=SC2206
[ -n "${FT_EXTRA:-}" ] && ARGS+=($FT_EXTRA)
# JIT でコンパイルしたカーネル（Triton、tvm-ffi）をホストに残し、2回目以降の起動を速くする。
# 初回起動では CUDA graph の取り込みに約190秒かかった（2026-10-31）。版ごとに分ける。
CACHE_DIR="/data/freetoken-bench/cache/${IMG##*:}"
mkdir -p "$CACHE_DIR"   # 親が書き込めない場合: sudo bash scripts/prepare_dirs.sh
docker run -d --name "$NAME" --gpus device=0 -p 127.0.0.1:8081:8080 \
  --memory 118g --memory-swap 118g --shm-size 64m --ipc host --ulimit memlock=-1 \
  -v "$CACHE_DIR:/root/.cache" -e TRITON_CACHE_DIR=/root/.cache/triton \
  "${MOUNT[@]}" "$IMG" ft serve "${ARGS[@]}"
echo "起動中: $NAME（$MODE、$IMG）"
echo "ft serve ${ARGS[*]}"
echo "準備完了を待つ: until curl -sf http://127.0.0.1:8081/health >/dev/null; do sleep 5; done; echo ready"

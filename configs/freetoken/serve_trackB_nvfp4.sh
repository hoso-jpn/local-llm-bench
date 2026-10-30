#!/usr/bin/env bash
# トラックB：FreeToken の推奨構成（NVFP4）。前回記事の構成を v0.2.0 で再現する。
# v0.2.0 では sm_120（RTX 50xx）で NVFP4 が W4A4 で動く。比較用に W4A16（triton）も取る。
set -eu
ft serve --model RadixArk/Qwen3.8-Flash-Next-NVFP4 \
  --moe-strategy offload \
  --text-model-only \
  --port 8080
# 比較用（前回と同じカーネル）：--quant-backend moe.nvfp4=triton
# 前回の主要設定：attention backend qsa_sparse / MoE CPU threads 16 / max_running_req 1 / max context 32768

#!/usr/bin/env bash
# トラックA：FreeToken で GSQ-RCO GGUF を提供する（MTPなし）。
# 前提：FreeToken v0.2.0 以降（GGUF の qwen4exp に対応）。
# TODO(Issue #2, #3)：GGUF の読み込みと MTP の扱いを確認してから値を確定する。
set -eu
MODEL="${MODEL:-$HOME/models/Qwen3.8-Flash-Next-GSQ-RCO-GGUF/IQ3_XXS/first-shard.gguf}"  # 先頭シャードを指定
ft serve --model "$MODEL" \
  --moe-strategy offload \
  --text-model-only \
  --port 8080
# 確認すること：
#  - n-gram表（PLE）と MTP 層が別ファイルの場合の指定方法
#  - context 長の指定（Strata と揃える。例：32768）
#  - prefix cache を無効にするオプションの有無（なければ nonce で回避）

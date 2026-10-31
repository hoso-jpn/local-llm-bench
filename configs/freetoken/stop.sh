#!/usr/bin/env bash
# FreeToken を止める前に、ログと起動条件を結果ディレクトリに保存する。
# 使い方: bash configs/freetoken/stop.sh results/<run> [コンテナ名]
set -eu
OUT="$1"; NAME="${2:-freetoken-bench}"
mkdir -p "$OUT"
docker logs "$NAME" > "$OUT/freetoken.log" 2>&1
docker inspect "$NAME" --format '{{.Config.Image}} {{json .Args}}' > "$OUT/freetoken_args.txt"
docker stop "$NAME" >/dev/null && docker rm "$NAME" >/dev/null
gzip -f "$OUT/freetoken.log"
echo "保存して停止しました: $OUT"; ls -la "$OUT"

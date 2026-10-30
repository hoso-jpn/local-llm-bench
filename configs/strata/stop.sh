#!/usr/bin/env bash
# Strata を止める前に、エンジンのログとコンテナのログを結果ディレクトリに保存する。
# 使い方: bash configs/strata/stop.sh results/<run> [コンテナ名]
set -eu
OUT="$1"; NAME="${2:-strata-bench}"
mkdir -p "$OUT"
docker exec "$NAME" sh -c 'ls /opt/strata/strata-*.log' 2>/dev/null | while read -r f; do
  docker cp "$NAME:$f" "$OUT/engine-$(basename "$f")"
done
docker logs "$NAME" > "$OUT/container.log" 2>&1
docker exec "$NAME" env | grep STRATA_ > "$OUT/strata_env.txt" || echo "(STRATA_* なし)" > "$OUT/strata_env.txt"
docker stop "$NAME" >/dev/null && docker rm "$NAME" >/dev/null
gzip -f "$OUT"/engine-*.log "$OUT/container.log" 2>/dev/null || true
echo "保存して停止しました: $OUT"
ls -la "$OUT"

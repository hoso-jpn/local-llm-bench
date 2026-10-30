#!/usr/bin/env bash
# Strata をリポジトリの設定ファイルで起動する（ホストの 127.0.0.1:8082 に公開）。
# 使い方:
#   TAIL_SKIP=0 bash configs/strata/run.sh configs/strata/strata-iq3_xxs-trackA.json   # トラックA
#               bash configs/strata/run.sh configs/strata/strata-iq3_xxs-shipped.json  # トラックB（tail skip は既定のまま）
# 前提: FreeToken など他のエンジンが止まっていること。モデルは /data/strata に取得済みであること。
set -eu
CFG="$1"; NAME="${2:-strata-bench}"; MODEL="${MODEL:-IQ3_XXS}"
BASE="$(basename "$CFG")"
if docker ps --format '{{.Names}}' | grep -qi freetoken; then
  echo "FreeToken が動いています。先に止めてください（RAM が足りなくなります）" >&2; exit 1
fi
sudo cp "$CFG" "/data/strata/config/$BASE"
ENVS=(-e MODEL="$MODEL" -e FAMILY=qwen -e CONTEXT=32768 -e VISION=no -e KV=int8 -e CONFIG="/data/config/$BASE")
if [ -n "${TAIL_SKIP+x}" ]; then ENVS+=(-e STRATA_ROUTE_TAIL_SKIP="$TAIL_SKIP"); fi
docker run -d --name "$NAME" --gpus device=0 -p 127.0.0.1:8082:8080 --ulimit memlock=-1 \
  -v /data/strata:/data "${ENVS[@]}" strata-comparison:v0.1.42
echo "起動中: $NAME（config=$BASE, STRATA_ROUTE_TAIL_SKIP=${TAIL_SKIP:-既定}）"
echo "準備完了を待つ: until curl -sf http://127.0.0.1:8082/health >/dev/null; do sleep 5; done; echo ready"

#!/usr/bin/env bash
# Strata をリポジトリの設定ファイルで起動する（ホストの 127.0.0.1:8082 に公開）。
# 使い方:
#   TAIL_SKIP=0 STRATA_EXTRA_ENV="STRATA_PREFILL_CPU_SHARE=0" \
#     bash configs/strata/run.sh configs/strata/strata-iq3_xxs-trackA.json             # トラックA
#               bash configs/strata/run.sh configs/strata/strata-iq3_xxs-shipped.json  # トラックB（tail skip は既定のまま）
# 前提: FreeToken など他のエンジンが止まっていること。モデルは /data/strata に取得済みであること。
set -eu
CFG="$1"; NAME="${2:-strata-bench}"; MODEL="${MODEL:-IQ3_XXS}"
BASE="$(basename "$CFG")"
if docker ps --format '{{.Names}}' | grep -qi freetoken; then
  echo "FreeToken が動いています。先に止めてください（RAM が足りなくなります）" >&2; exit 1
fi
# STRATA_CTX があれば --max-context を置き換えた設定を作る（長い文脈・長い生成の評価用）
if [ -n "${STRATA_CTX:-}" ]; then
  BASE="${BASE%.json}-ctx${STRATA_CTX}.json"
  python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); a=c["args"]; a[a.index("--max-context")+1]=sys.argv[2]; json.dump(c,open(sys.argv[3],"w"),indent=1)' \
    "$CFG" "$STRATA_CTX" "/data/strata/config/$BASE"
else
  cp "$CFG" "/data/strata/config/$BASE"   # 書き込めない場合: sudo bash scripts/prepare_dirs.sh
fi
ENVS=(-e MODEL="$MODEL" -e FAMILY=qwen -e CONTEXT=32768 -e VISION=no -e KV=int8 -e CONFIG="/data/config/$BASE")
if [ -n "${TAIL_SKIP+x}" ]; then ENVS+=(-e STRATA_ROUTE_TAIL_SKIP="$TAIL_SKIP"); fi
# 追加の環境変数（空白区切りの KEY=VALUE）。トラックAでは STRATA_PREFILL_CPU_SHARE=0
for kv in ${STRATA_EXTRA_ENV:-}; do ENVS+=(-e "$kv"); done
docker run -d --name "$NAME" --gpus device=0 -p 127.0.0.1:8082:8080 --ulimit memlock=-1 \
  -v /data/strata:/data "${ENVS[@]}" strata-comparison:v0.1.42
echo "起動中: $NAME（config=$BASE, STRATA_ROUTE_TAIL_SKIP=${TAIL_SKIP:-既定}）"
echo "準備完了を待つ: until curl -sf http://127.0.0.1:8082/health >/dev/null; do sleep 5; done; echo ready"

#!/usr/bin/env bash
# 1つのエンジンを起動し、準備完了を待って計測し、ログを保存して止めるまでを行う。
# 使い方:
#   bash scripts/run_track.sh <engine> <track> <出力ディレクトリ> [llm_engine_bench.py に渡す引数...]
#   engine: freetoken | strata     track: A | B
# 例（試運転）:
#   bash scripts/run_track.sh freetoken A results/2026-10-31_smoke/freetoken \
#     --source bench/prompts/code.txt --prompt-kind code --input-lens 4096 --output-lens 256 --runs 2
# 環境変数:
#   KINDS="code ja"  1回の起動で、bench/prompts/<kind>.txt を順に測る（--source と --prompt-kind は自動で付く）
#   SESSION=s1       セッション名を --label として記録する（同じ構成を別々に起動した回を区別する）
set -euo pipefail
cd "$(dirname "$0")/.."
ENGINE="$1"; TRACK="$2"; OUT="$3"; shift 3
mkdir -p "$OUT"
# 計測の途中では sudo を使わない（バックグラウンド実行中にパスワードを求めて止まるため）。
# 書き込み先は事前に scripts/prepare_dirs.sh で自分の持ち物にしておく
for d in /data/strata/config /data/freetoken-bench/cache; do
  if [ ! -w "$d" ]; then echo "$d に書き込めません。先に: sudo bash scripts/prepare_dirs.sh" >&2; exit 1; fi
done
TOKENIZER="${TOKENIZER:-/data/tokenizers/Qwen3.8-Flash-Next}"
READY_TIMEOUT="${READY_TIMEOUT:-1200}"

case "$ENGINE/$TRACK" in
  freetoken/A) URL=http://127.0.0.1:8081; MODEL=qwen3.8-flash-next-iq3_xxs; FILE=GSQ-RCO-IQ3_XXS
               START=(env FT_STATS=0 bash configs/freetoken/run.sh gguf-iq3_xxs) ;;
  freetoken/B) URL=http://127.0.0.1:8081; MODEL=qwen3.8-flash-next-nvfp4; FILE=NVFP4
               START=(env FT_STATS=0 bash configs/freetoken/run.sh nvfp4) ;;
  strata/A)    URL=http://127.0.0.1:8082; MODEL=qwen3.8-flash-next-iq3_xxs; FILE=GSQ-RCO-IQ3_XXS
               START=(env TAIL_SKIP=0 STRATA_EXTRA_ENV="STRATA_PREFILL_CPU_SHARE=0" bash configs/strata/run.sh configs/strata/strata-iq3_xxs-trackA.json) ;;
  strata/B)    URL=http://127.0.0.1:8082; MODEL=qwen3.8-flash-next-iq3_xxs; FILE=GSQ-RCO-IQ3_XXS
               START=(bash configs/strata/run.sh configs/strata/strata-iq3_xxs-shipped.json) ;;
  *) echo "未対応: $ENGINE/$TRACK" >&2; exit 1 ;;
esac

echo "== [$(date +%T)] 環境を記録"
bash scripts/env_check.sh "$OUT/env_check.txt" > /dev/null 2>&1 || true
git rev-parse HEAD > "$OUT/repo_commit.txt"

echo "== [$(date +%T)] 起動: ${START[*]}"
T0=$(date +%s)
"${START[@]}"
# /health は読み込み中でも 200 を返すエンジンがある（FreeToken）。短い生成が成功するまで待つ
PROBE='{"model":"'"$MODEL"'","messages":[{"role":"user","content":"hi"}],"max_tokens":1,"temperature":0,"reasoning_effort":"none"}'
until [ "$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d "$PROBE" "$URL/v1/chat/completions")" = 200 ]; do
  sleep 5
  if (( $(date +%s) - T0 > READY_TIMEOUT )); then
    echo "準備完了せず（${READY_TIMEOUT}秒）。ログを保存して止めます" >&2
    if [ "$ENGINE" = freetoken ]; then bash configs/freetoken/stop.sh "$OUT"; else bash configs/strata/stop.sh "$OUT"; fi
    exit 1
  fi
done
echo "ready_after_s=$(( $(date +%s) - T0 ))" | tee "$OUT/startup.txt"

echo "== [$(date +%T)] 計測（PCIe・GPU を1秒ごとに記録）"
nvidia-smi --query-gpu=timestamp,pcie.link.gen.current,pcie.link.width.current,utilization.gpu,memory.used,power.draw \
  --format=csv -l 1 > "$OUT/gpu.csv" & SMI=$!
bench() {
  uv run -q --with transformers --with jinja2 --with nvidia-ml-py python bench/llm_engine_bench.py \
    --base-url "$URL/v1" --model "$MODEL" --engine "$ENGINE" --track "$TRACK" --model-file "$FILE" \
    --tokenizer "$TOKENIZER" --label "${SESSION:-}" --out "$OUT/results.jsonl" "$@" 2>&1 | tee -a "$OUT/bench_stdout.txt"
  return "${PIPESTATUS[0]}"
}
set +e
RC=0
if [ -n "${KINDS:-}" ]; then
  for k in $KINDS; do bench --source "bench/prompts/$k.txt" --prompt-kind "$k" "$@" || RC=$?; done
else
  bench "$@" || RC=$?
fi
set -e
kill $SMI 2>/dev/null || true

echo "== [$(date +%T)] 停止してログを保存"
if [ "$ENGINE" = freetoken ]; then bash configs/freetoken/stop.sh "$OUT"; else bash configs/strata/stop.sh "$OUT"; fi
echo "== 集計"
python3 bench/llm_engine_bench.py --summarize "$OUT/results.jsonl" | tee "$OUT/summary.tsv"
exit $RC

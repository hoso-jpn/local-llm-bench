#!/usr/bin/env bash
# トラックAの本計測。ABBA の順（FreeToken → Strata → Strata → FreeToken）で、各エンジンを2回ずつ別々に起動して測る。
# 起動し直したときの差（試運転で約6%）がセッション内の差より大きいため、1構成を2セッションに分ける。
# 使い方: bash scripts/run_trackA_full.sh results/<日付>_trackA
#   途中から再開する: STEPS="strata:s1 strata:s2 freetoken:s2" bash scripts/run_trackA_full.sh results/<日付>_trackA
# 前提: <出力先>/prereg.md をコミット済みであること（事前登録）
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?出力ディレクトリを指定}"
if ! git ls-files --error-unmatch "$OUT/prereg.md" > /dev/null 2>&1; then
  echo "$OUT/prereg.md がコミットされていません。計測の前に事前登録をコミットしてください" >&2; exit 1
fi
# コンテキストは 32,768（前回記事と同じ）。入力＋出力がそれを超えないよう、最長は 30,720 トークン
GRID=(--input-lens 1024,4096,16384,30720 --output-lens 256,1024 --runs 5 --warmup 1)
export KINDS="code ja"
for step in ${STEPS:-freetoken:s1 strata:s1 strata:s2 freetoken:s2}; do
  set -- ${step/:/ }
  echo "######## [$(date +%T)] $1 / $2"
  SESSION="$2" bash scripts/run_track.sh "$1" A "$OUT/$1_$2" "${GRID[@]}" || echo "!! $1 $2 が失敗。続けます" >&2
  sleep 30   # GPU の温度を落ち着かせる
done
echo "######## 全体の集計"
cat "$OUT"/*/results.jsonl > "$OUT/all.jsonl"
python3 bench/llm_engine_bench.py --summarize "$OUT/all.jsonl" | tee "$OUT/summary.tsv"

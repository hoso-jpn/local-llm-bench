#!/usr/bin/env bash
# 品質評価：4つの構成を順に起動し、同じ問題を解かせて採点・集計する。
#   FreeToken A（GGUF IQ3_XXS、近似なし） / Strata A（同じ GGUF、下書き0・近似なし）
#   Strata B（IQ3_S、出荷状態：MTP・tail skip あり） / FreeToken B（NVFP4）
# 使い方: bash scripts/run_quality_all.sh results/<日付>_quality
#   途中から: STEPS="freetoken:B" bash scripts/run_quality_all.sh results/<日付>_quality（再開時は解いた問題を飛ばす）
# 前提: <出力先>/prereg.md をコミット済み、data/quality/ を作成済み（quality_eval.py prepare）
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?出力ディレクトリを指定}"
git ls-files --error-unmatch "$OUT/prereg.md" > /dev/null 2>&1 || { echo "$OUT/prereg.md をコミットしてください" >&2; exit 1; }
ls data/quality/{gsm8k,humaneval,jcqa,json}.jsonl > /dev/null || { echo "先に quality_eval.py prepare を実行してください" >&2; exit 1; }
docker image inspect python:3.12 > /dev/null || { echo "HumanEval の実行用イメージ python:3.12 がありません" >&2; exit 1; }
export BENCH=quality
for step in ${STEPS:-strata:B strata:A freetoken:A freetoken:B}; do
  set -- ${step/:/ }
  echo "######## [$(date +%T)] $1 / $2"
  QLABEL="$1-$2" bash scripts/run_track.sh "$1" "$2" "$OUT/$1_$2" \
    --tasks gsm8k,humaneval,jcqa,json --effort low --max-tokens 4096 || echo "!! $1 $2 が失敗。続けます" >&2
  sleep 30
done
echo "######## 採点（HumanEval はネットワークなしのコンテナで実行）"
python3 bench/quality_eval.py score "$OUT"/*/quality.jsonl
python3 bench/quality_eval.py report "$OUT"/*/scored.jsonl | tee "$OUT/report.md"
{
  echo; echo "## 同じ重み（IQ3_XXS）でのエンジン間の一致"
  python3 bench/quality_eval.py compare "$OUT/freetoken_A/scored.jsonl" "$OUT/strata_A/scored.jsonl"
  echo; echo "## Strata：近似なし（A、IQ3_XXS）と出荷状態（B、IQ3_S）"
  python3 bench/quality_eval.py compare "$OUT/strata_A/scored.jsonl" "$OUT/strata_B/scored.jsonl"
} | tee -a "$OUT/report.md"

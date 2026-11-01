#!/usr/bin/env bash
# 難しい推論・長い生成・長い文脈の評価を一晩で流す（9〜10時間）。
#   1. 長い文脈（16K〜128K、3課題 × 4長さ × 10問）：Strata IQ3_XXS・IQ3_S、FreeToken NVFP4。コンテキスト 135,168
#   2. 長い文脈の速度（64K・128K、トラックBの計測）：同じ3構成
#   3. 難しい推論（AIME 60問＋MATH-500 レベル5 134問、thinking high、最大 32,768）：Strata 2構成は全問、NVFP4 は AIME のみ
# 使い方: bash scripts/run_hard_all.sh results/<日付>_hard
#   途中から: STEPS="hard:freetoken:B" bash scripts/run_hard_all.sh ...（解いた問題は飛ばす）
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?出力ディレクトリを指定}"
git ls-files --error-unmatch "$OUT/prereg.md" > /dev/null 2>&1 || { echo "$OUT/prereg.md をコミットしてください" >&2; exit 1; }
for f in aime math5 lc; do [ -s "data/quality/$f.jsonl" ] || { echo "data/quality/$f.jsonl がありません" >&2; exit 1; }; done
LC_CTX=135168; HARD_CTX=36864
DEFAULT_STEPS="lc:strata:BX lc:strata:B lc:freetoken:B speed:strata:BX speed:strata:B speed:freetoken:B hard:strata:BX hard:strata:B hard:freetoken:B"
for step in ${STEPS:-$DEFAULT_STEPS}; do
  IFS=: read -r kind eng trk <<< "$step"
  D="$OUT/${kind}_${eng}_${trk}"
  echo "######## [$(date +%T)] $kind / $eng / $trk"
  case "$kind" in
    lc)    STRATA_CTX=$LC_CTX FT_CTX=$LC_CTX BENCH=quality QUALITY_FILES=lc QLABEL="$eng-$trk" \
             bash scripts/run_track.sh "$eng" "$trk" "$D" --tasks lc --effort low --max-tokens 4096 || echo "!! $step 失敗" >&2 ;;
    speed) STRATA_CTX=$LC_CTX FT_CTX=$LC_CTX KINDS="code ja" SESSION=s1 \
             bash scripts/run_track.sh "$eng" "$trk" "$D" --input-lens 65536,131072 --output-lens 256 --runs 3 --warmup 1 \
             --timeout 3600 || echo "!! $step 失敗" >&2 ;;
    hard)  T=aime,math5; [ "$eng" = freetoken ] && T=aime
           STRATA_CTX=$HARD_CTX FT_CTX=$HARD_CTX BENCH=quality QUALITY_FILES="aime math5" QLABEL="$eng-$trk" \
             bash scripts/run_track.sh "$eng" "$trk" "$D" --tasks "$T" --effort high --max-tokens 32768 || echo "!! $step 失敗" >&2 ;;
  esac
  sleep 30
done
echo "######## 採点と集計"
uv run -q --with "math-verify[antlr4_13_2]" python bench/quality_eval.py score "$OUT"/lc_*/quality.jsonl "$OUT"/hard_*/quality.jsonl
uv run -q --with "math-verify[antlr4_13_2]" python bench/quality_eval.py report "$OUT"/lc_*/scored.jsonl "$OUT"/hard_*/scored.jsonl | tee "$OUT/report.md"
{
  echo; echo "## 難しい推論：IQ3_XXS と IQ3_S（Strata、出荷状態）"
  python3 bench/quality_eval.py compare "$OUT/hard_strata_BX/scored.jsonl" "$OUT/hard_strata_B/scored.jsonl"
  echo; echo "## 長い文脈の速度"
  cat "$OUT"/speed_*/results.jsonl > "$OUT/speed_all.jsonl"
  python3 bench/llm_engine_bench.py --summarize "$OUT/speed_all.jsonl"
} | tee -a "$OUT/report.md"

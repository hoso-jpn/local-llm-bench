#!/usr/bin/env bash
# Issue #9：FreeToken の offload（トラックB と同じ）と hybrid を、同じ条件で ABBA の順に測る。
#   B  = offload（configs/freetoken/run.sh nvfp4。トラックB と同じ）
#   H  = hybrid、--moe-hybrid-max-fetch -1（auto：ft bench bw の結果から PCIe で運ぶ割合を決める）
#   H0 = hybrid、--moe-hybrid-max-fetch 0（PCIe からは運ばず、キャッシュにない expert をすべて CPU で計算。余力があれば）
# 使い方:
#   bash scripts/run_ft_hybrid.sh results/<日付>_ft_hybrid                      # 速度：B s1 → H s1 → H s2 → B s2
#   STEPS="H0:s1" bash scripts/run_ft_hybrid.sh results/<日付>_ft_hybrid        # 追加や再開
#   QUALITY=1 bash scripts/run_ft_hybrid.sh results/<日付>_ft_hybrid            # 速度のあと、H で品質評価（約2時間）
# 品質評価は、2026-11-01_quality の freetoken_B（offload）と答えの一致を比べる。
# 前提: <出力先>/prereg.md をコミット済み。scripts/ft_bench_bw.sh を実行済み（H の auto がその結果を使う）
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?出力ディレクトリを指定}"
git ls-files --error-unmatch "$OUT/prereg.md" > /dev/null 2>&1 || { echo "$OUT/prereg.md をコミットしてください（事前登録）" >&2; exit 1; }
# トラックB と同じグリッド（コード・日本語 × 入力 1K / 4K / 16K / 30K × 出力 256 / 1,024、捨て1回＋本計測5回）
GRID=(--input-lens 1024,4096,16384,30720 --output-lens 256,1024 --runs 5 --warmup 1)
export KINDS="code ja"
if [ "${QUALITY_ONLY:-0}" != 1 ]; then
  for step in ${STEPS:-B:s1 H:s1 H:s2 B:s2}; do
    set -- ${step/:/ }
    echo "######## [$(date +%T)] freetoken $1 / $2"
    SESSION="$2" bash scripts/run_track.sh freetoken "$1" "$OUT/freetoken_$1_$2" "${GRID[@]}" || echo "!! $1 $2 が失敗。続けます" >&2
    # hybrid が有効になったかを起動ログで確かめる（ログは stop.sh が freetoken.log.gz に保存）
    zgrep -Eai 'moe[-_ ]?strategy|hybrid|max[-_ ]fetch|bench bw' "$OUT/freetoken_$1_$2/freetoken.log.gz" 2>/dev/null | head -20 \
      > "$OUT/freetoken_$1_$2/strategy_log.txt" || true
    sleep 30   # GPU の温度を落ち着かせる
  done
  echo "######## 速度の集計"
  cat "$OUT"/freetoken_*_s*/results.jsonl > "$OUT/all.jsonl"
  python3 bench/llm_engine_bench.py --summarize "$OUT/all.jsonl" | tee "$OUT/summary.tsv"
fi
if [ "${QUALITY:-0}" = 1 ] || [ "${QUALITY_ONLY:-0}" = 1 ]; then
  BASE=results/2026-11-01_quality/freetoken_B/scored.jsonl
  [ -s "$BASE" ] || { echo "$BASE がありません" >&2; exit 1; }
  ls data/quality/{gsm8k,humaneval,jcqa,json}.jsonl > /dev/null || { echo "先に quality_eval.py prepare を実行してください" >&2; exit 1; }
  echo "######## [$(date +%T)] 品質評価：freetoken H（2026-11-01_quality と同じ課題・設定）"
  KINDS= BENCH=quality QLABEL=freetoken-H bash scripts/run_track.sh freetoken H "$OUT/quality_H" \
    --tasks gsm8k,humaneval,jcqa,json --effort low --max-tokens 4096
  python3 bench/quality_eval.py score "$OUT/quality_H/quality.jsonl"
  {
    python3 bench/quality_eval.py report "$BASE" "$OUT/quality_H/scored.jsonl"
    echo; echo "## offload（2026-11-01_quality の freetoken_B）と hybrid（H）の答えの一致"
    python3 bench/quality_eval.py compare "$BASE" "$OUT/quality_H/scored.jsonl"
  } | tee "$OUT/quality_report.md"
fi

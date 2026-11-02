#!/usr/bin/env bash
# FreeToken v0.2.0 の `ft bench bw` を NVFP4 のチェックポイントで実行し、結果を保存する（Issue #9）。
# hybrid の --moe-hybrid-max-fetch -1（auto）は、この結果から PCIe で運ぶ割合を決める。
# serve と同じキャッシュ（/root/.cache）をマウントするので、結果がキャッシュに保存される場合は serve からも見える。
# 使い方: bash scripts/ft_bench_bw.sh results/<日付>_env
# 前提: Strata・FreeToken のどちらも止まっていること。sudo は使わない
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?出力ディレクトリを指定}"; mkdir -p "$OUT"
IMG="${FT_IMAGE:-seedcore-freetoken:127aa0a920ce-cu130-v1}"
if docker ps --format '{{.Names}}' | grep -Eq 'strata|freetoken'; then
  echo "別のエンジンが動いています。先に止めてください:" >&2; docker ps --format '  {{.Names}}' | grep -E 'strata|freetoken' >&2; exit 1
fi
CACHE_DIR="/data/freetoken-bench/cache/${IMG##*:}"
[ -w "$CACHE_DIR" ] || { echo "$CACHE_DIR に書き込めません。先に: sudo bash scripts/prepare_dirs.sh" >&2; exit 1; }
RUN=(docker run --rm --gpus device=0 --memory 118g --memory-swap 118g --shm-size 64m --ipc host --ulimit memlock=-1
     -v "$CACHE_DIR:/root/.cache" -v /data/freetoken-flash-next/models/Qwen3.8-Flash-Next-NVFP4:/models:ro "$IMG")
MARK="$OUT/.ft_bench_bw_start"; touch "$MARK"
LOG="$OUT/ft_bench_bw_nvfp4_v020.txt"
{
  echo "# ft bench bw（FreeToken v0.2.0、NVFP4）  $(date -Is)"
  echo "# image: $IMG"
  echo "# PCIe（待機中は世代が下がって見えることがある。最大値も記録）:"
  nvidia-smi --query-gpu=pcie.link.gen.current,pcie.link.width.current,pcie.link.gen.max,pcie.link.width.max --format=csv 2>&1 || true
  echo; echo "== ft bench bw --help =="
  "${RUN[@]}" ft bench bw --help 2>&1 || true
  echo; echo "== ft bench bw --model /models =="
  "${RUN[@]}" ft bench bw --model /models 2>&1
  echo; echo "== 実行中にキャッシュへ書かれたファイル =="
  find "$CACHE_DIR" -newer "$MARK" -type f -printf '%TY-%Tm-%Td %TH:%TM  %s  %p\n' 2>/dev/null | grep -v '/triton/' | head -20 || true
} 2>&1 | tee "$LOG"
rm -f "$MARK"
echo "保存しました: $LOG"

#!/usr/bin/env bash
# 負荷中のPCIe世代と幅を記録する（idle中はGen1に落ちるため）。計測中に別ターミナルで実行する。
# 使い方: bash scripts/pcie_under_load.sh results/<run>/pcie.csv 60
OUT="${1:-pcie.csv}"; SEC="${2:-60}"
nvidia-smi --query-gpu=timestamp,pcie.link.gen.current,pcie.link.width.current,utilization.gpu,power.draw \
  --format=csv -l 1 > "$OUT" & PID=$!
sleep "$SEC"; kill $PID
echo "saved: $OUT"

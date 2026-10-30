#!/usr/bin/env bash
# 計測環境を記録する。使い方: bash scripts/env_check.sh results/<run>/env_check.txt
# RAM速度の取得に sudo を使う（パスワードを一度求められる）。
set -u
export LANG=C LC_ALL=C   # lscpu などの項目名を英語に固定する
OUT="${1:-env_check.txt}"
mkdir -p "$(dirname "$OUT")"
{
echo "# recorded: $(date -Iseconds)"
echo "== GPU / PCIe =="
nvidia-smi --query-gpu=name,driver_version,pcie.link.gen.max,pcie.link.width.current,pcie.link.width.max,memory.total --format=csv
echo "== CUDA =="
command -v nvcc >/dev/null && nvcc --version | tail -1 || echo "nvcc なし"
echo "== CPU =="
lscpu | grep -E "Model name|^CPU\(s\)"
grep -q -m1 avx512f /proc/cpuinfo && echo "AVX-512 あり" || echo "AVX-512 なし"
echo "== RAM =="
free -g
sudo dmidecode -t memory | grep -E "^\s+(Size|Configured Memory Speed):" | grep -v "No Module"
echo "== Disk =="
df -h ~
lsblk -d -o NAME,MODEL,SIZE
echo "== OS =="
uname -r; lsb_release -ds
echo "== Python =="
python3 --version; command -v uv || echo "uv なし"
echo "== FreeToken =="
command -v ft >/dev/null && ft --version || (pip show freetoken 2>/dev/null | head -2 || echo "未導入")
echo "== Strata =="
command -v strata || ls -d ~/Strata 2>/dev/null || echo "未導入"
echo "== 既存モデル =="
du -sh ~/.cache/huggingface/hub/models--* 2>/dev/null | sort -h | tail
} 2>&1 | tee "$OUT"

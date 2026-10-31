#!/usr/bin/env bash
# 計測中に sudo を使わずに済むよう、エンジンが使う書き込み先を一度だけ自分の持ち物にする。
# 使い方: sudo bash scripts/prepare_dirs.sh   （計測を始める前に一度だけ）
set -euo pipefail
U="${SUDO_USER:?sudo を付けて実行してください}"
mkdir -p /data/strata/config /data/freetoken-bench/cache
chown -R "$U" /data/strata/config /data/freetoken-bench
echo "OK: /data/strata/config と /data/freetoken-bench を $U の持ち物にしました"

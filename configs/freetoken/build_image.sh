#!/usr/bin/env bash
# FreeToken のイメージを版を指定してビルドする。
# 使い方: bash configs/freetoken/build_image.sh v0.2.0   （または 0.1.2）
# ログは results/<今日>_env/freetoken_build_<版>.log に残る。
set -eu
cd "$(dirname "$0")"
case "${1:-v0.2.0}" in
  v0.2.0) REV=127aa0a920ce2ba3c3fedf66e8c31072990df1f6 ;;
  0.1.2)  REV=4b94bdc38a46a4dfe534e8793126160d56904c44 ;;
  *) echo "未知の版: $1" >&2; exit 1 ;;
esac
TAG="seedcore-freetoken:${REV:0:12}-cu130-v1"
LOG="../../results/$(date +%F)_env/freetoken_build_${1:-v0.2.0}.log"
mkdir -p "$(dirname "$LOG")"
echo "build $TAG -> $LOG"
docker build -t "$TAG" --build-arg FT_REV="$REV" -f Dockerfile . > "$LOG" 2>&1
docker run --rm "$TAG" ft --version | tee -a "$LOG"
docker run --rm --entrypoint cat "$TAG" /opt/freetoken-requirements.txt > "../../results/$(date +%F)_env/freetoken_requirements_${1:-v0.2.0}.txt"
echo "done: $TAG"

#!/usr/bin/env bash
# 計測用のプロンプト素材を作る。どちらも公開してよい素材だけを使う。
#   bench/prompts/code.txt : llama.cpp（MIT）の src/*.cpp を固定の commit で連結
#   bench/prompts/ja.txt   : 青空文庫の夏目漱石『こころ』『吾輩は猫である』（著作権切れ）からルビと注記を除いたもの
# 使い方: bash scripts/prepare_prompts.sh
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=bench/prompts
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
LLAMA_TAG="${LLAMA_TAG:-b6000}"

echo "== code.txt: llama.cpp $LLAMA_TAG =="
git clone -q --depth 1 --branch "$LLAMA_TAG" https://github.com/ggml-org/llama.cpp "$TMP/llama.cpp"
LLAMA_COMMIT="$(git -C "$TMP/llama.cpp" rev-parse HEAD)"
: > "$OUT/code.txt"
for f in $(cd "$TMP/llama.cpp" && ls src/*.cpp | sort); do
  printf '// ===== %s =====\n' "$f" >> "$OUT/code.txt"
  cat "$TMP/llama.cpp/$f" >> "$OUT/code.txt"
done

echo "== ja.txt: 青空文庫 =="
fetch_aozora() {  # $1 = zip の URL。整形はロケールに左右されないよう Python で行う
  curl -fsSL "$1" -o "$TMP/a.zip"
  rm -rf "$TMP/a" && mkdir "$TMP/a" && unzip -q -o "$TMP/a.zip" -d "$TMP/a"
  python3 - "$TMP"/a/*.txt <<'PY'
import re, sys
t = open(sys.argv[1], "rb").read().decode("cp932").replace("\r\n", "\n")
# 青空文庫の書式：冒頭の記号説明（ダッシュ行で囲まれた部分）と、末尾の底本情報を除く
parts = re.split(r"^-{20,}\s*$", t, flags=re.M)
body = parts[2] if len(parts) >= 3 else t
body = body.split("\n底本：")[0]
body = re.sub(r"《[^》]*》", "", body)    # ルビ
body = body.replace("｜", "")            # ルビの開始位置
body = re.sub(r"［＃[^］]*］", "", body)  # 入力者注
sys.stdout.write(body.strip() + "\n")
PY
}
{
  fetch_aozora https://www.aozora.gr.jp/cards/000148/files/773_ruby_5968.zip   # こころ
  printf '\n\n'
  fetch_aozora https://www.aozora.gr.jp/cards/000148/files/789_ruby_5639.zip   # 吾輩は猫である
} > "$OUT/ja.txt"

ls -la "$OUT"/*.txt
if [ "$(wc -c < "$OUT/ja.txt")" -lt 100000 ]; then echo "ja.txt が小さすぎます。取得か整形に失敗しています" >&2; exit 1; fi
head -c 300 "$OUT/ja.txt"; echo
python3 - "$LLAMA_TAG" "$LLAMA_COMMIT" <<'PY'
import sys, re
p = "bench/prompts/README.md"; s = open(p, encoding="utf-8").read()
s = re.sub(r"- code.txt：.*", f"- code.txt：llama.cpp {sys.argv[1]}（commit `{sys.argv[2]}`）の src/*.cpp を名前順に連結", s)
s = re.sub(r"- ja.txt：.*", "- ja.txt：青空文庫 夏目漱石『こころ』（773_ruby_5968）＋『吾輩は猫である』（789_ruby_5639）。ルビ・注記・底本情報を除去", s)
open(p, "w", encoding="utf-8").write(s)
PY
echo "done"

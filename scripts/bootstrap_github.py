#!/usr/bin/env python3
"""
GitHub の Label・マイルストーン・初期 Issue を登録する（gh CLI の REST API を使う）。
同じ名前の Label・マイルストーン・Issue がすでにあれば作らない。

使い方: python3 scripts/bootstrap_github.py hoso-jpn/local-llm-bench
"""
import json
import subprocess
import sys

REPO = sys.argv[1] if len(sys.argv) > 1 else "hoso-jpn/local-llm-bench"
MILESTONE = "AIと実装02：FreeToken vs Strata"

LABELS = [
    ("track:A", "1d76db", "エンジン単体（同一GGUF・MTPなし）"),
    ("track:B", "0e8a16", "出荷状態（各エンジンの推奨構成）"),
    ("track:C", "5319e7", "エージェント実戦（多ターン・prefix cache）"),
    ("type:check", "fbca04", "事前確認・調査"),
    ("type:measure", "c5def5", "計測"),
    ("type:writing", "f9d0c4", "記事の執筆"),
    ("blocker", "b60205", "これが解決しないと先に進めない"),
]

ISSUES = [
    ("環境を記録する（ステップ0）", ["type:check"], """\
Seedcore-01 の現在の構成を記録し、`docs/env/seedcore-01.md` を更新する。

- [ ] `bash scripts/env_check.sh results/<日付>_env/env_check.txt` を実行する
- [ ] 負荷中の PCIe 幅を確認する（`scripts/pcie_under_load.sh`。idle 中は Gen1 に落ちる）
- [ ] RAM の実動作速度を確認する（4 DIMM なら 3600 MT/s のはず）
- [ ] ディスクの空きを確認する（追加で約170GB必要）
- [ ] 前回からの変更（M.2 の移設、DIMM の構成）があれば変更履歴に追記する
"""),
    ("FreeToken v0.2.0 で GSQ-RCO GGUF が読めるか確認する", ["type:check", "blocker", "track:A"], """\
トラックA（同一ファイルでの比較）が成り立つかどうかを決める確認。

- [ ] FreeToken を v0.2.0 以降に更新する（前回は 0.1.2）
- [ ] `scripts/gguf_check/` で、重みをダウンロードせずに読み込めるか確認する
- [ ] ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF の IQ3_XXS（できれば IQ3_S も）を `ft serve --model <file>.gguf` で起動する
- [ ] n-gram 表（PLE）が別ファイルの場合の扱いを確認する
- [ ] 短いプロンプトで正しい出力が返ることを確認する

参考：v0.2.0 のリリースノートでは、`qwen4exp` の GGUF と IQ2_XS / IQ3_XXS / IQ3_S / Q2_0 に対応。IQ1_M は未対応。
"""),
    ("FreeToken で Qwen3.8-Flash-Next の MTP が使えるか確認する", ["type:check", "blocker", "track:B"], """\
前回記事でも未解決だった点。トラックBの解釈（B − A がMTPの寄与かどうか）に効く。

- [ ] ドキュメントと CLI のヘルプで、投機的デコードのオプションを探す
- [ ] 使える場合は ON / OFF の両方で decode を測れるようにする
- [ ] 使えない場合は、記事に「FreeToken は MTP なし」と明記する
"""),
    ("Strata を導入し、比較用の設定を確認する", ["type:check", "track:A"], """\
- [ ] `git clone https://github.com/Niko1221/Strata` して `./setup.sh` を実行する（Linux はソースからビルド。CUDA 13 が必要）
- [ ] RTX 50 シリーズと CUDA 13.2 の組み合わせで誤答が出るという既知の問題を避ける版を選ぶ
- [ ] 128GB 向けの IQ3_S と、トラックA用の IQ3_XXS を用意する
- [ ] 使ったタグと commit を記録する
- [ ] `/health` と短いプロンプトで動作を確認する
- [ ] `--spec 2 --mtp-max-t 1` でドラフトが0になることをログで確認する（`--spec 0` は起動時に拒否される）
- [ ] `STRATA_ROUTE_TAIL_SKIP=0` が効いていることを確認する
- [ ] OpenAI 互換 API で logprobs が取れるか確認する（取れなければ一致度は完全一致率と分岐位置だけにする）
- [ ] expert cache hit 率の定義を確認し、FreeToken と比べられるか判断する
"""),
    ("トラックA：同一 GGUF・MTP なしで計測する", ["type:measure", "track:A"], """\
`docs/plan.md` の計測グリッドで両エンジンを計測する。

- [ ] `results/<日付>_trackA_freetoken/prereg.md` と `..._strata/prereg.md` を計測前にコミットする
- [ ] 入力長 1K / 4K / 16K / 32K（余力があれば 64K / 128K）× 出力長 256 / 1,024 × コードと日本語
- [ ] 捨てリクエスト1回＋本計測5回。サーバは常に1つだけ起動する
- [ ] 同じ100プロンプトで greedy 出力の一致度を比べる
- [ ] PCIe（prefill 中と decode 中）、RAM、swap を記録する
"""),
    ("トラックB・C：出荷状態と多ターンで計測する", ["type:measure", "track:B", "track:C"], """\
- [ ] トラックB：FreeToken は NVFP4（W4A4 と W4A16 の両方）、Strata は IQ3_S＋MTP
- [ ] MTP の受理率をログから取る
- [ ] トラックC：`--no-nonce --turns 3` で2ターン目以降の TTFT を比べる
- [ ] コールドロード時間（ページキャッシュを捨ててから `/health` が応答するまで）
"""),
    ("品質評価（GSM8K・HumanEval・日本語・JSON）", ["type:measure", "track:A", "track:B"], """\
- [ ] GSM8K 300問、HumanEval 164問、JMMLU または JCommonsenseQA 300問、JSON スキーマ 100件
- [ ] thinking は `low`、greedy に固定する
- [ ] 正答率に Wilson の95%信頼区間を付ける
- [ ] 正答1件あたりの所要時間を出す
- [ ] エージェント評価では外向き通信を既定で遮断する
"""),
    ("記事の下書き：AIと実装02", ["type:writing"], """\
`docs/plan.md` の構成案に沿って書く。

- [ ] TL;DR とスコアカード
- [ ] 設計の違い（重みの配置図）
- [ ] トラックA・B・C の結果とグラフ3枚
- [ ] どちらを使うべきか、この検証の限界
- [ ] 公開に合わせてリポジトリを public にする
"""),
]


def gh(*args, payload=None):
    cmd = ["gh", "api", *args]
    if payload is not None:
        cmd += ["--input", "-"]
    r = subprocess.run(cmd, input=json.dumps(payload) if payload is not None else None,
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"{' '.join(args)}: {r.stderr.strip() or r.stdout.strip()}")
    return json.loads(r.stdout) if r.stdout.strip() else None


def main():
    existing = {l["name"] for l in gh(f"repos/{REPO}/labels?per_page=100")}
    for name, color, desc in LABELS:
        if name in existing:
            print(f"label  exists : {name}")
            continue
        gh(f"repos/{REPO}/labels", payload={"name": name, "color": color, "description": desc})
        print(f"label  created: {name}")

    ms = [m for m in gh(f"repos/{REPO}/milestones?state=all&per_page=100") if m["title"] == MILESTONE]
    if ms:
        ms_no = ms[0]["number"]
        print(f"milestone exists : #{ms_no}")
    else:
        ms_no = gh(f"repos/{REPO}/milestones", payload={
            "title": MILESTONE,
            "description": "FreeToken と Strata で Qwen3.8-Flash-Next を比較する記事（AIと実装02）"})["number"]
        print(f"milestone created: #{ms_no}")

    titles = {i["title"] for i in gh(f"repos/{REPO}/issues?state=all&per_page=100")}
    for title, labels, body in ISSUES:
        if title in titles:
            print(f"issue  exists : {title}")
            continue
        n = gh(f"repos/{REPO}/issues", payload={
            "title": title, "body": body, "labels": labels, "milestone": ms_no})["number"]
        print(f"issue  created: #{n} {title}")


if __name__ == "__main__":
    main()

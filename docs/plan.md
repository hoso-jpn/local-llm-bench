# 評価計画：FreeToken vs Strata（Qwen3.8-Flash-Next / Seedcore-01）

下書きと議論は Claude のドキュメントで行い、確定した内容をここに反映する。

## 1. 答える問い

1. 同じGGUFでエンジンだけを替えると、prefillとdecodeはどれだけ変わるか（エンジン差）
2. 各エンジンの推奨構成では、実際に使ったときの速度はどう違うか（出荷状態の差）
3. その速度差と引き換えに、出力の一致度とタスクの精度はどれだけ変わるか
4. VRAM・RAM・SSD・PCIeの使い方はどう違うか（前回のボトルネック分析の続き）

## 2. 比較トラック

| トラック | モデルファイル | MTP | 固定条件 |
| --- | --- | --- | --- |
| A | 両者ともGSQ-RCO GGUF（IQ3_XXS、可能ならIQ3_Sも） | 両者OFF（Strataは `--spec 2 --mtp-max-t 1` でドラフト0にする） | greedy、thinking none、`STRATA_ROUTE_TAIL_SKIP=0`、nonceでprefix cacheを無効化、context長を揃える |
| B | FreeToken：NVFP4 ／ Strata：IQ3_S（またはUD-IQ4_XS） | 各エンジンの既定 | 温度とthinkingは揃える |
| C | Bと同じ | Bと同じ | prefix cacheを有効にしたまま、同じ会話を2〜5ターン続ける |

比較を歪めやすいのは、近似計算（Strataのtail skip）、会話キャッシュ（Strataにはない）、サンプリング（Strataはgreedyのみ）の3点。

## 3. 速度の指標

| 指標 | 定義 |
| --- | --- |
| TTFT | リクエスト送信から最初の出力トークン（reasoningを含む）を受け取るまで（s） |
| Decode | (completion_tokens − 1) ÷ (最後のチャンク到着 − 最初のチャンク到着)（tok/s） |
| Prefill | prompt_tokens ÷ TTFT |
| E2E | completion_tokens ÷ 総時間 |
| チャンク間隔 p50 / p95 / p99 | ストリームのチャンクの到着間隔（ms）。MTPが効くとトークンは数個ずつ届くので、トークン間ではなくチャンク間で測る |
| 停滞率 | 到着間隔が200 msを超えたチャンクの割合 |
| MTP受理率、expert cache hit率 | エンジンのログから取る |
| コールドロード時間 | ページキャッシュを捨てた状態から `/health` が応答するまで |
| 2ターン目のTTFT | トラックC |

計測グリッド：入力長 1K / 4K / 16K / 32K / 64K / 128K、出力長 256 / 1,024、プロンプトはコード要約と日本語の自由記述の2種類、並列数は1（余力があれば2も）。

## 4. 品質の指標

| 層 | 指標 | 規模 |
| --- | --- | --- |
| 一致度 | greedy出力の完全一致率、最初に分岐したトークン位置の中央値、top-1一致率、KL（logprobsが取れれば） | 100プロンプト × 256トークン |
| タスク精度 | GSM8K | 300問 |
| タスク精度 | HumanEval pass@1 | 164問 |
| タスク精度 | JMMLU または JCommonsenseQA | 300問 |
| タスク精度 | JSONスキーマ適合率 | 100件 |
| タスク精度 | needle検索（32K・128K） | 各20件 |
| エージェント | tool callの成功率 | 50件 |
| エージェント | 実リポジトリでのタスク完了率と所要時間 | 10〜20タスク |

総合指標：**正答1件あたりの所要時間 = 総時間の合計 ÷ 正答数**。正答率にはWilsonの95%信頼区間を付ける。thinkingは品質評価では `low`、速度計測では `none` に固定する。

## 5. リソースの指標

プロセスのRSSとpinned量、最小MemAvailable、swapのin/out、VRAM、PCIe H2D（prefill中とdecode中に分ける）、SSDの読み出し、CPU使用率、GPU電力と電力効率（tok/J）、ディスク占有量、他のアプリとの同居、導入と運用の手間。

## 6. 計測プロトコル

- 1セル（構成 × 入力長 × 出力長 × プロンプト種類）につき、捨てリクエスト1回＋本計測5回。中央値とmin–maxで報告する
- サーバは常に1つだけ起動する
- 版を記録する：エンジンのタグとcommit、ドライバ、CUDA、カーネル、モデルファイルのsha256
- 毎回記録する：PCIeの世代と幅（負荷中に取る）、RAMの実動作速度、`ft bench bw`
- コールドロードを測る前に `sync; echo 3 | sudo tee /proc/sys/vm/drop_caches`
- **事前登録**：計測の前に各セルの予想値を `results/<run>/prereg.md` に書いてコミットする

実施順：トラックA（一致度も） → トラックB → 品質評価 → トラックC → 余力があればFreeTokenのoffloadとhybrid、`--ple-backend` のRAMとdiskの比較。

## 7. 事前チェック

- [ ] FreeToken v0.2.0でGSQ-RCO GGUFが読めるか（`scripts/gguf_check/`）
- [ ] FreeTokenでQwen3.8-Flash-NextのMTPが使えるか
- [ ] Strataでドラフト0にするフラグが効くか（ログでdrafts=0を確認）
- [ ] Strataでlogprobsが取れるか
- [ ] StrataのLinuxビルド（CUDA 13）と、RTX 50シリーズ × CUDA 13.2の既知の不具合を避ける組み合わせ
- [ ] 両エンジンのcache hit率の定義が同じか
- [ ] Seedcore-01の現在のPCIe幅とRAM速度
- [ ] モデルと量子化版のライセンス
- [ ] エージェント評価では外向き通信を既定で遮断する

## 参考資料

- [前回記事](https://blog.florigen.ai/posts/rtx-5090-qwen38-flash-next-freetoken)
- [FreeToken releases](https://github.com/flashml-org/freetoken/releases)
- [Strata](https://github.com/Niko1221/Strata) / [DETAILS.md](https://github.com/Niko1221/Strata/blob/main/docs/DETAILS.md)
- [InsiderLLM：Strata vs llama.cpp（RTX 3060）](https://insiderllm.com/pdfs/strata-vs-llama-cpp-rtx-3060.pdf)
- [SmartScope：Strataの要件とtail skip](https://smartscope.blog/en/blog/strata-local-llm-engine-qwen3-8-flash-next-2026/)
- [AkitaOnRails：RTX 5090でのStrata](https://akitaonrails.com/en/2026/10/22/best-open-source-llm-strata-with-qwen-3-8-flash-next/)

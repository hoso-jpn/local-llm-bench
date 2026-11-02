# 事前登録：FreeToken offload と hybrid（Issue #9）

**計測を始める前にこのファイルをコミットする。** 予想は、トラックB（`results/2026-11-01_trackB/`）、前回記事（0.1.2 の `ft bench bw`）、v0.2.0 のヘルプ（`results/2026-10-31_env/freetoken_v020_cli.txt`）から立てた。v0.2.0 の `ft bench bw` の結果は取得後に「条件」へ追記する（予想は書き換えない）。

## 目的

AIと実装01 の4章「次はoffloadとhybridを同一条件で比較する」を実機で確かめる。帯域テストの推奨（offload）は、実際の生成速度・TTFT と一致するか。

## 条件

| 項目 | 内容 |
| --- | --- |
| エンジン | FreeToken v0.2.0（イメージ `seedcore-freetoken:127aa0a920ce-cu130-v1`） |
| モデル | RadixArk Qwen3.8-Flash-Next-NVFP4（トラックB と同じファイル） |
| B（offload） | `configs/freetoken/run.sh nvfp4`（トラックB と同じ） |
| H（hybrid、auto） | 上と同じ＋`FT_STRATEGY=hybrid FT_HYBRID_FETCH=-1`（`--moe-strategy hybrid --moe-hybrid-max-fetch -1`） |
| H0（余力があれば） | 上と同じで `FT_HYBRID_FETCH=0`（PCIe からは運ばず、キャッシュにない expert をすべて CPU で計算） |
| 共通 | チャンク 8,192、`--text-model-only`、PLE は disk、`--cache-type radix`、`--moe-cache-auto`、コンテキスト 32,768、`--moe-cpu-threads 16` |
| リクエスト | トラックB と同じ（温度 0、thinking `none`、先頭に乱数、ストリーミング） |
| グリッド | コード・日本語 × 入力 1K / 4K / 16K / 30K × 出力 256 / 1,024。捨て1回＋本計測5回。中央値と min–max |
| 順番 | ABBA（B s1 → H s1 → H s2 → B s2）。サーバは常に1つだけ起動する。`scripts/run_ft_hybrid.sh` |
| 品質（余力があれば） | H で GSM8K・HumanEval・JCQA・JSON（2026-11-01_quality と同じ課題・設定）。freetoken_B（offload）と答えの一致を比べる |

### v0.2.0 の `ft bench bw`（取得後に追記）

（`results/2026-11-03_env/ft_bench_bw_nvfp4_v020.txt`）

## 基準（トラックB の offload、v0.2.0）

| 種類 | TTFT 1K / 30K | decode | 平均 PCIe 受信（出力 1,024） |
| --- | --- | --- | --- |
| コード | 2.5〜2.6 s / 10.3〜10.9 s | 59〜61 tok/s | 14〜18 GB/s |
| 日本語 | 2.6〜2.7 s / 16.0〜16.6 s | 66〜69 tok/s | 12〜15 GB/s |

RAM の空き（最小）は 50.6〜51.8 GiB。VRAM の expert キャッシュは 5,926 スロット（全 24,576 の約 24%）。

## 予想

| 項目 | B（offload） | H（hybrid、auto） | H0（すべて CPU） |
| --- | --- | --- | --- |
| decode（コード） | 58〜62 tok/s | 60〜85 tok/s | 45〜85 tok/s |
| decode（日本語） | 65〜70 tok/s | 66〜90 tok/s | 50〜90 tok/s |
| TTFT | トラックB と同じ（±10%） | B と同じ（±10%） | B と同じ（±10%） |
| decode 中の PCIe 受信 | トラックB と同じ | B より 20〜50% 少ない | B より大きく少ない |
| CPU 使用率（decode 中） | 低い | B より高い | もっとも高い |
| RAM の空き（最小） | 約 51 GiB | B と同じ（±3 GiB） | B と同じ（±3 GiB） |

予想の根拠と、確かめたい仮説：

1. **v0.2.0 の `ft bench bw` も offload を推奨する**（比率 1.5〜1.9 倍）。ハードは前回記事と同じ（PCIe 5.0 x8、DDR5-3600・2チャネル）。0.1.2 では CPU-MoE 45.5 GB/s、PCIe gather 26.7 GB/s、比率 1.70 倍で、hybrid の基準（2.0 倍超）に届かなかった
2. **それでも hybrid の decode は offload と同じか、やや速い（1.0〜1.4 倍）**。トラックB の decode 中の PCIe 受信は平均 12〜18 GB/s で、x8 の上限（約 29 GB/s）に張り付いてはいない。1ステップの中で運ぶ待ち時間の一部を CPU の計算に回して重ねられれば、ステップが短くなる余地がある。一方、CPU 側の計算（16 スレッド、DDR5-3600）と同期の手間で相殺される可能性もある
3. **TTFT は変わらない**。ヘルプによると hybrid の振り分けは decode のステップ単位で、prefill は offload と同じ経路を通る
4. **H0（すべて CPU）は、どちらに転ぶか読めない**。CPU-MoE の帯域（45.5 GB/s）は PCIe（26.7 GB/s）より大きいが、CPU の計算は GPU より遅い。参考：Strata は VRAM にない expert を CPU で計算して 133〜137 tok/s（トラックA、IQ3_XXS、MTP なし）を出したが、expert のサイズも実装も違う
5. **hybrid でも答えはほぼ変わらない**。CPU で計算する expert の数値がわずかに変わり、長い推論の途中で文章が分かれることがある。答えの一致は 97〜100%、正答率の差は信頼区間の中

## 結果が予想から外れたら

外れた理由の仮説をここに追記する（計測後に）。

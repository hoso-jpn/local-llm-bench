# Strata の設定

イメージは `strata-comparison:v0.1.42`（v0.1.42、commit 61b3fb5、`CUDA_ARCHITECTURES=120` で Docker ビルド）。
モデル・パック・MTP 層・設定はホストの `/data/strata` にあり、コンテナからは `/data` に見える。

| ファイル | 用途 | 中身 |
| --- | --- | --- |
| `strata-iq3_xxs-shipped.json` | トラックB（出荷状態）の基準 | セットアップが生成したもの（2026-10-31）そのまま。`--spec 4 --spec-min-p 0.5` |
| `strata-iq3_xxs-trackA.json` | トラックA | MTP の下書きを0にする：`--spec 2 --mtp-max-t 1`（`--spec 0` は起動時に拒否される）。ほかは shipped と同じ |
| `run.sh` | 起動 | 設定を `/data/strata/config/` に置き、`CONFIG` 環境変数で指定して起動する。FreeToken が動いていれば止まる |
| `stop.sh` | 停止 | エンジンのログ・コンテナのログ・`STRATA_*` 環境変数を `results/<run>/` に保存してから止める |

## 取得済みのファイル（ホスト側）

| パス | 中身 |
| --- | --- |
| `/data/strata/models/IQ3_XXS/...-00001-of-00002.gguf`（47.0GB） | 本体（`--native`） |
| `/data/strata/models/IQ3_XXS/...-00002-of-00002.gguf`（28.8GB） | PLE（n-gram 表）。Strata は RAM に常駐させず SSD から読む（`--ple-gguf`） |
| `/data/strata/packs/iq3_xxs/` | expert のパックと tokenizer |
| `/data/strata/mtp/rt` | MTP 層（Q2_0、約0.9GB） |

## トラックAの確認事項

- [ ] 計測中のレスポンスの `timings.draft_n` が 0 であること（`llm_engine_bench.py` が `draft_n` として記録する）
- [ ] `results/<run>/strata_env.txt` に `STRATA_ROUTE_TAIL_SKIP=0` があること
- [ ] speed projection が off であること（セットアップのログで確認済み。設定に projection 関連の引数がないこと）

## 初回起動で分かったこと（2026-10-31、IQ3_XXS、shipped 設定）

- RAM に expert 39.97 GiB を 2.27 GiB/s で読み込み
- VRAM の expert キャッシュ：14,795 個（24.04 GiB）＝全 24,576 個の約60%

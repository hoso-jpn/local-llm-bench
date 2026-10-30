# local-llm-bench

自宅ワークステーション **Seedcore-01** で、ローカルLLMの推論エンジンを同じ条件で比較・記録するリポジトリ。

現在のテーマは、**FreeToken と Strata で Qwen3.8-Flash-Next を動かし、推論速度と品質を比較すること**。

- 前回記事：[AIと実装01；RTX 5090一枚で125B級MoEを約65 tok/sで動かしてみた](https://blog.florigen.ai/posts/rtx-5090-qwen38-flash-next-freetoken)
- 評価計画：[docs/plan.md](docs/plan.md)
- 検証環境と変更履歴：[docs/env/seedcore-01.md](docs/env/seedcore-01.md)

## 比較の考え方

速度の差がエンジン・量子化・MTP（投機的デコード）のどれから来ているかを分けるため、計測を3つのトラックに分ける。

| トラック | 内容 |
| --- | --- |
| A：エンジン単体 | 両エンジンに同じGGUF（ISTA-DASLab GSQ-RCO）を読ませ、MTPなし・tail skipなし・prefix cacheなしで比べる |
| B：出荷状態 | 各エンジンの推奨構成で比べる（FreeTokenはNVFP4、StrataはIQ3_S＋MTP） |
| C：エージェント実戦 | prefix cacheを有効にしたまま多ターンで使い、2ターン目のTTFTなどを比べる |

## ディレクトリ

```
docs/       評価計画、検証環境
bench/      計測スクリプト（llm_engine_bench.py）とプロンプト素材の説明
configs/    各エンジンの起動コマンド・設定ファイル
results/    計測結果。1回の計測につき1ディレクトリ（YYYY-MM-DD_<track>_<engine>）
analysis/   集計とグラフ
scripts/    補助スクリプト（環境記録、GitHub初期設定）
```

## 計測の手順（概要）

```bash
# 1. 環境を記録する
bash scripts/env_check.sh results/2026-11-01_trackA_freetoken/env_check.txt

# 2. 計測前に予想を prereg.md に書き、コミットする（事前登録）

# 3. サーバを1つだけ起動して計測する
python3 bench/llm_engine_bench.py --base-url http://127.0.0.1:8080/v1 \
  --engine freetoken --track A --model-file GSQ-RCO-IQ3_XXS \
  --source bench/prompts/code.txt --prompt-kind code \
  --tokenizer Qwen/Qwen3.8-Flash-Next \
  --out results/2026-11-01_trackA_freetoken/results.jsonl

# 4. 集計する
python3 bench/llm_engine_bench.py --summarize results/2026-11-01_trackA_freetoken/results.jsonl
```

`llm_engine_bench.py` は標準ライブラリだけで動く。正確なトークン長には `transformers`、GPUの計測には `pynvml` を入れる（どちらも任意）。

## 入れないもの

- モデルの重み、n-gram表、MTP層
- 巨大なエンジンログ（必要な部分だけ切り出すか、圧縮して入れる）

## ライセンス

コードは MIT。モデルの重みには各提供元のライセンス（Qwen Community License 1.0 など）が適用される。

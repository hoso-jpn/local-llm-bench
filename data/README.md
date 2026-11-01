# 評価データ

`data/quality/` は `python bench/quality_eval.py prepare` で作る。出典とライセンス：

| ファイル | 出典 | ライセンス | 使う範囲 |
| --- | --- | --- | --- |
| `gsm8k.jsonl` | [openai/gsm8k](https://huggingface.co/datasets/openai/gsm8k)（main / test） | MIT | 先頭 300 問 |
| `humaneval.jsonl` | [openai/openai_humaneval](https://huggingface.co/datasets/openai/openai_humaneval)（test） | MIT | 全 164 問 |
| `jcqa.jsonl` | [leemeng/jcommonsenseqa-v1.1](https://huggingface.co/datasets/leemeng/jcommonsenseqa-v1.1)（validation、JGLUE の JCommonsenseQA v1.1） | CC BY 4.0 | 先頭 300 問 |
| `json.jsonl` | 合成（`make_json_tasks`、seed 20261101）。人名・メールアドレスは架空 | MIT（このリポジトリ） | 50 問 |
| `aime.jsonl` | [MathArena/aime_2025](https://huggingface.co/datasets/MathArena/aime_2025)・[MathArena/aime_2026](https://huggingface.co/datasets/MathArena/aime_2026)（問題は MAA の AIME 2025・2026） | CC BY-NC-SA 4.0 | 全 60 問（各年 30 問） |
| `math5.jsonl` | [HuggingFaceH4/MATH-500](https://huggingface.co/datasets/HuggingFaceH4/MATH-500)（test.jsonl、元は Hendrycks らの MATH） | MIT | level 5 の 134 問 |
| `lc.jsonl` | 合成（`prepare-lc`、seed 20261102）。干し草は `bench/prompts/code.txt`・`ja.txt` の一部で、ファイルには文字位置と埋め込む文だけを保存する | MIT（このリポジトリ）。干し草の元資料は `bench/prompts/README.md` を参照 | 3 種 × 4 長さ × 10 問 = 120 問 |

`aime.jsonl` は CC BY-NC-SA 4.0 のため、このファイルを再配布するときは同じライセンスを引き継ぎ、営利目的に使わない。記事では問題文を転載せず、正答数だけを載せる。

`SOURCES.json` には `prepare` が実際に読んだファイルを記録する。aime の取得はこの記録を入れる前の版で行ったため、上の表を正とする。

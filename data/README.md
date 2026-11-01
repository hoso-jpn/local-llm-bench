# 評価データ

`data/quality/` は `python bench/quality_eval.py prepare` で作る。出典とライセンス：

| ファイル | 出典 | ライセンス | 使う範囲 |
| --- | --- | --- | --- |
| `gsm8k.jsonl` | [openai/gsm8k](https://huggingface.co/datasets/openai/gsm8k)（main / test） | MIT | 先頭 300 問 |
| `humaneval.jsonl` | [openai/openai_humaneval](https://huggingface.co/datasets/openai/openai_humaneval)（test） | MIT | 全 164 問 |
| `jcqa.jsonl` | [leemeng/jcommonsenseqa-v1.1](https://huggingface.co/datasets/leemeng/jcommonsenseqa-v1.1)（validation、JGLUE の JCommonsenseQA v1.1） | CC BY 4.0 | 先頭 300 問 |
| `json.jsonl` | 合成（`make_json_tasks`、seed 20261101）。人名・メールアドレスは架空 | MIT（このリポジトリ） | 50 問 |

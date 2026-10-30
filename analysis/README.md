# 集計とグラフ

まずはスクリプトの集計機能を使う：

```bash
python3 bench/llm_engine_bench.py --summarize results/<run>/results.jsonl
```

記事用のグラフは3枚を予定している。

1. 入力長 × Decode速度の折れ線（構成ごと）
2. 4構成のTTFTの棒（32K）
3. 正答率 × 正答あたり時間の散布図

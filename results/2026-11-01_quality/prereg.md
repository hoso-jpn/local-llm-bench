# 事前登録：品質評価

**計測を始める前にこのファイルをコミットする。** 予想は、モデルの公開情報と量子化についての一般的な傾向から立てた（このモデルでの実測はまだない）。

## 目的

トラックB で Strata が速かった理由の一部は、小さい量子化（IQ3_S）にある。その分だけ賢さを失っていないかを確かめる。あわせて、同じ重みならエンジンが違っても答えが同じかも確かめる。

## 構成

| ラベル | エンジン | モデル | 近似・MTP |
| --- | --- | --- | --- |
| freetoken-A | FreeToken v0.2.0 | GSQ-RCO IQ3_XXS（GGUF） | なし |
| strata-A | Strata v0.1.42 | 同じ GGUF | 下書き 0、tail skip 0、prefill の CPU 分担 0 |
| strata-B | Strata v0.1.42 | GSQ-RCO IQ3_S | 出荷状態（MTP、tail skip 7、prefill の CPU 分担） |
| freetoken-B | FreeToken v0.2.0 | RadixArk NVFP4 | なし |

起動設定はトラックA・B と同じ（`scripts/run_track.sh`）。実行順：strata-B → strata-A → freetoken-A → freetoken-B（各1セッション）。

## 課題

| 課題 | 中身 | 問題数 | 採点 |
| --- | --- | --- | --- |
| GSM8K | 算数の文章題（英語） | 300（test の先頭） | 最後の「Answer: 数値」（なければ最後の数値）が正解と一致 |
| HumanEval | Python の関数を書く | 164（全問） | テストが通る。ネットワークなし・読み取り専用・権限なしのコンテナで、1問10秒まで |
| JCommonsenseQA v1.1 | 日本語の常識問題（5択） | 300（validation の先頭） | 最初に出た 0〜4 の数字が正解と一致 |
| JSON 抽出 | 日本語の注文文から決まった形の JSON を作る | 50（合成） | 6つのキーがすべて正しく、余計なキーがない |

リクエスト：温度 0、thinking `low`、最大出力 4,096 トークン、ストリーミングなし。問題文は `bench/quality_eval.py` の `build_prompt`。

## 予想

| 課題 | freetoken-A / strata-A（IQ3_XXS） | strata-B（IQ3_S） | freetoken-B（NVFP4） |
| --- | --- | --- | --- |
| GSM8K | 90〜95% | 92〜96% | 93〜97% |
| HumanEval | 83〜93% | 85〜94% | 87〜95% |
| JCommonsenseQA | 84〜92% | 85〜93% | 86〜94% |
| JSON 抽出 | 90〜100% | 92〜100% | 92〜100% |

1. **量子化が大きいほど、わずかに正答率が高い（NVFP4 ≥ IQ3_S ≥ IQ3_XXS）。ただし差の多くは信頼区間（300問で ±3〜5 ポイント）の中に収まる**
2. **同じ重み（freetoken-A と strata-A）では、正答率の差は信頼区間の中。** ただし、計算の細かな違い（カーネル、KV キャッシュの精度：FreeToken bf16、Strata int8）で、長い推論の途中から文章が分かれるため、答えの一致は 90〜97% にとどまる
3. **Strata の出荷状態の近似（tail skip など）は、正答率に測れるほどの差を生まない**（strata-A と strata-B の差は、量子化の違いの範囲に収まる）
4. **正答1件あたりの時間は strata-B が最も短く、freetoken-B が最も長い**（トラックB の decode の差がそのまま出る）
5. **JSON 抽出は、どの構成でも形式の崩れ（パースできない出力）がほぼない**

## 結果

（計測後に追記）

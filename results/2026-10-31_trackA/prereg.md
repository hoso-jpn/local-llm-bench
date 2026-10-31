# 事前登録：トラックA（同一 GGUF・MTP なし）

**計測を始める前にこのファイルをコミットする。** 予想は試運転（`results/2026-10-31_smoke/`、4K 入力・256 出力）から外挿したもの。

## 条件

| 項目 | FreeToken | Strata |
| --- | --- | --- |
| エンジン | v0.2.0（commit 127aa0a、イメージ `seedcore-freetoken:127aa0a920ce-cu130-v1`） | v0.1.42（commit 61b3fb5、イメージ `strata-comparison:v0.1.42`） |
| モデルファイル | ISTA-DASLab GSQ-RCO IQ3_XXS（同一ファイル。sha256 1つ目 `219ea929…6d15`、2つ目 `316b46f3…e113`） | 同左 |
| 起動設定 | `configs/freetoken/run.sh gguf-iq3_xxs`（offload、`--max-prefill-length 2048`、`--cache-type naive`、PLE は disk） | `configs/strata/strata-iq3_xxs-trackA.json`（`--spec 2 --mtp-max-t 1`、`STRATA_ROUTE_TAIL_SKIP=0`、`STRATA_PREFILL_CPU_SHARE=0`） |
| MTP | なし（機能がない） | 下書き 0（`draft_n` で確認） |
| コンテキスト | 32,768 | 32,768 |
| KV キャッシュ | bf16 | int8 |
| ハード | RTX 5090（PCIe 5.0 x8）、Ryzen 9 9950X3D2、DDR5 128GB（4 DIMM、3600 MT/s） | 同左 |

リクエスト：温度 0、thinking `none`、先頭に乱数（prefix cache を避ける）、ストリーミング。

## 計測の順番

ABBA：FreeToken s1 → Strata s1 → Strata s2 → FreeToken s2。各セッションで、コード・日本語 × 入力 1K / 4K / 16K / 30K × 出力 256 / 1,024 を、捨て1回＋本計測5回。

## 予想

| 入力長 | FreeToken TTFT | Strata TTFT | FreeToken decode | Strata decode |
| --- | --- | --- | --- | --- |
| 1K | 1.5〜3 s | 0.3〜0.6 s | 135〜150 tok/s | 115〜135 tok/s |
| 4K | 4〜5 s | 0.8〜1.1 s | 135〜150 tok/s | 115〜135 tok/s |
| 16K | 11〜15 s | 3〜4.5 s | 125〜145 tok/s | 105〜130 tok/s |
| 30K | 20〜27 s | 6〜9 s | 115〜140 tok/s | 95〜125 tok/s |

予想の根拠と、確かめたい仮説：

1. **prefill は Strata が 4〜6 倍速い**（試運転 4K で約5倍）。Strata は 8,192 トークンのチャンクで expert を流し、FreeToken は 2,048 トークンのチャンクで、チャンクごとに expert を PCIe で運ぶため
2. **decode は FreeToken が 10〜20% 速い**（試運転 4K で約15%）。両者とも expert キャッシュの hit 率は高い（Strata 97.7%）ので、差はキャッシュ外の expert の扱い（FreeToken は PCIe で運んで GPU で計算、Strata は CPU で計算しつつ一部を PCIe）と、カーネルの違いから来ると予想する
3. **入力が長いほど decode は下がる**（attention の分）。下がり方は両エンジンで大きく変わらない
4. **日本語とコードで、decode の差は 5% 以内**（MTP がないので、出力の予測しやすさは効かない。expert の使われ方の違いだけが効く）
5. **セッション間の差は 3〜7%**（試運転の Strata で約6%）

## 揃えていない条件（記事に明記する）

- prefill のチャンク：FreeToken 2,048（前回記事の設定）、Strata 自動（8,192）。感度を見るため、後で FreeToken の 8,192 を1セット取る
- KV キャッシュの精度：FreeToken bf16、Strata int8

## 結果が予想から外れたら

計測後に、外れた理由の仮説をここに追記する。

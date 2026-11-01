# 事前登録：トラックB（出荷状態）

**計測を始める前にこのファイルをコミットする。** 予想は、トラックA（`results/2026-10-31_trackA/`）、チャンク 8,192 の感度確認（`results/2026-11-01_trackA_ft_prefill8192/`）、前回記事、各エンジンの公開資料から立てた。Strata IQ3_S の起動設定は取得後に「条件」へ追記する（予想は書き換えない）。

## 目的

各エンジンを「実際に使う推奨構成」で動かしたときの速さを比べる。トラックA との差が、量子化（GGUF IQ3_XXS → 各エンジンの推奨）と、MTP・近似計算の効果になる。

## 条件

| 項目 | FreeToken | Strata |
| --- | --- | --- |
| エンジン | v0.2.0（イメージ `seedcore-freetoken:127aa0a920ce-cu130-v1`） | v0.1.42（イメージ `strata-comparison:v0.1.42`） |
| モデル | RadixArk Qwen3.8-Flash-Next-NVFP4（前回記事と同じファイル。expert は NVFP4 W4A4、PLE は FP8） | ISTA-DASLab GSQ-RCO IQ3_S（128GB 向けの推奨） |
| 起動設定 | `configs/freetoken/run.sh nvfp4`（offload、チャンク 8,192、`--text-model-only`、PLE は disk、`--cache-type radix`） | `configs/strata/strata-iq3_s-shipped.json`（セットアップが生成したもの。取得後に追記） |
| MTP | なし（機能がない） | あり（`--spec 4`。受理率を `draft_n` / `draft_n_accepted` で記録） |
| 近似計算 | なし | 既定どおり（tail skip 7、prefill の CPU 分担 ON） |
| コンテキスト | 32,768 | 32,768 |

リクエストはトラックA と同じ（温度 0、thinking `none`、先頭に乱数、ストリーミング）。計測の順番も同じ ABBA（FreeToken s1 → Strata s1 → Strata s2 → FreeToken s2）、グリッドも同じ（コード・日本語 × 入力 1K / 4K / 16K / 30K × 出力 256 / 1,024、捨て1回＋本計測5回）。

## 予想

| 入力長 | FreeToken TTFT | Strata TTFT | FreeToken decode | Strata decode（コード / 日本語） |
| --- | --- | --- | --- | --- |
| 1K | 0.8〜1.8 s | 0.8〜1.2 s | 70〜110 tok/s | 150〜200 / 125〜170 tok/s |
| 4K | 1.5〜3 s | 0.9〜1.5 s | 70〜110 tok/s | 150〜200 / 125〜170 tok/s |
| 16K | 4〜8 s | 3〜4.5 s | 70〜110 tok/s | 150〜200 / 125〜170 tok/s |
| 30K | 6〜12 s | 5〜7 s | 70〜110 tok/s | 150〜200 / 125〜170 tok/s |

予想の根拠と、確かめたい仮説：

1. **FreeToken の decode は、トラックA（GGUF、142 tok/s）より大きく下がる（70〜110 tok/s）**。NVFP4 の expert は1個約 2.6 MiB で、IQ3_XXS（約 1.7 MiB）の約1.6倍。VRAM に置ける expert が減り（0.1.2 の前回は 6,119 スロット、GGUF では 13,235）、キャッシュにない expert を PCIe で運ぶ量が増える。前回記事の 0.1.2 は 65 tok/s だった
2. **FreeToken の prefill は、W4A4 のカーネルで GGUF より速い区間がある**が、運ぶバイト数が多い分と相殺され、TTFT はトラックA の 8,192（30K で 6.5 s）と同程度か、やや遅い
3. **Strata は MTP で decode が 1.2〜1.6 倍になる**。IQ3_S は IQ3_XXS より CPU の仕事が多く、MTP なしなら 10〜15% 遅い（公式資料の RTX 5070 で IQ3_XXS 61.6 → IQ3_S 53.3 tok/s）。そこに MTP が掛かる
4. **MTP の効きは、コードの方が日本語より大きい**（受理率：コード 65〜80%、日本語 50〜70%）。コードの要約は入力を引用しやすく、下書きが当たりやすい
5. **出荷状態では、decode も Strata が速くなる**（トラックA では FreeToken が約6%速かった）。MTP の有無と量子化の重さの差が効く
6. **RAM の使用は FreeToken 約 70 GiB、Strata 約 55 GiB**。どちらも PLE を SSD から読む。前回記事の 0.1.2 は PLE を RAM にピン留めして約 115 GiB 使っていた

### Strata IQ3_S の起動設定（2026-11-01、取得後に追記。予想は変えていない）

- `configs/strata/strata-iq3_s-shipped.json`：セットアップが生成したもの（`results/2026-11-01_env/strata_iq3s_check.txt`）と同一。`--expert-cache auto --prefill auto --spec 4 --spec-min-p 0.5 --mtp /data/mtp/rt --max-context 32768 --kv int8`
- 初回起動：RAM に expert 46.84 GiB、VRAM の expert キャッシュ 12,488 個（23.70 GiB）。IQ3_XXS（14,795 個）より約16%少ない
- speed projection：off
- 2つ目のシャード（PLE 表）は IQ3_XXS と同一（sha256 `316b46f3…c161e113`）。Strata はダウンロードせずハードリンクした

## 揃えていない条件（記事に明記する）

- 量子化：FreeToken NVFP4（expert 4bit、他は BF16）、Strata IQ3_S（混合の i-quant、平均 3〜3.5 bit 程度）。速さの差には量子化の差が含まれる
- MTP：Strata だけ
- KV キャッシュ：FreeToken bf16、Strata int8

## 結果

（計測後に追記）

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

## 結果（2026-11-01 計測）

ABBA の4セッション、384 リクエスト、エラー 0。値は2セッションの全リクエストの中央値。生データは各セッションの `results.jsonl`、まとめて `all.jsonl`。

### TTFT と decode

| 種類 | 入力長 | TTFT FreeToken | TTFT Strata | decode FreeToken（256 / 1024） | decode Strata（256 / 1024） | MTP 受理率（256 / 1024） |
| --- | --- | --- | --- | --- | --- | --- |
| コード | 1K | 2.54 s | 1.06 s | 62.8 / 59.2 tok/s | 208 / 222 tok/s | 72% / 76% |
| コード | 4K | 2.85 s | 1.17 s | 60.7 / 59.5 tok/s | 212 / 221 tok/s | 68% / 74% |
| コード | 16K | 8.10 s | 2.89 s | 61.6 / 60.6 tok/s | 219 / 224 tok/s | 73% / 77% |
| コード | 30K | 10.63 s | 4.95 s | 61.4 / 60.7 tok/s | 212 / 218 tok/s | 70% / 75% |
| 日本語 | 1K | 2.62 s | 1.06 s | 66.4 / 66.9 tok/s | 181 / 179 tok/s | 54% / 57% |
| 日本語 | 4K | 3.18 s | 1.17 s | 66.3 / 67.3 tok/s | 185 / 177 tok/s | 57% / 58% |
| 日本語 | 16K | 10.37 s | 2.76 s | 66.3 / 68.5 tok/s | 182 / 178 tok/s | 59% / 62% |
| 日本語 | 30K | 16.29 s | 4.91 s | 67.1 / 68.5 tok/s | 177 / 171 tok/s | 58% / 58% |

- decode は Strata がコードで約 3.6 倍、日本語で約 2.7 倍速い。TTFT も Strata が 2.1〜3.8 倍速い
- FreeToken の expert キャッシュは 5,926 スロット（トラックA の GGUF では 13,235）。Strata の IQ3_S は 12,488 個

### トラックA からの変化（decode、1,024 出力）

| エンジン | 種類 | トラックA（同一 GGUF、MTP なし） | トラックB（出荷状態） | 倍率 |
| --- | --- | --- | --- | --- |
| FreeToken | コード | 135〜141 tok/s | 59〜61 tok/s | 約 0.43 倍 |
| FreeToken | 日本語 | 142〜143 tok/s | 67〜69 tok/s | 約 0.48 倍 |
| Strata | コード | 135〜136 tok/s | 218〜222 tok/s | 約 1.6 倍 |
| Strata | 日本語 | 133〜137 tok/s | 171〜179 tok/s | 約 1.3 倍 |

FreeToken は量子化を GGUF IQ3_XXS から NVFP4 にしたことで半分以下になり、Strata は IQ3_S＋MTP で 1.3〜1.6 倍になった。**出荷状態での大きな差は、エンジンそのものより、量子化の大きさと MTP の有無から来ている。**

### 資源

| 項目 | FreeToken | Strata |
| --- | --- | --- |
| RAM の空き（最小） | 50.5 GiB | 69.1 GiB |
| VRAM の使用（最大） | 30.1 GiB | 31.6 GiB |
| GPU の電力（中央値） | 221 W | 350 W |
| decode 中の PCIe（30K、256 出力、コード） | 23.3 GB/s | 22.8 GB/s |

### セッション間の再現性

FreeToken：TTFT は最大 12.2%（日本語・4K）、decode は数%以内。Strata：decode は最大 6.3%（日本語・30K、MTP の当たり外れの差）。トラックA よりばらつきが大きい。FreeToken は日本語の長い入力の TTFT が不安定（キャッシュにない expert の呼ばれ方で、運ぶ量が変わるため）。

### 予想との照合

| 予想 | 結果 | 判定 |
| --- | --- | --- |
| FreeToken TTFT：1K 0.8〜1.8 / 4K 1.5〜3 / 16K 4〜8 / 30K 6〜12 s | コード 2.54 / 2.85 / 8.10 / 10.63 s、日本語 2.62 / 3.18 / 10.37 / 16.29 s | コードの 4K・30K は範囲内。1K は遅く、日本語の長い入力は大きく遅い |
| Strata TTFT：1K 0.8〜1.2 / 4K 0.9〜1.5 / 16K 3〜4.5 / 30K 5〜7 s | 1.06 / 1.17 / 2.76〜2.89 / 4.91〜4.95 s | 1K・4K は範囲内。16K・30K は予想より少し速い |
| FreeToken decode：70〜110 tok/s | 59〜69 tok/s | 外れ（予想より遅い。前回記事の 0.1.2 の 65 tok/s と同水準） |
| Strata decode：コード 150〜200 / 日本語 125〜170 tok/s | コード 208〜224 / 日本語 171〜185 tok/s | 外れ（予想より速い） |
| 1. FreeToken の decode はトラックA より大きく下がる | 142 → 60〜68 tok/s | 支持（下がり方は予想以上） |
| 2. FreeToken の TTFT はトラックA の 8,192 と同程度か、やや遅い | コード 30K で 6.47 → 10.63 s（1.6 倍） | 方向は支持、差は予想より大きい |
| 3. Strata は MTP で decode が 1.2〜1.6 倍 | トラックA 比でコード 1.6 倍、日本語 1.3 倍（IQ3_S の重さと tail skip を含む） | 支持 |
| 4. MTP の受理率：コード 65〜80%、日本語 50〜70% | コード 68〜77%、日本語 54〜62% | 支持 |
| 5. 出荷状態では decode も Strata が速くなる | コードで約 3.6 倍、日本語で約 2.7 倍 | 支持（差は予想よりはるかに大きい） |
| 6. RAM は FreeToken 約 70 GiB、Strata 約 55 GiB | 空きの最小から逆算して、FreeToken 約 73 GiB、Strata 約 54 GiB（他のサービス分を含む） | 支持 |

### 外れた理由の仮説

- **FreeToken の decode が予想より遅い**：NVFP4 の expert は大きく、VRAM に置けるのが 5,926 スロット（全 24,576 の約 24%）にとどまる。トラックA の GGUF（約 54%）や Strata IQ3_S（約 51%）の半分以下で、キャッシュにない expert の転送が decode を支配している。W4A4 のカーネルの速さは、decode（1トークンずつ）ではほとんど効かない
- **日本語で FreeToken の decode が速く、TTFT が遅い**：NVFP4 では置ける expert が少ないため、どの expert がよく呼ばれるかの差が速さに直接出る。日本語の decode では呼ばれる expert が偏ってキャッシュに当たりやすく、長い日本語の prefill では幅広い expert が呼ばれて転送が増えていると考えられる（未検証。`--moe-collect-stats` で確かめられる）
- **Strata が予想より速い**：MTP の受理率は予想どおりだったが、1回の検証で受理される下書きの数が多く、MTP なしの 135 tok/s から予想以上に伸びた。IQ3_S の重さによる減速は、5090 では小さかった

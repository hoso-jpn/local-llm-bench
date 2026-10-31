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

---

## 結果（2026-10-31 計測、2026-11-01 追記）

計測は ABBA の順で4セッション（FreeToken s1 → Strata s1 → Strata s2 → FreeToken s2）。各条件で捨て1回＋本計測5回。下表は各セッションの中央値を、2セッションで平均した値（コード、256トークン出力。decode は 1,024 出力の値も併記）。生データは各セッションの `results.jsonl`、集計は `summary.tsv`。

| 入力長 | TTFT FreeToken | TTFT Strata | 比 | prefill FreeToken | prefill Strata | decode FreeToken（256 / 1024） | decode Strata（256 / 1024） |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1K | 1.56 s | 0.79 s | 2.0倍 | 691 tok/s | 1,373 tok/s | 144 / 135 tok/s | 132 / 136 tok/s |
| 4K | 4.63 s | 0.93 s | 5.0倍 | 896 tok/s | 4,491 tok/s | 145 / 140 tok/s | 135 / 135 tok/s |
| 16K | 13.71 s | 2.83 s | 4.9倍 | 1,199 tok/s | 5,827 tok/s | 143 / 140 tok/s | 135 / 134 tok/s |
| 30K | 24.24 s | 4.67 s | 5.2倍 | 1,270 tok/s | 6,592 tok/s | 145 / 140 tok/s | 135 / 135 tok/s |

日本語では TTFT の比が 2.0〜5.5倍、decode の差は FreeToken が 4〜6.5% 速い。全条件を通した decode の中央値は FreeToken 142.3 tok/s、Strata 134.8 tok/s（FreeToken が 5.6% 速い）。

### セッション間の再現性

- TTFT：2セッションの差は最大 0.64%
- decode：最大 1.8%。例外は Strata の「起動直後の最初の条件」（コード・1K・256出力）で、s1 127 tok/s と s2 136 tok/s（6.8%）。s1 では本計測の1〜2回目が 125〜127 tok/s で、その後 136 tok/s 前後に上がっている。起動直後に expert キャッシュが会話に合わせて入れ替わる間の遅れと考えられる。**起動後の最初の数リクエストは遅い**ことを、記事の注意点に入れる

### PCIe（リクエスト中の平均受信量、コード）

| 入力長 | FreeToken（256 / 1024 出力） | Strata（256 / 1024 出力） |
| --- | --- | --- |
| 1K | 13.3 / 7.8 GB/s | 7.8 / 2.8 GB/s |
| 4K | 21.9 / 13.1 GB/s | 9.8 / 3.4 GB/s |
| 16K | 26.9 / 20.7 GB/s | 13.1 / 6.2 GB/s |
| 30K | **29.0** / 24.3 GB/s | 15.5 / 8.3 GB/s |

256 出力では時間の多くが prefill なので、この値はほぼ prefill 中の転送量を表す。**FreeToken の prefill は 30K で平均 29.0 GB/s に達し、PCIe 5.0 x8 の実測上限（`ft bench bw` の H2D 28.9 GB/s）に張り付いている。** FreeToken の prefill は、この PC の x8 のリンクに律速されている可能性が高い。Strata はその約半分しか使わない（キャッシュにない expert の 75% を CPU で計算するため）。

その他：RAM の空き（最小）は FreeToken 69.6 GiB、Strata 72.8 GiB。トークンの到着間隔の p99 は FreeToken 9.6 ms、Strata 14.8 ms。

### 予想との照合

| 予想 | 結果 | 判定 |
| --- | --- | --- |
| FreeToken TTFT：1K 1.5〜3 / 4K 4〜5 / 16K 11〜15 / 30K 20〜27 s | 1.56 / 4.63〜4.74 / 13.7〜14.3 / 24.2〜25.4 s | すべて範囲内 |
| Strata TTFT：1K 0.3〜0.6 / 4K 0.8〜1.1 / 16K 3〜4.5 / 30K 6〜9 s | 0.79 / 0.92 / 2.7〜2.8 / 4.67 s | 4K のみ範囲内。1K は遅く、16K・30K は速かった（prefill が長い入力ほど速くなり、30K で 6,600 tok/s に達した） |
| FreeToken decode：135〜150（1K・4K）、125〜145（16K）、115〜140（30K） | 135〜145（すべての入力長） | 30K は予想の上限をわずかに超えた |
| Strata decode：115〜135（1K・4K）、105〜130（16K）、95〜125（30K） | 132〜137（すべての入力長） | 16K・30K は予想より速い |
| 仮説1：prefill は Strata が 4〜6 倍速い | 4K 以上で 4.9〜5.5 倍、1K では 2.0 倍 | 4K 以上では支持。1K では差が小さい |
| 仮説2：decode は FreeToken が 10〜20% 速い | 平均 5.6%（条件により −1〜+10%） | 外れ。方向は合っているが差は小さい |
| 仮説3：入力が長いほど decode は下がる | 1K〜30K でほぼ横ばい（両エンジン） | 外れ |
| 仮説4：日本語とコードで decode の差は 5% 以内 | 差は 2% 以内 | 支持 |
| 仮説5：セッション間の差は 3〜7% | TTFT 0.6% 以内、decode 1.8% 以内（起動直後の1条件を除く） | 外れ（予想より再現性が高い） |

### 外れた理由の仮説

- **仮説3（decode が長さで落ちない）**：Qwen3.8-Flash-Next は 48 層のうち 36 層が Gated DeltaNet（線形 attention、状態の大きさが文脈長によらない）で、残る 12 層も Qwen Sparse Attention（ブロックを選んで読む）。32K までの文脈では、attention の重さが expert の処理に比べて小さいままだと考えられる。64K 以上で崩れるかは未確認
- **Strata の prefill が長い入力ほど速い**：8,192 トークンのチャンクで expert を一度運べば、そのチャンク内のトークン全部に使い回せる。入力が長いほど、運ぶ回数あたりの計算量が増え、転送のコストが薄まる。1K では 1チャンクしかなく、この利点が出ない
- **仮説2（decode の差が小さい）**：試運転の Strata が 124 tok/s と低かったことに引きずられた。本計測では起動直後を除き 134〜137 tok/s で安定していた

## 次に確かめること

1. FreeToken の `--max-prefill-length 8192`（Strata と同じチャンク）で TTFT がどれだけ縮むか。PCIe x8 に張り付いているなら、チャンクを大きくしても縮まない可能性がある
2. 64K 以上の入力で decode が落ちるか（コンテキストを広げて起動）
3. トラック B（出荷状態：FreeToken NVFP4、Strata IQ3_S＋MTP）

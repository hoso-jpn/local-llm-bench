# 2026-10-31 準備のメモ

## 両エンジンを IQ3_XXS の GGUF で初めて起動した結果

同じファイル（`/data/strata/models/IQ3_XXS/`、sha256 は `strata_iq3xxs_check.txt`）を両エンジンに渡した。

| 項目 | Strata v0.1.42 | FreeToken v0.2.0 |
| --- | --- | --- |
| RAM に置いた expert | 39.97 GiB（2.27 GiB/s） | 40.0 GiB（7秒。直前に Strata が読んだためページキャッシュに載っていた可能性が高い） |
| PLE（n-gram 表、2つ目のシャード 28.8GB） | SSD から読む（`--ple-gguf`） | SSD から読む（`ple_backend='disk'`、pread ×16、O_DIRECT） |
| VRAM の expert キャッシュ | 14,795 個（24.04 GiB） | 13,235 スロット（型ごとに 10 プール、276〜2,206 スロット） |
| KV キャッシュ（32K） | int8 | 0.77 GiB（bf16） |
| 起動時の RAM 使用 | used 49GB / available 73GB | コンテナ 48.6 GiB / available 70GB |
| VRAM の使用 | 31.7 / 32.6 GB | 28.8 / 32.6 GB |
| 準備完了までの時間 | 約1分（expert 読み込み 32秒＋キャッシュ充填） | 約3分22秒（うち CUDA graph の取り込み 191秒。JIT。キャッシュを残せば2回目以降は短くなるはず） |
| 「2+2は？」 | 4（2トークン、下書き3・受理3） | 4（2トークン） |
| MTP | あり（`timings.draft_n` で受理数が分かる） | なし（オプションが存在しない） |
| thinking の既定 | high | xhigh（`reasoning_effort: none` は受け付ける） |

### 記事に使えそうな点

- 前回記事の FreeToken 0.1.2＋NVFP4 は、PLE 47.7 GiB を RAM にピン留めし、合計 114.7 GiB を回収できない形で使っていた。v0.2.0＋GGUF では PLE を SSD から読み、RAM は約 49 GiB で済んだ。「128GB は実用の下限」という前回の結論は、v0.2.0 では当てはまらない可能性がある（NVFP4 でも `--ple-backend disk` で確かめる）
- 2つ目のシャード（PLE、28,800,138,432 バイト）の sha256 `316b46f3…c161e113` は、InsiderLLM が記録した Coder 版 IQ1_M の2つ目のシャードと一致した。PLE 表は量子化の種類によらず共通
- GSQ-RCO の「IQ3_XXS」は1つの型ではない。expert の gate_up は IQ2_XXS / IQ2_XS / IQ2_S / IQ3_XXS / IQ3_S、down は IQ4_NL / Q2_0 の混合（`freetoken_gguf_check.jsonl`）
- FreeToken v0.2.0 は IQ1_M のカーネルを持たない（`freetoken_kernels.json`）。Coder 版 IQ1_M は FreeToken では動かない

## 計測の条件で揃えていない点（記事に明記する）

- prefill のチャンク：FreeToken は前回記事どおり `--max-prefill-length 2048`、Strata は `--prefill auto`（RTX 3060 では 8192 が選ばれたという報告がある）。感度を見るため、FreeToken の 8192 も1セット取る
- KV キャッシュの精度：Strata int8、FreeToken bf16
- コールドロードは `drop_caches` の後に測る（今回の FreeToken の 7秒はページキャッシュの影響）

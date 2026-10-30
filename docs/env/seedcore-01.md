# Seedcore-01 検証環境

計測のたびに `scripts/env_check.sh` の出力を `results/<run>/env_check.txt` に残す。このファイルには、構成と変更履歴だけをまとめる。

## 構成（前回記事時点、2026年9月）

| 項目 | 内容 |
| --- | --- |
| CPU | AMD Ryzen 9 9950X3D |
| GPU | ASUS ASTRAL RTX 5090 32GB |
| RAM | Crucial DDR5 128GB（32GB × 4、実動作 3600 MT/s） |
| マザーボード | ASUS ROG STRIX X870-F GAMING WIFI |
| システムSSD | WD_BLACK SN8100 4TB（M.2_1） |
| データSSD | WD_BLACK SN7100 4TB（M.2_2。PCIEX16(G5)と帯域を共有） |
| 電源 | Corsair HX1500i |
| OS | Ubuntu 24.04 LTS |
| GPU接続 | PCIe 5.0 x8（M.2_2が使われているため） |

前回の `ft bench bw` の結果：CPU STREAM read 50.1 GB/s、PCIe H2D 28.9 GB/s、D2H 28.7 GB/s、NVFP4 CPU-MoE 45.5 GB/s、NVFP4 PCIe gather 26.7 GB/s、CPU/PCIe比 1.70x（推奨：offload）。

## ストレージと既存の資産（2026-10-31 確認）

| 場所 | 中身 |
| --- | --- |
| `/home`（SN8100、nvme0n1p3） | 空き 3.1TB。`~/apps/nvfp4-strata-comparison/`（2026-10-11 の比較実験）、`~/apps/strata-comparison-source/`（Strata のソース）、`~/apps/freetoken-context-fix/`、`~/seedcore-ops/`（FreeToken のメモリ運用メモとガード） |
| `/data`（SN7100、nvme1n1p1、ext4） | `freetoken-flash-next/models/Qwen3.8-Flash-Next-NVFP4`（NVFP4 の重み）、`freetoken-flash-next/cache/`、`llama-flash-next/`（llama.cpp、2026-08） |
| Docker | FreeToken はコンテナ `freetoken-qwen38-flash-next-trial`（127.0.0.1:1919）で動かしている |

注意：`strata-comparison-source/data/experimental-speed-projection/` は速度向上の機能ではなく、拒否方向を取り除く制御ベクトル。比較では常に OFF にし、OFF であることを記録する。

## リポジトリへの push

Seedcore-01 からは、このリポジトリ専用の書き込み可デプロイキー（`~/.ssh/local_llm_bench_deploy`、ホスト別名 `github-llmbench`）で push する。GitHub CLI は使わない。

## 変更履歴

| 日付 | 変更 | 影響 |
| --- | --- | --- |
| 2026-09 | 初期構成（上表） | — |
| 2026-10-31 | 変更なしを確認（PCIe Gen5 x8、32GB × 4 @ 3600 MT/s）。ドライバ 595.99.02、CUDA Toolkit 12.8、カーネル 6.8.0-142、Ubuntu 24.04.5、Python 3.12.3 | 前回記事の値と直接比べられる。Strata のビルドには CUDA 13 を別途入れる |

## 予定している変更（前回記事より）

1. SN7100をM.2_2からM.2_4へ移し、GPUをPCIe 5.0 x16に戻す
2. 32GB × 4を64GB × 2に替え、RAM速度を上げる（DDR5-5600を狙う）
3. FreeTokenのoffloadとhybridを比べる

ハードを変えたら、変更前後で同じ計測を1セット取ってからこの表に追記する。

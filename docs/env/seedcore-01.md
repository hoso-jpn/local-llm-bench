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

## 変更履歴

| 日付 | 変更 | 影響 |
| --- | --- | --- |
| 2026-09 | 初期構成（上表） | — |
| | <!-- 例：SN7100をM.2_4へ移設 → PCIe x16 --> | |

## 予定している変更（前回記事より）

1. SN7100をM.2_2からM.2_4へ移し、GPUをPCIe 5.0 x16に戻す
2. 32GB × 4を64GB × 2に替え、RAM速度を上げる（DDR5-5600を狙う）
3. FreeTokenのoffloadとhybridを比べる

ハードを変えたら、変更前後で同じ計測を1セット取ってからこの表に追記する。

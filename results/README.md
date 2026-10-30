# 計測結果

1回の計測につき1ディレクトリを作る。名前は `YYYY-MM-DD_<track>_<engine>`（例：`2026-11-01_trackA_strata`）。

| ファイル | 中身 |
| --- | --- |
| `prereg.md` | 計測前に書く予想と条件。**計測を始める前にコミットする** |
| `env_check.txt` | `scripts/env_check.sh` の出力 |
| `pcie.csv` | `scripts/pcie_under_load.sh` の出力（負荷中のPCIe） |
| `results.jsonl` | `bench/llm_engine_bench.py` の出力 |
| `engine.log.gz` | エンジンのログ（必要な部分だけ、または圧縮） |
| `notes.md` | 気づいたこと、異常値、やり直した理由 |

雛形は `_template/` にある。

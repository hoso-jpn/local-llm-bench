# Strata の設定

- `strata launch` が生成した設定 JSON の `args` を、トラックに応じてこのディレクトリのファイルで置き換える
- トラックAでは `STRATA_ROUTE_TAIL_SKIP=0` を環境変数で渡す（v0.1.42以降、CUDAでは既定で7）
- 起動ログ（`strata-<model>.log`）から、VRAMに載ったexpert数、MTPの受理率、PCIeの実測値を `results/<run>/` に抜き出しておく
- 使ったStrataのタグとcommitを `results/<run>/prereg.md` に書く

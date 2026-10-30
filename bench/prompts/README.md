# プロンプト素材

公開リポジトリに入れるので、権利上問題のない素材だけを置く。

| ファイル | 中身 | 出典とライセンス |
| --- | --- | --- |
| `code.txt` | llama.cpp のソースを連結したもの（例：`src/llama-context.cpp` ほか） | llama.cpp（MIT）。使った commit を下に記録する |
| `ja.txt` | 日本語の長文 | 青空文庫など、著作権が切れた作品。作品名を下に記録する |

長さはスクリプトが tokenizer で切り出すので、各ファイルは 130K トークン以上にしておく（足りない分は繰り返して埋める）。

## 記録

- code.txt：llama.cpp commit `TODO`
- ja.txt：`TODO`

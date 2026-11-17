# 各OSでのデバッグ機能の出力

英語版：[README.md](README.md)（こちらが原本）。

このディレクトリには、`tests/scripts/verify-debug-outputs.py` が各OSで記録した結果を置きます。デバッグ機能（[docs/DEBUGGING.ja.md](../../../docs/DEBUGGING.ja.md)）の出力を、OSの間で1行ずつ比べるためのものです。tque #890（macOSの出力を、WindowsとLinuxの出力と直接比べる）のために作りました。

| ファイル | OS |
|---|---|
| `macos.json` | macOS 27.2、Apple silicon（arm64）、FORTH/Sigma 0.11.0 |
| `windows.json` | Windows（これから記録する） |
| `linux.json` | Linux（これから記録する。WSLでもよい） |

## 記録するもの

スクリプトは27通りを、それぞれOSの一時フォルダーに作った新しいフォルダーの中で、どのOSでも同じプログラム（docs/DEBUGGING.md の `prog.fs`）と入力で動かします。そのため、出力に絶対パスは入りません。それぞれについて、次のものを保存します。

- 渡した引数と標準入力
- 終了コード
- 標準出力と標準エラー（出たまま、UTF-8として読む）
- その場合に書かれるファイル（`--format` の後の `fmt.fs`、`--debug-log` の `run.jsonl`）

27通りは、docs/DEBUGGING.md の例（バックトレース、`--max-steps`、`--trace`、`~~` と `~~BT`、パイプからのキーでの `DBG`、`WATCH`、`--profile`、`--coverage`、`--lint`、`--format-check`、`--debug-log`）と、例のない機能（`--max-steps=N`、`--trace-limit`、`~~1BT` と `ONCE`、`~~VALUE` と `~~VARIABLE`、`DBG` のキー `n`・`u`・`d`・`s`、`BREAK:` と `BREAK"`、`UNWATCH`、`.COVER-RAW`、`--lint` の4種の指摘、`--format`、`--format-indent`、`--`）です。一覧はスクリプトの `CASES` にあります。

## 各OSでの記録

リポジトリのルートで、リリースのビルドを使います。

```sh
zig build -Doptimize=fast
python3 tests/scripts/verify-debug-outputs.py --sigma zig-out/bin/sigma --out tests/scripts/debug-outputs/macos.json
```

Windowsでは次のとおりです。

```powershell
zig build -Doptimize=fast
python tests/scripts/verify-debug-outputs.py --sigma zig-out/bin/sigma.exe --out tests/scripts/debug-outputs/windows.json
```

ファイルには、OS、プロセッサー、バナーの1行目（版）も記録されます。もう一方のOSで比べられるよう、できたファイルをコミットします。

## 2つのOSの比較

```sh
python3 tests/scripts/verify-debug-outputs.py --compare tests/scripts/debug-outputs/macos.json tests/scripts/debug-outputs/windows.json
```

1つ目のファイルの各場合を、2つ目のファイルの同じ名前の場合と比べます。比べるのは、終了コード、標準出力、標準エラー、ファイルです。Windowsは行を CR LF で終えるので、比べる前に CR LF を LF とみなします。それ以外は変えません。結果は、場合ごとに1行で出ます。

- `[same]`：すべて同じ。
- `[differs]`：違うもの（`exit 1 / 0`、`stdout`、`stderr`、`file fmt.fs`）が続き、標準出力と標準エラーは、違う行ごとに、行番号と、1つ目のファイルの行、2つ目のファイルの行を引用符つきで示す。
- `[missing]`：2つ目のファイルに、その名前の場合がない。

最後の行は、場合の数と、違った場合の数です。終了コードは、違いがなければ0、あれば1です。

確認を終える前に、すべての違いの理由を明らかにします。不具合か、意図したOSの違い（docs/DECISIONS.md に記録する）のどちらかです。2つのファイルは同じコミットで記録したものを使い、結果の先頭の版の行で確かめます。

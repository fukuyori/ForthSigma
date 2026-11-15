# macOS実機のP10検証

2026-11-15。tque #752（#553 → #742配下）の検証記録。

## 対象と環境

- 対象コミット：`16945a5ffacbd1a33a846d832849f4347b499ff2`。開始時の作業ツリーに変更なし。
- macOS 27.2、arm64、Zig 0.17.1。通常版・単独機能除外8構成ともネイティブターゲットでビルド・実行。
- `scripts/verify-feature-matrix.py`に`--platform macos`を追加。既存のWindows・Linux・WSL経路は維持した。アプリケーション実装の変更なし。
- 初回は既定キャッシュへのアクセスがPermissionDeniedで停止。リポジトリ内の`.zig-global-cache`・`.zig-cache`を指定して以降の検証を実施した。

## 結果

通常版の単体テストは1062成功・7 skip、21/21ビルドステップ成功。全構成のビルド・単体テスト・freestanding確認と、以下のP10統合が成功した。

| 構成 | 単体テスト成功 | skip | P10統合成功 |
| --- | ---: | ---: | ---: |
| 通常 | 1062 | 7 | 37 |
| float除外 | 997 | 46 | 36 |
| files除外 | 845 | 222 | 30 |
| help除外 | 1051 | 18 | 37 |
| tools除外 | 1025 | 44 | 37 |
| image除外 | 1023 | 46 | 24 |
| graphics除外 | 943 | 125 | 34 |
| audio除外 | 1041 | 28 | 34 |
| debug除外 | 1000 | 69 | 36 |

通常37件＋除外版268件＋構成間保存イメージ読込7件＝312件成功。全統合JSON・`matrix.json`・`cross-build.json`の`complete: true`と件数を照合した。通常版の辞書を7除外版へ読み込み、float除外版では保存された浮動小数点語の実行を-261で拒否することも確認した。

追加でランタイム13件（深い再帰回復、出力順、SYSTEM、flush、入力前プロンプト）が成功。文書チェックは指摘0件。全7語彙の実行時辞書に記載漏れなし、標準キー35件、出力例28件、単独使用例132件も成功した。

## 実行方法と証跡

```sh
export ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-global-cache"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache"
zig build test --summary all
zig build --prefix .work/p10/macos/default --summary all
python3 scripts/verify-p10.py --sigma .work/p10/macos/default/bin/sigma --output .work/p10/macos/default-integration.json
python3 scripts/verify-feature-matrix.py --platform macos
python3 scripts/verify-p10-cross-build.py --default .work/p10/macos/default/bin/sigma --matrix .work/p10/macos
python3 scripts/verify-runtime.py --sigma .work/p10/macos/default/bin/sigma --output .work/p10/macos/runtime.json
python3 scripts/check-docs.py
python3 scripts/word-reference.py --check --sigma .work/p10/macos/default/bin/sigma
```

証跡は`.work/p10/macos/`。環境は`environment.json`、通常版は`default-{tests,build,integration}.log`・`default-integration.json`、除外版は`no-*-{tests,build,integration}.log`・`no-*-integration.json`、集計は`matrix.json`・`matrix.log`、構成間読込は`cross-build.json`・`cross-build.log`。追加確認は`runtime.json`・`runtime.log`、`docs.log`、`reference-check.log`。

tqueは752 → 742 → 553 → 542の順に全子の完了を照合してdoneとし、542配下全件のdone・auto100%を再照会した。照会結果は`tasks-before.json`・`tasks-after.json`。

## 範囲

単独機能除外8構成であり、全256構成の確認ではない。保存した描画・音声語の検証は、表示・音声デバイスの目視・聴取確認ではない。今回の追加実行は上記P10・ランタイム・文書確認であり、過去のPTYや境界テスト全体を再実行したものではない。Windows・WSL・Linuxの既存結果は各検証記録を参照する。

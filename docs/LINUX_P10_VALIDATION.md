# LinuxネイティブのP10検証

2026-11-15。tque #754（#553 → #742配下）の検証記録。

## 対象と環境

- 対象コミット：`9d26340569a15d0ddc2e105b2c0eebdd4223c625`。作業開始時にGitリモートのmain先端との一致を確認した。
- Ubuntu Linux x86_64、カーネル`7.0.0-43-generic`、Zig `0.17.1`。
- `/tmp/ForthSigma-553-linux`の`task-553-linux`作業ツリーで実施。元の作業ツリーの未コミットCATCH差分を保持した。
- 通常版はLinuxネイティブターゲット（glibc）、単独機能除外8構成は`x86_64-linux-musl`。ビルドランナー・Python・テスト・実行ファイルはすべてこのLinux環境で直接実行した。

## 検証中に修正した項目

- `verify-feature-matrix.py`はWindowsからWSLを起動する方式だけに対応していた。Linux上ではZigのビルドランナーとPython統合テストを直接実行するよう修正し、JSONに`execution: native`とホスト情報を記録する。Windows・WSLの既存経路は残す。
- glibcでSIGPIPE復元テストが失敗した。Linuxのシグナル集合はlibcの予約領域を含み、予約領域のバイト比較は有効なシグナル状態の比較にならない。テストをLinuxカーネルのシグナル集合サイズの範囲に限定した。ハンドラーとフラグの一致、EPIPEの発生、flush/closeの成功確認は維持した。処理系のSIGPIPE処理は変更していない。確認にはローカルのZig標準ライブラリの`sigset_t`定義と[glibcのsigaction実装](https://codebrowser.dev/glibc/glibc/sysdeps/unix/sysv/linux/libc_sigaction.c.html)を参照した（実装コードの転用なし）。

## 結果

すべて成功。通常版の`zig build test`は21/21ビルドステップ成功（修正前に通ったコアテストはキャッシュ利用、修正対象のホストテストは63成功・1 skip）。通常ビルド、各除外構成の単体テスト・freestanding確認・ビルドも成功した。

| 構成 | 単体テスト成功 | skip | P10統合成功 |
| --- | ---: | ---: | ---: |
| 通常 | 全テストステップ成功 | 上記参照 | 37 |
| float除外 | 997 | 45 | 36 |
| files除外 | 845 | 221 | 30 |
| help除外 | 1051 | 17 | 37 |
| tools除外 | 1025 | 43 | 37 |
| image除外 | 1023 | 45 | 24 |
| graphics除外 | 943 | 124 | 34 |
| audio除外 | 1041 | 27 | 34 |
| debug除外 | 1000 | 68 | 36 |

通常版37件＋除外版268件＋構成間保存イメージ読込7件＝312件。すべての統合JSON、`matrix.json`、`cross-build.json`の`complete: true`を照合した。通常版で保存した辞書を7除外版へ読み込み、float除外版で保存済みの浮動小数点語の実行が-261になることも確認した。

追加のLinuxネイティブ確認も成功した。

- ランタイム13件：再帰回復・出力順・SYSTEM・flushなど。
- POSIX統合10件：パイプ・SH-GET・エディタ引数・レポート権限/削除・保存復元。
- PTY/FIFO 24件：入力・Ctrl+C・resize・修飾キー・NS中断・端末モード復元。
- 境界482件：権限・glob・パス・cwd・mkdir・列挙・FPATH・バイト入力・時計/TZ・SH-GETの寿命など。`--minimal`にはfiles除外版を指定（このスクリプトがその実行体に要求するのはFILENAME-MATCHの除外確認だけ）。全機能同時除外の最小構成試験ではない。
- 文書チェック指摘0件。SIGPIPEテストの変更だけで語の説明・使用例に影響しないことを確認し、`translation-sources.json`の指紋を更新した。生成本文に変更なし。
- 全7語彙の実行時辞書の記載漏れなし、EKEYS値35件一致、出力例28件と単独実行例132件成功。

追加証跡は`runtime.json`、`posix-native/report.json`、`posix-terminal/report.json`、`posix-boundaries/report.json`、`docs.log`、`reference-refresh.log`、`reference-check.log`。`git diff --check`と`zig fmt --check src/main.zig`も成功した。

## 実行方法

```sh
zig build test --summary all
zig build --prefix .work/p10/linux/default --summary all
python3 scripts/verify-p10.py --sigma .work/p10/linux/default/bin/sigma --output .work/p10/linux/default-integration.json
python3 scripts/verify-feature-matrix.py --platform linux
python3 scripts/verify-p10-cross-build.py --default .work/p10/linux/default/bin/sigma --matrix .work/p10/linux
python3 scripts/check-docs.py
```

証跡は同作業ツリーの`.work/p10/linux/`に保存する。環境は`environment.json`、通常テストは`default-tests.log`、構成別ビルド・単体・統合は`no-*-{tests,build,integration}.log`と`no-*-integration.json`、全体集計は`matrix.json`、構成間保存読込は`cross-build.json`。

## 範囲

単独機能除外8構成を対象とし、複数機能の同時除外全256構成ではない。保存したグラフィックス・音声語の検証は、描画・音声デバイスの目視・聴取確認ではない。macOS実機の#752は別項目であり、このLinux検証で#742・#553全体を完了にはしない。

## 元の作業フォルダーへの統合（2026-11-15）

利用者の指示により、元の`/home/fuk/source/zig/ForthSigma`のmainを`9d26340`へfast-forwardし、このLinux検証の修正と文書を反映した。`.work/p10`の証跡も全ファイルのSHA-256一致を確認してコピーした。証跡内の古い絶対パスは初回検証時の作業先を表す。

元の未コミットCATCH差分はstash「Preserve pre-integration CATCH changes 2026-11-15」と`/tmp/ForthSigma-catch-before-integration.patch`に退避した。最新mainのCATCH再帰対策・拡張された回帰テストを確認し、古い本体実装は重ねなかった。元の回帰テストは追加保持した。これに伴うテストファイルの指紋変更は日本語説明への影響なしと確認して更新した。

統合後に通常テストを実行し、1063件成功・6件skip（コア1000成功・5 skip、ホスト63成功・1 skip）、21/21ビルドステップ成功。通常ビルドとP10統合37件も成功した。証跡は元のフォルダーの`.work/p10/linux/integrated-tests.log`・`integrated-build.log`・`integrated-p10.json`。統合に伴う実装変更はなく、8除外構成の結果は初回検証記録を維持する。

退避したCATCH差分は復元可能な状態で保持する。

統合後の文書チェックは指摘0件。回帰テスト挿入により変わった英日ワードリファレンスの参照行番号も再生成した。別作業ツリーの変更ファイル6件は`.work/p10/integration-backup/`へ追加退避したうえで、`/tmp/ForthSigma-553-linux`のworktreeを削除した。作業先は元のフォルダーへ一本化済み。

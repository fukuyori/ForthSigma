# 900 共通基盤のMac実機確認

対象：tque 1065（親1063、祖先900）のMac実機確認。共通基盤に加え、1056・1036で実装した語群とOS判別のMac確認もここに残す。状態：未実行。Windowsでのaarch64-macos向けコンパイル成功とは別の作業である。

本書はMac側で実行する手順。Zigはこのリポジトリが要求する版を使い、リポジトリのルートで実行する。Python 3を使う。Gforthや別リポジトリの読取りは不要。

## 手順

1. `zig version`と`git rev-parse HEAD`、作業中の差分の有無を記録する。今回の実装は未コミットのため、変更したファイルも同じ内容であることを確認する。
2. `zig build runtime-test --summary all`を実行する。共通の時計・起床・台帳・信号所有・回復の試験が成功することを確認する。
3. `zig build test --summary all`を実行する。スキップの件数と理由も記録する。ホスト試験にNSの復元と時計故障・信号復元再試行の試験が含まれることを確認する。
4. `zig build --prefix .work/runtime-native --summary all`で検証用の実行体を作る。配布用のパッケージは作らない。
5. `python3 tests/scripts/verify-p05b-ns.py --sigma-only --sigma .work/runtime-native/bin/sigma`を実行する。これはNSの期限・範囲・リダイレクト入力・SIGINT後の再待機、PTYのcanonical/raw・制御文字・端末状態復元を検査する。試験が自分で起動した子プロセスへ信号を送る。
6. `.work/runtime-native/bin/sigma -e "REQUIRE-EXTENSION ALSO EXTENSION HOST-OS TYPE PREVIOUS BYE"`の出力が`macos`であることを記録する。
7. `python3 tests/scripts/verify-extension-matrix.py`を実行する。3語群の8通りとfiles/debug等を除いた4構成、除外した実行体でのイメージ拒否を確認する。結果は`.work/extension-matrix/matrix.json`へ保存する。
8. 可能なら`zig build test -Dgraphics=false -Daudio=false -Ddebug=false --summary all`も実行し、除外構成の結果を記録する。

## 期待する結果と記録

- コマンドが成功し、NS用スクリプトの`pass`がtrue。`comparison`はfalse、`runtimes`はsigmaのみ。Gforthとの互換比較を行った結果ではない。
- PTYケースはcanonical-interrupt、raw-interrupt、raw-special、raw-control、canonical-normalが成功する。
- 識別値、台帳の寿命、信号復元・失敗からの回復、pipeの非ブロッキング・close-on-execを確認する。失敗時はコマンド・標準出力・標準エラー・対象コードの版を残す。
- 結果は[実装記録](CORE_EXTENSION_IMPLEMENTATION.md)とtqueへ反映する。クロスコンパイルだけでこの実機項目を完了にしない。

共有後のRuntime/Wake/OwnedTableはコピー・移動せず、通知側・消費者を止めてjoinしてから解放する契約の範囲を確認する。SIGKILL等の強制終了での端末や子の完全回収を保証する試験ではない。

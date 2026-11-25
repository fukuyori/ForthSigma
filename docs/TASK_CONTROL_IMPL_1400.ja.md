# AC-28：タスク除外の検査（1400）

主文書は[英語版](TASK_CONTROL_IMPL_1400.md)。構成別の期待は
[構成表](TASK_CONTROL_CONFIG_MATRIX.md)に記載した。

`src/tests/task_exclusion_test.zig` をcoreの通常試験へ登録し、検索順に依存せず
辞書全体、構成で絞ったHELP表、保存イメージを検査する。公開58語に加えて
`task_` builtinタグ全件を対象とし、タスク専用OpKindが存在しないことも検査する。
extension=falseの辞書にTASK builtinはなく、名前のない項目も残らない。
wire互換性のため構成間で共通のBuiltin enum識別子や、共用ホスト基盤の除去は要求しない。

HELPの構成で絞った表はextension=trueでTASK項目58件、falseで0件となる。
help=falseはHELP入口を除外するが、この表の絞込み条件とは独立している。
試験では表を明示的に参照するため、試験実行体に表があることから製品実行体にも
残ると判断することはできない。

extension=falseでは実際のencoder出力をparseし、TASK名・TASK builtin・
除外builtinの直接Opがないことを確認する。さらに58語それぞれを追加builtin語と
直接`.builtin` Opとして個別に挿入して保存し、正しいチェックサムを持つイメージを
restoreがInvalidImageで拒否すること、拒否前後の保存内容がバイト単位で一致することを
確認する。他の拡張語や不正なチェックサムによる拒否で代用しない。

構成スクリプトでも公開SAVE・LOAD-DICTIONARYを使用する。extension=trueで
EXTENSIONを読み、58語すべてへの参照を定義してSAVEしたイメージを、
extension=falseの各構成で読み込む。-264で拒否し、既存語を実行でき、
拒否後の新規定義も実行できることを確認する。各消費側でもSAVEを実行する。一方、EXTENSIONを読み込まず基本辞書だけを保存した
extension=trueのイメージは受け入れ、既存語と読み込んだ語を実行できることも確認する。

ソース読込みの失敗は58語をそれぞれ新しい定義に含めて確認する。
UnknownWordと通常のエラー報告による復旧後、既存の語数・コード数・HEREが一致し、
失敗した定義はなく、既存語と後続の新規定義を実行できることを検査する。
正常に完了した先行定義や任意の副作用までソース全体として巻き戻す保証ではない。

## 検証

2026-11-25、Windows AMD64、Zig 0.17.1、Python 3.14.3で実行した。
開始時HEADは`f33eb57`、最終確認時は`d3d0d66`だった。
コミット・ブランチ作成・プッシュは行っていない。既定のZigグローバルキャッシュは
書込み権限がなかったため、リポジトリ内の`.zig-global-cache`を使用した。

| コマンド | 結果 |
|---|---|
| `zig build test` | 合格 |
| `zig build test -Ddebug=false` | 合格 |
| `zig build -Dextension=false test` | 合格 |
| `zig build runtime-test` | 合格 |
| `python tests/scripts/verify-task-public-matrix.py` | C00〜C17の18構成すべて合格。155コマンドすべて成功 |
| `python scripts/check-docs.py` | 合格、findings: 0 |
| `zig fmt --check src/forth_test.zig src/tests/task_exclusion_test.zig` | 合格 |

extension=falseの7構成C00/C02/C04/C06/C12/C13/C17すべてで、TASK語を含む
イメージの拒否は`-264 42 9`、基本辞書イメージの受入れは`0 42 77`となった。
core試験では各builtin／直接Opの個別拒否前後で辞書の保存内容がバイト単位で一致した。
ログは`.work/ac28-*.log`（最終マトリクスは`.work/ac28-matrix-final.log`）、
構成別のログ・コマンド・結果は`.work/task-public-matrix/`に保存した。
語の説明変更を伴わない試験追加であることを確認し、日本語語彙リファレンスの
ソース指紋を更新した。今回追加した検査のLinux・macOS実行はClaudeが担当し、
ここでは未実施である。

`tque show 1400`は実行したが、保存先のロックを開く際にアクセス拒否となった。
tqueのファイルは直接操作せず、完了印も付けていない。

TaskManager等のコード残存、通常ループの機械語、性能、128 MiBの実測は対象外。
生成コード比較は1390に残す。保存イメージの互換性方針は変更していない。

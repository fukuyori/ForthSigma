# ForthSigma 作業引き継ぎ

更新日：2026-11-15。現在状態はこの文書、実装経緯は各フェーズ記録とgit履歴を参照する。tqueの表示番号は振り直されるため、再開時はタスク名と親子関係で照合する。

## 現在状態

- 「すべてのワードの説明をドキュメント化する」（今回照会時753）は完了(auto100%)。[全ワードリファレンス](WORD_REFERENCE.ja.md)と[読み方・使用例](WORD_REFERENCE_GUIDE.ja.md)を英日で作成。全1,503項目に日本語説明・使用例・注意点を収録。全7語彙の実行時辞書1,463項目と構文・ローカル宣言40項目を照合し、記載漏れなし。単独使用例132件と出力確認例28件、標準キー値35件が成功。`zig build test`も成功。翻訳元の変更・説明や使用例の欠落を検出するチェックを追加。実装照合・Claude Codeレビューの指摘を修正し、動作回帰19件と選択・指紋の回帰5件も成功。詳細と検証の限界は[収録・検証記録](WORD_REFERENCE_STATUS.md)と[修正・レビュー記録](WORD_REFERENCE_REVIEW.md)を参照。

- P10の742は作業中。追加確認749〜751はWindows・WSLとも通常37件＋8単独機能除外268件＋構成間イメージ読込7件、各OS312件が成功。通常版最終ビルドとHELP・英日文書整合も完了、文書チェック指摘0件。[P10実施記録](P10_IMPLEMENTATION.md)。今回のP10で残るOS確認はmacOSの752。

- Windows確認は完了。通常1058成功・10 skip、最小582成功・457 skip、通常ビルド/freestanding、統合24件、追加境界378件、コンソール36件と既存ブロック/EKEY/ランタイム13件が成功。利用者のIME変換・全角/絵文字編集・表示確認も「ok」の回答で完了。tque537〜540・718・719とWindows専用確認はdone(auto)。[Windows検証記録](WINDOWS_VALIDATION.md)。
- Windows追加修正は既存ファイルのCRT属性保持とSYSTEM後のコンソールモード復元。WSL専用728〜741も今回すべて完了(auto)とし、全子の完了を再照会して607を完了にした。P10・542全体の統合条件は残る。[タスク対応表](PLATFORM_TASK_AUDIT.md)。
- WSL2 Ubuntuは最新ソースで通常1062成功・6 skip、最小586成功・453 skip、境界482件、PTY/FIFO24件、P01〜P03行列15,371件、CLI9件、EKEYのパイプ/PTY、SHOW PTY20件、POSIX統合10件等が成功。行編集18件の前回成功記録も維持。初期スタック1MiBでCLI/ランタイム/保存実行統合が成功。WindowsでLinux用にコンパイルしてWSLで実行した。指定Gforth比較・Linux版Zigのビルドランナーは今回の結果に含めない。[WSL検証記録](WSL_VALIDATION.md)。
- P00・S01・P01〜P09と依頼済みレビューは完了。P09は全50語、tque576・577・578・552・701が完了(auto)。P09レビュー修正は`a76d000`、追加examples・文書は`7ce9a4f`でpush済み。[実装記録](P09_IMPLEMENTATION.md)・[レビュー](P09_REVIEW.md)。
- 698も調査・修正・検証が完了(auto)。明示STDOUT書込みとSYSTEM/SH/エディタ実行後にSHOWが文字を上書きする問題を修正した。修正と本引継ぎは対応するコミットに含む（git履歴参照）。[修正記録](OUTPUT_ACTIVITY_FIX.md)。
- macOSの698修正時の検証は通常1061件通過（6 skip）、最小構成585件通過（453 skip）、freestanding確認、通常ビルド、半ブロック/SixelのmacOS疑似端末20ケース、P09b比較・エディタ・保存復元確認が通過。証跡は`.work/698-*`。Windows/Linux実機確認は含まない。
- tque階層121 → 415 → 542 → 553（P10）→ 742。742は未完了、子タスクからの自動進捗90%。743〜751はdone、752はtodo（今回再照会）。Windows/Linuxの基礎確認607と引用符付きEDITORの702は完了。
- `docs/NATIVE_WINDOW_STUDY.md`と`examples/graphs.fs`・`graphs-tk.fs`および関連文書はコミット済み。ネイティブウィンドウの実装検討は後回し。

## 次の作業と進め方

- ワード説明の文書化は完了。追加・修正時は日本語説明と使用例も更新し、`python scripts/word-reference.py --check --sigma zig-out/bin/sigma.exe`で全件照合する。翻訳元が変わった場合は日本語説明を確認してから`--record-reviewed-sources`で元ソースの指紋を更新する。使用例の抜粋は、参照先の準備・期待されるエラーを含む文脈と区別して扱う。

1. 次は752：macOS実機で今回のP10統合・単独機能除外・構成間保存読込を確認する。このWindows環境では未実施。過去のmacOS検証やクロスコンパイル成功を今回の実機結果として扱わない。`verify-feature-matrix.py`はWindows/WSL用で、macOS用オーケストレーションは未対応。
2. Windows・WSL追加確認749〜751は完了。追加ケースの全構成再実行、WSL構成間イメージ読込、HELP変更後ビルド・文書整合を再び未実施扱いにしない。検証範囲と証跡は[P10実施記録](P10_IMPLEMENTATION.md)を参照する。
3. 作業が完了した時点で証跡を文書へ記録し、該当するtqueタスクをdoneにする。タスク名は作業内容だけとし、「実施済」「未実施」「残件」などの状態を付けない。状態は完了フラグ、進捗はautoで管理する。752が残る742・553・542は完了にしない。
4. P09追加の組込み語によるABI変更があり、以前のイメージは再作成する。698修正による追加ABI変更はない。HANDOFFは現在状態・次の作業・制約に絞り、詳細は各検証記録へ記載する。

## 再開時の成果物と実行方法

- 再開時のHEADは`eaf0fe1`、開始時の作業ツリーはクリーンだった。従来のWindows/WSLソース・検証変更はこのコミットに含まれる。今回のワードリファレンス、HELP修正、生成・照合スクリプト、索引・引継ぎは同じ作業としてコミット対象にする。公開済みの状態はgit履歴とリモートで照合する。開始時に`git status --short`で再照会し、既存変更を保持する。
- P10用スクリプト：`scripts/verify-p10.py`（通常/除外版統合）、`scripts/verify-feature-matrix.py`（8構成のビルド・単体・統合）、`scripts/verify-p10-cross-build.py`（通常版→除外版の保存イメージ読込）。
- 既存除外版実行体：`.work/p10/windows/no-<機能>/bin/sigma.exe`、`.work/p10/linux/no-<機能>/bin/sigma`。機能は`float files help tools image graphics audio debug`。再実行前に対象ソースとビルド時点を照合する。
- 統合検証：`python scripts/verify-p10.py --sigma <実行体> --disabled <除外機能> --output <JSON>`。通常版では`--disabled`を省略。Linux実行体はWSLからLinux側のパスで指定する。
- 構成間読込：`python scripts/verify-p10-cross-build.py --default <通常版実行体> --matrix <.work/p10/windows または linux>`。WSLではWSL側のPythonから実行する。
- 証跡：`.work/p10/windows-default.json`、`linux-default.json`、両OSの`matrix.json`と構成別ログ、Windowsの`cross-build.json`、`.work/p10-docs.log`。`complete: true`と件数、実際のログを照合する。
- 今回は追加の実行検証まで完了。`.work/p10-refresh.log`と更新済みJSONが最新のWindows・WSL追加確認結果。最終ビルドは`.work/p10-windows-final-build.log`・`.work/p10-linux-final-build.log`、最終文書チェックは`.work/p10-docs-final.log`。

## 制約

- コミット・タグ・pushは、その依頼で明示された場合だけ行う。通常の実装継続からは推定しない。
- Windows/Linux確認は607配下で別管理し、パイプ/SH-GETは695、P06cは696。Windowsでの今回の確認範囲は上記記録を参照。freestandingビルド確認は実機実行ではない。
- 仕様や意図に不明点がある場合は実装前に問い合わせる。質問は通常のメッセージで行い、Queued follow-up inputsや専用質問ツールを使わない。比較用Gforth固有の不正アクセスや未定義動作は模倣しない。GPL実装コードを転用しない。
- 標準EKEYS（固定wid3）とGRAPHICSのキー値・検索順を混同しない。端末EKEY/EKEY?/KEY-IORのCtrl+Cは割込み(-28)、ファイル/パイプのバイト3は文字3。EKEY EOFは承認によりK-EOFへ変更済み（KEYは-262、KEY-IORは-512）。
- 辞書イメージはSIGIMG45/46/47。旧形式・不一致ABIは拒否する。アドレスは明示的な型付き登録で再配置し、生セルから推測しない。
- パッケージはスクリプト確認以外で作成しない。版番号を変える場合は[更新チェックリスト](version-update-checklist.md)に従う。
- リポジトリ外・外部データは利用者の許可ルールに従う。このセッションでは指定Gforth・tque・Gitリモート・依頼されたClaude Codeレビューへのアクセスが許可済み。
- `.work/`・`.zig-cache/`・`.zig-global-cache/`はGit管理外の検証成果物。clean/resetで破棄したりコミットへ混ぜたりしない。

## 検証と参照先

通常確認は`zig build test`と`zig build`。最小構成や追加検証は変更内容に応じて行う。同じ検証用ファイルを使うテスト同士は同時実行しない。比較前には実行体をビルドする。

指定Gforthはコミット`c479e1eec66dd57a2441c3020177267ba70d3bdc`の`.work/gforth-audit/gforth-build/`（Gforth1.0.1、GCC16再構築）。ローカル成果物がない場合は、過去の実測を実施済みと推測しない。

- [基本仕様・比較方針](GFORTH_P00_SPEC.md)、[フェーズ表](GFORTH_WORD_PHASES.md)、[決定事項](DECISIONS.md)
- [S01レビュー](S01_REVIEW.md)、[P01レビュー](P01_REVIEW.md)、[P02記録](P02_IMPLEMENTATION.md)、[P03記録](P03_IMPLEMENTATION.md)、[P04記録](P04_IMPLEMENTATION.md)
- [P05記録](P05_IMPLEMENTATION.md)・[レビュー](P05_REVIEW.md)、[P06記録](P06_IMPLEMENTATION.md)・[レビュー](P06_REVIEW.md)、[P07記録](P07_IMPLEMENTATION.md)、[イメージ形式](IMAGE_FORMAT45.md)

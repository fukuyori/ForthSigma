# ForthSigma 作業引き継ぎ

更新日：2026-11-14。現在状態はこの文書、実装経緯は各フェーズ記録とgit履歴を参照する。

## 現在状態

- P00・S01・P01〜P09と依頼済みレビューは完了。P09は全50語、tque576・577・578・552・701が完了(auto)。P09レビュー修正は`a76d000`、追加examples・文書は`7ce9a4f`でpush済み。[実装記録](P09_IMPLEMENTATION.md)・[レビュー](P09_REVIEW.md)。
- 698も調査・修正・検証が完了(auto)。明示STDOUT書込みとSYSTEM/SH/エディタ実行後にSHOWが文字を上書きする問題を修正した。修正と本引継ぎは対応するコミットに含む（git履歴参照）。[修正記録](OUTPUT_ACTIVITY_FIX.md)。
- 最新検証は通常1061件通過（6 skip）、最小構成585件通過（453 skip）、freestanding確認、通常ビルド、半ブロック/SixelのmacOS疑似端末20ケース、P09b比較・エディタ・保存復元確認が通過。証跡は`.work/698-*`。Windows/Linux実機確認は含まない。
- tque階層121 → 415 → 542。次は553（P10）。進捗はauto。Windows/Linux確認は607配下、引用符付きEDITOR実行パスの未確認事項は702で管理する。
- `docs/NATIVE_WINDOW_STUDY.md`と`examples/graphs.fs`・`graphs-tk.fs`および関連文書はコミット済み。ネイティブウィンドウの実装検討は後回し。

## 次の作業と進め方

1. 次は553（P10、統合と互換性の確認）。[完了条件](GFORTH_WORD_PHASES.md#p10-統合と互換性の確認)を確認し、macOSで複合機能、SAVE/LOAD/SAVESYS、FORGET/MARKER、エラー巻戻し、機能除外ビルドの未確認範囲を洗い出して進める。P09追加の組込み語によるABI変更があり、以前のイメージは再作成する。698修正による追加ABI変更はない。
2. Windows/Linux実機確認607配下はここでは実施しない。macOSでの確認結果と区別し、未確認条件を残したままP10全体や親542を完了にしない。
3. チャンク途中はコード・テスト・HELP・検証スクリプトだけを更新する。英日マニュアル、互換性一覧、フェーズ表、P0x記録、tqueはサブフェーズ完了時に一括更新する。チャンクの区切りだけで応答を終えず、依頼された作業の完了まで継続する。
4. HANDOFFは現在状態・次の作業・制約だけを保ち、経緯はフェーズ記録とgit履歴へ任せる。

## 制約

- コミット・タグ・pushは、その依頼で明示された場合だけ行う。通常の実装継続からは推定しない。
- **Windows/Linux実機確認はここでは行わない。** 607配下で別管理し、パイプ/SH-GETは695、P06cは696。freestandingビルド確認は実機実行ではない。
- 実装の未決事項は推奨案を選んで継続する（利用者の最新指示）。比較用Gforth固有の不正アクセスや未定義動作は模倣しない。GPL実装コードを転用しない。
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

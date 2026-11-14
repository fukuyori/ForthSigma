# ForthSigma 作業引き継ぎ

更新日：2026-11-14。現在状態はこの文書、実装経緯は各フェーズ記録とgit履歴を参照する。

## 現在状態

- ブランチはmain。P06cは`78f79ae`でorigin/mainへpush済み。P06レビュー修正のコミットはgit履歴で確認する。再開時に`git status -sb`と`git log -3 --oneline`で確認する。
- P00・S01・P01〜P05、P06全29語（a5・b9・c15）は完了。P05・P06レビューも完了。
- P06cは一括承認の15語を実装し、通常/最小テスト、74実測比較・PTY6件・既存入力回帰が通過。P06レビューでSTDOUT描画判定とパイプのカーソル追跡を修正。次は457（P07先行4語）。
- tque階層は121 → 415 → 542。569・549・レビュー697は完了、542は未完了。既存の明示出力経路の描画判定は698で別管理。進捗はauto。
- P06の仕様・意図した差・検証結果は[P06実装記録](P06_IMPLEMENTATION.md)。SH-GETは次回呼出しまでの借用で、FREEしない。パイプはR/O・W/Oのみ、EPIPEは-544。

## 次の作業と進め方

1. [フェーズ表](GFORTH_WORD_PHASES.md)の457（IS・ACTION-OF・TO・+TOの辞書化）全4語の仕様調査を先行する。P07a570は457の後。P06cの再現は`scripts/probe-p06c.py`・`scripts/verify-p06c.py`、成果物は`.work/p06c-check/`。
2. 仕様上の選択肢を一度にまとめて質問し、承認後は承認待ちを挟まず連続実装する。実装中に新たな不明点が判明した場合だけ個別に確認する。
3. チャンク途中はコード・テスト・HELP・検証スクリプトだけを更新する。英日マニュアル、互換性一覧、フェーズ表、P0x記録、tqueはサブフェーズ完了時に一括更新する。
4. HANDOFFは現在状態・次の作業・制約だけを保ち、経緯や「最新」の追記を積み重ねない。今回の整理は利用者の明示依頼による。

## 制約

- コミット・タグ・pushは、その依頼で明示された場合だけ行う。通常の実装継続からは推定しない。
- **Windows/Linux実機確認はここでは行わない。** 607配下で別管理し、パイプ/SH-GETは695、P06cは696。freestandingビルド確認は実機実行ではない。
- 仕様不明点はコード変更前に確認する。比較用Gforth固有の不正アクセスや未定義動作は模倣しない。GPL実装コードを転用しない。
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
- [P05記録](P05_IMPLEMENTATION.md)・[レビュー](P05_REVIEW.md)、[P06記録](P06_IMPLEMENTATION.md)・[レビュー](P06_REVIEW.md)、[イメージ形式](IMAGE_FORMAT45.md)

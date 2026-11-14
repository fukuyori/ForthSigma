# ForthSigma 作業引き継ぎ

更新日：2026-11-14。現在状態はこの文書、実装経緯は各フェーズ記録とgit履歴を参照する。

## 現在状態

- mainのP08レビュー修正は`4348277`でコミット・push済み。P00・S01・P01〜P08と依頼済みの各レビューは完了。
- P09a15/15語（576）は実装・検証完了、tqueは完了(auto)。P09全体は15/50語。P09aと音楽examples3件・対応文書は今回のコミット対象へ反映済み。[実装記録](P09_IMPLEMENTATION.md)。
- 通常テスト1013件通過（6件skip）、最小構成576件通過（414件skip）、通常ビルド、P09a比較55件＋方針15件＋native2件、既存P08a/b検証が通過。例外記録の保存・追加再配置、コード衝突の変更前拒否を確認した。
- tque階層121 → 415 → 542。既存の明示出力経路の描画判定は698で別管理。進捗はauto。
- 利用者の追加指示により、音楽examples3件と対応するCHANGELOG・GRAPHICS_AND_SOUND英日もP09aと合わせてコミットする。再開時はgit statusと履歴を確認する。

## 次の作業と進め方

1. 次は577（P09b、スタックとソース位置の表示30語）。冒頭で全語をGforth実測し、推奨方針で継続する。P09aには新規組込み語と例外記録種別によるABI変更があり、旧イメージは再作成する。
2. チャンク途中はコード・テスト・HELP・検証スクリプトだけを更新する。英日マニュアル、互換性一覧、フェーズ表、P0x記録、tqueはサブフェーズ完了時に一括更新する。
3. HANDOFFは現在状態・次の作業・制約だけを保ち、経緯はフェーズ記録とgit履歴へ任せる。

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

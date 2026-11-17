# FORTH/Σ for Zig

英語版（正）: [README.md](README.md)。この日本語版は英語版の訳です。内容が異なる場合は英語版に従ってください。

プロジェクト概要、ビルド方法、現状の機能、Forth標準との違い、出典とライセンスは[リポジトリのREADME](../README.ja.md)を参照してください。

- [FORTH/Σ仕様書](SPEC.ja.md): 雑誌資料から整理した仕様と出典箇所
- [ユーザーマニュアル](USER_MANUAL.ja.md): 起動方法、基本操作、現在の登録語一覧
- [全ワードリファレンス](WORD_REFERENCE.ja.md): 現在の全語・構文・標準キー・内部補助語のスタック効果、日本語説明、使用例、注意点。[読み方と確認済み使用例](WORD_REFERENCE_GUIDE.ja.md)
- [デバッグの手引き](DEBUGGING.ja.md): プログラムの悪いところを調べる方法。コマンドラインとエージェントから使う（バックトレース、トレース、ステップ実行、メモリの監視、プロファイル、カバレッジ、lint、フォーマッター、JSON Lines のログ）
- [グラフィックスとサウンドのマニュアル](GRAPHICS_AND_SOUND.ja.md): グラフィックスの語（描画、文字、Tcl/Tk、キー、マウス、アニメーション）とサウンドの語（MSX BASIC の PLAY、音源、録音した音、モジュール）
- [グラフィックモード](GRAPHICS_MODES.ja.md): `SHOW` の表示先（端末、Sixel、ウィンドウ、Tkのウィンドウ）、色数、表示の大きさ
- [サウンドの調査](SOUND_RESEARCH.md): MSX、Atari ST、C64、NES、Amiga の音源、MSX BASIC の音の語、各システムの音の出力と、その出典
- [ネイティブウィンドウの検討（Windows・macOS・Linux）](NATIVE_WINDOW_STUDY.md): `SHOW` の共通条件の案と、macOS・Linux の表示方式・依存・検証条件（検討段階）
- [実装ノート](IMPLEMENTATION.md): Zig移植版の構成、実装判断、未実装機能
- [Forth 2012の語の状況](forth2012-word-status.tsv): Forth 2012規格の語の一覧の各項目と、全機能ビルドでの有無（2026-11-17確認。要約はトップのREADME）
- [サイズ測定・速度比較](SIZE_SPEED_MEASUREMENT.md): 2026-11-17のWindows/Linux実行体サイズとWSLでのGforth 1.0.2比較、生データと再実行手順
- [本体側のTUI・非同期実行基盤の対応方法](ASYNC_CORE_PLAN.md): 本体に実装する7項目について、SigmaとGforthの現状と、項目ごとの対応方法と、2026-11-17の決定事項（実装未着手）
- [VM実行速度の改善計画](VM_PERFORMANCE_PLAN.md): CATCHの安全性を維持して通常実行の負担を減らす実験案。改善実装は未実施
- [VM改善計画のレビュー結果](VM_PERFORMANCE_REVIEW.md): Claude CodeとAntigravity（agy）のレビュー、指摘の採否と具体的な判定基準
- [GforthのVM実装参照](GFORTH_VM_REFERENCE.md): 固定版ソースから参照する設計原理と、Sigmaへ移植しない方式の区別
- [ワード互換性一覧](COMPATIBILITY.ja.md): 誌面掲載ワードと現在の実装状況
- [Gforth未対応ワードの実装フェーズ](GFORTH_WORD_PHASES.md): Forth 2012の標準語を優先する、重要度A〜Cの380語と既存4語の辞書化の実装順序、完了条件、tqueタスクとの対応
- [P00の仕様と比較ケース](GFORTH_P00_SPEC.md): 利用者が確定した互換方針、保存時の再配置設計、Gforthによる実測と再実行方法
- [決定事項・保留事項](DECISIONS.md): 原資料の仕様と移植判断の区分
- [メモリとグラフィックスの計画](MEMORY_AND_GRAPHICS_PLAN.md): メモリの上限を起動時とビルド時に指定する計画と、MSX、NES、Amiga を手本にした GUI、スプライト、画像の語の計画
- [開発の記録](DEVELOPMENT_SCHEDULE.md): 作業の経緯
- [バージョン更新チェックリスト](version-update-checklist.md): 版番号を変えるときに直すものと、リリースの手順

- [S01レビュー・検証記録](S01_REVIEW.md)：Claude Codeの指摘対応と比較実測。

- [P01レビュー・検証記録](P01_REVIEW.md)：Claude Codeの指摘対応とリターンスタック差異の実測。

- [非同期・TUI実行基盤とエディタ拡張の企画](ASYNC_OVERVIEW.md): 非同期案の検討3点、エディタ向け16項目のAPI・要件・段階案と、本体・アプリ側の区分。tque 613配下は本体側の7件と共通の取り決めの1件、仕様未確定。

- [P02数値演算・数値入出力の実装記録](P02_IMPLEMENTATION.md)：境界仕様、Gforthとの差、検証手順。

- [P02レビュー・検証記録](P02_REVIEW.md)：Claude Codeの指摘対応と追加比較・回帰。

- [P03メモリー操作の実装記録](P03_IMPLEMENTATION.md)：P03aの幅・整列・エンディアンと検証。再配置・ヒープの段階は未着手。

- [SIGIMG45/46/47 image format](IMAGE_FORMAT45.md)

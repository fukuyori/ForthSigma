# FORTH/Σ for Zig

英語版（正）: [README.md](README.md)。この日本語版は英語版の訳です。内容が異なる場合は英語版に従ってください。
- [638 イベントキューの詳細設計](EVENT_QUEUE_DESIGN.md): 期限付きEKEY、途中入力、マウス付随情報、貼付け、入力切替と復元。
- [637 端末制御の詳細設計](TERMINAL_CONTROL_DESIGN.md): 表示要求、入力境界、復元、Windows/Linux/Macの確認範囲。

プロジェクト概要、ビルド方法、現状の機能、Forth標準との違い、出典とライセンスは[リポジトリのREADME](../README.ja.md)を参照してください。

- [FORTH/Σ仕様書](SPEC.ja.md): 雑誌資料から整理した仕様と出典箇所
- [ユーザーマニュアル](USER_MANUAL.ja.md): 起動方法、言語と基本操作、拡張機能への入口、登録語一覧
- [全ワードリファレンス](WORD_REFERENCE.ja.md): 現在の全語・構文・標準キー・内部補助語のスタック効果、日本語説明、使用例、注意点。[読み方と確認済み使用例](WORD_REFERENCE_GUIDE.ja.md)
- [デバッグの手引き](DEBUGGING.ja.md): プログラムの悪いところを調べる方法。コマンドラインとエージェントから使う（バックトレース、トレース、ステップ実行、メモリの監視、プロファイル、カバレッジ、lint、フォーマッター、JSON Lines のログ）
- [グラフィックスとサウンドのマニュアル](GRAPHICS_AND_SOUND.ja.md): グラフィックスの語（描画、文字、Tcl/Tk、キー、マウス、アニメーション）とサウンドの語（MSX BASIC の PLAY、標準の音と音色、機種のライブラリ、録音した音、モジュール、PCMストリーム）
- [拡張機能の手引き](EXTENSION.ja.md): 端末、イベント、非ブロッキング I/O、子プロセス、ファイルシステム、実行制限、タスク、複合待機、保存アプリの使い方
- [グラフィックモード](GRAPHICS_MODES.ja.md): `SHOW` の表示先（端末、Sixel、ウィンドウ、Tkのウィンドウ）、色数、表示の大きさ
- [サウンドの調査](SOUND_RESEARCH.md): MSX、Atari ST、C64、NES、Amiga の音源、MSX BASIC の音の語、各システムの音の出力と、その出典
- [ネイティブウィンドウの検討（Windows・macOS・Linux）](NATIVE_WINDOW_STUDY.md): `SHOW` の共通条件の案と、macOS・Linux の表示方式・依存・検証条件（検討段階）
- [Linuxの物理抜き差し確認](LINUX_DISPLAY_HOTPLUG_VALIDATION.md): ケーブル操作の手順、DRM/X11の証跡、記録機構の検査、物理確認の残件（tque 1336・1345）。
- [LOGOのタートルグラフィックスの検討](LOGO_TURTLE_STUDY.md): 外部ForthアプリとしてLOGOのプログラムを解釈してタートルグラフィックスを描く方式、決める項目、問題点（検討段階）
- [実装ノート](IMPLEMENTATION.md): Zig移植版の構成、実装判断、未実装機能
- [Forth 2012の語の状況](forth2012-word-status.tsv): Forth 2012規格の語の一覧の各項目と、全機能ビルドでの有無（2026-11-17確認。要約はトップのREADME）
- [サイズ測定・速度比較](SIZE_SPEED_MEASUREMENT.md): 2026-11-20のWindows/Linux構成別サイズ・変更前後のCPU時間とWSLでのGforth 1.0.2比較、生データと再実行手順
- [本体の機能拡張の全体](CORE_EXTENSION_PLAN.md): 共通基盤・OS判別、TUI・非同期、音と描画、ゲーム表示、タスク制御の範囲、依存関係、段階0〜Eの工程（tque 613、共通基盤・637のMac実機まで完了、638はWindows/Linux受け入れ済み・Mac実機待ち）。[実装・検証記録](CORE_EXTENSION_IMPLEMENTATION.md)
- [Unicode書記素の設計](GRAPHEME_DESIGN.md)と[実装・検証記録](GRAPHEME_IMPLEMENTATION.md): Unicode 18.0.0の境界、検査範囲と計算量、試験とMac実機の残作業
- [ファイルシステム設計](FILESYSTEM_DESIGN.md)と[実装・検証記録](FILESYSTEM_IMPLEMENTATION.md): パス補助・metadata・同期、レビュー採否とMac実機の残作業
- [本体機能拡張の引継ぎ（2026-11-19）](CORE_EXTENSION_HANDOFF_2026-11-19.md): 現在の本体拡張、Git・tque・検証結果
- [語群基盤とOS判別の設計](EXTENSION_GROUP_DESIGN.md): extensionの選択・読込み、HOST-OS、除外構成・イメージの契約（1056・1036）
- [保存アプリの起動基盤](SAVED_APPLICATION_STARTUP_PLAN.md): SAVESYS実行体の自動起動・引数・終了・保存整合の計画（1003配下1066）。LOGO本体は外部Forthアプリ
- [本体の機能拡張の詳細設計](CORE_EXTENSION_DETAILED_DESIGN.md): 本体コア・グラフィックス・サウンド・拡張への配置、API候補、内部構造、所有権、失敗・取消し・復元、検証条件。[判断記録](CORE_EXTENSION_DESIGN_DECISIONS.md)、[State隔離監査表](CORE_EXTENSION_WORKER_STATE_AUDIT.md)
- [詳細設計レビューへの対応](CORE_EXTENSION_REVIEW_RESPONSE.md): Claude Codeの[初稿レビュー](CORE_EXTENSION_CLAUDE_REVIEW.md)と[再確認](CORE_EXTENSION_CLAUDE_FOLLOWUP.md)への対応、残る採用判断。[依頼文](CORE_EXTENSION_REVIEW_REQUEST.md)
- [システムのタスク制御の補完計画](TASK_CONTROL_PLAN.md): 実行方式、状態と結果、複合待機、取消し・回収、VM分離、通常ビルドでの利用（tque 1048、方式未確定・実装未着手）
- [1048 タスク制御の詳細計画](TASK_CONTROL_DETAILED_PLAN.md): 現実装の照合、方式比較と試作ゲート、子タスクの成果物、隔離・取消し・複合待機、検証・測定、採用前の判断事項（設計案）
- [本体の機能拡張：共通の取り決め](ASYNC_COMMON_RULES.md): 段階0（tque 900）の契約案と内部最小基盤の実装範囲。時計、待機・期限・中断、キュー、実行制御、資源、辞書イメージ、語群。具体的な未決事項は実装時に確認する
- [TUI・非同期実行基盤の対応方法](ASYNC_CORE_PLAN.md): 拡張モジュールの7項目（tque 1002）について、SigmaとGforthの現状、項目ごとの対応方法、2026-11-17の決定事項
- [レトロPCエミュレータ向け拡張の対応方法](EMULATOR_CORE_PLAN.md): サウンドとグラフィックスに足す5項目（tque 1003）について、現状、対応方法、Codexのレビューの反映、2026-11-18の決定事項
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

- [非同期・TUI実行基盤とエディタ拡張の企画](ASYNC_OVERVIEW.md): 非同期案の検討3点、エディタ向け16項目のAPI・要件・段階案と、本体・アプリ側の区分。tque 613配下の1002は本体側の7件、共通の取り決め（900）は1055配下。内部基盤を実装し、後続機能の仕様は各担当項目で確定。

- [P02数値演算・数値入出力の実装記録](P02_IMPLEMENTATION.md)：境界仕様、Gforthとの差、検証手順。

- [P02レビュー・検証記録](P02_REVIEW.md)：Claude Codeの指摘対応と追加比較・回帰。

- [P03メモリー操作の実装記録](P03_IMPLEMENTATION.md)：P03aの幅・整列・エンディアンと検証。再配置・ヒープの段階は未着手。

- [SIGIMG45/46/47 image format](IMAGE_FORMAT45.md)

- [保存アプリ起動基盤：実装・検証結果とMac手順](SAVED_APPLICATION_STARTUP_IMPLEMENTATION.md)

- [PCMストリーム：採用設計・内部リングと変換の検証](PCM_STREAM_IMPLEMENTATION.md)

- [音声ホストの停止・回収と初期化失敗の検証](PCM_HOST_LIFETIME_IMPLEMENTATION.md)

- [PCM公開語の実装と検証](PCM_PUBLIC_IMPLEMENTATION.md)：所有・待機・画像境界、Windows/Linux自動確認とMacの残件。

- [Forth音源の試作](PCM_SYNTH_PROTOTYPE.md)：独自の4声合成、PCM送出、Windows/Linux測定と限界。

- [NES APUのForth試作](NES_APU_FORTH.md)：NTSC 4声のレジスタ、時刻指定書込み、基準版とまとめ処理版の照合・測定範囲。

- [NES DMCのForthモデル](NES_DMC_FORTH.md)：5声のreader/DAC/IRQ、専用メモリと負荷測定。

- [C64 SIDのForthモデル](SID_FORTH.md)：3声の決定的モデル、整数フィルター近似、独立検証と再現範囲。

- [PaulaのForthレジスタモデル](PAULA_FORTH.md)：4声ステレオのDMA/手動出力/IRQ/変調モデル、独立検証とMac受け入れの残項目。

- [YM2149/STのForthモデルと監査](YM2149_FORTH.md)：既存nativeの不足・固定0音量の修正、時刻指定・仮想port/bus、独立PCM検証と測定。

- [8対象の音源経路と不足の監査](AUDIO_TARGET_AUDIT.md)：ソースと資料による不足・モデルの境界、機種別/OS別の後続タスク。最終採否は別工程。

- [SNES S-DSP音源](SNES_DSP_AUDIO_FORTH.md): 8声/BRR/envelope/noise/PMON/echoFIRの宣言モデル、独立検証と制限。
- [ZX Spectrum 48K/128K音源](ZX_SPECTRUM_AUDIO_FORTH.md): Forthのbeeper/AY、独立port/PCM検証と宣言範囲。
- [Apple II／II+のスピーカーとMockingboardの音源](APPLE2_AUDIO_FORTH.md): Forthのスピーカー切替えと6522経由のAY-3-8910 2個、独立したバス/PCM検証と宣言範囲。
- [CHIP-8とXO-CHIPのForth音源](CHIP8_AUDIO_FORTH.md)：60Hz timer、移植用ブザー、128bitコピーと整数pitch/phaseモデル。CPUとOS別受け入れは別工程。

- [S-DSP native frame kernel](SNES_DSP_NATIVE_DESIGN.md): 測定不足を受けた同期・借用buffer処理の設計とレビュー判断。

## 計算タスク

G1の経路探索、T1の検索、I1の順序付きチェックサムは、
[利用例](../examples/TASK_EXAMPLES.ja.md)と[1380結合試験報告書](TASK_CONTROL_IMPL_1380.md)を参照する。

EXTENSIONのタスク語はメイン専用である。次は入力をそのまま結果として返し、`abc`を表示する最小例である。

```forth
REQUIRE-EXTENSION ALSO EXTENSION
: TC-ECHO ;  \ ( input-addr input-u -- result-addr result-u )
CREATE TC-OUT 32 ALLOT
TASK-SNAPSHOT THROW CONSTANT TC-SNAP
TC-SNAP S" TC-ECHO" S" abc" TASK-I1 0 TASK-SUBMIT THROW CONSTANT TC-JOB
TC-JOB -1 TASK-WAIT THROW 2DROP
TC-JOB TC-OUT 32 TASK-RESULT THROW DROP
TC-OUT SWAP TYPE CR
TC-JOB TASK-RELEASE THROW
TC-SNAP TASK-SNAPSHOT-RELEASE THROW
```

SnapshotとタスクのIDを別々に解放する。入力・結果はコピーし、結果取得は非消費である。取消し要求と取消し終端は異なり、WAITの期限はタスクを取り消さない。REPLエラー・ABORT・QUITはタスクを終了せず、BYE・所有者終了で回収する。workerは1、台帳16件、Snapshotは生存3版である。workerで使える語は各語のworker欄と入口検査で制限する。extension=falseで公開語を除外し、files=falseではI/O待機、graphics=falseでは描画待機を拒否する。描画kind=5はid=0をホスト自身のネイティブ窓とする。他のidはTASK-E-HANDLE（-300）、arg0はGFX-WINDOW-FRAMESのshown（1セル）、arg1は0に限り、非0はTHROW -24である。不正・未投入・旧窓の目標はHANDLE、Tk・AUTOがTkを選んだ経路・窓なし・graphics=falseはNO-CAPABILITY（-311）である。登録後のcloseはRELEASED、backend描画完了はPAINTEDであり、物理提示の保証ではない。窓の寿命世代と目標は固定する。複数表示先への拡張はid、将来の2セル目標用にはarg1を残す。

[公開API・数値・上限](TASK_CONTROL_PUBLIC_API_PROPOSAL.md)、[利用条件](TASK_CONTROL_USAGE_CONDITIONS.md)、[実装と検証状況](TASK_CONTROL_IMPL_1379.md)。

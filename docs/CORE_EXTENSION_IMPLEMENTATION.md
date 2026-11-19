# 613 実装・検証の記録

## 2026-11-19：637 ターミナル制御（1070〜1073）

基点は`b4af2fb Record Mac acceptance for core extension`。本節の実装・設計・レビュー記録は、この文書と同じコミットに含む。tqueの1070〜1072は完了、637はauto75%。Mac実機1073は未実施。

EXTENSIONへTERM-MODE!/@、COLS/ROWSと4定数を追加した。表示要求はホストのManagerでraw入力と独立して所有する。KEY/ACCEPTではalt/cursorを保ち、REPLとSYSTEMで退避、未捕捉診断と通常終了で解除する。Windowsのpaste要求を除外する。coreは語の処理・FORM共用・入力エラー伝達、ホストはOS操作と資源の後始末を担当する。[詳細設計](TERMINAL_CONTROL_DESIGN.md)。

Claude Codeへ設計・実装・Windows入力再開・最終の読み取り専用レビューを依頼し、指摘を評価して反映した。レビュー原文・こちらの採否・仕様を別資料に保存した。[反映判断](reviews/637-review-response.md)。Windowsのcooked readをキャンセルした後、次の一行が失われるケースを実際に確認し、専用CONIN$ハンドルを中断後に閉じる修正で解消した。追加レビューで指摘された読み取り完了とCtrl+Cハンドラーの順序、POSIXのread直前の信号、dirty状態からの明示解除も補強した。

| 確認 | 結果と証拠 |
|---|---|
| Windows `zig build test --summary all` | 23/23ステップ成功。host 95成功・10スキップ。core 1031成功・8スキップ、runtime 15成功は直前の成功済みキャッシュを含む。Cortex-M0+のfreestandingチェックも成功。`.work/637-review/final3-tests.log` |
| Windows 通常実行体 | debug実行体のビルド10/10成功。`.work/637-windows/bin/sigma.exe`、`.work/637-review/final3-native-build.log` |
| Windows新規独立コンソール | 8ケース成功。raw前の表示、paste除外、mouse、解除、不正mask、SYSTEM、CATCH、外部生成Ctrl+C後のFILE-EOF?=0と次のKEY。`.work/terminal-modes/windows/result.json` |
| Windows ConPTY | Ctrl+Cバイト→CATCH=-28→次のKEYでQ=81を10回連続成功。最後のEOF修正後もFILE-EOF?=0と次のKEYを再確認。`.work/terminal-modes/windows/conpty.json`は最後の1回。物理キー操作とは区別 |
| Windows既存コンソール | 入力レコード注入36ケース成功。`.work/windows-console.json` |
| Linux向けコンパイル・実行 | musl向けcore/host/runtimeを16/16ステップで作成しWSLで実行。core 1031成功・8スキップ、host 106成功・5スキップ、runtime 15成功。`.work/637-review/final3-linux-build.log`、`final3-linux-execution.log` |
| Linux PTY | 13ケース成功。KEY/ACCEPTの表示維持・SIGINT、REPL打掛けBYEの実行抑止、SYSTEM、例外、profile、リダイレクト、termios/画面復元。`.work/terminal-modes/posix.json` |
| Linux NS既存回帰 | sigma-only pass=true。期限8・範囲1・リダイレクト2・信号復帰2・PTY5ケース。`.work/p05b-ns-check/sigma-only.json` |
| Mac向けコンパイル | aarch64-macos、audio/graphics/float除外のcore/host/runtimeで14/14ステップ成功。`.work/637-review/final3-macos-build.log`。Mac実行の証拠ではない |
| 英日HELP・全語参照 | 1544項目、HELP1330、実辞書に欠落なし、例28件と個別例144件成功。check-docs findings=0。`.work/637-review/final3-word-reference.log`、`final3-check-docs.log` |
| 3語群・機能除外 | 最終コードの12/12構成でtestと実行体ビルド成功。extension除外版でのイメージ拒否と既存辞書の保持も成功。matrix.jsonのsource_sha256が現在のbuild.zig/srcと一致。`.work/637-review/final3-extension-matrix.log`、`.work/extension-matrix/matrix.json` |

実OS APIの失敗を任意に注入した受け入れ、物理キーボード操作、Mac実行は未確認。Managerの差替えBackendでは部分失敗・巻戻し・dirty保持・入れ子・明示解除を確認した。入力/待機スコープ外の既定SIGINTやCtrl+Break、SIGTERM/SIGHUP・強制終了時の完全復元は保証しない。通常VMループへ信号処理を追加する変更は含めていない。

次工程は638イベントキュー。637のMac実機確認は1073として残し、1057の最終統合受け入れで待つ。保存アプリ起動の1067は計画済み・未実装であり、LOGO機能のSigma組込みは行っていない。


## 2026-11-19：1065 Mac実機受け入れ

対象コミット：`b7411f68d9430d495906d30fefc4e14efb399213`。環境はmacOS 27.2（Darwin 27.2.0、arm64）、Zig 0.17.1、Python 3。作業ツリーは開始時にクリーン。クロスコンパイルではなく、このMacで同一コードをビルド・実行した。

| 確認 | 結果 |
|---|---|
| `zig build runtime-test --summary all` | 15/15成功 |
| `zig build test --summary all` | 23/23ステップ成功。core 1027成功・8スキップ、host 88成功・6スキップ、runtimeは15/15成功済みキャッシュ。合計1115成功・14スキップ。スキップはOS専用・明示opt-in・利用可能な表示/外部ライブラリなどを条件とする試験で、ビルド失敗ではない |
| `zig build --prefix .work/runtime-native --summary all` | 10/10ステップ成功。検証用実行体を作成 |
| `verify-p05b-ns.py --sigma-only` | pass=true、sigmaのみ、比較なし。期限8件、範囲1件、リダイレクト2件、信号復帰2件、PTYのcanonical/raw・制御文字・端末復元5ケースが成功 |
| `REQUIRE-EXTENSION ALSO EXTENSION HOST-OS TYPE PREVIOUS` | 実出力`macos` |
| `verify-extension-matrix.py` | 12/12構成成功（audio/graphics/extensionの8通りとfiles/debug等の4構成）。extensionイメージを除外ビルドで拒否し、既存辞書が保たれることも確認。結果は`.work/extension-matrix/matrix.json` |

試験はNS/PTYと記載した語群・共通基盤の契約を確認した。物理キーボード操作、実OS APIの失敗注入、強制終了時の完全回収は確認範囲外。1065の手順に記載した除外構成はマトリクスの`001-no-files-no-debug-no-float-no-image-no-x11`で実行し、`zig build test -Dgraphics=false -Daudio=false -Ddebug=false --summary all`と同等以上に語群を限定した構成を通した。

### 1055レビュー

計画・詳細設計・既存の1056/900レビュー対応記録と、今回の主な実装経路（語群読込み、イメージ機能検査、HOST-OS、Runtime/Wake/信号Broker）を照合した。確認範囲で新たな重大・高の問題は見つからず、1055の通常・機能除外の縦通し条件はWindows/Linuxの記録と今回のMac確認で満たしている。将来の子プロセス生成より前にmacOSのpipe＋fcntl初期化を済ませる条件、参加者のjoin後にRuntimeを解放する条件、実OS APIの復元失敗を注入した試験が未実施である境界は維持する。613全体や将来機能のレビューではない。

## 2026-11-19：1056 語群基盤・1036 OS判別（1065実施前の記録）

利用者の「mac部分は残して、次に進めて」により、Mac実機1065と900の未完了を維持して次の実装を進めた。1056と1036は実装・最終回帰を完了し、tqueも完了へ更新した。1055はauto97%、900はauto91%、1063はauto50%。Mac実機1065は未完了のまま維持する。

### 実装と採用判断

- `-Dextension`を既定trueで追加した。audio/graphicsとは独立し、内部Runtime・時計・Wakeはextension除外でも利用する。
- `REQUIRE-EXTENSION`がEXTENSION語彙とHOST-OSを初回だけ登録する。既存のlibrary_loadingを再利用し、CURRENT・検索順・BASE・一度だけの定義名を維持する。失敗した辞書追加を戻して再試行でき、FORGET/MARKER後も再読込みできる。
- `HOST-OS ( -- c-addr u )`は実行体の対象OS系列をwindows / linux（WSL/Androidを含む）/ macos / unknownで返す。数値案から文字列へ具体化した。呼ぶたびに専用論理領域へコピーし、保存された別OSの文字列を使い続けない。結果は次の呼出しかイメージ復元までの書換え禁止の借用文字列。
- extensionを除くと、読込みのparser分岐・語彙・HELPを除き、通常のUnknownWord（-13）となる。有効時は既存REQUIRE-AUDIOと同じ解釈時入口であり、`[DEFINED]`では検出できない。
- 語群の一覧をlibrary_groupsへ共通化し、State追加とバイト列追加の両方で読込み済み認識を更新する。追加後の再読込みで語数が増えないことを確認した。
- 新しいBuiltinでABI署名を更新するが、新magicは作らない。wire codecは構造検査を維持し、復元・追加のpreflightで除外した追加builtin語と直接builtin Opを共通検査する。これは従来読めたaudio/graphicsイメージを一部拒否する変更。予約した基本辞書欄への通常呼出しは従来どおり読込み可能で、実行時に-261。生xtデータに対する実行時の防御も維持する。
- Stateに追加したextension_libraryをワーカー隔離の監査表へ追記し、直下168項目をソースと照合、1053のタスク名も更新した。再帰監査の完了ではない。
- HELP、英日README・互換性一覧・全語リファレンスへ反映した。将来の公開時計API、タスク実行方式、各機能固有のfiles/debug条件の実装完了を意味しない。

[採用設計](EXTENSION_GROUP_DESIGN.md)、[判断記録](CORE_EXTENSION_DESIGN_DECISIONS.md)。HOST-OSはSigma独自語として扱い、外部Gforthの同名語との照合は行っていない。

### Claude Codeレビュー

実装を続けながら3回、Read/Glob/Grepだけの読み取り専用レビューを依頼した。[依頼文](reviews/1056-requests.md)、[設計原文](reviews/1056-design.md)、[実装原文](reviews/1056-implementation.md)、[修正の追加確認原文](reviews/1056-followup.md)、[評価・対応](reviews/1056-response.md)を分離して保存した。

追加確認では、読んだ範囲に新たな高・中の問題は見つからず、既存試験の期待値・範囲検査・HELP・領域境界の修正が確認された。実行試験と文書全体を承認した評価ではない。追加の低い指摘には、不変性の確認項目、既定構成での明示skip、HELPの未知値、機能検査の適用例を補強し、回帰試験を行った。

### 検証

Windows PowerShell、Zig 0.17.1。性能比較・リリース用パッケージ・実Mac実行は行っていない。

| 対象 | 結果 |
|---|---|
| Windows通常構成の最終全体試験 | 23/23ステップ成功。core1027成功・8スキップ、host87成功・10スキップ、runtimeは先行成功のキャッシュ。Cortex-M0+も成功 |
| Windows 3語群の8通り＋代表4構成 | 低い指摘の追加補強後も12構成すべて成功し、異なるextension構成間のイメージ拒否も確認した。files単独除外、debug単独除外、3語群有効でfiles/debug除外、extensionのみ有効でfiles/debug/float/image/x11除外。各構成で全体試験・実行体・語の登録を確認 |
| Windows結合試験 | 通常とextension除外それぞれ38件成功。既存graphics/audioのイメージ保存・追加・単独実行も含む |
| WSL/Linux通常の最終core/host/runtime | core1027成功・8スキップ、host98成功・5スキップ、runtime15/15成功。三つとも対象OSで実行した |
| WSL/Linux実行体 | HOST-OSの実出力がlinuxであることを確認 |
| WSL/Linux extension除外 | core1023成功・12スキップ、host98成功・5スキップ、runtime15/15成功、結合試験38件も成功。古い「失敗ログから試験実行体2個を推定」する処理をやめ、core-check/host-check/runtime-checkで明示配置して実行するよう個別除外スクリプトを修正した |
| aarch64-macos | graphics/audio/floatを除きextensionを含むcore/host/runtime、14/14ステップでコンパイル成功。Macでの実行は未確認 |
| 全語リファレンス | 実辞書との照合で1536項目、HELP1322項目、文書例28件、独立例136件が成功。選択器の5試験・動作回帰19件も成功 |

構成試験は`tests/scripts/verify-extension-matrix.py`。ログとJSONは`.work/extension-matrix/`、レビューと個別検証ログは`.work/1056-review/`に置く。JSONのsource_sha256は実行開始時の参照値であり、Gitコミットの識別子ではない。途中の最終整形ではlibrary_loadingのコメントだけを整形し、動作は変更していない。

### tqueと残作業

1056の先行条件を900全体から完了済み1064へ変更した。後続実装も共通基盤の実装確認には1064を待つよう整理し、900の契約担当とMac実機受け入れは維持した。1057は1055を通して未完了の900も待つため、最終受け入れからMac確認は抜けない。

1065には共通基盤のMac実行に加え、HOST-OSのmacos出力と語群構成の実行確認を残す。[Mac実機手順](CORE_EXTENSION_MAC_ACCEPTANCE.md)を更新済み。900はauto91%のまま未完了。今回の実装は未コミット・未プッシュ。


## 2026-11-19：1061・1062のホスト統合とレビュー反映

現在の状態：1061（ホスト文脈）・1062（信号所有の接続）・1064（自動受け入れ）は完了。1063は50%、900はautoで91%。残りの1065はMac実機確認。工数や所要時間の91%を意味しない。当初1056・1036は900完了待ちとしていたが、下記の利用者指示で1056の先行条件を変更した。

### 実装と境界

- `src/host_runtime.zig`のRuntimeが時計・Wake・取消し・信号Brokerを所有する。ownerと台帳incarnationのepochをプロセス内で再利用しない共通採番器から発行する。終了状態はatomicとし、通知側が動く間にshutdownを要求できる。deinit前の全参加者の停止・joinは必須。
- OwnedTableは`initTable(out)`で安定したアドレスへ束縛し、コピー・移動による操作を拒否する。生きた台帳や信号スコープがあればRuntimeの解放を拒否する。getのポインターはremove/deinitまでの借用。起動をまたぐepochの一意性やForthセルへの符号化はまだ提供しない。
- 実行体のHostContextからNS・音の待機をRuntimeへ接続した。fallbackの利用者も同じプロセスの信号所有ゲートを使い、互いにハンドラーを上書きしない。メタデータと端末の操作は一つのホストスレッドから行う。
- 復元失敗のNativeScopeはプロセス所有の領域へ、TicketはBrokerへ保持し、次の待機と終了時に再試行する。部分復元は項目ごとに記録し、復元済みのハンドラーを二度解除しない。部分beginの巻戻し失敗も所有を維持する。
- 端末のenter/leave/setMouse前に保留した復元を試す。enterは失敗時に一時的なNS設定を基準として取り込まない。別の正式なモード変更で古くなった端末スナップショットは捨て、ハンドラーの復元は続ける。終了時はleaveより先に復元を試みる。
- 復元不能等の最終終了経路でも、出力flush・UTF-8コンソール設定・resizeの後始末を明示的に試みる。生存が必要なRuntimeやVM Storageを解放して処理を進めない。
- 音待機のホスト障害を`AudioWait.host_failed`から既存の-265へ伝える。waitTakenで即時失敗を300回繰り返したり、resetの消費を成功扱いにしたりしない。
- POSIXの通知はpendingで集約し、解除もacq_relのRMWにした。書込み失敗後の再通知と満杯のEAGAINを試験した。書込み側から先にcloseする。プロセス全体のSIGPIPE方針は変更していない。

### Claude Codeレビュー

実装を続けながら固定コピーを読み取り専用で4回レビューした。[依頼文](reviews/900-runtime-requests.md)、[初回](reviews/900-runtime-initial.md)、[統合版](reviews/900-runtime-integration.md)、[復元処理の再確認](reviews/900-runtime-followup.md)、[端末復元の追加確認](reviews/900-runtime-terminal.md)、[対応記録](reviews/900-runtime-response.md)を分けて残す。

最後の端末復元の追加確認では、読んだ範囲で重大・高・中の未解決欠陥は見つからなかったとの評価。実OSの障害注入・Mac実機・全動作の承認ではない。追加の低い指摘のうち、端末を壊しかねない試験を、OSへ設定を渡さず無効化状態を直接調べる試験へ修正した。POSIXでSIGINTハンドラーの復元自体が失敗し保留されている間、待機外のSIGINTが既定動作へ戻らない制約は残る。OS障害下の配送方針・実際の復元失敗の注入は未検証として扱う。

### 最終の検証結果

Windows、PowerShell、Zig 0.17.1。通常のVMループの速度計測は行っていない。試験の待機時間・期限確認は機能検証であり、性能比較ではない。

| 対象 | 結果 |
|---|---|
| Windows `zig build test --summary all` | 23/23ステップ成功。最終回のhostは87成功・10スキップ、runtimeは14成功・1スキップ。coreは同じコードの1020成功・5スキップのキャッシュを利用。Cortex-M0+と実パイプの確認も成功 |
| Windows graphics/audio/debug除外の全体試験 | 22/22ステップ成功。hostは86成功・9スキップ。core/runtimeは先行した同じコードの成功キャッシュを利用 |
| Windows検証用実行体＋`verify-windows-console.py` | 隠した独立コンソールへの入力レコード・実制御イベントを使う36ケースが成功。NSのraw/canonical入力保持、SIGINT後の再待機を含む。物理キーボード操作の確認とは別 |
| WSL/Linux runtime | 15/15成功。満杯・書込み失敗・継承フラグ・並行通知を含む |
| WSL/Linux host | 98成功・5スキップ（103件）。NSの実ハンドラー復元、時計故障、保存した復元の再試行、古いモードの無効化を含む。スキップは未対応OS・明示的なデスクトップ等の条件による |
| WSL/Linux実行体＋NS sigma-only | 期間8・範囲1・リダイレクト2・信号からの復帰2・PTY5ケースが成功。Gforthとの比較ではない |
| aarch64-macos host/runtime | graphics/audio/floatを除いた構成でコンパイル成功。Mac実機での実行は未確認 |

`host-check`を追加し、ホスト試験の実行体を`<prefix>/host-tests/<arch>-<os>/test[.exe]`へ配置できるようにした。`runtime-check`と同じく、クロスコンパイルと対象OSでの実行を分けるための工程であり、配布パッケージは作らない。

### 残作業とtque

| tque | 状態 |
|---|---|
| 1058〜1062 | 完了。共通部品・ホスト文脈・信号所有の最小接続と試験 |
| 1063 | 完了。1064の自動受け入れと1065のMac実機受け入れを確認 |
| 1064 | 完了。1061・1062に依存し、Windows/Linuxの実行・macOSコンパイル・記録を確認 |
| 1065 | 完了。macOS 27.2 / arm64、Zig 0.17.1で実行。上記の1065記録を参照 |

2026-11-19、利用者の「mac部分は残して、次に進めて」により、当初は1065・1063・900を未完了のまま保ち、1056の依存を900から完了済み1064へ変更して1056→1036を先行した。その後1065のMac実機受け入れを実施し、1063・900・1055を完了にした。今回のコードは未コミット・未プッシュ。

## 2026-11-19：900 共通内部基盤の初回実装（履歴）

以下は最初の8件の試験とtque分割時点の記録。現在の状態は上のホスト統合の節を参照する。

状態：900に着手。最小部品の実装と下記の検証を実施。900は未完了、1056・1036は未着手。公開Forth語・辞書ABI・語群の構成は変更していない。

### tqueへの反映（2026-11-19）

900を以下の6子タスクへ分割し、確認済みの3件を完了にした。900は未完了を維持し、進捗はautoによる50%。作業件数による集計であり、工数や残り時間の見積りではない。

| tque | 作業 | 状態・直接依存 |
|---|---|---|
| 1058 | 期限・取消し・台帳・信号所有の最小部品と境界試験 | 完了 |
| 1059 | 単調時計の共通化とOS起床通知 | 完了。Windows/Linuxは実行、macOSはコンパイルまで |
| 1060 | 独立テスト・全体テスト・除外構成・クロスコンパイル・記録 | 完了。Mac実機確認は含めない |
| 1061 | ホスト文脈・epoch・寿命・差替え入口への統合 | 未完了。1058・1059に依存 |
| 1062 | 信号所有の仲介とNS・音待機の接続 | 未完了。1061に依存 |
| 1063 | 統合後のOS受け入れ・Mac実機・継承境界の確認 | 未完了。1060・1061・1062に依存 |

次の実装対象は1061。1063に643全体の完了待ちは設定せず、900との循環を避ける。900完了後に1056、その後1036へ進む既存の依存は維持する。

### 実装した範囲

| 対象 | 実装と境界 |
|---|---|
| `src/core/runtime_base.zig` | OSに依存しない期限・差替え時計の契約、stickyな取消し印、所有者・種類を検査する有界資源台帳、LIFOの信号所有スコープ |
| `src/host_clock.zig` | WindowsのQPC／POSIXのCLOCK_MONOTONICを共通の内部時計へ分離。既存NSから利用する |
| `src/host_wake.zig` | 一つの消費者と複数の通知側を想定。Windowsの自動リセットEvent、Linuxのnonblocking/CLOEXEC pipe2、macOSのpipe＋fcntl。世代を先に更新して起床し、単一期限で状態を再確認する |
| `src/runtime_test.zig`、`src/tests/runtime_base_test.zig` | 共通部品だけの独立した8件の試験。通常の`zig build test`にも組み込む |
| `src/freestanding_check.zig` | 期限計算・台帳・信号所有のメタデータ操作をCortex-M0+向けにコンパイルする確認を追加 |

NSの時計の式・精度・失敗時の結果は従来のまま。端末モード、既存の信号ハンドラー、他の内部時計、通常の実行ループは変更していない。内部InstantはNSが従来使うi128を保ち、公開単調時計語を1セルにする案の採用は638で別に確認する。

### 部品の契約と制約

- **期限**：相対msから一度だけ期限を計算。0は即時確認、負値は無期限。加算のあふれを拒否し、OSへ渡すmsへの切上げもあふれないようにする。
- **取消し**：一度要求したら解除しない。利用者が終了した後に新しいtokenを作る。取消しだけではOSオブジェクトを起こさないため、待機は最大20msずつ区切って確認する。応答時間の上限保証ではない。即時の起床が必要な接続側はnotifyも行う。
- **起床**：状態を更新してからnotifyする。消費者はobserve→状態の確認→waitの順を守る。世代が変われば期限前でも通知結果を返す。世代は折返しを拒否する。世代は通知の発行を示すだけで、可変payloadの排他制御は利用側が行う。
- **OS資源**：init後に共有したWakeを移動しない。すべての通知側・消費者を停止・joinしてからdeinitする。macOSのpipe＋fcntlはCLOEXEC設定が原子的でないため、初期化を並行した子プロセス作成より前に行う。643との接続時に生成・継承の直列化を検証する。
- **台帳**：容量とpayload型は利用側が指定する。所有スレッドのみが操作し、payloadのOS資源は台帳から除く前に利用側が停止・回収する。serialは再利用せず、枯渇をエラーにする。epochはホストが与える非0の台帳incarnationの識別値で、一意性を作る処理はまだ接続していない。同じepochで別の台帳を作らないことが利用側の前提。起動をまたぐ古いForthセルの拒否や公開セルへの符号化は未実装。
- **信号所有**：所有者と入れ子のLIFOを検査するメタデータ操作。既存のsigaction・mask・NSのactiveフラグの代替にはまだ接続しない。利用側の一つのホストスレッドがスコープを管理する。

### 実行した検証

環境：Windows、PowerShell、Zig 0.17.1。WSLから実行したものは別記。

| コマンド・対象 | 結果と範囲 |
|---|---|
| `zig build runtime-test --summary all` | Windowsで8/8成功。早着・集約通知、並行通知、古いOS通知、単一期限、時計故障、取消し、台帳と信号所有の誤用、番号枯渇を確認 |
| `zig build test --summary all` | 23/23ステップ成功。今回実行分は1091成功・14スキップ、独立runtimeの8件は成功済みキャッシュを利用。Cortex-M0+コンパイルと実パイプの既存試験も成功 |
| `zig build test -Dgraphics=false -Daudio=false -Ddebug=false --summary all` | 22/22ステップ成功。今回実行分は876成功・227スキップ、独立runtimeの8件は成功済みキャッシュを利用 |
| `zig build runtime-check -Dtarget=x86_64-linux-musl --prefix .work/runtime-linux --summary all` | コンパイルと試験実行体の配置成功 |
| WSLから`.work/runtime-linux/runtime-tests/x86_64-linux/test`を実行 | Linuxで8/8成功。self-pipeの通知・待機・終了を含む。Linuxの全体試験ではない |
| `zig build runtime-check -Dtarget=aarch64-macos --summary all` | macOS向けのコンパイル成功。Mac実機での実行は未確認 |

`runtime-check`は試験実行体を`<prefix>/runtime-tests/<arch>-<os>/test[.exe]`へ配置する。別OS向けの試験をコンパイルだけで止め、そのOSで明示的に実行するための工程。配布パッケージは作成しない。

### 次の作業と900の残り

1. 所有するホスト文脈へ時計・Wake・台帳・信号所有をまとめ、epochの生成・寿命と、差替え可能な起床・所有の入口を具体化する。
2. 信号所有の最小仲介と既存NS・音待機の境界を接続し、失敗・入れ子・解除順を差替え試験する。既存の信号やmaskの一括移行は行わず、接続範囲を明記する。
3. Mac実機の起床試験と、プロセス作成・継承を伴う接続の検証は、実施環境と担当を分けて進める。
4. 900の共通契約・最小実装の完了条件を満たしてから1056の語群基盤へ進み、その後に1036のOS判別を実装する。24点すべての詳細仕様を今回確定したものとは扱わない。

コミット・プッシュは今回の着手指示では実施していない。

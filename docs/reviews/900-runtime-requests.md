# 900 実装レビューの依頼文

2026-11-19。いずれもRead/Glob/Grepだけを許可し、permission-mode dontAsk、strict-mcp-config、no-session-persistenceの非対話CLIで依頼。以下は各回に送った依頼文。

## initial-request.txt

900の実装済み共通部品を読み取り専用でレビューしてください。ファイルの編集・Git操作・テスト実行・外部アクセスはしないでください。
レビュー対象の固定コピーは .work/900-review/initial/ 内のruntime_base.zig、host_clock.zig、host_wake.zig、host_wait.zig、runtime_base_test.zigです。相対importは元ソースを参照する必要はなく、API照合が必要ならsrc/とdocs/CORE_EXTENSION_IMPLEMENTATION.md、CORE_EXTENSION_DETAILED_DESIGN.mdを読めます。固定コピー以外は現在の作業中のコードであり、原稿の指摘と混同しないでください。
重点は競合・lost wakeup・取消し・期限・番号再利用・異なる台帳のepoch・OS資源寿命・POSIX pipeとSIGPIPE・クロスプラットフォーム・NS互換性です。現在は単一消費者・複数通知側、deinit前の全参加者停止、台帳は所有スレッド限定、epochは呼出し側が一意に割り当てる前提で、ホスト統合は次の作業です。
日本語で、重大度・対象と位置・具体的な失敗条件・修正案を示してください。指摘は重要なもの最大10件、未確認のOS挙動は推測と明記し、実行したとは書かないでください。標準出力へ返してください。


## integration-request.txt

900の1061・1062の統合を読み取り専用でレビューしてください。ファイル変更、Git操作、実行テスト、外部アクセスは禁止です。日本語で結果を標準出力へ返してください。
固定コピー .work/900-review/integration/ のhost_runtime.zig、host_signal_broker.zig、host_wait.zig、host_wake.zig、runtime_base.zigを中心に、main.zigのRuntime初期化・shutdown/deinit・HostContextとNS/audio callbackの接続、host_audio.zig・host_interface.zig・words_audio.zigのhost_failed、追加テストを確認してください。必要な他のソースはリポジトリ内で読めますが、固定コピーがレビュー対象です。
前回のレビューはdocs/reviews/900-runtime-initial.mdです。Runtimeの共通採番器はowner/台帳epochをプロセス内で再利用せず、台帳epochは台帳incarnationごとに異なります。OwnedTableはホストスレッド限定で、全利用者停止・join後にdeinit、共有後のRuntime/Wake/台帳はコピー・移動禁止です。起動をまたぐepoch一意性・Forthハンドル形式は未実装です。
重点は、別台帳や再生成時のID衝突、closed/closingと資源参照、信号のプロセス全体所有、begin失敗・end失敗・入れ子の復旧、NSと音の互換、POSIX通知集約のlost wakeup、終了defer順、エラーコード、テストで漏れる問題です。既存NSのrawモード処理は維持し、音待機はrawを変えずsigactionへ共通化しています。停止不能時のlibc.exitは後続のStorage解放を避ける最終経路です。
重大度・対象の位置・具体的な失敗条件・修正案を重要順に最大10件。未確認OS仕様は推測と明記し、単なるAPIの将来案と現在の欠陥を分けてください。読んだ範囲と未実行を記載してください。


## final-request.txt

900統合の指摘反映を読み取り専用で最終再確認してください。編集・Git操作・実行テスト・外部アクセスは禁止です。日本語で簡潔に最大6件、重大/高を優先し、根拠と具体的な失敗条件を示してください。
対象は固定コピー .work/900-review/final/ のhost_runtime.zig、host_signal_broker.zig、host_wait.zig、host_wake.zig、main.zig、words_audio.zig、audio_test.zig。前回原文はdocs/reviews/900-runtime-integration.md。
修正点：NativeScopeと失敗Ticketをプロセス所有/ Broker領域に保持し、次の待機とshutdownでrecover。部分復元はinstalled/console/terminalで冪等に追跡、復元失敗を中断より優先。begin rollback失敗も所有を保持。NativeScopeはprocess gate取得後だけ変更。mainのfatal経路ではflush・utf8_console.finish・resize_scope.endを明示的に実行。Runtime.phaseをatomic化。台帳はinitTable(out)でアドレスへ束縛しコピーを拒否。waitTakenはHostFailed等を伝え300回空回りを止める。pending解除をRMW化。close失敗時もruntimeはclosedへ移る。
契約：メタデータと信号の所有仲介はアプリ内の一つのホストスレッドのみ。通知だけ別スレッドから可。deinit前には全参加者をjoin。新しいRuntime/Wakeを共有後にコピー・移動しない。OwnedTableのgetが返すポインターはremove/deinitまでの借用。Forthのタスクや公開ハンドル形式は未実装。
前回の高・中の指摘が直ったか、未解決の現在の欠陥があれば教えてください。実装済みとは断定せず、OS試験の未確認は明記してください。未決APIの将来案の繰返しは不要です。


## terminal-request.txt

読み取り専用、編集/Git/実行テスト/外部アクセスなしで、直前の中優先指摘の修正だけを確認してください。固定対象は.work/900-review/terminal/のhost_input.zig、host_wait.zig、main.zig。前回原文はdocs/reviews/900-runtime-followup.mdです。
変更点：終了のhost_input.leave前にもrecoverを試みます。host_inputのenter/leave/setMouseはbefore_mode_changeフックで先にpending復元を試し、失敗時enterは一時NSモードを元状態として捕捉しません。leaveのような後続の正規モード変更には世代を付け、NativeScope.endは古い端末スナップショットだけ破棄し、信号ハンドラーの復元は継続します。Windowsハンドラーは待機外ではCTRL_Cを消費しません。新テストは回復フックがbaseline取得より先に呼ばれることと、古い不正な保存端末状態を再適用しないことです。
リポジトリの現ソースは必要な関連箇所だけ読めます。評価は日本語で簡潔に、今回の修正に未解決の重大/高/中の欠陥があるか、あれば失敗条件と修正提案を最大3件。なければ設計上の指摘が解消した旨と実OSエラー注入が未検証である旨を区別してください。将来APIの繰返しは不要です。

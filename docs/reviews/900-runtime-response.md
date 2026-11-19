# 900 実装レビューへの対応

対象：1058〜1062の共通部品・ホスト統合。日付：2026-11-19。

実装を続けながら、リポジトリ内の固定コピーをClaude Codeへ読み取り専用で渡した。レビュー中に対象を変えないため、初回は`.work/900-review/initial/`、統合版は`integration/`、再確認は`final/`へ分けた。レビューはコードの読取りであり、OS動作を検証したものではない。実行した検証は[実装記録](../CORE_EXTENSION_IMPLEMENTATION.md)を参照する。

## 初回レビュー

[原文](900-runtime-initial.md)。Claude Code 2.1.327、セッション`ab470686-8e9a-4196-bbc9-60f010b13d00`、約181秒。原文の番号にRを付けて追跡する。

| ID | 対応 | 検証・残る境界 |
|---|---|---|
| R01 台帳間のID衝突 | ホストの共通採番器から台帳incarnationごとに異なるepochを発行 | 別台帳・閉じた台帳からの古いハンドル拒否を試験。起動をまたぐ一意性は未保証 |
| R02 owner再利用 | ownerとepochを同じ非再利用の採番器から割当て | 番号枯渇を検査。タスク単位のownerは後続のタスク制御で追加する |
| R03 コピー・並行解放 | 共有後のRuntime/Wakeのコピー・移動と、通知側が残るdeinitを禁止。OwnedTableは後述I03でアドレスへ束縛 | deinitの前に全参加者をjoinする契約は維持。並行deinitが安全だとは主張しない |
| R04 SIGPIPEとclose順 | POSIXの書込み側を先に閉じる。ホストの一つのWakeは通常起動時に作る | 通知者停止後の解放が前提。プロセス全体のSIGPIPE方針は変更しない |
| R05 取消しの起床 | Runtime.beginShutdownが取消し印とnotifyを一緒に実行する | 素のCancellationだけを渡す既存部品は20msごとの確認。硬い応答時間保証はない |
| R06 通知集約 | pendingのfalse→trueでだけPOSIXへ書込み。解除はacq_relのRMW | 満杯のEAGAIN、書込み失敗後の再通知、並行通知を試験 |
| R07 macOS CLOEXEC | 実行体のホストRuntimeは子プロセス生成前に作成。複数Native Runtimeの動的作成は現在使わない | macOSで動的生成を導入する際はプロセス生成との直列化を別途行う。実機は未確認 |
| R08 時計の系統 | 新しいRuntimeの期限とNSはそのRuntime.clockを使用 | 装置内の音時計など既存の全時計の移行は行わない。休止の扱いも確定済みとしない |
| R09 ownerとエラーの露出 | OwnedTableの現在のownerはホストRuntimeに固定。内部診断エラーをForthへ公開しない | タスクownerの導入時に公開エラーと検査順を見直す。insert失敗でpayloadの所有を取らない契約を追加 |
| R10 期限と時計の組 | Runtime.waitForは同じRuntime.clockで期限を一度だけ計算 | 絶対期限を渡すwaitは同じ時計の期限を使う前提。Gforthとの新たな比較は実施していない |

## 統合版レビュー

[原文](900-runtime-integration.md)。セッション`0e73077f-57af-43fb-aedf-e620ee6b9326`、約259秒。原文の番号にIを付ける。台帳間の衝突とowner再利用の解消が確認され、POSIX集約通知の永久的な取りこぼしは見つからなかった。一方、信号復元と終了経路などに指摘があった。

| ID | 対応 | 検証・残る境界 |
|---|---|---|
| I01 失敗した信号復元の保存先 | NativeScopeをプロセス所有の固定領域へ移し、Brokerは失敗Ticketを保持。次の待機と終了時にrecoverする。部分beginの巻戻し失敗も保持 | 復元失敗後に次のaudio/NSへ復帰する差替え試験。復元失敗を中断より優先。解除済み項目は再解除しない |
| I02 fatal終了時の出力・コンソール | Runtimeを回収できない最終経路でもflush、utf8_console.finish、resize_scope.endを明示的に実行 | resize_scopeはSIGWINCHとフラグのみを扱いStorageへ触れないことをソースで確認。実OSの復元不能を故意に起こす試験は未実施 |
| I03 OwnedTableコピー | initTable(out)へ変更し、安定したアドレスへ束縛。各操作・deinitでコピーを拒否 | コピーによるinsertとdeinitを拒否し、参照数を二重に減らさない試験 |
| I04 phaseの競合 | phaseをatomic enumに変更 | 別スレッドからnotifyしながらホストがshutdownする試験。deinit前のjoinは引き続き必須 |
| I05 音待機の空回り | waitTakenがホスト障害・上限到達をエラーで伝える。resetの失敗も成功扱いにしない | すべての待機がhost_failedでも短くエラーで戻り、残るresetを消費者が後で処理できる試験 |
| I06 pendingの同期・未到達分岐 | 解除をacq_relのswapへ変更 | POSIXの満杯・無効な書込み先・複数通知側を試験 |
| I07 close失敗後の状態 | OSのcloseを試す前にRuntimeをclosedへ移す | 二度目のdeinitで再度OS資源を閉じない。実OSのclose失敗を誘発した証拠とはしない |
| I08 試験cleanupのpanic | 新しいRuntime等のcleanup失敗は診断し、保持スコープの解除もdeferへ追加 | 根本のexpect失敗をunreachableで覆わないようにする。既存テスト全体の書換えはしない |
| I09 payloadの借用 | getのポインターはremove/deinit/スロット再利用までと明記 | タスク単位の所有分離は現在の実装範囲に含めない |
| I10 生のResourceTable | OS非依存の部品として保持し、ホスト側の生成はRuntime.initTableへ統一 | 独自ホストが使う場合は一意epochを渡す契約。公開Forth型ではない |

## 再確認

[再確認原文](900-runtime-followup.md)。セッション`3aef4c04-a62e-4e4d-9321-315ab058fd03`、約185秒。I01〜I07の対応がコードにあると確認され、端末モードの復元順に中1件、寿命・Windowsハンドラー・試験範囲に低3件の追加指摘があった。

| 追加指摘 | 対応 |
|---|---|
| F01 保留した古い端末モードの再適用 | 終了のleaveより前にもrecover。enter/leave/setMouseは復元フックを通し、enterは回復失敗時に一時モードをbaselineへ取り込まない。モード世代が変わった保存値は捨て、ハンドラーだけ引き続き回復する |
| F02 破棄されたRuntimeへの回復参照 | ResourceBusyではRuntimeを破棄せず、回復と利用者の回収まで生存させる契約を明記。実行体は回収不能時にVM Storageを解放せず最終終了する |
| F03 保留したWindowsハンドラーのCtrl+C消費 | 待機で割込みを受け付ける間だけCTRL_Cを消費し、それ以外は次のハンドラーへ渡す。実際の削除失敗の誘発は未検証 |
| F04 失敗注入の範囲 | 差替えによるbegin巻戻し・end再試行・古いスナップショット破棄・持続的な音待機失敗を試験。実OS APIの失敗を注入した証拠とは区別する |

F01の修正を別の固定コピー`.work/900-review/terminal/`として読み取り専用で追加確認に出した。レビュー待ちの間にもWindowsコンソール・Linux PTY・機能除外・Mac向けコンパイルを進める。

## 端末復元の追加確認

[原文](900-runtime-terminal.md)。セッション`f355af48-5214-475e-84eb-35e540b3862b`、約61秒。読んだ範囲で重大・高・中の未解決欠陥は見つからず、F01とWindowsのF03はコード上で解消したとの評価だった。実OS障害の注入とビルド・実行はレビューでは行っていない。

追加の低い指摘への対応：

- 不正なtermiosを用いる試験が実端末へ適用しかねない点は、無効化処理を切り出し、OSを呼ばずに保存値の破棄を直接調べる試験へ変更した。機械的な切出しと試験の安全化を行った後の再々レビューは実施していない。
- POSIXでSIGINTハンドラーそのものの復元が失敗している間の、待機外SIGINTの扱いは残る制約。失敗を報告し次の待機・モード変更・終了で回復を試みるが、既定配送へ戻ったことを保証しない。OSの障害注入を含む検証は未実施。

最終の実行結果とMac実機の未確認範囲は[実装記録](../CORE_EXTENSION_IMPLEMENTATION.md)へまとめた。

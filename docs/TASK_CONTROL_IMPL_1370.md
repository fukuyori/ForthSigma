# タスク1370：描画完了の共通Wake接続

作成日：2026-11-24。対象は1048配下のタスク制御03-Cである。

## 1. 結論と境界

**既存語の挙動変更：macOSでは子入力EOFを受けると`window_size.gone()`を反映する。既存の`WINDOW-PAINT-WAIT`（frameWait）等も窓の消失を認識して待機を終了する。改善として維持するが、新規内部APIだけの変更ではない。**

レビュー指摘1〜6はソースで確認し、すべて反映した。指摘7のLinux・POSIX実行確認はWSL側へ引き継ぐ。指摘を誤りとして退けた事項はない。

描画完了の内部登録・非消費照会・解除と、Windows・X11・macOSから共通Wakeへの接続を追加した。公開Forth語、スタック効果、公開エラー番号は追加・確定していない。Forth命令実行ループとworkerの許可集合は変更していない。方式の確定・公開、性能条件の達成を示すものではない。

根拠はTASK_CONTROL_WAIT_REGISTRATION.mdの4節・6.5節、CORE_EXTENSION_DESIGN_DECISIONS.mdの利用者決定D08、TASK_CONTROL_STATE_MACHINE.md、TASK_CONTROL_USAGE_CONDITIONS.mdである。painted_event等を共通待機へ加えず、状態公開後に共通Wakeへ通知する構成である。backend描画完了であり、物理提示完了ではない。

## 2. 変更ファイルと要点

| ファイル | 内容 |
|---|---|
| `src/core/task_paint.zig`（新規） | Source、Registration、Result。能力・窓有無・目標番号を検査し、固定目標、寿命世代、能力喪失世代、通知障害を保持する |
| `src/host_paint.zig`（新規） | プロセス内の単一native windowの持続するSource。対応構成だけに初期能力を与える |
| `src/tests/task_paint_test.zig`（新規） | 実窓なしの登録検査、固定目標、close・再表示、能力喪失、通知世代、解除、通知失敗、世代枯渇、POSIX子パイプの非消費待機を試験する |
| `src/host_window.zig` | WindowsのSHOW・作成・描画完了・破棄時の状態公開、入力メッセージ処理後の通知、内部paintCapable/registerPaint/probePaint/waitPaintChanges、任意実行の実窓試験 |
| `src/host_window_linux.zig` | SHOW・publish・painted・forget・close検出から状態公開、X11イベント処理後と文字キュー追加時の通知 |
| `src/host_window_macos.zig` | PAINTED・WINDOW等の受信とcloseから状態公開、子入力の有限量排出、子パイプfdの内部貸出、EOF時の窓終端と監視解除 |
| `src/host_wake.zig` | 共通Wakeと追加POSIX読取fdを同時に待つ内部操作。追加fdはここで読まない |
| `src/host_runtime.zig` | WakeOpsの借用口とnative runtimeの追加fd待機口 |
| `src/main.zig` | 安定したRuntime確保後の通知先接続と、Runtime破棄前の接続解除の2行 |
| `src/runtime_test.zig` | 新規単体試験を既存のtest対象へ追加する1行 |

`src/forth.zig`、`src/forth_test.zig`、build.zigには今回の変更を加えていない。開始時点から存在した他タスクの変更は保持した。

## 3. 設計上の選択と理由

### 状態と寿命

登録は呼出し内の対象番号index、現在のwindow寿命世代、固定した目標番号、能力喪失世代を値として持つ。target=nullは登録時の最新SHOW番号を一度だけ採る。0、未投入番号、過去の窓寿命に属する番号は拒否する。close時に次の窓が受け付ける番号の下限も保持する。後続SHOWで目標を動かさず、目標以上の完了番号で成立する。closeした後は完了番号を満たしていてもreleasedである。Linuxはclose検出と同じロック境界で即時に終端を公開し、後のpublishより先にSHOWが再投入されても旧窓を保持しない。SHOW側もstatus=readyの場合だけopenを公開し、破棄前のshared.openを新窓の成立と扱わない。再表示では寿命世代が進み、新窓の完了で旧登録を成立させない。能力喪失後に能力が戻っても既登録はcapability_lostである。世代枯渇や通知失敗はHostFailedとして残し、永久pendingにしない。通知障害notification_failedと世代枯渇failedは分離する。bind(null)では通知障害を消さない。非nullへの再bindで通知を再試行し、成功時だけ通知障害を解除する。失敗なら再び障害を保持する。世代枯渇は再bindでも回復しない。保持していた完了番号・寿命世代・能力喪失世代・登録値は再bindで変更しない。

host adapterのregisterPaint/paintCapable/probePaintは所有VMのStateを受け取る。`library_loading.isLoaded`でGRAPHICSを検査し、その語彙の`(DISPLAY)`変数を検索順序によらず読む。明示選択が0（自動）のときだけgfx_auto_displayを参照し、2（native）のときだけ登録を許す。未解決の自動選択、Tk、端末は古いnative窓が開いていても拒否する。Forthコード実行や表示先の自動決定は行わない。Source.selectで能力喪失世代を進め、backendからのcapable=trueの公開が表示先の非選択を上書きしない。窓なしはNoWindow、未対応経路はUnsupportedBackend、番号不正はInvalidTargetとして内部で区別する。これらは公開エラー番号ではない。indexは共通登録側の返却対応用であり、待機対象配列の容量・index上限検査は1369側の責務である。

Sourceは単一native windowに対するプロセス寿命の保持領域であり、登録から窓の画素やOSハンドルを参照しない。新規窓への置換は世代で判別する。Sourceは共有後に移動しない。登録操作・照会・解除は所有ホストスレッドで行い、Registrationは解除後にコピーを使い回さない。unregisterはその登録値だけを無効化し、共有状態・完了番号・共通Wakeを初期化しない。backendは登録スタックや返却配列へのポインターを持たないため、登録解除時にbackend callbackを待つ必要はない。

### 同期と共通Wake

Sourceは短い専用ロックを持つ。Windowsのregister/probeは描画用SRWLockを取らず、長い描画の終了をそのロックで待たない。backendの公開箇所は既存ロック→Sourceの順である。逆順の取得は行わない。Sourceの保持状態を書き換えてからWakeOps.notify_fnを呼ぶ。入力本体は既存キューへ残し、通知だけを足す。

通知先はmainでRuntime.ops()から借用する。RuntimeとWakeは接続中に移動・破棄しない。bind(null)はSourceロックにより進行中notifyとの参照終了を同期する。非null bindは保持状態の再巡回を促すため一度notifyする。mainのdefer順は窓close→接続解除→Runtime破棄である。個別登録ごとに別Wakeを作らず、起動時接続を共有する。登録前の成立もSourceに保持される。

呼出し側は共通Wakeのobserve→全対象probe（描画はprobePaintへStateを渡す）→waitPaintChanges→再巡回の順で使う。notifiedを描画成立そのものに読み替えない。waitPaintChangesは複数対象の登録配列や成立集合を実装するものではなく、1369以降が共通巡回へ組み込む内部接点である。

### backendの能力

- Windows：全画像の描画成功かつ非最小化という既存paintedWholeの条件でのみ完了番号を公開する。既存painted_eventの作成・SetEvent・frameWaitは維持する。
- Linux：graphics=trueかつx11=trueのX11/XWaylandに限る。既存painted()の描画・最小化判定を通った番号だけを公開する。文字キュー・物理キー・マウス・preedit・窓状態の公開箇所から通知する。無関係のX11イベントでは通知しない。
- macOS：子AppKitのPAINTED番号を親が受領した時点で完了とする。親から非消費probeするだけでは子のパイプが進まないため、waitPaintChangesが共通Wakeと子読取fdを同時に待ち、前後に最大4096 byteの既存入力排出を進める。入力本体は既存キューに残す。EOFでは窓を終端化し、以後そのfdを監視しない。期限到来・取消しの場合も呼出し側は再照会する。
- Tk、Linuxのx11=false、graphics=false、その他の非native経路：描画登録は未対応である。タイマーで描画成立を代用しない。

POSIXの追加fd待機はパイプを消費せず、通知理由としてだけ返す。共通Wakeが同時readyなら有限量read→pending=false→世代再照合の順を守る。共通Wake以外の自動リセットイベントを対象にしない。Runtime.initWithによる注入runtimeの追加fd待機はHostFailedで拒否し、注入側独自のmultiplexerを必要とする。

## 4. 通常経路の変更と既存ファイル変更の理由

命令ごとの取消し確認、VMのState配置、Forth語実行入口、worker実行には今回の変更がない。通常ホスト経路の変化は次のとおりである。

1. Runtime起動・終了に通知先接続・解除を追加した。backendから既存の共通Wakeを安全に借用するためである。
2. native SHOW、窓の作成・破棄、描画完了に短いSource同期を追加した。状態を保持し、描画ロックと登録照会を分けるためである。
3. 対象Windows入力メッセージ、X11入力・窓状態・文字キュー、macOS子応答に共通通知を追加した。通知は併合され得る。WindowsのfocusやIMEコンテキストの変化も通知する。WindowsのWM_CAPTURE_CHANGEDによるreleaseButtonsとタイマー0x5343でのShift解放も通知する。releaseButtonsは実際にボタンを解放したとき、Shiftはheldから解放したときだけ通知する。WM_MOUSEMOVEの一律通知は外し、座標・ボタン・未読状態の変化があるときだけmouseMovedから通知する。X11も全イベントのdefer通知を外し、状態の公開箇所へ移した。マウスのdirtyがfalseからtrueになる場合は、既存の入力APIが新たに観測できる変化として通知する。
4. POSIXの既存Wake.waitWithClockは追加fd付き内部操作へ委譲する。従来呼出しでは追加fd=-1であり、poll配列の無効な第2要素は無視される。レビュー前はread直後の早期notifiedで取消し優先が崩れていた。現在はread→pending解除→世代再照合後にループ先頭へ戻り、取消し→世代→期限を判定する。追加fd単独およびWakeのstale信号と追加fdが同時readyの場合もnotifiedの直前に取消しを検査する。既存20ms上限は維持する。Windows側の待機対象は従来どおり共通Wake一個である。
5. macOSの子入力EOFはSourceだけでなく既存window_sizeにもgoneを反映する。閉じた窓への新規登録とEOFパイプによる再起床の反復を防ぐためである。
6. Zig 0.17.1のzig fmtがLinuxのfit_modeとmacOSのparent_fit等のenum変換を@fromBackingInt/@backingIntへ正規化した。対象ファイルのfmt --checkを満たすための構文更新である。

コード生成・実行速度・メモリ費用の比較は行っていない。上記の通常経路変化は利用者の個別判断対象として報告する。

## 5. 試験と実行結果

Windows/PowerShell、Zig 0.17.1で実行した。今回のレビュー修正後の結果は以下の表に記す。キャッシュ・一時領域は作業ツリー内に置いた。初回はキャッシュ作成のAccessDeniedとbuild runnerによる--global-cache-dir拒否があり、環境変数指定へ切り替えた。その後は既存試験の固定パス`.zig-cache`がないことによる15件のファイル関連失敗があった。環境変数でキャッシュと一時領域を指定し、`.zig-cache`を作成した後は成功した。既存試験コードは変更していない。

| 検証 | 結果 |
|---|---|
| `zig build test` | 成功（終了コード0）。レビュー修正後に再実行した |
| `zig build test -Ddebug=false` | 成功（終了コード0）。レビュー修正後に再実行した |
| Windows実窓の任意試験 | FORTHZ_PAINT_SMOKE=1で成功。2×2画像を表示し、登録から描画完了を取得、closeでreleased、再表示後も旧登録がreleasedであることを確認した |
| 新規の実窓なし単体試験 | Windowsで成功。POSIX専用パイプ試験はWindowsではskipである |
| `zig build -Dtarget=aarch64-macos` | 成功。macOS実行・実画面は未確認である |
| `zig build host-check runtime-check -Dtarget=aarch64-macos` | 試験実行体のクロスコンパイル成功。macOS上の実行は未確認である |
| `zig build host-check runtime-check -Dtarget=x86_64-linux` | POSIX待機試験・X11ホスト試験を含む試験実行体のクロスコンパイル成功。Linux上の実行は未確認である |
| `zig build -Dtarget=x86_64-linux` | 成功。X11有効のLinux実行体をクロスビルドした |
| `zig build -Dgraphics=false -Dextension=false -Daudio=false` | 成功（終了コード0）。レビュー修正後に再確認した |
| 変更したZigファイル10本の`zig fmt --check` | 成功 |
| `git diff --check` | 成功 |
| WSL Linux実窓・POSIX待機実行 | 未実施。前回のアクセス拒否は利用者提示のとおりであり、今回は再試行していない |

追加試験ではwaitPaintChangesのtimeout結果を検査する。POSIX専用試験ではextra fdだけがreadyの場合、Wakeと同時readyの場合、初回の取消し確認を通過した後（注入時計callback）に取消し要求と通知が発生する場合を区別し、extra fdなしの既存waitWithClockにも取消し優先を確認する。子パイプを消費しないことも検査する。通知失敗はunbind後と失敗する再bind後にも残り、生きたWakeへの再bindで回復すること、世代枯渇は再bindでも残ることを検査する。

初回の追加表示先試験はfake Writerにwindow_fnがなくDISPLAY-WINDOWが拒否されて失敗した。試験用Output.has_window=trueへ修正し、再実行で成功した。製品コードへの回避策は追加していない。

既存testのキャッシュ済み部分を合算して独自の総試験数は作らない。速度・時間の測定は追加していない。新規試験の5秒deadlineはハング防止であり、性能の合否基準ではない。

## 6. 再現手順と未確認事項

Windowsでの実窓の確認は、リポジトリルートのPowerShellから次のように行う。

```powershell
New-Item -ItemType Directory -Force .zig-cache, .cache-1370 | Out-Null
$env:ZIG_GLOBAL_CACHE_DIR = "$PWD\.cache-1370\global"
$env:ZIG_LOCAL_CACHE_DIR = "$PWD\.cache-1370\local"
$env:TEMP = "$PWD\.cache-1370"
$env:TMP = $env:TEMP
$env:FORTHZ_PAINT_SMOKE = '1'
zig build test
Remove-Item Env:FORTHZ_PAINT_SMOKE
zig build test -Ddebug=false
```

任意試験名は`native paint registration real window smoke (opt in)`である。小窓が表示・close・再表示され、試験終了で閉じる。手操作は不要である。フラグなしではこの試験をskipする。

WSL LinuxではX11/XWaylandとDISPLAYを利用できるセッションで対象worktreeへ移動し、Linux用Zig 0.17.1を確認したうえで次を実行する。実行結果は今回未確認である。

```sh
mkdir -p .zig-cache .cache-1370/wsl
export ZIG_GLOBAL_CACHE_DIR="$PWD/.cache-1370/wsl/global"
export ZIG_LOCAL_CACHE_DIR="$PWD/.cache-1370/wsl/local"
export TMPDIR="$PWD/.cache-1370/wsl"
# POSIX取消し優先（extra fdなし/単独/同時ready）、fd非消費、X11ホスト試験
zig build runtime-test
FORTHZ_PAINT_SMOKE=1 zig build test
zig build test -Ddebug=false
```

Linuxでは追加のPOSIXパイプ試験も実行される。窓を最小化している間のpending、入力による起床、入力キュー非消費、複数対象の同時成立、登録解除とcallbackの並行、通知故障回復の実backend結合確認は別途必要である。再bindの回復条件そのものは単体試験で確認した。macOS実機は今回未確認であり、クロスビルドをPAINTEDプロトコルとOS待機の実機成立の証拠にはしない。macOSの任意実窓試験は明示的にskipしている。

1369との接点として、登録には`registerPaint(state, index, target)`、毎巡の照会には`probePaint(state, registration)`を使う。低層Source.register/probeを直接使って表示先の検査を省略しない。表示先変更は所有ホストスレッドが扱い、変更後にpaintCapableまたはprobePaintを呼んで非選択状態を反映する。表示先を変更してすぐ戻す間に一度も反映しなかった履歴は検出しないため、1369側の表示先変更を受領する境界でも刷新が必要である。通常Forth命令ループへ監視は加えていない。通知障害後は1369側で障害を受領し、旧通知先との参照終了を同期したうえで生きたWakeへ再bindし、observe→全対象再照会を行う。障害からの自動再試行やRuntime全体の再作成は本実装の責務に含めない。

1369以降では全対象の事前検査・有限容量・全件probe・成立集合・共通Wake単一消費者・絶対期限維持・macOS追加fd待機の巡回接続を確認する必要がある。この実装だけで複合WAITやタスクスケジューラー全体の完成とはしない。

## 7. 利用者の判断が必要な事項

D08等の決定済み条件に再判断を求める事項はない。方式の最終採用と公開、公開語・スタック効果・エラー値は引き続き保留である。通常ホスト経路の変更は4節の列挙を判断材料とする。macOS・WSL実機の未確認事項と後続の共通登録結合試験は残る。性能条件の達成可否は今回判断していない。

コミット・branch作成・タグ作成・push・tque変更・作業ツリー外への変更は行っていない。

## 8. 最終Git状態と引渡し

以下は最終の`git status --short`である。1370以外の開始時点からの変更も含む。今回の対象は2節の11ファイルだけである。

```text
 M docs/CORE_EXTENSION_DESIGN_DECISIONS.md
 M docs/CORE_EXTENSION_DETAILED_DESIGN.md
 M docs/CORE_EXTENSION_PLAN.md
 M docs/CORE_EXTENSION_WORKER_STATE_AUDIT.md
 M docs/README.ja.md
 M docs/README.md
 M docs/TASK_CONTROL_PLAN.md
 M docs/WINDOWS_NATIVE_DISPLAY_VALIDATION.md
 M src/core/defs.zig
 M src/core/dictionary_image.zig
 M src/core/error_reporting.zig
 M src/core/exception_registry.zig
 M src/core/image_append.zig
 M src/core/image_restore.zig
 M src/core/words_system.zig
 M src/forth.zig
 M src/forth_test.zig
 M src/host_runtime.zig
 M src/host_wake.zig
 M src/host_window.zig
 M src/host_window_linux.zig
 M src/host_window_macos.zig
 M src/main.zig
 M src/runtime_test.zig
?? docs/TASK_CONTROL_ACCEPTANCE.md
?? docs/TASK_CONTROL_AUDIT_ALLOWED_SET.md
?? docs/TASK_CONTROL_AUDIT_REENTRY.md
?? docs/TASK_CONTROL_AUDIT_SHARED_STATE.md
?? docs/TASK_CONTROL_CONFIG_MATRIX.md
?? docs/TASK_CONTROL_DETAILED_PLAN.md
?? docs/TASK_CONTROL_IMPL_1359.md
?? docs/TASK_CONTROL_IMPL_1360.md
?? docs/TASK_CONTROL_IMPL_1361.md
?? docs/TASK_CONTROL_IMPL_1370.md
?? docs/TASK_CONTROL_IMPL_1384.md
?? docs/TASK_CONTROL_METHOD_COMPARISON.md
?? docs/TASK_CONTROL_METHOD_DECISION.md
?? docs/TASK_CONTROL_PROTO_1352.md
?? docs/TASK_CONTROL_PROTO_1353.md
?? docs/TASK_CONTROL_PROTO_1354.md
?? docs/TASK_CONTROL_PROTO_1355.md
?? docs/TASK_CONTROL_PROTO_1356.md
?? docs/TASK_CONTROL_STATE_MACHINE.md
?? docs/TASK_CONTROL_USAGE_CONDITIONS.md
?? docs/TASK_CONTROL_WAIT_REGISTRATION.md
?? src/core/task_context.zig
?? src/core/task_paint.zig
?? src/core/task_permissions.zig
?? src/core/task_policy.zig
?? src/core/task_snapshot.zig
?? src/core/task_transfer.zig
?? src/host_paint.zig
?? src/tests/task_control_1384_test.zig
?? src/tests/task_control_w1_test.zig
?? src/tests/task_paint_test.zig
?? src/tests/task_permissions_test.zig
?? src/tests/task_snapshot_test.zig
?? src/tests/task_transfer_test.zig
```

1370だけの差分は`.cache-1370/task-1370.patch`に保存した。開始時点で変更済みだったファイルをpatchへ含めていない。`git apply --reverse --check .cache-1370/task-1370.patch`で現在の作業内容との一致を確認した。メインへの実際の適用と他タスクとの結合は未実施である。キャッシュ領域内のpatchは追跡対象ではないため、キャッシュを消去する前に取り出す必要がある。

# タスク1359：明示Snapshot内部APIの本番実装

対象は専用worktree `D:/tmp/forthz-1359`、Zig 0.17.1である。開始時のHEADは `35523f676836134c4fbaed19e3d01d2a23ec2a92`、detached HEADである。公開Forth語・スタック効果・公開エラー番号は追加していない。

## 変更ファイルと要点

| ファイル | 内容 |
|---|---|
| `src/core/task_snapshot.zig`（新規） | 不変イメージの所有、固有ID・版・元VM識別子・構造epoch、atomic参照数、投入判定とAdmission、新規VM復元、版内の入口名解決である |
| `src/tests/task_snapshot_test.zig`（新規） | 版の固定、失効境界、参照寿命、ホスト後始末の隔離、割当失敗回収の試験である |
| `src/forth.zig` | Stateへ2フィールドを追加し、forgetFromで構造epochを進める |
| `src/core/image_restore.zig` | preflight成功後のapplyで構造epochを進める |
| `src/core/image_append.zig` | typed appendのapplyで構造epochを進める |
| `src/core/dictionary_image.zig` | State間appendImageの変更開始前に構造epochを進める |
| `src/forth_test.zig` | 新規試験を登録する |
| 本書（新規） | 設計・検証・未確認範囲の記録である |

開始時から変更済みであった文書7件および未追跡の計画・監査・試作文書は保持した。本タスクの差分を適用する際は、上表の8ファイルだけを対象とする。commit・branch作成・push・tque操作は行っていない。作業ツリー外の変更、速度・時間の測定は行っていない。

## 設計上の選択と理由

### 取得と不変性

`Manager.capture`はメインVMの静止した安全境界で呼ぶ内部APIである。取得・投入判定・辞書構造変更をメインVMの所有者が直列化する契約である。実行中のStateのコピーや継続の複製は行わない。

`encodeImage`の実体である`image_encoder.measure/encode`を直接呼び、同じ保存形式と検証を使用する。既存`State.encodeImage`ラッパーは大きなWorkspaceをローカル変数に置くため、そのラッパーは経由しない。Snapshot用Workspaceはallocator.createでヒープに確保し、取得終了時に解放する。既存ラッパーの契約を変えず、他タスクとの衝突を抑える選択である。

バイト列はSnapshotが所有し、`image()`は`[]const u8`だけを返す。利用者はフィールドを直接書き換えず、SnapshotとAdmissionの所有権を値コピーしない契約である。取得時にVMのsizesも保存し、復元側のStorageへ使用する。

固有IDはプロセス内のatomic単調カウンタから採番する。元VM識別子も同じカウンタから別に採番し、別VMやStateアドレスの再利用による取り違えを防ぐ。版は取得時の固有IDを使う。したがって版は単調増加し、欠番を許す。連番の公開仕様ではない。ID枯渇時は周回せず`IdentityExhausted`で失敗する。

### epochと新規投入

`task_structure_epoch`は`image_generation`から独立したStateフィールドである。通常変数の書込みや通常の定義追加では進めない。`State.forgetFrom`を通るFORGET・MARKER・ライブラリ巻戻し、typed image append、State間append、完全復元で進める。`dropWordsFrom`は変更していないため、エラー中断やquotationの一時定義回収だけでは進めない。

加算は飽和加算であり、最大値では取得と投入を拒否する。古いepochへ周回しない。完全復元でepochや元VM識別子を保存イメージの値に戻すこともない。restoreとtyped appendのpreflight失敗はepochを変えない。

既存のState間appendImageには変更開始後もtryを伴う処理があるため、事前検査の後、最初の変更が起きる前にepochを進める。途中失敗しても旧版を新規投入できない安全側の扱いである。対象が自分自身である場合など、事前検査で拒否しただけならepochは変わらない。

`canSubmit`は元VM識別子とepochの一致を検査する。`admit`は検査に成功すると参照を1つ取得し、所有権を持つ`Admission`を返す。メイン所有者の直列化を解く前に呼ぶ必要がある。単独の`canSubmit`呼出しだけでは投入を予約しない。

### 参照寿命と復元

Snapshotの初期参照、Admissionの参照、FreshVmの参照は独立する。retainは枯渇を検査し、releaseはatomic参照数が最後の1つであった場合だけbytesとSnapshotを解放する。参照を持たないポインタからretainして復活させる使用法は禁止である。

構造変更後は新規Admissionを取得できないが、投入済みAdmissionや稼働中FreshVmはその版を保持する。`FreshVm.create`はAdmissionを受け、追加参照を取得し、新規Storage.allocate(false)とState.initからrestoreFreshする。epochの再検査は行わず、投入済み版の復元を可能にする。

Stateと復元Planもヒープに確保する。Planは復元終了時に解放する。入力イメージとPlanと対象Storageは別領域である。各失敗経路はerrdeferで所有資源と追加参照を戻す。FreshVm.deinitは画像後始末、Storage、State、Snapshot参照の順に解放する。

入口は復元したVMの検索順序で名前解決する。返すword IDは復元VM専用であり、メインのxtやIDを渡すAPIはない。同名語の再定義を含め、選択したSnapshotの内容で解決する。

FreshVmはホストWriterを引数に取らない。context=null、破棄用write_fnだけを持つWriterで初期化する。applyの物理キーresetや画像解放などがメインのcallbackや画像slotを受け取る経路を作らない。既存VMにcallbackを残したままrestoreFreshする使い方は提供しない。

atomic参照数は、Stateの並行操作やSnapshot公開そのものを同期する仕組みではない。キュー等への参照移転には別の同期が必要であり、allocatorは利用スレッドからの割当・解放に対応する必要がある。

## 通常経路の変更と既存ファイルを変更した理由

既存ソースへの追加は合計8行である。

- Stateに`u64`のepochと元VM識別子を追加した。Stateの配置・サイズと初期化対象が変わる。実際のパディング量は測定していない。
- forgetFrom、完全復元、2種類のappend境界に飽和加算を各1行追加した。既存の辞書変更で失効規則を必ず通すためである。
- 試験ルートにimportを1行追加した。新規試験を既存testターゲットへ含めるためである。

実行ループ、命令ごとの取消し確認、counted経路選択、回復判定は変更していない。通常変数の書込みにも監視を追加していない。zig fmtによる既存ファイルの改行形式の正規化はあるが、Gitの内容差分は上記8行だけである。

## 試験と実行結果

PowerShellから実行し、`ZIG_GLOBAL_CACHE_DIR`をworktree内の`.zig-global-cache`へ設定した。ビルドツールが自動表示する時間を測定資料に使わない。

最初の実行では、新規試験の型情報APIがZig 0.17.1に合わずコンパイルエラーになった。リポジトリ内の使用例に合わせて`field_names`と`@FieldType`へ修正した。また、ビルド中の試験追加により別構成で`file contents changed during update`が発生したため、以後はソースを固定して再実行した。

最終ソースでの結果は以下である。runtime等のcachedは新たな実行として数えない。新規Snapshot試験10件に構成によるskip条件はない。

| コマンド | 結果 |
|---|---|
| `zig build test --summary all` | 終了コード0、23/23 steps succeeded、1386/1411 tests passed、25 skippedである。coreは1204 pass / 10 skip、hostは182 pass / 15 skip、runtimeはcached成功である |
| `zig build test -Ddebug=false --summary all` | 終了コード0、23/23 steps succeeded、1313/1411 tests passed、98 skippedである。coreは1132 pass / 82 skip、hostは181 pass / 16 skip、runtimeはcached成功である |
| `zig build test -Ddebug=false -Dgraphics=false -Daudio=false -Dextension=false -Dfiles=false -Dimage=false --summary all` | 終了コード0、13/13 steps succeeded、850/1404 tests passed、554 skippedである。coreは685 pass / 529 skip、hostは165 pass / 25 skip、runtimeはcached成功である |
| `zig fmt --check src/forth.zig src/forth_test.zig src/core/dictionary_image.zig src/core/image_append.zig src/core/image_restore.zig src/core/task_snapshot.zig src/tests/task_snapshot_test.zig` | 終了コード0、診断なしである |
| `git diff --check` | 終了コード0である。改行形式に関するGitの警告はあるが、空白エラーはない。未追跡ファイルはこの検査の対象外であるため、新規3ファイルの行末空白も別途検索し、該当なしを確認した |

新規試験は、取得後の変数・定義変更、旧版の明示投入、FORGET/MARKER後のID再利用、完全復元、2種類のイメージ追加、ライブラリ巻戻し、エラー中断とquotation、外部所有者とAdmission解放後のVM参照、別VM拒否、epoch枯渇、割当失敗を対象とする。ホスト試験ではメイン側に物理キーresetと画像freeの計数callbackおよび模擬画像slotを設定し、復元側Writerの全optionalフィールドがnullであることと、メイン側の資源が維持されることを検査する。

## 未確認事項と利用者の判断が必要な事項

- 実スレッドでの競合、同期付きキューへの所有権移転、取消し・停止・結果回収の結合は本タスクの試験対象外であり未確認である。
- 本APIは復元までを提供する。任意の入口を実行してよいとの許可ではない。初期許可集合の検査は1360、workerの取消し・実行経路は担当タスクで接続する必要がある。動的実行・例外・PAD・DO系等を許可する処理は追加していない。
- State.initとrestoreFreshの全フィールド残留監査、OS実資源を使用する並行試験、Windows以外の実行、費用・上限の評価は未確認である。新規VMを基準とし、再利用の合格を主張しない。
- 固有IDと参照数の最大値までの実反復は行っていない。epochは境界値を設定して試験する。
- 本タスクを成立させるための追加の利用者判断はない。方式の確定・公開、公開エラー番号、費用の実証、VM再利用は既存決定どおり保留である。Snapshotの容量・版数上限は今回の修正で決定済みとして適用した。
- `docs/TASK_CONTROL_STATE_MACHINE.md`は確認時点で存在しなかった。本書はそれを存在済みの根拠として扱わない。

根拠は`CORE_EXTENSION_DESIGN_DECISIONS.md`の利用者決定、`TASK_CONTROL_METHOD_DECISION.md`8節、詳細計画、監査文書、`TASK_CONTROL_PROTO_1354.md`と指定試作コード、および現行のencode/restore/append/forget実装である。試作コードは読取りだけとし、試作の入口検査を本番の許可検査として流用していない。

## 最終Git状態

以下は最終確認時の `git status --short` 全出力である。本タスクの8ファイル以外は開始時から存在した文書差分であり、変更していない。

```text
 M docs/CORE_EXTENSION_DESIGN_DECISIONS.md
 M docs/CORE_EXTENSION_DETAILED_DESIGN.md
 M docs/CORE_EXTENSION_PLAN.md
 M docs/README.ja.md
 M docs/README.md
 M docs/TASK_CONTROL_PLAN.md
 M docs/WINDOWS_NATIVE_DISPLAY_VALIDATION.md
 M src/core/dictionary_image.zig
 M src/core/image_append.zig
 M src/core/image_restore.zig
 M src/forth.zig
 M src/forth_test.zig
?? docs/TASK_CONTROL_ACCEPTANCE.md
?? docs/TASK_CONTROL_AUDIT_ALLOWED_SET.md
?? docs/TASK_CONTROL_AUDIT_REENTRY.md
?? docs/TASK_CONTROL_AUDIT_SHARED_STATE.md
?? docs/TASK_CONTROL_CONFIG_MATRIX.md
?? docs/TASK_CONTROL_DETAILED_PLAN.md
?? docs/TASK_CONTROL_IMPL_1359.md
?? docs/TASK_CONTROL_METHOD_COMPARISON.md
?? docs/TASK_CONTROL_METHOD_DECISION.md
?? docs/TASK_CONTROL_PROTO_1352.md
?? docs/TASK_CONTROL_PROTO_1353.md
?? docs/TASK_CONTROL_PROTO_1354.md
?? docs/TASK_CONTROL_PROTO_1355.md
?? docs/TASK_CONTROL_PROTO_1356.md
?? docs/TASK_CONTROL_USAGE_CONDITIONS.md
?? src/core/task_snapshot.zig
?? src/tests/task_snapshot_test.zig
```

## レビュー指摘への修正（2026-11-24）

今回の修正は `src/core/task_snapshot.zig`、`src/tests/task_snapshot_test.zig`、本書の3ファイルだけである。既存ソースと通常実行経路への追加変更はない。前節の試験表とGit状態は前回実装時の記録であり、今回の最終結果は本節に記録する。

### 指摘1：静止境界

指摘は正しい。旧captureとimage_encoder.measureには定義途中の拒否がなく、error_reportingとquotationsの中断はepochを進めずdropWordsFromを呼ぶ。取得入口をManager.captureへ統一し、defining・quote_depth・compilingを検査するようにした。pending（名前等の入力待ち）、postponing、control_depthも拒否する。

追加でquotation終結処理のquote_closing、匿名／予約名定義のnoname_next・next_name_len、deferred定義中のcolon_is_word、解釈ループ中のinterpret_loop_depthを拒否する。quotations、words_names、words_value_extensions、library_loading、words_compiling、error_reportingの状態更新から確認した。pending_constant等の値保持欄はpendingの判別子で扱う。pending_key・pending_event系はホスト入力の保持であり、辞書定義の未完了状態ではないため拒否しない。実行停止と直列化は引き続き所有者の契約であり、この検査はStateの並行操作を安全にするものではない。

個々の状態を単独設定する試験と、実入力による未完了定義・quotation・定義内のコンパイル再開・名前待ち・定義中の `[` によるコンパイル停止の試験を追加した。拒否時は採番・予約・確保に進まない。追加試験の当初の入力である単独の `]` はCompileOnlyになるため、ソースで条件を確認して定義内の `[`・`]` へ修正した。

### 指摘2：容量と生存版数

指摘は正しい。利用条件10節問4の決定に従い、Managerの既定値をmax_image_bytes＝4×1,024×1,024、max_versions＝3とした。内部設定値として変更可能である。measureの結果が上限を超えたらImageTooLargeを返し、イメージバッファを確保しない。measure用Workspaceは検査のため先に確保し、失敗時も解放する。容量と上限が等しい場合は許可する。

Managerはタスク機能全体で1個を共有する管理側の所有物である。VMごと・取得ごとに別Managerを作って制限を回避してはならない。後続1364・1366の管理側は同じManagerを所有し、全取得をそのcaptureへ接続する。Managerのアドレスと設定は取得開始から全版の最終解放まで維持する。公開管理機能との結合が完成したとは主張しない。

live_versionsはatomicであり、取得開始時に枠を予約する。上限時はVersionLimitを返す。取得中も1版として数え、取得失敗時はerrdeferで枠を返す。成功時はSnapshotがManagerを参照し、最終参照の解放時にbytesとSnapshotを解放してから枠を返す。現行版、外部参照のある旧版、Admission／FreshVmだけが保持する旧版を区別せず数える。同一版のretainは枠を増やさず、参照中旧版を強制破棄して新規取得を通す処理もない。

容量の超過・等値、生存3版時の4版目拒否、Admissionだけが保持する版の計数、最終解放後の再取得を試験する。全割当失敗試験にもManagerの計数が0へ戻る検査を加えた。実スレッド上で取得中の競合を作る試験は未実施である。

### 指摘3：appendのepoch

dictionary_imageのState間appendで、epoch更新後にも失敗可能な処理があることを確認した。説明どおり安全側の失効であり変更しない。誤りとして退けた指摘はない。

公開語・公開エラー番号・命令ごとの取消し確認は追加していない。新たに利用者判断を必要とする事項はない。Snapshot・Managerの全体予算管理との接続、実スレッド競合、128 MiB全体予算の実証は未確認である。

### 修正後の検証結果

PowerShellから実行した。速度・時間の測定は行っていない。新規Snapshot試験は合計14件である。

| コマンド | 今回の結果 |
|---|---|
| `zig build test --summary all` | 終了コード0、23/23 steps succeeded、core 1208 pass / 10 skip（1218件）である。他のrun testとruntimeはcached成功であり、新規実行数に含めない |
| `zig fmt --check src/forth.zig src/forth_test.zig src/core/dictionary_image.zig src/core/image_append.zig src/core/image_restore.zig src/core/task_snapshot.zig src/tests/task_snapshot_test.zig` | 終了コード0、診断なしである |
| `git diff --check` | 終了コード0である。未追跡の今回の3ファイルは別途行末のスペース・タブを検索し、該当なしである |
| `zig build test -Ddebug=false --summary all` | 終了コード0、23/23 steps succeeded、core 1136 pass / 82 skip（1218件）である。他のrun testとruntimeはcached成功である |
| `zig build test -Ddebug=false -Dgraphics=false -Daudio=false -Dextension=false -Dfiles=false -Dimage=false --summary all` | 終了コード0、13/13 steps succeeded、core 689 pass / 529 skip（1218件）である。他のrun testはcached成功である |

最終ソースで3構成とも成功した。新規Snapshot試験14件にskip条件はない。試験ログはworktree内の `.zig-cache/task1359-default.log`、`task1359-nodebug.log`、`task1359-excluded.log` に置いた。

### 今回修正後のGit状態

今回の修正対象3ファイルは前回から未追跡のままである。以下の他の差分も開始時から保持しており、今回変更していない。commit・branch・push・tque操作は行っていない。

```text
 M docs/CORE_EXTENSION_DESIGN_DECISIONS.md
 M docs/CORE_EXTENSION_DETAILED_DESIGN.md
 M docs/CORE_EXTENSION_PLAN.md
 M docs/README.ja.md
 M docs/README.md
 M docs/TASK_CONTROL_PLAN.md
 M docs/WINDOWS_NATIVE_DISPLAY_VALIDATION.md
 M src/core/dictionary_image.zig
 M src/core/image_append.zig
 M src/core/image_restore.zig
 M src/forth.zig
 M src/forth_test.zig
?? docs/TASK_CONTROL_ACCEPTANCE.md
?? docs/TASK_CONTROL_AUDIT_ALLOWED_SET.md
?? docs/TASK_CONTROL_AUDIT_REENTRY.md
?? docs/TASK_CONTROL_AUDIT_SHARED_STATE.md
?? docs/TASK_CONTROL_CONFIG_MATRIX.md
?? docs/TASK_CONTROL_DETAILED_PLAN.md
?? docs/TASK_CONTROL_IMPL_1359.md
?? docs/TASK_CONTROL_METHOD_COMPARISON.md
?? docs/TASK_CONTROL_METHOD_DECISION.md
?? docs/TASK_CONTROL_PROTO_1352.md
?? docs/TASK_CONTROL_PROTO_1353.md
?? docs/TASK_CONTROL_PROTO_1354.md
?? docs/TASK_CONTROL_PROTO_1355.md
?? docs/TASK_CONTROL_PROTO_1356.md
?? docs/TASK_CONTROL_USAGE_CONDITIONS.md
?? src/core/task_snapshot.zig
?? src/tests/task_snapshot_test.zig
```

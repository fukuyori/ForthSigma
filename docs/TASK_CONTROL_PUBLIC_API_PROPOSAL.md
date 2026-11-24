# タスク制御06-C：公開APIの決定（1379）

作成日：2026-11-24。作成者：ロク。最終決定者：レモン。

## 1. 位置付けと根拠

状態：2026-11-24に利用者が決定した公開APIである。レモンは9節の問1〜10すべてで推奨案（A）を採用した。以下の語名・数値・セル表現・スタック効果は決定済みの契約である。1379の実装・HELP登録・リファレンス生成・試験は完了し、結果は[実装記録](TASK_CONTROL_IMPL_1379.md)に記す。今回の文書更新では試験・測定を再実行していない。推奨理由は設計上の比較であり、未測定の速度や到達可能な性能を述べるものではない。

前提は[詳細計画11節](TASK_CONTROL_DETAILED_PLAN.md#11-公開apiの検討単位)、[状態機械](TASK_CONTROL_STATE_MACHINE.md)、[待機登録](TASK_CONTROL_WAIT_REGISTRATION.md)、決定済みの[利用条件](TASK_CONTROL_USAGE_CONDITIONS.md)、[判断記録D03〜D08](CORE_EXTENSION_DESIGN_DECISIONS.md#利用者の決定2026-11-24)である。D06のEXTENSION所属、graphics単独時の明示併用、-282を公開値として確定しない方針は再選択の対象にしない。

以下の根拠表は設計時点の調査内容である。公開対応表・ラッパー等の実装結果は[1379の実装記録](TASK_CONTROL_IMPL_1379.md)に従う。

| 読み取った根拠 | 確認した内容と公開APIへの接続 |
|---|---|
| `src/core/task_snapshot.zig` | Manager.capture、Snapshot.admit/release、FreshVm.resolve。復元版の検索順で入口名を解決する。設計時点では公開Snapshot IDは未実装であった |
| `src/core/task_transfer.zig`、`task_job.zig`、`task_job_queue.zig` | 入力の所有コピー、新規VM、入口の実行、結果の深さ・範囲検査。内部のバイトABIを公開APIの基準とする |
| `src/core/task_permissions.zig`、`task_policy.zig`、`task_memory.zig`、`task_context.zig` | allow/memory/deny、静的到達検査、実行時のアクセス検査、workerスレッドでの投入拒否。HELP上の分類だけでは許可を保証できない |
| `src/core/task_ledger.zig`、`task_results.zig`、`task_queue.zig`、`task_cancel.zig` | 外部有効性と内部参照、終端不変、非消費コピー、キュー期限、取消し要求と実際の停止を分ける |
| `src/core/task_schedule.zig`、`task_schedule_host.zig` | 用途・streamによる差替えと逆圧、所有者検査、結果依存の拒否、段階的な結果公開。公開ラッパーへ用途情報を渡す必要がある |
| `src/core/task_wait.zig`、`task_paint.zig`、`src/host_task_wait.zig` | 全成立集合、単一期限、世代・対象寿命、入力/I/O/タスク/時計と別の描画条件。Zig enumの序数は公開しない |
| `src/core/task_reap.zig`、`src/host_task_reap.zig`、`src/host_task_stop.zig` | 所有者終了、QUIT/BYE、復元、停止未確認時の保持と診断。RELEASEを同期joinにしない |
| `src/core/runtime_base.zig` | 内部Handleはepochとserialの各u64。公開セル表現は2.1節で決定した |
| `src/core/help_text.zig`、`words_process.zig`、`words_files.zig`、`memory_map.zig`、`defs.zig` | PROC-STATUS/WAIT/FREEの命名・ior、論理アドレス、errno由来ior、既存THROW表 |
| [全語リファレンス](WORD_REFERENCE.md)、[日本語版](WORD_REFERENCE.ja.md)、[表記ガイド](WORD_REFERENCE_GUIDE.md) | 左がスタック下部、1セル8バイト、addr uはバイト列。旧登録も残した全登録の一覧と、公開語・内部補助語の区別 |

標準の根拠はForth 2012 [9.3.1 THROW values](https://forth-standard.org/standard/exception)、[11 File-Access](https://forth-standard.org/standard/file)である。標準のTHROW範囲は-255〜-1、システム用は-4095〜-256である。タスク語はforthz独自拡張であり、標準語とは表示しない。文字列と識別子の表記を参考にする。[Gforthの例外処理](https://www.complang.tuwien.ac.at/forth/gforth/Docs-html/Exception-Handling.html)で説明される、iorを検査するかTHROWへ渡す慣習を参考にする。Gforthのタスク互換性を主張せず、コードや実装例は転載しない。

## 2. 共通表現と失敗の方針

### 2.1 ハンドル、状態、フラグ

Snapshotを `snap`、タスクを `task` とし、それぞれ1セルの不透明な正のIDで表す。0は無効値とする。メイン所有の対応表でIDを内部HandleまたはSnapshot参照へ写像し、種別・所有者・世代を検査する。内部ポインターや配列添字を公開しない。IDはプロセス中に再使用せず、符号付きセルの正数範囲を使い切れば作成を拒否する。辞書イメージへのID保存や別VM・別起動への転送をサポートする契約は設けない。同一起動内ではVM間の数値一致だけで通さないため、発行元をプロセス内で共通とし、所有者も検査する。単なる1セル整数から別起動由来かを完全に判別する保証はできないため、再起動をまたぐ古いIDの一致防止まで要求する場合は、起動識別情報を含む別表現・発行方式を先に決める必要がある。内部Handleにも起動をまたぐ一意性の確定契約はない。これは追加する公開対応表の要件であり、既存内部APIの実装済み機能ではない。

代替案は `( epoch serial )` の2セルである。内部タスクHandleを忠実に表せるが、Snapshotにも種別付きの対応が必要で、各語のスタックが長くなる。1セル内へepoch/serialをビット分割する案は枯渇条件を追加するため推奨しない。IDのDUPは所有参照を増やさず、RELEASEで複製も一括して無効になる。

| 公開状態 | 値 | 定数名 | 意味 |
|---|---|---|---|
| 無効な出力の埋め値 | 0 | 定数は不要 | iorが非0のときだけ使う。createdやreleasedを示す状態ではない |
| 投入済み | 1 | TASK-QUEUED | 受理済みで実行待ちである |
| 実行中 | 2 | TASK-RUNNING | 開始前検査・実行・完了封印を実行側が担当する |
| 成功 | 3 | TASK-SUCCEEDED | 必要な結果コピーを含む成功が確定した |
| 失敗 | 4 | TASK-FAILED | 実行失敗等が確定した |
| 取消し | 5 | TASK-CANCELLED | 未実行の排他的な取消し、または取消し専用帰還が確定した |

定数は `( -- state )` とする。値を明記してZig enumから独立させる。created、待機登録、回収中、停止未確認、RELEASE済みは追加状態にしない。取消し要求は別の `flag`（偽0、真-1）で返す。

### 2.2 iorとTHROW

通常のAPI失敗を末尾の `ior` で返す方式である。成功0、失敗は下表の負値とし、必要なら呼出し側がTHROWへ渡す。キュー満杯や容量不足を例外だけで処理させない。呼出しの失敗、待機期限、対象タスクの失敗・取消しは別に表す。タスク失敗を照会できた場合、照会自体のiorは0である。

呼出し側のスタック不足は既存のスタック例外、論理メモリ範囲不正はTHROW -9、数値引数不正はTHROW -24、除外機能の操作口がない場合はTHROW -21、実端末のCtrl+CはTHROW -28とする。THROW前に入力引数を失わず、副作用・部分コピーを起こさない。Ctrl+Cでも対象を自動取消しせず、複合待機の登録は解除する。

| ior | 記号名 | 用途 |
|---|---|---|
| -300 | TASK-E-HANDLE | 0、古いID、別所有者、別種別 |
| -301 | TASK-E-FULL | 台帳・キュー・Snapshot本数の満杯、逆圧 |
| -302 | TASK-E-STALE | 辞書構造変更後のSnapshotによる新規投入 |
| -303 | TASK-E-ENTRY | 復元版に入口名がない |
| -304 | TASK-E-DENIED | 許可集合外、workerからの操作、禁止された結果依存 |
| -305 | TASK-E-LIMIT | 入力・結果・Snapshot・総量上限 |
| -306 | TASK-E-NOT-READY | 未終端のRESULT/診断照会 |
| -307 | TASK-E-SHORT | 出力容量不足。必要量を返し、出力領域を変えない |
| -308 | TASK-E-ABI | 結果の深さ・範囲・長さ等の規約違反を示す診断値 |
| -309 | TASK-E-BUSY | 不完全なコンパイル中のSnapshot取得等 |
| -310 | TASK-E-EXHAUSTED | ID・世代・参照数の枯渇 |
| -311 | TASK-E-NO-CAPABILITY | 描画待機能力や必要な対象がない |
| -312 | TASK-E-HOST | 時計・通知・OS処理・登録解除等の障害 |
| -313 | TASK-E-QUEUE-EXPIRED | キュー滞留期限超過の診断値 |
| -314 | TASK-E-STOP-UNCONFIRMED | 停止未確認の回収診断値 |

各記号定数は `( -- ior )` とする。実行時に生じたABI違反・上限超過・キュー期限超過はfailed終端と主診断へ記録し、後日のSTATE成功を非0にしない。取消し自体の数値例外は公開しない。

衝突確認の範囲は現チェックアウトの `defs.zig` のTHROW表と `memory_map.zig` のior変換、およびsrc内の候補数値検索である。既存の独自THROWは-256〜-282にあり、errno由来iorは `-512 - errno`（非負errnoなら-512以下）である。決定した-300〜-314はこれらにも標準予約-255〜-1にも重ならず、システム用範囲内である。数値に偶然一致する浮動小数点テスト値は割当とみなさない。-282は内部TaskCancelledの表に残るが、`task_policy.numeric_throw_codes`から除外されており、公開取消し値へ転用しない。確保失敗には既存の-257、その他のVM実行エラーの診断には既存の公開THROW値を利用する。内部Zig errorの番号をそのまま公開しない。

代替は既存errnoへ寄せる案、または全失敗を即THROWする案である。前者はSnapshot失効・許可拒否の意味が失われやすく、後者は逆圧・再試行が扱いにくいため、専用iorを採用した。将来の登録時には例外表・メッセージと割当範囲を再照合する。本書は範囲の予約操作を行わない。

## 3. 公開操作とスタック効果

各行の先頭の語名を採用した。代替名は比較記録であり、登録対象ではない。全操作はメイン側から呼ぶ。ハンドルは2.1節、状態は同表、失敗は2.2節を共通契約とする。正常なior帰還では入力を消費し、出力数を固定する。ior非0では通常出力を0で埋める。ただし容量不足のneeded、待機時の保存済み成立集合・flagsは後述の例外である。

| 操作 | 語名（採用／比較した代替） | スタック効果 | 成功と通常の失敗 |
|---|---|---|---|
| Snapshot取得 | TASK-SNAPSHOT / TASK-SNAPSHOT-NEW / TASK-CAPTURE | `( -- snap ior )` | 明示版を取得。FULL/LIMIT/BUSY/EXHAUSTED/-257 |
| Snapshot解放 | TASK-SNAPSHOT-RELEASE / TASK-SNAPSHOT-FREE | `( snap -- ior )` | 外部参照を無効化。実行中の内部参照は保持。HANDLE |
| 投入 | TASK-SUBMIT / TASK-START / TASK-RUN | `( snap name-addr name-u input-addr input-u profile stream -- task ior )` | 入力をコピーし受理後だけIDを返す。HANDLE/STALE/ENTRY/DENIED/FULL/LIMIT/EXHAUSTED/-257 |
| 状態照会 | TASK-STATE / TASK-STATUS | `( task -- state requested result-u diag-u ior )` | 非消費。未完了時の量は0。HANDLE/HOST。result-uは成功結果量、diag-uは主診断文の量 |
| 取消し | TASK-CANCEL / TASK-REQUEST-CANCEL | `( task -- ior )` | 要求受付。終端済みなら無変更で0。HANDLE/HOST |
| 単独待機 | TASK-WAIT / WAIT-TASK | `( task ms -- state wait-flags ior )` | 終端または期限で返る。期限だけなら現状態と期限bit、ior=0。HANDLE/HOST |
| 結果取得 | TASK-RESULT / TASK-RESULT-COPY / TASK-READ-RESULT | `( task addr capacity -- needed state ior )` | 成功終端の結果を全量コピー。SHORT時neededとstateを返す。未終端はNOT-READY。失敗・取消し終端ならneeded=0、stateとior=0、コピーなし |
| 診断取得 | TASK-DIAGNOSTIC / TASK-ERROR / TASK-DIAG | `( task which addr capacity -- needed code ior )` | which=0主、1副、2Writer障害、3回収診断。未終端はNOT-READY（回収診断は存在すれば照会可）。診断なしはneeded=code=0。SHORT時needed/code保持 |
| タスク解放 | TASK-RELEASE / TASK-FREE | `( task -- ior )` | 外部ID無効化＋未終端なら取消し要求。同期joinしない。HANDLE。通知障害時も無効化済みならHOSTを返し、再利用せず内部回収を継続する |
| 複合待機 | TASK-WAIT-MANY / WAIT-EVENTS / WAIT-SET | `( targets count events capacity ms -- n wait-flags ior )` | 5節の集合を返す。HANDLE/FULL/NO-CAPABILITY/HOST。容量は対象数以上を事前要求し、不足ならSHORT、n=必要レコード数、登録なし |

解放処理の受理前の検査失敗は無副作用である。受理後の通知障害を「IDがまだ有効」と解釈させないため、RELEASEのHELPには上記の境界を明記する。Snapshot解放は参照を落とす操作であり、実行中の版の即時破棄ではない。全操作でIDの複製や数値加算による資源作成はできない。

診断文字列はUTF-8のバイト列でNULを付けない。コード0は診断なしとする。取消しの主診断は状態5で識別し、code=0でも取消しと分かる。診断バッファ確保不能でも状態とコードを保持する。result-uが0でも成功した空結果と、未終端・失敗をstateで区別する。内部のWriter出力は結果バイト列に混ぜず、初期許可集合で出力語を禁止するため、通常利用向けの出力取得語は初期版に含めない。

## 4. 入口と入力・結果

入口はソースから名前を構文解析する方式ではなく、`name-addr name-u` で渡す。保存済みSnapshotを新規VMへ復元し、その版の検索順と既存の名前照合規則で `FreshVm.resolve` する。空名は引数不正とし、NUL終端を要求しない。名前と入力はSUBMIT帰還後まで借用しない。メインのxt・論理アドレス・ホストポインターをworkerへ直接渡さない。代替のxt方式は復元版との対応と失効契約を別途要する。任意ソース文字列のEVALUATE方式は初期版から外す。

入口ABIは `( input-addr input-u -- result-addr result-u )` である。どちらのアドレスもworker自身の論理メモリを指す。入力は新規VMのデータ領域へコピーし、結果は停止後、データ領域内の範囲から管理側へコピーする。帰還時のデータスタックは正確に2セル、浮動小数点スタックは空、実行・リターン等の状態は `task_transfer.resultBytes` の条件に従う。heap、locals、system、block領域を結果として返さない。空結果でも有効なデータ領域内のアドレスを返す。入力や結果の中の数値をメインVMの参照として自動再配置しない。

上限は既決定の入力1件2 MiB、結果1件512 KiB、入力・結果の所有コピー総量16 MiB、診断1件16 KiB・総量1 MiB、Snapshot1版4 MiB・生存3版、台帳16件、worker 1、追加128 MiBである。個別用途には利用条件3節のさらに小さい上限を適用する。解放後も内部参照が残る資源と同時コピーを総量に数える。確認点のないnative処理は総量64 KiB/回以下であり、2 MiBの入力を一度のMOVE等で扱えるという意味ではない。

`profile` は0=G1、1=G2、2=T1、3=I1の定数（`TASK-G1` 等、`( -- profile )`）とする。待ち滞留期限は順に50/100/100/200 msで、WAITのmsとは別である。`stream` は呼出し側の非負1セルの計算系列IDとし、G1/G2のgame、T1のtuiでは所有者・種別・streamが一致する旧要求の差替えに使い、I1では順序を守る系列に使う。同じgame種別でもG1/G2を同時に残す場合は別streamを使う。profile引数を省いて固定値にする案より用途の制約を確認できる。内部Requestのkind/stream/millisecondsへの変換は公開ラッパーで追加する必要がある。

投入の失敗では旧要求と入力の所有を保つ。成功後も入力は呼出し側の所有であり自由に変更できる。結果は非消費で、TASK-RESULTの再取得を許す。容量不足で部分コピーせず必要量を返す。0容量の量照会は非空結果ならSHORT、空結果なら0となる。投入や待機を使って他タスクの未完了結果へ暗黙に依存する機能は初期版に設けない。

通常の変数変更では旧Snapshotを明示利用できる。FORGET・MARKER・完全復元後は旧版による新規投入を拒否し、実行中の版は保持する。最新値が必要なら明示的に再取得する。解放済みタスクからの結果取得は不可である。

## 5. 複合待機の契約

呼出しごとの配列登録とする。公開の永続WaitSetハンドルを増やさず、`TASK-WAIT-MANY` の中で検査→保持→登録→全件再照会→共通待機→再照会→解除を行う。戻る経路とTHROWの経路で解除を完了する。永続集合をNEW/ADD/REMOVE/FREEで操作する代替案は、反復登録を避ける候補にはなるが、所有・解除・メモリ予算の契約が増えるため後続とする。登録費用の大小は本書では評価していない。

対象レコードは5セル `( kind id arg0 arg1 tag )`、結果レコードは4セル `( index tag reason detail )` とする。配列はセル境界に整列した論理メモリで、件数はバイト数ではない。公開サイズ定数 `TASK-WAIT-TARGET-CELLS` と `TASK-WAIT-EVENT-CELLS` はそれぞれ `( -- u )` で5と4を返す。生のZig struct配置をコピーしない。対象と出力の領域重複は拒否し、全範囲・件数・容量を副作用前に検査する。対象数1〜64、出力容量は対象数以上とする。余剰出力領域は変更しない。登録・結果の内部一時領域も追加128 MiB内で会計し、入れ子の同時登録は拒否する。64件は内部task_wait.capacityに合わせた公開上限であり、D07の決定済みタスク台帳16件とは別である。

| kind | id | arg0 / arg1 | 成立条件 |
|---|---|---|---|
| 1 入力 | 0（現在のメイン入力） | 0 / 0 | 意味上の入力、EOF、障害。入力本体を消費しない |
| 2 I/O | 既存fileid | 関心mask（読取1、書込2） / 0 | 可用・EOF・障害・close。fileidをタスクIDとして扱わない |
| 3 タスク | task | 0 / 0 | 成功・失敗・取消し終端、登録後の外部解放 |
| 4 時計 | 0 | 相対ms（非負） / 0 | 呼出し開始時の単調時刻から一度だけ作った個別期限 |
| 5 描画 | 0（ホスト自身のネイティブのウィンドウ） | shown（1セル） / 0 | 登録した世代・目標以上のbackend描画完了、解放、能力喪失 |

kind定数は `TASK-WAIT-INPUT` と同じTASK-接頭辞の形式とし、各々 `( -- kind )` で1〜5を返す。

2026-11-24にレモンはkind=5について次の契約を決定した。id=0は「ホスト自身のネイティブのウィンドウ」であり、現状では1つだけである。id≠0はTASK-E-HANDLE（-300）である。目標は `GFX-WINDOW-FRAMES ( -- shown painted-through )` のshown（1セル）をarg0に入れる。arg1は0に限り、非0ならTHROW -24とする。Tkの経路・ネイティブのウィンドウがない場合・graphicsを除いた構成ではTASK-E-NO-CAPABILITY（-311）である。タイマーで描画完了を代用しない。将来、表示先が複数になればidの意味を広げ、2セルの目標への拡張用にarg1を残す。files除外時のkind=2もTASK-E-NO-CAPABILITYで拒否する。

`tag` は利用者の任意1セルであり、そのまま返す。`index` は対象配列の0始まり添字である。ID自体を返さなくてもindex/tagから元の対象へ対応できる。複数の理由が同一対象で成立した場合は、reasonをbit集合で返すため、1対象1レコードで足りる。同時に成立した全対象を添字順で返し、最初の1件だけに縮めない。入力・結果の取得、I/Oの実行成功を予約しない。

reasonは入力1、読取可用2、書込可用4、EOF 8、I/O等の障害16、close 32、成功64、失敗128、取消し256、対象解放512、個別時計期限1024、描画完了2048、能力喪失4096とする。`TASK-EVENT-*` 定数（`( -- mask )`）を用意する。detailは通常0、障害時は公開診断コードとする。i128の内部detailや絶対時刻は1セルへ切り詰めず、必要な情報だけをkind別に変換する。

全体の `wait-flags`は期限1、待機側取消し2、中断4、ホスト障害8の独立bitで、`TASK-WAIT-EXPIRED` 等の定数（`( -- mask )`）を付ける。OS待機中の実Ctrl+Cは-28を優先し、解除してからTHROWする。内部待機側中断を通常帰還できるadapterでは中断bitを返す。ホスト障害はHOSTのiorも返し、既に安全に保存したn件・flagsを残す。成立集合と全体期限を同時に返せる。単独WAITも同じflagsを使い、タスクのrequestedと待機側取消しを混同しない。

ms=0は全対象を一度照会するpoll、ms<0は全体期限なし、ms>0は呼出し開始時からの単一期限とする。内部の再試行で期限を延長しない。個別時計期限は全体期限と別の対象である。期限到来はタスクを取消しにしない。登録後の対象解放・closeは対応する対象のイベントとして返し、登録前に無効ならHANDLE等で全体を拒否する。重複対象は別indexとして保持し、同じ成立を各々へ返す。解除不能なら保持参照と回収責任を残し、HOSTで診断する。

## 6. workerの初期許可集合の示し方

HELPのworker欄は8節に従う英語表示とし、日本語の許可・条件付き・不可の説明は全語リファレンスの日本語版に載せる。条件付きには論理領域・書込可否・native総処理量の制限を記す。許可語名一覧を `task_permissions.policy` とbuiltin名の対応から作り、除外語群を反映する。分類表は必要条件であり、入口からの静的到達検査・最適化後Op検査・実行時の境界検査を通ることまで保証しない。登録されていない語や将来の語は既定で不可とする。

算術・比較・スタック操作・BEGIN系を基礎とし、メモリ操作は監査済み範囲に限る。動的実行（EXECUTE、DEFER、DOES>等）、CATCH/THROW、workerでの652予算・trace/profile/step、PAD、未許可のDO系、解釈・コンパイル・辞書変更、入力・表示・音・ファイル・SYSTEM、タスク投入・タスク間待機は初期不可である。解除は機能ごとの利用者判断を要する。「Forthの計算語ならすべて使える」とは記載しない。

公開前に英日で同じ許可表を確認し、代表的な許可入口と拒否入口を文書例へ載せる。許可一覧の表示専用語を追加する代替案は、後から検討できる。初期版では表示専用の語を作らず、文書・HELPで示す。

## 7. 所属語群と構成

既決定のEXTENSION所属に従う。決定した語と定数はEXTENSIONへ置き、利用者には `REQUIRE-EXTENSION` と `ALSO EXTENSION` によるロード・検索順の指定を示す。graphics単独構成では明示的なextension併用が必要であり、graphics/audioから自動で有効化しない。

extension除外時はタスクの公開語・定数を登録せず、その語を含むイメージは既存の除外builtin検査方針に合わせて拒否する。内部Runtimeの型を他語群が利用することと、公開タスク機能の有効化を分ける。help除外でもタスク機能の意味は変えず、HELP表示だけを除く。graphicsなしでは描画対象だけ、filesなしではI/O対象だけを拒否し、計算タスクや入力・時計待機を自動的に除かない。構成動作の実確認は1379後の1381等で行う。

## 8. HELP・英日全語リファレンスの方針

2026-11-24にレモンはHELPを既存どおり英語だけと決定した。worker行も `worker: allowed` / `worker: conditional (...)` / `worker: forbidden` / `worker: depends on definition` の英語だけとし、タスク機能のある構成（EXTENSION有効）でだけ表示する。コロン定義の語は `worker: depends on definition` と表示する。日本語の説明は `docs/WORD_REFERENCE.ja.md` に載せる。ユーザーマニュアルの英日版のHELP説明は更新済みである。HELPと英日全語リファレンスの語名・スタック欄・数値・単位・成功条件を一致させ、日本語は「だ・である」調とする。各語には所属、メイン専用、コピーと借用、解放条件、非消費か否か、iorとTHROW、未完了/失敗/取消しの区別、上限、除外構成を記す。RELEASEには停止完了ではないこと、WAITには取消し要求を出さないことを短く明記する。

説明の例は次のとおりである。英語はHELPと英語版全語リファレンス、日本語は日本語版全語リファレンスに載せる。

- TASK-CANCEL 英：Request cancellation without waiting for termination. A successful request does not establish a cancelled outcome.
- TASK-CANCEL 日：終了を待たずに取消しを要求する。要求の成功だけでは取消し終端は確定しない。
- TASK-RESULT 英：Copy the retained successful result without consuming it. A short buffer returns the required byte count and leaves the destination unchanged.
- TASK-RESULT 日：保持された成功結果を消費せずコピーする。容量不足では必要バイト数を返し、出力先を変更しない。

全語リファレンスは既存の生成元・レビュー手順に合わせ、既存の旧登録と新登録、定数、内部補助語を含む全語を保つ。英日版で公開/内部を同じ分類にする。新語は実装後に生成し、APIの決定だけを実装済み一覧へ混ぜない。例はSnapshot取得→投入→状態/待機→結果→両方の解放を示し、空結果、SHORT後の再取得、取消しと正常帰還の競合、複合待機の同時成立も扱う。英日READMEには最小例と制限の要点、詳細文書へのリンクを置く。CATCH等を使う後始末例はメイン用であると明記する。

## 9. 利用者の回答（2026-11-24）

レモンは2026-11-24に、問1〜10すべてで推奨案（A）を採用した。各問の比較理由を以下に残す。回答は公開APIの決定であり、実装・登録・検証の完了を示さない。

1. ハンドルは1セルの不透明IDとするか。推奨は1セルである。既存PROC系と同じ扱いやすさを保ち、内部のepoch/serialは対応表で検査できるためである。代替は2セルである。保証範囲は同一起動内とし、別起動の古い数値まで識別する必要がある場合は表現案を再検討する。 **回答（2026-11-24）：推奨案（A）を採用する。**
2. 通常失敗はior、引数・メモリ・機能・Ctrl+Cは2.2節のTHROWとするか。推奨は併用案である。再試行とプログラム異常を分け、必要時にiorをTHROWへ渡せるためである。 **回答（2026-11-24）：推奨案（A）を採用する。**
3. 専用iorを-300〜-314の表で割り当てるか。推奨は表の範囲である。標準・既存独自値・errno由来値と重ならず、-282を公開しないためである。 **回答（2026-11-24）：推奨案（A）を採用する。**
4. 状態は1〜5の固定値と別の取消し要求flagで示すか。推奨は2.1節である。終端と要求、外部解放と内部回収を混同しないためである。 **回答（2026-11-24）：推奨案（A）を採用する。**
5. 入口名の文字列とバイト列ABIを4節の形とするか。推奨は名前での解決とコピーである。Snapshotの版を明示でき、メインのxtやアドレスを転送せずに済むためである。 **回答（2026-11-24）：推奨案（A）を採用する。**
6. SUBMITにprofileとstreamを明示するか。推奨は4節の形である。既決定の用途別上限・滞留期限・差替えを内部スケジュールへ対応させるためである。設定レコードは比較した代替であり、採用しない。 **回答（2026-11-24）：推奨案（A）を採用する。**
7. 結果と診断を別語で非消費取得し、容量不足は全量未コピーとするか。推奨は3節である。再取得でき、成功結果と主・副・回収診断を分けられるためである。 **回答（2026-11-24）：推奨案（A）を採用する。**
8. 複合待機は呼出し単位の配列登録と全成立集合の返却にするか。推奨は5節である。永続ハンドルの寿命管理を増やさず、同時成立・期限・障害を保持できるためである。レコード幅、kind/reason/flagsの値も同節の値で決定した。 **回答（2026-11-24）：推奨案（A）を採用する。**
9. 操作語名は3節の先頭候補に統一するか。推奨はTASK-接頭辞である。Snapshot・状態・待機・解放の所属を見分けやすく、汎用STATEやFREEとの混同を避けられるためである。定数名も同じ接頭辞を用いる。 **回答（2026-11-24）：推奨案（A）を採用する。**
10. worker制限はHELPの三分類と全語一覧で示すか。推奨は6節である。個々の語の制限と入口全体の検査を併記できるためである。8節の説明・例の方針も採用した。HELPの表示言語は同節の追加決定に従う。 **回答（2026-11-24）：推奨案（A）を採用する。**

1379の公開ラッパー・登録・エラー報告の実装、英語HELP・英日全語リファレンス・READMEの反映と整合確認は完了した。実施結果は[1379の実装記録](TASK_CONTROL_IMPL_1379.md)に従い、1380〜1383の結合・構成・実機確認とは別に追跡する。

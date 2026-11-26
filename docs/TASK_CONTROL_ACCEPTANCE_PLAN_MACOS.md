# 1383 タスク制御 06-G macOS 実機受入れ計画 v6

2026-11-25、準備者ロク、実機実行者Claude、判断者レモン。この改訂での本測定は未実施。
2026-11-25の決定Bに従い1382 v4と同じhold方式を採用した。今回の対話測定は1382 v5に合わせる。本書のSHA-256は [実装報告書](TASK_CONTROL_IMPL_1383.md) に固定する。

対話の workloads は単独の計測用ビルド（task-acceptance=true、task-trace=false、task-native-probe=false）を使う。ワーカーの組み込み語ごとに実行される native 取消し位相の観測をコンパイル時に外す。D07の始点・終点、管理巡の全標本、題材・供給間隔は維持する。下表の各10分×1回は1 runあたりの回数である。今回のworkloads再測定は6題材を独立した新規runで2回（60分×2）実行し、旧版と合算しない。取消し位相の測定には従来どおりnative観測を含むビルドを使う。

## 1. 適用範囲と事前確認

対象はMacBook Air、Apple Silicon arm64、macOS 27.2.1、Zig 0.17.1、Python 3.15.2（/opt/homebrew/bin）。環境情報はClaude確認済みとして依頼された値であり、ロクによる実機確認ではない。Claudeは実行時にも版・実体・アーキテクチャ、電源、負荷、端末、backend、表示周期を記録する。SSHではzsh -lcを使う。作業場所は ~/source/zig/ForthSigma。Rosetta/x86_64やfat実行体を混ぜない。

**レモンは2026-11-25に1382と同じ縮小回数を1383にも採用した。今回の改訂で回数は変えない。** 本書作成は測定の許可ではない。利用条件8節の正式な出発点（位相ごと1,000回、対話10分×3回）と区別する。確認参照を --confirmed に記録し、実施前に他アプリの停止を依頼する。変更があれば本書を改訂して再固定する。

根拠は [詳細計画13節](TASK_CONTROL_DETAILED_PLAN.md#13-必須の検証項目)、[D07利用条件](TASK_CONTROL_USAGE_CONDITIONS.md)、[1382固定計画](TASK_CONTROL_ACCEPTANCE_PLAN.md)（SHA-256 c45a98503ee4939ddd2518377ee721e70656b38af5ebc4a9d3af61de083e4dcb）。1382計画の3節の入力・供給頻度・題材順、4節の区間・目標・位相判別、5節の基準/負荷停止点、6節の欠測/集計、9節の固定条件を、本書のOS・時計・メモリ・回数・対照Aの記述で置き換える箇所以外は適用する。既存Windows/Linuxの結果・合否はmacOSへ転記しない。

## 2. 固定と構成

.gitattributesで本書を-textとする。Claudeは報告書の固定文字列とshasum -a 256の実値を比較し、不一致なら停止する。直前の実値を期待値に代入しない。Darwin上のrunnerの既定計画は本書であり、--planでも明示できる。子を起動する前とrun終了時に照合し、同じバイト列の計画コピー・SHAを保存する。

runは .work/acceptance/<UTC>-<unique>/。HEAD、git status、追跡済み/新規ソースmanifest、runner/probe/fixtureのハッシュ、Zig版・実体ハッシュ、ビルドコマンド、実行体ハッシュ、OS/CPU/Python、親時計・TTY、JSON/JSONL、生ログを保存する。異なるOS・構成・入力・位相・回数・改訂前後を合算しない。中断・欠測・変更は合格にしない。

A/Bともnative arm64、ReleaseFast、debug=false、strip=true、既定語群・VM容量。worker 1、待ち4、台帳16、追加予算128 MiB。通常の起動・size・入力→状態・手動はtask-trace=false/task-acceptance=false。内部区間はtask-trace=false/task-acceptance=trueの通常経路probe。06-H traceは別run、参考専用。通常経路へ命令ごとの定期確認を追加しない。

## 3. 初期の回数と追加規則

| 項目 | 縮小案の初期値 |
|---|---|
| 生成/実行取消し | 25対象位相×各100要求試行 |
| native取消し | FILL/MOVE/COMPARE/SEARCH/ROLL、5種×直前/実行区間/直後×各100要求試行 |
| 待ち取消し | 100回 |
| Snapshot | 独立100プロセス、各3取得（3,000,000 bytes題材、実image bytes記録） |
| 対話 | G1開放/壁/蛇行、G2、T1、I1、入力→状態、各10分×1回、計70分 |
| メモリ | 同じ7題材の基準/負荷、各3回 |
| 起動/size | A/B各5 warmup＋100回、AB/BA交互。size各1生成物 |

有効標本の最大が目標の80%を超えたcase/位相/metricは、取消し・Snapshotは追加1,000回、対話は当該case10分を独立2回追加、メモリは当該case追加10回。元runを保持し追加理由・参照を新runへ残す。遅い値を除外せず、成功数に達するまで補充しない。追加後も80%超・欠測・超過があれば原因確認と再計画が必要。中央値（偶数は中央2値平均）・nearest-rank p95・最大・超過件数・欠測を分離する。

## 取消し位相の改訂（2026-11-25、決定B）

レモンは、3 OSとも生成段階を狙った取消しの約7割が対象を取り逃し、nativeのFILL・SEARCH・ROLLでは最初の3回とも取り逃して打ち切った結果を受け、「B: 段階を確実に狙える測り方に変えて、測り直す」を採用した。回数は変更しない。Windows・Linux・macOSそれぞれ生成25段階、native 5種×3位相、待ち中の計41ケースを各100試行（4,100試行/OS）で新runへ採取する。旧runの有効値・欠測・超過は保持し、新方式と混ぜない。既存の他群の追加規則も消さない。

`-Dtask-acceptance=true`だけで、workerは対象段階を固定領域のatomic `hold_stage`へrelease-storeし、取消しtokenをacquire-loadして待つ。ホストのTASK-STATEによる巡回が到達を確認すると、Forthスタック上の同じtask idを使って公開語TASK-CANCELのハンドラーを呼び出す。取消し経路を別実装しない。requestedはそのTASK-CANCEL入口、stoppedはrunner帰還、reclaimedは従来どおり物理handback・所有資源とslot回収後。hold待機はrequestedより前に置かれるので要求→停止/回収へ加算しない。到達からtokenまでのholdは実時計で最大5秒（OSによる実行待ちを除く）、時計異常も解除して欠測にする。ホストが要求しない場合は時間切れで再開し、BYEのshutdown取消しtokenでも解除する。段階通過時に繰り返しholdしない。

生成各段階およびnative before/afterは到達した位置でholdする。native_runningは**実処理中の要求ではなく、事前確認後の入口でholdし、要求後にnative全体を実行する保守的な代替**を採用する。理由は、短い非分割nativeの内部に停止点を追加せず、外側から要求を確実に重ねることはできず、旧方式では取り逃しが残るため。入口は既存checkpointの後、次のcheckpointはnative直後にあり、holdはtoken確認後にエラーを返さず通常処理へ戻る。最大量のnative全体が要求→停止に含まれるため、途中で要求する場合の残仕事量を上から覆う検証になる。ただしOSのスケジューリングを含む全入力・全実行の最悪遅延を証明するものではない。method=`guarded-native-entry-full-call`と記録し、実際のduringを観測したと表現しない。

最大量の題材はFILL 65,536 bytes、MOVE 32,768読＋32,768書、COMPARE各32,768（同値の領域）、SEARCHは65,535 bytesのaと末尾に置く1 byteのb（不一致で全文走査、領域合計65,536、仕事量65,535）、ROLLは8,192 cells=65,536 bytes。SEARCHの旧256×256は最初の候補で一致するため全文走査を検証できず変更した。ROLLの旧4,000 cellsは64KiB未満なので、native-rollプロセスだけ`--data-stack-size 16384`を付け、8,191 ROLLを実行する。他の題材の容量は従来どおり。回数は変えず、題材・構成の差はmanifestとcommandに保存する。D07の64KiB/回以下と要求→停止10msをこの全量実行で照合する。

phase_okはhold_stage、要求直前に保存したrequest_stage、指定段階の3つが一致し、hold_timeout=falseの場合だけtrue。待ち中はqueued=trueと未実行（request_stage=api_entryの初期値）を確認する。native境界の時刻は残すが、同時刻による区間推定から位相を決めない。smokeでも全位相のphase_okを保存し、端点は0、速度統計は空のままにする。holdの時間切れ・時計異常・位相不一致・task行欠落は理由付き欠測とし、速度標本に使わない。最初の3回での打切りと250msの観測窓は廃止する。全100試行を記録し、成功数までの補充はしない。nativeの出力観測guardは6秒、プロセスの異常停止guardは120秒で、いずれも速度標本ではない。

通常ビルドではenabled=falseのcomptime分岐、空のStorage、voidのtoken付帯フィールドによりholdを除去する。通常経路の変更有無は同条件のReleaseFast/debug=false/task-trace=false/task-acceptance=falseで変更前後の.textを比較して確認する。検証では取消し成功、要求なしの5秒時間切れ、要求なしのBYE終了を短い動作確認として実施する。本測定はClaudeが担当する。


## 4. 時計と端末なしの実行

Zigのtask_acceptance.nowはhost_clock.nowを使う。macOSの非Windows経路はclock_gettime(CLOCK_MONOTONIC)。probe開始時に同じ時計のclock_getresを一度読み、ACCEPTANCE行にclock/monotonic/resolution_nsを記録する。時計読取り失敗や0の端点を成功値にしない。分解能は表現単位1nsや実効精度と同一ではない。

Pythonの起動・入力→状態はperf_counter_ns、試行費用・期限はperf_counter。runnerはget_clock_info("perf_counter")のimplementation/monotonic/adjustable/resolutionをresults.jsonに保存し、monotonic=falseなら停止する。ZigとPythonの時計を引き算しない。smoke・メモリ専用の内部端点は0、速度統計・目標比較は作らない。trial_wall_secondsは準備費用専用。

子のstdinはPIPE、出力はraw.logまたは背景readerによるPIPE受信。Windows専用selectは使わない。kill後はwaitし、reader/samplerをjoinしpipeを閉じる。workerは同一プロセス内のthreadであり個別joinを回収時刻に代用しない。ClaudeはSSHのTTYなしsmokeで入力注入・q・メモリ保持点の改行応答・終了を確認する。実端末での入力/画面/復帰は別の手動確認とする。

## 5. macOSメモリの定義

ctypesで/usr/lib/libproc.dylibのproc_pid_rusage(pid, RUSAGE_INFO_V4, buffer)を使い、ri_resident_size（常駐bytes）とri_phys_footprint（物理フットプリントbytes）を採る。ri_lifetime_max_phys_footprintは参考値として残すが基準との差分ピークには使わない。仮想サイズは同じlibprocのproc_pidinfo(PROC_PIDTASKINFO)のpti_virtual_size（bytes）で採る。2呼出しは原子的な同時標本ではない。API失敗/短い読取りは欠測とし、RSS等へ暗黙の代替をしない。

rusage_info_v4はUUID16 bytes＋uint64_t 35個、sizeof=296、resident offset=64、phys_footprint=72、lifetime_max=240、末尾runnable_time=288。proc_taskinfoはsizeof=96、virtual offset=0。根拠はAppleの [sys/resource.h](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/resource.h)、[sys/proc_info.h](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc_info.h)、[libproc.h](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.h)。PythonにSDKの順序を明記した。Claudeは実機のxcrun SDKに対するacceptance-macos-abi.cのstatic_assertを先に実行し、SDKパス・ヘッダハッシュも保存する。違えば測定を停止し、配置を確認する。公開ヘッダの参照は実機SDK一致の証拠にはしない。

| macOSの保存値 | Windows/Linuxとの関係 | 128 MiBの扱い |
|---|---|---|
| process_resident_bytes | WorkingSetSize / smaps Rssに相当する常駐の観測。完全な同一定義ではない | 参考、合格上限にしない |
| process_phys_footprint_bytes | Windows PrivateUsage、Linux accountable mapping Sizeと同一ではない。物理課金量を別名で保存 | 基準/負荷差を128 MiBの目安と比較し、80%超の追加規則を適用 |
| process_virtual_bytes | 仮想空間サイズ。Windows reserve+commit / Linux smaps Sizeと同じ意味での私有予約保証ではない | 参考。128 MiBと直接比較しない |

※推測です：macOSでの追加負担の目安にはphys_footprint差が適すると考え、この計画では128 MiBとの比較対象にする。ただし私有コミット/予約の厳密な上限を証明しない。macOSの予約・コミット128 MiBの受入れ全体は、allocator上限の機能試験と追加のOS確認が必要であり、footprintだけで合格とはしない。

基準は同じmainデータと1世代Snapshot/初期化済serviceを保持した最後のBASELINE-READY標本だけ。負荷は10ms周期＋保持停止点のピーク。Snapshot負荷は追加2世代と取得中workspaceを含む。保持点は親が採取して改行応答後に再開する。メモリ専用は待ち期限120秒・内部時計0とし速度判定へ混ぜない。基準/負荷の最大差は観測差であり全確保境界の絶対ピークではない。エラー、保持点欠落、短命ピークの取りこぼしを残す。

## 6. サイズと対照A

sizeはthin Mach-O 64-bit arm64のLC_SEGMENT_64から__TEXT,__textのsection_64.sizeを読む。論理bytesとfile-backed bytes（通常の__textでは同値）と実行体全体bytesを別保存する。fat（32/64、両byte order）、非arm64、欠落/重複section、範囲外/破損command、file-backedでない__textは拒否する。

AはW1導入前35523f676836134c4fbaed19e3d01d2a23ec2a92。Macでのビルド成功は未確認。報告書のgit archive手順で別の作業配置へ展開し、同じZig 0.17.1/native arm64/ReleaseFast/debug=false/strip=true/既定語群・VM容量でビルドする。Aへ存在しないtask-trace/task-acceptanceは渡さない。ソースarchiveと実行体のSHA、コミット、SDK、Zig、コマンド、生ログを保存する。

Aがビルド不能/起動不能ならログと理由を保存し、startup・sizeのA/B比較を未確認のまま残す。別コミットやpatch版Aへの差替え、x86_64実行との比較、Bだけでの合格扱いは行わない。B単独の解析値は参考として区別できる。対照比較の未確認は他の機能検査の証拠を消さないが、1383全体の合格にはしない。A/A'/Bの通常VM・逆アセンブル採取もrunnerでは未対応でありAC-29全体の合格とはしない。

## 7. 実機の残りと所要時間

Claudeは [手動手順英語](TASK_CONTROL_ACCEPTANCE_MANUAL.md) / [日本語](TASK_CONTROL_ACCEPTANCE_MANUAL.ja.md) のAC-02/05/18/20/24/25をmacOSで実行し、AC-27（macOS実機）の内訳として記録する。foreground端末のキー、q/Ctrl+C後の端末復帰、所有process/thread/child、I/O、利用可能なnative backendを観察する。画面/音/複合資源の未実装fixture・利用不能機能は未確認のまま残す。SSH pipeの成功を実端末・物理提示の成功にしない。クロスビルドは実機受入れの代わりではない。

対話は計画上70分。native観測窓だけの最大は15×100×0.25秒=375秒（起動/回収/guardは別）。※推測です：自動検査・ビルド・smokeに20〜60分、本測定の短い群とAのビルド/比較に10〜30分、手動確認に15〜30分を確保し、全体は約2〜3.5時間を初期枠とする。Macの実測に基づく見積りではない。80%超の追加・ビルド失敗・原因調査・異常guardは別枠。smokeの準備費用で更新する場合も計画を先に改訂・再固定する。実行コマンドは報告書に記載する。

## tque 1396 revision

Reason: separate queue residence from submit preparation and execution. Task rows record submitted (submit entry), input_copied (owned input copy completed), enqueued (queue insertion under the gate), and acquired (physical worker ownership under the same gate). Limits: G1_enqueue_acquired_ns = 50 ms, G2_enqueue_acquired_ns = 100 ms, T1_enqueue_acquired_ns = 100 ms, I1_enqueue_acquired_ns = 200 ms. The existing per-case/metric 80% extension rule applies. Tasks removed before acquisition have no acquisition sample; they must not contribute zero residence. Invalid acquired endpoints remain missing evidence. Smoke retains zero timestamps and does not compute timing statistics.

Snapshot readiness is unresolved: USAGE_CONDITIONS section 6 specifies capture start to submission readiness within 100 ms, but STATE_MACHINE section 3 and PUBLIC_API_PROPOSAL sections 3-4 do not define an independent readiness condition. snapshot_main_ns measures API duration only. No snapshot_ready_ns or readiness verdict is produced pending a decision. This is a measurement gap, not evidence of compliance.

Trial counts, workloads, pacing and extension counts are unchanged. Old runs do not establish the newly instrumented intervals. Formal timing requires Lemon's confirmation and Claude's execution.


## 1394：ネイティブ窓の描画と終了（本版で追加）

本測定は利用者が時間の測定を承認してからClaudeが実施する。既存の回数・供給間隔・独立run数・80%規則は変更しない。短い動作確認を測定標本に数えない。前版のrunと混合しない。

`examples/task-native-path.fs`（G1、256×256開放盤面）と`task-native-search.fs`（T1、1MiBのa）は要求世代と採用した結果の世代を別々に窓内へ描く。n、a/bで差し替え、fでゼロ除算のworker失敗、qで終了する。`NATIVE-DRAW generation=… frame=… requested=…`を端末にも記録する。連続差し替え後に世代が逆行しないこと、失敗世代を描かず以前の結果を保持することを窓の中身と照合する。要求世代の反映とworker結果の公開所要時間を混同しない。

計測用ビルドは`-Dtask-acceptance=true -Dtask-trace=false -Dtask-native-probe=false`。`SIGMA_ACCEPTANCE_SMOKE=1`（既定）は時刻0であり集計しない。承認後の測定だけ`SIGMA_ACCEPTANCE_SMOKE=0`。PAINTTRACEは同一プロセスのQPC/CLOCK_MONOTONICナノ秒を使う。requestはネイティブフレーム番号の発行時、completeは既存backendの描画完了通知時（macOSは親がPAINTEDを処理した時）である。wait-register/wait-paintedはTASK-WAIT-MANY kind=5の登録とPAINTED観測。後続のpainted-through番号から未描画フレームの完了を補わない。固定リングが溢れた場合は欠測とする。

入力始点はホストがキーを取得した時（peekが先ならその最初の取得）で、NATIVE-INPUTの要求世代へ関連付ける。端末の終点はNATIVE-DRAW行をwriterから排出した時。非同期出力が残った場合は端点を記録せず欠測とする。端末エミュレーターがピクセルへ描く時刻は別途観察する。要求世代の窓反映は同じ行のフレームに対応するcompleteまで。画面33.34ms・端末50msの統計と超過数を保持する。キーの物理的押下、OSの入力待ち時間、compositorやパネルの発光時刻は含まない。D07で本作業が対象とする画面の終点はbackendの描画完了であり、物理提示の合格を主張しない。

最初のフレームは窓を開くため、生記録に残して定常60Hzの期限集計から除外する。2番目の要求を基点に、フレーム番号差から1/60秒の固定期限を算出する。全フレームの要求・完了・待ち端点、期限超過数を保存する。NV-BASELINEを真に定義した別起動では最初の結果だけ取得し、その後のtask投入を止め、同じ入力と描画処理を続ける。基準が周期内に収まる条件で、同じフレーム数・描画負荷・入力列の負荷あり実行と比較する。基準なし、条件不一致、欠測は追加フレームの合格にしない。基準と負荷で描く結果の形が異なる場合も、同一描画負荷を確認するまで比較を未確認とする。

手動確認は`manual-acceptance-tty.py --native-paint --cases native`。基準用の短い確認は同じ選択に`--native-baseline`を追加する。既存のJob/POSIX supervisorによる所有・回収・端末復旧の保護をそのまま使う。`task-native-bye.fs`は音・窓・Snapshot・実行中workerを残してBYEする。終了コード、所有したprocess/thread/window/audioの生存期間と終了を確認し、音が鳴り止んだことは人の聴取として別記する。macOSの短命の子孫は間欠採取だけで回収済みにしない。

既存ログの集計は`run-acceptance.py --mode smoke --only paint --paint-log <log>`（時刻の差分は計算しない）。承認済み非smokeログはmeasureと既存の`--confirmed`、本版`--plan-sha256`、`--paint-baseline-log`で取り込む。runnerは窓も測定も起動しない。統計が目安内でも目視・聴取・環境一致の未確認を自動で合格にしない。

## 60Hz期限の判定の改訂（2026-11-26、利用者の決定 案1、tque 1405・1406）

1394節の「2番目の要求を基点に、フレーム番号差から1/60秒の固定期限を算出する」積み上げ方式は、題材の描画ループの周期が16.67msをわずかに超えるだけで遅れが積み重なり、描画が間に合っていてもほぼ全フレームを超過と数える。Linux実機（2026-11-26）では、各フレームの要求→完了は1,200中1,199が1/60秒以内だったが、ループの平均周期が16.7〜17.6msのため、積み上げ方式では基準（タスクなし）でも1,200中1,106〜1,184が超過になった。

本版から、60Hzのフレーム期限は**各フレームの要求から完了までが1/60秒（16,666,667ns）以内か**で判定する。最初のフレームは従来どおり除外する。追加の超過は、同じフレーム数・入力数・キーの並びの基準と負荷ありの組で、負荷ありの超過数から基準の超過数を引いて求める。基準の超過が0であることは比較の条件にしない。積み上げ方式の超過数は、題材のループ周期の特性として結果に残すが、合否には使わない。

基準と負荷ありの組は、manual-acceptance-tty.pyで負荷ありを先に実行し、その結果（`--native-baseline-schedule`）を基準に渡して、同じフレーム番号で同じキーを送る（上限1,200フレーム）。基準ではタスクを投入せず、要求世代も進めない。基準の入力端点は数の照合だけに使い、入力→画面の統計は負荷ありの実行から求める。
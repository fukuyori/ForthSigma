# 1382 Windows・Linux受け入れ測定計画 v4（2026-11-25固定）

レモンの2026-11-24の判断を反映した縮小計画である。**利用条件8節の正式な出発点（各位相1,000回、対話10分×3回）とは異なる。** 結果にもこの区別を残す。本測定はWindows・LinuxともClaudeが行う。ロクは測定器の機能確認と試行全体の所要時間の見積りだけを行い、速度標本の採取・評価はしない。git commit・branch・push、tque変更は行わない。

## 1. 固定と保存

根拠は[TASK_CONTROL_USAGE_CONDITIONS.md](TASK_CONTROL_USAGE_CONDITIONS.md)3〜8・10節。報告書に固定したSHA-256の文字列を使用し、実行直前のファイルから期待値を再計算しない。`.gitattributes` の本書に対する `-text` によりGitの改行変換を禁止する。WindowsのGet-FileHashとLinuxのsha256sumを、それぞれ報告書の同じ固定値と比較し、不一致なら停止する。本書の最終SHA-256を固定後、測定コマンドの `--plan-sha256` に渡す。runnerは子プロセスを起動する前に一致を検査し、同じバイト列の計画コピーとSHA-256をresults.jsonへ保存する。終了時にも原本の一致を確認する。不一致、変更、中断、欠測を合格としない。fixtureは生成後にハッシュを保存し、当該run中は変更しない。

各runは `.work/acceptance/<UTC>-<unique>/`。ソースmanifest（追跡済み・新規ファイル）、HEAD、git status、Zig版・実体ハッシュ、ビルドコマンド、実行体ハッシュ、fixtureハッシュ、JSON、JSONL、stdout/stderr生ログを残す。OS、CPU、電源設定、バックグラウンド負荷、端末、backend、表示周期をoperatorが別途記録する。OS・ビルド・入力・位相・温め方・試行数の異なる値は合算しない。

## 2. ビルドと時計

Zig 0.17.1、native x86_64、ReleaseFast、debug=false、strip=true、既定語群・VM容量。worker 1、待ち4、台帳16、追加予算128MiB。

- 入力→状態・起動・サイズ・手動確認は `-Dtask-trace=false -Dtask-acceptance=false` の通常実行体。
- 内部区間は同じ通常経路に `-Dtask-acceptance=true` を付ける。既定はfalse。workerの固定領域・atomic・必要な時計読み出しと本書の計測用holdを有効にし、診断traceは使わない。メイン側のログ整形・書込みは区間計測後にまとめて行う。計測自体の費用を含む値として扱う。
- 06-Hの `-Dtask-trace=true` は内訳の参考専用。受け入れ判定には使わない。通常経路probeと同じrunに混ぜない。入力→状態はrunnerが別の通常ビルドを用い、management_turn_ns出力を発生させない。入力fixtureは1 MS待機を入れない。親のpipe受信・scheduler費用は残るので、内部の状態更新時間そのものとは区別する。
- 内部時計はWindows QPC、Linux CLOCK_MONOTONIC。親子の時計を引き算しない。
- smokeは内部時刻を0とし、差分・中央値・p95・最大・目標との比較を計算しない。`trial_wall_seconds` は準備時間の見積り専用で、受け入れ標本ではない。

## 3. 固定する題材と順序

`tests/scripts/acceptance-fixtures.py` が実際のForthソースを生成する。ワーカーは既存例と同じSnapshot/public APIを使い、許可集合から外れるI/O・解釈・DO系ループを使わない。メイン側はDO系ループを使用できる。

| 順 | ケース | 固定する入力・動作 | 回数 |
|---|---|---|---|
| 1 | 機能回帰 | test、debug=falseのtest、runtime-test、docs、fmt | 測定前に成功を確認 |
| 2 | サイズ・起動 | 同構成のA/B、起動はready markerの親受信、AB/BA交互 | サイズ各1、起動各5 warmup＋100回 |
| 3 | Snapshot | 私有データ3,000,000bytes、旧・現・取得中の3世代を保持。実際のimage bytesも記録 | 独立プロセス100回、各3取得を別標本として保存 |
| 4 | 生成・実行取消し | 既存06-Hと同じ25個の要求対象段階、末尾はexecuting。各対象ごとに独立プロセス | 各対象100回 |
| 5 | native取消し | FILL 64KiB、MOVE 32KiB読＋32KiB書、COMPARE各32KiB、SEARCH 65,535×1不一致、ROLL深さ8191（8192 cells、当該プロセスのdata stackは16384） | 5語×直前/実行区間/直後×各100回 |
| 6 | 待ち取消し | 先行busy workerを保持し、別I1要求を待ちへ置いてTASK-CANCEL。queueから実際に取り除いた場合のみqueuedとして記録 | 100回 |
| 7 | G1 | 256×256の開放盤面、縦壁、蛇行路。種0、始点0。終点は開放/壁65535、蛇行65280。既存4近傍BFS | 各10分×1回 |
| 8 | G2 | 256×256、種0、(17×index＋seed) mod 31 = 0 を地雷とし隣接8セルの数字を付与。幅28〜256を受け付ける | 10分×1回 |
| 9 | T1 | 1MiBのa、検索語a、保存最大1000件。既存検索worker | 10分×1回 |
| 10 | I1 | bytes(range(256))反復の64KiB塊。busy workerで初回4待ちを作り、解除後は最大5件（実行1＋待ち4）を補充 | 10分×1回 |
| 11 | 入力→状態 | busy workerと管理巡回を続けながらpipeからbを注入し、状態store後のmarkerを受信。qで終了 | 10分×1回 |
| 12 | OSメモリ | G1各形状/G2/T1/I1およびSnapshot 3世代の同じmainデータを持つtaskなし基準と負荷を別起動。10ms周期＋資源を保持する停止点で採取・親の確認後に再開 | 各3回、対話の採取も併記 |

G1/T1は処理完了後100ms、G2は1000msを置いて次を投入する。遅い処理を重ねて規定頻度を達成したと主張しない。I1は50msごとに空きslotを補充する。拒否・期限切れ・失敗も残す。待ち4を常時維持できたと推定せず、実際のqueue_waitingを記録する。各対話ケースはq入力を確認し、結果の出力と管理を続ける。画面提示と実端末の入力は手動手順で別確認する。

Snapshotの3MB題材は4MiB上限そのものではない。snapshot_image_bytesで実寸を確認し、4MiB境界の機能試験と区別する。VMプール・温めた復元を実装済みと扱わない。

## 4. 区間と目標

| metric | 始点→終点 | 目標 |
|---|---|---|
| request_stop_ns | 公開取消しAPI入口（位相指定ではhost request開始）→runner帰還、以後入力に触れない時点 | 10ms |
| request_reclaim_ns | 同じ要求→物理handback/retirement完了を確認し、台帳entry、結果、入力、名前、実行用Snapshot参照、VM、task slotを解放 | 100ms |
| queued_cancel_publish_ns | 要求→次のhost pollによるready公開直前 | 次巡、10ms |
| G1/T1/I1_submit_publish_ns | admission前のsubmit入口→readyのrelease-store直前 | G1 100ms、T1 200ms、I1 250ms |
| G2_submit_publish_ns | 同上 | 500ms |
| management_turn_ns | Service.poll入口→全処理から帰還（ログ書込みを除く） | 1ms/巡 |
| input_state_ns | 親のpipe書込み開始→状態store後markerの親受信 | 16.67msの保守的な上界 |
| snapshot_main_ns | TASK-SNAPSHOTのAPI入口→handleを返す直前。初回のservice初期化を含む。重複していたsnapshot_ready_nsは削除 | 50ms |
| snapshot_image_bytes / queue_waiting | 実Snapshot画像bytes / submit後の待ち数 | 4MiB / 4件 |
| publish_reclaim_ns | ready公開直前→上記task回収完了 | 100ms |

ready公開時刻はrelease-store直前の計測点であり、ストア後の観測値ではない。全体shutdownのjoinと、個別taskのworker handbackを混同しない。共有workerをtaskごとにjoinしない。公開Snapshot handleを利用者が保持している間、その独立した所有参照はtask回収の対象外である。

## 取消し位相の改訂（2026-11-25、決定B）

レモンは、3 OSとも生成段階を狙った取消しの約7割が対象を取り逃し、nativeのFILL・SEARCH・ROLLでは最初の3回とも取り逃して打ち切った結果を受け、「B: 段階を確実に狙える測り方に変えて、測り直す」を採用した。回数は変更しない。Windows・Linux・macOSそれぞれ生成25段階、native 5種×3位相、待ち中の計41ケースを各100試行（4,100試行/OS）で新runへ採取する。旧runの有効値・欠測・超過は保持し、新方式と混ぜない。既存の他群の追加規則も消さない。

`-Dtask-acceptance=true`だけで、workerは対象段階を固定領域のatomic `hold_stage`へrelease-storeし、取消しtokenをacquire-loadして待つ。ホストのTASK-STATEによる巡回が到達を確認すると、Forthスタック上の同じtask idを使って公開語TASK-CANCELのハンドラーを呼び出す。取消し経路を別実装しない。requestedはそのTASK-CANCEL入口、stoppedはrunner帰還、reclaimedは従来どおり物理handback・所有資源とslot回収後。hold待機はrequestedより前に置かれるので要求→停止/回収へ加算しない。到達からtokenまでのholdは実時計で最大5秒（OSによる実行待ちを除く）、時計異常も解除して欠測にする。ホストが要求しない場合は時間切れで再開し、BYEのshutdown取消しtokenでも解除する。段階通過時に繰り返しholdしない。

生成各段階およびnative before/afterは到達した位置でholdする。native_runningは**実処理中の要求ではなく、事前確認後の入口でholdし、要求後にnative全体を実行する保守的な代替**を採用する。理由は、短い非分割nativeの内部に停止点を追加せず、外側から要求を確実に重ねることはできず、旧方式では取り逃しが残るため。入口は既存checkpointの後、次のcheckpointはnative直後にあり、holdはtoken確認後にエラーを返さず通常処理へ戻る。最大量のnative全体が要求→停止に含まれるため、途中で要求する場合の残仕事量を上から覆う検証になる。ただしOSのスケジューリングを含む全入力・全実行の最悪遅延を証明するものではない。method=`guarded-native-entry-full-call`と記録し、実際のduringを観測したと表現しない。

最大量の題材はFILL 65,536 bytes、MOVE 32,768読＋32,768書、COMPARE各32,768（同値の領域）、SEARCHは65,535 bytesのaと末尾に置く1 byteのb（不一致で全文走査、領域合計65,536、仕事量65,535）、ROLLは8,192 cells=65,536 bytes。SEARCHの旧256×256は最初の候補で一致するため全文走査を検証できず変更した。ROLLの旧4,000 cellsは64KiB未満なので、native-rollプロセスだけ`--data-stack-size 16384`を付け、8,191 ROLLを実行する。他の題材の容量は従来どおり。回数は変えず、題材・構成の差はmanifestとcommandに保存する。D07の64KiB/回以下と要求→停止10msをこの全量実行で照合する。

phase_okはhold_stage、要求直前に保存したrequest_stage、指定段階の3つが一致し、hold_timeout=falseの場合だけtrue。待ち中はqueued=trueと未実行（request_stage=api_entryの初期値）を確認する。native境界の時刻は残すが、同時刻による区間推定から位相を決めない。smokeでも全位相のphase_okを保存し、端点は0、速度統計は空のままにする。holdの時間切れ・時計異常・位相不一致・task行欠落は理由付き欠測とし、速度標本に使わない。最初の3回での打切りと250msの観測窓は廃止する。全100試行を記録し、成功数までの補充はしない。nativeの出力観測guardは6秒、プロセスの異常停止guardは120秒で、いずれも速度標本ではない。

通常ビルドではenabled=falseのcomptime分岐、空のStorage、voidのtoken付帯フィールドによりholdを除去する。通常経路の変更有無は同条件のReleaseFast/debug=false/task-trace=false/task-acceptance=falseで変更前後の.textを比較して確認する。検証では取消し成功、要求なしの5秒時間切れ、要求なしのBYE終了を短い動作確認として実施する。本測定はClaudeが担当する。


## 5. OSメモリと予算

WindowsはVirtualQueryExのMEM_RESERVE＋MEM_COMMITを予約総量、PrivateUsageを私有コミット、WorkingSetSizeを常駐として別保存する。LinuxはsmapsのSize、VmFlags acのaccountable mapping size、Rssを保存し、private/shared、stack、swapも分ける。Linux accountable mappingsはWindowsのPrivateUsageと同じ意味ではなく、VmSizeやRSSをコミットに読み替えない。

同じmain題材の基準と負荷の各ピーク差を保存し、追加予約・コミット128MiBと照合する。基準値には最後のBASELINE-READYで確認した1標本だけを使い、起動途中や最初のSnapshot生成workspaceの最大値を基準値に混ぜない。負荷側は停止点と周期採取の最大値を使う。基準は同じmain題材を初期化し、TASK-SNAPSHOTを1回取得してサービスと公開Snapshotを保持した状態でBASELINE-READYを出し、親の採取確認を待つ。従ってサービス初期化と最初のSnapshotは追加task予算から除く。Snapshot専用ケースも基準は1世代であり、負荷との差は追加2世代と取得中workspaceを含む。

メモリ専用runだけSIGMA_ACCEPTANCE_MEMORY_HOLDを設定する。Snapshot取得時はimageとencoder workspaceが共存する点、entry検証workspaceの保持点、workerの各stageの初回通過、結果コピー後でgrants解放前の点で停止する。親はOS情報を採取しstdinへ改行を送り、確認後だけ進める。Snapshot題材は3世代を保持したmain側停止点も置く。これにより短命なVM・結果・画像を10ms間隔の偶然だけで採取しない。時間測定runには停止点を有効にしない。停止点の待ち時間でI1の待機要求が期限切れにならないよう、メモリ専用runだけ待機期限を120秒に延長する。通常の50/100/100/200msの待機期限の試験とは区別し、速度・期限の合格には使わない。メモリ専用runの内部時計は0にし、停止時間を含む速度統計は作らない。停止点採取の欠落とOS読取りエラーは欠測とする。OS全体の一時的な内部割当て・ページ常駐の絶対最大を保証するものではなく、保持点のピークと周期採取ピークを区別する。常駐は別記する。これは停止点と10msサンプリングによる観測差であり、全確保境界の絶対ピークやカテゴリ帰属の証明ではない。欠測・OS読取り失敗・ピーク取りこぼしの可能性を結果に残す。128MiBの厳密な上限合格には、allocator上限の機能試験およびOS側の追加確認も必要である。

## 6. 集計・追加試行・除外

中央値は偶数個なら中央2値平均、p95はnearest rank。最大、目標超過件数、欠測、timeout、位相不一致を全て保存する。遅い標本を除外しない。smokeはこれらを計算しない。

**事前規則：有効標本の観測最大が目標の80%を超えた項目は、そのcase/位相/metricだけを追加確認する。** 取消し/Snapshotは当該case/位相について追加1,000回、対話は当該ケースのみ10分を2回追加、メモリは当該ケースのみ追加10回とする。元のrunを保持し、新runに増加理由と元runへの参照を残す。複数metricが同じcaseに属する場合は同時に再採取する。追加後も80%超過・欠測・目標超過があれば、規定試行による合格とはせず、原因確認と再計画を必要とする。runnerのextend_requiredは実行要求の記録であり自動合格ではない。

追加は `--probe-cases <case> --probe-stages <stage> --repetitions 1000`。待ち取消し/Snapshot/メモリにはstage指定を付けない。対話の2回追加は独立したmeasure起動を2回行う。--repetitionsで変更した回数と部分case選択はargvに残し、標準計画の完遂と扱わない。

## 7. コマンドと所要時間

WindowsはPowerShell、Linuxは同じリポジトリのルートでpythonをpython3に置き換える。

```text
python tests/scripts/run-acceptance.py --only fmt test runtime plain docs
python tests/scripts/run-acceptance.py --mode smoke --only workloads snapshot response reclaim memory
# 位相到達の事前確認（速度の本測定はしない）
python tests/scripts/run-acceptance.py --mode smoke --only reclaim --probe-cases native-roll native-fill --repetitions 3
# Claudeの本測定。HASHは本書の最終SHA-256、REFは利用者の実行確認参照。
python tests/scripts/run-acceptance.py --mode measure --only reclaim snapshot memory workloads response --plan-sha256 HASH --confirmed REF
python tests/scripts/run-acceptance.py --mode measure --only startup size --baseline PATH_TO_A --plan-sha256 HASH --confirmed REF
# 06-Hは別run、判定用ではない。
python tests/scripts/run-acceptance.py --mode smoke --only cancel
```

A/Bの起動・サイズ比較には同じ語群・最適化のA実行体が必要。起動markerは親受信でありpipeとscheduler遅延を含む。実行体とPE/ELFの.text論理/ファイルbytesを保存する。A/A′/Bの通常単一VM比較と逆アセンブル採取はこのrunnerでは未対応であり、AC-29全体の合格にはしない。

短い試行の実際の壁時間から得た所要時間と算出式は、[実装報告書](TASK_CONTROL_IMPL_1382.md)の今回追記に記録する。ビルドは別枠、OS別の本測定速度の見積りではない。対話は6題材＋入力1ケースで合計70分/OSを確保し、起動/終了/ビルド/追加試行の時間を加える。

## 8. 短い試行に基づく所要時間の見積り

Windowsでの準備用smokeの実際のプロセス壁時間を使う。根拠は `.work/acceptance/20261124T100620Z-dcd41750/`、起動は `20261124T100147Z-28005f7c/`。速度区間は全て0またはnullで、目標との比較はしていない。

| 項目 | 短い試行の所要時間 | 計画回数への換算（ビルド別） |
|---|---|---|
| 生成・実行取消し＋native＋待ち | 41ケース1巡で0.917秒 | ※推測です：100巡で約92秒。下記の位相観測待ちを含まない準備費用の下限 |
| Snapshot（取得3回） | 1プロセス0.046秒 | ※推測です：100プロセスで約5秒 |
| OSメモリ | 7題材の負荷合計1.140秒＋対応基準合計0.506秒 | ※推測です：各3回で約5秒。OS採取の欠測時は再確認が必要 |
| G1/G2/T1/I1 | 6題材の短い機能試行の合計0.973秒 | 計画上6×600秒＝60分。終了余裕を別に確保 |
| 入力→状態 | 注入・終了の1試行0.073秒 | 計画上600秒＝10分。pipeの上界を採る |
| 起動 | warmup込みA/B計14プロセス0.146秒 | ※推測です：各105回、計210プロセスで約3秒。通常ビルドとprobe buildを使った形式確認からの費用見積りでありA/B比較結果ではない |
| 実行体/.text | 同じ起動smoke内のPE読取り成功 | ※推測です：各1生成物の読取りは数秒の枠を確保。ビルド・逆アセンブル採取を含めない |
| 管理1巡・投入→公開・公開→回収 | 上記各プロセスの中で同時採取 | 単独の追加実行時間なし |

上表は旧方式の準備費用の記録であり、v4の確定所要時間ではない。※推測です：取消し4,100試行は正常に到達・解除できれば数分〜15分/OS、ビルド・環境記録は別枠。全件がhold時間切れなら5秒×4,000件=約5.6時間に起動・回収費用が加わる。異常時120秒guardの費用は別枠とし、欠測を成功標本へ読み替えない。

## 9. レビュー後の固定条件

本版では11点のレビューを反映した。欠けたtask行、時計終点、要求位相不一致、失われたイベントは理由付きmissingに保存する。queue_waitingの単位はcount、snapshot_image_bytesはbytesとし結果表へ出す。JSONLは群ごとに一度開き、題材ハッシュも群の各caseにつき一度だけ計算する。

対照AはW1導入前の `35523f676836134c4fbaed19e3d01d2a23ec2a92`（1386で使用したA）を使う。別のソース配置に `git archive` で展開し、Zig 0.17.1で `zig build -Doptimize=ReleaseFast -Ddebug=false -Dstrip=true --prefix <A出力先> -j2`。語群とVM容量は既定値、targetは当該OSのnative x86_64としBも同じ条件にする。Aにはtask-trace/task-acceptanceオプションが存在しないので渡さない。Aのコミット、ソースarchiveのハッシュ、ビルドコマンド、Zig版、実行体ハッシュを保存する。ブランチ操作・コミットは不要。このAはW1導入前との比較であり、1382直前との差分だけの比較ではない。

所要時間見積りの旧smoke値はv2の記録であり、本版のメモリ停止点費用には使わない。生成段階の欠測率が高い場合も試行回数を成功数へ読み替えない。対話70分/OSに、短い試行・hold・ビルド・起動・回収・OS確認を加える。異常時guardと追加規則による時間は別枠とする。

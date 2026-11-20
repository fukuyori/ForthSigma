# PCMストリームの採用設計（998）

2026-11-20、基点6512916、Zig 0.17.1。設計1125の採用仕様。公開語・ホスト終了処理は実装前。内部リング1126の実装/実行結果は別記録へ分ける。[初期提案](PCM_STREAM_DESIGN_PROPOSAL.md)、[ソース/API照合](PCM_STREAM_SOURCE_AUDIT.md)、[レビュー判断](reviews/998-review-response.md)。

## 公開境界

AUDIO語群。内部Builtinは既存に合わせSND-PCM-*、audio.fsでPCM-*を公開する。audio=falseで除外し、debug/graphics/extensionは必要条件にしない。通常の不正数値は-24、不正範囲は-9をTHROWし、検査前の引数を保持。stack不足もTHROW。対象の状態に関する失敗は既存のerrnoIorを使う。missing host callbackは-21、host基盤・時計・端末復元の失敗は-265をTHROWする。正常なdeviceなしは既存同様silent消費で継続し、AUDIO?で区別する。

| 語 | スタック効果 | 契約 |
| --- | --- | --- |
| PCM-OPEN | hz channels capacity -- pcm ior | mono/stereo、s16LE固定、入力Hz 8000..192000。容量は2の冪で256..65536、capacity≤hzかつcapacity×25≥hz（40ms..1s）。同時に1stream。busyは0,-528、未確保は0,-524。成功は正のID,0 |
| PCM-WRITE | addr frames pcm -- written ior | nonblocking complete-frame copy。全要求のbyte範囲と乗算overflowを先に検査。fullは0,0。frames=0ならmemoryを参照しない。呼出し後sourceを借りない |
| PCM-QUEUED | pcm -- frames ior | engineが消費する前の入力frame数。ZOHが出力中のframeを含む。失敗は0,ior |
| PCM-WAIT | frames ms pcm -- flag ior | frames以上の空き。1..capacity。0ms=poll、負数=無期限、正数は単調期限1個。timeout false,0。中断はTHROW -28 |
| PCM-STOP | mode ms pcm -- flag ior | mode0=discard、1=engine drain。drain待ちのtimeout/中断ではrunningと受理済み音を保持。その後停止要求を出したらstoppingへ移り、残り期限でack待ち。timeoutはfalse,0で要求を残す。中断はTHROW -28で要求を残す。後のSTOPでackを確認できる |
| PCM-CLOSE | pcm -- ior | discard/detachを要求し最大1000ms ack待ち。成功でID無効化。timeoutは-528、中断は-516でclosingのIDを保持し再度CLOSEできる。バッファはfreeしない |
| PCM-UNDERRUNS | pcm -- u ior | 最初に1frame以上出力した後、runningで空になったepisode数。連続emptyやstopped/drainedは数えない。u32最大値で飽和し、Forth cellへ拡張する |

不正/閉じた/同一process内の古いIDは-521。stopping/stopped/closingへのWRITE/WAITは-534。STOP後もQUEUED/UNDERRUNS/CLOSEは使える。STOP済みからの再生はCLOSE→OPENとし、暗黙restartしない。

OPENのattach ack前でも新入力のコピーは許すが、UNDERRUNSは新世代のackまで0として古いstreamの値を返さない。STOP/CLOSEは前のattach requestのackを待ってからdetachをpublishし、mailboxを上書きしない。各操作の期限を待ち直す際も延長しない。

readyとtimeoutが同時なら、まず引数・対象状態を検査し、その後readyを検査してから期限を検査する。ただし観測済み中断/host失敗を成功に隠さない。共有信号scopeは待機全体を覆う形にし、3msごとにscopeを外す窓でCtrl+Cを取り逃す設計にしない。既存の内部clock・Deadline・信号所有/入力保持を使う。新しい暗黙VMポーリングは追加しない。

## 所有と保存

音のconsumerが参照するStream/Control/最大65536 Frame（256KiB）はhostのEngine側の安定領域へ置く。State.memory、sample pool、Forthからのborrowed pointerへ置かない。hostは一度だけ有界storageを確保し、PCM-CLOSE後も再利用のため保持する。consumerの停止/join成功後にだけfreeする。Stateへ置く場合も非永続の現在の論理IDだけとし、consumerはStateを参照しない。VM/ownerとIDを照合し、別VMのstreamを操作させない。workerVMのaudio許可は1053で別に監査する。

IDは同一process内で単調増加し使い回さず、枯渇ならOPEN失敗。cross-process一意性は保証しない。画像に普通の整数として保存した値が別起動の新streamと一致する可能性はあり、世代検査だけで必ず拒否できるとは言わない。画像からOS資源やstreamを復活させない。

SAVE/SAVESYSは許可し、live handle/ring/positionは保存対象外。完全復元はcurrent StateがPCMを所有していれば**適用前にbusy（-528）を拒否**し、明示的CLOSE後に再実行する。image_restore.applyへ待機やabandonを足さない。typed appendとLOADは追加先のPCMを保持し、自動再開しない。LOADの一時StateはPCMを所有しない。完全復元とappendが共有するprepareへ無条件のbusy検査を足し、appendを意図せず禁止しない。

## SPSCと再標本化

producerのみtail、consumerのみheadを更新する。framesをコピーしてからtail release、読取り後head release。capacityは2の冪かつ2^32を割り切るためu32 wrapでも位置を保つ。QUEUEDはproducerのtailとacquireしたheadの差。held frameのheadは最後の使用が済むまで進めない。

整数位相によるzero-order hold（sample/hold）を採用する。既存sound_pcm.Playerもholdを使うが、新実装は整数の比で長期ドリフトを避ける。anti-alias filterは付けず、高品質resamplingとは扱わない。各出力frameでphase+=input_hz、advance=phase/output_hz、phase%=output_hz。未着の読み飛ばし数はconsumerのskipへ保持し、次のsampleの最初に落とす。次回にも該当frameがなければ無音を出してphase/skipを0へ戻す。無音を出さずにWRITE分割だけで位置を変えない。

monoは左右複製、stereoはs16LE interleaved。非整列inputも読める。既存chip/MML/MOD/SFXのDC除去/0.6gain後のs16とPCMをi32で加算し[-32768,32767]へ飽和。既存音のfilterを変更せず、PCMのDC値を勝手に除去しない。PLAY(0)、CHIPS、FREE-SAMPLES、STOP-MODはPCMを暗黙停止しない。

Controlはsingle-slotのrelease/acquire mailbox。producerは前要求のack前にpendingを上書きしない。consumerはrender境界で前streamをdiscardし、次streamのphase/skip/episodeをresetしてからackする。停止要求を出しただけで参照終了とはみなさない。serialは単調増加し比較可能、過去のcompletedもtrueを維持する。最後のserialはdetach専用に予約し、枯渇でactiveを外せなくしない。counter/制御serialは32bit atomicとし、Cortex-M0+の既存freestanding確認でも64bit atomicを要求しない。公開handleのIDとは別の内部serialである。callback内でallocation/lock/wait/host呼出しをしない。

drain開始前にproducerがdrainingをreleaseで立て、consumerはacquireで見た意図的empty tailをunderrunに数えない。drain timeout/中断でrunningへ戻す場合はproducerが解除し、その後の実際のempty出力は再び数える。beginはproducer-ownedのこのflagを上書きしない。再OPENでは前のdetach ack後、再publish前にproducerがfalseへ初期化する。drain成功後はdetach ackまでtrueを保持し、停止待ちの尾部を誤って数えない。

drainはengineへ取り込むまで。QUEUED=0も実際に鳴り終わった意味ではなく、OS装置bufferは残る。初版は実再生位置・device送出位置の能力を提供しない。音を基準にしたエミュレータ同期精度は未測定。

## hostの停止（1127で実装、未実装）

既存backendを維持する。stop_requested→再投入を止める→consumer/callback停止→OS資源解放→thread_exited→join→engine storage解放。初期化失敗のrollbackも同じ所有状態を使う。OS解放は原則としてbackend所有thread内で行い、期限内join後のVM threadが追加の無期限driver呼出しへ入らないようにする。

shutdownは1000msを基本期限とし、未停止ならfailedを報告してbuffer/Engine/device所有権を保持する。未停止threadをfree済みState/runtimeへ結び付けない。プロセスは失敗として終了できるが、これを回収成功や通常の音停止成功とは扱わない。shutdown未完了のhostを再startしない。

| backend | 採用する対応 |
| --- | --- |
| Windows waveOut | event wake、再投入終了、waveOutReset→準備済みheaderのunprepare→close→event close。途中open失敗も段階別に回収 |
| Linux Pulse simple | 現行backendを維持。write間でstopを見る。blocking writeを別threadからfreeして中断しない。期限内終了できなければ上記の未完了を返して保持。asyncへの移行は別工程で測定後に判断 |
| Linux ALSA | nonblocking化、EAGAINでは有限wait後stop再検査、部分書込みとrecoverにもstop検査。drop/closeは所有thread。open/set_params失敗をrollback |
| Linux pipe | 専有writerをnonblockingにし有限poll。pid/groupを保持、EOF→期限→TERM/KILL→指定pid回収。process registryと二重回収しない。partial spawn失敗のfd/child回収も検査 |
| macOS AudioQueue | stoppingを立て、callbackはrender/enqueueしない。所有threadでStop/Dispose同期成功後にexited。成功前にengineをfreeしない |
| silent | 有限sleep/catch-up途中もstopを確認し終了 |

Pulse abandonを正常の停止方式に格下げするわけではない。阻害backend fixtureで期限内に失敗として戻り、未停止consumerの領域を解放しないことを試験する。装置/driver障害の全てを1000msで完全回収すると保証しない。API一次資料の内容と実測を分ける。

## タスクと完了条件

1125設計→1126内部リング/変換/Engine混合、および1127 host寿命→1128公開語/所有/画像/終了→1129 Windows/Linux受け入れ、1130 Mac実機。全体998は公開語とOS確認が終わるまで未完了。Mac未確認のために1126/1127/1129の作業を一律に止めない。

1126は満杯/partial/wrap、符号/非整列、入力分割と全rate、underrun、mailbox遅延ack/再利用/枯渇、実2threadの順序、旧音声試験と混合を確認する。1127はdeviceなし、20回の開閉資源数、阻害backendでのtimeout保持、pipe子回収、初期化全段のrollback。1128/1129は引数失敗原子性、ms期限/中断/closing再試行、保存アプリからの起動/正常/THROW/中断、語群除外、英日HELP/全語を照合する。実際に音を聞く確認と数値captureを区別する。

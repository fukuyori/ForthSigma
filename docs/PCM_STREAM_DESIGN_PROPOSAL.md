# 998 PCMストリーム：設計提案（レビュー前）

2026-11-20、基点6512916、Zig 0.17.1。未採用。実装済みとは扱わない。

## 照合した現在のソース

sound_engine.Engineは単一producer/consumer。Ringは固定容量u32のSPSC。host_audioは48kHz/s16/stereo、480frames×8buffers（Windows/macOS）、LinuxはPulse simple/ALSA writei/pipe write。音のconsumerはWindows/Linux/silentでは専用thread、macOSではAudioQueue callback。startThreadはdetachし、終了要求・join・device解放がない。silent消費も無限。実装ではこの寿命を整理する必要があり、PCM-CLOSEだけでhost全体が止まると解釈しない。

sound_pcm.poolはサンプル/SFX/MOD用のappend-only領域。流し続けるPCMには使わない。Engine.renderの既存chip/MOD/SFX加算→filteredにはDC除去と0.6gainがある。PCMをこの前へ加算するとDC/波形が変わるため、既存filtered結果とPCMのs16をi32で加算しsaturateする案。既存の音量特性を変更しない。

words_audio.Waiterはhost audio_wait_fnを使い中断をRuntimeErrorへ持つ。900/639の部分書込み・期限・取消しを踏襲し、受理済みPCMを中断で取り消さない。取得したsource sliceを音threadへ渡さずコピーする。

## 提案API（AUDIO）

形式は初版s16 little-endian interleavedのみ。bufferは非整列でも読める。mono/stereo、Hz 8,000..192,000、容量power-of-two 256..65,536入力frames。1VM/hostのactive streamは1個。handleは正のgeneration IDで再利用時に同じIDを返さない。workerVMの共有は1053で決め、今回multiple-producerを許さない。

- `PCM-OPEN ( hz channels capacity -- pcm ior )`：事前検査後に有界ring確保、consumerとの公開/ack。成功handle,0、失敗0,ior。既存activeならbusy。format固定なのでconfig-recordを作らない案。
- `PCM-WRITE ( addr frames pcm -- written ior )`：nonblocking、最大空き分だけコピー。0framesはaddr0も許す。fullは0,0。全要求のbyte範囲とframes×channels×2のoverflowを先に検査。中途失敗はwrittenとiorを返す。フレームを半分だけpublishしない。
- `PCM-QUEUED ( pcm -- frames ior )`：まだ音engineが消費していない入力frames。resampler保持の現在frameを数に含め、producerから一貫して読めるsnapshotを返す。実再生位置は返さない。
- `PCM-WAIT ( frames timeout-ns pcm -- ready ior )`：入力ringにframes以上空くまで。timeout相対ns、0=poll、-1=無期限、それ未満は不正。readyはForthflag、timeoutはfalse,0、中断false,-28。deadlineは単調時計を一度だけ作り、wake後必ず再検査。framesは1..capacity。
- `PCM-STOP ( mode timeout-ns pcm -- stopped ior )`：0=discard、1=engine drain。停止をconsumerがackしたらtrue,0。drainは期限中に空にならなければfalse,0でrunningを維持、interruptedでもring保持。成功後stoppedでWRITE拒否。装置bufferの排出完了は保証しない。discardもすでにdeviceへ渡した音は戻せない。
- `PCM-CLOSE ( pcm -- ior )`：consumerから外してackを得てからfreeしhandle無効化。stoppedでなくてもdiscard。内部制御ackは有限（案1秒）。timeoutならbusyで所有権保持、解放しない。中断を受けてもcleanupを完遂し、その後-28を返す案。CLOSEを繰返すと不正handle。close失敗でhandleを失わせない。
- `PCM-UNDERRUNS ( pcm -- u ior )`：stream開設から、runningで入力なしになったepisode数。連続無音でframeごと加算しない。飽和u64をcellへ返すとき最大signedcellで飽和。open直後empty episodeは数える案。

通常の不正値/アドレス/ハンドルも固定stack結果とiorで返し、stack不足だけTHROW。既存ior対応表から値を選び、新規値は必要最小にする。主所有はStateの非永続fieldを案とし、画像へlive handleやring/pointer/positionを入れない。literalの古い整数handleがSAVEに残っても世代/owner検査で拒否する。SAVE自体は許す。完全restore/typed append時の活動資源の取り扱いは900と照合しbusy拒否か明示停止を決める。LOADは自動再開しない。

## consumer・再標本化

入力ringは新規sound_stream.zig。capacityフレーム×stereo最大4bytes、上限256KiB。producerのみtail、consumerのみhead。monoは複製。初版は整数位相accumulatorによるzero-order hold（sample/hold）を提案する。filter/アンチエイリアスなしを明記し、高品質再標本化とは扱わない。rate/output_rateは整数の比なので48k/44.1k等で長期ドリフトしない。underrun時は無音、現在sample/phaseの規則を固定し、古いsampleを無期限に伸ばさない。block分割やWRITE分割で結果が変わらないことを試験する。

controlはringと別のsingle-slot atomic mailbox（open/stop/closeのrequest generation、consumer ack）。consumerのみresamplerをresetしproducerはack前に内容を変えない。通常command ringのreset/CHIPS/FREE-SAMPLESはPCMを暗黙破棄しない。既存PLAY/MOD/SFXと独立に混合する。callback内でallocation/lock/wait/host-callをしない。

## host終了と障害

新streamの有無にかかわらずaudio shutdownをmainのruntime解放前deferへ置く。音threadをjoin可能にし、stop request→device待機解除→callback停止/consumer終了→join→device/pool/ring解放の順。Windows waveOutReset/UnprepareHeader/Close、AudioQueueStop/Disposeとcallback寿命、Linuxのpipe停止/子回収/非ブロック化、Pulse simple/ALSA blocking writeの解除を実APIと照合する。stop期限を過ぎたconsumerへ無理にfreeしない。既存process registryと二重回収しない。

Pulse simpleはblocking writeを外から安全に中断できる前提を置かない。実装の選択肢はPulse asyncへ移行、非blocking ALSA/pipeだけ使う、またはhelper processへ隔離し既存process管理で停止する。ここはClaudeとの比較で確定する。既存音出力を黙って縮小しない。backend差と実機未確認を明記する。

## 検証と分割

998を仕様/リングとresampler/公開語とhost寿命/WindowsLinux受け入れ/Mac実機へ分割。dependencyは共通1064、PCM公開語の通常の語群基盤1056。coreはmock consumerでfull/partial/wrap/invalid/close race/ack delayed/rate/underrun/saturate/mix/継続波形を決定的に検証。hostは専用consumer/virtual captureで開閉repeat・fd/thread/handle・deviceなし・阻害writeの停止・失敗rollbacksを検証。音を聞いた確認、公開語process、cross compileを区別する。audio=false/debug=false/graphics=false/extension=falseと保存アプリからの起動/中断/終了を検証し、Mac実機だけを未完了で残せる構成にする。

具体値とstop/close/timeout/所有境界、resamplerの端点、既存backendを壊さない終了方法についてレビューで確定する。採用設計は別文書へ保存し、この提案は変更しない。

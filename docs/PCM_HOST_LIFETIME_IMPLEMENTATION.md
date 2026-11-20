# PCM03 音声ホストの停止・回収（1127）

2026-11-20、基点main `416caf9`、Zig 0.17.1。1127の実装・検証記録。前段のPCM設計/内部リングは416caf9でcommit/push済み。本記録のhost変更は未コミット。[採用設計](PCM_STREAM_DESIGN.md)、[レビュー評価](reviews/1127-review-response.md)、[原データとソース指紋](measurements/2026-11-20-audio-lifetime.json)。

**公開PCM語・PCM Frameのhost確保/所有・画像連携は1128で未実装。** 998全体を完了にせず、Mac実機1130も残す。

## 実装した動作

- 音声threadをdetachせず保持し、shutdownでstop要求→backend cleanup→exited公開→join→library unload→pool freeの順に回収する。consumerの参照先はhost globalとhost poolだけで、StateやRuntimeへ渡さない。
- 1000msを基本の終了待ちとし、未停止/時計故障/join失敗/未解決のcleanup失敗ではEngineやpoolを残してfailedにする。明示shutdownを再試行し、遅れたworkerの終了を確認できれば回収できる。未完了の間は再startしない。
- backend失敗からsilentへ移る前に装置/callbackを解放する。Mac callbackを残してsilent consumerを同時に走らせない。startupでthreadを作れなかった場合も装置/poolをrollbackする。
- WindowsはReset→準備済みheaderのunprepare→Close→event close。別threadからSetEventする方式は採用せず、有限100ms waitでstopを検査する。eventをworkerが閉じる瞬間と競合するnative callを避ける。
- LinuxはPulse simpleを維持し、blocking write/freeを別threadから無理に解除しない。ALSAはnonblocking、未準備/部分書込み/recoverの間でstopを検査する。pipe writerはnonblocking、有限poll、子のpid/groupを保持してEOF→TERM→KILL→指定pidのwaitpidで回収する。
- macOSはcallbackがstop時にrender/enqueueせず、所有threadの同期Stop/Dispose成功後にexitedを出す。framework/libraryはjoin後にunloadする。
- POSIXの音声workerは同期fault以外のsignalをblockし、既存のsignal所有を音声threadへ移さない。
- 通常終了/例外で音声shutdownを実行するdeferを追加。未停止workerが残った場合は他のdeferとflush後、POSIX _exit/Windows自プロセスTerminateProcessでstatus1に進む。runtime cleanupのfatal分岐にも同じ保護を入れる。

一時的なcleanup失敗は、再試行で実際に回収でき、terminal failureがなければ成功へ戻す。ALSA closeでhandleが消費されたerror等は、単にpointerがnullになったことを回収成功の証拠にしない。恒久的失敗の領域はfreeしない。

## 実行結果

| 対象 | 結果 |
| --- | --- |
| Windows Debug host | 160成功・15除外、失敗0 |
| Linux musl Debug host（WSL） | 165成功・17除外、失敗0 |
| Windows graphics/audio/extension/debug除外 host | 158成功・15除外、失敗0 |
| Windows zig build test | core/runtime/CLI/freestandingを含む既存全体テストが成功 |
| Mac aarch64 host/阻害fixture | cross compile成功、実行していない |
| 阻害consumer別プロセス | Windows/Linux各3回、status1、期待stdout、stderrなし |

追加試験は、silent consumerを20回joinした後のhandle/fd数、5ms timeoutでpool保持・再start拒否・遅れたjoin、thread作成失敗、時計故障、継続するcleanup失敗、回復したstartup/worker cleanupを含む。Windowsではevent後の失敗20回、header0..7枚の途中失敗、実waveOut装置の反復開閉20回で所有資源数が戻ることを確認した。比較前に一度開いて閉じる。最初の観測ではcold86→warm185 handleとなり、その後の反復は同数だった。初回とsteady-stateの数を混ぜない。

Linuxでは読まない専用playerのpipeを満杯にしてEAGAINを通し、EOFで終了する子、TERMで終了する子、TERMを無視してKILLで終了する子をそれぞれ回収した。writer fd/pidが無効になり、再waitがECHILDとなり、fd数が戻ることを照合した。ALSAの未準備/0書込み/17frameの部分書込み/回復を差し替え、停止とcloseを確認した。Pulse writeを含む阻害libraryの代用として、stop要求を無視するconsumerを別fixtureで使った。

Windows通常実行体ではAUDIO?=-1、正常BYE=0、THROW=1、音声を使う保存アプリ=0を確認した。GNU Linux実行体はAUDIO?=0のsilent経路でstatus0。**LinuxのPulse/ALSA実装置、Macの実装置、実際に音を聞く確認は行っていない。** fixtureの成功を実機音声の確認済みとはしない。

## API資料と限界

- [Microsoft waveOutUnprepareHeader](https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/nf-mmeapi-waveoutunprepareheader)：bufferをfreeする前にprepareを解き、再生中bufferを扱わない。
- [ALSA closeの一次ソース](https://github.com/alsa-project/alsa-lib/blob/master/src/pcm/pcm.c)：closeの戻り値にかかわらずPCM objectが消費される点を確認し、二重closeを避けた。コードは移植していない。
- [Apple AudioQueueDispose](https://developer.apple.com/documentation/audiotoolbox/audioqueuedispose(_:_:))：inImmediate=trueの同期disposeと、その後callbackを呼ばない仕様を確認。実機は1130。
- [Pulse simple API](https://www.freedesktop.org/software/pulseaudio/doxygen/simple.html)：writeはblocking。server/driverの任意障害から完全回収できる時間上限は保証せず、停止未完了を成功に隠さない。

通常の音声thread停止を確認した結果と、任意driver/libraryの全異常を1000msで完全解放できる保証は別である。callback停止やnative closeに失敗した領域を強制freeしない。

## 再実行

```powershell
zig build test
zig build host-check audio-lifecycle-check --prefix .work/1127/windows
.work/1127/windows/host-tests/x86_64-windows/test.exe
python tests/scripts/verify-audio-shutdown.py .work/1127/windows/audio-check/x86_64-windows/probe.exe
```

Linuxはtargetをx86_64-linux-muslへ変えて作り、WSL/LinuxでtestとPython scriptを実行する。Macはaarch64-macosでcompileし、1130で実際に実行する。fixtureは明示したaudio-lifecycle-checkだけで作り、通常のinstall/releaseには含めない。専用プロセスだけを強制終了し、利用者のconsoleへ入力を送らない。

次は1128の公開語・owner/handle・PCM storage・画像復元busy/append保持・終了連携と英日HELP。1129の装置/生成アプリ受け入れ、1130のMac実機を別に完了させる。

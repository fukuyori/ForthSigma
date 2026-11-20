# PCMストリーム：ソースと外部APIの照合

2026-11-20。基点6512916。設計の判断材料であり、PCM公開機能・host終了を実装したという記録ではない。

## 既存コードの接続箇所

| 箇所 | 確認した動作 | 追加で満たすこと |
| --- | --- | --- |
| sound_engine.Ring | head/tail各1 writer、release/acquire、u32 wrap、容量固定 | PCMはコピーしたframes専用のring。制御側がconsumerのheadを勝手にresetしない |
| sound_engine.Engine.render | chip/MOD/SFX混合→DC除去/0.6gain/clip | PCMを同じfilterへ入れるか否かを明示。提案は既存filter後にs16飽和加算 |
| sound_pcm | sample poolはappend-only、SFX最大4 | streaming領域をpoolへ足し続けない |
| words_audio.Waiter | audio_wait_fn、入力読取り時graphics_input、-28等 | 新語は900の結果分類と期限を使い、既存PLAYの巻戻しと混同しない |
| host_audio.start/startThread | global Engine、pool確保、device open→detached thread | 初期化失敗のdevice/pool回収、join可能thread、consumer停止後free |
| Windows play | waveOut buffers8個、done eventを100ms waitし再投入 | 終了要求時は再投入を止め、reset/unprepare/close/event解放 |
| Linux play | Pulse simple_write/ALSA writei/pipe writeは現行blocking | 他threadからfree/closeして中断できると仮定しない。非blocking化・所有thread内closeが必要 |
| Mac play/refill | AudioQueue callbackだけがrender、失敗時stopしてsilentへ移行 | callback停止の確定後にring/engine解放。失敗移行でconsumerを二重にしない |
| runtime_base / host_runtime | Deadlineは相対ms/負数無期限、owner/epoch/serialの台帳、pcm kind | 任意の新しいtimeout単位や中断iorの方針を持ち込まない |
| ASYNC_COMMON_RULES / ASYNC_IO_DESIGN | 中断-28・host unavailable -21・host failed -265はTHROW。対象の通常失敗はior | レビュー前提案のnsと-1限定、-28をiorで返す箇所は採用前に修正する |
| image_restore/append | prepare→失敗しないapply。Stateやmemoryを変更する | live PCM/borrowed inputを保存しない。新しいrestore busy検査は変更前に行う |

## 一次資料の確認（2026-11-20）

- [PulseAudio Simple API](https://www.freedesktop.org/software/pulseaudio/doxygen/simple.html)：read/writeはblocking。これだけを根拠に別threadからfreeして安全に中断できるとは言えない。
- [PulseAudio mainloop](https://www.freedesktop.org/software/pulseaudio/doxygen/mainloop_8h.html)：iterateのblock=0でイベント待ちを行わず処理できる。async streamとの組合せを移行案として比較する。実装・装置での停止時間は未確認。
- [ALSA PCM interface](https://www.alsa-project.org/alsa-doc/alsa-lib/group___p_c_m.html)：SND_PCM_NONBLOCK、snd_pcm_nonblock、snd_pcm_dropを提供。現在のopen flags=0とblocking writeを維持したままstop flagだけ足しても待機解除にはならない。
- [Microsoft waveOutReset](https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/nf-mmeapi-waveoutreset)と[装置のclose](https://learn.microsoft.com/en-us/windows/win32/multimedia/devices-and-data-types)：pending bufferを返してからunprepare/closeする。closeだけで再生中bufferを安全に回収できる前提にしない。
- [Apple AudioQueueDispose](https://developer.apple.com/documentation/audiotoolbox/audioqueuedispose(_:_:))：inImmediate=trueで同期dispose。以後queue/callbackへアクセスしない。実機でcallback終了・解放順を別に検証する。

外部APIの仕様を読み、新しいbackendコードを実行したわけではない。Linux server停止、装置切断、driver異常まで時間上限を保証するには実装と差替え検証が必要。

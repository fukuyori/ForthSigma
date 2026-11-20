# task1127 レビュー報告（host_audio.zig / main.zig の終了処理 defer）

レモン、静的レビューの結果です。見たのは Read/Grep だけで、コマンド・git・テストは実行していません。ビルド結果とテスト結果は**未確認**です。OS API の動作もソースを読んだだけで、実機では確かめていません。

## 結論

- **High は見つかりませんでした。**
- **Medium が4件、Low が3件**あります。修正方法はそれぞれ下に書きました。
- 次の点は設計（`docs/PCM_STREAM_DESIGN.md:47-62`）のとおりに実装されています。
  - 期限切れでもストレージを保持する
  - 遅れて終了した worker を後から join できる
  - 起動失敗時の rollback
  - 失敗後に再 start しない

## Medium

### M1. 時計が失敗すると `state` が `.running` のまま false を返す
- 場所: `src/host_audio.zig:102`、`:104` の `catch return false`
- 何が起きるか: `stop_requested` は true になっていて、worker は止まります。それでも `state == .running` のままなので、次の `start()` が `&engine` を返します（`:61`）。消費する側のいない engine が「running」として渡され、PLAY は空き待ちを続けます。設計の「shutdown 未完了の host を再 start しない」に反します。
- 修正: `stop_requested.store(true)` の直後に `state = .failed;` を置きます。`state = .idle` にするのは `:127` の成功時だけにします。そうすれば `:105`、`:115`、`:122` の個別の代入は要りません。
- 試験: 時計失敗の fake を足し、失敗後に `start(null) == null` になることを確かめます。

### M2. worker thread が終了する前に dlclose している（Pulse、ALSA、AudioToolbox）
- 場所: `:478-481`、`:489-492`、`:761-764`。どれも worker の `closeBackend()` から呼ばれます。
- リスク: libpulse 側の thread-local 値が worker に残っていると、thread が終了するときに解放処理が呼ばれ、すでに unmap されたコードへ飛ぶおそれがあります。※推測です（libpulse の内部は確認していません）。
- 修正: `release()` を2つに分けます。
  - `releaseDevice()`: worker が行います（`pa_simple_free`、`snd_pcm_drop/close`、`AudioQueueStop/Dispose`、pipe の後始末）。
  - `unloadLibraries()`: VM thread が行います。呼ぶのは、shutdown で join に成功し `cleanup_ok` が true のときだけです。thread がない start rollback（`:76`）では、その場で VM thread が呼んでかまいません。
- `pulse_write` などの関数ポインタを使うのは device がある間だけです。そのため、library を VM 側で後から close しても問題ありません。

### M3. worker が残ったままプロセスが通常の exit をする
- 場所: `src/main.zig:3559`。`main` から return して通常の exit に入ります。
- 何が起きるか: worker が `pa_simple_write` で止まったまま、libc の exit 処理（atexit、共有ライブラリの終了処理）が動きます。その結果、終了時に crash や hang が起き、終了コードが 1 でなくシグナルによる終了に変わるおそれがあります。※推測です。Windows の ExitProcess は他の thread を先に止めますが、これも静的には確認していません。
- 修正: `audio_cleanup_failed` が true のときは、出力を flush した後、POSIX では `std.c._exit(1)` で終了します。Windows は現状のままで、fixture で確認します。
- 試験: 阻害 fixture で、プロセスが終了コード 1 で終わることを確認します。

### M4. open が失敗したとき、global の handle に中身の分からない値が残る可能性
- 場所: `:288` の `waveOutOpen(&device, ...)`、`:711` の `new_output(..., &queue)`
- 何が起きるか: 失敗したときに出力先へ何が書かれるかは、API の資料では保証されていません（未確認）。値が残っていると、後の `release()` がその値に対して `waveOutReset/Close` や `AudioQueueStop/Dispose` を呼んでしまいます。
- 修正: local 変数で受け、成功したときだけ global に代入します。
  - Windows: `var handle: ?HANDLE = null; if (waveOutOpen(&handle, ...) != 0) return false; device = handle;`
  - macOS: `queue` も同じ形にします。

## Low

- **L1** 一度 `cleanup_ok` が false になると、その後 worker 内の再試行（`run` の defer）で解放に成功しても、shutdown はずっと false を返します。これは「失敗したら reset しない」方針どおりなので、変えません。
  - 直したいのは表示です。start の rollback で `closed == true` だった場合、pool はすでに free されています（`:79-82`）。それでも main は「shared storage retained」と表示します（`main.zig:3693`）。
  - 修正: pool を保持しているかどうかを `engine.pool.len != 0` で判定し、表示を分けます。
- **L2** `pipe()` の後に `fcntl(FD_CLOEXEC)` をかけるまでの間（`:545-552`）、別の thread が fork すると write 側の fd が子に引き継がれます。すると EOF が届かず、TERM/KILL まで待つことになります。
  - 修正: Linux では `pipe2(O_CLOEXEC | O_NONBLOCK)` を使います。
- **L3** worker は `pthread_create` を呼んだ VM thread の signal mask をそのまま引き継ぎます（`:137`）。そのため、生き残った worker の上で SIGINT などの handler が動くことがあり得ます。
  - 修正: `PosixThread.entry` の先頭で、同期シグナル以外をすべて block します。

## 確認して問題がなかった点

- 終了の順序（`run` の defer の順）: stop_requested → backend 解放 → `thread_exited` → join → pool の free（`:151-152`、`:103-126`）
- 期限切れのとき: `state = .failed` にして pool、Windows の `samples/headers`、mac の buffers をすべて保持します。shutdown を再試行すれば、遅れて終了した worker を join できます。pthread_join に失敗した場合は handle を保持します。
- start の rollback: thread 起動に失敗したときや `cleanup_ok == false` のときは、VM thread が `closeBackend` を呼びます。解放に成功したときだけ pool を free します。
- Windows の解放順: Reset → 準備済み header を逆順に unprepare → Close → event close。`prepared` の数で、途中で失敗しても続きから解放できます。待ちは 100ms の有限時間で、別 thread から device を操作することはありません。
- 失敗時の切替で二重 render しない: device を解放（mac では Dispose が同期して成功）してから silent に移ります。解放に失敗した場合は silent に移りません（`:162`）。mac の refill は `failed`/`stop` を見ると render も enqueue もしません。
- Linux:
  - ALSA は nonblocking で、20ms の wait と部分書込み、recover の各所で stop を確認します。
  - pipe も nonblocking で、20ms の poll を使います。子は pid を指定して回収し、group には TERM→KILL を送ります。
  - process registry も pid を指定して回収するので（`host_process_native.c:523`）、二重に回収することはありません。
  - Pulse の blocking write を別 thread から free する処理はありません。
- worker が触るのは host の global（`engine`、各 backend の static）だけで、State や runtime には触れません。Engine の中身も自分で持つデータと host の pool だけです（`sound_engine.zig:224-270`）。main の defer は、audio の shutdown が `storage.free` と `runtime.deinit` より前に走る順で並んでいます。

## 公式資料への照合（静的レビューでは確認していません）

ここに書いたことは、どれも実機または資料で確かめる必要があります。

- waveOutReset、Unprepare、Close の順序と、失敗時の handle: https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/nf-mmeapi-waveoutreset
- pa_simple_write が blocking であること、pa_simple_free が戻るまでの時間: https://www.freedesktop.org/software/pulseaudio/doxygen/simple.html
- ALSA:
  - `snd_pcm_recover` が ESTRPIPE で resume を繰り返す時間
  - nonblocking のときの `snd_pcm_close`
  - 資料: https://www.alsa-project.org/alsa-doc/alsa-lib/group___p_c_m.html と alsa-lib のソースの `pcm.c`
- AudioQueueDispose(inImmediate=true) が、実行中の callback の終了を待つかどうか: https://developer.apple.com/documentation/audiotoolbox/audioqueuedispose(_:_:)
- 1130 の Mac 実機で確認する事項として記録してください。

## 追加する試験の案（fixture の準備と合わせて）

1. 時計失敗の後は `start == null` になる（M1）。
2. backend の解放に失敗したとき（`cleanup_ok = false`）、shutdown は false を返し、pool を保持する。表示も保持の有無で分かれる（L1）。
3. Windows の open が途中で失敗したとき、event だけ、device まで、header k 枚まで、のそれぞれで rollback できる。
4. pipe の子が EOF・TERM・KILL のどれで終わっても、指定した pid を回収し、fd を残さない。
5. M2 を直した後、shutdown が成功するまで library が close されない。

## 1128 に向けて

- `pcm_control` が持つ `*Stream` と、その Frame の保存領域を free するのは、`:125` と同じく shutdown が成功したときだけにしてください。
- `state` は atomic ではありません。workerVM から start/shutdown を呼べる場合は、1053 の監査で一緒に扱ってください。

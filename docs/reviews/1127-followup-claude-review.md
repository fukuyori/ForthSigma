レモン、静的レビューの結果です。見たのは Read/Grep だけです。コマンド・ビルド・テストは実行していないので、ビルド結果とテスト結果は**未確認**です。Zig の型は手元にある 0.17.1 の `lib/std/c.zig` と照らし合わせました。

## 結論
- **High は見つかりませんでした。**
- **Medium が4件**あります。M1〜M4 と L2・L3 の修正自体は、意図どおりに入っています（下の「確認できた点」）。

## Medium

### N1. runtime の後始末が失敗すると、ハード終了を通らずに通常の exit をする
- 場所: `src/main.zig:3673-3680`
- 何が起きるか: defer は登録と逆の順に動きます。そのため audio の defer（`:3695`）が先に走り、`audio_cleanup_failed = true` になります。その後に runtime の defer が走り、`runtime.deinit` が失敗すると `libc.exit(1)` を呼びます。worker が残ったまま libc の終了処理と DLL の切り離しが動き、M3 で塞いだ経路を別の口から通ります。
- 修正: `libc.exit(1)` の直前に `if (audio and audio_cleanup_failed) host_audio.abortIncomplete();` を置きます。flush はその前の行で済んでいます。

### N2. open の途中で失敗し、再試行で解放に成功しても、shutdown がずっと false を返す
- 場所: `src/host_audio.zig:118-127`、`:165-168`
- 何が起きるか:
  1. `windows.open` / `openAlsa` / `macos.open` / `spawn` の rollback で解放に失敗し、`cleanup_ok=false` になります。
  2. `start` が `closeBackend()` で解放をやり直し、成功します（`closed == true`）。library の unload と pool の free まで終わります。
  3. それでも `cleanup_ok` は false のままなので、`shutdown` は毎回 false を返します。
  4. main は「audio shutdown incomplete」と出力し、`abortIncomplete` で終了コード 1 のハード終了をします。
- 結果: 資源はすべて解放されているのに、プログラムが失敗扱いで終わります。`:137` のコメント「False means shutdown is incomplete」とも合いません。thread の作成に失敗した場合（`fail_thread`）は true を返すので、扱いが揃っていません。
- 修正: `:122` の `if (closed)` の中で `cleanup_ok.store(true, .release);` を呼びます。こうすると `fail_thread` と同じ扱いになり、後の start で再び開くことを許します。再 start を禁止したい場合は、`state` とは別に「再 start しない」ことを示すフラグが要ります。どちらにするかは、レモンに決めてもらう事項です。
- 試験: `test_mode` に「start の中で `cleanup_ok` を false にする」モードを足し、次の3点を確かめます。
  - `start == null`
  - `engine.pool.len == 0`
  - `shutdown(1000) == true`

### N3. Linux で、同じ名前の extern 関数を型の違う宣言で2つ使っている（コンパイルできるかは未確認）
- 場所: `:439-441`（`linux.sigemptyset/sigaddset/pthread_sigmask` の引数が `*anyopaque`）と `:51-67`（`std.c.sigfillset/sigdelset/pthread_sigmask` の引数が `*sigset_t`）
- 何が起きるか: 今回の変更で、Linux では同じシンボル `pthread_sigmask` を型の違う2つの宣言から参照するようになりました。Zig のバックエンド（特に Debug で使う自前の x86_64 バックエンド）がこれを受け付けるかは確認していません。※推測です
- 修正: `entry` は SIGPIPE を除外リストに入れていないので、SIGPIPE はすでに block されています。したがって `linux.play` の `:692-695` は重複です。この4行と、`sigemptyset/sigaddset/pthread_sigmask` の extern、`sig_block/sigpipe` の定数を削除すれば、宣言は `std.c` の1つだけになります。

### N4. host_audio の test がテスト実行に含まれるか、コード上で保証されていない
- 場所: `src/main.zig:4116-4133` の `test {}` ブロック。ここに `host_input` などは明示的に参照されていますが、`host_audio` はありません。`forth_test.zig` も host_audio を import していません。
- 何が起きるか: `host_audio.start` が参照されているので、Zig 0.17 がこのファイルの test を集める可能性はあります。ただし確認していません。集められなければ、時計失敗・解放失敗・Windows の部分 open・pipe の EOF/TERM/KILL の試験は、どれも実行されません。
- 修正: `if (audio) _ = host_audio;` をこのブロックに足します。test を実行したら、出力にこれらの test 名が出ていることを確認してください。

## 確認できた点（新しい回帰は見つかりませんでした）
- **M1**: `:141-142` で、時計を読む前に `stop_requested` を立て、`state = .failed` にしています。時計の失敗、期限切れ、join の失敗のどれでも、再 start しません。
- **M2**: worker が呼ぶのは `closeBackend` だけで、デバイスの解放だけを行います。library の unload は次の2か所だけです。
  - `shutdown` で join に成功し、`cleanup_ok` が true のとき（`:169`）
  - start の rollback で `closed` が true のとき（`:123`）
  - 失敗後に無音で続けている間も library は読み込んだままです。`unload` は null に戻すので、2回呼んでも二重には close しません。
- **M3**: `run` がエラーで終わっても、defer がすべて走った後に `main:3559` でハード終了します。POSIX は `_exit`、Windows は自プロセスへの `TerminateProcess` です。fixture は `build.zig:101-113` で別に作られ、install には含まれません。`fixture_enabled` が true になるのは、test と、`audio_lifecycle_fixture` を宣言した root だけです。
- **M4**: `waveOutOpen` と `AudioQueueNewOutput` は local 変数で受け、成功したときだけ global に代入しています（`:366-368`、`:813-815`）。
- **L2**: `pipe2(O_CLOEXEC)` と、fd が 0〜2 だった場合に `F_DUPFD_CLOEXEC` で 3 以上へ移す処理が入っています。移すのに失敗したときに fd を close する処理も正しく書かれています。
- **L3**: `std.c.sigset_t` と `SIG` の型は Linux と macOS で揃っています。`SIG.BLOCK` は Linux の std にあることを確認しました。macOS 側の定義は確認していません。mask の設定に失敗したときは、解放をしてから `thread_exited` を立てます。
- **子プロセスの終了**: ハード終了の前に `closeAllProcesses` と、audio の pipe の EOF→TERM→KILL による回収が済んでいます。

N1〜N3 を直す場合は、テスト実行（PowerShell から）の結果で確かめてください。

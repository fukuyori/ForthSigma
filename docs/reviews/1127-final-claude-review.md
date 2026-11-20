レモン、静的レビューの結果です。使ったのは Read と Grep だけです。ビルドとテストは実行していないので、Windows・Linux・macOS のどれについても、コンパイルできるかとテストが通るかは**未確認**です。

## 結論
- **High：なし**
- **Medium：1件**（下の M1）。前回の N2 と同じ種類の問題が、worker 側の後始末に残っています。

## Medium

### M1. worker が後始末をやり直して成功しても、shutdown がずっと false を返す
- **場所**：`src/host_audio.zig:249-264`（`run`）、`:238-247`（`closeBackend`）
- **何が起きるか**：
  1. `play` が終わります。止める要求が来た場合も、デバイスが失敗した場合も同じです。その後、`:261` の `closeBackend()` が失敗し、`cleanup_ok=false` になって `return` します。
  2. `:251` の defer `closeBackend()` が解放をやり直し、成功します。たとえば Linux の pipe では、最初の 300 ms 以内に回収できなかった player を、2回目の `reapFor` で回収できます。
  3. それでも `cleanup_ok` は false のままです。そのため `shutdown` は join の後に毎回 false を返します（`:187-190`）。main は「audio shutdown incomplete」と出力し、`abortIncomplete` で終了コード 1 のハード終了をします。
- **結果**：資源はすべて解放されているのに、プログラムが失敗扱いで終わります。start 側の rollback（`:143-144`）では、同じ状況で `cleanup_ok` を true に戻すので、扱いが揃っていません。
- **修正**：`:251` を次のように置き換えます。
  ```zig
  defer {
      if (closeBackend() and !terminal_cleanup_failure) cleanup_ok.store(true, .release);
  }
  ```
  - 次の2つの場合は、これまでどおり false のままです。
    - ALSA の close が失敗した場合。`terminal_cleanup_failure` が立つので、true に戻りません。
    - `test_cleanup_failed` を使う場合。`closeBackend` が false を返すので、true に戻りません。
  - `terminal_cleanup_failure` を読み書きするのは、`release` を呼んでいる worker だけです。main がこの値と `cleanup_ok` を読むのは、`thread_exited` の acquire と join の後なので、データ競合は起きません。
- **試験**（Linux のみ）：
  1. `closeBackend` に、fixture のときだけ1回だけ失敗する `test_cleanup_fail_once` を足します。失敗するときは、`release` を呼ぶ前に `cleanup_ok=false` にして false を返します。
  2. `.alsa_fixture` でこれを有効にし、次の3点を確かめます。
     - `shutdown(1000) == true`
     - `test_alsa_closed == true`
     - `engine.pool.len == 0`

## 確認できた点（新しい回帰は見つかりませんでした）
- **N1**：defer は登録と逆の順に動きます。audio の defer（`main.zig:3696`）が runtime の defer（`:3669`）より先に走るので、`audio_cleanup_failed` はすでに確定しています。そのうえで `:3680` が `libc.exit(1)` より前にハード終了します。flush、`utf8_console.finish`、`resize_scope.end` もその前に済んでいます。
- **N2**：
  - `closed && !terminal_cleanup_failure` のときだけ `cleanup_ok` を true に戻します。state は `.failed` のままです。
  - `shutdown` はスレッドがない場合も `cleanup_ok` を見るので、終わり方は次のどちらかに揃います。
    - 回復できた場合：解放済みの空の pool で idle に戻り、true を返します。
    - terminal failure の場合：ずっと false を返します。
  - `terminal_cleanup_failure` を false に戻すのは start の idle 経路だけです。idle になるには `shutdown` の成功が要るので、一度立つと消えません。
  - ALSA は、close の戻り値にかかわらず `pcm=null` にします（`:584-589`）。そのため2回 close することはありません。
- **N3**：
  - `std.c` の `sigfillset` / `sigdelset` / `pthread_sigmask` だけになりました。古い opaque 型の extern と、`linux.play` で SIGPIPE を block していた処理はなくなっています。
  - SIGPIPE は除外リストにないので、block されます。pipe の書き込みは EPIPE で `return` します。
  - mask の設定に失敗したときは、`closeBackend` を呼んでから `thread_exited` を立てます。
  - macOS の `std.c.sigdelset` の定義は**未確認**です。
- **N4**：`main.zig:4122` で `_ = host_audio;` を明示的に参照しています。
- **終了済み worker の検出**：
  - `getEngine` は毎回 `audio_fn` を呼びます（`words_audio.zig:270-273`）。そのため、`start` が `.failed` に変えて null を返すと HostFailed になります。
  - `putCommand` と reset の待ちループは、毎回 `Waiter.wait` を通ります。`wait` / `waitWithRuntime` は `.host_failed` を返すので、ループが止まります。新しい deadlock は見つかりませんでした。
  - 終わったスレッドは `shutdown` で join されます。`windows_thread` / `posix_handle` は残っているので、join を飛ばすことはありません。
- **子プロセス**：`waitpid(-1)` や `P_ALL` で回収しているコードは、ほかにありませんでした（Grep で確認）。audio の player を回収するのは、その所有者だけです。
- **fixture の分離**：
  - `fixture_enabled` が true になるのは、test と、`audio_lifecycle_fixture` を宣言した root だけです。probe は install の対象外で、`audio-lifecycle-check` の step でだけ作られます。
  - Python スクリプトは次の点を確かめます：timeout 5 秒、終了コード 1、stdout が1行だけ、stderr が空。
  - probe は、`shutdown(5)` が期限切れで false を返し、`retained()` が true の場合にだけ、ハード終了に進みます。

Windows と Linux のテスト名・fixture の実行結果は、こちらでは確認していません（**未確認**）。

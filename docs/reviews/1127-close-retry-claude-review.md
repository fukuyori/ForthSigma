レモン、M1 について確認した範囲では、**High・Medium に当たる指摘はありません。**

確認した点は次のとおりです(Read と Grep だけで、ビルドと試験の実行は未確認です)。

- **やり直しが成功したとき**:`run` の defer(`src/host_audio.zig:257-259`)は `closeBackend() and !terminal_cleanup_failure` のときだけ `cleanup_ok` を true に戻します。M1 の修正案と同じです。
  - defer の順序:`thread_exited.store` の defer(`:256`)を先に登録しているので、これが最後に走ります。`cleanup_ok` の確定は `thread_exited` の release より前に終わります。main はその後で acquire と join をしてから `cleanup_ok` を読みます(`:170-188`)。
- **後始末の失敗が続くとき**:
  - `test_cleanup_failed` を使う場合、`closeBackend` は毎回 false を返すので(`:245-247`)、`cleanup_ok` は false のままです。
  - ALSA の close が失敗した場合、`terminal_cleanup_failure=true` が立ちます(`:595`)。2回目の `release` では `pcm` がもう null なので true が返りますが、`!terminal_cleanup_failure` の条件で弾かれ、true には戻りません。
- **各 backend の `release` は失敗しても状態を消さない**:Windows の device/event、Linux pipe の `pipe_pid`、macOS の queue は、失敗したとき handle を残したまま false を返します(`:412-427`、`:599-614`、`:908-916`)。そのため、2回目が true になるのは実際に解放できたときだけです。中身のない成功で true に戻ることはありません。
- **signal mask の設定に失敗したとき**:`PosixThread.entry`(`:54-73`)は `run()` に入りません。`cleanup_ok=false` を立てて `thread_exited` を立てるだけなので、defer で true に戻ることはなく、失敗のまま残ります。
- **consumer が終わる前に解放しないこと**:
  - `shutdown` が `engine.pool` を free し、`unloadLibraries` を呼ぶのは、`thread_exited` を確認し、join し、`cleanup_ok` が true だったときだけです(`:188-194`)。
  - 時間切れや join の失敗では、何も解放せずに false を返します。
  - macOS の callback は `dispose_queue` が同期的に止めます。これに失敗すると queue が残り、`cleanup_ok` も false のままなので、pool は解放されません。
- **`test_cleanup_fail_once` と試験**:
  - `closeBackend` に入れた1回だけの失敗(`:240-244`)は、`release` を呼ぶ前に `cleanup_ok=false` を立てて false を返します。
  - 試験(`:1138-1152`)では、この失敗を `:269` の呼び出しが消費します。その後、defer の `closeBackend` が `testClose` で解放に成功します。
  - 確かめているのは `shutdown(1000)==true`、`test_alsa_closed`、`engine.pool.len==0` で、M1 が求める3点と一致します。

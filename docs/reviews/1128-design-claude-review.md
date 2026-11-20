読み取りのみで、採用設計と現在のソースを照合しました。レビュー中に親側の実装が進み、`src/core/sound_stream_session.zig`、`host_audio.zig` の `next_pcm_id`/`freeStorage`、`image_restore.zig` のガード、`Writer.audio_scope_ops` が新しく現れています。以下はその時点のファイル内容に基づく所見です。実装やテストが完了しているかは確認していません（未確認）。

# 1128 提案レビュー

## 1. 具体的な不整合（修正が必要）

| # | 箇所 | 問題 | 解決案 |
|---|---|---|---|
| C1 | `sound_stream_session.zig:41-50` `tryDetach` | `draining` を立てるのが `publish(null)` の**後**です。discard の STOP/CLOSE では、ack までの尾部で空になると UNDERRUNS が1増えます。設計43行の「停止待ちの尾部を誤って数えない」に反します | `draining.store(true,.release)` を publish の**前**へ移します。この時点では `completed(request)` を確認済みなので Busy は起きません |
| C2 | 同 `tryDetach` | `publish(null)` が失敗すると `false` を返すだけです。呼び出し側からはタイムアウトと区別できず、無期限待ちになり得ます | 失敗はエラーとして返し、-265 で THROW します。現状の到達経路はありませんが、黙って待ち続ける形は避けます |
| C3 | STOP drain のタイムアウト/中断（未実装部分） | 提案は「running へ戻す」ですが、attach ack 前（opening）に STOP した場合は opening へ戻す必要があります | STOP 入口で直前の phase を保存し、取り消すときはその phase へ戻します。`draining` も false に戻します |
| C4 | `Session.open` の `Stream.init(..., 48000, ...)` | 出力 rate を直書きしています | `engine.sample_rate` を渡します |
| C5 | `Session.open` で `InvalidConfig` を -534 にしている | 設計では、不正な設定は呼び出し側で事前に THROW -24 を出します。ior が混在します | 語の側で `validCapacity` と channels を先に検査し、ここは `unreachable`/assert にします |
| C6 | CLOSE を stopping 中の session に出したとき | `tryDetach` は `detached` が true だとすぐ戻るため、phase が `.closing` になりません。タイムアウトすると stopping のまま ID が残ります | CLOSE 入口で必ず `beginClose()` を呼び、phase を closing に固定します |
| C7 | `getEngine` 経由の `audio_fn` | `host_audio.start` は idle なら**音声スレッドを起動**します。無効な handle に QUEUED などを出しただけでスレッドが起動し得ます | handle の検査（State の `audio_pcm_handle` と一致するか）を `audio_fn` の呼び出しより前に置きます。不一致なら固定結果（`0,-521` など）を返し、エンジンには触れません |

## 2. 寿命と所有の競合

- **`transport` の再初期化（安全条件）**: `Stream.init` は atomics を含む構造体全体を非 atomic に上書きします。これが安全なのは「phase=free なら、最後の request が completed かつ Control.active≠&transport」が成り立つときだけです。現在、この条件を作るのは `commitClose` の assert と新しい Engine の生成だけです。この不変条件を `open` の先頭に assert として明記するよう推奨します。
- **Engine の再初期化**: `start()` が `engine = Engine.init(...)` で session を free に戻すことは、shutdown が成功した後に限れば安全です。ただし State 側の `audio_pcm_handle` は古い値のまま残ります。本番では shutdown はプロセス終了時だけですが、テスト用 fixture では起こり得ます（→ 決定事項 D3）。
- **owner = State のアドレス**: 現状は成立します。main は audio shutdown の後に State を destroy します。LOAD の一時 State は handle 0 で、アドレスも異なります。将来の workerVM（1053）ではアドレスが再利用される危険があります。そのため「State の destroy 前に session が free であること」を前提条件として記録します。
- **Frame storage の解放**: `freeStorage` は join の後、`cleanup_ok` が成功したときだけ呼ばれます。join は成功したが `cleanup_ok` が false のときは storage を保持します（安全側の残存です）。起動時のロールバックも `closed` のときだけ解放しており、設計どおりです。
- **UNDERRUNS を 0 にする判定**: `request` は detach の serial で上書きされます。それでも「`!detached && !completed(request)` のときだけ 0、それ以外は `transport.underruns`」と導出できます。attach が完了した後でなければ detach を publish しないためです。

## 3. 信号 scope の入れ子と優先順位

- `beginExecution` は `execution_depth` を先に増やしてから `beginInput` を呼びます（`host_wait.zig:261-267`）。そのため native scope は `restart=true` の execution 用になり、broker は `signal_broker.fallback` です。runtime broker とは別物ですが、PCM の待機中は他の scope が動かないので衝突しません。
- 待機ループは `audio_wait_fn` だけを使います。`execution_depth≠0` の経路では `pollExecution`（→ `executionRawPoll`）を呼んでから 3ms sleep し、`thread_exited` なら `.host_failed` を返します。**`ops.poll` は別途呼びません**（二重 poll を避けます）。
- `.read_input` は `.waited` として扱います。`executionRawPoll` が入力をすでに取り込んでいるので、PLAY の `Waiter` のように `readPending` は呼びません。
- 入れ子の場合（EXEC-LIMITED 内）、内側の `endExecution` は中断を消費しません。ループ中の poll が見つけた中断はその場で返ります。scope を抜けた後に届いた中断は外側へ渡ります。この扱いは「観測していないものは隠さない」に合っています。
- **優先順位**:
  1. stack 不足
  2. 状態に依存しない数値の検査（THROW -24、入力を保持）
  3. handle と状態の検査（ior）
  4. capacity に依存する数値の検査（THROW -24）
  5. 待たずに判定できる ready なら scope に入らず成功を返す
  6. 0ms ならそのまま `false,0` を返す
  7. scope の中で ready → 期限の順に判定する
  8. scope 終了時の HostFailed（-265）は他のすべてより優先し、その次が中断（WAIT/STOP は THROW -28、CLOSE は `-516` を返す）、最後に ready/timeout の結果
- CLOSE の再試行では、ack 済みならすぐ `commitClose` します。scope は不要です。scope 終了で中断や失敗が起きた場合は commit せず、ID を保持します。

## 4. 画像経路のバイパス確認

- `restore`/`restoreFresh` の先頭ガードは、prepare の前、つまり変更より前に置かれています。適切です。
- LOAD の流れは `loaded.init(machine.writer)` → `loaded.restoreFreshImage` → `machine.appendImage` です。一時 State は handle 0 で、`appendImage` は handle に触れません。typed append（`image_append.append`）は公開の接続がまだなく、prepare の共有部分にもガードはありません。設計どおりです。
- `audio_pcm_handle` は Zig のフィールドで、State.memory の外にあります。そのため SAVE/SAVESYS には含まれず、`apply` も触れません。`machine.init` を再度呼ぶのはテストとツールの経路だけです。
- 制約として、現在は公開語から完全復元へ至る経路がありません（呼び出し元は起動時と freestanding だけ）。このガードの検証は内部呼び出しの試験になります。

## 5. 確定してほしい事項（決定事項）

- **D1 ID 枯渇時の ior**: 現在の実装は -587（EOVERFLOW）です。`host_directories` は枯渇時に EMFILE（-536）を返しています。どちらに揃えるか決めてください。
- **D2 closing 中の STOP/QUEUED/UNDERRUNS**: 推奨は、STOP は -534、QUEUED と UNDERRUNS は使えるようにすることです。
- **D3 State の handle が古くなった場合**（host を再起動した後など）: 推奨は、照合に失敗したら handle を 0 に戻し、-521 を返すことです。こうすると完全復元の -528 が永久に続くことを防げます。
- **D4 WAIT の frames > capacity**: -24 とするか -9 とするか。推奨は -24 です。
- **D5 Frame の確保**: 現在は起動時に 256KiB を常に確保しています。このままでよいか、OPEN 時の遅延確保（新しい host callback が必要）にするか。推奨は現状維持です。

Builtin enum の末尾に7語を追加すること、`words_audio.words` に登録して audio=false で除外することは、現在の enum と除外表の構造に矛盾しません。

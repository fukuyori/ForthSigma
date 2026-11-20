# 998 PCMストリーム設計提案（docs/PCM_STREAM_DESIGN_PROPOSAL.md）レビュー報告

これは静的レビューです。ファイルの読取り（Read/Glob/Grep）だけで行いました。ビルド、テスト、git コマンド、実機での確認はしていないので、以下に「実行結果」はありません。ファイルも書いていません。tque への登録も未実施です（書込み禁止の指示に従いました）。外部 API の挙動（waveOut、ALSA、Pulse、AudioQueue）は公式文書と照合しておらず、すべて**未確認**です。

## 1. 指摘（High）

### H1. PCM の状態を State に置くと、終了時に解放済みメモリを読むおそれがある
- **根拠**
  - 提案 25行目は、主な所有を「State の非永続 field」としています。
  - `main.zig:3661` の `storage.free` は、runtime の defer より先に登録されています。そのため実行は最後になり、音の停止処理より後に走ります。
  - Pulse の書込みが止まったまま join が期限切れになると、音のスレッドは生きたまま残ります。この状態で Storage や State 上のリングが解放されると、音のスレッドが解放済みメモリを読みます。
  - `image_restore.apply` は「preflight の後は失敗しない」作りです（`image_restore.zig:17`）。待機が要る停止はここでは行えません。
- **修正**
  - リングと制御用 mailbox は `Engine` の field にします。`engine` はホストの静的変数（`host_audio.zig:37`）です。
  - リングの本体（最大 65536 frames × 4 bytes = 256 KiB）は、`host_audio.start` で pool と同じく `page_allocator` から**一度だけ**確保します。
  - `PCM-CLOSE` は**メモリを解放しません**。解放するのは、音の停止処理で join が成功した後だけです。
  - これで「期限切れの consumer へ無理に free しない」が構造として保証されます。State には永続化する field を置きません。

### H2. 中断を ior で返している（共通取り決めと前例に反する）
- **根拠**
  - 提案 20行目は、`PCM-WAIT` の中断を `false,-28` で返します。提案 22行目は、`PCM-CLOSE` が後始末の後で -28 を返します。
  - 共通取り決め（ASYNC_COMMON_RULES §2）は「中断は -28 の THROW。ior では返さない」としています。
  - 非同期 I/O の前例（ASYNC_IO_DESIGN 48行目）では、閉じる操作が中断された場合は EINTR=-516 を返し、ID を保持します。
- **修正**
  - `PCM-WAIT` と `PCM-STOP` の待機中の中断は **THROW -28** にします。
  - `PCM-CLOSE` の ack 待ち中の中断は **-516 を返し、handle を closing のまま保持**します。もう一度 CLOSE を呼べば待機を続けます。

### H3. 時間引数の形が既存の語とそろっていない
- **根拠**
  - 提案は ns を取り、-1 だけを無期限、-2 以下を不正としています。
  - 共通取り決め（決定が要る点の #4、詳細設計 §4.3）と、実装済みの `WAIT-FILES`・`PROC-WAIT`・`EKEY-WAIT` は、いずれも**相対ミリ秒、0 はポーリング、負の数は無期限**です。
  - 音の待機はもともと 3 ms 刻み（`host_wait.zig:371`）で、音のスレッドも 10 ms 単位で消費します。ns の分解能を取っても意味がありません。
- **修正**
  - 引数は ms にそろえます。期限は `Writer.standard_clock` で一度だけ計算します（`base.Deadline.afterMilliseconds`）。
  - clock がなければ THROW -21 とします。

### H4. 音の停止処理が backend ごとに決まっておらず、現状の欠陥も前提に入っていない
ソースで確認した現状は次のとおりです。
- スレッドは detach されています（`host_audio.zig:75,88`）。
- 失敗した後は `device_open=false` になりますが、装置は開いたままです（`:96`）。
- `windows.open` が途中で失敗すると、event と device が漏れます（`:212-226`）。
- `openAlsa` で `set_params` が失敗すると、pcm が開いたまま pipe 経路へ進みます（`:346-348`）。
- pipe の子プロセスの pid を保持していません（`:403`）。
- mac は Dispose をしていません。

方式は §3 で確定します。

### H5. 「古い handle は世代と owner の検査で拒否する」は保証できない
- **根拠**
  - 詳細設計 §4.1 と共通取り決め §7 は、epoch が一意だと検証できるまで、起動をまたぐ拒否をうたわないとしています。
  - PROC の ID は毎回 `first_id` から始まります（`host_process_table.zig:12`）。
  - `ResourceKind.pcm` はありますが、`OwnedTable` は本番コードではまだ使われていません。
- **修正**
  - 文言を次のように直します。「同じプロセスの中で閉じた handle や古い handle は EBADF にする。保存したイメージに残った値は、新しい起動の stream と一致することがある（落ちないことだけを保証する）」。
  - handle は PROC と同じ方式にします。固定の起点から単調に増やし、使い回さず、0 は無効です。

## 2. 指摘（Medium）と確定案

| # | 問題 | 修正 |
|---|---|---|
| M1 | capacity の範囲 256..65536 は、1秒分の上限（決定が要る点の #9）を超えます（8 kHz なら 8 秒）。また 192 kHz で 256 frames だと、1回の render（480 出力 frames = 入力 1920 frames）より小さく、必ず underrun します。 | **2の累乗、256≤c≤65536、c≤hz、c×25≥hz**（40 ms 以上 1 秒以下）とします。どの Hz にも有効な値があります（例：8000 Hz は 512..4096、192000 Hz は 8192..65536）。 |
| M2 | 「resampler が保持している frame を含む一貫した snapshot」は、原子的に読めません。 | 保持中の frame の **head は進めません**（peek で読み、出力し終えたら drop）。QUEUED は `tail − head.load(acquire)` だけで決まり、drain の完了は `head==tail` で判定できます。 |
| M3 | open 直後の空状態を underrun として数えると、必ず1回数えてしまいます。 | 1 frame 以上消費した後で running 中に空になった、という遷移だけを1回の episode として数えます。stopped と drain の後は数えません。 |
| M4 | 不正な値やアドレスを ior で返しています。前例の `WAIT-FILES` は、引数を peek したまま -24 と -9 を THROW します（`words_async_io.zig:14-19`）。 | 範囲外の数値は THROW -24、不正なメモリは THROW -9（引数は保持）にします。資源の状態に関するものだけを ior で返します。 |
| M5 | OPEN で ack を待つ必要はありません。また producer が head をリセットすると、SPSC の所有（head を書くのは consumer だけ）に違反します。 | 前の stream が ack 済みなら、head==tail です。添字は u32 のまま連続させ（2の累乗なので折り返しても正しく動きます）、OPEN では設定を書いてから `stream_generation` を release で公開するだけにします。consumer は render の入口で世代の変化を見て、自分の状態をリセットします。 |
| M6 | 装置がないとき、装置が失敗したとき、engine を起動できないときの扱いが未記載です（EMULATOR 計画 §9 の未決）。 | 装置なし・失敗後も、silent 経路が時間どおりに消費するので、PCM はそのまま動きます（状態は `AUDIO?` で見ます）。`audio_fn` がなければ THROW -21、engine を起動できなければ既存の `getEngine` と同じく -265 です。 |
| M7 | 完全復元のときの扱いが未決です。apply は失敗しない作りで、資源の検査もしていません（`image_restore.zig:23-109`）。stream を残すと、1つしかない枠が永久に塞がります。 | apply の中で、失敗しない **abandon** をします。closing にして close 要求を投げ、handle を無効にします。後の OPEN は、ack を最大 1000 ms 待ちます。typed append では stream を残します。SAVE は許可し、LOAD で自動再開はしません。 |
| M8 | 詳細設計 §8 は、残量、engine の取得位置、装置へ渡した位置、実再生位置を区別することを求めています。 | 初版は QUEUED（リングの残量）だけにします。装置側の位置と実再生位置は「能力なし」と明記します。 |

### 確定 API
- **語の登録**：既存の流儀にそろえ、組込み語は `SND-PCM-*` として定義表の末尾に追加し、`audio.fs` で `PCM-*` を定義します。
- **ior の値**（どの OS でも同じ errno 値の範囲）：
  - EBADF -521：不正、閉じた後、古い handle
  - EBUSY -528：OPEN 時にすでに使用中、ack の期限切れ
  - EINVAL -534：stopping または stopped の stream への WRITE や WAIT
  - ENOMEM -524：stream 用のバッファがない
  - EINTR -516：CLOSE の中断

各語のスタック効果と動作：

- `PCM-OPEN ( hz channels capacity -- pcm ior )`
  - hz は 8000..192000、channels は 1 か 2、capacity は M1 のとおり。
  - 前の close の ack を待つ場合だけ、最大 1000 ms 待ちます（中断は THROW -28）。
- `PCM-WRITE ( addr frames pcm -- written ior )`
  - 待たずに、空いている分だけコピーします。満杯なら `0 0` です。
  - frames=0 のときはメモリを検査しません。検査の後でコピーが失敗することはないので、written と ior が同時に 0 以外になることはありません。
- `PCM-QUEUED ( pcm -- frames ior )`
- `PCM-WAIT ( frames ms pcm -- flag ior )`
  - frames は 1..capacity。期限切れは `false 0` です。
  - `audio_wait_fn` で 3 ms ずつポーリングします（起床の通知は使いません）。
- `PCM-STOP ( mode ms pcm -- flag ior )`
  - drain：producer 側で `head==tail` まで待ちます。期限切れや中断のとき、stream は running のまま変わりません。
  - drain の後、または discard のとき：停止要求を投げて stopping にし、残りの期限の中で ack を待ちます。ack が来れば `true 0`、期限切れは `false 0` で stopping のまま、中断は THROW -28 で、要求は残ります。
- `PCM-CLOSE ( pcm -- ior )`
  - stopped なら、待たずに無効化します。
  - それ以外は discard と close の要求を投げ、ack を内部で固定の 1000 ms 待ちます。
- `PCM-UNDERRUNS ( pcm -- u ior )`
- **mailbox**：producer は `request_kind` を書いてから `request_seq` を release で書きます。consumer は `ack_seq` を書きます。前の要求の ack が来るまで、次の要求は投げません。consumer は render の入口で mailbox を処理します（discard は `head = tail.load(acquire)` と resampler のリセット）。
- **resampler**（ZOH、フィルターなし）：
  - phase は 0 ≤ phase < out_rate の整数です。1 frame 出力するごとに `phase += hz` とし、`phase ≥ out_rate` の間は `phase -= out_rate` して drop と peek を繰り返します。
  - peek で frame がなければ、無音を出して phase を 0 に戻します。古い frame を伸ばして出し続けることはしません。
  - mono は左右に同じ値を入れます。
  - 既存の filtered の結果と i32 で加算し、[-32768, 32767] に飽和させます。

## 3. 期限付きで終わる停止処理（backend ごとの確定案）

**共通の流れ**
1. `host_audio.shutdown(1000 ms)` が `stop_requested` を立てます。
2. backend の待機を起こします。
3. スレッドが最後の処理として立てる `thread_exited` を、5 ms ごとに期限まで見ます。
4. 立っていれば join し、VM のスレッドで装置を解放します。期限を過ぎたら detach し、**装置もメモリも解放せず**「未完了」を debug log に記録して終了処理を続けます（現状と同じく、残りはプロセスの終了で片付きます）。

`pthread_timedjoin_np` は musl と mac での可否が未確認なので使いません。defer は `main.zig:3687` と `3688` の間に登録します。こうすると、window を閉じる直前に実行され、runtime の解放と `storage.free` より必ず前になります。`state==.failed` で装置だけが開いている場合も解放します。

| backend | 停止の方法 | 解放（join の後） |
|---|---|---|
| Windows waveOut | 既存の `WaitForSingleObject(event,100)` のループで stop を見る。`SetEvent` ですぐに起こす | `waveOutReset` → 各 header の `UnprepareHeader` → `waveOutClose` → `CloseHandle(event)`。`device_open` とは別に、所有しているかの印を持つ。open の失敗時も同じ関数で戻す |
| Linux Pulse simple | 書込みと書込みの間で stop を見る。止まっている書込みは**中断しない** | join できたときだけ `pa_simple_free`。期限切れなら abandon |
| Linux ALSA | `set_params` の後で `snd_pcm_nonblock(pcm,1)`。EAGAIN なら `snd_pcm_wait(pcm,20)` で待ち、stop を見る | `snd_pcm_drop` → `snd_pcm_close`。open の失敗時も close する |
| Linux pipe | pid を保持する。書込み側を O_NONBLOCK にし（専有している fd）、EAGAIN なら `poll(POLLOUT,20)` で待ち、stop を見る | `close(fd)` → `waitpid(pid,WNOHANG)` で期限まで待つ → `kill(-pid,SIGTERM)` → `SIGKILL` → 回収。process registry には入れない（registry は pid を指定する `waitid` だけを使い、全体を回収する処理はない。確認済み） |
| macOS AudioQueue | 待機を 10 ms 刻みにし、stop で `stopping` を立てる。refill は stopping なら render も enqueue もしない | 音のスレッドの上で `AudioQueueStop(q,1)` → `AudioQueueDispose(q,1)` を行い、その後で exited を立てる |
| silent | 5 ms のループで stop を見る | なし |

Pulse の async 移行は前提にしません。abandon が実際に起きると分かった場合の、任意の後続作業とします。

## 4. 後続タスク案（依存関係つき）と最小限の検証

1. **998-a 採用仕様の文書**：この報告の値を別の文書に固定します。提案の文書自体は変えません。
2. **998-b コア**（a に依存）：`sound_stream.zig`、mailbox、resampler、合成。
   - 最小限の検証：
     - capacity の検証表
     - 部分書込み、満杯、u32 の折り返し（head と tail を 2³²−8 から始める）
     - render を 480、1+479、7 frames ずつに分けても出力が一致すること
     - 44100 Hz で 48000 出力 frames ちょうどに 44100 入力 frames を消費すること
     - underrun の episode の数え方
     - 飽和
     - consumer が止まった状態での CLOSE → EBUSY、再度の CLOSE → 0
     - 中断で -516
     - 復元時の abandon → OPEN
3. **998-c ホストの寿命管理**（a に依存。b とは並行可）：§3 の内容と、open 失敗時の後始末。
   - 最小限の検証：
     - 書込みが永久に止まる偽の backend で、期限内に「未完了」で戻り、解放しないこと
     - Windows で open と停止を 20 回繰り返し、handle の数が増えないこと
     - Linux pipe で、代わりのコマンドの子プロセスを回収し、fd の数が戻ること
     - 装置がない環境でスキップすること
4. **998-d 公開語**（b、c、1056、1064 に依存）：`SND-PCM-*`、`audio.fs`、英語と日本語の HELP、`library_words`、復元時の abandon、語群の除外の組合せと保存アプリからの起動。
5. **998-e Windows/Linux の受け入れ**（c、d に依存。実際に音を聞く確認は利用者）
6. **998-f Mac 実機**（c、d に依存）：Stop/Dispose の後にコールバックが来ないこと。
7. **（任意）Pulse の async 移行**（e で abandon が観測された場合だけ）

**実装前に公式文書で確認する外部 API の挙動（未確認）**
- `waveOutReset` がすぐに戻り、すべての header を完了扱いにすること
- `snd_pcm_nonblock` と `snd_pcm_wait` の意味
- `pa_simple_write` が止まる時間の上限
- 同期の `AudioQueueStop` と `AudioQueueDispose` の後にコールバックが来ないこと

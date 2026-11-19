<!-- Claude Code, 2026-11-19, session 0e73077f-57af-43fb-aedf-e620ee6b9326. Fixed integration snapshot; original response follows. -->

# 900 統合(1061・1062)レビュー — 対象は `.work/900-review/integration/` の固定コピー

レモン、レビュー結果です。ファイルの変更、Git 操作、テストの実行、外部アクセスはしていません。コードを読んで判断した結果です。OS の挙動のうち確認していないものには「※推測」を付けています。

前回の指摘のうち次の2点は、統合で解消を確認しました。
- 別の台帳との ID 衝突: epoch を共通の採番器から台帳ごとに割り当てるようになりました。
- owner の再利用: 採番器が owner と epoch を再利用しなくなりました。

POSIX の通知集約(`pending`)で、通知が永久に失われる経路は見つかりませんでした。

---

## 現在の欠陥

### 1. 【高】終了処理(end)が失敗すると、信号の所有がセッションの終わりまで残る
- **対象**: `host_wait.zig:159-164`、`:171-179`、`host_signal_broker.zig:2-3, 36-43`、`host_wait.zig:42-47`
- **失敗する条件**:
  - `Ticket.hooks.context` は、`waitUsing`/`audioWait` のスタック上にある `native`(NativeScope)を指しています。
  - end が失敗すると、Broker は所有を残したまま関数が戻ります。このとき Ticket と保存していた端末の状態(termios、コンソールのモード)が捨てられます。
  - Broker の注記にある「Ticket を使って再試行できる」経路が、実際には存在しません。
  - 結果として次のことが起きます。
    - プロセス全体の所有者 `process_owner` が残るため、fallback を含むすべての Broker で、以降の NS と PLAY が HostFailed になります。
    - 終了時の `runtime.deinit` が `ResourceBusy` になり、`libc.exit(1)` に進みます(2 の経路)。
  - `waitUsing:163-164` は `try outcome` を先に評価します。そのため UserInterrupt と復元の失敗が重なると、復元の失敗が報告されません。
  - `audioWait` は end が失敗すると `interrupted` を消費しないまま戻ります。
  - Windows では、SetConsoleMode の失敗後に再試行すると、ハンドラーの削除がもう一度呼ばれます。登録されていないハンドラーの削除は失敗を返すため、再試行が永久に成功しない可能性があります(※推測。Microsoft の資料は未確認です)。
- **修正案**: 方針を決めて契約に書きます。
  - (a) end では、復元を一度試した結果にかかわらず所有を解放し、エラーだけを返す。保存状態はもう失われているので、所有を残しても意味がありません。
  - (b) Ticket と NativeScope を Runtime が所有する領域に置き、次の begin や shutdown の時点で再試行する。

  どちらの場合も、エラーの優先順位を「復元の失敗 > 中断」にし、Windows の end は削除済みかどうかを覚えて冪等にします。試験は「waitUsing/audioWait の end が失敗した後、次の待機と deinit がどうなるか」を追加します。

### 2. 【中〜高】`libc.exit(1)` の経路で、出力の吐き出しとコンソールの復元が飛ばされる
- **対象**: `main.zig:2101-2106`。飛ばされる defer は `:2050-2058`
- **失敗する条件**: deinit が失敗すると、以前に登録された defer がすべて実行されません。
  - `utf8_console.finish()`(`main.zig:1093-` で `flushOutput` を呼び、コード ページを元に戻す)
  - `flushOutput()`
  - `resize_scope.end()`

  その結果、`output_buffer` に残った出力が失われ、Windows のコンソールが CP65001 のまま残ります。エラーの文言が標準出力より先に出るため、出力の順序も入れ替わります。

  また、現在の main は台帳を作らないので、deinit が失敗する現実的な原因は「信号の所有が残った」(1)だけです。この場合は VM の Storage を使っている者はいないため、`exit` までする根拠がありません。
- **修正案**:
  - `catch` の中で、Storage に触れない後片付け(`flushOutput`、`utf8_console.finish`、resize の後片付け)を明示的に呼んでから exit する。resize の後片付けが Storage に触れないかどうかは未確認です。
  - `ResourceBusy` を原因で分け、`exit` は台帳や参加スレッドが残っている場合に限る。

### 3. 【中】OwnedTable をコピーすると、同じ Handle が二重に発行され、`tables` の数が壊れる
- **対象**: `host_runtime.zig:83-89`(値で返す `newTable`)、`:114-119`
- **失敗する条件**: 契約は「共有後のコピー禁止」ですが、`newTable` は値で返すので、共有前のコピーは防げません。
  - コピーした2つは同じ epoch と `next_serial` を持つため、どちらも `{E,1}` を発行します。片方の Handle がもう片方の別の資源として通ります。これは今回の重点である「再生成時の ID 衝突」の残りです。
  - 両方を deinit すると `runtime.tables -= 1` が2回行われます。Debug/ReleaseSafe では panic、ReleaseFast では値が折り返し、deinit が常に `ResourceBusy` になって 2 の exit に進みます。
- **修正案**:
  - `newTable(self, out: *OwnedTable)` のように、その場で初期化する形にする。
  - または初期化時に自分のアドレスを記録し、各操作で `@intFromPtr(self)` と照合する。
  - `tables` の減算は、閉じた印との組合せで一度だけにする。

  あわせて、コピーの誤用を検出する試験を追加します。

### 4. 【中】`Runtime.phase` を通知側から非原子的に読んでいる
- **対象**: `host_runtime.zig:46, 51, 56`(読み取り)、`:72, 81`(書き込み)
- **失敗する条件**: Wake は通知側が複数ある前提で、`Runtime.notify` はその自然な入口です。一方、`beginShutdown` はまさに「通知側が動いている間」に `phase` へ書き込みます(join はその後)。この読み書きは、Zig のメモリーモデルではデータ競合(未定義動作)です。
- **修正案**:
  - `phase` を `std.atomic.Value` にする(書き込みは release、読み取りは acquire)。
  - または「別スレッドからは Wake の ops だけを使い、`Runtime.notify` を呼ばない」と明記し、型の上で分ける。

### 5. 【中】音の waitTaken が host_failed のとき、待たずに 300 回空回りする
- **対象**: `words_audio.zig:534-540`(結果を無視している)、`host_wait.zig:169-172`(begin の前に眠らず即座に返す)、`words_audio.zig:509`
- **失敗する条件**: host_failed では待機が発生しないため、「約1秒」の上限が数マイクロ秒で尽きます。
  - `0 PLAY`、MOD の開始、BEEP/stop が、音のスレッドがコマンドを受け取る前に戻ります。「MOD? がすぐに真になる」という前提が崩れます。
  - `play` のエラー経路では、`reset(...) catch {}` がエラーを捨てます。そのため、キューにノートが残ったまま HostFailed が投げられることがあります。
  - 1 で所有が残ると、これが毎回起きます。
  - 既存の試験(`audio_test.zig:233`)は1回目だけを失敗させているので、この問題を検出できません。
- **修正案**:
  - waitTaken では、host_failed のときに信号の範囲を持たない単純な sleep で待つ。または HostFailed を呼出し元へ返す。
  - 「すべての待機が host_failed」になる試験を追加する。

### 6. 【低〜中】POSIX: 消費側の `pending` の解除が RMW ではない
- **対象**: `host_wake.zig:154`、`:103`
- **失敗する条件**: 消費側は `store(false)` で解除しています。そのため、「swap で true を見て書き込みを省いた通知側」から消費側の次の世代の読み取りへ、happens-before の関係が形式上できません。弱いメモリー順序の環境(ARM)では、通知に気づくのが次の 20ms の区切りまで遅れる可能性があります。待機は 20ms ごとに区切られているので、永久に取りこぼすことはありません(※メモリーモデルからの推論です)。
- **修正案**:
  - `_ = self.pending.swap(false, .acq_rel)` にして、release sequence に参加させる。
  - 試験の補強: 1000 回の通知でも、`pending` があるため pipe へは1バイトしか書かれません。そのため次の2つが試験で通っていません。
    - EAGAIN の分岐(`:107`)
    - 書き込みに失敗したときの `pending` の解除(`:109`)

    複数の通知側を同時に動かす負荷試験もありません。

### 7. 【低】Wake.deinit が失敗した後、Runtime.deinit を再度呼ぶと成功して見える
- **対象**: `host_runtime.zig:77-82`、`host_wake.zig:56-69`
- **失敗する条件**: Wake は close の前に fd/HANDLE を無効値にします。そのため、2回目の `Runtime.deinit` は何も閉じずに成功し、`phase = .closed` になって最初の失敗が見えなくなります。main は1回目で exit するので、今は実害はありません。
- **修正案**: 失敗したときも `.closed`(または `.failed`)へ移し、エラーは一度だけ返します。

### 8. 【低】試験の後片付けで `catch unreachable` を使っている
- **対象**: `host_runtime.zig:125, 181`、`host_wait.zig:218`
- **失敗する条件**: 台帳や信号の範囲を保持したまま途中の expect が失敗すると、defer の deinit が `ResourceBusy` を返して panic します。元の失敗が隠れ、テストのバイナリ全体が止まります。特に `host_wait.zig:225-228` は、所有を保持したまま expect をしています。
- **修正案**: `catch |e| std.debug.print(...)` にするか、errdefer で保持中の資源を先に解放します。

---

## API の将来案(現在の欠陥ではありません)

### 9. owner の単位が Runtime だけになっている
- **対象**: `host_runtime.zig:104, 108, 112`
- OwnedTable は常に `runtime.owner` を使います。そのため、task ごとの所有の分離と、前回の #9(WrongKind/WrongOwner の違いから他者の資源が分かる問題)には、現在の API からは到達しません。task を導入するときには owner を引数で受け取り、検査の順序も見直す必要があります。
- `get` が返す `*Payload` は、remove した後や枠が再利用された後に、別の資源を指します。今の契約(ホストスレッド限定)の範囲内ですが、明記を勧めます。

### 10. 公開型から epoch を任意に指定できる
- **対象**: `runtime_base.zig:81`
- `ResourceTable.init(epoch)` は公開されているので、共通の採番器を通さずに台帳を作れます。その epoch が採番器の値と衝突する余地が型の上で残っています。`host_runtime` 経由に限定する(または採番器の値を受け取る型にする)ことを、将来の検討として挙げます。

---

## 確認して問題を見つけなかった点
- Broker の begin が失敗したときの巻き戻し(depth が 1 のときだけ `process_owner` を解放する)と、入れ子の begin が失敗したときに所有を保持する点
- NS の raw モードの処理(ISIG を有効にし、QUIT/SUSP などを無効化)が、`wait` と `waitWithRuntime` で共通の `waitUsing` を通っている点
- main の defer の順序: profile/lint の表示 → `beginShutdown` → 従来の資源の解放 → `runtime.deinit` → Storage の解放
- `beginShutdown` の後に Forth のコードが動く経路がない点

**未確認の事項**:
- 統合前の音の待機(POSIX)と NS の実装との差分: Git 操作をしない条件のため比べていません。`host_audio.zig:174, 202` に、使われていない `SetConsoleCtrlHandler` と `ctrl_c_event` の宣言が残っています。
- `resize_scope.end` が何をするか

---

## 読んだ範囲
- 固定コピー: `host_runtime.zig`、`host_signal_broker.zig`、`host_wait.zig`、`host_wake.zig`、`runtime_base.zig`、`runtime_base_test.zig`、`host_audio.zig`(全体)
- 固定コピーの一部: `main.zig`(`:161`、`:255-274`、`:1060-1123`、`:1745-1773`、`:2000-2199`、`:2744-2770`)、`words_audio.zig:499-584` と `:90-100, 215-230`、`host_interface.zig:127-141, 282-285`、`audio_test.zig:200-279`
- リポジトリ: `docs/reviews/900-runtime-initial.md`、`src/runtime_test.zig`、`build.zig:110-125`、`src` 全体の SIGINT/ConsoleCtrlHandler の検索結果

## 実行していないこと
ビルド、テストの実行、Git 操作、`host_clock.zig` の再読、設計書(docs)の照合、OS 仕様の確認(Windows の `SetConsoleCtrlHandler` の削除の挙動、端末が切断されたときの `tcsetattr` の失敗)

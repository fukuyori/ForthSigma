# 643 Tcl移行レビュー原文

2026-11-19。Read/Grep/Globだけを許可したread-onlyレビュー。ビルドと実行結果は別記録。

## 初回

Warning: this sign-in may have ended between 2026-11-16 and 2026-11-19. If requests are refused, run claude auth login, or use claude setup-token for unattended jobs.
# Tcl 移行レビュー（読み取りのみ・ビルドとテストは未実行）

レモン、Read/Grep/Glob だけでレビューしました。ファイルは変更していません。旧コードは削除済みで、git 履歴は見ていません。そのため「旧挙動」と書いた箇所は、残っているコメントと契約文からの判断です（旧コードそのものは未確認）。

## 具体的な不具合

### 1. Windows: wish の探索と起動で、探す範囲が食い違っている（中）
`host_process.zig:227-239`
- `SearchPathW(null, "wish", ".exe")` は PATH 以外も探します。Sigma の exe があるディレクトリ、カレントディレクトリ、システムディレクトリです。ここで見つかると `on_path != 0` になり、`programName` は見つかったフルパスを捨てて `"wish"` を返します。
- 移行後は `spec.resolveProgram` が、子に渡す環境の PATH だけを探します（設計 30 行目）。
- その結果、wish.exe が Sigma と同じディレクトリかカレントディレクトリにしかない場合は ENOENT で起動に失敗します。さらに `on_path != 0` なので、Git for Windows の場所（`git_places`）も試されません。
- 旧経路はコマンドラインの `"wish"` を CreateProcess の探索で見つけていたと推測されます（※推測です）。
- 修正方針の候補は 2 つです。
  - `found` のフルパスを返す。ただしカレントディレクトリから見つかったものを採用するかは、安全面で別に判断が必要です。
  - PATH だけの判定に揃え、解決できなければ `git_places` へ進む。

### 2. Sigma 終了時、wish の子孫が KILL されない（設計 55 行目との相違）
`main.zig:3459-3461` → `host_process.zig:89-113`
- 終了時は `host_process.stop` が `closeAllProcesses` より先に動きます。wish が stdin の EOF で 2 秒以内に自分で終われば、group/Job へ KILL を送らずに `free` します。
- Windows の Job は KILL_ON_JOB_CLOSE を使っていません。POSIX では group を手放します。どちらでも、Tcl スクリプトが起動した子孫が残ります。
- 設計 55 行目は「FREEされていない全group/Job（直接の子が既に終わったものも含む）へKILL」です。Tcl は直前に FREE されるので文面上は対象外になりますが、内部枠を共通表に載せた意図とずれます。
- 修正するなら、終了時の停止だけ `free` の前に `signal(force)` を入れる形になります。

### 3. 解放は済んでいるのに stop が false を返す（小）
`host_process.zig:112`
- 次の 2 つの場合、内部エントリは削除済みで `shared_id == 0` なのに false を返します。
  - `tclClose` の fclose が失敗した場合（設計 92 行目どおり、所有は手放し済み）
  - POSIX の ECHILD で `freeWithin` が除去後に `ior(10)` を返した場合
- 影響:
  - GFX-TCL-STOP が HostFailed を投げます。
  - `startProgram` 内の事前停止でこれが起きると、SHOW が 1 回だけ失敗します。次の試行では成功します。
- エラーの報告と「次に起動できるか」を分けるかどうかは、判断が必要です。

## 確認して問題がなかった点

- **起動失敗時の後始末（rollback の所有）**
  - `tclLaunch` は失敗しても ID を返し、`launchShared` が `shared_id` に入れてから `stopProgram` で `freeWithin` します（`host_process.zig:58-62`）。
  - `abortStart` が失敗した場合は `native_owned` が残り、次の `freeWithin` が `abortStart` をやり直します。
  - `startWithin` 中の `stop_internal` は、`shared_id` がまだ 0 なので何もしません。生ハンドルも未設定なので問題ありません。
- **一時スクリプトの寿命**
  - 削除は、レジストリが実際に除去したときの `releasedInternal` だけで行われます。
  - `startProgram` の errdefer は `shared_id == 0` のときだけ削除します。
  - `stopProgram` が true を返すには `shared_id == 0` が必要なので、`writeScript` が前回の名前を上書きすることはありません。
  - `Registry.shutdown` で解放された場合も、コールバック経由で削除されます。
- **内部 ID の非公開**
  - 公開側の経路はすべて `index(id, false)` か `getPublic` を通り、内部枠には届きません。
  - `internalStream` は内部エントリかどうかを確認します。
  - 内部エントリは `room` も publish も通りません。
- **生 FILE と fd/HANDLE の寿命**
  - FILE を閉じる経路は 3 つあります。`tclClose`、`abortStart`/`freeWithin`/`shutdown` の後の native destroy/abort です。どれも、その前に detach（`stopProgram` 冒頭か `closeStreams`→`stop_internal`）を通ります。
  - 親側の端は、Windows では `_O_NOINHERIT` と継承許可リスト、POSIX では CLOEXEC になっていて、後から起動する PROC の子へは漏れません。
  - Linux で `O_NONBLOCK` を付けても、FILE は `_IONBF` で使われないため問題ありません。
- **表示時間の上限（display budget）**
  - `cleanupLimit()` は、起動失敗時の後始末と FREE の両方を `until` 以内（最大 3000ms）に抑えます。
  - 上限が切れていて終了を確認できない場合は、FREE せずに所有を残し、次回やり直します。
- **終了時の文脈**
  - defer は beginShutdown → `host_process.stop` → … → `closeAllProcesses` の順に動きます。
  - `stop` は runtime も table も使いません。`&host` もまだ有効です。
  - stop に失敗して残ったものは、`shutdown` の KILL と 3 秒待ちで回収されます。

## 判断が必要な事項（不具合ではなく選択）

1. **前の wish を止められないと、新しい wish を起動できない**
   - `tcl.zig:333-334` は「the next use starts a new one all the same」としています。
   - 内部枠は 1 つだけで、`startProgram` は前のエントリを解放できるまで起動しません。旧 singleton は放棄して起動していたと推測されます（※推測です）。
   - 実際には KILL の後に回収できるので、影響は小さいです。
2. **終了にかかる時間**
   - Tcl の停止は 2 秒 + 1 秒 + 3 秒 + FREE で、そのあと共通の 3 秒が続きます。
   - 設計 94 行目の「全体3秒」に Tcl を含めるかどうかは未定です。
   - 停止を待つ間、Ctrl+C では中断できません。
3. **POSIX の起動制約が Tcl にも適用される**
   - SIGCHLD が SIG_IGN か NOCLDWAIT のときは ECHILD で起動しません。
   - wish は独立した process group になり、端末の Ctrl+C や SIGHUP が届かなくなります。
4. **wish の stderr を null にしている**（`main.zig:1869`）
   - Tk の起動エラー（display に接続できない等）が端末に出なくなります。
   - 旧挙動が継承だったかは未確認です。
5. **Windows で起動できるプログラムの条件が変わった**
   - SIGMA_WISH / TCL-PROGRAM について、argv[0] に `"` を含むものと、.bat/.cmd を拒否します。
   - Job への割り当てが失敗すると、起動失敗になります。
   - 旧挙動との差は未確認です。
6. **Windows では TERM も KILL と同じ強制終了になる**
   - TERM は TerminateJobObject(143) です。契約どおりで、待ってから KILL するので実害はありません。
7. **内部 ID の消費が利用者から見える**
   - 内部 ID は公開 ID と同じ連番から取るため、PROC-NEW の ID が 1 つ飛びます。
   - 利用者には Tcl が起動したことが推測できますが、その ID ではアクセスできません。
8. **process_native が使えない OS では Tcl が使えない**
   - `process_native.available` が false の OS では、Tcl が -21 になります。
   - そうした OS で graphics ビルドがあるかは未確認です。

## 未確認

- ビルドとテストの結果（実行していません）
- 旧コードの stderr、プロセスグループ、探索の挙動
- 移行後の GUI の前面表示

1〜3 を修正するか、選択事項として記録するかを指示してください。

## 修正後

Warning: this sign-in may have ended between 2026-11-16 and 2026-11-19. If requests are refused, run claude auth login, or use claude setup-token for unattended jobs.
レモン、再レビューの結果です。Read/Grep/Glob だけで確認し、ファイルは変更していません。ビルドとテストは実行していないため、結果は未確認です。

**結論：Shared アダプタ、main の Tcl コールバック、レジストリの shutdown の 3 箇所に、修正が必要な不具合は見つかりませんでした。** 前回の指摘 1・2 と stderr の件は解消しています。指摘 3 は、意図した方針として扱えば問題ありません。

## 解消を確認した点

1. **Windows の `programName` が見つけたフルパスを返す**（`host_process.zig:226-232`）
   - `SearchPathW` で見つかった `found` を `buffer` にコピーして返しています。
   - 見つからない場合（`on_path == 0`）だけ `git_places` を試し、どこにもなければ `"wish"` を返します。
   - パスが長すぎて `found` に入らない場合（`on_path >= found.len`）は、`"wish"` を返して PATH での探索に任せます。コメントの記述と一致しています。

2. **終了時の Tcl の停止をレジストリの shutdown に一本化**
   - 終了時の defer は `runtime.beginShutdown` だけになり、`host_process.stop` は呼ばれていません（`main.zig:3458-3461`）。
   - Tcl は `closeAllProcesses` → `Registry.shutdown` の中で、公開エントリと同じように処理されます（`host_process_registry.zig:223-253`）。
     - 第 1 段階：起動済みのものすべてに KILL を送ります。直接の子が終わったものも対象なので、子孫も止まります。これは設計 55 行目どおりです。
     - 第 2 段階：期限は全体で 1 つ（3 秒）です。`closeStreams` は内部エントリでは `tclDetach` を呼んでアダプタの参照を外すだけです。生の FILE は、その後 `freeWithin` の中の `destroy` が閉じます。
     - 最後に `released_internal` が呼ばれ、一時スクリプトが削除されます。
   - 回収しきれなかった場合は `processes` が残り、`shared_id` も 0 にならないので、両者は食い違いません。

3. **stderr の扱い**（`main.zig:1869`）
   - POSIX は `inherit`（mode 1）に戻っています。
   - Windows は `ignore`（mode 2）です。stdin と stdout は既定の `pipe` のままです。

## 意図した方針として扱ってよい点

- **後始末は成功したのにエラーを報告する**
  - fclose の失敗や ECHILD では、`freeWithin` がエントリを除去し、`releasedInternal` で `shared_id` が 0 になります。そのうえで `stopProgram` は false を返し、HostFailed になります。次の起動は再試行できます。
  - 設計 92 行目（fclose は失敗しても所有を手放し、エラーは報告する）とも一致しています。
  - **文言に相違があります。** `WORD_REFERENCE.md:32250` の GFX-TCL-STOP は「-265 when the host could not see it end」と書いています。プロセスの終了は確認できたが後始末でエラーが出た場合も -265 になることは、この説明には含まれていません。動作を正とするなら、説明（英語版・日本語版）を広げる必要があります。
- **所有が解放されないうちは、次の wish を起動しない**
  - `startProgram` の冒頭で `stopProgram` が false を返すと起動しません（`:250`, `:493`）。
  - `tcl.zig:333-334` のコメント「next use retries cleanup before starting another owned program」と一致しています。
- **終了時は wish に EOF での猶予を与えず、すぐに KILL する**
  - 期限を全体で 1 つにしたことの結果で、仕様どおりです。

## 不具合ではないが、判断が必要な点

1. **失敗した後に TCL-STOP を繰り返すと、何もせずに成功を返す**（`tcl.zig:336`）
   - `halt` は最初に `running = false` にします。そのため停止に失敗したあとの 2 回目の TCL-STOP は、`shared_id != 0` のままでも後始末を再試行せずに成功を返します。
   - 再試行は次の起動のときに行われるので、所有の扱いとしては安全です。ただし、利用者は 2 回目の成功を見て停止できたと読む可能性があります。
   - 旧 singleton でも同じ動作だったと推測されます（※推測です）。
2. **Windows でカレントディレクトリの wish.exe を起動しうる**
   - `SearchPathW(null, …)` は PATH のほかに、Sigma の exe があるディレクトリとカレントディレクトリも探します。見つかったフルパスがそのまま起動されます。
   - 旧経路も CreateProcess の探索だったので、同じ範囲だったと推測されます（※推測です）。安全面でこの範囲を許すかどうかは方針の判断です。
3. **TCL-PROGRAM や SIGMA_WISH に名前だけを渡すと、探索は PATH だけになる**
   - `spec.resolveProgram` が子に渡す PATH だけを探します。`"wish"` に戻した場合も同じです。
   - 旧経路の CreateProcess の探索（exe のディレクトリやカレントディレクトリも含む）より範囲が狭くなります。
4. **到達しない確認が残っている**（`host_process.zig:229`）
   - `on_path > buffer.len` は成り立ちません。`on_path < found.len`（512）で、`buffer` も 512 だからです。害はありません。

## 未確認

- ビルドとテストの結果
- Windows の `SearchPathW` の安全探索モードの設定と、実際の探索順序
- 実機での終了時の子孫回収（Windows の Job、POSIX の process group）

判断が必要な点 1〜3 と GFX-TCL-STOP の説明文について、修正するか記録に残すかを指示してください。

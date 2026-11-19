# 643 子プロセス管理設計のClaude Codeレビュー原文

2026-11-19。読取り専用レビュー。試験はロクが別途行う。

## 初回レビュー

# 子プロセス管理（643/1097）残り3点の決定案

読んだのは、指定の5か所（PROCESS_MANAGEMENT_DESIGN.md、ASYNC_CORE_PLAN.md の5節、host_process.zig、main.zig の FileSlot・fileClose・closeAllFiles・drainWriter、host_file_reader.zig）と、ASYNC_IO_DESIGN.md の中断の記述だけです。ファイルの編集とコマンドの実行はしていません。試験も実行していないので、動作の確認はすべて未確認です。

## 決定1：終了要求・強制終了・待機と中断

**語を2つに分けます。どちらも待たずにすぐ戻ります。**

| 語 | 効果 | POSIX | Windows |
|---|---|---|---|
| `PROC-TERM ( proc -- ior )` | 終了を要求する | プロセスグループへ `killpg(pgid, SIGTERM)` | Job へ `TerminateJobObject(job, 143)`（強制終了になる） |
| `PROC-KILL ( proc -- ior )` | 強制終了する | `killpg(pgid, SIGKILL)` | `TerminateJobObject(job, 137)` |

- 「SIGTERM→1秒→SIGKILL」を語の中で同期して行う案は採りません。1秒止まる間の Ctrl+C の扱いが新たに必要になるためです。猶予を置きたい場合は、アプリが `PROC-TERM`、`ms PROC-WAIT`、`PROC-KILL` の順に組み合わせます。
- Windows には、コンソールのないパイプ子へ穏やかに終了を求める共通の手段がありません。そのため `PROC-TERM` は強制終了と同じ動作にします（Python の `terminate()` と同じ扱いです）。結果の報告はOS間で揃えます。この語で終了したことを記録しておき、終了コードが143なら state=3 code=15、137なら state=3 code=9 として報告します。子自身が同時に143や137で終了した場合は区別できません。この制限は仕様に明記します。
- 状態ごとの結果：設定中（state 0）は EINVAL を返します。終了済み（2/3）は何もせず 0 を返します。回収済みのPIDやグループへはシグナルを送りません。PIDの再利用による誤送信を防ぐためです。
- 孫プロセスの扱い：
  - POSIX では、子を自分のプロセスグループ（`setpgid(0,0)`）に置きます。親の側でも `setpgid(pid,pid)` を呼び、どちらが先でもよいようにします。
  - Windows では、`CREATE_SUSPENDED` で作り、`AssignProcessToJobObject` の後に `ResumeThread` します。割当てに失敗した場合は子を終了・回収し、起動の失敗として返します。
  - `KILL_ON_JOB_CLOSE` は付けません。付けると、FREE の時点で孫まで消えてしまい、「離脱する子孫は隔離しない」方針と POSIX の動作から外れるためです。`BREAKAWAY_OK` を許します。
- `PROC-WAIT ( proc ms -- state code ior )`：
  - ms の値の扱い：0 はその場で調べるだけ、負の値は無期限、正の値は単調時計の期限です。ms の上限と範囲外の扱いは WAIT-FILES の規則に合わせます。
  - 待つ対象は直接の子だけで、孫は待ちません。
  - 待ち方は drainWriter と同じ形にします。Windows は `WaitForSingleObject(process, min(残り,20))` を繰り返し、そのたびに `inputInterrupted` を見ます。POSIX は `waitpid(pid, WNOHANG)` と、最大10msの wake 待ちを繰り返します。SIGCHLD のハンドラは作りません。
  - `waitpid(-1)` は使いません。SYSTEM や Tcl の子を横取りしないためです。
  - 時間切れは state=1 code=0 ior=0 です。Ctrl+C は THROW -28 で、子は止めず、proc の状態も変えません。
  - 設定中の proc では待たずに state=0 を返します。
- 終了結果の表し方：通常の終了は state=2 で、code は終了コードです。Windows の値は32ビットの符号なしとして返します。シグナルによる終了は state=3 で、code はシグナル番号です。
- **Ctrl+C を子へ届かせない仕組み**：POSIX では子が別のプロセスグループにいるので、端末の SIGINT は届きません。Windows では `CREATE_NEW_PROCESS_GROUP` を付けます。

## 決定2：PROC-FREE と、procが持っているストリーム

- 実行中の proc に対しては EBUSY を返します。
- 設定中または終了済みの proc では、まだ proc が持っているストリームを、**内容を捨てて閉じます**。その後で proc ID を無効にします。
  - 対象は (所有proc ID, file ID) が一致するものだけです。利用者が先に CLOSE-FILE で閉じたものは対象になりません。
  - writer は `deinit`（取消しを繰り返して止める）で、未送信の内容を捨てます。drain はしません。
  - reader も `deinit` で、受信キューを捨てます。
  - 最後に `fclose` します。閉じる順序は stdin、stdout、stderr です。
- 失敗したとき：`deinit` が HostFailed を返したら、FREE は EIO を返します。残りの資源は proc が持ったままにし、もう一度 FREE を呼べば続きから進むようにします。完了していないのに成功とは報告しません。
- 出力を最後まで読みたい場合は、アプリが EOF まで読んで CLOSE-FILE してから FREE します。仕様にはこの使い方を書きます。
- 無効な proc ID（解放済み、存在しない、古いID）には EBADF を返します。
- **FileSlot に必要な変更**：`proc_owner: u64 = 0` を足します。
  - `fileClose` は、従来の `.pipe`（popen 用）と区別して、proc が持つパイプも受け付けます。閉じるときに `proc_owner = 0` に戻します。
  - proc ID は単調に増え、再利用しません。そのため、世代番号を別に持たなくても古い参照を見分けられます。
  - 利用者の CLOSE-FILE は従来どおり配送を待ちます。中断されたら -516 を返し、IDは残します。

## 決定3：起動の経路（argv・環境・cwd・PATH）

**共通の方針**：実行するファイルは、**起動する前に親の側で絶対パスに解決します**。

- PATH は、子に渡す環境の PATH を使います。
- 相対パスの解決には、子の作業ディレクトリを使います。cwd も、相対で指定された場合は親の cwd を基準に絶対パスにします。
- PATH の空の要素は飛ばします（macWish と同じ扱いです）。PATH が設定されていなければ探索せず、ENOENT を返します。
- 名前に区切り文字（`/`、Windows では `\` と `:` も）がある場合は、探索せずに子の cwd を基準にします。
- 暗黙のシェルは使いません。ENOEXEC は起動の失敗として返します。
- 環境：もとにする環境に、指定した上書きを順に適用します。もとにする環境は、Forth の GETENV と同じ取得元（`host.environ_map` と推測されます）にします。どちらを使うかは、実装の前に確認します。

**Linux**：fork と、async-signal-safe な子の処理を使います。

- 親で準備するもの：argv と envp の配列、絶対パス、cwd、エラー通知用パイプ（`pipe2(O_CLOEXEC)`）、閉じるfdの上限。親の側のパイプ端は CLOEXEC にし、子の側の端は `F_DUPFD_CLOEXEC` で3以上へ移しておきます。
- 子で行うこと：
  1. `setpgid`
  2. シグナルの既定化と、シグナルマスクを空にする
  3. `chdir`
  4. 0/1/2 への `dup2`
  5. `close_range(3, ~0)` を raw syscall で呼ぶ。ENOSYS なら、親で求めた上限までループで閉じる
  6. `execve`
  7. 失敗したら errno をパイプへ書いて `_exit(127)`
- 子では、メモリの確保も文字列処理もしません。
- 親はパイプを EOF まで読みます。何も来なければ起動の成功です。errno が届いたら、その子を `waitpid` してから、その errno を ior として返します。これで、起動の失敗と終了コード127を区別できます。

**macOS**：`posix_spawn` を使います。

- 属性：`POSIX_SPAWN_CLOEXEC_DEFAULT`、`SETPGROUP`、`SETSIGDEF`、`SETSIGMASK`。
- ファイルアクション：`adddup2`、`addinherit_np`、`addopen("/dev/null")`、`addchdir_np`。
- 関係のないfdを確実に閉じられる点と、exec の失敗が戻り値で返る点を理由に選びました。最低対応の macOS の版は未確認です。

**Windows**：

- パイプ：`CreatePipe` で作る同期パイプにし、容量は64KiB にします。親の側の端は継承させません。`_open_osfhandle` と `_fdopen` で FILE にし、`IONBF` を設定して、`native_pipe=true` にします。
- ハンドルの継承：`STARTUPINFOEXW` と `PROC_THREAD_ATTRIBUTE_HANDLE_LIST` を使い、継承するのは子の3端だけにします。stderr を stdout へ統合した場合は、同じハンドルを1つにまとめます。inherit 指定のハンドルは継承可能な複製を作り、null 指定には `NUL` を開きます。
- 起動：`lpApplicationName` に解決済みのフルパスを渡し、`CREATE_UNICODE_ENVIRONMENT` で UTF-16 の環境ブロックを渡します。`=C:` のような `=` で始まる継承エントリは残します。
- 実行ファイルの名前：
  - 最後の要素に拡張子があれば、その名前をそのまま試します。`.exe` で終わらない名前には `+.exe` も試します。
  - 解決した結果が `.bat` または `.cmd` なら、起動せずに ENOEXEC を返します。
  - コマンド行が32767文字を超える場合は E2BIG を返します。
- コンソール：Sigma にコンソールがあれば子もそれを共有し、ない場合だけ `CREATE_NO_WINDOW` を付けます。

## ブロッカーとAPIの調整

1. **POSIX で、子の標準入出力を端末から継承する場合**：子を別のグループに置くと、端末を読んだときに SIGTTIN で止まります。そこで、0/1/2 のいずれかが端末から継承される場合だけ、子を新しいグループに置きません。その場合、TERM/KILL は子のPIDだけが対象で、Ctrl+C が子に届くこともあります。この例外を仕様に明記します。
2. FileSlot の `pipe` は popen の所有を意味します。proc 用には `proc_owner` を別に持たせ、closeAllFiles の流れにも組み込みます。
3. **Sigma 終了時の順序**：
   1. 実行中の全 proc を KILL する（猶予なし）
   2. proc のストリームを、内容を捨てて閉じる
   3. 全体で最大3秒まで `waitpid` / `WaitForSingleObject` で回収する
   4. その後に、従来の closeAllFiles を実行する

   穏やかに終わらせたい場合は、アプリが BYE の前に TERM と WAIT を行います。
4. ASYNC_IO_DESIGN.md の35行目は「待機4語の中断は-28」、43行目は「中断はEINTR ior -516」と書かれていて、食い違って見えます。PROC-WAIT は PROCESS_MANAGEMENT_DESIGN.md のとおり -28 としますが、WAIT-FILES が実際にどちらを返すかは未確認です。
5. **Tcl の扱い**：Tcl の adapter は、プロセスを1つグローバルに持つ今の形のまま残し、64件の枠の外に置きます。wish の発見、一時ファイル、display budget は変えません。

   Tcl の Windows 起動は継承の制限なしに `bInheritHandles=1` で起動しているので、CRT で開いたファイルも子へ渡ります。これを許可リスト方式へ移す改善は、別タスクにする候補です。この改善がなくても、643 の妨げにはなりません。
6. **保存画像と実行時の境界**：設定と proc の表はホストが持ち、VM State と保存画像には何も加えません。この点は変更しません。

## 段階計画

| 段階 | 内容 | 検証 |
|---|---|---|
| 1098a | `host_proc_spec.zig`：設定・検証、Windows の引用、環境の合成、PATH の解決。ファイルの存在判定は差し替えられる純粋関数にする | 全OSの単体試験。Windows の引用は Linux でも試験できる |
| 1098b | Windows：パイプ、許可リスト、Job、中断を含む WAIT、TERM/KILL、FileSlot への登録 | Windows |
| 1098c | Linux の fork 経路、macOS の posix_spawn 経路 | Linux で実行、macOS はクロスビルドだけ |
| 1099 | コアの語（Builtin の末尾に追加、未提供なら -21）、FREE、CLOSE-FILE で閉じられるようにする、終了時の順序。Tcl の回帰確認 | Windows/Linux |
| 1100 | `tests/scripts/verify-proc-*.py`：argv の境界、env、cwd、127と起動失敗の区別、64件、逆圧下の並行入出力、中断 | Windows/Linux |
| 1101 | Mac 実機での受け入れ | 保留 |

確認が必要な点：環境の取得元（`environ_map` かどうか）、ビルドが対象とする macOS の最低版、WAIT-FILES の中断時の値。いずれも未確認です。

## 所有・終了の再検討

レモン、2ファイルを読んだうえでの評価です。コマンドの実行とファイルの変更はしていません。`environ_map` やほかのコードは読んでいないので、それらに関わる点は未確認です。

## 総評
提案(1)〜(5)はすべて採用でよいと考えます。前回のレビューのうち、次の2点はこの提案で置き換えます。
- 決定1の「Windows で 143/137 を state3 として報告する」
- ブロッカー5の「Tcl は今の形のまま残す」

## (1) Linux の close_range
指摘は正しいです。前回の案では、エラー通知用パイプを3以上へ移したあとに `close_range(3, ~0)` を呼ぶため、そのパイプも閉じてしまいます。その結果、exec の失敗を親へ伝えられません。

dup3 で fd3 に置く案でも成り立ちますが、次の条件が付きます。
- dup3 を 0/1/2 への dup2 より**後**に行う。stdio の元の fd が3にある場合に、上書きしないためです。
- `errfd == 3` のときは dup3 が EINVAL になる。この場合は fcntl で CLOEXEC を付けるだけにする。
- ENOSYS の場合の代わりのループでも、3は閉じない。

もっと単純な方法として、次の2つを推奨します。
- **A**：`close_range(3, errfd-1)` と `close_range(errfd+1, ~0)` の2回に分けて呼ぶ。dup が要りません。
- **B**：`close_range(3, ~0, CLOSE_RANGE_CLOEXEC)` で全部に CLOEXEC を付け、閉じるのは exec に任せる。EINVAL や ENOSYS のときは A かループに切り替える。

もう一つ注意があります。stdio の元の fd が移し先と同じ番号の場合、dup2 は CLOEXEC を外しません。親の側で、子の側の端をすべて3以上へ移しておくことを前提として明記してください。

## (2) Windows の終了コード
賛成です。Windows では、TERM/KILL で終わらせた場合も state2 とし、code は 143/137 の生の値のまま返します。state3 は POSIX でだけ使います。

あわせて、表の側で次の点を強めることを提案します。
- `finished(.signaled, code)` は 1〜127 だけを受け付ける。今は 0 から u32 の最大値まで通ります。
- Windows のビルドでは `.signaled` を拒む。
- POSIX の exited は 0〜255 に限る。

## (3) waitid(WNOWAIT) で直接の子を回収せずに残す
考え方は正しいです。直接の子を回収しなければ、ゾンビとして PID が残ります。PGID はこの PID と同じ番号なので、再利用されません。そのため、子が終わった後でも `killpg` を安全に送れます。

ブロッカーと確認事項は次のとおりです。
1. **自動回収の禁止（未確認）**：プロセス全体で SIGCHLD を SIG_IGN にしていないこと、SA_NOCLDWAIT を付けていないこと、`waitpid(-1)` や `wait()` をどこでも使っていないことを確認する必要があります。SYSTEM、Tcl adapter、ライブラリも含みます。どれか一つでも当てはまると、ゾンビが回収されて保証が崩れます。
2. **siginfo の扱い**：WNOHANG では、子がまだ終わっていないとき si_pid が0のまま戻ります。呼ぶ前に siginfo を0で埋め、戻った後に si_pid を見ます。
   - `CLD_EXITED` は state2
   - `CLD_KILLED` と `CLD_DUMPED` は state3
3. **macOS（未確認）**：waitid と WNOWAIT が正しく動くかは確認していません。1101 で、kqueue の `NOTE_EXIT|NOTE_EXITSTATUS` などの代わりの方法と比べて決める必要があります。Windows と Linux の実装の妨げにはなりません。
4. **FREE の順序**：ストリームを捨てて閉じる → 子孫を手放す → 直接の子を `waitpid(pid)` で回収する（EINTR なら再試行）→ 表から外す。Windows は、プロセスのハンドルと Job のハンドルを閉じます。Job に kill-on-close を付けていないので、子孫は残ります。
5. **終了時の対象**：Sigma の終了時に KILL する対象は、FREE されていない全 proc です。状態2/3でも、残っている子孫がいれば止めます。FREE 済みのものは対象にしません。この非対称は仕様に明記してください。
6. **前回の例外の扱い**：端末から継承するため新しいグループを作らない子には、PID に対して kill します。相手がゾンビなら何も起きないので、この案でも成り立ちます。

## (4) 環境
GETENV の取得元が `host.environ_map` であることは、私は確認していません（未確認）。仕様に加える点は次のとおりです。
- **名前の照合（Windows）**：大文字と小文字を区別せず、ロケールに依存しない比較を使います（`CompareStringOrdinal(..., TRUE)` 相当）。同じ名前の編集が複数あれば、最後の編集が値と名前の綴りの両方を決めます。
- **環境ブロックの並び（Windows）**：名前順に並べるかどうかを決めてください。`=C:` のような項目は先頭に残します。※並べる必要があるかは確認を推奨します。
- **`=` で始まる名前**：`addEnvironment` が InvalidText で拒みます。編集はできず、継承したものはそのまま残します。仕様に明記してください。
- **上限の数え方**：64KiB の上限は、argv、環境の編集、cwd の合計です。継承した環境は数えません。E2BIG の判定は起動時に行います（Windows はコマンド行の32767文字、Linux は execve の戻り値）。
- **UTF-8 の制限**：argv と環境の編集は UTF-8 で、NUL を含めないことが条件です。POSIX では UTF-8 でないバイト列を渡せません。この制限を仕様に書いてください。

## (5) Tcl の段階的な移行
賛成です。提案する段階は次のとおりです。
- **T1**：Windows で Tcl を起動するとき、`bInheritHandles=1` を単独では使わず、HANDLE_LIST による許可リストを**必須**にする。
- **T2**：Tcl も共通の起動経路を使う。Job またはプロセスグループに入れ、中断できる WAIT と共通の終了順序に従わせる。表には内部用の予約枠として置き、64件には数えず、PROC の語には見せません。
- **T3**：Tcl だけが持っている古い経路を削除する。

追加の条件として、継承できる複製ハンドルを作ってから CreateProcess の直後に閉じるまでの間に、別のスレッドが `bInheritHandles=TRUE` で起動すると、そのハンドルが漏れます。プロセスの起動は、すべて VM のスレッドで行うか、1つのロックで直列にすることを条件にしてください。

## 表のコード（host_process_table.zig）
- **確保の巻き戻し**：問題ありません。どの経路でも、dupe の後に errdefer で解放しており、text_bytes は成功した後でだけ更新しています。`checkAllAllocationFailures` で確かめられています。
- **改善を推奨する点**：
  - `finished` の code の範囲を、(2) で書いたとおり状態とOSごとに分ける。
  - 起動に失敗した場合は configuring のまま残し、設定もそのまま保ち、もう一度起動するか FREE できる、という契約にする。docコメントにも書く。
  - 状態2/3でもOSの資源（ゾンビ、ハンドル、Job）を持っていることを、docコメントに書く。今の「remove の前に解放する」という前提は、FREE の手順でだけ満たされます。
  - `Entry.config` が pub なので、`editable()` を通さずに変更できます。テストの202行目でも直接触っています。nit です。
  - `setMode` で組合せが不正なときに InvalidText を返すのは意味がずれています。nit です。
  - 表は VM のスレッドだけから使う、という前提をコメントに書く。

## 最終の契約（要約）
- **状態**：configuring(0)、running、exited(2)、signaled(3, POSIX のみ)。終了状態は一度決まったら変わらない。
- **TERM/KILL**：グループまたは Job へ送る。状態2/3でも、FREE の前なら子孫へ届く。configuring では EINVAL を返す。
- **WAIT**：WNOWAIT で調べ、結果を記録する。直接の子は回収しない。
- **FREE**：running なら EBUSY を返す。それ以外では、ストリームを捨てて閉じ、子孫を手放し、直接の子を回収して、ID を無効にする。途中で失敗したら EIO を返し、もう一度呼べば続きから進む。
- **Sigma の終了時**：FREE されていない全 proc の子孫を KILL する → ストリームを捨てて閉じる → 全体で最大3秒まで回収する → closeAllFiles を実行する。

**Windows と Linux の実装に入る前に解決が必要なのは、(1) の fd の扱いと、(3)-1 の自動回収がないことの確認の2点です。** macOS の waitid は 1101 で扱います。

## 起動前基盤の実装レビュー

# 643/1098 基盤のレビュー（読み取りのみ）

5ファイルを読んで確認しました。テストとビルドは実行していないので、すべて未確認です。

## 基盤の阻害要因（native backend を接続する前に直すもの）

1. **`remove` の保護が POSIX の終了後に効かない** — `src/host_process_table.zig:160-169`
   - `remove` が止めるのは `phase == .running` のときだけです。
   - POSIX の WNOWAIT 方式では、`exited`/`signaled` になってもゾンビの leader と PGID を所有し続けます（`:99-100` のコメント）。
   - backend が回収する前に表の項目を消すと、PID/PGID の所有記録がなくなり、二重 reap や古い PGID への signal につながります。
   - 対策: Entry に「native 資源を解放済み」の状態を持たせ、`remove` はその状態のときだけ許可する。
   - 設計書 9行目は「プロセス表が OS process/job/PID を所有する」、表の冒頭コメントは「OS 資源を保持しない」と書いていて食い違っています。資源の置き場所をどちらかに決める必要があります。

2. **`remove` が公開IDと Tcl 内部枠を区別しない** — `:160`
   - 公開側の検索は `getPublic` で分けていますが、`remove` は内部枠も検索します。
   - PROC-FREE の実装が `getPublic` を先に呼び忘れると、Tcl の項目を解放できてしまいます。
   - 対策: `removePublic` を用意するか、`remove` に internal フラグの照合を入れる。

3. **Windows の .bat/.cmd 拒否を回避できる** — `src/host_process_spec.zig:26-30, 70`
   - `isScript` は、利用者が指定した名前の拡張子だけを `eqlIgnoreCase` で見ています。
   - `x.bat.` や `x.bat `（末尾のドット・空白）は検査を通りますが、Windows のパス正規化で `x.bat` になります。CreateProcessW がそれを cmd.exe 経由で起動すると、CRT 引用ではシェルの解釈を防げません（BatBadBut と同類の問題です）。
   - 対策: 解決後の絶対パスに対して、末尾の `.`/空白を除いてから判定する。可能なら、末尾が `.`/空白の名前やドライブ指定以外の `:` は EINVAL にする。
   - `x.bat::$DATA` のような ADS 名でどう動くかは未確認です（※推測では同じ系統の問題です）。

## 仕様の阻害要因（設計書に明記が必要なもの）

4. **POSIX の PATH 解決が字句的** — `:35-38`
   - `std.fs.path.resolve` は `..` を字句的に畳みます。
   - cwd や PATH 要素がシンボリックリンクを含むと、子プロセスの cwd で execvp したときとは違うファイルを解決します。
   - 「字句的に解決する」と仕様に書くか、`..` を含む場合は畳まずに連結するか、どちらかに決める必要があります。

5. **Windows で拡張子なしの名前を先に試す順序** — `:49`
   - CreateProcess は、名前に拡張子がなければ `.exe` を補う規則です。
   - 現在の順序では、拡張子なしの非PEファイル（Git for Windows の sh スクリプトなど）を先に見つけて、起動時に失敗します。
   - `.exe` を先に試すか、probe が PE 形式まで判定することを仕様にする必要があります。

6. **argv[0] の扱いが決まっていない**
   - `"` を含む argv[0] は、Windows では quote 段階で EINVAL になりますが、表は受け付け、設計書の EINVAL 条件にも載っていません。
   - コマンドラインの argv[0] に「利用者の文字列」と「解決後のパス」のどちらを入れるかが書かれていません。
   - lpApplicationName には解決後のパスを必ず渡す、という条件も書かれていません。

7. **長さの上限が2種類ある**
   - 表は合計 64KiB まで設定を受け付けますが、Windows のコマンドラインは NUL を含めて 32767 単位までです（上限の判定 `src/host_process_quote.zig:9` 自体は正しい）。
   - 設定は通って START で TooLarge になるので、そのときの ior（E2BIG 相当）を仕様に書く必要があります。
   - `InvalidUtf8` と `InvalidText` から ior への対応表もありません。

8. **PROC-CWD が相対パスのときの基準が書かれていない**
   - 親の cwd を基準にするのか、存在しない cwd を program の ENOENT より先にエラーにするのかが未定義です。

9. **入出力モードと状態コードの細部が未定義**
   - mode=3（stderr を stdout へ統合）で、stdout が inherit/null のときの動作。
   - PROC-STDOUT が非pipe のときの戻り値。
   - state 0/1 のときの code の値。

## backend で守る条件（今の基盤では阻害要因ではない）

- Windows の環境ブロックは、名前で大文字小文字を区別しない Unicode 順に並べて作る必要があります（Microsoft の規定）。
- 継承した環境の WTF-8 は utf8 ではなく wtf8 で変換する必要があります。継承した `=C:` 項目は削除できず、PROC-CWD を設定すると古い値が残ります。
- 終了コード 259（STILL_ACTIVE）は GetExitCodeProcess だけでは判定できないので、wait の結果で判定する必要があります。
- waitid では WEXITED だけを観測し、CLD_DUMPED は signaled として扱います。
- `Config` の各メソッド（`setMode` を含む）は phase を検査しません。呼び出し側は必ず `editable()` を経由する必要があります（テスト `:225` は直接呼んでいます）。
- `Table.deinit` は running の項目も黙って捨てます。debug assert を入れることを勧めます。
- `cmd.exe` を明示して起動する場合、引数は CRT ではなく cmd の規則で解釈されます。利用者向けの注意書きが必要です。

## 問題を見つけなかった点

- 表・quote・環境合成・PATH 解決の allocation 失敗時の errdefer と所有の扱いは、コードを読んだ範囲では整合しています。
- CRT の引用（argv[0] を別扱い、引用符の直前と末尾の backslash を倍化）は正しいです。
- ID が単調に増えて wrap しないこと。
- 終了状態の範囲（POSIX の exited 0..255、signaled 1..127、Windows の 32 ビット値で signaled を拒否）。
- Windows の Unicode 名照合を前提にした環境の編集順序。

## 起動前基盤の再レビュー

## 643/1098a 基盤の再レビュー（読み取りのみ）

読んだファイルは `host_process_table.zig`、`host_process_spec.zig`、`host_process_quote.zig`、設計書の最終節と、前回のレビュー `.work/643/claude-foundation-review.txt` です。コマンドは実行していません。ビルドとテストが通るかは未確認です。

### 前回の指摘の対応状況（コード上で確認）
- 1・2（remove の保護、公開IDと Tcl 内部枠）：解消しています。`nativeAcquired` から `nativeReleased` までは remove できません。`removePublic` は Tcl の項目を拒否し、`deinit` は assert で止まります。
- 3（.bat/.cmd 拒否の回避）：主な経路は塞がっています。末尾のドット/空白、ADS、`\\?\` と `\\.\` は、指定した名前と解決後のパスの両方で拒否しています。下記 A の抜けが残ります。
- 4〜9（PATH解決、`.exe` の順序、argv[0]、上限、cwd、入出力モード）：コードか設計書の 76〜82 行に反映されています。

### 残っている基盤の阻害要因

**A. 拡張名前空間の検出が `\\?\` と `\\.\` の綴りだけ** — `host_process_spec.zig:37`
- `//./pipe/x`、`/\.\x` のような区切り文字の混在や、`\??\UNC\server\share\x.exe` はコロンを含まないので、検査を通ります。
- 設計書 30 行の「拡張名前空間はEINVAL」を満たしていません。
- 対策：区切り文字を `\` に揃えてから、先頭の `\\?\`、`\\.\`、`\??\` を拒否します。テストに `//./`、`\??\` の例を追加します。

**B. PATH 要素のドライブ相対（`C:bin`）を拒否していない** — `:35-38, :52`
- program の `C:tool` は 94 行で拒否しますが、PATH 要素はコロンが 1 文字目の次にあるため通ります。
- その後 `std.fs.path.resolve` が `C:bin` をどう解決するかは未確認です。※推測ですが、Windows が使うドライブごとの cwd（`=C:`）とは一致しないと思われます。
- 対策：解決前の directory にも、program と同じドライブ相対の拒否を入れます。

**C. START 失敗後の proc の状態が設計書にない**（仕様）
- 表の動きは次のとおりです。rollback に成功して `nativeReleased` を呼ぶと、phase は `configuring` に戻り、再設定と再 START ができます。rollback に失敗すると `native_owned` のまま残り、変更は EBUSY になります。
- この挙動を PROC-START の契約として一文書く必要があります。

### 小さい点（阻害要因ではない）
- `host_process_table.zig:242` のテストは `editable()` を通さずに `config.addArgument` を直接呼んでいます。
- テストが足りない点：
  - `.exe` と拡張子なしの両方が存在するときの順序（今の TestProbe は一致を 1 件しか持てません）
  - PATH 要素の末尾ドットを拒否すること
- `error.Capacity` は、表の容量（EMFILE）と ARG/ENV の件数（E2BIG）の両方で使われています。ior へ変換するときは、どの語から呼ばれたかで区別する必要があります。

### 後の backend で守る条件（今の基盤の阻害要因ではない）
- Windows の native probe：PE 形式であることに加えて、通常ファイルであることも確認します（NUL/CON などのデバイス、ディレクトリを除くため）。
- Windows の探索範囲：探すのは PATH だけで、CreateProcess の標準の探索順（アプリのディレクトリ、System32 など）は使いません。この違いを利用者向け文書に明記します。
- 親の cwd が `\\?\` 付きの場合、START が EINVAL になります。対応を決めておきます。
- 前回からの継続事項：
  - cwd の事前検査をする順序
  - lpApplicationName を必ず明示すること
  - 環境ブロックの並び順、WTF-8、`=C:` の扱い
  - 終了コード 259 の判定
  - WNOWAIT と disposition の検査、ECHILD による所有喪失の扱い
  - PROC 層は必ず `getPublic`/`removePublic`/`editable` を経由すること
  - FREE と Sigma 終了時の回収順序

**まとめ**：基盤の阻害要因として残っているのは、A（名前空間の検出漏れ）と B（ドライブ相対の PATH 要素）の2件です。どちらも `validateWindowsPath` の範囲で直せます。仕様の追記としては C の1件が残っています。

## パス検査の最終レビュー

レモン、読み取りだけで確認しました。読んだのは `src/host_process_spec.zig` の全体、`.work/643/claude-foundation-rereview.txt`、`docs/PROCESS_MANAGEMENT_DESIGN.md` の該当行です。コマンドは実行していないので、ビルドとテストが通るかは未確認です。

## 結論
基盤として残っている阻害要因はありません。

## 前回の指摘 A・B・C の確認

**A(拡張名前空間の検出漏れ)は解消しています。**
- `host_process_spec.zig:37-40` では、先頭 4 文字の `/` を `\` に揃えてから、`\\?\`・`\\.\`・`\??\` と、区切り文字が 3 つ続く先頭を拒否しています。
- この検査は、解決前のパス(`:58`、`:97-98`)と解決後のパス(`:61`)の両方で行われます。
- そのため、PATH 要素が `\\.` や `\\?` だけでも、解決後に `\\.\tool` のような形になれば `:61` で止まります。
- テストは `:222`(`//./pipe/x`、`/\.\x`、`\??\UNC\...`)と `:260`(`//./pipe`、`\??\UNC\server\share`)にあります。

**B(ドライブ相対の PATH 要素)は解消しています。**
- `:41-44` では、2 文字目のコロンで、先頭が英字、次が区切り文字のもの(`C:\`、`C:/`)だけを通します。ほかの位置のコロンや `C:` だけのものは拒否します。これで ADS も止まります。
- この検査は directory(`:58`)にも適用されています。テストは `:260` の `C:bin` です。
- 子の cwd にディスク指定子が必要な点は `:96` で実装され、テストは `:259` の `\work` です。

**C(START 失敗後の状態)は解消しています。**
- 設計書の 84 行に書かれています。rollback が完了した場合は、設定と ID を残したまま再設定・再 START・FREE ができます。完了しなかった場合は native_owned を残し、設定変更と再 START は EBUSY、FREE は残りの回収を再試行します。
- これは前回の再レビューで確認した表の動きと一致します。

## 追加されたテストの確認
- `.exe` と拡張子なしの名前が両方ある場合の順序:`Both` probe が使われ、`tool.exe` が選ばれて probe は 1 回だけ呼ばれます(`:241-258`)。
- `""` だけの PATH 要素は probe されません。拒否されるケースでも probe の回数は 1 のままです(`:264`)。
- PATH 要素の末尾のドットと空白(`tools.`、`tools `)は拒否されます(`:260`)。

## 小さい点(阻害要因ではありません)
1. `:101` のドライブ相対の検査は、`:43` と重なっていて、残っていても無害です。
2. PATH 要素や program が `\bin` のようにルート相対の場合、`std.fs.path.resolve` が cwd のドライブを引き継ぐかどうかは未確認です。cwd が UNC の場合も同じです。テストもありません。
   - `:96` で cwd にディスク指定子が必須になっているので曖昧さは減っています。ただ、※推測ですが、解決結果を固定するテストを 1 件入れておくと安全だと考えます。
3. `?`、`*`、`"`、`<>|` といった Windows で使えない文字は拒否していません。たとえば片側だけ引用符のある PATH 要素などです。probe が missing を返すので実害はないと考えますが、EINVAL ではなく ENOENT になります。
4. cwd に UNC(`\\server\share\...`)を使えるかどうかは、Zig の `diskDesignatorWindows` の動き次第で、未確認です。

## 後の OS backend で守る条件
これまでの再レビューで挙げた条件はそのまま残ります。
- PE 形式で、通常ファイルであることの確認(NUL や CON などのデバイスを除くため)
- 探すのは PATH だけで、Windows 標準の探索順は使わないこと。この違いを利用者向け文書に書くこと
- `lpApplicationName` を必ず明示すること
- 環境ブロックの並び順と `=C:` の扱い
- 終了コード 259 の判定
- 回収の順序

## probeエラー伝搬の限定レビュー

## 結論：ブロッカーはありません

`src/host_process_spec.zig` の現行版を読んだ結果です。ビルドとテストは実行していません。テストが Windows で通る点は、ご報告に基づいています。

### メモリの解放（`tryCandidate`、68–92行）
どの経路でも、二重解放やリークは見つかりませんでした。

- **`.exe` の割り当てが失敗した場合**：外側の `errdefer` で `path` を解放します。
- **`.exe` を確認する時点で probe がエラーを返した場合**（`.invalid_format` からの `BadExecutable` と、`Io` の両方）：内側と外側の `errdefer` で、`with_extension` と `path` の両方を解放します。
- **`.exe` が `.executable` だった場合**：`path` を解放して `with_extension` を返します。正常に戻るので `errdefer` は動きません。
- **`.exe` が `.missing` か `.denied` だった場合**：82行で `with_extension` を解放します。内側の `errdefer` はこの `if` ブロックの中だけで有効なので、ブロックを出た後の二重解放は起きません。
- **元の名前を確認する時点**：`.executable` なら `path` を返します。エラーなら外側の `errdefer` で解放します。`.missing` と `.denied` なら 90行で解放して `null` を返します。
- **`resolveProgram` 側**：`candidate` が返した領域の持ち主は、そのまま `tryCandidate` に移ります。呼び出し元に二重の責任は残りません。

### 新しいテスト
- **269–285行（ルート相対と UNC の cwd）**：`D:\child` に `\bin\tool.exe` を指定すると `D:\bin\tool.exe` になり、UNC でも共有のルートが保たれることを確認しています。期待値は妥当です。
- **287–301行（失敗の区別）**：Windows では `dir/tool` に拡張子がないので、`.exe` 経路の中でエラーが返る場合を通ります。`std.testing.allocator` を使っているので、リークがあれば検出されます。POSIX では元の名前の経路を通ります。

### ブロッカーではない指摘
- **PATH 検索の打ち切り（117–118行）**：途中の PATH 要素で `invalid_format` か `Io` が返ると、残りの要素を探さずに検索が終わります。形式やメタデータの失敗を「見つからない」と扱わない、という今回の方針どおりの動きです。ただし、これが意図した仕様であることを、設計文書に一行書いておくことをおすすめします。
- **同じ場所に `tool.exe` と `tool` がある場合（78行）**：`tool.exe` が `invalid_format` なら、`tool` があってもそちらは試さずに `BadExecutable` を返します。`.exe` を優先する方針とは矛盾しません。
- **テストの範囲**：PATH 検索の中で `invalid_format` や `Io` が返る場合のテストはありません。明示したパスの場合だけを確認しています。必須ではありません。

`.exe` と元の名前の両方を誤った形式と判定する処理は、ネイティブ実装ができてから見る必要があります。このコードでは、まだ確認できません。

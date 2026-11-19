# 643 実装レビュー原文

2026-11-19。Claude CodeにRead/Grep/Globだけを許可し、編集・コマンド実行を禁止して依頼した。以下は原文。レビューは実行試験の代わりではない。

## native初回

## host_process_native.c/.h レビュー(読み取りのみ。編集とコマンド実行はしていません)

### 実際の不具合(コードから確認)

1. **POSIX: 終了を一度観測した後は、所有を失っても検出しない**(`host_process_native.c:322`, `:339-342`)
   `waitid` を呼ぶのは `state==1` のときだけです。一度 `state=2/3` を記録すると、それ以降は ECHILD を検出できません。この状態で外部の `waitpid(-1)` などが zombie を回収すると、TERM/KILL は再利用された可能性のある PGID へ `kill(-pid)` を送ります。設計 51 行「所有喪失時は古いPGIDへsignalを送らない」に反します。
   - 対策案: `sigma_proc_signal` と `destroy` で、終端状態でも `waitid(P_PID, pid, WEXITED|WNOHANG|WNOWAIT)` を呼び直し、zombie が残っているか確かめる。

2. **所有を失った/状態取得に失敗した場合、streams が閉じられない**(`:368-369`, `:397`, `:400`)
   `destroy` は `sigma_proc_status` がエラーになるとすぐ return します。そのため ECHILD(lost)や WAIT_FAILED のときは、`close_startup` も stream の `fclose` も実行されません。この状態は永久に回復しないので、pipe と FILE が恒久的に残ります。`abort` も `signal` → `status` の順で同じように止まります。
   設計 43 行の「回収できない資源は所有を残す」は守れていますが、プロセスの回収とは関係のない stream まで巻き込んでいます。stream の close はプロセス状態と切り離して実行し、失敗の報告だけ残すのが妥当と考えます。

3. **Linux: fork の前後で signal を遮断していない**(`:270-277`)
   子プロセスは `setpgid` → `sigprocmask(空)` → disposition の初期化、の順で処理します。そのため fork 直後から disposition を初期化し終えるまでに届いた signal(たとえば端末の Ctrl+C。この時点ではまだ親と同じ pgrp にいます)は、子の中で Sigma のハンドラとして実行されます。
   - 対策案: 親が fork 前に `pthread_sigmask` で全 signal を遮断する → 子は disposition を初期化してから mask を空にする → 親は fork 後に元の mask へ戻す。
   - ハンドラの中身によって影響の大きさは変わりますが、ハンドラの中身は未確認です。

4. **Windows: `abort` が終了済みの未割当プロセスで失敗し続ける**(`:139-140`)
   `assigned==0` で既に終了しているプロセスに `TerminateProcess` を呼ぶと、ACCESS_DENIED になります。`abort` はそれをエラーとして返すので、`destroy` まで進みません。該当するのは、Job への割当に失敗した後の経路だけです。

5. **Windows: `STARTF_USESHOWWINDOW | SW_HIDE` が常に付く**(`:108-109`)
   現行の Tcl 経路(`host_process.zig:216-218`)にはこの指定がありません。wish をこの backend へ移すと、GUI の子の最初の `ShowWindow` が隠し表示になるおそれがあります(※推測です。Tk の初回 `ShowWindow` の挙動は未確認)。少なくとも、モードによって付ける/付けないを選べるようにする必要があると考えます。

### 契約上の注意(呼び出し側の Zig を作るときに必要)

- **start がエラーを返しても子プロセスが存在する場合があります。** 対象は、Windows で Assign/Resume に失敗した場合、Linux で setpgid・handshake の read に失敗した場合や exec 失敗が通知された場合、両 OS の成功後の `close_startup` 失敗です。このとき `state==1` です。呼び出し側は、start が失敗したら `status` で状態を確認して `abort` を呼ぶ必要があります。`destroy` は EBUSY になります。
- **起動前の失敗では、同じ object を再 start できません。** 対象は CreateProcess・fork・posix_spawn の失敗です。残った資源の検査(`:75-76`, `:259-260`)で EBUSY になるため、`destroy` して `sigma_proc_new` からやり直す必要があります。設計 84 行の「rollback 完了後に再 START」は、表の側で native object を作り直す前提になります。
- **POSIX では `cwd==NULL` を許しません。** `chdir(NULL)` や `addchdir_np(NULL)` になります。空の cwd(継承)のときは、親が絶対パスを必ず渡す必要があります(呼び出し側はまだないため未確認)。
- **起動に失敗した Windows object は、inheritable な子側 handle を destroy まで持ち続けます。** その間に旧 Tcl 経路(`bInheritHandles=1`、許可リストなし)が起動すると、その handle が wish に漏れます。Tcl を共通 backend へ移せばこの問題はなくなります。

### 確認できた点(問題なし)

- **Windows**
  - 同期 CreatePipe を使い、親側は非継承です。子側の端点は stream を作った後で継承可にしています。
  - `HANDLE_LIST` は 3 端点だけです。
  - CREATE_SUSPENDED → Job に割当 → Resume の順になっています。BREAKAWAY_OK を付け、KILL_ON_JOB_CLOSE は付けていません。
  - 259 の扱いは、wait の結果を先に見てから exit code を取得しています。
  - 部分的に作った資源(pipe の親側、attributes、job)はすべて記録されるか、閉じられています。
- **Linux**
  - 子プロセスで使う関数は async-signal-safe なものだけです。
  - stdio の元 fd は 3 以上にあるため、dup2 の同一 fd 問題や CLOEXEC 解除の問題は起きません。
  - error pipe は CLOEXEC で、2 区間の close_range から除外しています。close_range が使えない場合のループもあります。
  - EOF なら exec 成功、4 バイト受信なら errno、と区別して終了 127 と混同しません。
- **macOS**
  - `CLOEXEC_DEFAULT`、`SETPGROUP(0)`、`SETSIGDEF`/`SETSIGMASK`、`addchdir_np` は設計どおりです。
  - exec の失敗は posix_spawn の戻り値で同期的に分かります。
- **再試行**
  - `destroy` の再試行は、POSIX では `pid=0`、stream は NULL 化済みのため、二重 close になりません。

### 仮説(未確認・優先度は低め)

- **Linux の代替ループが遅くなる可能性**(`:224-230`): `close_limit` は `rlim_max` と `/proc` の最大値のうち大きいほうを使います。カーネル 5.9 未満で `rlim_max` が 2^20〜2^30 だと、代替の close ループが非常に遅くなるおそれがあります。
- **Windows の継承モード**: 継承(mode 1)で `GetStdHandle` が NULL を返すと(GUI subsystem で起動した場合など)、EBADF になります。Sigma の subsystem は未確認です。
- **macOS の build**: SDK 26 では `addchdir_np` が deprecated です。warning を error にする build 設定だと build が止まる可能性があります。
- **macOS の waitid**: macOS の `waitid(WNOWAIT)` が `si_status` を正しく返すかどうかは、1101 の実機で確認が必要です。
- **軽微**:
  - `_open_osfhandle` や `_fdopen` が失敗したとき、古い errno が返る可能性があります(`:67`, `:69`)。
  - `win_error` は ERROR_DIRECTORY と ERROR_ELEVATION_REQUIRED を EIO にまとめます。設計 80 行の「元の errno 相当」との差は小さいです。
  - Windows の `close_handle` が失敗した後に再試行すると、同じ handle 値を再び閉じる可能性があります。

優先して直すべきなのは 1〜3 です。1 と 2 は lost の扱いを `destroy`/`signal` にまとめれば一緒に直せます。


## native再レビュー

# native backend 再レビュー(読み取りのみ)

ファイルの編集とシェルコマンドの実行はしていません。使ったのは Read・Grep・Glob だけです。対象は `host_process_native.c` / `.h` / `.zig` で、比較のために `host_process_spec.zig` と `host_process_table.zig`、src 全体の signal/waitpid の使い方も確認しました。

## 前回の指摘への対応(コードで確認しました)

| 項目 | 確認結果 |
|---|---|
| 終了済みを記録した後の WNOWAIT 再確認 | `.c:422-433` で、`pid!=0` なら状態に関係なく毎回 `waitid` を呼んでいます。ECHILD なら `lost=1` にします |
| lost のとき ECHILD を返し、再試行で解放 | `.c:486-509`。1 回目で stream と startup 資源を閉じて ECHILD を返し、2 回目で free します |
| fork 前後の signal 遮断 | `.c:357-380`。全 signal を遮断してから fork し、子で disposition を初期化 → fd を整理 → mask を空にしてから exec します。親は fork 後に元の mask に戻します |
| Windows: Job 割当前に終わったプロセスの abort | `.c:201-205` で TerminateProcess の失敗後に終了済みかを確認し、成功扱いにしています |
| SW_HIDE | 削除済みです。`CREATE_NO_WINDOW` は継承する stdio が 1 つもない場合だけ付けます(`.c:172`) |
| 部分失敗時の raw handle / CRT fd の保持 | `parent[]`、次に `parent_fd[]`、最後に `streams[]` の順で所有を移しています。`close_startup` はこの 3 段階すべてを閉じます |
| 失敗起動で inheritable な handle が漏れる件 | `start_error` が子側 handle の継承属性を外します(`.c:125-128`) |
| clock の失敗 | `now_ms` がエラーを返し、abort もそれを返します |
| checkpoint | Windows は 8 箇所(stdio 3 + 5)、Linux は 5 箇所(stdio 3 + `:384` + `:415`)で、件数は報告どおりです |

## 必ず直すべき不具合

**今回のファイルの中には、必ず直すべき不具合は見つかりませんでした。**

## 要判断(仕様の問題。直すかどうかはレモンさんの判断です)

1. **Windows の PATH 検索が、拡張子のないスクリプトで止まります**
   - 起きること: `sigma_proc_probe_windows` は、PE 形式でないファイルを 3(invalid_format)と判定します(`.c:67-74`)。`spec.tryCandidate` はこの判定を受けて `BadExecutable` を返し、PATH の残りを調べずに検索を終えます。
   - 例: `code` で検索すると、VS Code の `bin\code`(sh スクリプト)が見つった時点で終わり、PATH の後ろにある `Code.exe` まで届きません。
   - 比べると、CreateProcess の標準の検索は拡張子のない名前に `.exe` だけを付けて探します。
   - 対応案は 2 つです。(a) 拡張子なしの完全一致で invalid_format になったら、missing と同じく次の候補に進む。(b) 拡張子なしの完全一致そのものを試さない。

## 軽微・仮説(優先度は低め)

- **POSIX の pid 再利用**: 終了済みと記録した後に、`waitid` が `si_pid==0`(実行中)を返した場合です。これは別のプロセスに pid が再利用されたことを意味しますが、今は lost と判定されません。ただし src 内に `waitpid(-1)` はなく、どの呼び出しも pid を指定しています(grep で確認)。そのため、今のツリーでは起きません。
- **POSIX の destroy**: ECHILD 以外の status エラー(たとえば `:429` の EIO)では、stream を閉じずに return します(`.c:488`)。Windows 側(`:479-484`)とは扱いが揃っていません。
- **Linux の SIGWINCH**: `host_resize.zig` が SIGWINCH ハンドラを入れていますが、子で既定に戻すのは 6 種類の signal だけです。mask を空にしてから exec するまでの間に SIGWINCH が届くと、子の中でハンドラが動きます。子は既に別の pgrp にいて端末の前面グループではないため、実際に起きる可能性は低いと推測されます(※推測です)。
- **Linux で親の mask を戻せなかった場合**: `pthread_sigmask` の復元が失敗すると、親のスレッドは全 signal を遮断したままになります(`.c:379-380`)。ほぼ起きない失敗です。
- **前回から残っている項目**:
  - Windows の `close_handle` が失敗した後に再試行すると、同じ handle 値を二重に close する可能性があります。
  - 継承モードで `GetStdHandle` が NULL を返すと EBADF になります。
  - close_range が使えない場合の代替ループが遅くなる可能性があります。
  - macOS の `addchdir_np` deprecated と、`waitid` の `si_status`。
- **Zig 側の cwd**: `currentDirectory` は `config.cwd` が絶対パスでも先に呼ばれます。そのため、Sigma の現在のディレクトリが削除されていると、不要な失敗になります(POSIX の getcwd が ENOENT を返すため)。
- **Zig 側の drive-relative cwd**: Windows で `D:foo` のような cwd を指定した場合、`fs.path.resolve` の解決結果は Windows のドライブ別カレントの意味と異なる可能性があります。挙動は未確認です。
- **`=X:` の key**: `environment.put(&drive, cwd)` の `drive` はブロック内の stack 配列です(`.zig:145-146`)。`Environ.Map.put` が key を複製するかどうかは、std のソースを探しましたが見つからず未確認です。複製しない場合は、`windowsBlock` で使う時点で dangling になります。
- **macOS の checkpoint**: 4 箇所あり、実機テストは未確認です。

## Zig 側の parent 準備(確認できた点)

- **cwd**: 必ず絶対パスにしてから C に渡しています。そのため、前回の契約上の注意「POSIX で `cwd==NULL`」は解消しています。Windows の cwd は WTF-16 → WTF-8 → WTF-16 と変換しているので、単独の surrogate も保たれます。
- **環境変数**: Windows の環境ブロックは、名前を WTF-16 で 1 code unit ずつ大文字にして比較し、並べ替えています。`=C:` は `=` で始まるため先頭に来ます。空の値も保持されることをテストで確認しています。
- **argv**: `max_arguments+1` 要素の配列で null 終端しています。Windows では quote してから WTF-16 に変換しています。
- **probe の結果の対応**: probe のエラーは `native_error` を経由して errno に戻します。テキスト変換のエラーは EINVAL になります。
- **opaque token**:
  - `sigma_proc_new` が成功した直後に `self.pointer` を設定し、C の start が失敗しても保持します。
  - 準備段階で失敗した場合は pointer が null のままで、全メモリが解放されます(`checkAllAllocationFailures` のテストで確認)。
  - destroy / abort は成功したときだけ pointer を null にします。

## 残っている統合上の義務(FileSlot / PROC ワードの実装側)

1. **start 失敗後の処理**: start が 0 以外を返したときは `pointer != null` かどうかを見て、null でなければ abort を呼ぶ必要があります。返り値だけでは、準備段階の失敗か native の失敗かを区別できません。
2. **ECHILD の再試行回数**: lost が abort の途中で分かった場合、ECHILD は最大 2 回返ります。1 回目は signal → status から、2 回目は destroy の報告からです。3 回目で解放されます。そのため「1 回だけ再試行」の実装では資源が漏れます。ECHILD は「解放されるまで再試行する」扱いにする必要があります。
3. **abort の EBUSY(timeout)**: object は保持されたままです。BYE や close の経路に、後で再試行する仕組みが必要です。
4. **FileSlot と stream の所有**: FileSlot が `stream()` で借りた FILE* を持ったまま destroy すると、native 側が fclose するため dangling になります。FileSlot が `take()` で所有を移すか、slot を解放してから destroy するかを決める必要があります。
5. **起動の直列化**: Windows では、起動中の短い間だけ子側の handle が inheritable になります。旧 Tcl 経路(`bInheritHandles=1`、許可リストなし)と同時に起動しないことが前提です。両方が VM の owner スレッドで直列に動くかどうかは未確認です。
6. **SIGCHLD の確認**: SIGCHLD が SIG_IGN または NOCLDWAIT の場合、start は毎回 ECHILD を返します。PROC ワード側でこのエラーをどう見せるかを決める必要があります。
7. **終了後に残る子孫プロセス(Windows)**: Job に `KILL_ON_JOB_CLOSE` を付けていないため、正常終了の後に destroy すると、残っている孫プロセスは管理から外れます。設計どおりですが、PROC ワードの仕様書に明記が必要です。

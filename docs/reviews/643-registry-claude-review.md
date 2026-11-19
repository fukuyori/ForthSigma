# 643 実装レビュー原文

2026-11-19。Claude CodeにRead/Grep/Globだけを許可し、編集・コマンド実行を禁止して依頼した。以下は原文。レビューは実行試験の代わりではない。

## registry初回

Warning: this sign-in can end at any time from now until 2026-11-19. Renewing it does not move that date. Run claude auth login now, or use claude setup-token for unattended jobs.
レビューで修正が必要なのは 3 件です。主な問題は二つあり、終了時の「全体3秒」という上限が守られないことと、`fclose` が失敗したときに子プロセスの回収が飛ばされることです。ほかに軽微な修正候補が 2 件、方針として扱う事項が 3 件あります。

Read・Grep だけで調べ、ビルドやテストは実行していません。指摘は実行で確かめていない、コードを追った結果です。

## 修正が必要な欠陥

**1. 終了処理の「全体3秒」の上限が守られない(修正)**
- `src/host_process_registry.zig:93` の `abortStart` は、毎回 `native.abort(3000)` を独自の 3 秒で呼びます。
- `shutdown` の待ちループ(`:218-226`)では、起動に失敗して後始末が残っているエントリ(設定中で native を所有したまま)の status は `state=0, ior=16` です。そのため待たずにループを抜け、`:227` の `free` から `:177` の `abortStart` に入ります。
- その結果、該当するエントリが N 件あると、共通の deadline とは別に最大 N×3 秒かかります。設計書(`docs/PROCESS_MANAGEMENT_DESIGN.md:55`)の「全体3秒を上限」に反します。
- 修正案: `abortStart` に待ち時間の上限を引数で渡せるようにします。`shutdown` からは deadline の残り時間を、`start` の失敗時は従来どおり 3000 を渡します。

**2. `fclose` が失敗すると、子の回収がされないまま残る(修正)**
- `src/main.zig:1896-1898` の `processFileDiscard` は、`slot.* = .{}` で FileSlot を空けてから `fclose` します。C の規約では `fclose` が失敗してもストリームは解放されます。つまりエラーが返った時点で、資源はもう解放済みです。
- それでも `closeStreams`(`host_process_registry.zig:82-84`)はそのエラーを返し、次の 2 か所が止まります。
  - `abortStart` `:91-92`: native 側の abort をせずに戻ります。`start` の失敗後(`:118-120`)は、強制終了のシグナルを送っただけで回収されていない子が残ります。エントリは「設定中・native 所有」のままです。設計書 `:35` の「子を終了・回収してからエラーを返す」に反します。
  - `shutdown` `:213-216`: `continue` で、そのエントリの待ちと `free` を飛ばします。終了時には再試行の機会がないため、回収できたはずの子が回収されず、`closeAllProcesses` は失敗を報告します。
- 補足: `free` の経路(`:183-184`)は、2 回目の FREE で回収できます。ただし 1 回目はエラーなのに資源は解放済み、という食い違いがあります。
- 修正案: 「ストリームを解放できなかった」(Windows の `writer`/`reader` の `deinit` 失敗で、FileSlot がまだ残っている)と、「解放はしたが `fclose` がエラー」を区別します。後者ではエラーを記録しつつ native の後始末を続けます。`closeStreams` の中で、discard の後に `belongs` が false ならそのまま続行する、という形です。

**3. 所有喪失(ECHILD)が起動失敗の後始末の経路で見つかると、FREE を 2 回呼ばないと消えない(修正)**
- 実行後の FREE の経路(`host_process_registry.zig:185-191`)には、ECHILD を受けて `abort(0)` を再試行するループがあります。`abortStart`(`:93-95`)にはありません。
- 具体的な流れは次のとおりです。
  1. 起動失敗の後始末が EBUSY で途中のまま残る。
  2. その後、何かのはずみで ECHILD が起きる。
  3. 1 回目の FREE: `abortStart` の中の `sigma_proc_destroy` が初回の報告として ECHILD を返し(`host_process_native.c:503`)、エントリは残ります。
  4. 2 回目の FREE: 除去されます。ior=10 は 2 回とも返ります。
- 実行後の経路は 1 回の FREE で済むので、挙動がそろっていません。
- 修正案: `abortStart` にも同じ再試行ループを入れます(`err == 10` なら `ownershipLost` の後に `abort(0)` をもう一度)。

## 軽微な修正候補

**4. `shutdown` が EINVAL を誤って報告する**
- 対象: `host_process_registry.zig:206-208`。
- 起動前の段階(Windows は `CreateProcess` 前、POSIX は fork 前)で失敗し、後始末も失敗したエントリは、`pointer != null` なのにプロセスがありません。
- そのため `sigma_proc_signal` が EINVAL を返し、`first` が `ior(22)` になります。`abortStart`(`:90`)は同じ結果を無視しているので、扱いがそろっていません。

**5. 時計が読めないと、残りのエントリの後始末を全部飛ばす**
- 対象: `host_process_registry.zig:221` の `clock.now() catch return ior(5)`。
- ここで return すると、後ろのエントリは `closeStreams` も `free` も試されません。
- 修正案: エラーを記録して、待たずに `free` へ進みます。

## 方針として扱うもの(欠陥ではない)

- **Windows で KILL_ON_JOB_CLOSE を使わない**: FREE で Job ハンドルを閉じても子孫は残ります。また、終了後の TERM/KILL(`native.c:200`)は Job 内に残った子孫を止めます。設計書 `:55`・`:60` に書かれているとおりの方針です。
- **POSIX の FREE 後の子孫は対象外**: 設計書 `:55` のとおりです。
- **起動失敗時の後始末が VM スレッドを最大 3 秒止める**: `start` の経路です。設計上は許容範囲ですが、上の 1 を直す際に、同じ上限を引数で渡す形にそろえることを勧めます。

## 確認して問題がなかった点

- 公開成功後の所有権の受け渡しは正しい順序です。`stream` で公開してから `streams[]` に記録し、その後 `take` します(`:116-124`)。公開に失敗したストリームは native 側の `destroy` が閉じます。
- FileSlot の再利用は `(proc_owner, fid)` で照合されます。CLOSE-FILE で `proc_owner = 0` に戻り(`main.zig:729`)、別のプロセスの公開では owner ID が異なるため、誤って取得・解放することはありません。プロセス ID も再利用されません。
- 解放した slot の `streams[slot]` は、`closeStreams` が成功した後は必ず 0 になっています。そのため次のプロセスに古い fid は残りません。
- 終了時の順序は、`defer` の逆順によって `closeAllProcesses`(`main.zig:3387`)が `closeAllFiles`(`:3386`)より先に動きます。設計書 `:55` の順序と一致します。
- Windows の reader/writer の `deinit` は、`CancelSynchronousIo` で取り消してから join するので、Job の外にいる子孫が pipe を持ち続けていても止まりません。
- 内部用(Tcl)のエントリはまだ作られていません(`create(true)` を呼ぶ箇所は見つかりませんでした)。移行の際は `stop_internal` の設定が必須です。未設定のままだと、`shutdown` の中の `destroy` が、Tcl 側のスレッドが使っている FILE を閉じてしまいます。

1〜3 は修正対象として tque に登録するのが適切ですが、今回は読み取りだけという指示なので、登録はしていません。


## registry/コア再レビュー

Warning: this sign-in may have ended between 2026-11-16 and 2026-11-19. If requests are refused, run claude auth login, or use claude setup-token for unattended jobs.
前回の指摘 5 件は、すべてコード上で修正されています。`words_process.zig` にも阻害要因(ブロッカー)は見つからず、残るブロッカーは 0 件です。Read・Grep だけで調べたので、ビルドとテストは実行していません。

## 前回の指摘の状況(すべて修正済み)

| # | 前回の指摘 | 今回の確認箇所 | 判定 |
|---|---|---|---|
| 1 | 終了処理の「全体3秒」上限が守られない | `abortStart(slot, timeout_ms)`(`host_process_registry.zig:92`)。`shutdown` は deadline の残り時間を `freeWithin` に渡し(`:243`)、`abortStart` まで届く(`:189`)。`start` からは 3000(`:120,127,135`) | 修正済み |
| 2 | `fclose` が失敗すると子の回収が飛ばされる | `closeStreams` は discard の後に、FileSlot がまだ自分の持ち物か(`belongs`)を確かめ、手放していれば ID を 0 にする(`:84`)。中断するのは、まだ残っているストリームがあるとき(`streamsPending`)か内部用のときだけ(`abortStart :96`、`freeWithin :197`、`shutdown :232`)。1 回目の FREE はエラーを返しつつエントリを除去する(`:190-191, :211`)。`main.zig:1889-1905` の処理自体は前回のままで、修正はレジストリ側で入っている | 修正済み |
| 3 | 起動失敗の後始末で ECHILD が起きると、FREE を 2 回呼ばないと消えない | `abortStart` に、実行後の FREE の経路と同じ再試行ループがある(`:98-102`) | 修正済み |
| 4 | `shutdown` が EINVAL を誤って報告する | 最初のループは native の status を直接見て、`state==0`(起動前)なら signal を送らずに次へ進む(`:221-222`)。`sigma_proc_status` は起動前でも `err=0, state=0` を返す(`native.c:184-197, 424-442`) | 修正済み |
| 5 | 時計が読めないと残りの後始末を全部飛ばす | `cleanupNow`(`:261-266`)はエラーを記録し、`maxInt` を返す。その場合 deadline は即時に期限切れ、残り時間は 0 になる(`runtime_base.zig:34-48`)。各エントリの `free` は引き続き試される | 修正済み |

項目 1 の補足として、期限が切れたあとは `abort(0)` が signal の直後に EBUSY を返し、エントリは残ります。その後 `closeAllProcesses` が失敗を報告し、`hasResources` が true なのでテーブルは解放されません。待ち時間に上限を設けた結果として、設計どおりの動きです。

## `core/words_process.zig` のレビュー

ブロッカーはありません。確認した内容は次のとおりです。

- **スタックの検証**
  - 入力の数は `requireDepth`(`:17`)で、出力の数は溢れの事前チェック(`:18`)で確かめています。これは `HostUnavailable` を判定するより前です。
  - 出力数の計算は、`help_text.zig:1309-1322` のスタック効果と一致しています。
  - 引数を取る順序も文書と一致しています。PROC-IO の `( mode which proc )` は `peek(0)` が proc、`peek(1)` が which、`peek(2)` が mode で、PROC-WAIT の `( proc ms )` も同様です。
- **メモリの検証**: PROC-ARG/CWD/ENV では、長さが負なら -24 を投げ、`memoryAddress` で範囲を確かめます。どちらもホストを呼ぶ前で、スタックは変わりません(`:29-32`)。
- **スタックを途中で壊さないこと**
  - スタックを変えるのは、ホスト呼び出しが戻った後だけです。`push` は事前チェック済みなので失敗しません。
  - `proc_start`/`proc_wait` は、`try` で投げられる例外でもスタックを保ちます。
  - `procLaunch`(`main.zig:1927-1935`)は、`registry.start` を呼んだ後に例外を投げる経路がありません。つまり、子を起動したのに例外でスタックが元に戻る、という状態は起きません。
  - `procWait` は、状態を見てから `endInput` が失敗した場合に例外を投げます。ただし観測結果は保持され、何度読み直しても同じなので、問題になりません。
- **エラー時の値**: エラー時の fid や proc は `FileResult.value` の既定値 0 で返ります(`host_interface.zig:31`)。

## 方針として扱うもの(欠陥ではない)

- **ホストが使えないときの返し方がそろっていない**: PROC-NEW/ARG/IO/STDIN/STATUS/TERM/KILL/FREE は ior -21 を返します。一方、PROC-START/PROC-WAIT は例外 `HostUnavailable` を投げます(`main.zig:1916-1978`)。これを文書化するか、どちらかにそろえるかは方針として決める事項です。
- **PROC-START が出力の flush 失敗を例外にする**: flush が失敗すると、ior ではなく `HostFailed`/`UserInterrupt` を投げます(`main.zig:963-968`)。子はまだ起動していないので、整合性の問題はありません。
- **PROC-WAIT で ms が大きすぎると例外になる**: 正の ms が大きすぎて deadline の計算が溢れると、`ResultOutOfRange` の例外になります(`main.zig:1953`)。無期限としては扱いません。
- **起動失敗の後始末が VM スレッドを最大 3 秒止める**(`:120,127,135`): 前回のとおり、許容範囲です。
- **Windows で KILL_ON_JOB_CLOSE を使わない/POSIX の FREE 後の子孫は対象外**: 前回のとおり、設計書の方針です。
- **内部用(Tcl)の経路は未実装**: `create(true)` の呼び出し元はまだなく、`processRegistry` も `stop_internal` を設定していません(`main.zig:1910`)。移行の際は `stop_internal` の設定が必須です。設定しないと、`shutdown` の中の `destroy` が、Tcl 側のスレッドが使っている FILE を閉じてしまいます。

## 未確認

- **Windows の writer の `deinit` を再試行してよいか**: `processFileDiscard` では、`writer.deinit` が成功したあとに `reader.deinit` が失敗すると、次の再試行で `writer.deinit` がもう一度呼ばれます(`main.zig:1893-1894`)。
  - reader 側は、片付けた各段階のフィールドを null にするので、再試行しても安全です(`host_file_reader.zig:223-234`)。
  - writer の実装は今回読んでいないので、2 回呼んでよいかは未確認です。
- **前回 tque 登録を保留した 1〜3**: 今回の範囲は読み取りだけなので、tque の状態は確認していません。

# 639 実装のClaude Codeレビュー原文

2026-11-19。各レビューは固定スナップショットに対する読取り専用の静的レビュー。実行検証はロクが別途実施。

## 読取り初回レビュー

# input1094 読取りバックエンドのレビュー結果（固定スナップショット `.work/639/read-review-snapshot/`）

ブロッカーは3件です。どれもコードを読んでの判断で、ビルドやテストは実行していません。writer 未接続はブロッカーにしていません。

## ブロッカー

**B1. pause/deinit が止まらなくなる競合（`host_file_reader.zig:72-81`, `:134-149`）**
- worker は `stopping` を 72 行でロックの外で読みます。キューが満杯のときは、ロック内で `ResetEvent(space)` をしてから INFINITE で待ちます。
- その間に pause が割り込むと、次の順で止まります。
  1. worker が 72 行で `stopping=false` を読む。
  2. pause が `stopping=true` にして `SetEvent(space)` を呼ぶ。
  3. worker が `ResetEvent` で通知を消し、`WaitForSingleObject(space, INFINITE)` に入る。
- このとき `in_io=false` なので、pause は `CancelSynchronousIo` を呼びません。10ms ごとに見に行くだけで、終わりません。
- 起きる場面: 移行済みのパイプに 64KiB 以上がたまったまま、CLOSE-PIPE / CLOSE-FILE / SYSTEM / OPEN-PIPE / 子プロセス起動を行うとき。stdin の pause も同じです。
- 修正案: worker がロック内で `stopping` を見直してから `ResetEvent` する。pause 側も `stopping` の設定と `SetEvent` をロック内で行う。

**B2. READ-FILE で、移行済みパイプのデータが失われる（`main.zig:804-807`）**
- `readerByte` は、キューが空になって初めてエラー（ior）や中断を返します。
- そのため、`count` バイトを受け取った後にエラーや Ctrl+C（-516）が来ると、`.{ .ior = ... }` だけを返します。
  - キューから取り出したバイトは呼び出し側に渡らず、捨てられます。
  - decoder に残った prefix の後ろに欠けができ、順序も崩れます。
- 設計書の「保留prefixは未報告のエラー/中断で失わない」に反します。中断は reader 経路で新しく入ったため、既存の動作ではなく今回の後退です。
- `LineSource.get`（`:727-733`、READ-LINE）も同じで、中断すると途中まで取り出した行が失われます。
- 修正案: `value = prefix + count` と ior を一緒に返して prefix を確定する。または、取り出したバイトを decoder に戻す。

**B3. 1091 の境界: pending があると native パイプでも seek してしまう（`main.zig:832-840`）**
- native パイプを seek しない判定（844-858 行）より前に、`input.length != 0` のときの `tell64` / `seek64` / `resetFileInput` が無条件に実行されます。
- R/W で開いた POSIX FIFO/ソケット: KEY?-FILE や EKEY-WAIT で pending ができた後の WRITE-FILE が ESPIPE で失敗します。
- Windows のパイプ: tell/seek が失敗せずに通ってしまうと、`resetFileInput` で未読の pending が消えます（※推測です。UCRT がパイプに対して ESPIPE を返すかは未確認）。
- 修正案: pending があるときの同期処理も `native_pipe`（slot の値）で飛ばす。あわせて `fileReposition` / `filePosition` / `fileSize`（`:871`, `:882`, `:892`）も `.pipe` だけでなく `native_pipe` で ESPIPE を返すようにする。

## 確認して問題なかった点
- start / pause / join の流れ:
  - pause は `in_io` をロック内で見て、`CancelSynchronousIo` を 1168 なら繰り返し、取得済みのデータは保持します。
  - deinit は join の後で `self.* = .{}` にするので、ID を再利用できます。
  - `closeAllFiles` は、reader が残っている間は wake を解放しません。
- CRT との同時読取りはありません。移行後の stdin は `rawStandardInputByte` / `redirectedInputReady` が reader を経由し、file 側は `managedReader` で fread/getc を避けています。パイプストリームは `_IONBF` です。
- 子プロセスの前の stdin pause は `runShellCommand` / `fileOpenPipe` / `processStart` の3か所にあり、キューは保持されます。
- 文字でない通知は `deferred_packets` に残り、EKEY が lookahead より先に出すので順序は保たれます。
- EOF とエラーは sticky で、データを先に渡します。部分読取りとエラーが同時のときは、READ-AVAILABLE が `count` と ior を返します。
- u=0 は reader を起動せず、EOF も進めません。core 側も `length != 0` のときだけ `beforeFileRead` を呼びます。
- 不正 ID は、core と host の両方で全件を待機前に検査しています。callback が失敗しても引数の3セルは残り、成功時だけ `data_depth -= 3` します。範囲外の index は HostFailed になります。

## 要実測（ブロッカーではありません）
- 書き手が 0 バイトの WriteFile をすると、`ReadFile` が成功のまま 0 バイトで返り、`ended=true` と誤って判定する可能性があります（`:106`）（※推測です）。実際のパイプで試すことをおすすめします。
- READ-FILE の reader 経路は、1バイトごとに `ensureReader` と guard の開始・終了を行っています。性能面の改善候補です。


## 統合初回レビュー

# 639 非ブロッキングI/O 実装スナップショットのレビュー（`.work/639/current-review` と `docs/ASYNC_IO_DESIGN.md` の照合）

レモン、読取り専用でレビューしました。ファイルは編集せず、コマンドも実行していません。そのため、ビルドとテストの結果は未確認です。

結論として、前回の B1〜B3 は解消を確認しました。新たに、出力の順序とデータ保持に関わるブロッカーが 4 件あります。

## 前回指摘の確認

- **B1（停止フラグとロック）：解消。** 停止フラグはロック内で立て（`host_file_reader.zig:201-204`）、ワーカーもロック内で再確認してから `in_io` を立てます（`:79-87`）。キャンセルは繰り返し行い、`1168` は許容しています（`:206-217`）。`in_io` が立ってから ReadFile に入るまでの隙間も、再試行で吸収されます。
- **B2（部分読取りの件数）：解消。** `main.zig:815-830` では、1 バイト以上読めたときだけ先読み分を消費して `prefix+count` を返します。1 バイトも読めなければ 0 を返し、先読み分は残します。
- **B3（native_pipe の seek）：解消。** 該当箇所は ESPIPE(29) を返します（`main.zig:893, 904, 914, 926`）。`prepareFileWrite` は native_pipe を素通りさせます（`:848`）。

## ブロッカー

**1. 管理下の stderr への書込みが切れたまま捨てられる**
- 場所：`main.zig:2503-2507`
- 内容：stderr のライターが動いた後の `writeStandardError` は、キューに入った分だけで終わります。待ちも再試行もありません。
- 起きること：一度 `WAIT-WRITABLE` / `WRITE-AVAILABLE` を stderr に使うと、それ以降のエラーメッセージは途中で切れ、戻り値 false だけが残ります。キュー 64KiB が埋まっているときに起きます。
- 変更前は直接のブロッキング書込みでした。キューを使うなら、受け入れきるまで drain して再投入する必要があります。

**2. stdout がライター管理下のとき、`flushOutput` が同期的なフラッシュではなくなる**
- 場所：`main.zig:2622-2629`
- 内容：キューへ積むだけで、書き終わりを待ちません。ところが次の箇所は「書き終わっている」前提で呼んでいます。
  - `runShellCommand`（`:377`）
  - `fileOpenPipe`（`:671`）
  - `writeStandardErrorDirect`（`:2513`、コメントは「stdout が先に出る」）
  - `processStart`（`:1755`、こちらはフラッシュ自体がありません）
- 起きること：
  - SYSTEM、OPEN-PIPE、プロセス起動で、子の出力が親の既出力より先に出ます。
  - `2>&1` でパイプに送ると、stderr が先行する stdout を追い越します。
  - stderr もライター管理下だと、キューが 2 本で別スレッドになるため、順序は保証されません。
- 修正案：上記の箇所で `flushStandardOutput()`（drain）と stderr の drain を行います。stderr への書込みの前には、stdout の drain が必要です。

**3. stdin と stdout/stderr の同一オブジェクト検査が片方向だけ**
- 場所：`main.zig:1142-1149`
- 内容：`id == stdin` のときだけ CompareObjectHandles で比べています。stdout/stderr をライターへ移す側では比べていません。
- 起きること：同じ同期ファイルオブジェクトを、権限を絞って複製し stdin と stdout に割り当てた場合、問題が起きます。
  - メインスレッドは stdin を同期 ReadFile で読み続けます（`:2015` または `:738`）。
  - その間、ライターの WriteFile が止まります。これは設計 §34 のプローブで確認済みの現象です。
  - 結果として、プロンプトが出ないまま入力を待つ状態になります。
- 設計 §41 は「読取りワーカーへ移行しない」とだけ書いており、書込み側の扱いが抜けています。設計への追記と、書込み方向の検査の両方が必要です。

**4. 中断時の FLUSH/CLOSE の扱いが決まっておらず、キューが捨てられる**
- 場所：`main.zig:717-723`, `697-709`
- 内容：`finishWriter` が `-516` を返しても、そのまま `deinit` に進みます。`deinit` は送信中の WriteFile をキャンセルし、キューを破棄して fid を閉じます。
- 設計の「FLUSH/close で配送完了を待つ」に対して、中断時の扱い（fid を開いたまま再試行させるか、破棄を仕様にするか）が書かれていません。
- 終了時の経路にも同じ問題があります。
  - 致命的エラーの経路（`:3122`）は、待たない `flushOutput` の後に `libc.exit` するため、stdout のキューが失われます。
  - `closeAllFiles`（`:1035`）は、中断が保留されていると drain が即座に戻り、キューが捨てられます（`drainWriter :1390`）。

## 推測（※いずれも推測です。実プローブで確認が必要です）

- **H1：** 書込み側が 0 バイトの WriteFile を行うと、ReadFile が「成功・0 バイト」で返り、EOF と誤判定するおそれがあります。該当は `host_file_reader.zig:116` と `main.zig:1201`。
- **H2：** `pause()` が途中で HostFailed を返すと、停止フラグが立ったまま thread が残ります。その後の `start()` は `thread != null` で何もせず戻ります（`host_file_reader.zig:62`）。ワーカーが自然に終わると、`readerByte` は Ctrl+C まで 20ms 待ちを繰り返す、と推測されます。発生には API の失敗が必要です。
- **H3：** stdout ライターは CRT の `fwrite/fflush` をワーカースレッドで呼びます（`host_file_stdio.c`）。
  - 終了時のキャンセルが CRT 内部に当たると、fflush に失敗しても `transferred` は fwrite の件数のままで、キューから消えます。
  - 現スナップショットでは、メインスレッドから CRT stdout へ直接書く経路は、管理下では見つかりませんでした。
- **H4：** POSIX の O_NONBLOCK の付け外し（`main.zig:1408-1418`, `1606-1616`）は、open file description 単位で効きます。
  - fd 0/1/2 が同じ tty や親シェルと description を共有している場合、他のプロセスやスレッドに一時的に影響します。
  - 設計は復旧しか定めていません。
- **H5：** POSIX で FIFO を r/w で開いた場合、`getc` の後に seek/flush なしで `fwrite` します（`:848`）。C 標準では未定義動作です。`_IONBF` なら glibc/BSD では実害は小さいと推測されます。Mac・Linux 実機での確認が必要です。
- **H6：** poll の後に読む方式（`main.zig:1290-1293`）は、共有している stdin を別の読み手に先に取られると、ブロックするおそれがあります。

## 残りの欠落

- 管理下の stdin に対する KEY/READ は、`fileStdinByte` の 1ms スリープループで待ちます（`:1749-1750`）。wake を使っていないため、短い周期のポーリングになります。
- `fileReadAvailable` は、部分読取りの後に起きた中断以外のエラーを EIO にまとめます（`:1317`）。元の errno が失われます。
- 不足しているテスト：
  - 管理下 stderr への部分受け入れ
  - stdout/stderr と子プロセスの順序
  - 中断時の close/flush
  - 書込み方向の同一オブジェクト検査
  - `pause` 失敗後の再開
  - 0 バイト書込みと EOF の判定
- Mac 実機での確認は、設計どおり別の受け入れ項目として残っています。


## 統合再レビュー

レモン、`.work/639/current-review` の最新スナップショットと `docs/ASYNC_IO_DESIGN.md` を読んで再レビューしました。ファイルの編集とコマンドの実行はしていないため、ビルドとテストの結果は未確認です。

**結論：コードに残るブロッカーはありません。** ただし、設計書への追記 1 件は確定前に必要です。

## 前回のブロッカー（コードで解消を確認）

1. **stderr：解消。** 全量をコピーするまで繰り返し、最後に drain します（`main.zig:2559-2570`）。
2. **順序：解消。** 子プロセスを起動する前と、stderr へ書く前に、stdout と stderr を drain しています。
   - SYSTEM：`:377`
   - OPEN-PIPE：`:673-676`
   - プロセス起動：`:1810`
   - stderr 直接書込みの前：`:2576`
3. **同一オブジェクト検査：解消。** stdout/stderr を書込みに使うときも、stdin と比べるようになりました（`:1176-1180`）。
4. **中断時の CLOSE：解消。** CLOSE と CLOSE-PIPE は -516 を返し、fid とキューを残します（`:703`, `:724`）。
   - 致命的エラーの経路も確認しました。`defer closeAllFiles`（`:3205`）は runtime の defer（`:3186`）より後に登録されています。そのため先に実行され、ライターを片付けます（`:1071-1072`）。その後の `flushOutput` と `writeStandardError` は直接書込みになります。
- **その他の解消（前回 H2 と残りの欠落）：**
  - リーダーは pause に失敗した後、次の start で pause をやり直します（`host_file_reader.zig:62`）。
  - 管理下の stdin の待ちは wake を使います（`main.zig:1780-1784`）。
  - READ-FILE と READ-LINE は、ior があっても件数を返します（`words_files.zig:175-180, 237-241`）。

## 設計書への追記（確定前に必要）

`ASYNC_IO_DESIGN.md:32` には「FLUSH/closeで配送完了を待つ」とだけあり、次の 3 点が書かれていません。

- CLOSE が中断されたら -516 を返し、fid とキューを残して再試行させること
- `closeAllFiles` は例外とし、中断の後はキャンセルして捨てること。通常の終了では標準出力と標準エラーの両方を drain すること
- stdout がライター管理下に移った後は、通常の出力もキュー経由になること（`:2694-2699`）。`:32` の「通常WRITE-FILEは…直接書込み」は stderr とファイルにだけ当てはまります。

## コードを読んで確認した軽微な点（ブロッカーではありません）

- **a. drain が中断を先に見る（`:1435`）**
  - キューが空でも、中断が保留されていれば -516 を返します。そのため配送済みの CLOSE や FLUSH も -516 になります。
  - `writeStandardError` では、先頭の `flushStandardOutput` が何もせずに戻り、stdout が出る前に stderr が出ます。キューが一杯のときは、残りのメッセージを捨てます（`:2560`, `:2567`）。
  - ※推測です：中断のラッチが、診断メッセージを出すときまで残っているかどうかで、実際に起きるかが決まると推測されます。ラッチを消す時点は host_wait.zig にあり、スナップショットに含まれないため確認していません。
- **b. 片付けの途中で止まる（`:1071`）**
  - `stdout_writer.deinit() catch return;` が失敗すると、stderr と stdin の片付けと wake の解放を飛ばします。
- **c. C ストリーム経路の件数（`:840-843`, `:780-782`）**
  - 通常ファイル、POSIX で OPEN-FILE した FIFO などで ferror が起きると、部分件数を返さず 0 にします。パイプ経路の「部分件数を返す」と動作がそろっていません。
- **d. READ-LINE の CR の後（`:789-791`）**
  - CR の次の 1 バイトを読むときに出たエラーや中断を捨て、行を正常に返します。
- **e. 部分読取り後のエラー番号（`:1362`）**
  - `fileReadAvailable` は、部分読取りの後に起きた中断以外のエラーを EIO にまとめたままです。

## 推測（※いずれも推測です。実機での確認が必要です）

- **H1（変化なし）：** 相手が 0 バイトの書込みをしたとき、EOF と誤判定するおそれが残ります。`directPipeByte` の `:1240` は、成功して 0 バイトなら EOF とします。
- **H3（影響は小さい）：** stdout のワーカーは、fflush に失敗しても `transferred` を全量として返します（`host_file_stdio.c:15-17`）。エラーは sticky なので、実際の影響は小さいと推測されます。
- **H4（未対処）：** O_NONBLOCK の付け外し（`:1454`, `:1655`）が、description を共有する他のプロセスへ影響するおそれがあります。設計書は復旧しか定めていません。
- **H5：** 残るのは OPEN-FILE で開いた FIFO だけです。読み書き両用の FIFO で `getc` の後に `fwrite` します（ESPIPE を許して `:866-868` を通過）。
  - ネイティブパイプでは解消しています。OPEN-PIPE の読み書き両用は拒否し（`:667`）、生 fd で読み書きします（`:894-903`, `:1248`, `:1659`）。
- **H6（未対処）：** POSIX で、poll の後にブロッキングで読みます（`:1335-1337`）。

不足しているテストのうち、次の 2 つが今回の変更に当たります。

- 中断が保留されたまま CLOSE して、その後に再試行する
- 中断が保留されたまま stderr に書く

Mac 実機の確認は、設計どおり別の受け入れ項目として残っています。


## 最終限定レビュー

レモン、最終レビューの結果です。読んだ範囲は、現在の `src/main.zig` の該当関数、`host_file_reader.zig`、`words_files.zig`、設計書2本、前回レビューです。ファイルの編集とコマンドの実行はしていません。`.work/639/current-review/main.zig` との行単位の比較はしておらず、ご指定の変更点を現在のコードで確かめました。テストの結果は未確認です。

**結論：ブロッカーはありません。** 細かい不整合が2件、文書の配置の問題が1件あります。

## ご指定の変更点（コードで確認済み）

- **WAIT-FILES ms=0：** 初回はリーダーへ移さず（`main.zig:1592`）、`PeekNamedPipe` と `directPipeByte` で1回だけ調べます（`:1677-1686`）。待ち時間が正でも負でも、または既に移行済みなら、`ensureReader` を呼びます。設計書 `:61` のとおりです。
- **nativePipe：** OS による分岐がありません（`:1235`）。POSIX のパイプは、読取り（`:1263`, `:1697`）も書込み（`:898-907`）も生 fd を使います。
- **リダイレクトされた stdin：** 一時的に O_NONBLOCK にして、読んだ後に元へ戻します。戻すのに失敗しても、読めたバイトは unread して残します（`:1350-1367`）。
- **通常ファイルの READ-FILE/READ-LINE：** fread または getc が途中でエラーになっても、件数と ior を返し、prefix は確定させます（`:841-848`, `:779-784`）。core 側も、ior があるときに件数を捨てていません（`words_files.zig:176-180`, `:238-241`）。
- **成功した0バイトの読取り：** `directPipeByte`（`:1253`）と worker（`host_file_reader.zig:116-119`）は、どちらも EOF として扱わず読取りを続けます。
- **closeAllFiles：** 標準の3つの deinit をすべて試します。1つでも残れば、Wake は解放しません（`:1074-1091`）。設計書 `:49` と一致しています。

## 新しく見つけた不整合（ブロッカーではない）

1. **移行前のリダイレクト stdin パイプでは、0バイトの成功が EOF のまま**
   - 該当箇所：`main.zig:2114`（`rawStandardInputByte` の Windows 分岐）
   - `ReadFile` が成功して0バイトを返すと、`-1` を返し、errno は0です。この組み合わせは EOF として扱われます。
   - 起きる条件：stdin が worker に移る前に、KEY、READ-LINE、READ-FILE で stdin を読んでいるとき、相手が長さ0の WriteFile をした場合です。
   - 設計書 `:55` は「成功した0バイトの pipe ReadFile を EOF にしない」と範囲を限らずに書いています。そのため、この経路が設計と合いません。
   - 直し方は2つあります。
     - コードを直す場合：`GetFileType == 3`（パイプ）のときだけ読取りを続けます。ディスクファイルでは、0バイトは正しい EOF なので、今のまま区別します。
     - 文書を直す場合：設計書 `:55` の対象を「ファイル ID のパイプと worker」に限ります。

2. **通常ファイルの READ-LINE で、CR の後の読取りエラーを報告しない**
   - 該当箇所：`main.zig:789-797`
   - FILE の経路では、CR の次の `getc` が失敗しても `source.ior` を設定しません。そのため、行は ior=0 で正常に返ります。
   - `clearerr` もしないため、エラーフラグが残ります。後で EOF に着いたときに、`:780` または `:841` が古いエラーを報告するおそれがあります。
   - パイプとリーダーの経路は修正済みです。そのため、実装記録 `:26`「CRの後の読取りエラー…採用」は FILE の経路には当てはまりません。

3. **設計書の文書配置**
   - `ASYNC_IO_DESIGN.md:61` の WAIT-FILES ms=0 の段落が、記録へのリンク行（`:59`）の後ろにあり、どの節にも入っていません。
   - 「## 実装レビュー後の終了・共有契約」の箇条（`:57` の後）か、「### 判定とエラー値の確定」へ移すと、文書の構成と合います。

## 最終判断

確定に進めて問題ありません。1は設計書の記述とコードが食い違っているため、コードか文書のどちらかを、確定の前か後続タスクでそろえることをお勧めします。2と3は軽微です。

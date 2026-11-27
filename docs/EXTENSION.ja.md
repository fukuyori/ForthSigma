# ForthSigma 拡張機能の手引き

英語版（原本）: [EXTENSION.md](EXTENSION.md)。この日本語版は英語版の訳です。

この手引きは、端末、ファイル、子プロセス、バックグラウンド計算を使う Forth プログラムを書くためのものです。各章は基本の説明、実行できる例、詳しい説明の順に進みます。語ごとの契約は[全ワードリファレンス](WORD_REFERENCE.ja.md)、言語とコマンドラインは[利用者マニュアル](USER_MANUAL.ja.md)を参照してください。

Forth のコードブロックをそれぞれ別の UTF-8 の `.fs` ファイルに保存し、Windows ではリポジトリのルートから `zig-out/bin/sigma.exe path/to/example.fs` で実行してください。POSIX では `zig-out/bin/sigma` を使います。例は全機能入りの構成、十進数、例ごとに独立したプロセスを前提とし、`EXEC-LIMITED` には debug も必要です。実行ファイルがなければ `zig build` でビルドします。ファイルを使う例はリポジトリのルートを作業ディレクトリとします。一時ファイルには `.work/1457/` を使うので、先にこのディレクトリを作成してください。窓や音声装置を開く例はありません。

## 1. 語群の読み込みと共通規則

`REQUIRE-EXTENSION` は語群を初回だけ読み込みます。`ALSO EXTENSION` で検索順に加え、`PREVIOUS` でその検索順から外します。読み込みだけでは語群を選択しません。読み込みの語はコロン定義の外に置いてください。

```forth
REQUIRE-EXTENSION ALSO EXTENSION
HOST-OS TYPE CR
PREVIOUS
BYE
```

Windows では `windows` と表示します。`HOST-OS ( -- c-addr u )` はビルド対象の OS 系統を `windows`、`linux`（WSL と Android を含みます）、`macos`、`unknown` のいずれかで返します。将来、未知の値が増えた場合も unknown として扱ってください。返された文字列は借用した読み取り専用の領域で、次の呼び出しまたは辞書の復元まで有効です。保持する場合はコピーしてください。

extension は graphics と audio から独立して選択できます。`-Dextension=false` は読み込みの語と語群を除外します（読み込みの語は未知の語となり -13 です）。`-Ddebug=false` は `EXEC-LIMITED` を除外しますが、タスク制御は残ります。`-Dfiles=false` は通常のファイル語を除外し、ファイルに依存する拡張操作も使えなくします。メモリ上のパス整理と書記素操作には files は不要です。`-Dgraphics=false` では複合待機の描画対象を使えません。`-Daudio=false` は PCM を除外し、`-Dimage=false` は保存アプリの語を除外します。`-Dhelp=false` が除外するのは HELP であり、拡張 API ではありません。

`ior` が 0 なら API の呼び出しは成功です。ただし、子プロセスの正常終了、タスクの成功、待機条件の成立を意味するわけではありません。他の戻り値も確認します。`THROW` は 0 を受け取ると何も起こさず、0 以外なら例外を発生させます。失敗時に処理を止める例ではこれを使います。復旧する場合は、特に I/O の部分転送件数やバッファ不足の戻り値を先に調べてください。メモリ・スタックの検査やホスト機能の不足では直接 THROW することもあるため、ior を返す API でも例外は発生します。区別は語ごとの契約に従います。`CATCH` は資源の解放や副作用の取り消しを代行しません。

本書の相対時間による待機は、`ms=0` がポーリング、負数が全体の期限なし、正数が単調時計による一つの期限です。時間切れと EOF は戻り値で区別します。準備完了の通知はバイトや空き容量を予約しません。対応する待機の範囲内では端末の Ctrl+C は -28 を THROW しますが、ファイルやパイプの値 3 はデータです。中断の制約とエラー処理は第6章・第9章で説明します。

### この章の語

[`HOST-OS`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a484f53542d4f53)。

別の語群に属する関連語: [`REQUIRE-EXTENSION`](WORD_REFERENCE.ja.md#w-53796e7461783a524551554952452d455854454e53494f4e)。

## 2. 端末の表示と標準イベント

`TERM-MODE!` で端末の表示要求全体を置き換え、`TERM-MODE@` で受理された要求を読みます。標準入力のイベントには `EKEY-WAIT` を使うと、不完全なエスケープ列を自分で読み続ける必要がありません。次の例は表示を解除して寸法を問い合わせるだけなので、出力をリダイレクトしても実行できます。

```forth
REQUIRE-EXTENSION ALSO EXTENSION
0 TERM-MODE! THROW
TERM-MODE@ . COLS . ROWS . CR
PREVIOUS
BYE
```

出力をリダイレクトした場合は `0 80 24` になります。`COLS` と `ROWS` は `FORM` と同じ出力先の規則を使います。寸法を取得できればその値、できなければ80列24行です。文字列への出力取り込み中は列数が最大正セル値、行数が1になります。

要求ビットは `OR` で組み合わせます。`TERM-ALT-SCREEN`=1、`TERM-PASTE`=2、`TERM-HIDE-CURSOR`=4、`TERM-MOUSE`=8 です。たとえば代替画面でカーソルを隠すマスクは `TERM-ALT-SCREEN TERM-HIDE-CURSOR OR` です。設定に成功すると、以前の全ビットを置き換えます。エラー経路も含め、`0 TERM-MODE! THROW` で明示的に解除してください。取得したマスクは受理された要求であり、端末からの肯定応答ではありません。マウスと貼り付けの報告は raw 入力中だけ適用されます。Windows は貼り付け要求を無視します。0 以外の要求には標準出力が対応端末である必要があります。Forth の出力取り込みには端末制御は混ざりません。

次のイベントの例は選択したファイルを読むので、対話入力を待ちません。小さなファイルを作成して削除します。EOF も真のフラグを伴う完全なイベントです。

```forth
REQUIRE-EXTENSION ALSO EXTENSION
S" .work/1457/event.dat" W/O CREATE-FILE THROW CONSTANT EF
S" A" EF WRITE-FILE THROW
EF CLOSE-FILE THROW
: EVENTS
  0 EKEY-WAIT THROW SWAP . . CR
  0 EKEY-WAIT THROW DROP K-EOF = . CR ;
S" .work/1457/event.dat" R/O OPEN-FILE THROW CONSTANT INPUT-F
' EVENTS INPUT-F INFILE-EXECUTE
INPUT-F CLOSE-FILE THROW
S" .work/1457/event.dat" DELETE-FILE THROW
PREVIOUS
BYE
```

`65 -1` と `-1` を表示します。文字 A の後に EOF が来たことを示します。`EKEY-WAIT ( ms -- event flag ior )` は時間切れなら `0 false 0`、EOF なら `K-EOF true 0` を返します。途中まで届いた UTF-8 やエスケープ列は時間切れでも保持します。ファイルは UTF-8 として読みますが、ESC と値 3 はそのままの文字です。`INFILE-EXECUTE ( xt fileid -- )` は選択ファイルを借用するので、復帰後に明示的に閉じてください。

`K-MOUSE` を消費した後で `EKEY-MOUSE ( -- column row buttons wheel )` を呼びます。座標は0起点で、ボタンのビットは左=1、右=2、中央=4、ホイールは上=1、下=-1です。`EKEY?` の先読みではこの付随情報は変わりません。対応する入力では `K-PASTE-BEGIN` と `K-PASTE-END` が貼り付けの境界となり、貼り付け中の制御バイトも文字として扱います。バイト入力または GRAPHICS 入力へ切り替えると貼り付けの解釈は終わります。同じ入力を二つの経路で読んでも、イベントが複製されるわけではありません。

### この章の語

[`TERM-MODE!`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5445524d2d4d4f444521), [`TERM-MODE@`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5445524d2d4d4f444540), [`COLS`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a434f4c53), [`ROWS`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a524f5753), [`EKEY-WAIT`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a454b45592d57414954), [`EKEY-MOUSE`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a454b45592d4d4f555345), [`TERM-ALT-SCREEN`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5445524d2d414c542d53435245454e), [`TERM-PASTE`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5445524d2d5041535445), [`TERM-HIDE-CURSOR`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5445524d2d484944452d435552534f52), [`TERM-MOUSE`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5445524d2d4d4f555345), [`K-MOUSE`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a4b2d4d4f555345), [`K-PASTE-BEGIN`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a4b2d50415354452d424547494e), [`K-PASTE-END`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a4b2d50415354452d454e44)。

別の語群に属する関連語: [`EKEY`](WORD_REFERENCE.ja.md#w-464f5254483a454b4559), [`EKEY?`](WORD_REFERENCE.ja.md#w-464f5254483a454b45593f), [`K-EOF`](WORD_REFERENCE.ja.md#w-454b4559533a4b2d454f46), [`INFILE-EXECUTE`](WORD_REFERENCE.ja.md#w-464f5254483a494e46494c452d45584543555445)。

## 3. 非ブロッキングのファイル I/O

準備完了を待ってから、その時点で転送できる分を扱い、残りは次の処理に回します。入力が一時的に空であることと EOF を区別してください。次の例は通常ファイルを使うので、外部の送信側は不要です。

```forth
REQUIRE-EXTENSION ALSO EXTENSION
CREATE IDS 1 CELLS ALLOT
CREATE BUF 16 ALLOT
S" .work/1457/io.dat" W/O CREATE-FILE THROW CONSTANT WF
WF IDS !
IDS 1 0 WAIT-WRITABLE THROW . CR
S" hello" WF WRITE-AVAILABLE THROW . CR
WF FLUSH-FILE THROW WF CLOSE-FILE THROW
S" .work/1457/io.dat" R/O OPEN-FILE THROW CONSTANT RF
RF IDS !
IDS 1 0 WAIT-FILES THROW . CR
BUF 16 RF READ-AVAILABLE THROW DROP BUF SWAP TYPE CR
RF CLOSE-FILE THROW
S" .work/1457/io.dat" DELETE-FILE THROW
PREVIOUS
BYE
```

`0`、`5`、`0`、`hello` を表示します。配列に入れるのはセル単位のファイル ID であり、OS ハンドルではありません。`WAIT-FILES` と `WAIT-WRITABLE` は `( addr n ms -- index ior )` で、件数は1〜64、返す添字は0起点です。待機前に全要素を検査します。EOF と I/O エラーも準備完了となり、時間切れは `-1 0` です。前の要素が準備できていても、不適合な要素の添字とエラーが返る場合があります。

`READ-AVAILABLE ( addr capacity fid -- count eof? ior )` は現在読めるバイトを返し、直ちに戻ります。count=0、EOF が偽、ior=0 は再試行が必要な状態であり、入力の終わりではありません。部分件数とエラーが同時に返る場合は、復旧する前にそのバイトを保持・処理します。容量0の読取りは要求を検査しますが、入力を消費せず EOF の観測も進めません。通常の読取りとイベント読取りは、同じファイルの保留バイトを共有します。

`WRITE-AVAILABLE ( addr length fid -- accepted ior )` は受理したバイトを復帰前にコピーします。その件数だけ送信元を進め、残りは書き込み可能になってから再試行します。受理は配送完了を意味しません。Windows ではキューに受け入れた後で配送が失敗することがあり、そのエラーは閉じるまで保持されます。`FLUSH-FILE` と close は配送を待つため、処理が止まる場合があります。Windows で close が中断されると -516 を返し、再試行用に ID とキューを保持します。POSIX の書込みは直接の結果を返し、Windows の配送キューは使いません。

新しい4語は端末の中断で -28 を THROW します。Windows の同期双方向パイプと、stdin が stdout/stderr と同じパイプ実体を共有する構成は、この API では EINVAL（-534）になります。通常のファイル操作と従来のイベント操作はそれぞれの契約を維持します。制約の詳細は[I/O 設計](ASYNC_IO_DESIGN.md)を参照してください。

### この章の語

[`WAIT-FILES`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a574149542d46494c4553), [`READ-AVAILABLE`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a524541442d415641494c41424c45), [`WRITE-AVAILABLE`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a57524954452d415641494c41424c45), [`WAIT-WRITABLE`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a574149542d5752495441424c45)。

別の語群に属する関連語: [`OPEN-FILE`](WORD_REFERENCE.ja.md#w-464f5254483a4f50454e2d46494c45), [`CLOSE-FILE`](WORD_REFERENCE.ja.md#w-464f5254483a434c4f53452d46494c45), [`FLUSH-FILE`](WORD_REFERENCE.ja.md#w-464f5254483a464c5553482d46494c45)。

## 4. 子プロセスとパイプ

stdin・stdout・stderr の分離、個別の引数、終了要求が必要なら `PROC-*` を使います。設定を作り、引数をコピーし、起動し、出力を読み、終了を確認して解放します。`PROC-START` はシェルを暗黙に呼びません。次の Windows の例は Windows PowerShell を明示的に起動します。出力が短い1行だけなので、読取り前に終了を待っても出力パイプは満杯になりません。

```forth
REQUIRE-EXTENSION ALSO EXTENSION
PROC-NEW THROW CONSTANT P
S" powershell.exe" P PROC-ARG THROW
S" -NoProfile" P PROC-ARG THROW
S" -NonInteractive" P PROC-ARG THROW
S" -Command" P PROC-ARG THROW
S" Write-Output child-ok" P PROC-ARG THROW
P PROC-START THROW
P PROC-STDIN THROW CLOSE-FILE THROW
P -1 PROC-WAIT THROW . . CR
CREATE CHILD-BUF 64 ALLOT
CHILD-BUF 64 P PROC-STDOUT THROW READ-AVAILABLE THROW
DROP CHILD-BUF SWAP TYPE
P PROC-FREE THROW
PREVIOUS
BYE
```

終了コード `0`、状態 `2`、`child-ok` を表示します。POSIX のシェルで対応する引数は `/bin/sh`、`-c`、`printf child-ok` です。次の例は設定だけを作るので、どちらの OS のシェルも起動せず、両方の引数列を確認できます。POSIX で前の例を使うときは、Windows 用の5引数を、後半の3引数に置き換えてください。

```forth
REQUIRE-EXTENSION ALSO EXTENSION
PROC-NEW THROW CONSTANT WIN-P
S" powershell.exe" WIN-P PROC-ARG THROW
S" -NoProfile" WIN-P PROC-ARG THROW
S" -NonInteractive" WIN-P PROC-ARG THROW
S" -Command" WIN-P PROC-ARG THROW
S" Write-Output child-ok" WIN-P PROC-ARG THROW
WIN-P PROC-FREE THROW
PROC-NEW THROW CONSTANT POSIX-P
S" /bin/sh" POSIX-P PROC-ARG THROW
S" -c" POSIX-P PROC-ARG THROW
S" printf child-ok" POSIX-P PROC-ARG THROW
POSIX-P PROC-FREE THROW
." configurations-ok" CR
PREVIOUS
BYE
```

`configurations-ok` と表示します。最初の `PROC-ARG` は実行ファイル名で、それ以降は空文字も含めて引数を追加します。`PROC-CWD` は子の作業ディレクトリを設定し、空なら起動時の親の値を継承します。`PROC-ENV` は順番に適用され、`NAME=VALUE` は設定、`NAME` は削除、`NAME=` は空値の設定です。設定はコピーされ、起動前だけ変更できます。上限はプロセス記録64件、引数128件、環境編集128件、終端 NUL を含む設定文字列64 KiBです。Windows の `.bat`・`.cmd` は明示的な `cmd.exe` が必要です。直接起動の API はシェルの引用や特殊文字を解釈しません。

`PROC-IO ( mode which proc -- ior )` の which は stdin=0、stdout=1、stderr=2 です。mode は0がパイプ（3本とも既定）、1が継承、2が null、3が stderr の stdout への統合（stderr 専用）です。3種類の取得語は通常のファイル ID を返し、パイプなし・統合時には0を返します。PROC のストリームは `CLOSE-FILE` で閉じます。stdin を閉じると EOF を渡しますが、子の終了は待ちません。出力が多い場合は、子が動いている間に stdout と stderr の両方を読み進めてください。先に終了を待つと、満杯のパイプで停止することがあります。

`PROC-STATUS` と `PROC-WAIT` は `( state code ior )` を返します。状態は0=設定中、1=実行中、2=終了、3=POSIX のシグナル終了です。待機の時間切れでは状態1のままで、状態は繰り返し取得できます。プロセスの終了とパイプの EOF は独立しており、子孫がパイプを開いたままの場合もあります。Windows は32ビット符号なし終了コードを状態2で保持し、POSIX の状態3は実際のシグナル番号を返します。

`PROC-TERM` は待たずにグループへ終了を要求します。POSIX は SIGTERM、Windows は終了コード143で Job を終了します。`PROC-KILL` は SIGKILL または Windows の終了コード137です。必要なら TERM、任意の猶予で待機、KILL、再度待機の順を明示します。`PROC-FREE` は直接の子が実行中なら EBUSY で拒否し、終了済み記録の解放時には未読・未配送のパイプ内容を破棄します。後始末が失敗すると所有を保持し、再試行できます。Ctrl+C や通常の Forth 例外だけでは子は終了しません。プロセス ID とファイル ID は所有する資源であり、数値のコピーでは所有権は増えません。

単方向の簡単なシェルコマンドには、本体のファイル語 `OPEN-PIPE` と `CLOSE-PIPE` を使えます。files が有効なら EXTENSION の選択は不要です。次のコマンドは Windows と POSIX のどちらのシェルでも使える形です。

```forth
S" echo pipe-ok" R/O OPEN-PIPE THROW CONSTANT SH-PIPE
CREATE SH-BUF 64 ALLOT
SH-BUF 64 SH-PIPE READ-LINE THROW DROP
SH-BUF SWAP TYPE CR
SH-PIPE CLOSE-PIPE THROW . CR
BYE
```

`pipe-ok` と状態 `0` を表示します。`OPEN-PIPE ( addr u fam -- fid ior )` は R/O または W/O を受け付け、R/W は使えません。`BIN` は指定できます。この ID は `CLOSE-PIPE ( fid -- status ior )` で閉じます。シェルの終了を待ち、`$?` は更新しません。CLOSE-FILE と CLOSE-PIPE を取り違えないでください。`BROKEN-PIPE-ERROR` は -544 ですが、Windows CRT は閉じたパイプに EINVAL（-534）を返す場合があります。パイプコマンドは端末状態を共有するので、前面で対話するコマンドには SYSTEM/SH を使います。[プロセス管理](PROCESS_MANAGEMENT_DESIGN.md)と[単方向パイプ](USER_MANUAL.md#one-way-shell-pipes-p06b)も参照してください。

### この章の語

[`PROC-NEW`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a50524f432d4e4557), [`PROC-ARG`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a50524f432d415247), [`PROC-CWD`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a50524f432d435744), [`PROC-ENV`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a50524f432d454e56), [`PROC-IO`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a50524f432d494f), [`PROC-START`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a50524f432d5354415254), [`PROC-STDIN`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a50524f432d535444494e), [`PROC-STDOUT`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a50524f432d5354444f5554), [`PROC-STDERR`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a50524f432d535444455252), [`PROC-STATUS`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a50524f432d535441545553), [`PROC-WAIT`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a50524f432d57414954), [`PROC-TERM`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a50524f432d5445524d), [`PROC-KILL`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a50524f432d4b494c4c), [`PROC-FREE`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a50524f432d46524545)。

別の語群に属する関連語: [`OPEN-PIPE`](WORD_REFERENCE.ja.md#w-464f5254483a4f50454e2d50495045), [`CLOSE-PIPE`](WORD_REFERENCE.ja.md#w-464f5254483a434c4f53452d50495045), [`BROKEN-PIPE-ERROR`](WORD_REFERENCE.ja.md#w-464f5254483a42524f4b454e2d504950452d4552524f52)。

## 5. ファイルシステムのパスと Unicode 文字列

文字列としてパスを整理する操作、既存パスを OS で解決する操作、通常ファイルの情報取得、書込み可能ファイルの同期を使い分けます。それぞれ目的が違います。次の例はパス文字列を編集し、VERSION を変更せずに調べます。

```forth
REQUIRE-EXTENSION ALSO EXTENSION
S" a/../b" COMPACT-FILENAME TYPE CR
CREATE PATH-BUF 8192 ALLOT
S" VERSION" PATH-BUF 8192 FILE>REALPATH THROW 0> . CR
S" VERSION" FILE-METADATA THROW 2DROP 0. D> . CR
PREVIOUS
BYE
```

`b`、`-1`、`-1` を表示します。順に整理したパス、解決後のパスが空でないこと、ファイルサイズが正であることを示します。`COMPACT-FILENAME` は渡されたバイトをその場所で変更し、アドレスを維持します。Windows でも区切りは `/` だけで、末尾の `.` や `..` は保持します。リンクの解決や存在確認はしません。リンクを含むパスでは整理によって意味が変わる場合があるため、OS による解決の代わりに使わないでください。

`FILE>REALPATH ( name u buffer capacity -- needed ior )` は既存パスのリンクをたどり、NUL なしのバイト列をコピーします。容量0なら必要長を調べられます。容量不足では必要長と ERANGE（-546）を返し、出力先は変更しません。他の失敗は0と ior です。入力と出力は重なっても構いません。Windows はバックスラッシュを含む UTF-8 の拡張パス、POSIX は OS のパスのバイト列を返します。入力は4095バイトまでで、チルダ展開や FPATH 探索は行いません。

`FILE-METADATA ( name u -- ud-size mtime-sec mtime-nsec ior )` はリンク先の通常ファイルを調べます。サイズは2セルで、時刻は符号付き Unix UTC 秒と0〜999999999のナノ秒です。実際の精度はファイルシステムに依存します。失敗時は4個の数値がすべて0です。情報取得は、後で読む内容との原子性や、変更をすべて検出することを保証しません。

書込み可能な通常ファイルを OS に同期させる必要があるときは `SYNC-FILE` を使います。次の独立した例は専用ファイルを作り、同期して削除します。

```forth
REQUIRE-EXTENSION ALSO EXTENSION
S" .work/1457/sync.dat" R/W CREATE-FILE THROW CONSTANT SF
S" saved" SF WRITE-FILE THROW
SF SYNC-FILE THROW
SF CLOSE-FILE THROW
S" .work/1457/sync.dat" DELETE-FILE THROW
." sync-ok" CR
PREVIOUS
BYE
```

`sync-ok` と表示します。SYNC-FILE は C のバッファを同期してから、POSIX の fsync または Windows の FlushFileBuffers を要求します。OS エラーでもファイルハンドルを保持し、成功時は論理位置、保留入力、EOF を保ちます。標準ストリーム、パイプ、通常ファイル以外、読取り専用のハンドルは拒否します。同期処理は途中で取り消せず、処理が止まる場合があります。名前変更・親ディレクトリの永続化や任意の電源断への耐性は保証しません。macOS は F_FULLFSYNC ではなく fsync を使います。

### 書記素の境界

文字列の編集には、先頭または末尾の拡張書記素クラスタの UTF-8 バイト長を返す `X-GRAPHEME` と `X-GRAPHEME-LAST` を使えます。返す値は端末の列数ではありません。

```forth
REQUIRE-EXTENSION ALSO EXTENSION
S" abc" 2DUP X-GRAPHEME /STRING TYPE CR
S" abc" X-GRAPHEME-LAST . CR
PREVIOUS
BYE
```

`bc` と `1` を表示します。空の範囲ではどちらも0です。規則は Unicode 18.0.0 / UAX #29 revision 49であり、表示幅の表（15.1.0）とは別です。先頭の検査は最初のクラスタと先読み1文字まで、末尾の検査は範囲全体を確認します。不正な UTF-8 は -24、不正なメモリは -9 を THROW し、引数を保持します。末尾を調べるときは元の先頭アドレスと全体の長さを渡してください。末尾削除の繰り返しは長さの二乗に比例する処理量になることがあります。正規化やロケール別の調整は行いません。[ファイルシステム設計](FILESYSTEM_DESIGN.md)と[書記素設計](GRAPHEME_DESIGN.md)も参照してください。

### この章の語

[`COMPACT-FILENAME`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a434f4d504143542d46494c454e414d45), [`FILE>REALPATH`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a46494c453e5245414c50415448), [`FILE-METADATA`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a46494c452d4d45544144415441), [`SYNC-FILE`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a53594e432d46494c45), [`X-GRAPHEME`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a582d4752415048454d45), [`X-GRAPHEME-LAST`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a582d4752415048454d452d4c415354)。

## 6. 実行の上限と中断

`EXEC-LIMITED` は協調的な処理量の上限を付けて定義を実行します。呼び出した VM での計算を制限する語であり、バックグラウンドタスクや中断位置からの再開ではありません。extension と debug の両方が必要です。

```forth
REQUIRE-EXTENSION ALSO EXTENSION
: SMALL 42 ;
' SMALL 100 EXEC-LIMITED . . CR
: SPIN BEGIN AGAIN ;
' SPIN 100 EXEC-LIMITED -280 = . CR
PREVIOUS
BYE
```

`0 42` と `-1` を表示します。スタック効果は `( i*x xt u -- j*x ior )` です。上限0は、中断を確認しながら無制限に実行する指定です。正常終了では0、この入口の上限に達した場合は -280 を返します。THROW に渡す前に値を比較してください。-280 を THROW すると、通常の回復可能な例外ではなく、従来の致命的な StepLimit として扱われます。

単位は入口の実行、コンパイル済み操作、入口内の解釈トークン、ネイティブ処理の確認点です。ミリ秒や CPU 命令数ではありません。最大16段まで入れ子にでき、外側の有限予算もすべて消費します。外側が尽きると、その所有する入口まで戻ります。CLI のステップ上限、通常の THROW、端末中断（-28）は外へ伝わります。

上限到達時は xt/u を除いた入口のスタックの深さに戻しますが、以前の値やメモリ・ファイル・描画・音の副作用は戻しません。確認点のないネイティブ処理や OS 操作は途中で止められません。計算のためだけに入力モードは変えません。先行する raw 入力は保持しますが、有界の入力キューが満杯になると、その後ろの Ctrl+C を検出できない場合があります。設計上の20 ms目標は応答時間の保証ではありません。[実行制御設計](EXECUTION_CONTROL_DESIGN.md)を参照してください。

### この章の語

[`EXEC-LIMITED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a455845432d4c494d49544544)。

## 7. タスク制御と複合待機

タスクは、許可検査を通った Forth の計算を、独立した新しいワーカー VM で実行します。入口を定義してから、不変の辞書スナップショットを取得します。入口の名前と入力バイト列のコピーを投入し、後で結果をコピーして受け取ります。ここでいう VM は、専用のメモリとスタックを持つ Forth の実行環境です。入力、描画、音、OS 資源はメイン VM が所有します。タスク API はメインスレッドから呼び出します。

### 投入・状態確認・コピー・解放

次の入口は入力をそのまま結果として返します。ワーカーに必要なスタック効果 `( input-addr input-u -- result-addr result-u )` を満たしています。

```forth
REQUIRE-EXTENSION ALSO EXTENSION
: ECHO-BYTES ;
CREATE RESULT-BUF 32 ALLOT
TASK-SNAPSHOT THROW CONSTANT SNAP
SNAP S" ECHO-BYTES" S" task-ok" TASK-I1 0 TASK-SUBMIT THROW CONSTANT JOB
JOB -1 TASK-WAIT THROW DROP TASK-SUCCEEDED = . CR
JOB TASK-STATE THROW 2DROP DROP TASK-SUCCEEDED = . CR
JOB RESULT-BUF 32 TASK-RESULT THROW DROP RESULT-BUF SWAP TYPE CR
JOB 0 RESULT-BUF 32 TASK-DIAGNOSTIC THROW . . CR
JOB TASK-RELEASE THROW
SNAP TASK-SNAPSHOT-RELEASE THROW
PREVIOUS
BYE
```

`-1`、`-1`、`task-ok`、`0 0` を表示します。API の形は次のとおりです。

| 語 | スタック効果 | 用途 |
| --- | --- | --- |
| TASK-SNAPSHOT | `( -- snap ior )` | 入口の定義後に辞書の版を取得します。 |
| TASK-SUBMIT | `( snap name-addr name-u input-addr input-u profile stream -- task ior )` | 入力をコピーして処理を受け入れます。 |
| TASK-STATE | `( task -- state requested result-u diag-u ior )` | 状態と取消し要求を別々に調べます。 |
| TASK-WAIT | `( task ms -- state wait-flags ior )` | 結果を消費せず終端を待ちます。 |
| TASK-RESULT | `( task addr capacity -- needed state ior )` | 保持された成功結果を NUL なしでコピーします。 |
| TASK-DIAGNOSTIC | `( task which addr capacity -- needed code ior )` | UTF-8 の診断を NUL なしでコピーします。 |
| TASK-CANCEL | `( task -- ior )` | 終了を待たずに取消しを要求します。 |
| TASK-RELEASE | `( task -- ior )` | 外部 ID を消費し、未完了なら取消しを要求します。 |
| TASK-SNAPSHOT-RELEASE | `( snap -- ior )` | 別に所有するスナップショット ID を消費します。 |

状態は `TASK-QUEUED`=1、`TASK-RUNNING`=2、`TASK-SUCCEEDED`=3、`TASK-FAILED`=4、`TASK-CANCELLED`=5 です。取消しを要求しただけでは状態5にならず、正常終了が先に成立する場合があります。失敗・取消しのタスクを調べても ior=0 になり得ます。結果が空でも成功なら状態3です。結果と診断は消費せず、解放前なら繰り返しコピーできます。未完了の結果は TASK-E-NOT-READY、容量不足は TASK-E-SHORT と必要長・状態（または必要長・診断コード）を返し、出力先を変更しません。結果は容量0で必要長を調べられます。診断の選択は0=主診断、1=副診断、2=Writer、3=回収です。診断がなければ長さ・コードは0/0で、取消し診断のコードも0の場合があります。診断は1件16 KiB、合計の保存枠は1 MiBです。

タスクとスナップショットの ID は正の不透明なセルで、プロセス内だけで有効、再利用しません。DUP は参照の追加ではありません。一つを解放すると数値のコピーもすべて無効になります。スナップショットを解放しても、受入れ済みタスクはその版を保持して動きます。TASK-RELEASE は終了を待たず、実際の停止も証明しません。解放が受理された後は、ホストエラーが返っても外部 ID が無効な場合があるので、同じ ID で無条件に再試行しないでください。ワーカーからの返却と回収を進めるには、メインループの毎巡でタスク API を呼び続けます。MS、EKEY?、描画ではタスクの回収は進みません。タスク ID がなくても、後述の期限0・時計だけの TASK-WAIT-MANY で回収処理を進められます。

取消しは明示的に要求し、その後で終端状態を待ちます。次の計算は通常復帰しないので、正常終了との競合を避けて取消しを確認できます。

```forth
REQUIRE-EXTENSION ALSO EXTENSION
: WORK-FOREVER BEGIN AGAIN ;
TASK-SNAPSHOT THROW CONSTANT CANCEL-SNAP
CANCEL-SNAP S" WORK-FOREVER" S" x" TASK-I1 0 TASK-SUBMIT THROW CONSTANT CANCEL-JOB
CANCEL-JOB TASK-CANCEL THROW
CANCEL-JOB -1 TASK-WAIT THROW DROP TASK-CANCELLED = . CR
CANCEL-JOB TASK-RELEASE THROW
CANCEL-SNAP TASK-SNAPSHOT-RELEASE THROW
PREVIOUS
BYE
```

`-1` と表示します。UI の処理を続けるアプリでは、この無期限の単一タスク待機の代わりに、ポーリングまたは複合待機を使ってください。

### 上限・スナップショット・ワーカーで使える語

現在の上限はワーカー1、待ちキュー4件、タスク台帳16件、スナップショットは1版4 MiBで最大3版、入出力コピーの共有枠16 MiB、タスク用追加割当128 MiBです。スナップショットは読み込み時に取得して再利用します。後で定義を追加しても古いスナップショットには入りません。FORGET、MARKER、完全復元、辞書の追加読込みは、新規投入に使う構造を無効にするため（TASK-E-STALE）、新しい版を取得します。通常の変数変更では古いスナップショットも使えますが、値は取得時のものです。受入れ済みの処理はその版を保持します。

| プロファイル | 値 | 入力上限 | 結果上限 | キュー滞在期限 |
| --- | --- | --- | --- | --- |
| TASK-G1 | 0 | 128 KiB | 512 KiB | 50 ms |
| TASK-G2 | 1 | 128 KiB | 128 KiB | 100 ms |
| TASK-T1 | 2 | 2 MiB | 64 KiB | 100 ms |
| TASK-I1 | 3 | 128 KiB | 4 KiB | 200 ms |

キューの期限は呼出し側の待機時間切れとは別です。G1/G2 のゲーム処理と T1 の TUI 処理はストリームごとの最新要求を使い、置換の受入れにより古い処理の取消しと古い結果の抑止が起こります。I1 は上限付き FIFO と逆圧を使います。独立した処理の流れごとに、安定した非負のストリーム番号を割り当てます。投入失敗時は既存の処理が保たれます。FULL/LIMIT では短いループで再投入を繰り返さず、空きを待つなどの対応をしてください。[利用条件](TASK_CONTROL_USAGE_CONDITIONS.md)の処理量や応答時間は評価条件であり、フレームレートや停止時間の保証ではありません。

ワーカーに渡すのはコピーしたバイト列であり、メイン VM のアドレス、実行トークン、実行中の資源ではありません。到達する語と最適化された操作も検査します。入口ではファイル・端末・描画・音の操作、コンパイル、SYSTEM、タスクの再投入、動的な EXECUTE/CATCH/THROW、非対応のループ形式を使わないでください。許可された算術・メモリ・スタック・分岐操作を使います。前の例の空のコロン定義は、入力をそのまま返す正しい入口です。入口から呼ぶ補助語も含め、ワードリファレンスの worker 分類を確認してください。スナップショットにメイン用の語が存在しても、ワーカーで使えるとは限りません。入口の引数・結果の規約違反は、未検査のポインターを返さず、診断付きのタスク失敗になります。

### 複数の種類の完了を待つ

`TASK-WAIT-MANY ( targets count events capacity ms -- n wait-flags ior )` にはセル境界にそろえた配列を渡します。対象は `kind id arg0 arg1 tag` の5セル、イベントは `index tag reason detail` の4セルです。TASK-WAIT-TARGET-CELLS と TASK-WAIT-EVENT-CELLS を使って確保します。対象数は1〜64です。capacity の単位はバイトではなくイベント記録数で、対象数以上が必要です。両配列は重ねられません。tag は利用者が識別用に付けるセルです。

次の時計だけのポーリングは、外部タスク ID をすべて解放した後も、メインループの毎巡で回収処理を進めるために使えます。

```forth
REQUIRE-EXTENSION ALSO EXTENSION
CREATE TARGET TASK-WAIT-TARGET-CELLS CELLS ALLOT
CREATE EVENT TASK-WAIT-EVENT-CELLS CELLS ALLOT
TASK-WAIT-CLOCK TARGET !
0 TARGET CELL+ !
0 TARGET 2 CELLS + !
0 TARGET 3 CELLS + !
77 TARGET 4 CELLS + !
TARGET 1 EVENT 1 0 TASK-WAIT-MANY THROW DROP . CR
EVENT CELL+ @ .
EVENT 2 CELLS + @ TASK-EVENT-DEADLINE AND 0<> . CR
PREVIOUS
BYE
```

イベント数1、タグ `77`、期限理由が真である `-1` を表示します。個別の時計の時間が0なら、呼出し全体がポーリングでも準備完了です。

| 種類 | id | arg0 | arg1 | 意味 |
| --- | --- | --- | --- | --- |
| TASK-WAIT-INPUT (1) | 0 | 0 | 0 | 現在のメイン入力です。準備完了では消費しません。 |
| TASK-WAIT-IO (2) | fileid | 1=読取り、2=書込み | 0 | ファイル、PROC・シェルのパイプの準備完了です。 |
| TASK-WAIT-TASK (3) | task | 0 | 0 | 結果を消費せず、終端状態または解放を待ちます。 |
| TASK-WAIT-CLOCK (4) | 0 | 非負の相対 ms | 0 | 呼出し全体とは独立した対象ごとの期限です。 |
| TASK-WAIT-PAINT (5) | 0 | GFX-WINDOW-FRAMES の shown | 0 | 登録したネイティブ窓のフレーム完了です。 |

同じ対象配列に複数の記録を入れると、入力、パイプの準備完了、タスク終端、時計・描画を一度の呼出しで待てます。戻る集合は対象の添字順で、重複対象も含め、準備できた対象ごとに1イベントです。入力を消費せず、パイプ容量を予約せず、タスク結果も取り除きません。戻った全記録を見てから処理を選びます。reason はビットマスクなので、単一の定数との一致ではなくビットを検査します。理由は INPUT=1、READABLE=2、WRITABLE=4、EOF=8、FAILURE=16、CLOSED=32、SUCCEEDED=64、FAILED=128、CANCELLED=256、RELEASED=512、DEADLINE=1024、PAINTED=2048、CAPABILITY-LOST=4096 です（すべて `TASK-EVENT-` を前置します）。入力元の失敗の detail は公開診断コードです。

待機フラグの EXPIRED=1、CANCELLED=2、INTERRUPTED=4、HOST-FAILED=8（`TASK-WAIT-` を前置）は、対象タスクではなく待機側の状態です。準備完了のイベントと全体の時間切れは同時に返ることがあります。時間切れは ior=0 で、対象を取り消しません。ホスト失敗は TASK-E-HOST を返し、安全に取得できたイベントが残る場合があります。実端末の Ctrl+C は、アダプター用の中断フラグだけを立てるのではなく、登録を解除して -28 を THROW します。配列の借用は呼出し中だけで、THROW を含むすべての終了経路で登録を解除します。

描画には、実際に提出したフレームについて GFX-WINDOW-FRAMES が返す1セルの shown を使い、フレーム番号を推測してはいけません。対象はホストのネイティブ窓だけ（id=0）です。不正・古い窓の対象は TASK-E-HANDLE、Tk・窓なし・graphics 除外は TASK-E-NO-CAPABILITY です。登録後に窓を閉じると RELEASED になり、PAINTED はバックエンドの処理完了であって物理画面に映った証明ではありません。本書の例は窓を開きません。

PCM は TASK-WAIT-MANY の対象種別にありません。音を流すアプリでは `PCM-WAIT ( frames ms pcm -- flag ior )` を ms=0 で呼んで入力枠の空きを調べるか、`PCM-QUEUED` を調べます。複合待機に短い時計・全体期限を設け、戻ったら PCM を再確認します。リングの空きや入力リングが空であることは、実際に音が鳴り終わったことではありません。PCM-STOP の drain/discard は独自の契約です。PCM の語には `REQUIRE-AUDIO ALSO AUDIO` が必要です。[グラフィックスとサウンド](GRAPHICS_AND_SOUND.ja.md)を参照してください。PCM ID をファイル ID やタスク ID として渡してはいけません。

設計の背景は[タスク詳細計画](TASK_CONTROL_DETAILED_PLAN.md)と[利用条件](TASK_CONTROL_USAGE_CONDITIONS.md)にあります。古い API 案と現行の登録・HELP が異なる部分は、現行の契約に従ってください。

次の例はタスクと時計を組み合わせます。返る集合を一定にするため先にタスクを終端にし、添字順に2記録を返します。通常のイベントループでは、未完了のタスクを登録し、その時点で準備できた記録を処理します。

```forth
REQUIRE-EXTENSION ALSO EXTENSION
: COPY-INPUT ;
TASK-SNAPSHOT THROW CONSTANT MIX-SNAP
MIX-SNAP S" COPY-INPUT" S" x" TASK-I1 0 TASK-SUBMIT THROW CONSTANT MIX-JOB
MIX-JOB -1 TASK-WAIT THROW 2DROP
CREATE MIX-TARGETS 2 TASK-WAIT-TARGET-CELLS * CELLS ALLOT
CREATE MIX-EVENTS 2 TASK-WAIT-EVENT-CELLS * CELLS ALLOT
MIX-TARGETS 2 TASK-WAIT-TARGET-CELLS * CELLS ERASE
TASK-WAIT-TASK MIX-TARGETS !
MIX-JOB MIX-TARGETS CELL+ !
MIX-TARGETS TASK-WAIT-TARGET-CELLS CELLS + CONSTANT CLOCK-TARGET
TASK-WAIT-CLOCK CLOCK-TARGET !
MIX-TARGETS 2 MIX-EVENTS 2 0 TASK-WAIT-MANY THROW DROP . CR
MIX-EVENTS @ .
MIX-EVENTS TASK-WAIT-EVENT-CELLS CELLS + @ . CR
MIX-JOB TASK-RELEASE THROW
MIX-SNAP TASK-SNAPSHOT-RELEASE THROW
PREVIOUS
BYE
```

`2` と添字 `0 1` を表示します。入力やパイプも加えるときは配列を広げ、前の表の形で INPUT またはパイプのファイル ID を持つ IO の記録を追加します。入力を消費したりパイプを読み書きしたりする前に、それぞれの理由を調べてください。

### この章の語

[`TASK-SNAPSHOT`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d534e415053484f54), [`TASK-SNAPSHOT-RELEASE`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d534e415053484f542d52454c45415345), [`TASK-SUBMIT`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d5355424d4954), [`TASK-STATE`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d5354415445), [`TASK-CANCEL`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d43414e43454c), [`TASK-WAIT`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d57414954), [`TASK-RESULT`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d524553554c54), [`TASK-DIAGNOSTIC`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d444941474e4f53544943), [`TASK-RELEASE`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d52454c45415345), [`TASK-WAIT-MANY`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d574149542d4d414e59), [`TASK-QUEUED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d515545554544), [`TASK-RUNNING`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d52554e4e494e47), [`TASK-SUCCEEDED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d535543434545444544), [`TASK-FAILED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d4641494c4544), [`TASK-CANCELLED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d43414e43454c4c4544), [`TASK-G1`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d4731), [`TASK-G2`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d4732), [`TASK-T1`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d5431), [`TASK-I1`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d4931), [`TASK-WAIT-TARGET-CELLS`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d574149542d5441524745542d43454c4c53), [`TASK-WAIT-EVENT-CELLS`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d574149542d4556454e542d43454c4c53), [`TASK-WAIT-INPUT`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d574149542d494e505554), [`TASK-WAIT-IO`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d574149542d494f), [`TASK-WAIT-TASK`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d574149542d5441534b), [`TASK-WAIT-CLOCK`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d574149542d434c4f434b), [`TASK-WAIT-PAINT`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d574149542d5041494e54), [`TASK-EVENT-INPUT`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d4556454e542d494e505554), [`TASK-EVENT-READABLE`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d4556454e542d5245414441424c45), [`TASK-EVENT-WRITABLE`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d4556454e542d5752495441424c45), [`TASK-EVENT-EOF`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d4556454e542d454f46), [`TASK-EVENT-FAILURE`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d4556454e542d4641494c555245), [`TASK-EVENT-CLOSED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d4556454e542d434c4f534544), [`TASK-EVENT-SUCCEEDED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d4556454e542d535543434545444544), [`TASK-EVENT-FAILED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d4556454e542d4641494c4544), [`TASK-EVENT-CANCELLED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d4556454e542d43414e43454c4c4544), [`TASK-EVENT-RELEASED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d4556454e542d52454c4541534544), [`TASK-EVENT-DEADLINE`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d4556454e542d444541444c494e45), [`TASK-EVENT-PAINTED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d4556454e542d5041494e544544), [`TASK-EVENT-CAPABILITY-LOST`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d4556454e542d4341504142494c4954592d4c4f5354), [`TASK-WAIT-EXPIRED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d574149542d45585049524544), [`TASK-WAIT-CANCELLED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d574149542d43414e43454c4c4544), [`TASK-WAIT-INTERRUPTED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d574149542d494e544552525550544544), [`TASK-WAIT-HOST-FAILED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d574149542d484f53542d4641494c4544)。

別の語群に属する関連語: [`PCM-WAIT`](WORD_REFERENCE.ja.md#w-415544494f3a50434d2d57414954), [`PCM-QUEUED`](WORD_REFERENCE.ja.md#w-415544494f3a50434d2d515545554544), [`PCM-STOP`](WORD_REFERENCE.ja.md#w-415544494f3a50434d2d53544f50), [`GFX-WINDOW-FRAMES`](WORD_REFERENCE.ja.md#w-47524150484943533a4746582d57494e444f572d4652414d4553)。

## 8. 保存アプリの自動起動と実行時資源

完成したコロン定義を `APP-ENTRY!` で登録します。SAVE は登録を保存し、SAVESYS で作る実行ファイルは起動時に入口を一度だけ呼びます。これらは EXTENSION ではなく image の語です。次の例は例用ディレクトリに小さな保存実行ファイルを作ります。

```forth
: MAIN ." application started" CR ;
' MAIN APP-ENTRY!
APP-ENTRY@ NIP . CR
SAVESYS .work/1457/ext-app.exe
APP-ENTRY-OFF
APP-ENTRY@ . . CR
BYE
```

作成側は `-1`、続いて `0 0` を表示します。Windows では `.work/1457/ext-app.exe` を実行してください（POSIX では `./.work/1457/ext-app.exe` です。拡張子は保存時に選んだ名前にすぎません）。`application started` と表示して、REPL に入らず終了します。通常の引数はアプリのデータであり、Forth ファイルやソースではありません。現在の起動引数は既存の ARGC/ARGV/ARG/NEXT-ARG/SHIFT-ARGS で読みます。正常復帰と BYE は共通の後始末を通り、QUIT と未処理エラーは終了状態1になります。

`APP-ENTRY@` は xt/真 または0/偽を返します。`APP-ENTRY-OFF` は以後の保存に使う登録を解除しますが、実行中の入口を止めません。登録できるのは完成した、コンパイル専用でないコロン定義だけです。組込み語や DEFER はコロン定義で包みます。不正な対象は -261、定義途中の登録は -259 を THROW します。再定義しても登録先は移らず、対象を削除すると解除されます。LOAD-DICTIONARY は定義を追加しますが、受け入れ側の登録を維持し、入口を自動実行しません。

保存アプリでは、先頭の `--sigma` だけがホストオプションを有効にします。たとえば `.work/1457/ext-app.exe --sigma --no-app -- -e "APP-ENTRY@ NIP . CR BYE"` は、そのプロセスだけ自動起動を回避し、保存された登録を消さずに真を表示します。最初のアプリ引数として文字列 `--sigma` を渡すには `--sigma -- --sigma` を使います。保存実行ファイルではホストの -m/-l は拒否され、debug 用のオプションには debug 構成が必要です。識別できた埋込み画像の破損は --no-app でもエラーになり、ソース実行へ切り替わりません。

永続化する Forth データを保存し、実行時の資源はアプリの起動時に作り直してください。開いたファイル、パイプ端点、プロセス設定・子、タスク ID・スナップショット、端末要求、PCM ストリーム、描画の保留は、保存して持ち運べる資源ではありません。以前 ID を入れていた整数を保存しても資源は復元しません。新プロセスの端末要求は解除状態から始まります。完全復元は活動中・回収前のタスク処理があると拒否し、暗黙には取り消しません。PCM ストリームが開いている間も完全復元は -528 で拒否します。完全復元と追加読込みの LOAD で後始末が同じだと考えないでください。資源の休止が必要な操作の前には、タスクを終え、タスク API を呼び続けて回収を進め、ストリームの排出・close、プロセスの解放、音の停止を行います。古い画像 ABI はソースから作り直します。画像操作で実行中の外部処理を途中保存することはできません。

[保存アプリ設計](SAVED_APPLICATION_STARTUP_DESIGN.md)と[辞書の保存](USER_MANUAL.md#saving-the-dictionary-and-stand-alone-executables)も参照してください。SAVESYS には書き込める出力先ディレクトリが必要です。実行中の自身、最終要素がシンボリックリンク・reparse point の出力先、通常ファイルでない出力先は拒否します。完成した一時ファイルを置換で公開しますが、電源断への保証ではありません。

### この章の語

新たな EXTENSION 語はありません。

別の語群に属する関連語: [`APP-ENTRY!`](WORD_REFERENCE.ja.md#w-464f5254483a4150502d454e54525921), [`APP-ENTRY@`](WORD_REFERENCE.ja.md#w-464f5254483a4150502d454e54525940), [`APP-ENTRY-OFF`](WORD_REFERENCE.ja.md#w-464f5254483a4150502d454e5452592d4f4646), [`SAVE`](WORD_REFERENCE.ja.md#w-464f5254483a53415645), [`SAVESYS`](WORD_REFERENCE.ja.md#w-464f5254483a53415645535953), [`LOAD-DICTIONARY`](WORD_REFERENCE.ja.md#w-464f5254483a4c4f41442d44494354494f4e415259), [`ARGC`](WORD_REFERENCE.ja.md#w-464f5254483a41524743), [`ARGV`](WORD_REFERENCE.ja.md#w-464f5254483a41524756), [`ARG`](WORD_REFERENCE.ja.md#w-464f5254483a415247), [`NEXT-ARG`](WORD_REFERENCE.ja.md#w-464f5254483a4e4558542d415247), [`SHIFT-ARGS`](WORD_REFERENCE.ja.md#w-464f5254483a53484946542d41524753)。

## 9. OS ごとの違いと困ったとき

まず、API の失敗、対象の失敗、時間切れを区別します。その語の契約で解放済みになるまでは所有を保持します。次の例は意図的に不正なタスク ID を調べ、戻った ior を THROW せずに判定します。

```forth
REQUIRE-EXTENSION ALSO EXTENSION
0 TASK-STATE TASK-E-HANDLE = . 2DROP 2DROP CR
PREVIOUS
BYE
```

`-1` と表示します。負の値をすべて同じ意味で扱わないでください。よくあるエラーは次のとおりです。

| ior | 意味と対応 |
| --- | --- |
| -9 | 不正なアドレス・範囲です。バイト容量とセル配列の確保量を確認します。直接 THROW する場合があります。 |
| -13 | 未知の語です。読み込み、検索順、ビルドでの機能除外を確認します。 |
| -21 | ホスト機能がありません。無限に再試行せず、files・debug・ホストの対応を確認します。 |
| -24 | 不正な数値・符号化です。マスク、件数、対象の各項目、UTF-8 を確認します。 |
| -28 | 対応範囲内で端末中断が起きました。資源の後始末はアプリで行います。 |
| -257 | 内部の一時領域を確保できません。保持する処理やデータを減らします。 |
| -265 | ホスト操作が失敗しました。契約上必要な資源を保持し、失敗を知らせます。 |
| -280 | EXEC-LIMITED 自身の予算切れです。THROW の前に判定します。 |
| -514 | ENOENT です。パス・実行ファイルが見つかりません。 |
| -521 | EBADF です。不正または閉じたファイル・資源 ID です。 |
| -525 | EACCES です。アクセス拒否や読取り専用への操作です。 |
| -528 | EBUSY です。資源が活動中です（実行中の子への PROC-FREE など）。 |
| -534 | EINVAL です。不正な引数、非対応のファイル・パイプの種類などです。 |
| -546 | ERANGE です。FILE>REALPATH の出力先が足りません。必要長を確保して再試行します。 |
| -544 | EPIPE です。書込みを止めて子を調べます。Windows では -534 の場合もあります。 |
| -516 | 従来のファイル・close 経路の EINTR です。Windows の close 中断は再試行用に ID を保持します。 |

タスク専用のエラーには名前付き定数があります。定数は値であり、自動的には THROW しません。

| 定数 | 値 | 意味と対応 |
| --- | --- | --- |
| TASK-E-HANDLE | -300 | 不正・古い・所有者違い・種類違いの ID です。解放済みのコピーを再利用しません。 |
| TASK-E-FULL | -301 | 容量不足・逆圧です。完了を処理し、保持中の記録を解放します。 |
| TASK-E-STALE | -302 | 新規投入に使うスナップショットの構造が無効です。取得し直します。 |
| TASK-E-ENTRY | -303 | 保存した辞書・検索順に入口名がありません。 |
| TASK-E-DENIED | -304 | ワーカー操作や依存が禁止されています。入口を見直します。 |
| TASK-E-LIMIT | -305 | バイト・VM 予算を超えています。入力・結果・保持する処理を減らします。 |
| TASK-E-NOT-READY | -306 | 結果・診断がまだありません。待機または再度ポーリングします。 |
| TASK-E-SHORT | -307 | 出力先が足りません。部分コピーは行われないので、必要長を確保して再試行します。 |
| TASK-E-ABI | -308 | ワーカーの結果スタック・長さ・範囲が不正です。入口の規約を直します。 |
| TASK-E-BUSY | -309 | 定義が未完了の間にスナップショットを取得しました。先に定義を終えます。 |
| TASK-E-EXHAUSTED | -310 | ID・世代・参照数の空間を使い切りました。巻戻しや再利用はしません。 |
| TASK-E-NO-CAPABILITY | -311 | 指定した入力・I/O・描画の機能がありません。対応する対象を選びます。 |
| TASK-E-HOST | -312 | ホストの待機・時計・後始末が失敗しました。保持されたイベントと診断を調べます。 |
| TASK-E-QUEUE-EXPIRED | -313 | キュー内の期限でタスクが失敗しました。呼出し側の待機時間切れとは別です。 |
| TASK-E-STOP-UNCONFIRMED | -314 | 実際の停止を確認できていません。資源を保持して回収処理を続けます。 |

Windows でシェル構文を使うときは、シェルを明示します（例は Windows PowerShell です）。POSIX のシグナルやパスをそのまま使えるとは限りません。Windows の TERM は Job の終了であり、POSIX の穏当な SIGTERM とは異なります。POSIX はプロセスグループを使いますが、子孫が離脱することもあり、どちらもサンドボックスではありません。ファイル時刻の精度や解決後のパス表記はホストに依存します。端末制御は実際の端末に依存しますが、ファイルからのイベント入力は端末のエスケープ報告とは独立しています。

ループが応答しないときは、待ち続ける read・flush、パイプを読む前の子の終了待ち、負数の無期限待機、解放していないタスク記録、RELEASE 後のタスク API 呼出し不足を確認してください。準備完了を調べても、後続操作の時点まで状態を予約できません。バッファや描画の準備完了から、実際の音の終了や物理画面への提示を判断してはいけません。設計の応答目標は OS のスケジューリング保証ではありません。

### 網羅範囲と確認の根拠

各章の一覧は EXTENSION の全97語を扱います。`src/core/words_extension.zig` の `definitions` 配列から90語、`src/extension/extension.fs` の CONSTANT 定義から7語を抽出しました。全名を WORD_REFERENCE の EXTENSION 節と照合し、各語をいずれか一つの章末一覧に割り当てています。TASK-E-* はこの章、他のタスク定数は第7章です。読み込み、本体のパイプ、画像保存、音・描画の補助語は別に関連語としてリンクし、97語には含めません。

動作はソースの登録と [HELP](../src/core/help_text.zig)、[ワードリファレンス](WORD_REFERENCE.ja.md)、[利用者マニュアル](USER_MANUAL.ja.md)の該当節、[互換性の記録](COMPATIBILITY.ja.md)に従います。[本体拡張の詳細設計](CORE_EXTENSION_DETAILED_DESIGN.md)、[タスク計画](TASK_CONTROL_DETAILED_PLAN.md)、[利用条件](TASK_CONTROL_USAGE_CONDITIONS.md)、各章の最終設計で背景を確認しています。旧案だけに存在する API は利用可能な語として書いていません。特に TASK-WAIT-MANY の PCM 種別、中断タスクの継続再開、実行中の OS 資源の保存保証はありません。

すべての Forth ブロックを Windows の実行ファイルに個別のファイルとして渡して動かしました。保存実行ファイルの別プロセス起動と --no-app も確認しました。POSIX の引数列は設定としてだけ検査しました。この手引きの確認では POSIX の子、実際のキー・マウス・貼り付け操作、描画窓、音声装置、強制中断、OS 間の復元は試していません。例はそれらを必要としない範囲に絞っています。

### この章の語

[`TASK-E-HANDLE`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d452d48414e444c45), [`TASK-E-FULL`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d452d46554c4c), [`TASK-E-STALE`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d452d5354414c45), [`TASK-E-ENTRY`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d452d454e545259), [`TASK-E-DENIED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d452d44454e494544), [`TASK-E-LIMIT`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d452d4c494d4954), [`TASK-E-NOT-READY`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d452d4e4f542d5245414459), [`TASK-E-SHORT`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d452d53484f5254), [`TASK-E-ABI`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d452d414249), [`TASK-E-BUSY`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d452d42555359), [`TASK-E-EXHAUSTED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d452d455848415553544544), [`TASK-E-NO-CAPABILITY`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d452d4e4f2d4341504142494c495459), [`TASK-E-HOST`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d452d484f5354), [`TASK-E-QUEUE-EXPIRED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d452d51554555452d45585049524544), [`TASK-E-STOP-UNCONFIRMED`](WORD_REFERENCE.ja.md#w-455854454e53494f4e3a5441534b2d452d53544f502d554e434f4e4649524d4544)。

# FORTH/Σワード互換性一覧

英語版（正）: [COMPATIBILITY.md](COMPATIBILITY.md)。この日本語版は英語版の訳です。内容が異なる場合は英語版に従ってください。

この一覧は[FORTH/Σ仕様書](SPEC.ja.md)と現在のZig実装を対応づけたものです。誌面に同名ワードがあることだけでは、すべての機種版で同じ仕様とは限らないため、出典は誌面の掲載内容で確認しています。2026-10-28以降、数値まわりと基本ワードはGforthに合わせています（[決定事項](DECISIONS.md)）。

## 凡例

- **実装**: 現在のZigコアに実装されています。
- **変更**: 誌面に掲載がありますが、Gforthに合わせて動作を変えています。
- **拡張**: ポータブル化のために追加した機能、または資料と動作が異なる実装判断です。
- **未実装**: 誌面に掲載がありますが、現在のコアにはありません。
- **機種依存**: CP/M、PC-8001、Z80の機械語やモニターに依存し、共通コアの対象外です。

## 共通言語コア（誌面掲載ワード）

| 分類 | 誌面掲載ワード | 現状 | 出典・補足 |
| --- | --- | --- | --- |
| スタック | DROP, DUP, SWAP, OVER, ROT, >R, R> | 実装 | 誌面参照。セルは64ビット。 |
| 算術 | +, -, *, /, MOD, /MOD, 1-, MINUS, ABS, MAX, MIN | 変更 | 64ビット。/、MOD、/MODは床関数除算、ゼロ除算はエラー。1-はサンプルとワード表の記載が一致しません。 |
| 比較・論理 | =, <>, <, >, <=, >=, 0=, NOT, AND, OR, XOR, COM, NAND, NOR | 変更 | 真は-1。NORの定義は資料内で記述が食い違います。 |
| バイト操作 | SWAB | 変更 | セル全体（8バイト）のバイト順を反転。 |
| メモリ | @, !, C@, C!, +!, 1+!, 1-!, OSET, ? | 変更 | セルは8バイト。?は末尾に空白。範囲外アドレスはエラー。 |
| 配列 | ARRAY, A@, A! | 変更 | 1要素8バイト。境界検査はありません。 |
| 辞書・データ領域 | :, ;, HERE, ALLOT, ,, C,, FORGET | 変更 | 名前は全文字で識別します（誌面は長さと先頭5文字）。 |
| 定義用語 | <BUILDS, DOES> | 実装 | 実行時に作成名を入力ストリームから読み、DOES>以後の操作列を作成語に結び付けます。 |
| 変数・定数 | VARIABLE/VAR, CONSTANT/CONST | 実装 | 誌面の版によりVAR/CONST等の表記差があります。 |
| 条件分岐 | IF, ELSE, THEN | 実装 | 誌面参照。 |
| 条件・後判定ループ | BEGIN, WHILE, REPEAT, END | 実装 | 誌面参照。 |
| カウント付きループ | DO, LOOP, +LOOP, LEAVE, I | 変更 | LEAVEは即座にループを抜けます（誌面は次のLOOPで終了）。DOの最低1回実行は維持。負の+LOOPの終端判定は資料から確定できません。 |
| 基数 | BASE, HEX, DEC, OCT | 実装 | 資料で確認できる基数は8、10、16です。 |
| 出力 | ., C., ECHO, CR, SPACE, SPCES, TYPE | 変更 | .とC.は末尾に空白、ゼロ埋めなし。TYPEは ( addr u )。 |
| 数値入力 | INPUT | 実装 | 端末から整数1個を読み取ります。 |
| 文字列 | " | 変更 | コンパイル専用、最大127バイト。アドレス、文字数の順に積みます（誌面は文字数、アドレス）。 |

## Gforthに合わせて追加したワード

`zig build -Dfloat=false` でビルドした版には、この節の浮動小数点の語（浮動小数点の行の語と、`FFIELD:` などのフィールド、`FLOAT%` などの大きさ、`FVALUE`、`FLITERAL`）と、共通言語コアの浮動小数点の語がありません（[決定事項](DECISIONS.md)の「浮動小数点を除いた版」）。

| 分類 | ワード | 備考 |
| --- | --- | --- |
| スタック | -ROT, NIP, TUCK, PICK, ROLL, 2DUP, 2DROP, 2SWAP, 2OVER, DEPTH, R@, .S | |
| 算術・比較 | NEGATE, 1+, 2*, 2/, 0<, 0>, 0<>, TRUE, FALSE | |
| ビット | INVERT, LSHIFT, RSHIFT | |
| メモリ | CELL, CELLS, CELL+, ALIGNED, BL, ON, OFF, ERASE, FILL, MOVE, CMOVE | |
| 出力 | U., EMIT, SPACES, DECIMAL | |
| 定義 | CREATE, VALUE, TO, IMMEDIATE, POSTPONE, RECURSE, CHAR, [CHAR], ['] | |
| 制御構造 | UNTIL, AGAIN, CASE, OF, ENDOF, ENDCASE, EXIT, UNLOOP | |
| コメント | \ | |
| 浮動小数点スタック | FDROP, FDUP, FSWAP, FOVER, FROT, F-ROT, FNIP, FTUCK, FPICK, FDEPTH, F.S | 教材Level 17 |
| 浮動小数点演算 | F+, F-, F*, F/, FNEGATE, FABS, FMAX, FMIN, FSQRT, FEXP, FLN, FSIN, FCOS, FTAN | 教材Level 17 |
| 浮動小数点比較 | F=, F<>, F<, F>, F<=, F>=, F0=, F0<>, F0<, F0>, F0<=, F0>= | 結果は整数スタック |
| 浮動小数点メモリ・変換 | F@, F!, F,, FLOATS, FLOAT+, FVARIABLE, FCONSTANT, S>F, F>S, F. | 教材Level 17 |
| 文字列・入力 | S", S\", .\", .(, COUNT, PAD, ACCEPT, EVALUATE, KEY, KEY?, >NUMBER, S>NUMBER?, >FLOAT | 段階3。教材Level 6、9、14、29 |
| 倍長整数 | 倍長整数リテラル（`123.`）, S>D, D>S, D+, D-, DNEGATE, DABS, D0=, D0<, D=, D<, D., 2@, 2!, 2VARIABLE, 2CONSTANT, D>F, F>D | 段階3。教材Level 18、20 |
| 数値の書式 | <#, <<#, #, #S, HOLD, HOLDS, SIGN, #>, #>> | 段階3。教材Level 20 |
| 小規模追加（グループA） | WITHIN, 2>R, 2R>, ENDIF, PLACE, ABORT, STATE, :NONAME, MS, UTIME, PAGE, GETENV, SYSTEM | 教材Level 2、5、6、9、10、14、15、25、30〜32。MS、UTIME、GETENV、SYSTEMはホスト機能を使います。 |
| コマンドライン（2026-11-08） | ARGC, ARGV, ARG, SHIFT-ARGS, NEXT-ARG。引数のファイルと `-e` | WSLのGforth 0.7.9_20260410で確かめ、値も、引数を取り除く順（引数と、`-e` とその文字列は、処理する前に取り除く）も同じです。引数0は起動したときのプログラム名です。引数は256個、合わせて約10 KBまでです。エラーはGforthの形式ではなく、この移植版の形式で表示します。 |
| 文字（UTF-8、2026-11-08） | XC-SIZE, X-SIZE, XC@+, XC@, XC!+, XC!+?, XC,, XCHAR+, XCHAR-, XEMIT, XKEY, XKEY?, X-WIDTH, XC-WIDTH, +X/STRING, X\STRING-, -TRAILING-GARBAGE, XHOLD, EKEY>XCHAR, X@+/STRING。CHAR、[CHAR]、`'c'` はコードポイントを返す | WSLのGforth 0.7.9_20260410で確かめ、正しいUTF-8、冗長な形、サロゲートで同じ結果になり、XC-WIDTHはすべてのコードポイントで同じです（Gforthはglibc 2.39の値を使い、この移植版の表はUnicode Character Database 15.1.0から作ります）。壊れたUTF-8は、Gforthでは語によって結果が違うため、この移植版の規則（U+FFFD）に従います。U+10FFFFを超える値はU+FFFDとして書きます（Gforthはもっと長い形で書きます）。Windowsのコンソールは、Sigmaの実行中UTF-8になります（`SYSTEM` で起動したプログラムは元のコードページで動きます）。ファイル名と `SYSTEM` のコマンドも、WindowsでUTF-8です。 |
| 基本語・倍長の乗除算・READ-FILE（2026-10-30） | ?DUP, U<, U>, ALIGN, UNUSED, .R, U.R, 2R@, */, */MOD, M*, UM*, UM/MOD, FM/MOD, SM/REM, READ-FILE | Forth 2012のCORE・CORE EXTの語と、ファイルの語。結果はGforthと同じです。`*/` などの除算は、0で割ると `DIVISION BY ZERO !`（-10）、商が1セルに収まらないと `RESULT OUT OF RANGE !`（-11）になります（Gforthと同じ）。`/` `MOD` `/MOD` も、最小値を-1で割ると-11になります（Gforthと同じ、2026-10-30から）。`READ-FILE` は `STDIN` からも読めます。Windowsでも、パイプやリダイレクトの標準入力はバイナリで読むので、CR LFや0x1Aもそのまま読めます（コンソールはテキストのままです）。 |
| REPRESENT, M*/（2026-10-30） | REPRESENT, M*/ | 結果はGforthと同じです。`REPRESENT` は数字を2進数の値から正確に丸め、0の指数は1、無限大とNaNは名前を切って書きます。`M*/` は途中を256ビットで計算し、Gforthと同じく除数を符号なしとして扱い、商が2セルに収まらないと折り返します（エラーにしません）。 |
| WHERE（2026-10-30） | WHERE | 出力はGforthと同じです（ファイルの位置、行頭の空白を除いた行、80桁、通し番号。全角文字は2桁、タブは8桁ごと）。Gforthと同じく、`'` `[DEFINED]` `FIND-NAME` などで名前を探した箇所も、直前に読んだ語の位置で記録します。違い: 記録するのはファイルから読んだ使用だけで、組み込み語の定義の中の使用はありません（Gforthの `WHERE DUP` はGforth自身のソースの使用も表示します）。記録は65536件までです。辞書イメージには入らず、`LOAD` やイメージの復元の後は空になります。行の幅は端末の幅によらず80桁です。位置の部分だけで80桁を超える行は、Gforthと同じく行の内容を切らずに全部表示します。 |
| 遅延語・コンパイル・構造体・小さなGforthの語（2026-10-30） | DEFER, IS, ACTION-OF, DEFER!, DEFER@, DEFERS, COMPILE,, [COMPILE], NAME>COMPILE, BEGIN-STRUCTURE, END-STRUCTURE, +FIELD, FIELD:, CFIELD:, FFIELD:, SFFIELD:, DFFIELD:, STRUCT, FIELD, END-STRUCT, CELL%, CHAR%, FLOAT%, DOUBLE%, SFLOAT%, DFLOAT%, %SIZE, %ALIGNMENT, %ALIGN, %ALLOT, %ALLOC, %ALLOCATE, +TO, ?EXIT, NOOP, PERFORM, ?LEAVE, CELL-, UNDER+, 0>=, ?OF, CONTOF, NEXT-CASE | 利用者の決定で、教材で使わない一般のGforthの語も加えた。結果はWindows版・Linux版ともGforthと同じです。違い: 動作を決めていないDEFERは警告を出して何もしないのはGforthと同じですが、`DEFER@` は-1を返します。定義の外の `COMPILE,` はエラーです（Gforthは警告を出してコンパイルします）。`SEE` の表示（DEFER、フィールド、`END-STRUCT` の名前）はGforthと違います。自分自身を実行するDEFERは `RETURN STACK OVER FLOW !` です（Gforthは止まりません）。動作を決めていないDEFERの `DEFERS` はエラーです（Gforthは警告を出す語を埋め込みます）。`[COMPILE]` にローカル変数を渡すとエラーです（Gforthも正しく扱いません）。`FORGET` や `MARKER` で消した語を実行するDEFERは、動作を決めていない状態に戻します（番号が新しい語に使われるため）。`+TO` はローカル変数にも使えます（Gforthと同じ）。`IS` `ACTION-OF` `+TO` は `TO` と同じく構文語で、語彙に属しません。`LOAD` では、DEFERの動作が読み込んだ語なら、その語の新しい番号に付け替えます。 |
| 残りの動的文字列の語（2026-10-30） | $SLURP、$+SLURP、$+SLURP-FILE、$SLURP-LINE、$+!LEN、$[]+!、$+[]!、$EXEC、$OFF、$VARIABLE、$[]VARIABLE、$? | Linux版の結果はGforthと同じです。`$VARIABLE` `$[]VARIABLE` は `VARIABLE` の別名で、`SEE` もGforthと同じく変数として表示します。`$?` はGforthでは値（VALUE）ですが、Sigmaでは値を返す語で、`TO` は使えません。Windowsの `$?` は終了コードです（Linux・macOSは `system` の返す値で、Gforthと同じ）。 |
| 解釈中の繰り返しと条件付きコンパイル（2026-10-30） | [IFDEF], [IFUNDEF], [ENDIF], [DO], [?DO], [LOOP], [+LOOP], [I], [BEGIN], [UNTIL], [AGAIN], [WHILE], [REPEAT], [FOR], [NEXT] | 結果はGforthと同じです。繰り返しは入力の位置（`SAVE-INPUT` と同じ情報）を覚えて戻るので、ファイルでは行をまたいで使え、`[ ]` の中でも使えます。端末と `EVALUATE` では同じ行の中だけで繰り返します。対応する開始語がないと `CONTROL STRUCTURE ERROR !` です。`CATCH` で捕捉したときは、捕捉した語の中で始めた繰り返しも終わります。 |
| 残りのファイルの語（2026-10-30） | FILE-POSITION, RESIZE-FILE, FLUSH-FILE, DELETE-FILE, RENAME-FILE, FILE-STATUS, BIN, INCLUDE-FILE | 結果（iorと値）はGforthと同じです。`BIN` は動きを変えません（ファイルはいつもバイトのまま扱います）。`RENAME-FILE` は、Windowsでも、変更先の名前のファイルを置き換えます（Gforthと同じ）。Windowsでは置き換えを一度の操作（`MoveFileEx`）で行うので、失敗しても変更先のファイルは残ります。`FILE-STATUS` の値は開ける方法（`R/O` `W/O` `R/W`）です。`INCLUDE-FILE` で読むファイルは、名前を `*file*` として記録します。 |
| 個別に設計の語の残り（#201、2026-10-30） | SYNONYM, TRAVERSE-WORDLIST, NAME>INTERPRET, CS-PICK, CS-ROLL, EKEY, EKEY?, EKEY>CHAR, ENVIRONMENT?, QUIT | 結果はGforthと同じです。`EKEY` は `KEY` と同じで、ファンクションキーなどの特殊なキーは解釈しません。`ENVIRONMENT?` はこの処理系の大きさを返し（`/HOLD` 4096、`STACK-CELLS` 既定で4096 など、Gforthとは値が違います）、語群の名前（`CORE` など）には偽を返します。`QUIT` はデータスタックを残し、`CATCH` で捕まえません。`WHILE` は標準と同じく、分岐をBEGINの下に置くようにしたので、`CS-ROLL` を使う書き方や、`BEGIN ... WHILE ... WHILE ... REPEAT THEN` が使えます。 |
| 個別に設計の語のうち小さなもの（#201、2026-10-30） | AHEAD, N>R, NR>, AT-XY, TIME&DATE | 結果はGforthと同じです。`AT-XY` はGforthと同じエスケープシーケンス（`ESC[行;列H`）を出力します。`TIME&DATE` はホストのCライブラリの地方時です。 |
| 入力処理（#197、2026-10-30） | SOURCE, >IN, SOURCE-ID, REFILL, SAVE-INPUT, RESTORE-INPUT | `>IN` は論理メモリのセルで、`PARSE` `WORD` などはこのセルの位置から読みます。端末・ファイル・`EVALUATE` での結果はGforthと同じです。負の `>IN` はGforthと同じく-18（`STRING TOO LONG !`）にします。`SAVE-INPUT` は入力元、`>IN`、行（端末と `EVALUATE` では行のアドレス、ファイルでは行の先頭の位置）、行の番号（ファイルでは行番号、端末と `EVALUATE` では行ごとの通し番号）の4個を返します（値の中身はGforthと違います）。`RESTORE-INPUT` はファイルでは保存した行を読み直し、端末と `EVALUATE` では同じ行の中でだけ戻り、入力元が違えば失敗（真）を返します。 |
| 次点の語（#198、2026-10-30） | C", ABORT", BUFFER:, 2LITERAL, 2VALUE, D.R, D2*, D2/, DMAX, DMIN, M+, DU<, 2ROT, DUMP | 出力はGforthと同じです。`C"` と `ABORT"` はGforthと同じく定義の中だけで使えます（定義の外では `COMPILE MODE ERROR !`）。`ABORT"` は `CATCH` がなければ文字列だけを表示します。`DUMP` の書式はGforthと同じで、表示するアドレスは論理メモリのアドレスです。 |
| 文字列の操作・比較・検索 | COMPARE, SEARCH, /STRING, -TRAILING, CHAR+, CHARS, BOUNDS, BLANK, CMOVE>, SLITERAL, PARSE-NAME, SCAN, SKIP, STR=, STRING-PREFIX?, +PLACE, SLURP-FILE, $SLURP-FILE | Forth 2012のSTRING語と基本語、Gforthの文字列語。`+PLACE` はGforthでは古い語とされています。負の長さは、Sigmaのほかの文字列語と同じく空の文字列として扱います（Gforthの `BLANK` `SCAN` などはメモリの誤りになります）。メモリの終わりを越える長さは `INVALID MEMORY ADDRESS !` になります。`SLITERAL` の文字列は `S"` と同じく255バイトまでです。境界の値（空の文字列、負の長さ、範囲を超える/STRING、タブを含む末尾）もGforthと同じ結果です。 |
| 例外・ファイル（段階5a、CATCH） | THROW, CATCH, R/O, W/O, R/W, STDIN, STDOUT, STDERR, OPEN-FILE, CREATE-FILE, CLOSE-FILE, READ-LINE, WRITE-LINE, WRITE-FILE, FILE-SIZE, REPOSITION-FILE | 教材Level 14、19、23、25、29。CATCHで捕捉しなかった0以外のTHROWはエラーとして報告します。 |
| 動的メモリ・動的文字列（段階5b） | ALLOCATE, FREE, RESIZE, $!, $@, $@LEN, $!LEN, $+!, C$+!, $., $DEL, $INS, $OVER, $FREE, $INIT, $SPLIT, $ITER, $TMP, $[], $[]!, $[]@, $[]#, $[]., $[]MAP, $[]FREE, $[]SLURP, $[]SLURP-FILE, $SLURP, $+SLURP, $+SLURP-FILE, $SLURP-LINE, $+!LEN, $[]+!, $+[]!, $EXEC, $OFF, $VARIABLE, $[]VARIABLE, $? | 教材Level 14、29、30、32。ヒープは論理メモリのデータ領域の後ろにあり、`-m` の大きさと同じ（既定で32 MiB）。 |
| 辞書探索・解析（#153） | WORD, FIND, PARSE, FIND-NAME, NAME>INT, NAME>STRING, SEE | 教材Level 10、31。`SEE` はコンパイル済みの命令列から定義を再構成します。`FIND` は構文語（`TO` `[']` など）を見つけません。 |
| 浮動小数点の関数・丸め・表示・メモリ（#200、2026-10-30） | FSINCOS, FASIN, FACOS, FATAN, FATAN2, FSINH, FCOSH, FTANH, FASINH, FACOSH, FATANH, FEXPM1, FLNP1, FLOG, FALOG, F**, FLOOR, FTRUNC, FROUND, F~, FE., FS., PRECISION, SET-PRECISION, FVALUE, SF@, SF!, DF@, DF!, SFLOATS, DFLOATS, SFLOAT+, DFLOAT+, FALIGN, FALIGNED, SFALIGN, SFALIGNED, DFALIGN, DFALIGNED | 数学関数はCORE-MATHの正しく丸める関数で、どのOSでも同じ値です（利用者の決定、方針A）。Gforth（glibc）とは30,349件のうち29,017件（95.6%）でビットまで一致し、残りの1 ulpの違いはglibcが正しく丸めていないためです（例: `0.5e FATANH` はln(3)/2を正しく丸めた値で、Gforthより1 ulp大きい）。範囲外の引数のNaNの符号はGforthと同じです。それ以外の語の出力はGforthと同じです。`PRECISION` が1のときの `FE.` と、0以下の `PRECISION` では、Gforthは異常終了しますが、Sigmaは表示します（1〜1000桁）。 |
| 浮動小数点の書式（#156） | F.RDP, F>STR-RDP, F>BUF-RDP | 教材Level 20、25、29。Gforthで確かめた118例すべてと同じ出力です。 |
| 説明・ライセンス | HELP, LICENSE | Gforthの `help` `license` に相当します。`HELP 語名` の説明はこの移植版のために書いたもので、Gforthのマニュアルの文章ではありません。起動時の表示（Gforthと同じく、コマンドラインの引数を処理した後、対話プロンプトの前に表示）は2行で、版番号とライセンスを示します。 |
| リテラルのコンパイル（#181） | LITERAL, FLITERAL | 教材Level 31。科学計算DSL（完成版）はGforthと同じ出力になります。COMPILE,、DEFER、IS、ACTION-OFも使えます（2026-10-30に追加）。 |
| 実行トークンのデータ領域（#177） | >BODY | 教材Level 31。`'` は語の番号を返すので、`'` の値をアドレスとして使う教材Level 12の `' DATA +` とLevel 21の `' pointA @` は動きません（Gforthでは動きます）。標準のForthでも、実行トークンをアドレスとして使うことは保証されていません（3.1.1）。語の番号は `BASE`（200H）などの処理系の変数の番地と重なるため、`' DATA +` への書き込みは `BASE` を壊し、`BASE ERROR !` になります（語の番号は組み込み語が増えると上がるので、届く番地も変わります）。`' DATA >BODY +` と書き直せば、結果はGforthと同じです（Level 12は `10 20 30 40 50 30`）。CONSTANT・FCONSTANT・コロン定義・組み込み語の `>BODY` はエラーです。 |
| 定義語・定数（#158） | 定義の中の :, ;, VARIABLE, VAR, FVARIABLE, 2VARIABLE, CONSTANT, CONST, FCONSTANT, 2CONSTANT, VALUE, ARRAY, FARRAY、PI | 教材Level 20、25、31。定義の中に書いた定義語は、その定義の実行時に名前を読みます。解釈中の `[` はエラーにしません。 |
| 語彙・条件付きコンパイル（段階6） | ONLY, ALSO, PREVIOUS, FORTH, DEFINITIONS, ORDER, GET-ORDER, SET-ORDER, >ORDER, GET-CURRENT, SET-CURRENT, VOCABULARY, WORDLIST, FORTH-WORDLIST, SEARCH-WORDLIST, [IF], [ELSE], [THEN], [DEFINED], [UNDEFINED] | 教材Level 16、30。検索順序の初期値と `ORDER` の表示はGforthと同じです。`:` `TO` などの構文語は語彙に属さず、検索順序によらず使えます。 |
| ソース読み込み（#154）・MARKER | INCLUDE, INCLUDED, REQUIRE, REQUIRED, NEEDS, INCLUDED?, SOURCEFILENAME, SOURCELINE#, LOCATE, WHERE, MARKER | 教材Level 2、10、14、16、19、30。ファイル名はカレントディレクトリからの相対パスです。 |
| ローカル変数（段階4） | { ... }, {: ... :}, LOCALS\|, 型指定 W: W^ D: D^ F: F^ C: C^ XT: XT^, TO | 教材Level 14〜16、25〜27、29、32。`{` と `LOCALS\|` は構文語で、`WORDS` には表示しません。 |

## 追加機能・移植上の違い

| 機能 | 状態 | 現在の動作 |
| --- | --- | --- |
| タブ区切り | 拡張 | タブも空白と同じくトークンの区切りです（誌面は空白とCRのみ）。Gforthと同じです。 |
| 大文字・小文字を区別しない名前照合 | 拡張 | ASCII英字の大小を同一視します。Gforthと同じです。 |
| 数値基数2〜36と接頭辞 | 拡張 | BASEのメモリ値で2〜36を使えます。`$` `#` `&` `%` 接頭辞、`0x`（Gforthと同じく基数で読めないとき）、`'c'` と `'c`（`-'c` とUTF-8の文字も）を認識し、WSLのGforth 0.7.9_20260410と同じ結果になります。 |
| 浮動小数点リテラル | 拡張 | 基数10で `e`/`E` を含むトークン。 |
| 無限大・NaNの表示 | 拡張 | `F.` `FE.` `FS.` は `infinity` `-infinity` `NaN` を `PRECISION` で切らずに表示します。Gforthは `PRECISION` の文字数で切ります（`6 SET-PRECISION` で `infini`、`2 SET-PRECISION` で `Na`）。既定の `PRECISION`（15）では同じです。 |
| F+!, F?, FA@, FA!, FARRAY, FINPUT, FMINUS | 拡張 | FORTH/Σの +!、?、A@、A!、ARRAY、INPUT、MINUS に対応する浮動小数点版。Gforthのワードではありません。 |
| ."文字列出力 | 拡張 | コンパイル時文字列出力です。1982年資料のワードではありません。 |
| ?DO | 拡張 | 開始値と終値が同じ場合、ループ本体を実行しません。FORTH/ΣのDOは同値でも1回実行します。 |
| J, K | 拡張 | 2段目・3段目のループ添字を取得します。誌面では利用者定義例として説明されています。 |
| EXECUTE | 拡張 | ポータブルな辞書トークンを実行します。Z80コードアドレス互換ではありません。 |
| 単一の論理メモリと上限 | 拡張 | 既定で64 MiBと64 KiBの論理メモリ（システム領域は4000H未満、入力バッファは4000H〜13FFFH、データ領域は14000Hから `-m` の大きさまで、その後に同じ大きさのヒープ、最後にローカル変数）と各種固定容量を使います。メモリとスタックの大きさは、gforthと同じ起動オプション `-m`、`-d`、`-r`、`-f`、`-l` で指定できます。歴史的な機種のメモリ配置とは異なります。 |
| REQUIRE-GRAPHICS, GFX-INIT, GFX-WIDTH, GFX-HEIGHT, GFX-PSET, GFX-PGET, GFX-HLINE, GFX-CLS, GFX-SAVE-PPM, GFX-SAVE-BMP（段階G1）と、グラフィックスのライブラリの RGB, COLOR, COLOR!, COLOR@, PSET, CLS, LINE, RECT, FILL-RECT, CIRCLE, FILL-CIRCLE, PAINT, SAVE-PPM, SAVE-BMP（段階G2）と、SHOW, DISPLAY-TERMINAL, DISPLAY-WINDOW, TERMINAL-BLOCKS, TERMINAL-SIXEL, GFX-SHOW-BLOCKS, GFX-SHOW-SIXEL, GFX-SHOW-WINDOW, GFX-WINDOW?（段階G3）と、SAVE-PNG, GFX-SAVE-PNG, X-RANGE, Y-RANGE, MPSET, MLINE, AXES, PLOT, INKEY, MOUSE, MOUSE-ON, MOUSE-OFF, FRAME, K-UP などのキーの番号, GFX-INKEY, GFX-MOUSE, GFX-MOUSE-MODE, TEXT, TEXT-SCALE, TEXT-WIDTH, TEXT-HEIGHT, LOAD-FONT, SYSTEM-FONT, BUILTIN-FONT, GFX-GLYPH-LOAD, GFX-GLYPH-BOX, GFX-GLYPH-ALPHA, GFX-FONT-HEIGHT, GFX-FONT-LOAD, GFX-FONT-SYSTEM, GFX-FONT-BUILTIN, DISPLAY-COLORS, DITHER, GFX-COLOR-MODE（段階G4）、TCL, TCL-EVAL, TCL-ERROR$, TCL-EVENT, TCL-PROGRAM, TCL-STOP, DISPLAY-TK, GFX-TCL, GFX-TCL-ERROR, GFX-TCL-EVENT, GFX-TCL-PROGRAM, GFX-TCL-STOP, GFX-SHOW-TK（2026-11-06）, KEY-HELD?, GFX-KEY-HELD, WINDOW-SIZE, GFX-WINDOW-SIZE（2026-11-06）、NEW-IMAGE, FREE-IMAGE, IMAGE-SIZE, SCREEN, DRAW-TO, DRAWING, COPY-RECT, PUT-IMAGE, TRANSPARENT, IMAGE-FLIP, GFX-IMAGE-NEW, GFX-IMAGE-FREE, GFX-IMAGE-SIZE, GFX-TARGET, GFX-TARGET@, GFX-COPY, LOAD-IMAGE, GFX-IMAGE-LOAD, IMAGE-MODE, IMAGE-ALPHA, IMAGE-SCALE, MOUSE-EVENT, GFX-MOUSE-EVENT, REQUIRE-GUI と GUI- の語、REQUIRE-GAME とその語、GFX-PIXEL、GFX-TILEMAP、GFX-INDEXED、GFX-ROW-SHIFT、GFX-ROW-COLOR（2026-11-10）、2026-11-05 | 拡張 | 移植版のグラフィックスです。Gforthにも誌面にもない語です。`REQUIRE-GRAPHICS` は解析語で、初めて実行したときに `GRAPHICS` 語彙と `GFX-` の語を辞書の既存の語の後ろに加えます。そのため、起動時の組み込み語は0.5.2と同じです。画面の画像は16384×16384画素・1 GiBまで。ほかに、描いたり長方形を写し合ったり（透明色、反転、XOR、加算、半透明、拡大つき）、PNG・BMP・PPM/PGM のファイルから読み込んだりできる画像を256枚、合計1 GiBまで作れます。どれもホストが論理メモリの外に置き、イメージには保存しません。ファイルは2進のPPM、24ビットのBMP、圧縮しないPNGです。ライブラリの語はプログラムに組み込んだForthの定義で、現在の色を使います。SHOW は、Windowsではウィンドウ（専用のスレッド、CライブラリなしのWin32）に、ほかでは端末（半角ブロックかSixel、端末に合わせて縮小）に表示します。X-RANGE, Y-RANGE, MPSET, MLINE, AXES, PLOT は浮動小数点数の数学座標で描く語で、`-Dfloat=false` の版にはありません。INKEY はキーを待たずに読み（KEY、KEY?、ACCEPT は変わりません）、MOUSE は端末（xtermのSGRの報告か、Windowsのコンソール）やウィンドウでマウスの下の画素を返し、FRAME は一定の間隔で画像を表示します。INKEY と MOUSE が読んだ Ctrl+C は -28 を THROW します。TEXT は、美咲ゴシックの ASCII の組み込みフォント（幅4・高さ8画素。THIRD_PARTY_NOTICES.md を参照）、LOAD-FONT で読んだ BDF のフォント、Windows では SYSTEM-FONT で選んだシステムのフォント（なめらか）で文字列を描きます。フォントにない文字は ? で描きます。DISPLAY-COLORS は画像の色を変えずに、2、16、256色で表示します（DITHER は4×4のBayerの模様）。TCL の語は、Sigmaが起動してパイプでやり取りするTcl/Tkのプログラム（wish）でTclのスクリプトを実行し、DISPLAY-TK は画像をTkのウィンドウに表示します。Tcl/Tkが入っている必要があります。`-Dgraphics=false` の版にはありません。グラフィックスとサウンドのマニュアルを参照してください。 |
| REQUIRE-AUDIO, PLAY, PLAY2, PLAY3, PLAYS, PLAY?, SOUND, BEEP, AUDIO?, MSX-SOUND, ST-SOUND, NES-SOUND, C64-SOUND, SCC-SOUND, AMIGA-SOUND, CHIPS, MSX, ST, NES, C64, SCC, AMIGA, STYLE, INSTRUMENT, SQUARE, PULSE, TRIANGLE, SAW, NOISE, DUTY, ADSR, RING, SYNC, FILTER, SCC-WAVE, LOAD-SAMPLE, SAMPLE, LOOP-SAMPLE, SAMPLE-INSTRUMENT, SFX, FREE-SAMPLES, AMIGA-FILTER, LOAD-MOD, PLAY-MOD, STOP-MOD, MOD?, SND- の語、2026-11-07 | 拡張 | 移植版のサウンドです。Gforthにも誌面にもない語です。`REQUIRE-AUDIO` は解析語で、`REQUIRE-GRAPHICS` と同じく、初めて実行したときに `AUDIO` 語彙と `SND-` の語を加えます。PLAY, PLAY2, PLAY3, PLAY?, SOUND, BEEP は MSX BASIC に合わせています（MSX Red Book が説明する MSX1 の ROM の MML、長さは 12000 / (L × T) を1/50秒の単位にしたもの、PLAY は32個の待ち行列に音符が入りきると戻る）。ホストの音のスレッドが鳴らします。音源（MSX の AY-3-8910 はレジスタの単位で、Atari ST の YM2149、NES、C64 の SID、コナミの SCC、Amiga の Paula）は、資料に書かれた動きに合わせて共通の部品で作り、8声の中で1つずつ、または同時に（CHIPS、どの声部でも STYLE で）鳴らせます。MML の `@n` で音色を選びます。標本（8か16ビットの PCM の WAV ファイル）と、ProTracker の4チャンネルのモジュールは、論理メモリの外の 64 MiB の領域に置きます。SFX は標本を曲と並べて鳴らします。音の状態はイメージに保存しません。Windows は waveOut、Linux は PulseAudio か ALSA か、pacat・pw-play・aplay のコマンド、macOS は AudioToolbox の AudioQueue で鳴らします。出力装置がないときは、音を出さずに動きます。PLAY が待っている間の Ctrl+C は -28 を THROW します。`-Daudio=false` の版にはありません。グラフィックスとサウンドのマニュアルを参照してください。 |
| SAVESYS | 拡張 | 現在の辞書・コンパイル済みコード・データ領域を含む単独実行ファイルを作成します。 |
| SAVE, LOAD | 拡張 | 利用者定義語の辞書イメージ（`SIGIMG42`）を保存し、読み込み時は既存定義の後ろへ追加します。`SIGIMG38` 以前（0.8.0まで）のイメージは、入力領域を辞書の前に移したため読み込めません。0.8.0までの版も、この版のイメージを読み込めません。グラフィックスの語を読み込んだ辞書は `SIGIMG43`、音の語を読み込んだ辞書は `SIGIMG44` で保存します。イメージには `-m` と `-l` の大きさを記録し、大きさの違うイメージも追加読み込みできます。`SAVESYS` で作った実行ファイルは保存したときの大きさで起動します。イメージにはCRC-32のチェックサムを付け、壊れたイメージは読み込みません。読み込めるのはSigmaの `SAVE`・`SAVESYS` で作ったファイルだけで、それ以外のファイルを読ませることは想定していません。イメージには論理メモリのうち使う範囲（0〜HERE、ヒープの使用部分、ソースファイルの表）だけを入れるので、1語だけなら約50 KBです。ソースファイルの位置情報と読み込み履歴は引き継がれます。ヒープの内容は追加読み込みでは引き継がれません。定数やメモリに保存した実行トークンと、`LITERAL` で定義に埋め込んだ実行トークンやアドレスは、追加読み込みでは再配置されません（`[']` で埋め込んだものは再配置されます）。 |

実装の選択値と容量は[実装ノート](IMPLEMENTATION.md)に記録しています。各ワードのスタック効果を含む誌面記述は[SPEC.md](SPEC.ja.md)を参照してください。

## 未実装・機種依存

| ワード・機能 | 現状 | 主な理由・出典 |
| --- | --- | --- |
| エディットバッファ版のLOAD／SAVE、LIST, EDIT, EXEC, CLB | 未実装 | エディットバッファ操作。掲載版と環境に依存します。 |
| CLOAD, CSAVE | 未実装 | カセット等の機種別処理。 |
| MCODE | 機種依存 | Z80機械語領域を扱います。 |
| USR, PUHL, POHL, NEXT | 機種依存 | Z80レジスタ、呼出規約、機械語実行に関係します。誌面参照。 |
| CP/Mのファイル操作、BDOS、DMA | 機種依存 | CP/M版のOS呼び出しとバッファを必要とします。誌面参照。 |
| PC-8001の編集、表示、モニター機能 | 機種依存 | PC-8001固有の入出力とモニターを必要とします。誌面参照。 |
| 文字列の置き換え: SUBSTITUTE, REPLACES, UNESCAPE と、Gforthの `$SUBSTITUTE` `$UNESCAPE` `$VALUE` などの残りの文字列語 | 未実装 | 標準のSTRING-EXTとGforthの語（2026-10-30の調査）。 |
| Gforthの例外の書き方: TRY, ENDTRY, RESTORE, IFERROR | 未実装 | `CATCH` で同じことができます（2026-10-30の調査）。 |
| Gforthの道具の語: LATEST, LATESTXT, ID., .NAME, >NAME, ALIAS, ]], [[, ~~, ASSERT( | 未実装 | 2026-10-30の調査。 |
| キーの語: EKEY>FKEY, EMIT?, K-SHIFT-MASK, K-CTRL-MASK, K-ALT-MASK | 未実装 | 標準のFACILITY-EXT（2026-10-30の調査）。`K-UP` などのキーの定数は、グラフィックスのライブラリの `GRAPHICS` 語彙にあります（起動したときの辞書にはありません）。 |
| 標準のブロックの語: BLK, BLOCK, BUFFER, EMPTY-BUFFERS, FLUSH, LIST, SAVE-BUFFERS, SCR, THRU, UPDATE | 未実装 | 標準のBLOCK（2026-11-08の照合）。`LOAD` はあるが、辞書イメージを読む語で、標準のブロックの語とは別物です。 |
| (LOCAL) | 未実装 | `{:` で書けます。 |
| CODE, ;CODE, ASSEMBLER, EDITOR（標準のTOOLS-EXT） | 対象外 | アセンブラとエディター。Gforthの `CODE` と同じく対象外です。 |
| Gforthの CODE, END-CODE, SAVESYSTEM, 'COLD, BOOTMESSAGE, FPATH, SCRIPT? | 対象外 | Gforthの起動処理やアセンブラに依存します（2026-10-30決定、教材Level 30）。SAVESYSTEM の代わりに SAVESYS を使えます。 |

Z80の命令実行・エミュレーションはプロジェクトの対象外です。

上の表の「基本語」から「個別に設計」までは、2026-10-30の調査（Codexのレビューを反映）によるものです。Forth 2012のCORE、CORE EXT、DOUBLEの語と、よく使われる拡張の語について、`HELP` で1語ずつ調べ、Sigmaにない語がオリジナル版Gforth（0.7.9）にあることを `find-name` で確かめました。2026-11-08 に、forth-standard.org のForth 2012の語の一覧（Annex H、433語）と照合しました。辞書にない語のうち、構文語（`S"`、`IS`、`{:`、`FORGET` など）は実際に動かして確かめ、残りはこの表の「未実装」「対象外」の語だけでした。表の語がGforthと同じ意味で動くかは、実装するときに確かめます。

## 自動回帰テストとの対応

zig build testで、現行コアの主要動作を次のテストで確認します（コア211件、ホスト7件の計218件）。

| テスト | 確認する動作 |
| --- | --- |
| 64-bit arithmetic | 64ビット折り返し、床関数除算の商と剰余 |
| true flags | 比較・0=・NOTの真偽値（-1と0） |
| dictionary identity | 大小文字を区別しない全文字照合 |
| nested loops, loop boundaries | 入れ子DO/LOOP、I/J、?DOの0回実行、DOの最低1回実行 |
| LEAVE, UNLOOP | LEAVEの即時脱出、UNLOOPとEXIT |
| variable, array, string | 変数、配列、文字列リテラルとTYPE |
| number output, dot-s | 末尾空白、全基数での符号付き表示、U.、C.、.S |
| standard words | スタック操作、シフト、セル計算、文字、数値接頭辞、\ コメント、メモリ操作 |
| control structures | UNTIL、AGAIN、EXIT、RECURSE、CASE、コンパイル専用語の拒否 |
| VALUE, IMMEDIATE, POSTPONE | 値の変更、即時語、コンパイル動作の組み込み |
| error recovery | 未定義語の報告とエラー後のスタック初期化 |
| FORGET | 辞書語・配列領域・コンパイル済みコード・作成語の回収と再利用 |
| defining words | <BUILDS/DOES>の実行時語作成、動作の結び付け、複数行入力、FORGET後の再利用 |
| memory boundary | ヒープの先頭でのデータ領域確保の拒否、メモリの末尾を越えるアドレスのエラー。指定できる大きさの境界（`-m` は1 MiB以上、`-l` は4 KiB以上、合計4 GiB未満、スタックは各16〜2^27要素）、既定の大きさと指定した大きさの State が `UNUSED` と `ENVIRONMENT?` でその値を返すこと、起動オプション（`-m`、`-d`、`-r`、`-f`、`-l`、長い名前、単位、`0`、`--`、エラー）、イメージが配置を記録することと、配置の違うイメージの `LOAD` |
| capacity errors | データ／リターンスタック、辞書、制御ネスト、コンパイル領域の上限 |
| division by zero | /、MOD、/MODのエラーと、最小値÷-1の `RESULT OUT OF RANGE !`。*/、*/MOD、UM/MOD、FM/MOD、SM/REMのゼロ除算と、商が1セルに収まらない場合の `RESULT OUT OF RANGE !`（CATCHでは-11） |
| floating point | リテラル認識、F.とF.Sの書式、非有限値、算術・比較・変換、関数、メモリ・変数・定数・配列、FINPUT、浮動小数点スタックのアンダーフロー。FASINからF**までの関数のGforthと同じビット、Gforthと1 ulp違う正しく丸めた値、範囲外の引数のNaN、FMA命令のないビルドの小さな引数、FLOOR・FTRUNC・FROUND（-0、中間の値、無限大）、F~、FSINCOS、SF@・SF!・DF@・DF!と境界の語、FE.・FS.・F.とPRECISION（1桁、20桁、100桁、101桁、1000桁、範囲外）、FVALUEとTO・>BODY・SEE、REPRESENT（丸めの繰り上がり、0と-0、非正規化数、無限大・NaN）、SF!の境界（無限大、非正規化数、負の0、NaN）、FROUNDの0.5と2^52の前後、CORE-MATHが使う `fma` とFMA命令の結果（符号付きの0、積が非常に小さい場合、無限大・NaN） |
| double-cell integers | 倍長整数リテラル、D+等の演算・比較・表示、2@/2!、2VARIABLE、2CONSTANT、2VALUE（TO、SEE）、2LITERAL、D.R、D2*、D2/、DMAX、DMIN、M+、M*/（3セルの積、折り返し、符号なしの除数）、DU<、2ROT。*/、*/MOD、M*、UM*、UM/MOD、FM/MOD、SM/REMの結果がGforthと同じこと（負の数、積が1セルを超える場合） |
| pictured numeric output | <<# # #S HOLD HOLDS SIGN #> #>>、入れ子、対応しない #>> のエラー |
| strings | S"、S\"、.\"、.( の解釈時・コンパイル時の動作、一時バッファ、COUNT、PAD。C"、ABORT"（CATCHの-2、CATCHがないときの表示、定義の外のエラー、SEE）、BUFFER:、DUMP（1行16バイト、端数の行、0バイト）。COMPARE、SEARCH、/STRING、-TRAILINGの結果がGforthと同じこと（空の文字列、負の長さ、符号なしの比較を含む）。CHAR+、CHARS、BOUNDS、BLANK、CMOVE>（重なり）、SCAN・SKIP（タブ、負の長さ）、STR=、STRING-PREFIX?、+PLACE（255バイト）、SLITERAL（解釈中のエラー、255バイト）、PARSE-NAME（タブ、行末、EVALUATE）、SLURP-FILE・$SLURP-FILE（CR LFとNULをそのまま読む、空のファイル、置き換え、ファイルを閉じる、ないファイルのior、閉じるのに失敗したときに確保した領域を解放すること）、READ-FILE（CR LFをそのまま読む、ファイルの終わり、閉じたファイルのior）、?DUP、U<、U>、2R@、ALIGN、UNUSED、.R・U.R（負の幅、幅より長い数、16進数）、読み込み中のファイルからのPARSE-NAME、メモリの終わりを越える長さの文字列がエラーになること（STR=、COMPARE、SEARCH、-TRAILING、SCAN、SKIP、STRING-PREFIX?、BLANK、TYPE） |
| string conversion and input | >NUMBER、S>NUMBER?、>FLOAT、D>F、F>D、ACCEPT、EVALUATE、KEY、KEY?。SOURCE、>IN（行末への移動、同じ語の読み直し、負の値）、SOURCE-ID（端末・EVALUATE・ファイル）、REFILL（端末・ファイル・EVALUATE、失敗したとき）、SAVE-INPUT・RESTORE-INPUT（ファイルの行への繰り返し、EVALUATEの文字列の中、端末の同じ行と違う行、入力元が違うとき、個数が違うとき） |
| image round trip | 辞書イメージの保存・復元・追加読み込みでの語・浮動小数点定数・VALUE・FVALUE（2回の追加読み込み、保存したTO、完全復元）・2CONSTANT・文字列の再配置、定数に保存した実行トークンの完全復元、旧形式の拒否 |
| group A words | WITHINの境界と折り返し、2>R/2R>の順序と不足、ENDIF、PLACEの重なり・255バイト上限・メモリ末尾、STATEの保存アドレス経由の読み取り、ABORT、:NONAMEとその巻き戻し |
| :NONAME rollback | 定義中のエラー、`;` でのコード領域不足、開始時のスタック満杯・辞書満杯の後に、辞書・コード・データ位置・スタック・STATEが戻り、次の定義が作れること |
| host words | MS、UTIME、TIME&DATE、AT-XY、GETENV（未設定・空・長すぎる値）、SYSTEM（失敗）・$?、MS・UTIMEの失敗の報告、ホスト機能がない場合のエラー（MS、SYSTEM、UTIME、GETENV）、PAGEの出力 |
| host callbacks（`src/main.zig`） | 実際のGETENVの3072／3073バイト境界と未設定・空・`=` を含む名前、実際のSYSTEMの4095／4096バイト境界、NULを含むコマンドの拒否、0以外の終了コードとその状態の値 |
| 起動時の表示（`src/main.zig`） | 版番号が `VERSION` の値と同じで、ライセンスと `help` の案内を含み、CRを含まないこと |
| 標準入力のパイプ（`build.zig`） | 作った実行ファイルに実際のパイプでバイトを渡し、`READ-FILE` がCR LF、0x1A、NUL、255をそのまま読むこと、`READ-LINE` がCR LFで行を区切ること |
| ファイルの語（`src/main.zig`） | 実際のファイルで、FILE-POSITION、RESIZE-FILE、FLUSH-FILE、FILE-STATUS、既にあるファイルへのRENAME-FILE、失敗したRENAME-FILEで変更先が残ること、DELETE-FILE（2回目のior） |
| SLURP-FILE（`src/main.zig`） | 実際のファイルの10000バイト（CR LFとすべてのバイト値を含む）と空のファイルをそのまま読み、ファイルを閉じること |
| SAVE・LOAD（`src/main.zig`） | ホストを通したSAVEと、2回続けたLOAD（LOADが作る2つ目のStateをスタックに置かないこと）で語と変数が使えること |
| THROW | 0の無視、-1の中断、標準コード・ファイルのior・その他のコードの報告（基数によらず10進） |
| CATCH | 0とTHROWコードの返却、データ・浮動小数点・リターン・ループスタックの深さの復元（Gforthと同じ結果）、内部エラーのコード、入れ子、ファイルのior、ローカル変数・$TMPとの組み合わせ、捕捉したコードの再THROW、途中で始まった定義の破棄 |
| heap | ALLOCATE・FREE・RESIZEの成功と失敗（ENOMEM、無効なアドレス）、解放した領域の再利用、全解放後のヒープの回復 |
| dynamic strings | 教材Level 14の例、自分自身を元にした連結・挿入、範囲外の削除・挿入・上書き、$SPLIT、$ITER、$TMP（入れ子、エラー後の出力復帰）、文字列配列、$[]SLURP／$[]SLURP-FILE、$SLURP・$+SLURP（ファイルの位置から）・$+SLURP-FILE・$SLURP-LINE（CR LF、空の行、終わり）、$+!LEN、$[]+!・$+[]!、$EXEC（入れ子、THROWの後の出力先）、$OFF、$VARIABLE、完全復元後のヒープ文字列 |
| tab separators | タブで区切ったソース、文字列語・CHARの直後のタブ |
| word lists | 教材Level 16の例（VOCABULARY・ONLY・ALSO・DEFINITIONS・ORDERの表示、WORDLIST・SET-CURRENT・>ORDERのモジュールと隠し方）、GET-ORDER・SET-ORDER・PREVIOUS・-1 SET-ORDER、検索順序のあふれ・不足・無効な語彙、WORDSとSEARCH-WORDLIST、MARKERによる検索順序の復元、イメージの復元とLOADでの語彙番号の付け替え |
| F.RDP | Gforthの出力と同じになる55例（固定小数点・指数表記・*で埋める場合・0・無限大・NaN・偶数への丸め・小さな値の丸め・丸めで指数の桁や有効桁数が変わる場合・0の整数部が入らない幅）、F.RDPの表示、F>BUF-RDP、教材Level 20の例、幅の上限と保持領域のあふれ、丸めで指数が短くなる値のF.RDPとF>BUF-RDP |
| 数学関数・F.S・.S | FSIN・FCOS・FTAN・FEXP・FLNがビット単位で正しく丸めた値になること（Windows版Gforthとzigの組み込み関数で1ビットずれる値と教材Level 25の値）、F.Sの `14 0 17 F.RDP` 形式と上の9個の表示（0・-0・無限大・NaN・非正規化数）、.Sの上の9個の表示 |
| 数学関数の境界 | 大きな引数の三角関数、FEXPのオーバーフロー・非正規化数・0への境界、FLNの最小非正規化数・1の近く・最大値でオリジナル版Gforthと同じビットになること、NaNの引数をそのまま返し無限大でCPUの既定のNaNを返すこと（全ビット1のNaNでないこと）、.SとF.Sの深さ0・ちょうど9個・16進 |
| >BODYと' | VARIABLE・2VARIABLE・FVARIABLE・VALUE・2CONSTANT・DOES>付きCREATE・CREATEの>BODY、定義の中の `'` が実行時に名前を読むこと（教材Level 31の形）、`[']` はコンパイル時に読むこと、解釈中の `'` が次の行の名前を読むこと、CONSTANT・コロン定義・組み込み語の>BODYのエラー、名前がない場合のエラー |
| LITERAL・FLITERAL | `[ 2 3 * ] LITERAL`、`[ ... ] FLITERAL`、`[ DEBUG ] LITERAL IF`、`[ ' DUP ] LITERAL EXECUTE`、教材Level 31のDSLと同じ形で `POSTPONE LITERAL` により変数のアドレスと実行トークンを埋め込む語、解釈中のエラー |
| '・>BODY・LITERALの境界 | 語彙で定義し直した `'` が検索順序に従うこと、FIND-NAME・POSTPONE・CATCHの中・INCLUDEしたファイルの次の行で `'` が名前を読むこと、EVALUATEの文字列の最後の `'` のエラー、ARRAYと（DOES>のない）CREATEの>BODY、MARKER・VOCABULARY・:NONAME・FCONSTANT・不正な値の>BODYのエラー、倍長整数を1セルずつ取り込むLITERAL、値がないときと `[ ]` の中のエラー、追加読み込みで `[']` の実行トークンは再配置されLITERALで埋め込んだものはされないこと |
| HELP・LICENSE | すべての組み込み語に説明があり、説明の名前はすべて実在する語であること（重複なし）、`HELP` だけで基本の説明を表示して次の行を読まないこと、`EVALUATE` の文字列で改行の先を読まないこと、定義の中の `HELP` が実行時に名前を読むこと、組み込み語・構文語・利用者定義語の `HELP 語名`、知らない名前のエラー、`LICENSE` がMITの全文とCORE-MATHの表示を、ホストに渡す前はLFで出すこと |
| 名前の領域・イメージの大きさ | FORGET・MARKER・失敗した定義で名前の領域も戻ること、255文字の名前で名前の領域がいっぱいになると `OUT OF DICTIONARY !` でそれまでの語は使えること、イメージの大きさが保存する範囲の合計に等しく、ヒープの中身を保ちHEREより先は0で戻り、1バイト欠けると読み込まないこと、LOADで加えた語の名前とSEE・FORGET。辞書65535語・コード65535操作の上限でのエラーと巻き戻し。1バイト壊れたイメージ（チェックサムで検出し、辞書・コード・メモリが変わらないこと）、名前の位置や長さが壊れたイメージと `SIGIMG31` のイメージを何も変えずに拒否すること、名前の領域がないときのVARIABLEがHEREを戻すこと、CATCHで捨てた定義の名前の領域、名前のない語をはさんだLOADとFORGET、名前の領域が足りないLOADで何も変わらないこと |
| 定義の中の定義語 | 定義の中のVARIABLE・CONSTANT・FVARIABLE・FCONSTANT・VALUE・2CONSTANT・2VARIABLE・ARRAY、教材Level 31の `:` で始めて `POSTPONE ;` で終える語、名前がない場合と定義中の `:` のエラー、検索順序から外した定義語、DOES>を付けた変数、10の累乗に近い値のF. |
| 解釈中の[・PI・F. | 解釈中の `[`、PIのF.とF.RDP、2進数の値から正確に丸めるF.とF.S |
| locals visibility | IF・ELSE・THEN、BEGIN・UNTIL・WHILE・REPEAT、DO・?DO・LOOP・LEAVE、CASE・OFでの名前の見える範囲（Gforthで確かめた15例） |
| word lists（レビュー対応） | 回収したデータ領域に作ったMARKERのLOAD、[DEFINED]・[UNDEFINED]とローカル変数、INCLUDEの中での[IF]の読み飛ばしとファイルの終わり、複数の語彙にある同名語のFIND・LOCATE、語彙と:NONAME・DOES>を含むイメージの復元 |
| conditional compilation | [IF] [ELSE] [THEN]の選択・入れ子・行をまたぐ読み飛ばし・コンパイル中の使用、[DEFINED]・[UNDEFINED]、EVALUATEの中で終わらない[IF]、[IFDEF] [IFUNDEF] [ENDIF]、[DO] [?DO] [LOOP] [+LOOP] [I]（入れ子、負の増分、`[ ]` の中、EVALUATE、ファイルの行をまたぐ繰り返し）、[BEGIN] [UNTIL] [WHILE] [REPEAT]、[FOR] [NEXT]、開始語のない[LOOP]と[I]、CATCHの後の繰り返し、同じ長さの次の端末の行、最大のセルをまたぐ[+LOOP]と+LOOP |
| source files（レビュー対応） | EVALUATE内の名前待ちのエラー、CREATEとDOES>の間のINCLUDE／EVALUATE、読み込み中のファイル内でのMARKER、LOADで読み込んだMARKER、呼び出し元の定義を終えて別の定義を始めるファイル、閉じるのに失敗した場合の位置、WORDの255／256バイト、NAME>STRINGの8個のバッファ、SEEの入れ子・空の分岐・CASE |
| source files | INCLUDEの複数行定義・SOURCEFILENAME・SOURCELINE#・INCLUDED?、REQUIRE（自分自身・パラメータ付き）、入れ子の内側のエラー位置、定義途中のファイル終了、ファイルがない場合、すべてのファイルを閉じること、CATCHで捕捉した後の続き、入れ子の上限、MARKERによる語と履歴の巻き戻し、LOCATE、WHERE（タブと全角文字の幅、長い行、80桁を超える位置、端末での使用、FORGETの後、再定義）、位置情報と履歴のイメージ復元・追加読み込み、実際のホストでのCR LFと4096／4097バイトの行 |
| parsing and dictionary words | 語の後の区切り1文字の消費とPARSE、文字列語の空白、WORDの数え付き文字列、FINDの即時語・未発見、FIND-NAME・NAME>INT・NAME>STRINGと無効な名前トークン、SEEの出力（制御構造、CREATE/DOES>、IMMEDIATE）、EVALUATEが端末の次の行を読まないこと、入力行の上限 |
| locals | スタック順の受け取り、定義途中・ループ内での宣言、TO、`\|`、W:/D:/F:/C:/XT:、W^/F^/C^のアドレス、LOCALS\|、`{: :}`、再帰と領域の解放、エラー後の解放、名前の有効範囲、定義外での拒否、追加読み込み後の実行 |
| file words | アクセス方法とストリーム番号、作成・書き込み・大きさ・位置変更・行単位の読み込み・閉じる、エラー時のiorとスタックの形、STDOUTへの書き込み、ホスト機能がない場合のエラー。FILE-POSITION、RESIZE-FILE（位置が変わらないこと）、FLUSH-FILE、FILE-STATUS、RENAME-FILE、DELETE-FILE（2回目のior）、BIN、INCLUDE-FILE、閉じたファイルのior |
| graphics | REQUIRE-GRAPHICS が検索順序と組み込み語を変えずに1回だけ読み込むこと、定義の中と `-Dgraphics=false` の版でのエラー、GFX-INIT の大きさの上限（1〜16384、1 GiB）とホストが失敗したときに前の画像が残ること、画像がないときのエラー、GFX-PSET・GFX-PGET・GFX-HLINE の切り取り、PPMとBMPのファイルのバイト列（行の詰め物）と失敗時のior、ライブラリを GRAPHICS に読み込むことと失敗時にすべて戻すこと、読み込む前は SIGIMG42・後は SIGIMG43（MARKER の後も）、グラフィックスの語を含むイメージの復元と追加読み込み（LOAD）、定義の途中で失敗するライブラリ（直接、エラー報告の後、CATCH 経由）、画像のある State への復元、語彙のセルの任意の値、違う長さを返すホスト、ライブラリの読み方（CR LF、空行、長すぎる行、行をまたぐ [DO]、REFILL、SOURCE-ID）、書き込み用バッファより大きい保存と書き込み・閉じる失敗、グラフィックスのない版での SIGIMG43 の GFX- の語の実行、ライブラリ: 色の語と BASE、画像がないときのエラー、LINE の全方向と端での切り取り（遠い端点を含む）、RECT と FILL-RECT（0以下の大きさ、遠い角）、CIRCLE と FILL-CIRCLE の形（対称性、円周が円の内側にあること、巨大な半径、半径0〜64で画像の端で切れる場合も含めて独立した中点アルゴリズムと画素が一致すること）、格子の端点での独立した Bresenham との LINE の一致、PAINT（作業用スタックが伸びる櫛形、同じ色、画像の外、作業用スタックを作れない・伸ばせないときの CANNOT ALLOCATE MEMORY と解放）、読み込みに失敗したときの BASE、SAVE-BMP と SAVE-PPM の THROW、ライブラリの語の HELP・LOCATE・WHERE、GFX-SHOW-BLOCKS と GFX-SHOW-SIXEL のバイト列と UTF-8 の通知、端末の大きさに合わせた平均での縮小、SHOW のウィンドウと端末への振り分けとウィンドウのないホストでの DISPLAY-WINDOW、独立に復号したSixel、出力のバッファを超える半角ブロック、PNGのファイル（チャンクとそのCRC-32、無圧縮ブロック、Adler-32、画素、ior）、数学座標（AXES、NaNと遠い値での MPSET と MLINE、y = x² と √x の PLOT と NaN での切れ目、NUMBER ERROR になる範囲、幅1の画像、画像がないときのエラー）、INKEY のエスケープシーケンスの解読（CSI、SS3、修飾キー、チルダのキー、知らない並び、Esc 単独、終わらない並び、UTF-8、LF と DEL）と Ctrl+C、ホストが解読したキー、SGRの報告（ボタン、離す、動き、ホイール）とウィンドウからの MOUSE、カーソルの位置からの画像の位置とそれがない場合、MOUSE が読む間に残るキー、前の画像の上に描く SHOW（半角ブロックとSixel、ほかの出力の後と端末でないときは新しく描く）、FRAME の待ち・遅れたときは待たないこと・表示、フォントの並びと GFX-GLYPH、TEXT（ASCII、制御文字、ASCII 以外の文字・漢字・不正なバイト・途中で切れた並びの ?、画像の端で切れる TEXT-SCALE、遠い位置）、TEXT-WIDTH、TEXT-SCALE の範囲、画像がないときの TEXT、組み込みフォントの字形の語、LOAD-FONT（順不同の字形、ベースラインより下、1行2バイト、文字番号のない字形、? のないフォント、TEXT-HEIGHT、壊れたファイル、開けないファイル、バッファがないとき）、偽のホストでの SYSTEM-FONT（濃さでの混色、拡大、ない字の ?、知らない名前、高さの範囲、フォントのないホスト）、2・16・256色のパレットとディザ、端末（半角ブロックとSixelのレジスター）とウィンドウでの DISPLAY-COLORS、画像の色が変わらないこと、使える値、和があふれる大きさの BDF の数値、空の字形、2回の読み取りの間に変わるフォントファイル（フォントとバッファが残ること）、キーの待ち行列が満杯のときの MOUSE、分かれて届く並びと50 ms後の Esc、raw の入力のやり直し、TEXT の厳密な UTF-8、最も広い範囲の PLOT、DSR の応答（ホスト）、偽のTclのプログラムでの TCL-EVAL（結果、エラー、UTF-8、空の結果、結果の前のイベントとキー、待たない TCL-EVENT と MOUSE、終わったプログラムの起動し直し、TCL-PROGRAM、TCL-STOP、合わない見出し、プログラムを起動できないホスト）、DISPLAY-TK のbase64のPNGの送信と失敗、スクリプトの実行中のTkのウィンドウの Ctrl+C、途中で切れた結果（ヒープの解放）、分かれて届くメッセージを待たずに読むこと、取り決めに合わない見出し、コード2の R、文字列の解放（releaseHeap を直接呼ぶ）、メッセージの途中と見出しの途中での SAVE と SAVESYS、メッセージの途中での TCL-STOP とホストが終わりを確かめられない停止、ためたキーより先の端末のやり直しとTkのウィンドウのキーとマウスが残ること、50 msを過ぎた Esc、KEY-HELD?（ウィンドウのキーは離すまで、Windowsのコンソールのキーは離すか端末のやり直しまで、端末の0.6秒と繰り返しと時計の戻り、TkのウィンドウからのU、0以外のコードのU、最後に押した16個のキー）、WINDOW-SIZE（次の SHOW からウィンドウに渡す大きさ、0 0、使えない大きさ、Tkのウィンドウに送る大きさ）、TCL-STOP の後と SAVE が離した知らせを捨てたときに Tk のキーを忘れる KEY-HELD?、入力元ごとに分けたキー |
| graphics images | NEW-IMAGE（黒であること、ハンドル、各辺・256枚・合計1 GiBの上限、確保に失敗するホストと画像の機能のないホスト）、FREE-IMAGE と無効になるハンドル（二重の解放、描画先、次の世代での位置の再利用、INVALID IMAGE HANDLE -278）、画像への DRAW-TO と描画の語・GFX-WIDTH・GFX-HEIGHT・SAVE-PPM、そのとき SHOW が画面を表示すること、GFX-INIT が描画先を変えないこと、COPY-RECT と PUT-IMAGE の両方の画像の各辺での切り取り（2^63に近い大きさも含む）、TRANSPARENT、IMAGE-FLIP の1〜3（一部分、切り取り、透明色との組み合わせ）とそのエラー、同じ画像の中で各方向に重なる写し、重なる場所への反転の拒否、辞書の復元で画像が解放されること、IMAGE-MODE の XOR・加算（255まで）・IMAGE-ALPHA 0・128・255 の半透明と透明色の組み合わせ、IMAGE-SCALE と反転・切り取り・透明色・2^63に近い大きさ・同じ画像の重なる場所の拒否、範囲外の値のエラー |
| load image | Pillow が書いた、または Pillow で確かめた32個のファイルの LOAD-IMAGE: PNG のすべての色の種類とビット深度（1、2、4、8、16）、パレット・灰色・RGB の tRNS、アルファの値、8ビット RGB と2ビット灰色の Adam7。BMP の1、4、8、16（5-5-5 と 5-6-5 のマスク）、24、32ビット（124バイトの見出しのアルファのマスクありとなし）、上から下の行、12バイトの見出し。PPM と PGM の2進、コメントつきテキスト、最大値15と65535。透明な画素が TRANSPARENT の色か黒になること。IMAGE FORMAT ERROR -279 で何も変えずに拒否すること（ほかのファイル、空、途中で切れたもの、圧縮データの1バイトの変更、ほかの圧縮の BMP、画素のない BMP、最大値を超える PNM の値、幅0の絵）、開けないファイルの ior、各辺16384を超える絵の NUMBER ERROR |
| gui | REQUIRE-GUI がグラフィックスの語を先に1回だけ読み込み、検索順序を変えないこと、定義の中とグラフィックスのない版で拒否すること。色の役割と線の太さとそのエラー、GUI-DEFAULT。ボタンのマウスでのクリック（ほかで離したときは押されない）、フォーカスのある Enter と Space、Tab によるフォーカスの移動、使えないボタン、GUI-KEY。チェックボックスのラベルのクリックと Space。入力欄の UTF-8、Backspace、矢印、Home、End、Delete、容量、Enter。リストの矢印（先頭から末尾へ回る）とクリック。メニューバーとメニューのクリックとキー、選べない項目、区切り線、下の部品からキーとマウスを取ること、Esc。ファンクションキー欄のキーとクリック。ダイアログの Enter と Esc。GUI-ASK、GUI-CHOOSE、GUI-MESSAGE が待ってから画面を戻すこと。ゲームパッドが押されたときだけキーになること |
| game | REQUIRE-GAME がグラフィックスの語を先に1回だけ読み込むこと。GFX-PIXEL の任意の画像、外側の -1、無効なハンドル。スプライトのコマ・反転・透明色での描画、非表示、アニメーション。HIT? と PIXEL-HIT? の透明な画素、反転、非表示、離れたスプライト、INIT-SPRITE で作った配列。SPRITE-PIXEL?。タイルマップの TILE@ と TILE! とそのエラー、>TILE（床関数）、スクロールした位置からビューへの描画と地図の端での切り取り、透明色付きの2枚目の地図、遠くや空のビュー、メモリーの外の地図、大きさのないタイル。辞書イメージがスプライトと地図を保つこと。パレット: PALETTE! が24ビットを保つこと、0〜255 の外の番号、複数の番号と1つの番号の ROTATE-PALETTE。色番号の絵: INDEX@ と INDEX! とそのエラー、番号を除いた描画と画像からはみ出した描画、メモリーの外のパレットと負の幅の GFX-INDEXED。RASTER-SCROLL の右、左、一周を超える量、画像からはみ出した長方形の中、空と外の長方形、メモリーの外の表、多すぎる行。RASTER-COLOR。DRAW-SPRITES の行ごとの制限、制限なし、両方向の反転、非表示のスプライト |
| audio | PSG のトーン、ノイズ（17ビットの LFSR）、エンベロープの16種類の形とその長さ、ミキサーと音量、MML（音符、長さ、既定値、エラー、`@`）、PLAY の声部が同時に始まること、PLAY(n)、長い PLAY の待ちと Ctrl+C（シグナルとキー）、誤った PLAY が何も入れないこと、BEEP、SOUND、同じ入力から同じ波形、WAV の見出し、REQUIRE-AUDIO（1回だけ、検索順序、定義の中、audio のない版）、SIGIMG44 とその読み込みと追加読み込み、各音源（NES の矩形波・デューティ・三角波・ノイズ、ST の周期、SID のレジスタ・波形・シンク・リング変調・フィルター、SCC の波形、Amiga の周期・左右・波形の間引き・LED フィルター）、ADSR、平均律の音の高さ、CHIPS（マスク、声部の番号、8声）、STYLE（どの声部でもどの機種でも）、INSTRUMENT とその語、WAV ファイル（形式、チャンク、エラー、満杯の領域）、SAMPLE、LOOP-SAMPLE、SAMPLE-INSTRUMENT、SFX、FREE-SAMPLES、MOD の見出しと再生（行の長さ、パターンの区切りとループ、終わり、くり返し、音量、音量の変化、ポルタメント、ノートディレイ）、すべての音の語の HELP |

現行テストは主要経路を確認するものです。全ワード、すべての容量境界、各エラー条件を網羅したものではありません。

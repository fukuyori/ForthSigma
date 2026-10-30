# FORTH/Σワード互換性一覧

この一覧は[FORTH/Σ仕様書](SPEC.md)と現在のZig実装を対応づけたものです。誌面に同名ワードがあることだけでは、すべての機種版で同じ仕様とは限らないため、出典は誌面の掲載内容で確認しています。2026-10-28以降、数値まわりと基本ワードはGforthに合わせています（[決定事項](DECISIONS.md)）。

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
| 基本語・倍長の乗除算・READ-FILE（2026-10-30） | ?DUP, U<, U>, ALIGN, UNUSED, .R, U.R, 2R@, */, */MOD, M*, UM*, UM/MOD, FM/MOD, SM/REM, READ-FILE | Forth 2012のCORE・CORE EXTの語と、ファイルの語。結果はGforthと同じです。`*/` などの除算は、0で割ると `DIVISION BY ZERO !`（-10）、商が1セルに収まらないと `RESULT OUT OF RANGE !`（-11）になります（Gforthと同じ）。既存の `/` `MOD` `/MOD` は、最小値を-1で割ると折り返したままで、Gforthの-11とは異なります。`READ-FILE` は `STDIN` からも読めます。Windowsでも、パイプやリダイレクトの標準入力はバイナリで読むので、CR LFや0x1Aもそのまま読めます（コンソールはテキストのままです）。 |
| 文字列の操作・比較・検索 | COMPARE, SEARCH, /STRING, -TRAILING, CHAR+, CHARS, BOUNDS, BLANK, CMOVE>, SLITERAL, PARSE-NAME, SCAN, SKIP, STR=, STRING-PREFIX?, +PLACE, SLURP-FILE, $SLURP-FILE | Forth 2012のSTRING語と基本語、Gforthの文字列語。`+PLACE` はGforthでは古い語とされています。負の長さは、Sigmaのほかの文字列語と同じく空の文字列として扱います（Gforthの `BLANK` `SCAN` などはメモリの誤りになります）。メモリの終わりを越える長さは `INVALID MEMORY ADDRESS !` になります。`SLITERAL` の文字列は `S"` と同じく255バイトまでです。境界の値（空の文字列、負の長さ、範囲を超える/STRING、タブを含む末尾）もGforthと同じ結果です。 |
| 例外・ファイル（段階5a、CATCH） | THROW, CATCH, R/O, W/O, R/W, STDIN, STDOUT, STDERR, OPEN-FILE, CREATE-FILE, CLOSE-FILE, READ-LINE, WRITE-LINE, WRITE-FILE, FILE-SIZE, REPOSITION-FILE | 教材Level 14、19、23、25、29。CATCHで捕捉しなかった0以外のTHROWはエラーとして報告します。 |
| 動的メモリ・動的文字列（段階5b） | ALLOCATE, FREE, RESIZE, $!, $@, $@LEN, $!LEN, $+!, C$+!, $., $DEL, $INS, $OVER, $FREE, $INIT, $SPLIT, $ITER, $TMP, $[], $[]!, $[]@, $[]#, $[]., $[]MAP, $[]FREE, $[]SLURP, $[]SLURP-FILE | 教材Level 14、29、30、32。ヒープは論理メモリの100000H〜1DFFFFH。 |
| 辞書探索・解析（#153） | WORD, FIND, PARSE, FIND-NAME, NAME>INT, NAME>STRING, SEE | 教材Level 10、31。`SEE` はコンパイル済みの命令列から定義を再構成します。`FIND` は構文語（`TO` `[']` など）を見つけません。 |
| 浮動小数点の書式（#156） | F.RDP, F>STR-RDP, F>BUF-RDP | 教材Level 20、25、29。Gforthで確かめた118例すべてと同じ出力です。 |
| 説明・ライセンス | HELP, LICENSE | Gforthの `help` `license` に相当します。`HELP 語名` の説明はこの移植版のために書いたもので、Gforthのマニュアルの文章ではありません。起動時の表示（引数なしのときだけ）は2行で、版番号とライセンスを示します。 |
| リテラルのコンパイル（#181） | LITERAL, FLITERAL | 教材Level 31。科学計算DSL（完成版）はGforthと同じ出力になります。COMPILE,、DEFER、IS、ACTION-OFはありません。 |
| 実行トークンのデータ領域（#177） | >BODY | 教材Level 31。`'` は語の番号を返すので、`'` の値をアドレスとして使う教材Level 12の `' DATA +` とLevel 21の `' pointA @` は動きません（Gforthでは動きます）。CONSTANT・FCONSTANT・コロン定義・組み込み語の `>BODY` はエラーです。 |
| 定義語・定数（#158） | 定義の中の :, ;, VARIABLE, VAR, FVARIABLE, 2VARIABLE, CONSTANT, CONST, FCONSTANT, 2CONSTANT, VALUE, ARRAY, FARRAY、PI | 教材Level 20、25、31。定義の中に書いた定義語は、その定義の実行時に名前を読みます。解釈中の `[` はエラーにしません。 |
| 語彙・条件付きコンパイル（段階6） | ONLY, ALSO, PREVIOUS, FORTH, DEFINITIONS, ORDER, GET-ORDER, SET-ORDER, >ORDER, GET-CURRENT, SET-CURRENT, VOCABULARY, WORDLIST, FORTH-WORDLIST, SEARCH-WORDLIST, [IF], [ELSE], [THEN], [DEFINED], [UNDEFINED] | 教材Level 16、30。検索順序の初期値と `ORDER` の表示はGforthと同じです。`:` `TO` などの構文語は語彙に属さず、検索順序によらず使えます。 |
| ソース読み込み（#154）・MARKER | INCLUDE, INCLUDED, REQUIRE, REQUIRED, NEEDS, INCLUDED?, SOURCEFILENAME, SOURCELINE#, LOCATE, MARKER | 教材Level 2、10、14、16、19、30。ファイル名はカレントディレクトリからの相対パスです。WHEREは未実装です。 |
| ローカル変数（段階4） | { ... }, {: ... :}, LOCALS\|, 型指定 W: W^ D: D^ F: F^ C: C^ XT: XT^, TO | 教材Level 14〜16、25〜27、29、32。`{` と `LOCALS\|` は構文語で、`WORDS` には表示しません。 |

## 追加機能・移植上の違い

| 機能 | 状態 | 現在の動作 |
| --- | --- | --- |
| タブ区切り | 拡張 | タブも空白と同じくトークンの区切りです（誌面は空白とCRのみ）。Gforthと同じです。 |
| 大文字・小文字を区別しない名前照合 | 拡張 | ASCII英字の大小を同一視します。Gforthと同じです。 |
| 数値基数2〜36と接頭辞 | 拡張 | BASEのメモリ値で2〜36を使えます。`$` `#` `&` `%` 接頭辞と `'c'` を認識します。 |
| 浮動小数点リテラル | 拡張 | 基数10で `e`/`E` を含むトークン。 |
| F+!, F?, FA@, FA!, FARRAY, FINPUT, FMINUS | 拡張 | FORTH/Σの +!、?、A@、A!、ARRAY、INPUT、MINUS に対応する浮動小数点版。Gforthのワードではありません。 |
| ."文字列出力 | 拡張 | コンパイル時文字列出力です。1982年資料のワードではありません。 |
| ?DO | 拡張 | 開始値と終値が同じ場合、ループ本体を実行しません。FORTH/ΣのDOは同値でも1回実行します。 |
| J, K | 拡張 | 2段目・3段目のループ添字を取得します。誌面では利用者定義例として説明されています。 |
| EXECUTE | 拡張 | ポータブルな辞書トークンを実行します。Z80コードアドレス互換ではありません。 |
| 単一の論理メモリと上限 | 拡張 | 2 MiBの論理メモリ（データ領域は100000H未満、ヒープは100000H〜1DFFFFH、入力バッファは1E0000H〜1EFFFFH、ローカル変数は1F0000H〜1FFFFFH）、各種固定容量を使います。歴史的な機種のメモリ配置とは異なります。 |
| SAVESYS | 拡張 | 現在の辞書・コンパイル済みコード・データ領域を含む単独実行ファイルを作成します。 |
| SAVE, LOAD | 拡張 | 利用者定義語の辞書イメージ（`SIGIMG20`）を保存し、読み込み時は既存定義の後ろへ追加します。`SIGIMG19` 以前のイメージは読み込めません。イメージにはCRC-32のチェックサムを付け、壊れたイメージは読み込みません。読み込めるのはSigmaの `SAVE`・`SAVESYS` で作ったファイルだけで、それ以外のファイルを読ませることは想定していません。イメージには論理メモリのうち使う範囲（0〜HERE、ヒープの使用部分、ソースファイルの表）だけを入れるので、1語だけなら約50 KBです。ソースファイルの位置情報と読み込み履歴は引き継がれます。ヒープの内容は追加読み込みでは引き継がれません。定数やメモリに保存した実行トークンと、`LITERAL` で定義に埋め込んだ実行トークンやアドレスは、追加読み込みでは再配置されません（`[']` で埋め込んだものは再配置されます）。 |

実装の選択値と容量は[実装ノート](IMPLEMENTATION.md)に記録しています。各ワードのスタック効果を含む誌面記述は[SPEC.md](SPEC.md)を参照してください。

## 未実装・機種依存

| ワード・機能 | 現状 | 主な理由・出典 |
| --- | --- | --- |
| エディットバッファ版のLOAD／SAVE、LIST, EDIT, EXEC, CLB | 未実装 | エディットバッファ操作。掲載版と環境に依存します。 |
| CLOAD, CSAVE | 未実装 | カセット等の機種別処理。 |
| MCODE | 機種依存 | Z80機械語領域を扱います。 |
| USR, PUHL, POHL, NEXT | 機種依存 | Z80レジスタ、呼出規約、機械語実行に関係します。誌面参照。 |
| CP/Mのファイル操作、BDOS、DMA | 機種依存 | CP/M版のOS呼び出しとバッファを必要とします。誌面参照。 |
| PC-8001の編集、表示、モニター機能 | 機種依存 | PC-8001固有の入出力とモニターを必要とします。誌面参照。 |
| 入力処理: SOURCE, >IN, SOURCE-ID, REFILL、その後 SAVE-INPUT, RESTORE-INPUT | 未実装 | `>IN` は論理メモリ上の変数とし、入力位置（端末、ファイル、EVALUATE、入れ子）と同期する設計が必要です。 |
| 次点: C", ABORT", BUFFER:, 2LITERAL, D.R, D2*, D2/, DMAX, DMIN, M+, DU<, 2ROT, 2VALUE, DUMP | 未実装 | `C"` は長さバイトのアドレスを積む新しい命令が必要で、LOADの再配置の対象になります。`ABORT"` は例外コード-2とメッセージの扱いが必要です。 |
| 方針の決定待ち: DEFER, IS, ACTION-OF, DEFER!, DEFER@, COMPILE,, [COMPILE], M*/ | 未実装 | DEFER系とCOMPILE,は教材で使わないため見送っています（[決定事項](DECISIONS.md)、#181）。教材対応から一般のGforth互換へ広げるかを決めてから対応します。M*/は192ビットの途中結果が必要です。 |
| 浮動小数点: FLOOR, FROUND, FTRUNC, F**, FASIN, FACOS, FATAN, FATAN2, FSINCOS, FLOG, FALOG, FEXPM1, FLNP1, FSINH, FCOSH, FTANH, FASINH, FACOSH, FATANH, F~, FVALUE, FE., FS., REPRESENT, PRECISION, SET-PRECISION, FALIGN, FALIGNED, SFALIGN, SFALIGNED, DFALIGN, DFALIGNED, SF@, SF!, DF@, DF!, SFLOATS, DFLOATS, SFLOAT+, DFLOAT+ | 未実装 | 精度の方針（正しく丸める、特定のGforthの結果に合わせる、関数ごとに決める）を決めてから対応します。FLOOR・FTRUNCは関数の精度と関係なく先に作れます。 |
| 個別に設計: QUIT, ENVIRONMENT?, EKEY, EKEY?, EKEY>CHAR, AT-XY, TIME&DATE, AHEAD, CS-PICK, CS-ROLL, N>R, NR>, SYNONYM, TRAVERSE-WORDLIST, NAME>COMPILE, NAME>INTERPRET | 未実装 | `QUIT` はデータスタックを残したまま入力待ちへ戻る経路が、`ENVIRONMENT?` は問い合わせの表が必要です。 |
| Gforthの残りのファイル語（FILE-POSITION, BIN, DELETE-FILE, RENAME-FILE, RESIZE-FILE, FLUSH-FILE, FILE-STATUS, INCLUDE-FILE）、WHERE、`$SLURP` などの残りの文字列語、`[IFDEF]` などの残りの条件付きコンパイル語 | 未実装 | 必要に応じて対応（[決定事項](DECISIONS.md)）。 |
| Gforthの CODE, END-CODE, SAVESYSTEM, 'COLD, BOOTMESSAGE, IS, FPATH, SCRIPT? | 対象外 | Gforthの起動処理やアセンブラに依存します（2026-10-30決定、教材Level 30）。SAVESYSTEM の代わりに SAVESYS を使えます。 |

Z80の命令実行・エミュレーションはプロジェクトの対象外です。

上の表の「基本語」から「個別に設計」までは、2026-10-30の調査（Codexのレビューを反映）によるものです。Forth 2012のCORE、CORE EXT、DOUBLEの語と、よく使われる拡張の語について、`HELP` で1語ずつ調べ、Sigmaにない語がオリジナル版Gforth（0.7.9）にあることを `find-name` で確かめました。調べた語の一覧は標準の原典と照合していないため、この表が標準の語のすべてを網羅しているとは限りません。表の語がGforthと同じ意味で動くかは、実装するときに確かめます。

## 自動回帰テストとの対応

zig build testで、現行コアの主要動作を次のテストで確認します（コア174件、ホスト6件の計180件）。

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
| memory boundary | ヒープの先頭（100000H）でのデータ領域確保の拒否、2 MiB末尾を越えるアドレスのエラー |
| capacity errors | データ／リターンスタック、辞書、制御ネスト、コンパイル領域の上限 |
| division by zero | /、MOD、/MODのエラー。*/、*/MOD、UM/MOD、FM/MOD、SM/REMのゼロ除算と、商が1セルに収まらない場合の `RESULT OUT OF RANGE !`（CATCHでは-11） |
| floating point | リテラル認識、F.とF.Sの書式、非有限値、算術・比較・変換、関数、メモリ・変数・定数・配列、FINPUT、浮動小数点スタックのアンダーフロー |
| double-cell integers | 倍長整数リテラル、D+等の演算・比較・表示、2@/2!、2VARIABLE、2CONSTANT。*/、*/MOD、M*、UM*、UM/MOD、FM/MOD、SM/REMの結果がGforthと同じこと（負の数、積が1セルを超える場合） |
| pictured numeric output | <<# # #S HOLD HOLDS SIGN #> #>>、入れ子、対応しない #>> のエラー |
| strings | S"、S\"、.\"、.( の解釈時・コンパイル時の動作、一時バッファ、COUNT、PAD。COMPARE、SEARCH、/STRING、-TRAILINGの結果がGforthと同じこと（空の文字列、負の長さ、符号なしの比較を含む）。CHAR+、CHARS、BOUNDS、BLANK、CMOVE>（重なり）、SCAN・SKIP（タブ、負の長さ）、STR=、STRING-PREFIX?、+PLACE（255バイト）、SLITERAL（解釈中のエラー、255バイト）、PARSE-NAME（タブ、行末、EVALUATE）、SLURP-FILE・$SLURP-FILE（CR LFとNULをそのまま読む、空のファイル、置き換え、ファイルを閉じる、ないファイルのior、閉じるのに失敗したときに確保した領域を解放すること）、READ-FILE（CR LFをそのまま読む、ファイルの終わり、閉じたファイルのior）、?DUP、U<、U>、2R@、ALIGN、UNUSED、.R・U.R（負の幅、幅より長い数、16進数）、読み込み中のファイルからのPARSE-NAME、メモリの終わりを越える長さの文字列がエラーになること（STR=、COMPARE、SEARCH、-TRAILING、SCAN、SKIP、STRING-PREFIX?、BLANK、TYPE） |
| string conversion and input | >NUMBER、S>NUMBER?、>FLOAT、D>F、F>D、ACCEPT、EVALUATE、KEY、KEY? |
| image round trip | 辞書イメージの保存・復元・追加読み込みでの語・浮動小数点定数・VALUE・2CONSTANT・文字列の再配置、定数に保存した実行トークンの完全復元、旧形式の拒否 |
| group A words | WITHINの境界と折り返し、2>R/2R>の順序と不足、ENDIF、PLACEの重なり・255バイト上限・メモリ末尾、STATEの保存アドレス経由の読み取り、ABORT、:NONAMEとその巻き戻し |
| :NONAME rollback | 定義中のエラー、`;` でのコード領域不足、開始時のスタック満杯・辞書満杯の後に、辞書・コード・データ位置・スタック・STATEが戻り、次の定義が作れること |
| host words | MS、UTIME、GETENV（未設定・空・長すぎる値）、SYSTEM（失敗）、MS・UTIMEの失敗の報告、ホスト機能がない場合のエラー（MS、SYSTEM、UTIME、GETENV）、PAGEの出力 |
| host callbacks（`src/main.zig`） | 実際のGETENVの3072／3073バイト境界と未設定・空・`=` を含む名前、実際のSYSTEMの4095／4096バイト境界、NULを含むコマンドの拒否、0以外の終了コード |
| 起動時の表示（`src/main.zig`） | 版番号が `VERSION` の値と同じで、ライセンスと `help` の案内を含み、CRを含まないこと |
| 標準入力のパイプ（`build.zig`） | 作った実行ファイルに実際のパイプでバイトを渡し、`READ-FILE` がCR LF、0x1A、NUL、255をそのまま読むこと、`READ-LINE` がCR LFで行を区切ること |
| SLURP-FILE（`src/main.zig`） | 実際のファイルの10000バイト（CR LFとすべてのバイト値を含む）と空のファイルをそのまま読み、ファイルを閉じること |
| SAVE・LOAD（`src/main.zig`） | ホストを通したSAVEと、2回続けたLOAD（LOADが作る2つ目のStateをスタックに置かないこと）で語と変数が使えること |
| THROW | 0の無視、-1の中断、標準コード・ファイルのior・その他のコードの報告（基数によらず10進） |
| CATCH | 0とTHROWコードの返却、データ・浮動小数点・リターン・ループスタックの深さの復元（Gforthと同じ結果）、内部エラーのコード、入れ子、ファイルのior、ローカル変数・$TMPとの組み合わせ、捕捉したコードの再THROW、途中で始まった定義の破棄 |
| heap | ALLOCATE・FREE・RESIZEの成功と失敗（ENOMEM、無効なアドレス）、解放した領域の再利用、全解放後のヒープの回復 |
| dynamic strings | 教材Level 14の例、自分自身を元にした連結・挿入、範囲外の削除・挿入・上書き、$SPLIT、$ITER、$TMP（入れ子、エラー後の出力復帰）、文字列配列、$[]SLURP／$[]SLURP-FILE、完全復元後のヒープ文字列 |
| tab separators | タブで区切ったソース、文字列語・CHARの直後のタブ |
| word lists | 教材Level 16の例（VOCABULARY・ONLY・ALSO・DEFINITIONS・ORDERの表示、WORDLIST・SET-CURRENT・>ORDERのモジュールと隠し方）、GET-ORDER・SET-ORDER・PREVIOUS・-1 SET-ORDER、検索順序のあふれ・不足・無効な語彙、WORDSとSEARCH-WORDLIST、MARKERによる検索順序の復元、イメージの復元とLOADでの語彙番号の付け替え |
| F.RDP | Gforthの出力と同じになる55例（固定小数点・指数表記・*で埋める場合・0・無限大・NaN・偶数への丸め・小さな値の丸め・丸めで指数の桁や有効桁数が変わる場合・0の整数部が入らない幅）、F.RDPの表示、F>BUF-RDP、教材Level 20の例、幅の上限と保持領域のあふれ、丸めで指数が短くなる値のF.RDPとF>BUF-RDP |
| 数学関数・F.S・.S | FSIN・FCOS・FTAN・FEXP・FLNがビット単位で正しく丸めた値になること（Windows版Gforthとzigの組み込み関数で1ビットずれる値と教材Level 25の値）、F.Sの `14 0 17 F.RDP` 形式と上の9個の表示（0・-0・無限大・NaN・非正規化数）、.Sの上の9個の表示 |
| 数学関数の境界 | 大きな引数の三角関数、FEXPのオーバーフロー・非正規化数・0への境界、FLNの最小非正規化数・1の近く・最大値でオリジナル版Gforthと同じビットになること、NaNの引数をそのまま返し無限大でCPUの既定のNaNを返すこと（全ビット1のNaNでないこと）、.SとF.Sの深さ0・ちょうど9個・16進 |
| >BODYと' | VARIABLE・2VARIABLE・FVARIABLE・VALUE・2CONSTANT・DOES>付きCREATE・CREATEの>BODY、定義の中の `'` が実行時に名前を読むこと（教材Level 31の形）、`[']` はコンパイル時に読むこと、解釈中の `'` が次の行の名前を読むこと、CONSTANT・コロン定義・組み込み語の>BODYのエラー、名前がない場合のエラー |
| LITERAL・FLITERAL | `[ 2 3 * ] LITERAL`、`[ ... ] FLITERAL`、`[ DEBUG ] LITERAL IF`、`[ ' DUP ] LITERAL EXECUTE`、教材Level 31のDSLと同じ形で `POSTPONE LITERAL` により変数のアドレスと実行トークンを埋め込む語、解釈中のエラー |
| '・>BODY・LITERALの境界 | 語彙で定義し直した `'` が検索順序に従うこと、FIND-NAME・POSTPONE・CATCHの中・INCLUDEしたファイルの次の行で `'` が名前を読むこと、EVALUATEの文字列の最後の `'` のエラー、ARRAYと（DOES>のない）CREATEの>BODY、MARKER・VOCABULARY・:NONAME・FCONSTANT・不正な値の>BODYのエラー、倍長整数を1セルずつ取り込むLITERAL、値がないときと `[ ]` の中のエラー、追加読み込みで `[']` の実行トークンは再配置されLITERALで埋め込んだものはされないこと |
| HELP・LICENSE | すべての組み込み語に説明があり、説明の名前はすべて実在する語であること（重複なし）、`HELP` だけで基本の説明を表示して次の行を読まないこと、`EVALUATE` の文字列で改行の先を読まないこと、定義の中の `HELP` が実行時に名前を読むこと、組み込み語・構文語・利用者定義語の `HELP 語名`、知らない名前のエラー、`LICENSE` がMITの全文とCORE-MATHの表示を、ホストに渡す前はLFで出すこと |
| 名前の領域・イメージの大きさ | FORGET・MARKER・失敗した定義で名前の領域も戻ること、255文字の名前で名前の領域がいっぱいになると `OUT OF DICTIONARY !` でそれまでの語は使えること、イメージの大きさが保存する範囲の合計に等しく、ヒープの中身を保ちHEREより先は0で戻り、1バイト欠けると読み込まないこと、LOADで加えた語の名前とSEE・FORGET。辞書8192語・コード65535操作の上限でのエラーと巻き戻し。1バイト壊れたイメージ（チェックサムで検出し、辞書・コード・メモリが変わらないこと）、名前の位置や長さが壊れたイメージと `SIGIMG19` のイメージを何も変えずに拒否すること、名前の領域がないときのVARIABLEがHEREを戻すこと、CATCHで捨てた定義の名前の領域、名前のない語をはさんだLOADとFORGET、名前の領域が足りないLOADで何も変わらないこと |
| 定義の中の定義語 | 定義の中のVARIABLE・CONSTANT・FVARIABLE・FCONSTANT・VALUE・2CONSTANT・2VARIABLE・ARRAY、教材Level 31の `:` で始めて `POSTPONE ;` で終える語、名前がない場合と定義中の `:` のエラー、検索順序から外した定義語、DOES>を付けた変数、10の累乗に近い値のF. |
| 解釈中の[・PI・F. | 解釈中の `[`、PIのF.とF.RDP、2進数の値から正確に丸めるF.とF.S |
| locals visibility | IF・ELSE・THEN、BEGIN・UNTIL・WHILE・REPEAT、DO・?DO・LOOP・LEAVE、CASE・OFでの名前の見える範囲（Gforthで確かめた15例） |
| word lists（レビュー対応） | 回収したデータ領域に作ったMARKERのLOAD、[DEFINED]・[UNDEFINED]とローカル変数、INCLUDEの中での[IF]の読み飛ばしとファイルの終わり、複数の語彙にある同名語のFIND・LOCATE、語彙と:NONAME・DOES>を含むイメージの復元 |
| conditional compilation | [IF] [ELSE] [THEN]の選択・入れ子・行をまたぐ読み飛ばし・コンパイル中の使用、[DEFINED]・[UNDEFINED]、EVALUATEの中で終わらない[IF] |
| source files（レビュー対応） | EVALUATE内の名前待ちのエラー、CREATEとDOES>の間のINCLUDE／EVALUATE、読み込み中のファイル内でのMARKER、LOADで読み込んだMARKER、呼び出し元の定義を終えて別の定義を始めるファイル、閉じるのに失敗した場合の位置、WORDの255／256バイト、NAME>STRINGの8個のバッファ、SEEの入れ子・空の分岐・CASE |
| source files | INCLUDEの複数行定義・SOURCEFILENAME・SOURCELINE#・INCLUDED?、REQUIRE（自分自身・パラメータ付き）、入れ子の内側のエラー位置、定義途中のファイル終了、ファイルがない場合、すべてのファイルを閉じること、CATCHで捕捉した後の続き、入れ子の上限、MARKERによる語と履歴の巻き戻し、LOCATE、位置情報と履歴のイメージ復元・追加読み込み、実際のホストでのCR LFと4096／4097バイトの行 |
| parsing and dictionary words | 語の後の区切り1文字の消費とPARSE、文字列語の空白、WORDの数え付き文字列、FINDの即時語・未発見、FIND-NAME・NAME>INT・NAME>STRINGと無効な名前トークン、SEEの出力（制御構造、CREATE/DOES>、IMMEDIATE）、EVALUATEが端末の次の行を読まないこと、入力行の上限 |
| locals | スタック順の受け取り、定義途中・ループ内での宣言、TO、`\|`、W:/D:/F:/C:/XT:、W^/F^/C^のアドレス、LOCALS\|、`{: :}`、再帰と領域の解放、エラー後の解放、名前の有効範囲、定義外での拒否、追加読み込み後の実行 |
| file words | アクセス方法とストリーム番号、作成・書き込み・大きさ・位置変更・行単位の読み込み・閉じる、エラー時のiorとスタックの形、STDOUTへの書き込み、ホスト機能がない場合のエラー |

現行テストは主要経路を確認するものです。全ワード、すべての容量境界、各エラー条件を網羅したものではありません。

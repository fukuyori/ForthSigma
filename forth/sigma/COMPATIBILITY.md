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
| 例外・ファイル（段階5a） | THROW, R/O, W/O, R/W, STDIN, STDOUT, STDERR, OPEN-FILE, CREATE-FILE, CLOSE-FILE, READ-LINE, WRITE-LINE, WRITE-FILE, FILE-SIZE, REPOSITION-FILE | 教材Level 14、19、23、25、29。CATCHは未実装のため、0以外のTHROWはエラーとして報告します。 |
| 動的メモリ・動的文字列（段階5b） | ALLOCATE, FREE, RESIZE, $!, $@, $@LEN, $!LEN, $+!, C$+!, $., $DEL, $INS, $OVER, $FREE, $INIT, $SPLIT, $ITER, $TMP, $[], $[]!, $[]@, $[]#, $[]., $[]MAP, $[]FREE, $[]SLURP, $[]SLURP-FILE | 教材Level 14、29、30、32。ヒープは論理メモリの100000H〜1EFFFFH。 |
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
| 単一の論理メモリと上限 | 拡張 | 2 MiBの論理メモリ（データ領域は100000H未満、ヒープは100000H〜1EFFFFH、ローカル変数は1F0000H〜1FFFFFH）、各種固定容量を使います。歴史的な機種のメモリ配置とは異なります。 |
| SAVESYS | 拡張 | 現在の辞書・コンパイル済みコード・データ領域を含む単独実行ファイルを作成します。 |
| SAVE, LOAD | 拡張 | 利用者定義語の辞書イメージ（`SIGIMG06`）を保存し、読み込み時は既存定義の後ろへ追加します。`SIGIMG05` 以前のイメージは読み込めません。ヒープの内容は追加読み込みでは引き継がれません。定数やメモリに保存した実行トークンは、追加読み込みでは再配置されません。 |

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
| GforthのCATCH、残りのファイル語（READ-FILE、FILE-POSITION、BINなど）、INCLUDE、`$SLURP` などの残りの文字列語、語彙、条件付きコンパイル | 未実装 | 段階6などで対応予定（[決定事項](DECISIONS.md)）。 |
| Gforthの .R, U.R, D.R, UM*, UM/MOD, M*, C", /STRING, COMPARE, F.RDP, F>STR-RDP, F>BUF-RDP | 未実装 | 段階1〜3の対象外。 |

Z80の命令実行・エミュレーションはプロジェクトの対象外です。

## 自動回帰テストとの対応

zig build testで、現行コアの主要動作を次のテストで確認します（97件）。

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
| division by zero | /、MOD、/MODのエラー |
| floating point | リテラル認識、F.とF.Sの書式、非有限値、算術・比較・変換、関数、メモリ・変数・定数・配列、FINPUT、浮動小数点スタックのアンダーフロー |
| double-cell integers | 倍長整数リテラル、D+等の演算・比較・表示、2@/2!、2VARIABLE、2CONSTANT |
| pictured numeric output | <<# # #S HOLD HOLDS SIGN #> #>>、入れ子、対応しない #>> のエラー |
| strings | S"、S\"、.\"、.( の解釈時・コンパイル時の動作、一時バッファ、COUNT、PAD |
| string conversion and input | >NUMBER、S>NUMBER?、>FLOAT、D>F、F>D、ACCEPT、EVALUATE、KEY、KEY? |
| image round trip | 辞書イメージの保存・復元・追加読み込みでの語・浮動小数点定数・VALUE・2CONSTANT・文字列の再配置、定数に保存した実行トークンの完全復元、旧形式の拒否 |
| group A words | WITHINの境界と折り返し、2>R/2R>の順序と不足、ENDIF、PLACEの重なり・255バイト上限・メモリ末尾、STATEの保存アドレス経由の読み取り、ABORT、:NONAMEとその巻き戻し |
| host words | MS、UTIME、GETENV（未設定・空・長すぎる値）、SYSTEM（失敗）、ホスト機能がない場合のエラー、PAGEの出力 |
| THROW | 0の無視、-1の中断、標準コード・ファイルのior・その他のコードの報告（基数によらず10進） |
| heap | ALLOCATE・FREE・RESIZEの成功と失敗（ENOMEM、無効なアドレス）、解放した領域の再利用、全解放後のヒープの回復 |
| dynamic strings | 教材Level 14の例、自分自身を元にした連結・挿入、範囲外の削除・挿入・上書き、$SPLIT、$ITER、$TMP（入れ子、エラー後の出力復帰）、文字列配列、$[]SLURP／$[]SLURP-FILE、完全復元後のヒープ文字列 |
| tab separators | タブで区切ったソース、文字列語・CHARの直後のタブ |
| locals | スタック順の受け取り、定義途中・ループ内での宣言、TO、`\|`、W:/D:/F:/C:/XT:、W^/F^/C^のアドレス、LOCALS\|、`{: :}`、再帰と領域の解放、エラー後の解放、名前の有効範囲、定義外での拒否、追加読み込み後の実行 |
| file words | アクセス方法とストリーム番号、作成・書き込み・大きさ・位置変更・行単位の読み込み・閉じる、エラー時のiorとスタックの形、STDOUTへの書き込み、ホスト機能がない場合のエラー |

現行テストは主要経路を確認するものです。全ワード、すべての容量境界、各エラー条件を網羅したものではありません。

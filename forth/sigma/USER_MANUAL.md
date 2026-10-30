# FORTH/Σ Zig版 ユーザーマニュアル

この文書は、現在のZig移植版の使い方を説明します。誌面に掲載された機能でも、現在の実装にないものは含めていません。FORTH/Σの仕様整理は[仕様書](SPEC.md)、各語の掲載状況は[互換性一覧](COMPATIBILITY.md)を参照してください。

この版は、FORTH/Σのワードを残しながら、数値まわりと基本ワードをGforthに合わせています。セルは64ビット、真の値は-1、浮動小数点数は専用スタックで扱います。誌面の16ビット仕様との違いは[決定事項・保留事項](DECISIONS.md)にまとめています。

## 起動と入力

リポジトリのルートで次のようにビルド・起動します。

```powershell
zig build
.\zig-out\bin\sigma.exe
```

引数なしで起動すると、次の2行を表示して対話プロンプトになります。版番号はルートの `VERSION` ファイルの値です。引数を付けて起動したとき（引数の文字列を1回実行して終了します）は表示しません。

```text
FORTH/Sigma 0.1.0  MIT License
Type `help' for basic help
```

`HELP` は基本的な使い方を、`HELP 語名` は語のスタックの変化と1行の説明を英語で表示します（例: `HELP DUP`）。名前は同じ行から読みます（`EVALUATE` の文字列でも、改行の先は読みません）。定義の中に書いた `HELP` は、その定義を実行したときに名前を読みます。利用者が定義した語は、`SEE` で中身を見るよう案内します。知らない名前は `名前 ?` のエラーです。`LICENSE` はライセンスの全文と、組み込んでいるCORE-MATHの著作権表示を表示します。

入力行を処理すると、成功時には `OK` が表示されます。たとえば次の入力は、12の二乗を表示します。

```forth
: SQUARE DUP * ;
12 SQUARE . CR
```

結果は `144 ` です。`.` は数値の後ろに空白を1個付けますが、改行は付けません。改行が必要なときは `CR` を続けます。複数行のForthソースは標準入力から渡せます。

```powershell
Get-Content .\examples\demo.fs | .\zig-out\bin\sigma.exe
```

`BYE` で処理系を終了します。未定義語などのエラーが起きた場合は診断を表示し、すべてのスタックを空にして次の入力行へ戻ります。

`( ... )` は同じ行の `)` までを、`\` は行末までをコメントとして読み飛ばします。

## 数値

整数は64ビットの符号付き値です。範囲を超えた加算・減算・乗算は折り返します。`/`、`MOD`、`/MOD` は床関数除算（負の無限大方向への切り捨て）で、`-7 2 /` は `-4`、`-7 2 MOD` は `1` です。0で割るとエラー `DIVISION BY ZERO !` になります。最小値（-9223372036854775808）を-1で割ると、商が1セルに収まらないため、`MOD` も含めて `RESULT OUT OF RANGE !`（例外コード-11）になります（Gforthと同じ）。

`*/`（( n1 n2 n3 -- n4 )）と `*/MOD`（( n1 n2 n3 -- 余り 商 )）は、n1×n2を倍長で計算してからn3で割るので、積が1セルを超えても正しい商が得られます（床関数除算）。`U<` `U>` は符号なしで比べます。`?DUP` は0でなければ複製します。

比較の結果は、真が `-1`（全ビット1）、偽が `0` です。`IF` などの条件は0を偽、0以外を真として扱います。

数値の前に接頭辞を付けると、現在の基数に関係なく基数を指定できます。

| 書き方 | 意味 |
| --- | --- |
| `$FF` | 16進数 |
| `#10`、`&10` | 10進数 |
| `%101` | 2進数 |
| `'a'` | 文字コード |

### 倍長整数

数字の間に `.` を含む数は倍長整数（128ビット）になり、スタックに下位セル、上位セルの順で2個積まれます。`123.` は123、`12345.123` は12345123です（小数点の位置は記録しません）。

```forth
1234567890000000000. 9876543210000000000. D+ D.   \ 11111111100000000000
-7 S>D DABS D.                                    \ 7
CREATE BIGNUM 2 CELLS ALLOT
12345678901234567890 1 BIGNUM 2!
BIGNUM 2@ D.                                      \ 30792422974944119506
```

| 用途 | ワード |
| --- | --- |
| 変換 | `S>D`, `D>S`, `D>F`, `F>D` |
| 算術 | `D+`, `D-`, `DNEGATE`, `DABS` |
| 比較 | `D0=`, `D0<`, `D=`, `D<` |
| 表示 | `D.` |
| 単長と倍長の乗除算 | `M*`（( n1 n2 -- d )）、`UM*`（( u1 u2 -- ud )）、`UM/MOD`（( ud u -- 余り 商 )、符号なし）、`FM/MOD`（( d n -- 余り 商 )、床関数除算）、`SM/REM`（( d n -- 余り 商 )、0方向への切り捨て） |

`*/` `*/MOD` `UM/MOD` `FM/MOD` `SM/REM` は、0で割ると `DIVISION BY ZERO !`、商が1セルに収まらないと `RESULT OUT OF RANGE !`（例外コード-11）になります。Gforthと同じです。
| メモリ・定義 | `2@`, `2!`, `2VARIABLE 名前`, `値 2CONSTANT 名前`, `値 2VALUE 名前`, `2LITERAL` | `2VALUE` の名前は値を積み、`値 TO 名前` で変更できます。`2LITERAL` は定義の中で倍長整数を埋め込みます。 |
| その他 | `D2*`, `D2/`, `DMAX`, `DMIN`, `M+`, `M*/`, `DU<`, `2ROT`, `D.R` | `M*/`（( d1 n1 +n2 -- d2 )）はd1×n1を3セルで計算してからn2で割ります（床関数除算。Gforthと同じく、n2は符号なしとして扱い、商が2セルに収まらないと折り返します）。`D2/` は負の無限大方向へ丸めます（算術シフト）。`M+` は倍長整数に単長整数を加えます。`DU<` は符号なしで比べます。`2ROT` は3組目の2セルを先頭へ移します。`D.R`（( d 幅 -- )）は幅に右寄せし、空白を付けません。 |

## ワードの定義と辞書

利用者定義語は `: 名前 ... ;` で作ります。ワード名は名前全体で照合し、ASCII英字の大文字・小文字は区別しません。既存名を再定義すると警告が出ますが、新しい定義が優先されます。組み込み語と同じ名前で定義した場合も、利用者の定義が優先されます。

```forth
: DOUBLE 2 * ;
21 DOUBLE . CR
```

`WORDS` は現在の辞書の登録語を表示します。`FORGET 名前` は指定語と、それより後に登録された利用者定義語を削除します。そのため、後から同名定義を追加したあと新しい方を `FORGET` すると、古い定義が再び使われます。削除対象より後に定義した別の語も一緒に削除される点に注意してください。

`IMMEDIATE` は直前に定義した語を即時語にします。`POSTPONE 名前` は、定義中の語に「名前のコンパイル」を組み込みます。`RECURSE` は定義中の語自身を呼び出します。

## 変数・定数・配列

```forth
VARIABLE COUNT
10 COUNT !
COUNT @ . CR
42 CONSTANT ANSWER
ANSWER . CR
5 VALUE LIMIT
8 TO LIMIT
4 ARRAY TABLE
CREATE BUF 16 ALLOT
```

`VARIABLE`（別名 `VAR`）は変数を作り、`CONSTANT`（別名 `CONST`）はスタック先頭の値を定数として登録します。`VALUE` は値を返す語を作り、`TO 名前` で値を変更します。`ARRAY` は要素数を受け取り、1要素8バイトの配列を作ります。配列添字は0からで、`添字 配列名 A@`、`値 添字 配列名 A!` で読み書きします。`CREATE 名前` はデータ領域の現在位置を返す語を作ります。

1セルは8バイトです。`CELLS` で要素数をバイト数に変換できます。メモリ操作ではアドレスと範囲を利用者が管理してください。論理メモリの外を読み書きすると `INVALID MEMORY ADDRESS !` になります。

## 制御構造

制御構造は定義内で使います。

```forth
: ABS-VALUE DUP 0 < IF NEGATE THEN ;
: COUNT-UP 5 0 DO I . LOOP ;
: GRADE CASE 1 OF ." ONE" ENDOF 2 OF ." TWO" ENDOF ." OTHER" ENDCASE ;
```

利用できる構造は次のとおりです。

- `IF ... ELSE ... THEN`
- `BEGIN ... END`（`END` の別名 `UNTIL`）、`BEGIN ... AGAIN`、`BEGIN ... WHILE ... REPEAT`
- `CASE ... OF ... ENDOF ... ENDCASE`
- `DO ... LOOP`、`DO ... +LOOP`、`?DO`

`IF ... ENDIF` も使えます（`ENDIF` は `THEN` の別名）。`DO` は開始値と終値が等しくても本体を1回実行します（FORTH/Σの仕様）。`?DO` は等しい場合に本体を実行しません。`LEAVE` は直ちにループを抜けます。ループの途中で `EXIT` するときは、先に `UNLOOP` でループを片付けます。`I`、`J`、`K` は内側からそれぞれ1段目、2段目、3段目のループ添字を返します。

## 浮動小数点数

浮動小数点数は64ビット（倍精度）で、整数とは別の浮動小数点スタックに積みます。ソース中では、基数が10のときに `e` または `E` を含む数が浮動小数点数になります。

```forth
1E 2E F+ F.          \ 3.
1.5e0 F.             \ 1.5
3.1415926535E FCONSTANT PI
: AREA ( f: r -- f: area ) FDUP F* PI F* ;
5E AREA F.           \ 78.5398163375
10 S>F 4E F/ F>S .   \ 2
```

`1.5` のように `E` を含まない数は浮動小数点数として扱いません。

| 用途 | ワード | 説明 |
| --- | --- | --- |
| 表示 | `F.`, `FE.`, `FS.`, `F.S`, `F?` | `F.` は `PRECISION` 桁（初期値15）を指数なしで表示し、末尾に空白を付けます（`3.`、`0.5`）。`FS.` は先頭1桁と小数点と指数（`1.23456780000000E4`）、`FE.` は指数を3の倍数にして（`12.3456780000000E3`）、どちらも `PRECISION` 桁を末尾の0も含めて表示します。無限大とNaNは名前（`infinity` `NaN`）だけを、空白を付けずに表示します（Gforthと同じ）。`F.S` は個数の後に上の9個を、それぞれ `14 0 17 F.RDP` と同じ形（`3.0000000000E0`）で表示します。 |
| スタック | `FDROP`, `FDUP`, `FSWAP`, `FOVER`, `FROT`, `F-ROT`, `FNIP`, `FTUCK`, `FPICK`, `FDEPTH` | `FPICK` の位置と `FDEPTH` の結果は整数スタックを使います。 |
| 算術 | `F+`, `F-`, `F*`, `F/`, `FNEGATE`/`FMINUS`, `FABS`, `FMAX`, `FMIN` | 0で割ると無限大またはNaNになります。 |
| 関数 | `FSQRT`, `FEXP`, `FLN`, `FSIN`, `FCOS`, `FTAN`, `FSINCOS`, `FASIN`, `FACOS`, `FATAN`, `FATAN2`, `FSINH`, `FCOSH`, `FTANH`, `FASINH`, `FACOSH`, `FATANH`, `FEXPM1`, `FLNP1`, `FLOG`, `FALOG`, `F**` | 三角関数はラジアンです。`FSINCOS` は ( f: r -- 正弦 余弦 )、`FATAN2` は ( f: y x -- 角度 )、`F**` は ( f: x y -- xのy乗 )、`FLOG` は常用対数、`FALOG` は10のr乗、`FEXPM1` はe^r - 1、`FLNP1` はln(1 + r)です。`FSQRT` 以外は正しく丸めた値で、どのOSでも同じ結果です。 |
| 丸め | `FLOOR`, `FTRUNC`, `FROUND` | 整数に丸めます。`FLOOR` は負の無限大方向、`FTRUNC` は0方向、`FROUND` は最も近い整数（ちょうど中間なら偶数）です。 |
| 比較 | `F=`, `F<>`, `F<`, `F>`, `F<=`, `F>=`, `F0=`, `F0<>`, `F0<`, `F0>`, `F0<=`, `F0>=`, `F~` | 結果（-1または0）は整数スタックに積みます。`F~`（( f: r1 r2 r3 -- ) ( -- flag )）は、r3が正なら差の絶対値がr3より小さいか、0ならビットまで同じか（`0e` と `-0e` は違い、同じNaNは等しい）、負なら差が \|r3\|×(\|r1\|+\|r2\|) より小さいかを調べます。 |
| メモリ | `F@`, `F!`, `F,`, `F+!`, `FLOATS`, `FLOAT+`, `DF@`, `DF!`, `DFLOATS`, `DFLOAT+`, `SF@`, `SF!`, `SFLOATS`, `SFLOAT+`, `FALIGN`, `FALIGNED`, `DFALIGN`, `DFALIGNED`, `SFALIGN`, `SFALIGNED` | 1個8バイトです。`DF` の付く語は同じ8バイトの値、`SF` の付く語は4バイト（単精度）の値を扱います（`SF!` は単精度に丸め、範囲を超えると無限大になります）。`FALIGN` と `DFALIGN` はHEREを8の倍数に、`SFALIGN` は4の倍数に切り上げます。 |
| 定義 | `FVARIABLE 名前`, `値 FCONSTANT 名前`, `値 FVALUE 名前`, `要素数 FARRAY 名前`, `FA@`, `FA!` | `FVALUE` の名前は値を浮動小数点スタックに積み、`値 TO 名前` で変更できます。 `FARRAY` の読み書きは `添字 配列名 FA@`、`添字 配列名 FA!` です。 |
| 変換・入力 | `S>F`, `F>S`, `FINPUT` | `F>S` は0方向へ切り捨てます。`FINPUT` は端末から数値を1個読み取ります（`E` は省略可能）。 |
| 数字の取り出し | `REPRESENT` | ( addr u -- n flag1 flag2 ) ( f: r -- ) の形で、rの有効数字u桁を（2進数の値から正確に丸めて）addrに書き、指数n（r = 0.数字 × 10のn乗）、負かどうか、有限かどうかを返します。無限大とNaNは名前をu文字までに切って書きます（Gforthと同じ）。 |
| 表示の桁数 | `PRECISION`, `SET-PRECISION` | `F.` `FE.` `FS.` の桁数を返す・設定します。表示は1〜1000桁の範囲で行います（Gforthは1000桁まで表示し、0以下や4000では異常終了します）。`PRECISION` は設定した値をそのまま返します。 |
| 書式付き出力 | `F.RDP`, `F>STR-RDP`, `F>BUF-RDP` | ( r 幅 小数桁 最低有効桁 -- ) の形で、幅に右寄せして表示（`F.RDP`）、文字列で返す（`F>STR-RDP` は ( -- addr u )、次の数値書式で上書きされます）、指定したバッファに書き込みます（`F>BUF-RDP` は ( r addr 幅 小数桁 最低有効桁 -- )）。例: `12345.6789E 10 2 7 F.RDP` は `  12345.68`、最低有効桁を8にすると `1.234568E4`。固定小数点で有効桁が足りないか、整数部が幅に収まらなければ指数表記、それも入らなければ `*` で埋めます。Gforthと同じ結果です。 |

## 入出力と基数

| 用途 | ワード | 説明 |
| --- | --- | --- |
| 数値出力 | `.`, `U.`, `C.`, `?`, `.S`, `.R`, `U.R` | `.R` `U.R` 以外は数値の後ろに空白を付けます。`.R`（( n 幅 -- )）と `U.R`（( u 幅 -- )）は幅に右寄せし、空白を付けません。数値が幅より長ければそのまま表示します。`U.` は符号なし、`C.` は下位8ビット、`?` はアドレスの内容、`.S` は個数と上の9個（`<個数> 値 ...`）を表示します。ゼロ埋めはしません。 |
| 文字出力 | `ECHO`/`EMIT` | スタック先頭の下位8ビットを文字として出力します。 |
| 文字列出力 | `TYPE`, `."..."` | `TYPE` はアドレスと文字数を受け取り、文字列を出力します。`."..."` は移植版の拡張です。 |
| 改行・空白 | `CR`, `SPACE`, `SPCES`/`SPACES`, `BL` | 改行、1個の空白、指定数の空白を出力します。`BL` は空白の文字コードを積みます。 |
| 文字コード | `CHAR 文字`, `[CHAR] 文字` | 次の語の先頭文字の文字コードを積みます。定義内ではリテラルとしてコンパイルします。 |
| 数値入力 | `INPUT` | 端末から整数を1個読み取ってスタックへ積みます。 |
| 基数変更 | `HEX`, `DEC`/`DECIMAL`, `OCT` | 数値入出力の基数を16進、10進、8進に切り替えます。初期値は10進です。 |
| 基数参照 | `BASE` | 基数値（2〜36）を保持する論理メモリのアドレスをスタックへ積みます。 |

誌面由来の `"..."` は定義内でコンパイルして使う文字列語です。実行するとアドレス、文字数の順にスタックへ積むため、そのまま `TYPE` に渡せます。

## 文字列

```forth
S" Hello, Forth!" TYPE CR
S\" Hello\tWorld!" TYPE CR
.\" Welcome,\nthe entire land" CR
.( 定義中でもすぐ表示 )
CREATE BUF 20 ALLOT
S" Forth" TUCK BUF SWAP MOVE BUF SWAP TYPE
```

| ワード | スタック | 説明 |
| --- | --- | --- |
| `S" ..."` | ( -- addr u ) | 文字列のアドレスと長さを積みます。対話中に使った文字列は一時バッファに置かれ、4個まで同時に有効です。定義内ではデータ領域に保存されます。最大255文字です。 |
| `S\" ..."` | ( -- addr u ) | `\n`（改行）、`\t`（タブ）、`\"`、`\\`、`\xHH` などのエスケープを解釈します。 |
| `.\" ..."` | ( -- ) | エスケープを解釈して表示します。 |
| `.( ... )` | ( -- ) | `)` までをすぐに表示します。 |
| `COUNT` | ( c-addr -- addr u ) | 先頭バイトを長さとする文字列を、アドレスと長さに変換します。 |
| `PAD` | ( -- addr ) | 作業用の4096バイトの領域のアドレスです。 |
| `ACCEPT` | ( addr u -- u2 ) | 端末から1行読み、最大u文字をaddrに格納して文字数を返します。 |
| `EVALUATE` | ( addr u -- ) | 文字列をForthの入力として解釈します。 |
| `KEY` | ( -- c ) | 1文字読み取ります。 |
| `KEY?` | ( -- flag ) | 読み取れる文字があるかを返します。対話端末では入力があるまで待ちます。 |
| `EKEY`, `EKEY?`, `EKEY>CHAR` | ( -- u )、( -- flag )、( u -- u false \| c true ) | `EKEY` と `EKEY?` は `KEY` と `KEY?` と同じです（ファンクションキーなどは解釈しません）。`EKEY>CHAR` は0〜255なら文字として真を返します。 |
| `>NUMBER` | ( ud addr u -- ud2 addr2 u2 ) | 数字を変換し、変換できなかった残りを返します。 |
| `S>NUMBER?` | ( addr u -- d flag ) | 文字列を整数（倍長）に変換し、成否を返します。 |
| `>FLOAT` | ( addr u -- flag ) ( f: -- r ) | 文字列を浮動小数点数に変換します。`E` は省略できます。成功時だけ浮動小数点スタックに積みます。 |

## 数値の書式（pictured numeric output）

`<<#` と `#>>` の間で、数値を右端から1桁ずつ文字列にします。

```forth
: dollars-and-cents ( u -- )
  0 <<# # # [CHAR] . HOLD #S [CHAR] $ HOLD #> TYPE SPACE #>> ;
1234 dollars-and-cents   \ $12.34
: my-. ( n -- ) S>D SWAP OVER DABS <<# #S ROT SIGN #> TYPE SPACE #>> ;
-123 my-.                \ -123
```

| ワード | スタック | 説明 |
| --- | --- | --- |
| `<#` | ( -- ) | 変換を開始し、入れ子を含む保持領域をすべて空にします。 |
| `<<#` | ( -- ) | 入れ子にできる変換を開始します（16段まで）。`#>>` と対にします。 |
| `#` | ( ud -- ud2 ) | 最下位の1桁を変換します。 |
| `#S` | ( ud -- 0 0 ) | 残りの桁をすべて変換します。 |
| `HOLD`, `HOLDS` | ( c -- )、( addr u -- ) | 文字または文字列を先頭に加えます。 |
| `SIGN` | ( n -- ) | nが負なら `-` を加えます。 |
| `#>` | ( ud -- addr u ) | 変換を終了し、文字列を返します。 |
| `#>>` | ( -- ) | `<<#` で始めた保持領域を解放します。 |

## その他のワード

```forth
5 0 10 WITHIN .                    \ -1
S" hello" PAD PLACE PAD COUNT TYPE  \ hello
S" abc" S" abd" COMPARE .          \ -1
S" hello world" S" wor" SEARCH . TYPE  \ -1 world
S" hello" 2 /STRING TYPE           \ llo
S" hi   " -TRAILING TYPE           \ hi
S" a,b,c" CHAR , SCAN TYPE         \ ,b,c
S" hello" S" he" STRING-PREFIX? .  \ -1
: GREETING [ S" hi there" ] SLITERAL ;
:NONAME DUP * ; CONSTANT SQUARE
7 SQUARE EXECUTE .                  \ 49
S" HOME" GETENV TYPE
S" dir" SYSTEM
```

| ワード | スタック | 説明 |
| --- | --- | --- |
| `WITHIN` | ( n lo hi -- flag ) | lo ≦ n < hi なら真を返します。範囲は符号なしの差で判定するため、上限と下限が逆でも一周する範囲として扱います。 |
| `2>R`, `2R>` | ( x1 x2 -- )、( -- x1 x2 ) | 2個のセルを順序を保ってリターンスタックとの間で移します。 |
| `2R@` | ( -- x1 x2 ) | `2>R` で移した2個のセルを、リターンスタックに残したまま複写します。 |
| `N>R`, `NR>` | ( x1 … xn n -- )、( -- x1 … xn n ) | n個のセルと個数nを、順序を保ってリターンスタックとの間で移します。 |
| `ALIGN`, `UNUSED` | ( -- )、( -- u ) | `ALIGN` はHEREをセルの大きさの倍数に切り上げます。`UNUSED` はデータ領域の残りのバイト数です。 |
| `PLACE` | ( addr u c-addr -- ) | 文字列を、先頭バイトに長さを持つ形でc-addrへ格納します。最大255文字です。 |
| `C" ..."` | ( -- c-addr ) | 定義の中で使い、先頭バイトに長さを持つ文字列のアドレスを積みます（定義の外では `COMPILE MODE ERROR !`）。 |
| `BUFFER: 名前` | ( u -- ) | uバイトのデータ領域を確保し、名前はそのアドレスを積みます。中身は初期化しません。 |
| `DUMP` | ( addr u -- ) | addrからuバイトを、1行16バイトずつ16進数と文字で表示します（32〜126以外の文字は `.`）。アドレスは論理メモリのアドレスです。 |
| `COMPARE` | ( addr1 u1 addr2 u2 -- n ) | 2つの文字列を先頭から1バイトずつ符号なしで比べ、1つ目が前なら-1、等しければ0、後なら1を返します。片方がもう片方の先頭部分なら、短いほうが前です。 |
| `SEARCH` | ( addr1 u1 addr2 u2 -- addr3 u3 flag ) | 1つ目の文字列から2つ目の文字列を探します。見つかれば、見つかった位置から後ろの文字列と真を、見つからなければ1つ目の文字列と偽を返します。2つ目が空なら、先頭で見つかったことになります。 |
| `/STRING` | ( addr u n -- addr+n u-n ) | 文字列の先頭からn文字を除きます。nがuを超えていても確かめません（Gforthと同じ）。 |
| `-TRAILING` | ( addr u -- addr u' ) | 文字列の末尾の空白を除きます。タブは除きません。 |
| `CHAR+`, `CHARS` | ( addr -- addr+1 )、( n -- n ) | 文字1つ分（1バイト）を加えます。`CHARS` はn文字分のバイト数（nのまま）を返します。 |
| `BOUNDS` | ( addr u -- addr+u addr ) | 文字列を `DO ... LOOP` の終わりと始めに変えます（`BOUNDS ?DO I C@ ... LOOP`）。 |
| `BLANK` | ( addr u -- ) | uバイトを空白にします。 |
| `CMOVE>` | ( from to u -- ) | uバイトを、高いアドレスから低いアドレスへ1バイトずつ写します。 |
| `SCAN` | ( addr u c -- addr' u' ) | 文字cを探し、見つかった位置から後ろの文字列を返します。見つからなければ長さ0です。空白はタブに一致しません。 |
| `SKIP` | ( addr u c -- addr' u' ) | 先頭に続く文字cを飛ばし、残りの文字列を返します。 |
| `STR=` | ( addr1 u1 addr2 u2 -- flag ) | 2つの文字列が同じなら真を返します。 |
| `STRING-PREFIX?` | ( addr1 u1 addr2 u2 -- flag ) | 1つ目の文字列が2つ目の文字列で始まるなら真を返します。 |
| `+PLACE` | ( addr u c-addr -- ) | 数え付き文字列の後ろに文字列を加えます。合わせて255バイトで止まります。 |
| `SLITERAL` | コンパイル時 ( addr u -- )、実行時 ( -- addr u ) | 定義の中で使い、文字列（255バイトまで）を定義に埋め込みます。 |
| `STATE` | ( -- addr ) | コンパイル中は-1、解釈中は0を保持するセルのアドレスです。書き込んでも状態は変わりません。 |
| `:NONAME ... ;` | ( -- xt ) | 名前のない定義を作り、実行トークンを積みます。 |
| `ABORT` | ( -- ) | スタックを空にして入力待ちに戻ります。メッセージは表示しません。 |
| `QUIT` | ( -- ) | 実行中の処理と読み込み中のファイルをやめて、入力待ちに戻ります。データスタックと浮動小数点スタックはそのまま残ります。`CATCH` では捕まえません（Gforthと同じ）。 |
| `ENVIRONMENT?` | ( addr u -- false \| 値 true ) | `MAX-N` `MAX-D` `/HOLD` `/PAD` `STACK-CELLS` `RETURN-STACK-CELLS` `FLOATING-STACK` `#LOCALS` `WORDLISTS` `MAX-FLOAT` `ADDRESS-UNIT-BITS` `FLOORED` `MAX-CHAR` `/COUNTED-STRING` などの問い合わせに、この処理系の値を返します。それ以外の名前（語群の名前を含む）は偽です。 |
| `ABORT" ..."` | ( flag -- ) | 定義の中で使い、flagが0でなければ文字列を表示して中断します（`THROW` の-2）。`CATCH` で捕まえると-2を返し、表示しません。 |
| `MS` | ( n -- ) | nミリ秒待ちます。 |
| `UTIME` | ( -- ud ) | 1970年1月1日からの経過時間をマイクロ秒単位の倍長整数で返します。 |
| `TIME&DATE` | ( -- 秒 分 時 日 月 年 ) | 地方時の日時を返します。月は1〜12、年は西暦です。 |
| `PAGE` | ( -- ) | 画面を消去し、カーソルを左上へ移します。 |
| `AT-XY` | ( x y -- ) | カーソルをx列、y行（どちらも0から）へ移します。Gforthと同じエスケープシーケンスを出力します。 |
| `GETENV` | ( addr u -- addr2 u2 ) | 環境変数の値を返します。未設定なら `0 0` です。結果は次の `GETENV` まで有効で、3072バイトを超える値は `STRING TOO LONG !` になります。 |
| `SYSTEM` | ( addr u -- ) | 文字列をシェルのコマンドとして実行します（Windowsは `cmd.exe`）。コマンドの終了コードは返しません（`$?` で取り出せます）。 |
| `$?` | ( -- n ) | 最後に実行した `SYSTEM` の状態です。LinuxとmacOSではGforthと同じく `system` の返す値（終了コードの256倍）、Windowsでは終了コードです。 |
## ローカル変数

```forth
: SUM3 { a b c -- sum } a b + c + ;
1 2 3 SUM3 .                          \ 6
: COUNTDOWN { n -- } BEGIN n . n 1- TO n n 0= UNTIL ;
5 COUNTDOWN                           \ 5 4 3 2 1
: AREA { F: w F: h -- F: a } w h F* ;
2E 3E AREA F.                         \ 6.
: SWAP2 { W^ a W^ b } b @ a @ ;       \ W^ はアドレスを積みます
```

`{` と `}` の間に名前を書くと、スタックの値をその名前で使えます。最後の名前がスタックの一番上の値を受け取ります。

| 書き方 | 意味 |
| --- | --- |
| `{ a b -- c }` | aとbをスタックから受け取ります。`--` から `}` まではコメントです。 |
| `{ a \| b c }` | `\|` の後のbとcは0で始まり、スタックからは受け取りません。 |
| `W:`（省略可）, `D:`, `F:`, `C:` | 名前を書くと、それぞれセル、倍長整数、浮動小数点数、文字の値を積みます。`TO 名前` で値を変更できます。 |
| `XT:` | 名前を書くと、受け取った実行トークンを実行します。 |
| `W^`, `D^`, `F^`, `C^`, `XT^` | 名前を書くと、値を入れた場所のアドレスを積みます。`@` `!` `F@` などで読み書きします。 |
| `{: a b :}` | 標準Forthの書き方です。`{ }` と同じです。 |
| `LOCALS\| a b \|` | 標準Forthの古い書き方です。最初の名前（a）がスタックの一番上を受け取ります。 |

ローカル変数は定義の途中や制御構造の中でも宣言できます。名前を使えるのは、必ずその宣言を通ってからたどり着く場所だけです（Gforthと同じ）。たとえば `IF` の中で宣言した名前は、`ELSE` の側や `THEN` の後では使えません。`BEGIN ... UNTIL` や `DO ... LOOP` の本体で宣言した名前は、ループの後でも使えます（`?DO` や `WHILE` の後で宣言した名前は使えません）。再帰呼び出しでは呼び出しごとに別の値を持ちます。アドレスの型で得たアドレスは、その定義を抜けると無効になります。定義の外では使えません。

## ファイルと例外

```forth
: MAKE-FILE
  S" data.txt" W/O CREATE-FILE THROW >R
  S" line 1" R@ WRITE-LINE THROW
  S" line 2" R@ WRITE-LINE THROW
  R> CLOSE-FILE THROW ;
: SHOW-FILE ( addr u -- )
  R/O OPEN-FILE THROW
  BEGIN PAD 80 2 PICK READ-LINE THROW
  WHILE CR PAD SWAP TYPE
  REPEAT DROP CLOSE-FILE THROW ;
MAKE-FILE S" data.txt" SHOW-FILE
```

ファイル語は結果のほかに **ior**（0なら成功、0以外ならエラー番号）を積みます。`THROW` に渡すと、エラーのときだけ処理を中断してメッセージを表示します（例: `NO SUCH FILE OR DIRECTORY !`）。

| ワード | スタック | 説明 |
| --- | --- | --- |
| `R/O`, `W/O`, `R/W` | ( -- fam ) | 読み取り専用、書き込み専用、読み書き両用のアクセス方法です。 |
| `OPEN-FILE` | ( addr u fam -- fileid ior ) | 既存のファイルを開きます。`W/O` で開いても内容は消えません。 |
| `CREATE-FILE` | ( addr u fam -- fileid ior ) | ファイルを新しく作ります。既にあれば中身を空にします。 |
| `CLOSE-FILE` | ( fileid -- ior ) | ファイルを閉じます。 |
| `READ-LINE` | ( addr u fileid -- u2 flag ior ) | 1行を最大u文字読み、文字数を返します。行末の改行は含みません。ファイルの終わりではflagが偽になります。 |
| `READ-FILE` | ( addr u fileid -- u2 ior ) | 最大uバイトを、改行も含めてそのまま読みます。ファイルの終わりではu2が0になります。`STDIN` からも読めます（Windowsでも、パイプやリダイレクトからはそのまま読みます。コンソールからの入力は、Enterが改行1文字になります）。 |
| `WRITE-LINE` | ( addr u fileid -- ior ) | 文字列と改行を書き込みます（WindowsはCR LF、それ以外はLF）。 |
| `WRITE-FILE` | ( addr u fileid -- ior ) | 文字列を改行なしで書き込みます。 |
| `FILE-SIZE` | ( fileid -- ud ior ) | ファイルの大きさ（バイト数、倍長整数）を返します。 |
| `REPOSITION-FILE` | ( ud fileid -- ior ) | 読み書きの位置を移動します。`FILE-SIZE` の結果を渡すと末尾へ移動し、追記できます。 |
| `FILE-POSITION` | ( fileid -- ud ior ) | 読み書きの位置を返します。 |
| `RESIZE-FILE` | ( ud fileid -- ior ) | ファイルをudバイトに切り詰めるか、0のバイトで伸ばします。読み書きの位置は変わりません。 |
| `FLUSH-FILE` | ( fileid -- ior ) | たまっている書き込みをファイルに書き出します。 |
| `DELETE-FILE` | ( addr u -- ior ) | 名前のファイルを削除します。 |
| `RENAME-FILE` | ( addr1 u1 addr2 u2 -- ior ) | 1つ目の名前のファイルを2つ目の名前に変えます。2つ目の名前のファイルがあれば置き換えます（Windowsでも同じ）。 |
| `FILE-STATUS` | ( addr u -- x ior ) | 名前のファイルがあればiorは0で、xは開ける方法（`R/O` `W/O` `R/W`）です。なければ-514です。 |
| `BIN` | ( fam -- fam' ) | バイナリのファイルを指定します。ファイルはいつもバイトのまま読み書きするので、動きは変わりません。 |
| `INCLUDE-FILE` | ( fileid -- ) | 開いたファイルを解釈し、閉じます。エラーの表示では、ファイル名は `*file*` になります。 |
| `SLURP-FILE` | ( addr u -- addr' u' ) | 名前のファイルを丸ごと、改行も含めてそのまま読み、`ALLOCATE` で確保した領域に置きます。使い終わったら `FREE` で解放します。開けなければ `THROW` します。 |
| `STDIN`, `STDOUT`, `STDERR` | ( -- fileid ) | 標準入力、標準出力、標準エラー出力のファイル番号です。 |
| `THROW` | ( n -- ) | nが0なら何もしません。-1なら `ABORT` と同じです。それ以外は、`CATCH` で捕まえていなければエラーとして表示し、入力待ちに戻ります。 |
| `CATCH` | ( xt -- 0 \| n ) | xtを実行し、正常に終われば0を、`THROW` やエラーが起きればその番号を積みます。例外のときはスタックの深さをCATCHの時点に戻します。スタック不足は-4、ゼロ除算は-10、未定義語は-13です。 |

同時に開けるファイルは64個までです。終了時に開いたままのファイルは閉じます。`CATCH` で `THROW` を捕まえられます（下の表）。

## 動的メモリと動的文字列

```forth
VARIABLE MYSTRING
S" Hello, World!" MYSTRING $!
7 MYSTRING $!LEN  S" land" MYSTRING $+!  '!' MYSTRING C$+!
MYSTRING $.                     \ Hello, land!
VARIABLE NAMES
S" Alice" 0 NAMES $[]!  S" Bob" 1 NAMES $[]!
NAMES $[].                      \ Alice と Bob を1行ずつ表示
100 CELLS ALLOCATE THROW  FREE THROW
```

文字列変数は `VARIABLE` で作ります。中身はヒープに置かれ、長さに合わせて自動的に確保・解放されます。

| ワード | スタック | 説明 |
| --- | --- | --- |
| `ALLOCATE` | ( u -- addr ior ) | uバイトの領域を確保します。足りなければiorが-524です。 |
| `FREE` | ( addr -- ior ) | `ALLOCATE` で確保した領域を解放します。 |
| `RESIZE` | ( addr u -- addr2 ior ) | 領域の大きさを変えます。内容は保たれ、アドレスが変わることがあります。 |
| `$!` | ( addr u $var -- ) | 文字列を文字列変数に格納します。 |
| `$@`, `$@LEN` | ( $var -- addr u )、( $var -- u ) | 文字列、または長さを返します。空の変数では `0 0`、`0` です。 |
| `$!LEN` | ( u $var -- ) | 長さを変えます。伸ばした部分は0です。 |
| `$+!`, `C$+!` | ( addr u $var -- )、( c $var -- ) | 文字列、または1文字を末尾に追加します。 |
| `$.` | ( $var -- ) | 文字列を表示します。 |
| `$INS`, `$OVER` | ( addr u $var off -- ) | off文字目に挿入、または上書きします。 |
| `$DEL` | ( $var off u -- ) | off文字目からu文字を削除します。 |
| `$FREE`, `$INIT` | ( $var -- ) | 文字列を解放して変数を0に、または空の文字列にします。 |
| `$SPLIT` | ( addr u c -- addr u1 addr2 u2 ) | 最初の文字cの前後に分けます。 |
| `$ITER` | ( $var c xt -- ) | 文字cで区切った各部分 ( addr u ) についてxtを実行します。 |
| `$TMP` | ( xt -- addr u ) | xtを実行し、その間の出力を文字列として返します。 |
| `$EXEC` | ( xt $var -- ) | xtを実行し、その間の出力を動的文字列の後ろに加えます。xtが `THROW` しても出力先は元に戻ります。 |
| `$+!LEN` | ( u $var -- addr ) | 文字列をuバイト長くし、加えた部分のアドレスを返します。 |
| `$OFF` | ( $var -- ) | `$FREE` と同じです（Gforthの古い名前）。 |
| `$VARIABLE 名前`, `$[]VARIABLE 名前` | ( -- ) | 動的文字列・文字列配列のための変数を作ります。`VARIABLE` と同じです。 |
| `$[]!`, `$[]@` | ( addr u n $[]var -- )、( n $[]var -- addr u ) | 文字列配列のn番目に格納、または取り出します。 |
| `$[]#`, `$[].` | ( $[]var -- n )、( $[]var -- ) | 要素数を返す、または全要素を1行ずつ表示します。 |
| `$[]MAP` | ( $[]var xt -- ) | 各要素 ( addr u ) についてxtを実行します。 |
| `$[]FREE` | ( $[]var -- ) | 全要素と配列を解放します。 |
| `$[]SLURP`, `$[]SLURP-FILE` | ( fileid $[]var -- )、( addr u $[]var -- ) | ファイルを1行ずつ配列に読み込みます。 |
| `$[]+!`, `$+[]!` | ( addr u n $[]var -- )、( addr u $[]var -- ) | 配列のn番目の文字列の後ろに加えます。`$+[]!` は新しい最後の要素として置きます。 |
| `$SLURP-FILE` | ( addr u $var -- ) | 名前のファイルを丸ごと動的文字列に読み込み、それまでの内容と置き換えます。 |
| `$+SLURP-FILE` | ( addr u $var -- ) | 名前のファイルを丸ごと動的文字列の後ろに加えます。 |
| `$SLURP`, `$+SLURP` | ( fileid $var -- ) | 開いたファイルを今の位置から終わりまで読み、動的文字列と置き換えます（`$+SLURP` は後ろに加えます）。ファイルは閉じません。 |
| `$SLURP-LINE` | ( fileid $var -- flag ) | 次の1行を（改行を除いて）動的文字列に読み込みます。ファイルの終わりではflagが0で、文字列は空になります。 |

ヒープは896 KiBです。`SAVESYS` で作った実行ファイルにはヒープの内容も保存されますが、`LOAD` では引き継がれません。

## 辞書の探索と入力の解析

```forth
: SQUARE ( n -- n^2 ) DUP * ;
SEE SQUARE                         \ : SQUARE / DUP * / ; と表示
S" DUP" FIND-NAME NAME>STRING TYPE \ DUP
: SHOW BL WORD FIND IF EXECUTE . ELSE COUNT TYPE ." ?" THEN ;
42 CONSTANT ANSWER
SHOW ANSWER                        \ 42
```

| ワード | スタック | 説明 |
| --- | --- | --- |
| `SEE 名前` | ( -- ) | 定義の内容を表示します。コロン定義は命令列から再構成するので、ソースと完全には一致しません。 |
| `FIND-NAME` | ( addr u -- nt \| 0 ) | 名前で辞書を探し、名前トークンを返します。見つからなければ0です。 |
| `NAME>INT` | ( nt -- xt ) | 名前トークンから実行トークンを得ます。 |
| `NAME>STRING` | ( nt -- addr u ) | 名前を文字列で返します。結果は8回分まで有効です。 |
| `WORD` | ( c -- c-addr ) | 入力から文字cで区切られた次の語を読み、数え付き文字列で返します。 |
| `SYNONYM 新しい名前 元の名前` | ( -- ) | 元の語の別名を作ります。即時語なら別名も即時語で、`TO` や `>BODY` も元の語に働きます。 |
| `TRAVERSE-WORDLIST` | ( xt wid -- ) | 語彙の語を新しい順に、名前トークンを渡してxt ( nt -- flag ) を実行します。偽が返るとやめます。 |
| `NAME>INTERPRET` | ( nt -- xt ) | `NAME>INT` と同じです。 |
| `FIND` | ( c-addr -- c-addr 0 \| xt 1 \| xt -1 ) | 数え付き文字列の名前を探します。即時語なら1、それ以外は-1です。`:` や `TO` などの構文語は見つかりません。 |
| `PARSE` | ( c -- addr u ) | 入力の続きを文字cの手前まで返します。 |
| `SOURCE` | ( -- addr u ) | 今の入力行（`EVALUATE` では文字列）のアドレスと長さです。 |
| `>IN` | ( -- addr ) | 入力行の中で次に読む位置（先頭からのバイト数）を持つセルのアドレスです。書き換えると、読む位置が変わります（行の長さ以上なら行の残りを読み飛ばし、負の値は `STRING TOO LONG !`）。 |
| `SOURCE-ID` | ( -- n ) | 端末なら0、`EVALUATE` なら-1、ファイルの読み込み中はそのファイルの番号です。 |
| `REFILL` | ( -- flag ) | 端末または読み込み中のファイルから次の行を読み、それを入力にして真を返します。入力の終わりと `EVALUATE` の中では偽です。 |
| `SAVE-INPUT`, `RESTORE-INPUT` | ( -- x1 x2 x3 x4 4 )、( x1 x2 x3 x4 4 -- flag ) | 入力の位置（入力元、`>IN`、行）を保存し、そこへ戻ります。戻れたらflagは偽です。ファイルでは保存した行を読み直し、端末と `EVALUATE` では同じ行の中でだけ戻れます。 |
| `PARSE-NAME` | ( "name" -- addr u ) | 空白とタブを飛ばして、入力から次の名前を返します。行の終わりでは長さ0です。 |

`WORD`、`PARSE`、`PARSE-NAME` は、そのワードが書かれた行の続きを読みます。行をまたいでは読みません。

## 語彙（ワードリスト）と条件付きコンパイル

```forth
VOCABULARY MY-WORDS
ONLY FORTH ALSO MY-WORDS DEFINITIONS
: HELLO ." Hello, My Words!" ;
ORDER                \ MY-WORDS Forth Root     MY-WORDS
ONLY FORTH DEFINITIONS
HELLO                \ HELLO ?（見えなくなる）
WORDLIST CONSTANT UTIL
UTIL SET-CURRENT : TWICE 2 * ; FORTH DEFINITIONS
UTIL >ORDER 5 TWICE .   \ 10
1 [IF] ." yes" [ELSE] ." no" [THEN]
```

語は「語彙」に属し、検索順序に並んだ語彙から探されます。新しい語は定義先の語彙に入ります。起動時の検索順序は `Forth Forth Root`、定義先は `Forth` です。

| ワード | スタック | 説明 |
| --- | --- | --- |
| `VOCABULARY 名前` | ( -- ) | 語彙を作ります。名前を実行すると、検索順序の先頭をその語彙に置き換えます。 |
| `WORDLIST` | ( -- wid ) | 名前のない語彙を作り、その番号を返します。 |
| `FORTH`, `FORTH-WORDLIST` | ( -- )、( -- wid ) | 検索順序の先頭をForthにする、またはForthの番号を返します。 |
| `ONLY` | ( -- ) | 検索順序を最小（`Root Root`）にします。続けて `FORTH` と書くのが普通です。 |
| `ALSO`, `PREVIOUS` | ( -- ) | 検索順序の先頭を複製する、または先頭を取り除きます。 |
| `>ORDER` | ( wid -- ) | 語彙を検索順序の先頭に加えます。 |
| `DEFINITIONS` | ( -- ) | 検索順序の先頭の語彙を定義先にします。 |
| `GET-CURRENT`, `SET-CURRENT` | ( -- wid )、( wid -- ) | 定義先の語彙を取得、または変更します。 |
| `GET-ORDER`, `SET-ORDER` | ( -- wid... n )、( wid... n -- ) | 検索順序を取得、または設定します。`-1 SET-ORDER` は `ONLY` と同じです。 |
| `ORDER` | ( -- ) | 検索順序と、空白をあけて定義先を表示します。 |
| `SEARCH-WORDLIST` | ( addr u wid -- 0 \| xt 1 \| xt -1 ) | 1つの語彙だけから名前を探します。 |
| `[IF]`, `[ELSE]`, `[THEN]` | ( flag -- )、( -- )、( -- ) | flagが0なら、`[ELSE]` か `[THEN]` までの入力を読み飛ばします。行をまたいでも使えます。 |
| `[DEFINED] 名前`, `[UNDEFINED] 名前` | ( -- flag ) | 名前が検索順序で見つかるかどうかを返します。 |
| `[IFDEF] 名前`, `[IFUNDEF] 名前`, `[ENDIF]` | ( -- ) | `[DEFINED] 名前 [IF]`、`[UNDEFINED] 名前 [IF]` と同じです。`[ENDIF]` は `[THEN]` と同じです。 |
| `[DO]` … `[LOOP]`, `[?DO]`, `[+LOOP]`, `[I]` | ( limit start -- )、( n -- )、( -- n ) | 解釈中に、入力の範囲を繰り返します（Gforthと同じ）。`[?DO]` はlimitとstartが等しければ1回も実行しません。`[I]` は一番内側の `[DO]` か `[FOR]` の添字です。ファイルでは行をまたいでも使えます。 |
| `[BEGIN]` … `[UNTIL]`, `[AGAIN]`, `[WHILE]` … `[REPEAT]` | ( flag -- ) など | 解釈中の不定回の繰り返しです。 |
| `[FOR]` … `[NEXT]` | ( n -- ) | 添字をnから0まで減らしながら、n+1回繰り返します。 |

検索順序は16段までです。`WORDS` は検索順序の先頭の語彙の語だけを表示します。`ONLY` の後でも `FORTH` `ONLY` `ALSO` `ORDER` などは使えます。`:` や `TO` などの構文語は、検索順序によらずいつでも使えます。

## ソースファイルの読み込み

```forth
INCLUDE mylib.fs          \ ファイルを読み込んで実行します
REQUIRE mylib.fs          \ まだ読み込んでいなければ読み込みます
S" mylib.fs" INCLUDED? .  \ -1（読み込み済み）
LOCATE SQUARE             \ mylib.fs:2 と定義の行を表示
MARKER SAFE  : TEMP ." Hello" ;  SAFE   \ TEMP は消えます
```

| ワード | スタック | 説明 |
| --- | --- | --- |
| `INCLUDE ファイル名` | ( -- ) | ファイルを1行ずつ読み込んで実行します。 |
| `INCLUDED` | ( addr u -- ) | 文字列で指定したファイルを読み込みます。 |
| `REQUIRE ファイル名`, `NEEDS ファイル名` | ( -- ) | まだ読み込んでいないファイルだけを読み込みます。 |
| `REQUIRED` | ( addr u -- ) | `REQUIRE` の文字列版です。 |
| `INCLUDED?` | ( addr u -- flag ) | そのファイルが読み込み済みなら真を返します。 |
| `SOURCEFILENAME` | ( -- addr u ) | 読み込み中のファイル名です。端末では `*the terminal*` です。 |
| `SOURCELINE#` | ( -- u ) | 読み込み中の行番号です。端末では0です。 |
| `LOCATE 名前` | ( -- ) | その語を定義したファイルと行、定義の内容を表示します。 |
| `WHERE 名前` | ( -- ) | 読み込んだファイルの中で、その語を使った箇所を `ファイル:行:桁: 行の内容` の形で一覧します（Gforthと同じく、各行は80桁で、右端に通し番号が付きます）。`'` や `[DEFINED]` で名前を探した箇所も含みます。端末や `EVALUATE` の文字列での使用は記録しません。 |
| `MARKER 名前` | ( -- ) | 名前を実行すると、その語と以後の定義を消し、以後に読み込んだファイルを未読み込みに戻します。 |

ファイル名はカレントディレクトリからの相対パスです。`REQUIRE` は名前を書かれたとおりに比べるので、`./a.fs` と `a.fs` は別のファイルとして扱います。読み込み中にエラーが起きると、`mylib.fs:3: ...` のようにファイル名と行番号を付けて表示します。ファイルの中で始めた定義は、同じファイルの中で終える必要があります。入れ子は8段まで、記録できるファイルは64個までです。

## 辞書の保存と単独実行ファイル

この移植版の `SAVE` と `LOAD` は利用者定義語の辞書イメージを扱います。誌面のエディットバッファ操作とは異なります。

```forth
SAVE words.sigma
LOAD words.sigma
```

`LOAD` は保存した利用者定義語を現在の辞書の後ろに追加します。同名語は読み込んだ新しい定義が優先されます。以前の版で保存した辞書イメージ（`SIGIMG01`〜`SIGIMG30`）と、壊れた辞書イメージは読み込めません（`INVALID IMAGE !`）。辞書イメージにはチェックサムが付いており、偶然の破損は読み込む前に見つかります。読み込むのは、Sigmaの `SAVE`・`SAVESYS` で作ったファイルだけにしてください。定数や変数に保存した実行トークン（`:NONAME` の結果など）と、`LITERAL` で定義に埋め込んだ実行トークンやアドレス（`[ ' X ] LITERAL` など）は、すでに利用者定義語がある辞書へ `LOAD` すると別の語や場所を指すことがあります。`['] X` で埋め込んだ実行トークンは正しく付け替えられます。`SAVESYS` で作った実行ファイルではこの問題は起きません。

`SAVESYS` は、現在の辞書・コンパイル済み定義・データを含む、実行中環境向けの単独実行ファイルを作ります。

```forth
SAVESYS demo.exe
```

生成したファイルは引数なしで起動すると、その辞書を持つ対話プロンプトを開きます。引数がある場合は、引数を連結した文字列をForth入力として1回実行して終了します。生成物は作成元と同じ実行環境向けです。

## 登録済みワード一覧

次の表は、起動時に辞書へ登録され、`WORDS`で表示される組み込みワードです。`TO`、`S"`、`{` などの構文語は別途、次の「構文・定義形式」に記載します。利用者が定義した語は、この表には含まれません。

| 分類 | 登録語 |
| --- | --- |
| スタック操作 | `DROP`, `DUP`, `SWAP`, `OVER`, `ROT`, `-ROT`, `NIP`, `TUCK`, `PICK`, `ROLL`, `2DUP`, `2DROP`, `2SWAP`, `2OVER`, `DEPTH`, `>R`, `R>`, `R@`, `2>R`, `2R>`, `2R@`, `?DUP`, `2ROT`, `N>R`, `NR>` |
| 算術 | `+`, `-`, `*`, `/`, `MOD`, `/MOD`, `*/`, `*/MOD`, `MINUS`, `NEGATE`, `ABS`, `1+`, `1-`, `2*`, `2/`, `MAX`, `MIN` |
| 比較・論理・ビット | `=`, `<>`, `<`, `>`, `<=`, `>=`, `NOT`, `0=`, `0<`, `0>`, `0<>`, `AND`, `OR`, `XOR`, `COM`, `INVERT`, `NAND`, `NOR`, `SWAB`, `LSHIFT`, `RSHIFT`, `TRUE`, `FALSE` |
| 定数・アドレス計算 | `BL`, `CELL`, `CELLS`, `CELL+`, `ALIGNED`, `ALIGN`, `UNUSED`, `WITHIN`, `BUFFER:`, `DUMP` |
| メモリ・配列 | `@`, `!`, `,`, `C,`, `C@`, `C!`, `+!`, `1+!`, `1-!`, `OSET`, `ON`, `OFF`, `?`, `A@`, `A!`, `ERASE`, `FILL`, `MOVE`, `CMOVE`, `HERE`, `ALLOT` |
| ループ関連 | `I`, `J`, `K`, `LEAVE`, `UNLOOP` |
| 入出力 | `.`, `U.`, `.R`, `U.R`, `C.`, `.S`, `ECHO`, `EMIT`, `CR`, `SPACE`, `SPCES`, `SPACES`, `TYPE`, `INPUT` |
| 基数 | `HEX`, `DEC`, `DECIMAL`, `OCT`, `BASE` |
| 定義補助・辞書・実行 | `<BUILDS`, `CREATE`, `IMMEDIATE`, `WORDS`, `BYE`, `LOAD`, `SAVE`, `SAVESYS`, `EXECUTE`, `SEE`, `FIND`, `FIND-NAME`, `NAME>INT`, `NAME>STRING`, `MARKER`, `LOCATE`, `WHERE` |
| 制御構造（即時語） | `IF`, `ELSE`, `AHEAD`, `THEN`, `CS-PICK`, `CS-ROLL`, `ENDIF`, `BEGIN`, `END`, `UNTIL`, `AGAIN`, `WHILE`, `REPEAT`, `DO`, `?DO`, `LOOP`, `+LOOP`, `DOES>`, `CASE`, `OF`, `ENDOF`, `ENDCASE`, `EXIT`, `RECURSE` |
| 浮動小数点スタック | `FDROP`, `FDUP`, `FSWAP`, `FOVER`, `FROT`, `F-ROT`, `FNIP`, `FTUCK`, `FPICK`, `FDEPTH`, `F.S` |
| 浮動小数点算術・関数 | `F+`, `F-`, `F*`, `F/`, `FNEGATE`, `FMINUS`, `FABS`, `FMAX`, `FMIN`, `FSQRT`, `FEXP`, `FLN`, `FSIN`, `FCOS`, `FTAN`, `FSINCOS`, `FASIN`, `FACOS`, `FATAN`, `FATAN2`, `FSINH`, `FCOSH`, `FTANH`, `FASINH`, `FACOSH`, `FATANH`, `FEXPM1`, `FLNP1`, `FLOG`, `FALOG`, `F**`, `FLOOR`, `FTRUNC`, `FROUND` |
| 浮動小数点比較 | `F=`, `F<>`, `F<`, `F>`, `F<=`, `F>=`, `F0=`, `F0<>`, `F0<`, `F0>`, `F0<=`, `F0>=`, `F~` |
| 浮動小数点メモリ・変換・入出力 | `F@`, `F!`, `F,`, `FA@`, `FA!`, `F+!`, `F?`, `FLOATS`, `FLOAT+`, `DF@`, `DF!`, `DFLOATS`, `DFLOAT+`, `SF@`, `SF!`, `SFLOATS`, `SFLOAT+`, `FALIGN`, `FALIGNED`, `DFALIGN`, `DFALIGNED`, `SFALIGN`, `SFALIGNED`, `S>F`, `F>S`, `F.`, `FE.`, `FS.`, `REPRESENT`, `PRECISION`, `SET-PRECISION`, `FINPUT`, `F.RDP`, `F>STR-RDP`, `F>BUF-RDP` |
| 倍長整数 | `S>D`, `D>S`, `D+`, `D-`, `DNEGATE`, `DABS`, `D0=`, `D0<`, `D=`, `D<`, `DU<`, `DMAX`, `DMIN`, `D2*`, `D2/`, `M+`, `M*/`, `D.`, `D.R`, `M*`, `UM*`, `UM/MOD`, `FM/MOD`, `SM/REM`, `2@`, `2!`, `2VALUE`, `2LITERAL`, `D>F`, `F>D` |
| 文字列・入力 | `COUNT`, `PAD`, `ACCEPT`, `EVALUATE`, `KEY`, `KEY?`, `>NUMBER`, `S>NUMBER?`, `>FLOAT`, `WORD`, `PARSE`, `PARSE-NAME`, `SOURCE`, `>IN`, `SOURCE-ID`, `REFILL`, `SAVE-INPUT`, `RESTORE-INPUT`, `EKEY`, `EKEY?`, `EKEY>CHAR` |
| 数値の書式 | `<#`, `<<#`, `#`, `#S`, `#>`, `#>>`, `HOLD`, `HOLDS`, `SIGN` |
| 文字列格納・比較・状態・中断 | `PLACE`, `+PLACE`, `COMPARE`, `SEARCH`, `/STRING`, `-TRAILING`, `CHAR+`, `CHARS`, `BOUNDS`, `BLANK`, `CMOVE>`, `SCAN`, `SKIP`, `STR=`, `STRING-PREFIX?`, `SLITERAL`, `STATE`, `ABORT` |
| 時間・画面・OS | `MS`, `UTIME`, `TIME&DATE`, `PAGE`, `AT-XY`, `GETENV`, `SYSTEM`, `ENVIRONMENT?`, `QUIT` |
| 語彙・条件付きコンパイル | `ONLY`, `ALSO`, `PREVIOUS`, `FORTH`, `DEFINITIONS`, `SYNONYM`, `TRAVERSE-WORDLIST`, `NAME>INTERPRET`, `ORDER`, `GET-ORDER`, `SET-ORDER`, `>ORDER`, `GET-CURRENT`, `SET-CURRENT`, `VOCABULARY`, `WORDLIST`, `FORTH-WORDLIST`, `SEARCH-WORDLIST`, `[IF]`, `[ELSE]`, `[THEN]`, `[DEFINED]`, `[UNDEFINED]`, `[IFDEF]`, `[IFUNDEF]`, `[ENDIF]`, `[DO]`, `[?DO]`, `[LOOP]`, `[+LOOP]`, `[I]`, `[BEGIN]`, `[UNTIL]`, `[AGAIN]`, `[WHILE]`, `[REPEAT]`, `[FOR]`, `[NEXT]` |
| ソース読み込み | `INCLUDE`, `INCLUDED`, `REQUIRE`, `REQUIRED`, `NEEDS`, `INCLUDED?`, `SOURCEFILENAME`, `SOURCELINE#` |
| ファイル・例外 | `THROW`, `CATCH`, `R/O`, `W/O`, `R/W`, `STDIN`, `STDOUT`, `STDERR`, `OPEN-FILE`, `CREATE-FILE`, `CLOSE-FILE`, `READ-LINE`, `READ-FILE`, `FILE-POSITION`, `RESIZE-FILE`, `FLUSH-FILE`, `DELETE-FILE`, `RENAME-FILE`, `FILE-STATUS`, `BIN`, `INCLUDE-FILE`, `WRITE-LINE`, `WRITE-FILE`, `FILE-SIZE`, `SLURP-FILE`, `REPOSITION-FILE` |
| 定義語・コンパイル | `:`, `;`, `VARIABLE`, `VAR`, `FVARIABLE`, `2VARIABLE`, `CONSTANT`, `CONST`, `FCONSTANT`, `2CONSTANT`, `VALUE`, `FVALUE`, `ARRAY`, `FARRAY`, `'`, `>BODY`, `LITERAL`, `FLITERAL` |
| 定数・説明 | `PI`, `HELP`, `LICENSE` |
| 動的メモリ・動的文字列 | `ALLOCATE`, `FREE`, `RESIZE`, `$!`, `$@`, `$@LEN`, `$!LEN`, `$+!`, `C$+!`, `$.`, `$DEL`, `$INS`, `$OVER`, `$FREE`, `$INIT`, `$SPLIT`, `$ITER`, `$TMP`, `$SLURP-FILE`, `$[]`, `$[]!`, `$[]@`, `$[]#`, `$[].`, `$[]MAP`, `$[]FREE`, `$[]SLURP`, `$[]SLURP-FILE`, `$SLURP`, `$+SLURP`, `$+SLURP-FILE`, `$SLURP-LINE`, `$+!LEN`, `$[]+!`, `$+[]!`, `$EXEC`, `$OFF`, `$VARIABLE`, `$[]VARIABLE`, `$?` |

起動時点でForth語彙に **476語** の組み込み語があります（`MINUS`/`NEGATE` のような別名もそれぞれ1語と数えます）。このほかRoot語彙に、`FORTH` `ONLY` などの10語が重ねて登録されています。

### 構文・定義形式

以下はForth入力で使える構文ですが、`WORDS`が列挙する組み込み辞書語ではありません。

| 種類 | 語・形式 | 説明 |
| --- | --- | --- |
| 定義 | `: 名前 ... ;`, `:NONAME ... ;` | コンパイル済みの利用者定義語を作ります。`:NONAME` は名前のない定義を作り、実行トークンを積みます。 |
| 定義・削除 | `VARIABLE 名前`, `VAR 名前`, `CONSTANT 名前`, `CONST 名前`, `値 VALUE 名前`, `FORGET 名前` | 変数・定数・値を登録し、または辞書末尾までを削除します。 |
| 値の変更 | `TO 名前` | `VALUE` で作った語の値を変更します。定義内でも使えます。 |
| 浮動小数点の定義 | `FVARIABLE 名前`, `FCONSTANT 名前` | 浮動小数点の変数・定数を登録します。 |
| 倍長整数の定義 | `2VARIABLE 名前`, `2CONSTANT 名前`, `2VALUE 名前` | 倍長整数の変数・定数・値を登録します。 |
| 配列 | `要素数 ARRAY 名前`, `要素数 FARRAY 名前` | 要素数をスタックから取り、配列を登録します。 |
| ローカル変数 | `{ ... }`, `{: ... :}`, `LOCALS\| ... \|` | 「ローカル変数」の節を参照してください。 |
| コンパイル制御 | `[`, `]`, `' 名前`, `['] 名前`, `POSTPONE 名前`, `LITERAL`, `FLITERAL` | コンパイル中断／再開、実行トークンの取得、コンパイル動作の組み込み、値の埋め込みに使います。`'` は実行したときに次の名前を読み、定義の中に書くとその定義を実行したときに読みます。`[']` は定義をコンパイルするときに名前を読み、その実行トークンを埋め込みます。`LITERAL` `FLITERAL` はコンパイル中にスタックの値を定義へ埋め込みます。 |
| データ領域 | `実行トークン >BODY` | VARIABLE・VALUE・CREATEなどで作った語のデータ領域のアドレスを積みます。CONSTANT・FCONSTANT・コロン定義・組み込み語では `INVALID EXECUTION TOKEN !` です。`'` は語の番号を返すので、Gforthのように `' 名前` の値をアドレスとして使うことはできません。語の番号は低い番地（`BASE` などの処理系の変数がある所）と重なるため、`' 名前 +` の先に書き込むと、処理系の変数を壊すことがあります（`BASE ERROR !` など）。データ領域には `' 名前 >BODY` を使ってください（例: `10 0 CELLS ' DATA >BODY + !`）。これは標準のForthでも正しい書き方です。 |
| 文字 | `CHAR 文字`, `[CHAR] 文字` | 文字コードを積みます。 |
| コメント | `( ... )`, `\` | 行内コメント、行末までのコメントです。 |
| 文字列 | `"..."`, `."..."` | コンパイル時文字列と、移植版の文字列出力拡張です。 |
| Gforthの文字列 | `S" ..."`, `S\" ..."`, `.\" ..."`, `.( ... )` | 「文字列」の節を参照してください。 |

## 実装していない機能

現在は `EDIT`、`LIST`、エディットバッファ版の `LOAD`／`SAVE`、CP/Mファイル操作、PC-8001のモニター機能、`MCODE`やZ80機械語実行に対応していません。Z80をエミュレートする処理系ではありません。

Gforthのワードのうち、`$SUBSTITUTE` などは未実装です。`CODE` や `SAVESYSTEM` などGforthの起動処理に関わる語は対象外です。詳しくは[互換性一覧](COMPATIBILITY.md)を参照してください。

# FORTH/Σ のプログラムのデバッグ

英語版: [DEBUGGING.md](DEBUGGING.md)。英語版が原本です。

この手引きは、FORTH/Σ で Forth のプログラムのどこが悪いかを調べる方法を説明します。エラーがどこで起きたか、プログラムがなぜ終わらないか、どの語がどんなスタックで実行されたか、あるセルを何が書き換えているか、どのコードが遅いか、どのコードが一度も実行されていないか、を調べられます。ここにある機能はすべて、コマンドラインから `sigma` を1回起動して、それが自分で終わる形で使えます。プロンプトの前の人だけでなく、プログラム（エージェント、スクリプト、CI）からも使えます。

[ユーザーマニュアル](USER_MANUAL.ja.md)には、同じ機能が語ごとに書いてあります。この手引きは、調べたいことの順に並べてあります。

## 何を使うか

| 調べたいこと | 使うもの | 出力先 |
|---|---|---|
| エラーがどこで起きたか | 何も要らない。メッセージの後にバックトレースが出る | 標準出力 |
| プログラムがなぜ終わらないか | `--max-steps N` | 標準出力 |
| どの語が、どの順に、どんなスタックで実行されたか | `--trace`、`--trace-limit N` | 標準エラー |
| 定義の中のある場所でのスタック | `~~`、`~~BT`、`~~1BT`、`ONCE` | 標準エラー |
| ある語が何をするかを、1命令ずつ | `DBG name`、`BREAK:`、`BREAK"` | 標準出力 |
| 値や変数がいつ使われるか | `~~VALUE`、`~~VARIABLE` | 標準エラー |
| メモリのあるセルを何が書き換えるか | `WATCH`、`UNWATCH` | 標準エラー |
| どの語の仕事がいちばん多いか | `--profile` | 標準エラー |
| コードのどの部分が実行されなかったか | `--coverage`、`.COVER-RAW`、`COV%`、`.COVERAGE` | 標準出力 |
| 実行しなくても分かる誤り | `--lint` | 標準出力 |
| 構造が見える字下げ | `--format`、`--format-check` | ファイル |
| 上のすべてを、プログラムが読む形で | `--debug-log FILE` | JSON Lines のファイル |

オプションは、大きさのオプションと同じく、ファイルやほかの引数より前に書きます。`--` でオプションを打ち切ります。

```text
sigma [オプション] [ファイル ...] [-e "文"] ...
```

以下の例では、次のファイル `prog.fs` を使います。

```forth
: SQUARE ( n -- n ) DUP * ;
: SUMSQ ( a b -- n ) SQUARE SWAP SQUARE + ;
: AVERAGE ( sum n -- avg ) / ;
: REPORT ( a b n -- )
   >R SUMSQ R> AVERAGE . ;
VARIABLE SCORE
: BUMP ( -- ) 1 SCORE +! ;
: SPIN ( -- ) BEGIN BUMP AGAIN ;
: TELL ( n -- ) DUP 0< IF DROP ." minus" ELSE 0= IF ." zero" THEN THEN ;
```

## エラー: バックトレース

コロン定義の中で、`CATCH` が捕まえなかったエラーが起きると、メッセージの後に、実行中だった定義とスタックが表示されます。何も指定する必要はありません。

```text
> sigma prog.fs -e "3 4 0 REPORT"
DIVISION BY ZERO !
BACKTRACE:
  AVERAGE prog.fs:3
  REPORT prog.fs:5
STACK: <0>
```

上から読みます。エラーは `AVERAGE` の中、`prog.fs` の3行目で起きました。`AVERAGE` を呼んだのは `REPORT` で、5行目です。`STACK:` は、エラーが起きたときのデータスタックを `.S` の形で示します（失敗した語は引数を取った後です）。浮動小数点スタックに値があるときは、`FLOAT STACK:` の行が続きます。入力そのものがファイルのときは、メッセージの前にその `ファイル名:行:` が付きます。

- 呼び出し元にコードを写した短い定義には、`(INLINE)` が付きます。
- 再帰は、回数を付けた1行になります（`DEEP prog.fs:4 *32`）。保持する32か所より外側の呼び出し元は、`... 4064 MORE` のように数だけを示します。
- 定義の外のエラー、`ABORT`、`QUIT`、`CATCH` が捕まえたエラーには、バックトレースがありません。
- 終了コードは1です。

## 終わらないプログラム: `--max-steps`

`--max-steps N` は、コンパイルしたコードが `N` 命令を実行したところで、エラー `STEP LIMIT !` で実行を終わらせます。バックトレースで、プログラムがどこを実行していたかが分かります。このエラーは `CATCH` では捕まえられません。

```text
> sigma --max-steps 1000 prog.fs -e "SPIN"
STEP LIMIT !
BACKTRACE:
  BUMP prog.fs:7
  SPIN prog.fs:8
STACK: <0>
```

数は、ファイル1つごと、`-e` 1つごと、入力した1行ごとに数え直します。中身を知らないプログラムを実行するエージェントは、必ず上限を付けてください。付けないと、キーを待つプログラムや終わらないループのプログラムから、戻ってこられません。

## 何が実行されたか: `--trace`

`--trace` は、コロン定義が始まるとき（`>`）と終わるとき（`<`）に、データスタックの深さと上から9個までの値を表示します。入れ子の深さだけ字下げします。

```text
> sigma --trace prog.fs -e "3 4 5 REPORT BYE"
> REPORT <3> 3 4 5
  > SUMSQ <2> 3 4
    > SQUARE <2> 3 4
    < SQUARE <2> 3 16
    > SQUARE <2> 16 3
    < SQUARE <2> 16 9
  < SUMSQ <1> 25
  > AVERAGE <2> 25 5
  < AVERAGE <1> 5
< REPORT <0>
```

語の終わりの行は、その語が残したものを示します。間違った値を残す語は、`<` の行が最初におかしくなる語です。`--trace-limit N` は、`N` 行を表示したところで `TRACE LIMIT` と表示してトレースを終え、プログラムは続きます。ループのあるプログラムでは必ず付けてください。エラーで終わった語には、`<` の行がありません。

## ある場所でのスタック: `~~` と `~~BT`

1つの定義の中の1か所を調べるときは、そこに `~~` を書きます。実行されるたびに、その場所（`ファイル名:行:桁:`）とデータスタックの全体を表示します。`~~BT` は呼び出し元も表示し、`~~1BT` は最初の1回だけ表示します。`ONCE ... THEN` は、その間を1回だけ実行します。ループの中の `~~` を1行にとどめられます。

```text
> sigma prog.fs -e ": T 5 ~~ SQUARE ~~BT DROP ; : CALLER T ; CALLER BYE"

*the terminal*:0:7:<1> #5

*the terminal*:0:17:<1> #25
BACKTRACE:
  CALLER
```

これらは gforth の語で、行の形も gforth と同じです。

## 1命令ずつ: `DBG` と `BREAK:`

`DBG name` は、コロン定義を1命令ずつ実行します。命令の前で、その命令と `->` を表示してキーを待ちます。キーを押すと命令を実行し、同じ行に、その命令が書いたものとスタックを続けて表示します。

```text
> printf '3 4 DBG SUMSQ\n\n\n\n\n\n. BYE\n' | sigma prog.fs
FORTH/Sigma 0.10.0  MIT License
Type `help' for basic help
: SUMSQ
[ 2 ] 3 4
SQUARE         -> [ 2 ] 3 16
SWAP           -> [ 2 ] 16 3
SQUARE         -> [ 2 ] 16 9
+              -> [ 1 ] 25
;              ->  OK
25  OK
```

| キー | 動作 |
|---|---|
| Enter | その命令を実行する。命令が呼ぶ語は、止まらずに実行する。 |
| `n` | 命令が呼ぶ定義の中に入る。その定義の `;` で、呼び出し元のステップ実行に戻る。 |
| `u` | 定義の残りを、止まらずに実行する。 |
| `d` | ステップ実行を終え、残りを実行する。 |
| `s` | エラー `debugger aborted` で実行を中止する。 |

キーは `KEY` と同じ方法で読むので、上の例のようにパイプから送れます。エージェントは、ステップ実行を始める行と、その後に1ステップにつき1つのキーを送ります。入力が終わると、`d` と同じようにステップ実行を終えます。

定義の中の `BREAK:` は、その場所からステップ実行を始めます。`BREAK" text"` は、その前に `BREAK AT: text` と表示します。調べたい場所がプログラムの奥にあって、先頭から1命令ずつ進めると時間がかかるときに使います。

## 値がいつ変わるか: `~~VALUE` と `~~VARIABLE`

`x ~~VALUE name` は、`TO` で書き換えるたびに表示する `VALUE` を定義します。`~~VARIABLE name` は、名前を使うたびに表示する `VARIABLE` を定義します。表示するのは、場所、データスタック、名前です。ソースの `VALUE` を `~~VALUE` に変えて実行し、調べ終わったら元に戻します。

## セルを何が書き換えるか: `WATCH`

`a-addr WATCH` は、それ以後、そのセルの値が変わるたびに、変えた定義と、その語の場所を表示します。どんな方法で変えても見つかります。名前を通した書き込みでも、計算したアドレスへの書き込みでも、`MOVE` や `FILL` でそのセルを上書きした場合でも同じです。触ってはいけないセルを書き換えている語を見つけられます。

```text
> sigma prog.fs -e "SCORE WATCH BUMP 7 SCORE ! BYE"
WATCH: 81920 changed from 0 to 1
  in BUMP prog.fs:7
WATCH: 81920 changed from 1 to 7
```

2つ目の変更はプロンプトで行ったものなので、定義の行がありません。`a-addr UNWATCH` は、そのセルの監視をやめます。監視できるセルは8個までです。`WATCH` は、プログラムを始める前に、定義の外で実行してください。すでに実行中の定義の中は調べません。

## 仕事がいちばん多いのはどこか: `--profile`

`--profile` は、プログラムが終わるときに、コロン定義ごとの呼び出し回数と、実行した命令の数を表示します。

```text
> sigma --profile prog.fs -e "3 4 5 REPORT BYE"
PROFILE: 19 OPERATIONS
     CALLS        SELF       TOTAL  WORD
         2           6           6  SQUARE prog.fs:1
         1           6          19  REPORT prog.fs:4
         1           5          11  SUMSQ prog.fs:2
         1           2           2  AVERAGE prog.fs:3
```

`SELF` はその定義自身のコードが実行した命令の数、`TOTAL` はその定義が始まってから終わるまでの命令の数で、呼び出した語の分を含みます。数えるのは時間ではなく命令の数なので、2回実行すれば同じ数になり、変更の前後を正確に比べられます。組み込み語は、何をする語でも1命令です。描画や待ちに使った時間は、プロファイルに表れません。

## 実行されなかったのはどこか: `--coverage`

`--coverage` は、コードのブロックごとに実行回数を数えます。ブロックは、定義の名前の後、`IF`、`ELSE`、`THEN`、`BEGIN`、`WHILE`、`REPEAT`、`UNTIL`、`AGAIN`、`DO`、`LOOP`、`CASE`、`OF`、`ENDOF`、`ENDCASE` の後、および定義の2行目以降の各行の先頭から始まります。回数は、gforth の語で表示します。

```text
> sigma --coverage prog.fs -e "3 4 5 REPORT -1 TELL CR COV% CR .COVERAGE BYE"
5 minus
53.3% coverage

: SQUARE ( 2)  ( n -- n ) DUP * ;
: SUMSQ ( 1)  ( a b -- n ) SQUARE SWAP SQUARE + ;
: AVERAGE ( 1)  ( sum n -- avg ) / ;
: REPORT ( 1)  ( a b n -- )
 ( 1)    >R SUMSQ R> AVERAGE . ;
VARIABLE SCORE
: BUMP ( 0)  ( -- ) 1 SCORE +! ;
: SPIN ( 0)  ( -- ) BEGIN ( 0)  BUMP AGAIN ( 0)  ;
: TELL ( 1)  ( n -- ) DUP 0< IF ( 1)  DROP ." minus" ELSE ( 0)  0= IF ( 0)  ." zero" THEN ( 0)  THEN ( 1)  ;
```

`( 0)` は、この実行で一度も届かなかったコードです。ここでは、`BUMP`、`SPIN`、`TELL` の `ELSE` の部分です。`.COVER-RAW` は、同じ回数を1行に1ブロック、`ファイル名:行:桁: 回数` の形で表示します。プログラムが読むにはこちらが向いています。位置と回数は、gforth で `require coverage.fs` の後に同じ文を実行したときと同じです。

## 実行しなくても分かる誤り: `--lint`

`--lint` は、ファイルをふだんどおり読み込んだ後、できた定義を検査します。Forth のソースは実行しないと読めないので、定義の外のコードは実行されます。自分では終わらないプログラムには、`--max-steps` を付けてください。

```text
> sigma --lint prog.fs
prog.fs:4: UNUSED: REPORT is not used in the files
prog.fs:8: UNUSED: SPIN is not used in the files
prog.fs:9: UNUSED: TELL is not used in the files
LINT: 1 DEFINITIONS WITHOUT A FIXED STACK EFFECT WERE NOT CHECKED FOR IT
LINT: 3 FINDINGS
```

| 検査 | 見つけるもの |
|---|---|
| `STACK EFFECT` | 名前の後のスタックコメント `( a b -- c )` と合わないコード |
| `STACK DEPTH` | スタックの深さが違う経路の合流（`IF 1 THEN`） |
| `RETURN STACK` | `R>` のない `>R`、`>R` のない `R>` |
| `UNREACHABLE` | `EXIT` や `AGAIN` の後のコード |
| `REDEFINED` | 前からある語と同じ名前 |
| `UNUSED` | どのファイルからも使われていない語 |

終了コードは、指摘がなければ0、あれば2です。効果が決まらない語を含む定義（`EXECUTE`、`?DUP`、`DEFER` の語、再帰、終わりのないループ。上の例では `SPIN`）は、スタックの3つの検査をしません。その数は最後に表示します。いちばん役に立つ習慣は、すべての名前の後にスタックコメントを書くことです。そうしておくと、`DROP` が1つ足りない、`SWAP` が1つ多い、といった誤りを、プログラムを実行する前に見つけられます。

## 構造が見える字下げ: `--format`

`--format` は、コロン定義と制御構造に合わせてファイルの字下げを整え、行末の空白を取り除きます。ファイルは文字として読むだけで、実行しません。変えるのは、行の最初の文字の前と最後の文字の後の空白だけなので、プログラムは元のままです。`--format-check` は何も変えず、変わる行の数を表示します。変わる行があれば、終了コードは2です。

```text
> sigma --format-check prog.fs
prog.fs: FORMATTED ALREADY
```

字下げが構造と合っていないプログラムは、読む前に整形してください。`THEN` のない `IF` は、字下げが戻ってこない行として見えるようになります。

## プログラムが読む形で: `--debug-log`

`--debug-log FILE` は、エラー、トレース、プロファイル、`--lint` の指摘、監視しているセルの変更を、1行に1つの JSON オブジェクトとして `FILE` に書きます。各行はその出来事が起きたときに書き出すので、プログラムが異常に終わっても、ログは欠けません。

```text
> sigma --debug-log run.jsonl --trace --profile prog.fs -e "3 4 0 REPORT"
```

```text
{"event":"start","version":"0.10.0"}
{"event":"enter","word":"REPORT","depth":0,"stack_depth":3,"stack":[3,4,0]}
{"event":"enter","word":"SUMSQ","depth":1,"stack_depth":2,"stack":[3,4]}
...
{"event":"enter","word":"AVERAGE","depth":1,"stack_depth":2,"stack":[25,0]}
{"event":"error","message":"DIVISION BY ZERO !","code":-10,"backtrace":[{"word":"AVERAGE","file":"prog.fs","line":3},{"word":"REPORT","file":"prog.fs","line":5}],"more":0,"stack_depth":0,"stack":[],"float_stack_depth":0,"float_stack":[]}
{"event":"profile","operations":16}
{"event":"profile_word","word":"SQUARE","file":"prog.fs","line":1,"calls":2,"self":6,"total":6}
```

ログがあるときは、トレースとプロファイルはログに書き、標準エラーには書きません。エラーは、ログがないときと同じように表示もします。出来事の種類は、`start`、`error`、`enter`、`exit`、`trace_limit`、`watch`、`lint`、`lint_end`、`profile`、`profile_word` です。それぞれの項目は、[ユーザーマニュアル](USER_MANUAL.ja.md)に一覧があります。ログを読むプログラムは、知らない項目や出来事を読み飛ばしてください。

## エージェント向けの注意

- **1回の起動で1つの答え。** プログラムと実行する内容を引数で渡し、`BYE` で終わらせて、出力を読みます（`sigma [オプション] prog.fs -e "MAIN BYE"`）。`BYE` がないと対話プロンプトに入ります。終わらせるには、入力を空にします（`< /dev/null`、`< NUL`）。
- **必ず上限を付ける。** 自分で書いていないプログラム、変更したばかりのプログラムには、`--max-steps 10000000` を付けます。`--trace` には必ず `--trace-limit` を付けます。
- **最初に終了コードを読む。** 0はエラーなし、1はエラー（メッセージとバックトレースが出力にある）、2は `--lint` の指摘がある、または `--format-check` で変わる行がある、です。
- **出力先を分けて読む。** プログラム自身の出力、エラーとバックトレース、`DBG` のステップ、`--lint` の指摘は標準出力に出ます。トレース、プロファイル、`~~`、`WATCH` は標準エラーに出ます。`--debug-log` を付けると、トレースとプロファイルはログだけに出ます。
- **出力を加工するなら、ログを使う。** ログの各行は1つの JSON オブジェクトです。
- **作業の順番の目安。** まず `--max-steps` を付けて実行する。エラーなら、バックトレースを読む。場所は分かるが原因が分からないときは、`--trace --trace-limit 200`。値がおかしいが、どこでおかしくなったか分からないときは、そのセルを `WATCH` する。ある語の動きが疑わしいときは、キーをパイプで送って `DBG` する。プログラムを渡す前に、`--lint` と `--format-check` をかける。

## 速さへの影響

コンパイルしたコードを実行するふつうのループは、これらの処理を何も行いません。オプションも語も使わなければ、プログラムの速さはこれらの機能がないときと変わりません。`--max-steps`、`--trace`、`--profile`、`--coverage`、`DBG`、コンパイルした `BREAK:`、`WATCH` を使うと、プログラムは命令を数えるもう1つのループで動き、遅くなります。`--trace`、`--profile`、`--coverage` では、短い定義を呼び出し元に写さずに呼び出すようにもなります。

`zig build -Ddebug=false` でビルドすると、これらの機能をすべて除いた FORTH/Σ になります。バックトレースもオプションもなく、語は `~~` と `ASSERT(` だけが残ります。配布するプログラムで、実行ファイルの大きさが問題になるときに使います。

## 一覧

| オプション | 値 | 効果 |
|---|---|---|
| `--max-steps` | `N` | コンパイルしたコードを `N` 命令で `STEP LIMIT !` にして終わらせる |
| `--trace` | — | コロン定義の始まりと終わりを表示する |
| `--trace-limit` | `N` | トレースを `N` 行で終える |
| `--profile` | — | 終わるときに、定義ごとの呼び出し回数と命令の数を表示する |
| `--coverage` | — | ブロックを数える（`.COVER-RAW`、`COV%`、`.COVERAGE` 用） |
| `--debug-log` | `FILE` | 出来事を JSON Lines で `FILE` に書く |
| `--lint` | — | ファイルを読み込んだ後に定義を検査する。プロンプトには入らない |
| `--format` | — | ファイルの字下げを整える。ファイルは実行しない |
| `--format-check` | — | `--format` で変わる行の数を表示する |
| `--format-indent` | `N` | `--format` の1段の空白の数（3） |

値は、オプションの後（`--max-steps 1000`）か、`=` の後（`--max-steps=1000`）に書きます。

| 語 | スタック | 由来 |
|---|---|---|
| `~~`、`~~BT`、`~~1BT` | `( -- )` | gforth |
| `ONCE` | `( -- )` | gforth |
| `DBG` | `( "name" -- )` | gforth |
| `BREAK:`、`BREAK"` | `( -- )` | gforth |
| `~~VALUE` | `( x "name" -- )` | gforth |
| `~~VARIABLE` | `( "name" -- )` | gforth |
| `+LTRACE`、`-LTRACE` | `( -- )` | gforth |
| `.COVER-RAW`、`COV%`、`.COVERAGE` | `( -- )` | gforth |
| `WATCH`、`UNWATCH` | `( a-addr -- )` | FORTH/Σ |
| `ASSERT(` | `( "code)" -- )` | gforth |

gforth の語の動作が gforth と違うところは、[ワード互換性一覧](COMPATIBILITY.ja.md)に書いてあります。

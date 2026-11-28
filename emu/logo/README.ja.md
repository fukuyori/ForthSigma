# LOGO とタートルグラフィックス

LOGO の一部を Forth に変換し、ForthSigma 上で実行します。以下のコマンドは
リポジトリ直下で、既存の全機能版 Sigma を使って実行してください。
言語と画素の規則は [仕様書](docs/SPECIFICATION.md) に定めています。

## 実行方法

```powershell
zig-out/bin/sigma.exe emu/logo/logo.fs emu/logo/examples/square.lg
zig-out/bin/sigma.exe emu/logo/logo.fs --emit-forth .work/square.fs emu/logo/examples/square.lg
```

通常実行では描画を表示し、終了後も **Esc** または **窓を閉じる操作** を待ちます。
どちらも終了状態0です。それ以外のエラーは、入力ファイル名、行番号、分類、
エラー番号を表示して終了状態1になります。`LOGO-MAIN` は診断を1回表示し、
`QUIT` で終了するため、Sigma 標準のエラー表示やバックトレースは出しません。
`LOGO-HEADLESS` は後始末後に元のエラーを Forth の呼出元へ再送出します。
中止（`-4205`）は診断せず終了状態0とします。出力先ディレクトリは事前に作成してください。

`--emit-forth 出力先` は、入力ファイルより前に1回だけ指定できます。
生成した Forth を UTF-8・LF で保存し、続けて実行します。変換だけを行うオプションでは
ありません。入力と出力が同じファイルへ解決される場合は、書込み前に拒否します。
ただし、異なるパス名のハードリンクは同一ファイルとして検出できません。
仕様書の2章で、この判定は対象外と定めています。そのような別名を出力先に使わないでください。

`logo.fs` をプログラム引数なしで読み込んだ場合と、後ろに Sigma の `-e` が続く場合は、
ライブラリを読み込むだけです。窓を開かずに実行するには、次の入口を使います。

```powershell
zig-out/bin/sigma.exe emu/logo/logo.fs -e 'ALSO LOGO S" emu/logo/examples/square.lg" LOGO-HEADLESS PREVIOUS ALSO TURTLE TURTLE-DISPOSE BYE'
```

PowerShell では、**`-e` の引数全体をシングルクォートで囲み**、Forth のダブルクォートは
そのまま書いてください。`LOGO-HEADLESS ( addr u -- )` は初期状態の640×480画像を用意し、
指定ファイルを変換・実行します。`SHOW` と `FRAME` は呼びません。成功時は画素検査や
保存のために画像だけを残すので、呼出元が `TURTLE-DISPOSE` で解放してください。
失敗時は画像も解放し、元の例外を返します。定義と翻訳バッファはどちらの場合も回収します。
解放済み画像のハンドルは使わず、次の実行前に現在の画像を解放してください。

## 受け付ける LOGO

名前は ASCII の英字または `_` で始め、その後には英数字、`_`、`?` を使えます。
大小文字は区別しません。`:name` は変数参照、`"name` は閉じる引用符のない引用語です。
`;` から行末まではコメントです。入力は UTF-8 で、先頭の BOM は1個だけ除きます。
改行は LF と CRLF を受け付けます。任意の UTF-8 引用語を受け付けるのは `LABEL` だけです。
`[]` と `()` の外では改行を越えて入力を補いません。1行に複数の命令を書けます。

| 命令・演算 | 入力と結果 |
| --- | --- |
| `FD FORWARD BK BACK` | 距離1個。前進・後退 |
| `RT RIGHT LT LEFT` | 角度1個。単位は度 |
| `PU PENUP PD PENDOWN` | 入力なし。ペン上下 |
| `HOME CS CLEARSCREEN CLEAN` | 入力なし。原点移動・消去 |
| `SETXY` | 座標2個 |
| `SETH SETHEADING` | 向き1個。0度が上、時計回りが正 |
| `SETPC SETPENCOLOR SETBG SETBACKGROUND` | 整数の色番号0〜15、または百分率0〜100のリテラル `[r g b]` |
| `SETPENSIZE SETSPEED` | 整数の幅1〜64、速度0〜1000ミリ秒（既定10ミリ秒） |
| `SETSCREENSIZE` | 整数の幅と高さ、各2〜4096。全状態を初期化 |
| `ST SHOWTURTLE HT HIDETURTLE` | 入力なし。亀の表示・非表示 |
| `WRAP WINDOW FENCE` | 入力なし。端で折返し・切取り・領域外移動を拒否 |
| `ARC` | 角度と0以上の半径。位置と向きは保持 |
| `LABEL` | UTF-8 の引用語1個。横書き |
| `TO name :arg ...` / `END` | 固定入力の手続き。宣言行と終了行をそれぞれ独立させる |
| `REPEAT count [commands]` | 回数を切り捨て、負なら0回。上限2147483647 |
| `REPCOUNT` | ソース上で囲む最内側の反復番号。1始まり、反復外は−1 |
| `IF condition [commands]` | 命令としてだけ使える分岐 |
| `IFELSE condition [a] [b]` | 命令列、または各枝1個の値式 |
| `STOP` / `OUTPUT value` | 現在の手続きから終了。`OUTPUT` は1値を返す |
| `MAKE "name value` / `LOCAL "name` | 代入／手続き局所変数の宣言 |
| `THING "name` / `:name` | 数値1個の参照 |
| `TRUE FALSE` | 数値の−1と0 |
| `RANDOM bound` | 0以上 floor(bound) 未満の整数。切捨て後の上限値は1〜2147483647 |
| 単項 `+ -`、二項 `* / + -` | 浮動小数点演算。乗除算を加減算より先に評価 |
| `= <> < > <= >=` | 数値比較。四則演算より低い優先順位。連鎖は禁止 |
| `(expression)` | 式のグループ化。入力個数は変えない |

前置演算は、固定個数の入力をそれぞれ式として取り込みます。
したがって `FD (RANDOM 10) + 1` と `FD RANDOM 10 + 1` は乱数の上限が異なります。
`FD :A - 10` は減算ですが、`FD :A -10` は使われない値が残るためエラーです。
`FD - 10` の単項マイナスは受け付けます。条件は0または−1だけです。
演算結果が非有限値になる場合と、ゼロ除算はエラーです。

局所変数は宣言された手続きだけから見え、呼出元からは引き継ぎません。
実行されない枝の中も含め、`LOCAL` は手続き全体の宣言として先に集めます。
局所・大域とも代入前の参照はエラーで、大域変数もプログラム終了時に消えます。
本体に `OUTPUT` があれば値手続きとし、その手続きで `STOP` または末尾へ到達すると
エラーになります。値の未使用と、命令手続きを値に使うことは変換時に拒否します。
前方参照、相互再帰、入れ子のループからの終了、自己末尾呼出しでの複数引数の同時更新を
扱います。一般再帰の深さは保証しません。1定義の引数・局所・フラグ・一時値は計64個までです。

自作例は、反復の `square`、有限の自己末尾呼出しの `spiral`、再帰の `branches`、
色と幅の `colours`、端の `edges`、値と変数の `values` の6種類です。

## LOGO.EXE の保存方法

ライブラリだけを読み込み、完成した入口を登録してから `SAVESYS` を使います。
例えば、書込み可能な `C:/Temp` が既にある場合は、次のように指定します。

```powershell
zig-out/bin/sigma.exe emu/logo/logo.fs -e 'ALSO LOGO '' LOGO-MAIN APP-ENTRY! PREVIOUS SAVESYS C:/Temp/LOGO.EXE BYE'
C:/Temp/LOGO.EXE emu/logo/examples/spiral.lg
C:/Temp/LOGO.EXE --emit-forth C:/Temp/spiral.fs emu/logo/examples/spiral.lg
```

PowerShell の文字列内の `''` は、Forth の `'` を1個渡すための書き方です。
同じ手順を Forth の入力として書くと、次のとおりです。

```forth
INCLUDE emu/logo/logo.fs
ALSO LOGO
' LOGO-MAIN APP-ENTRY!
PREVIOUS
SAVESYS C:/Temp/LOGO.EXE
BYE
```

保存前に LOGO プログラムを実行せず、プログラム用マーカーも残さないでください。
画像などの実行時資源は起動時に作り直します。保存アプリの通常引数は LOGO の入力で、
引数なしは使用法エラーです。`LOGO-MAIN` から正常復帰するとアプリが終了します。
保存時のメモリーとローカルスタックの容量を維持します。検査には Sigma の既定値である
32 MiB と64 KiBを使いました。

## Forth のタートル API

`turtle.fs` を読み込んで `ALSO TURTLE` とすると、単独の Forth API を使えます。
`F:` は独立した浮動小数点スタックです。詳しい意味は仕様書4章を参照してください。

| 語（同じ欄の別名は同じ効果） | スタック |
| --- | --- |
| `FD FORWARD BK BACK RT RIGHT LT LEFT SETH SETHEADING` | `( F: n -- )` |
| `SETXY ARC` | `( F: a b -- )` |
| `PU PENUP PD PENDOWN HOME CS CLEARSCREEN CLEAN` | `( -- )` |
| `ST SHOWTURTLE HT HIDETURTLE WRAP WINDOW FENCE` | `( -- )` |
| `SETPC SETPENCOLOR SETBG SETBACKGROUND SETPENSIZE SETSPEED` | `( n -- )` |
| `SETPENCOLOR-RGB SETBACKGROUND-RGB` | `( F: r g b -- )` |
| `SETSCREENSIZE TURTLE-INIT` | `( w h -- )` |
| `LABEL TURTLE-SAVE-PNG` | `( addr u -- )` |
| `TURTLE-PAINT TURTLE-DISPOSE` | `( -- )` |
| `TURTLE-IMAGE` | `( -- image )`。借用ハンドル。直接解放は禁止 |
| `TURTLE-RUN` | `( xt -- )`。表示して実行し、終了後も窓を保持 |

次の例は、窓を開かずに画像を初期化・描画・保存・解放します。

```powershell
zig-out/bin/sigma.exe emu/logo/turtle.fs -e 'ALSO TURTLE 101 101 TURTLE-INIT 20e FD 90e RT 20e FD S" .work/turtle.png" TURTLE-SAVE-PNG TURTLE-DISPOSE BYE'
```

同一プロセスで `TURTLE-INIT` を再度呼ぶ前には、現在の画像を解放してください。
`TURTLE-PAINT` は画面用画像の合成だけを行い、窓は開きません。
`TURTLE-RUN` が表示を行う際は、Sigma の `SHOW` に表示先の選択を任せます。

## UCBLogo との違い

対象は数値中心の限定した言語です。リスト値・処理、`RUN`、実行時のコード生成、
動的スコープ、対話プロンプト、可変・任意・残余入力、括弧による入力数変更、
組込みの再定義、`FILL`、`FOREVER`、`SUM`、多亀、消しゴム・反転ペン、
LOGO からの画像ファイル操作は扱いません。角括弧は命令ブロックと RGB リテラル専用です。
引用語は `MAKE`、`THING`、`LOCAL`、`LABEL` の直接の入力だけに使えます。
末尾呼出しの最適化は自己呼出しだけで、相互末尾呼出しは通常の呼出しになります。

`REPCOUNT` は呼出元の反復番号を引き継ぎません。真偽値は数値の−1と0で、条件にも
その2値だけを許します。局所宣言は手続き全体に適用します。パレットの RGB、
円弧の開始方向と折れ線化、正方形の筆跡、半画素の丸め、端での分割と FENCE 失敗時の
原子性、横書き文字、消去・初期化の保持規則、各上限、速度のミリ秒指定は、
本実装の仕様選択であり、UCBLogo との互換性を確認したものではありません。
窓をリサイズしてもキャンバス寸法は変えず、表示用の亀は保存画像に含めません。
速度0でも途中の入力確認は続けます。

## 検査と確認範囲

```powershell
zig-out/bin/sigma.exe emu/logo/test-turtle.fs
zig-out/bin/sigma.exe emu/logo/test-logo.fs
```

検査用の一時ファイルは `.work/1477/` に作ります。窓や音は使いません。
小画像の全画素を明示した期待値と比較し、検査失敗があれば終了状態1になります。
LOGO の検査では、生成コードの再評価、診断、反復実行後の回収、ファイル・画像の
使用可能枠数、6例の正常終了も確認します。7.4節の生成結果と例示コードとの差は
[実装報告](docs/IMPLEMENTATION-1477.md) に記録しています。
実際の窓操作、初期 ASCII フォント以外の表示、日本語の字形は目視確認していません。

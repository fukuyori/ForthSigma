# ワードリファレンスの読み方と使用例

## 対象と探し方

[全ワードリファレンス](WORD_REFERENCE.ja.md)は、古くからある語も追加語も、現在のソースに登録された名前を起点に収録します。FORTH、Root、EKEYS、EXTENSION、GRAPHICS、GUI、GAME、AUDIOごとに並べ、辞書に登録されない入力構文とローカル宣言はSyntaxにまとめます。語彙内では公開語を先に、内部補助語を後に掲載します。内部補助語は安定したAPIではありません。利用者が作成する任意の名前や、未実装の語はこの一覧の対象ではありません。

各項目にスタック効果、日本語の動作説明、worker欄、使用例、注意点、種別、出典を掲載します。照合用の英語の説明は折りたたみ表示で残しています。関連マニュアルとライブラリの定義も併用してください。使用例が既存コードの抜粋の場合は、リンク先の準備・入力・期待結果を含めて読み、単独実行できる例とは区別します。内部語には、対応する公開構文がその内部語を生成する間接使用例もあります。

個別説明の翻訳元の指紋を`docs/word-reference/translation-sources.json`に記録しています。原文や元定義が変わると照合が失敗します。日本語説明を確認・更新してから`python scripts/word-reference.py --record-reviewed-sources`で記録を更新してください。このオプションは日本語訳を自動生成するものではありません。

テストからの抜粋には正常系だけでなく、意図してエラー条件を検証する入力も含みます。期待される例外や、テスト側で用意するスタック・ファイル・ホストの設定は参照先を確認してください。使用例中のBYEはプロセスを終了します。STDINを読む例はEOFまで入力を消費します。

## スタック表記

`( before -- after )`は、左から右へスタックの下から上を表します。`( x1 x2 -- x2 x1 )`なら、上にあるx2とその下のx1を交換します。左右に書かれない下位の要素はそのままです。入力ストリームから読む名前や文字列は`"name"`や`"text"`で示します。これらをデータスタックに積むという意味ではありません。

`n`は符号付き64ビット整数、`u`は符号なし64ビット整数、`x`は1セルの値、`flag`は通常0（偽）か-1（真）、`addr`/`c-addr`は論理メモリー内の番地です。セルは8バイトです。倍長整数は2セルを使い、低位セル、高位セルの順で積みます。`addr u`は番地とバイト長の組で、UTF-8の文字数とは限りません。

`F:`は浮動小数点スタック、`R:`は利用者リターンスタックです。浮動小数点リテラルは`1e`や`1.5E3`のようにEを付けます。通常のデータスタックと浮動小数点スタックを混同しないでください。`compilation:`や`runtime:`があるときは、コンパイル時と実行時の効果を分けて読みます。内部語の`{ ... | ... -- ... }`は実装内のローカル宣言であり、`|`の後ろの一時変数は呼出側の入力ではありません。

## 定義、構文、検索順

`immediate`はコンパイル中にも実行される組込み語、`compile-only`は定義のコンパイル中だけ使える組込み語を示します。属性のない構文でもコンパイル時にしか使えないものがあります。各説明の条件に従ってください。`HELP IF`で説明を表示することと、対話入力で`IF`を実行することは別です。

追加ライブラリは`REQUIRE-GRAPHICS`などで読み込み、`ALSO GRAPHICS`などで検索順に加えます。REQUIREだけでは利用者の検索順は変わりません。GUIとGAMEはGRAPHICSを前提としますが、両方の語を使う場合は`ALSO GRAPHICS ALSO GUI`などと指定します。`PREVIOUS`で先頭の語彙を取り除きます。`DEFINITIONS`は新しい定義の登録先を変える語なので、検索するだけなら必要ありません。

標準特殊キーの`EKEYS K-LEFT`と、グラフィックスの`GRAPHICS K-LEFT`は異なる値です。標準値はEKEY/EKEY>FKEY、GRAPHICSの値はINKEYで使います。検索順によって同名のどちらが見つかるかが変わります。両者を同じ定数として扱わないでください。

## 所有権、エラー、機能の除外

`ior`を返す語は、その値を確認するか`THROW`へ渡します。0は成功です。`CATCH`が返す例外コードも0なら正常終了です。ファイル/パイプのEOFと、端末のEKEYが返すK-EOFを混同しないでください。端末Ctrl+Cは割込み、ファイル/パイプのバイト3は文字です。

`ALLOCATE`、`SAVE-MEM`、`S+`などが返す所有領域は、対応する方法で解放します。借用文字列は所有する領域とは異なり、次の操作で無効になる場合があります。辞書イメージに番地を保存する場合は、ACONSTANT/AVARIABLE/A,などの明示的な型付き参照を使います。通常の数値セルから番地を推測して再配置することはありません。

この一覧は全機能を含む通常構成を対象にします。`-Dfloat=false`などの機能除外版では対象の語がありません。GUIや音声などの語が載っていても、全OSで同じ表示装置や音声装置が使えるという意味ではありません。実際の前提と制約は[グラフィックスとサウンド](GRAPHICS_AND_SOUND.ja.md)を参照してください。

実装ソースの指紋も保存し、Zig処理本体を含む変更を検出します。指紋は変更検出のための確認ゲートであり、翻訳や意味の正しさを証明しません。内部状態・定数の用途はprivate-storage.jsonにも記録します。KEY-IORはバイトまたは負のI/O結果を1セルで返すため、通常のバイト値をTHROWに渡さないでください。RECURSEとローカル宣言は定義のコンパイル中に使います。


worker欄はtask_permissionsのbuiltin許可表と登録種別から作る。許可は入口全体の実行保証ではない。条件付きでは静的到達検査・最適化後Op検査と、メモリを扱う場合の論理領域・書込権限・native総処理量64 KiB/回以下の検査が必要である。除外構成では対象語を使えず、未登録・将来の語は既定で不可である。

## 使用例

### スタック操作

SWAPで2セルを交換し、DUPで最上位を複製します。ドットは表示したセルを取り除きます。

```forth
10 20 SWAP . . CR
3 DUP * . CR
```

出力：

```text
10 20
9
```

### 床関数除算とゼロ方向への除算

商が余りの上に積まれるため、ドットでは商を先に表示します。/MODは負の無限大方向、/MODSはゼロ方向に丸めます。

```forth
-7 3 /MOD . . CR
-7 3 /MODS . . CR
```

出力：

```text
-3 2
-2 -1
```

### 比較と真偽値

真は-1、偽は0です。ORはセル全体のビット演算です。

```forth
2 3 < . 3 2 < . TRUE FALSE OR . CR
```

出力：

```text
-1 0 -1
```

### 変数と辞書のデータ領域

変数やCREATEで定義した語はデータの番地を返します。CELL+は8バイト、1セル分進めます。

```forth
VARIABLE TOTAL
10 TOTAL ! 5 TOTAL +! TOTAL @ . CR
CREATE DATA 123 , 456 ,
DATA @ . DATA CELL+ @ . CR
```

出力：

```text
15
123 456
```

### 定義と分岐

IFとTHENはコロン定義の中で分岐をコンパイルします。

```forth
: MAGNITUDE DUP 0< IF NEGATE THEN ;
-12 MAGNITUDE . 8 MAGNITUDE . CR
```

出力：

```text
12 8
```

### 回数を指定するループ

DO/LOOPは上限を含みません。FOR/NEXTは0を含み、u+1回実行します。

```forth
: INDICES 4 0 DO I . LOOP ;
INDICES CR
: DOWN 3 FOR I . NEXT ;
DOWN CR
```

出力：

```text
0 1 2 3
3 2 1 0
```

### リターンスタック

定義の中でリターンスタックへ移した値を取り出し、対応を保ちます。

```forth
: SUM-SAVED 5 >R 7 R@ + R> DROP ;
SUM-SAVED . CR
```

出力：

```text
12
```

### 文字列とバイト長

S"は番地と長さを返します。TYPEは両方を消費し、等しいバイト列のCOMPAREは0になります。

```forth
S" hello" TYPE CR
S" abc" NIP . CR
S" abc" S" abc" COMPARE . CR
```

出力：

```text
hello
3
0
```

### UTF-8の文字

CHARは次の語から文字を読みます。文字列の長さはUTF-8のバイト数です。

```forth
CHAR A . CR
S" 日本" NIP . CR
```

出力：

```text
65
6
```

### 数値の基数

HEXはBASEを変更します。接頭辞では個々の数値の基数を指定できます。

```forth
HEX FF DECIMAL . CR
$FF . %101 . #10 . CR
```

出力：

```text
255
255 5 10
```

### 倍長整数

末尾のドットは倍長整数を表します。浮動小数点数ではありません。

```forth
123. 456. D+ D. CR
```

出力：

```text
579
```

### 浮動小数点の変換

浮動小数点数は専用スタックを使います。F>Sは変換結果をデータスタックへ積みます。

```forth
1e 2e F+ F>S . CR
9 S>F FSQRT F>S . CR
```

出力：

```text
3
3
```

### 実行トークンと引用

チックと無名引用から実行トークンを得て、EXECUTEで実行します。

```forth
: INC 1+ ;
5 ' INC EXECUTE . CR
[: 2 * ;] 7 SWAP EXECUTE . CR
```

出力：

```text
6
14
```

### 値と遅延語

TOは値を置き換え、+TOは加算します。ISは遅延語の実行内容を設定します。

```forth
10 VALUE LIMIT
20 TO LIMIT 3 +TO LIMIT LIMIT . CR
DEFER ACTION
' DUP IS ACTION
6 ACTION + . CR
```

出力：

```text
23
12
```

### ローカル変数

初期化する最後のローカルがスタック最上位を受け取ります。ローカルの寿命は呼出し中だけです。

```forth
: DIFFERENCE { a b -- n } a b - ;
10 3 DIFFERENCE . CR
: LOCAL-SQUARE {: n :} n n * ;
5 LOCAL-SQUARE . CR
```

出力：

```text
7
25
```

### 例外

CATCHは例外コードを返します。正常終了では処理結果の上に0を積みます。

```forth
: FAIL -24 THROW ;
' FAIL CATCH . CR
: PASS 42 ;
' PASS CATCH . . CR
```

出力：

```text
-24
0 42
```

### 文字列をソースとして実行

EVALUATEは番地と長さで渡した文字列をForthソースとして実行します。

```forth
S" 6 7 *" EVALUATE . CR
```

出力：

```text
42
```

### 所有するメモリー

割当てと解放のIORをTHROWで確認し、所有領域を使用後に解放します。

```forth
16 ALLOCATE THROW CONSTANT MEM
123 MEM ! MEM @ . CR
MEM FREE THROW
```

出力：

```text
123
```

### 所有する連結文字列

S+は新しい所有文字列を割り当てます。表示後にFREEできるよう番地を残します。

```forth
S" ab" S" cd" S+ 2DUP TYPE CR DROP FREE THROW
```

出力：

```text
abcd
```

### 所有文字列の値

文字列値は領域を所有し、実行時には番地と長さを借用として返します。

```forth
S" ab" $VALUE LABEL
S" cd" +TO LABEL
LABEL TYPE CR
```

出力：

```text
abcd
```

### 固定幅のメモリー操作

W!とW@で16ビットの値を格納し、符号なし整数として取り出します。

```forth
CREATE SHORT-DATA 4 ALLOT
$1234 SHORT-DATA W!
SHORT-DATA W@ . CR
```

出力：

```text
4660
```

### 伸長バッファー

BUFFER%は整列条件と大きさを返します。記述子を初期化してから伸長し、最後に所有領域を解放します。

```forth
CREATE BUF BUFFER% NIP ALLOT
BUF INIT-BUFFER
12 BUF ADJUST-BUFFER
BUF @ . CR
BUF FREE-MEM-VAR
```

出力：

```text
12
```

### 独自の語彙

DEFINITIONSで新しい語の登録先を変え、ALSOで検索対象を追加します。

```forth
VOCABULARY EXTRA
ALSO EXTRA DEFINITIONS
: ANSWER 42 ;
FORTH DEFINITIONS
ALSO EXTRA ANSWER . CR
PREVIOUS
```

出力：

```text
42
```

### 標準キーとグラフィックスのキー値

同じK-LEFTという名前でも、語彙とキー値は別です。

```forth
ALSO EKEYS K-LEFT . PREVIOUS
REQUIRE-GRAPHICS ALSO GRAPHICS K-LEFT . PREVIOUS CR
```

出力：

```text
2147483648 258
```

### メモリー上の描画

画像を作り、赤を選んで1画素を描きます。ウィンドウや端末への表示は行いません。

```forth
REQUIRE-GRAPHICS ALSO GRAPHICS
16 16 GFX-INIT
255 0 0 COLOR
3 4 PSET
3 4 GFX-PGET . CR
```

出力：

```text
16711680
```

### GUIの色の役割

対話フレームを動かさず、GUIの表面色を設定して読み出します。

```forth
REQUIRE-GUI ALSO GUI
$123456 GUI-FACE GUI-COLOR!
GUI-FACE GUI-COLOR@ . CR
```

出力：

```text
1193046
```

### スプライトのデータ

SPRITE:は辞書にスプライト用データを作ります。フィールドの語が返す番地を@で読みます。

```forth
REQUIRE-GAME ALSO GRAPHICS ALSO GAME
16 16 GFX-INIT
SCREEN 0 0 8 8 SPRITE: HERO
3 4 HERO PUT-SPRITE
HERO SPRITE-X @ . HERO SPRITE-Y @ . CR
```

出力：

```text
3 4
```

### 標準の音の音色

音色1を4分の1のパルス、ミリ秒の包絡、左を逆相にします。音色の設定にはホストの音声エンジンが要りますが、音は鳴らしません。

```forth
REQUIRE-AUDIO ALSO AUDIO
1 INSTRUMENT PULSE 16384 DUTY 10 200 40000 300 ADSR
-65535 65535 INSTRUMENT-PAN ." set" CR
```

出力：

```text
set
```

## 更新と照合

本文は実装の登録一覧・HELP原文・埋込みForthライブラリから生成します。番号や追加時期で対象を絞りません。`--check`はファイルを書き換えず、説明欠落と生成済み文書の古さを検出します。`--sigma`は指定実行体の実際の辞書と全件比較し、使用例の出力も確認します。実行体は通常構成で事前にビルドしてください。機能除外版を指定すると一致しません。

```powershell
zig build
python scripts/word-reference.py
python scripts/word-reference.py --check --sigma zig-out/bin/sigma.exe
python scripts/check-docs.py
```

使用例は各々新しいプロセスで実行します。ファイル保存・シェル起動・対話入力・画面表示・音声再生は行いません。これらの操作が必要な語の詳しい使用方法は、各項目の関連マニュアルを参照してください。この確認は全語の振る舞いを実機検証したという意味ではありません。

[全ワードリファレンスへ戻る](WORD_REFERENCE.ja.md)

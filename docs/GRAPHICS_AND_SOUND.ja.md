# FORTH/Σ グラフィックスとサウンドのマニュアル

英語版（正）: [GRAPHICS_AND_SOUND.md](GRAPHICS_AND_SOUND.md)。この日本語版は英語版の訳です。内容が異なる場合は英語版に従ってください。

Sigma のグラフィックスとサウンドは、この移植版の拡張です。誌面の FORTH/Σ には、どちらもありません。このマニュアルでは、描画、文字、Tcl/Tk、キー、マウス、アニメーション（`REQUIRE-GRAPHICS`）と、音楽、音源、録音した音、モジュール（`REQUIRE-AUDIO`）を説明します。Sigma の起動、言語、ほかの語は[ユーザーマニュアル](USER_MANUAL.ja.md)を、`SHOW` の表示先と色数は[グラフィックモードのマニュアル](GRAPHICS_MODES.ja.md)を参照してください。

## グラフィックス

Sigmaは、メモリ上の1枚の画像に描き、PPM、BMP、またはPNGのファイルに保存できます。グラフィックスの語は起動時の辞書にはありません。`REQUIRE-GRAPHICS` を初めて実行したときに、`GRAPHICS` 語彙と、`GFX-` の語、Forthで書いたグラフィックスのライブラリ（`src/graphics/graphics.fs` と、浮動小数点数の語がある版では `src/graphics/graphics_float.fs`。プログラムに組み込み済み）を加えます。2回目以降は何もしません。検索順序は変えないので、`ALSO GRAPHICS`（または `GRAPHICS`）で語を使えるようにします。`SHOW` の表示先と色数は、[グラフィックモードのマニュアル](GRAPHICS_MODES.ja.md)にまとめています。

```forth
REQUIRE-GRAPHICS
ALSO GRAPHICS
320 200 GFX-INIT                  \ 320×200画素の黒い画像
255 0 0 COLOR                     \ 現在の色を赤に
10 10 300 190 LINE
0 255 0 COLOR
160 100 50 CIRCLE
0 0 255 COLOR
20 120 80 50 FILL-RECT            \ 20 120 から 80×50画素
S" picture.bmp" SAVE-BMP
PREVIOUS
```

座標は左上が 0 0 です。画像の外に出た部分は切り取り、画像のずっと外を描いても、中を描くより時間はかかりません。描画の語は現在の色で描きます。現在の色は `COLOR` で決め、最初は白です。1つのセルで表す色は `$RRGGBB` です（下位24ビットより上は無視します）。画素はすべて不透明です。

| 語 | スタック | 説明 |
| --- | --- | --- |
| `REQUIRE-GRAPHICS` | ( -- ) | グラフィックスの語を読み込みます（初回だけ）。`TO` と同じく解析語で、定義の中では使えません。ライブラリは `BASE` によらず10進で読み、`BASE` は元のままです。 |
| `RGB` | ( r g b -- rgb ) | 赤・緑・青（各0〜255、下位8ビットだけを使う）の色 `$RRGGBB`。 |
| `COLOR` | ( r g b -- ) | 現在の色を決めます。 |
| `COLOR!`、`COLOR@` | ( rgb -- )、( -- rgb ) | 現在の色を `$RRGGBB` で決める・得る。 |
| `PSET` | ( x y -- ) | 1画素を塗ります。 |
| `CLS` | ( -- ) | 画像全体を黒にします。 |
| `LINE` | ( x1 y1 x2 y2 -- ) | 2点を結ぶ線（両端を含む。Bresenhamの方法）。 |
| `RECT` | ( x y w h -- ) | 左上が x y で幅 w・高さ h の長方形の枠。w か h が0以下なら何も描きません。 |
| `FILL-RECT` | ( x y w h -- ) | 塗りつぶした長方形。 |
| `CIRCLE` | ( x y r -- ) | x y を中心とする半径 r の円。中点アルゴリズムと同じ画素を描きます。r が負なら何も描かず、0なら1画素です。 |
| `FILL-CIRCLE` | ( x y r -- ) | 塗りつぶした円。同じ引数の `CIRCLE` の画素をすべて含みます。 |
| `PAINT` | ( x y -- ) | x y と同じ色で上下左右につながる領域を、現在の色で塗ります。画像の外や、領域がすでに現在の色のときは何もしません。 |
| `SAVE-PPM`、`SAVE-BMP`、`SAVE-PNG` | ( c-addr u -- ) | 画像を新しいファイルに、2進のPPM（P6）、24ビットのBMP、またはPNGで書きます。ファイル操作のエラーは `THROW` します。PNGは赤・緑・青の各8ビットで圧縮しないので、大きさはBMPとほぼ同じです。PNGを読めるプログラムなら読めます。 |
| `SHOW` | ( -- ) | 画像を表示します。ホストにウィンドウがあれば（Windows）ウィンドウに、なければデスクトップで `wish` が起動できればTkのウィンドウに（Linux、macOS。[グラフィックモードのマニュアル](GRAPHICS_MODES.ja.md)を参照）、それもだめなら端末に、または `DISPLAY-TERMINAL`・`DISPLAY-WINDOW`・`DISPLAY-TK` で決めた先に表示します。 |
| `DISPLAY-TERMINAL`、`DISPLAY-WINDOW` | ( -- ) | `SHOW` の表示先を端末、またはウィンドウにします。ホストにウィンドウがなければ、`DISPLAY-WINDOW` は `HOST FUNCTION UNAVAILABLE !` になります。 |
| `WINDOW-SIZE` | ( w h -- ) | 次の `SHOW` から、ウィンドウ（と `DISPLAY-TK` のTkのウィンドウ）で、画像を w×h 画素の大きさの領域に表示します。各辺は1〜16384で、0 0（初めの値）なら画像と同じ大きさです。画像は縦横の比を保って入る最大の大きさで中央に描き、余りは黒にします。たとえば `160 120 GFX-INIT 640 480 WINDOW-SIZE` で、1画素を4×4で表示します。画像そのものと端末への表示は変えません。 |
| `TERMINAL-BLOCKS`、`TERMINAL-SIXEL` | ( -- ) | 端末への表示を、半角ブロック（既定）またはSixelにします。 |
| `DISPLAY-COLORS` | ( n -- ) | `SHOW` の色数を、フルカラー（0、既定）か、2、16、256色にします。色数の少ない端末や、昔のパソコンのような見た目のためです。2は明るさによる白黒、16はANSIの色（エスケープの30〜37と90〜97。近い色はxtermの既定の見え方で選ぶので、端末によっては違って見えます）、256はxtermの6×6×6の色と24段階の灰色（`ESC [ 38 ; 5 ; n m`）です。Sixelとウィンドウも同じ色を使います。画像の色は変わらないので、ファイルにはフルカラーで保存されます。ほかの値は `NUMBER ERROR !` になります。 |
| `DITHER` | ( flag -- ) | 色数を減らすとき、4×4のBayerの模様で色を混ぜる（真）か、いちばん近い色にする（偽、既定）かを決めます。模様は位置で決まるので、アニメーションでもちらつきません。 |
| `GFX-INIT` | ( w h -- ) | 新しい黒い画像を作ります。幅・高さは各1〜16384画素で、画像は1 GiBまでです（1画素4バイト）。新しい画像を作れなかったときは、前の画像が残ります。 |
| `GFX-WIDTH`、`GFX-HEIGHT` | ( -- n ) | 描画先の画像（[画像](#画像)を参照）の大きさ。描画先が画面で `GFX-INIT` の前なら0です。 |
| `GFX-PSET` | ( x y rgb -- ) | 1画素を色 rgb で塗ります。 |
| `GFX-PGET` | ( x y -- rgb ) | 1画素の色。画像の外は-1です。 |
| `GFX-HLINE` | ( x1 x2 y rgb -- ) | x1からx2まで（両端を含む）の横線を引きます。 |
| `GFX-CLS` | ( rgb -- ) | 画像全体を色 rgb で塗ります。 |
| `GFX-SAVE-PPM`、`GFX-SAVE-BMP`、`GFX-SAVE-PNG` | ( c-addr u -- ior ) | `SAVE-PPM`・`SAVE-BMP`・`SAVE-PNG` と同じですが、`THROW` せずに ior（0かエラー）を返します。`-Dfiles=false` の版でも使えます。 |
| `GFX-SHOW-BLOCKS`、`GFX-SHOW-SIXEL`、`GFX-SHOW-WINDOW` | ( -- ) | 画像を、端末に半角ブロックで、Sixelで、またはウィンドウに表示します。 |
| `GFX-WINDOW?` | ( -- flag ) | ホストが画像をウィンドウに表示できれば真。 |
| `GFX-COLOR-MODE` | ( n flag -- ) | `GFX-SHOW-` の語の色数。`DISPLAY-COLORS` と `DITHER` と同じです（`SHOW` が毎回渡します）。 |

`GFX-` の語は、ライブラリを書くための基本の語です。ほかの語はForthの定義なので、`SEE`・`LOCATE`・`WHERE` で中身を見られます。計算があふれないように、座標と大きさは、`LINE`・`RECT`・`FILL-RECT` では -2^61〜2^61、円では -2^30〜2^30 に制限してから描きます（それを越える値の円は、値を上限に寄せて描きます）。`PAINT` は、まだ塗っていない行をヒープに置きます。非常に複雑な領域ではヒープが足りなくなり、`CANNOT ALLOCATE MEMORY !`（THROW -524）になります（そのときは途中まで塗られます）。

エラー: 大きさが範囲外なら `NUMBER ERROR !`、ホストが画像の領域を確保できなければ `OUT OF MEMORY !`、`GFX-INIT` の前に画像を使うと `NO GRAPHICS IMAGE !`（THROW -271）、`-Dgraphics=false` の版の `REQUIRE-GRAPHICS` は `GRAPHICS UNAVAILABLE !`（THROW -270）です。ライブラリの読み込みに失敗したときは、`REQUIRE-GRAPHICS` が加えたものをすべて取り除きます。`FORGET` や `MARKER` で `GRAPHICS` 語彙や `GFX-INIT` を消したあとは、`REQUIRE-GRAPHICS` でもう一度読み込めます。それより後ろの語だけを消した場合（`FORGET GFX-WIDTH` など）は、`REQUIRE-GRAPHICS` は何もせず、消えた語は戻りません。

Sigmaを作り直さずにライブラリの変更を試すには、組み込みのライブラリを読み込んでから、変えたファイルを `GRAPHICS` に読み込みます。その語が組み込みの語に代わります: `REQUIRE-GRAPHICS ALSO GRAPHICS DEFINITIONS DECIMAL INCLUDE src/graphics/graphics.fs`。

端末では、1文字で上下2画素を、24ビット色のエスケープで表示します。多くの端末（Windows Terminal と Windows のコンソール、xterm、GNOME Terminal など）で表示できます。画像が端末より大きいときは、縦横比を保って端末に収まるように縮め、縮めた1画素は元の画素の平均の色にします。1行はプロンプトのために残します。出力が端末でないとき（パイプやファイル）は、80桁24行とみなします。Sixel（`TERMINAL-SIXEL`）は、対応した端末では本物の画素で、216色で表示します。対応していない端末では、乱れた文字が出るか、何も表示されないことがあります。Windowsのコンソールは、UTF-8のコードページで半角ブロックを表示するので、Sigmaは書いている間だけコードページをUTF-8にして、終わったら元に戻します。

Windowsのウィンドウは専用のスレッドで動くので、Forthが入力を待っている間も、動かす・大きさを変える（画像はそれに合わせて伸び縮みします）・閉じることができます。キー入力はコンソールのままです。`SHOW` のたびに今の画像を描き直し、画像の大きさか `WINDOW-SIZE` の大きさが変わればウィンドウの大きさも合わせます（`WINDOW-SIZE` がなければ、1600×1200画素より大きい画像は縮めて表示します）。ウィンドウの大きさを変えると、画像は縦横の比を保って描き直し、余りは黒にします。`MOUSE` はマウスの下の画像の画素を返します。閉じたウィンドウは、次の `SHOW` で開き直します（ウィンドウが閉じるのとちょうど同時に表示した画像は、そのときまで表示されないことがあります）。LinuxとmacOSにはまだウィンドウがなく、`SHOW` は、Tcl/Tkのあるデスクトップではそのウィンドウに、ほかでは端末に表示します。

画像は辞書の一部ではありません。`SAVE` と `SAVESYS` はグラフィックスの語とそれを使う語を保存しますが、画素は保存しないので、プログラムは起動後に `GFX-INIT` で画像を作ります。辞書は、読み込んだときのグラフィックスのライブラリを持ち続けます。`REQUIRE-GRAPHICS` は新しい版のライブラリの語を加えないので、それを使うには、その辞書をソースから作り直します。

### 画像

`GFX-INIT` の画像（画面）のほかに、描いたり写したりするための画像を作れます。MSX2のページやAmigaのブリッターのように、スプライト、タイル、背景、一度描いて何度も写す絵などに使います。画像はハンドルで指し、`SCREEN`（0）は画面を指します。描画の語（`PSET`、`LINE`、`TEXT`、`PAINT` など）、`GFX-WIDTH`、`GFX-HEIGHT`、`SAVE-` の語は、`DRAW-TO` で選んだ画像を使います。`SHOW` は常に画面を表示します。

| 語 | スタック | 動作 |
|---|---|---|
| `NEW-IMAGE` | ( w h -- img ) | 黒い画像を作ります。各辺は1〜16384です。256枚、合計1 GiBまで（画面は数えません）で、それを超えると `OUT OF MEMORY !` です。 |
| `FREE-IMAGE` | ( img -- ) | 画像を解放します。そのハンドルはもう画像を指しません。描画先だったときは、描画先は画面に戻ります。 |
| `IMAGE-SIZE` | ( img -- w h ) | 画像の幅と高さ。画面なら画面の大きさです（`GFX-INIT` の前は0 0）。 |
| `SCREEN` | ( -- 0 ) | 画面のハンドル。 |
| `DRAW-TO` | ( img -- ) | 以後、その画像に描きます。`SCREEN DRAW-TO` で画面に戻ります。 |
| `DRAWING` | ( -- img ) | 描画先の画像のハンドル。 |
| `COPY-RECT` | ( src sx sy w h dx dy -- ) | 画像 src の sx sy にある w×h の長方形を、描画先の dx dy に写します。どちらかの画像からはみ出す部分は写しません。同じ画像の中で2つの長方形が重なってもかまいません（各画素は、上書きされる前に読みます）。 |
| `PUT-IMAGE` | ( src x y -- ) | 画像 src 全体を、描画先の x y に写します。 |
| `TRANSPARENT` | ( rgb\|-1 -- ) | `COPY-RECT` と `PUT-IMAGE` は、この色の画素を写しません。-1（初めの値）なら、すべて写します。 |
| `IMAGE-FLIP` | ( n -- ) | `COPY-RECT` と `PUT-IMAGE` で長方形を反転します。0は反転なし（初めの値）、1は左右、2は上下、3は両方です。ほかの値は `NUMBER ERROR !` です。 |
| `LOAD-IMAGE` | ( c-addr u -- img ) | PNG、BMP、PPM/PGM のファイルを新しい画像に読み込みます（下を参照）。 |

`LOAD-IMAGE` が読める形式は次のとおりです。PNG はすべての色の種類とビット深度で、インターレース（Adam7）も読めます。BMP は1、4、8、16、24、32ビットで、行が下からのものも上からのものも、色のマスク（`BI_BITFIELDS`）のものも、古い12バイトの見出しのものも読めます。RLE で圧縮したものは読めません。PPM と PGM は、2進（P6、P5）とテキスト（P3、P2）で、最大値は65535までのどの値でも読めます。16ビットの値は上位8ビットを使い、8ビットより少ない値は0〜255に広げます。画像は不透明なので、半分以上透明な画素（アルファが128未満。アルファの値、PNG の `tRNS`、BMP のアルファのマスクによる）は `TRANSPARENT` で決めた色にします。-1 なら黒にします。`TRANSPARENT` の後でスプライトを読み込めば、`PUT-IMAGE` は透明な部分を写しません。開けない・読めないファイルは、その ior で `THROW` します。ほかの形式や壊れたファイル（PNG は各チャンクの CRC と圧縮データのチェックサムを確かめます）は `IMAGE FORMAT ERROR !`（THROW -279）、各辺が16384より大きい絵は `NUMBER ERROR !` です。ファイル全体を一時的に辞書の外のメモリーに読むので、ファイルは2 GiBまでです。`-Dfiles=false` の版でも使えます。

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
320 200 GFX-INIT
16 16 NEW-IMAGE CONSTANT BALL
BALL DRAW-TO  $FF00FF GFX-CLS  255 255 0 COLOR  8 8 7 FILL-CIRCLE  SCREEN DRAW-TO
$FF00FF TRANSPARENT
: BALLS ( -- )   10 0 DO  BALL I 30 * 10 + 90 PUT-IMAGE  LOOP ;
BALLS  1 IMAGE-FLIP BALL 0 0 PUT-IMAGE  0 IMAGE-FLIP  SHOW
```

画像を指さないハンドル（作っていない、解放した、`SAVE` や `SAVESYS` の前から持っていた）は `INVALID IMAGE HANDLE !`（THROW -278）です。同じ画像の重なる場所へ反転して写すと `NUMBER ERROR !` になるので、別の画像を経由して写してください。画像は画面と同じく辞書の一部ではありません。辞書を復元すると（`SAVESYS` で作った実行ファイルの起動も）すべて解放されるので、プログラムは起動後に画像を作ります。保存した辞書の変数に残したハンドルは、新しい画像が同じ位置と世代番号になると、偶然その画像を指すことがあります。ハンドルを残さずに、画像を作り直してください。`TRANSPARENT` と `IMAGE-FLIP` の値は、`COLOR` と同じくライブラリの変数で、辞書と一緒に保存されます。下にある `GFX-` の語は、`GFX-IMAGE-NEW` ( w h -- img )、`GFX-IMAGE-FREE` ( img -- )、`GFX-IMAGE-SIZE` ( img -- w h )、`GFX-TARGET` ( img -- )、`GFX-TARGET@` ( -- img )、`GFX-COPY` ( src sx sy w h dx dy key flip -- )、`GFX-IMAGE-LOAD` ( c-addr u key -- img ior ) です。`GFX-COPY` の key は透明色で、負の数なら透明色なしです。`GFX-IMAGE-LOAD` の key は透明な画素に付ける色です。

### 文字

`TEXT` は、文字列を今のフォントで描きます。初めは組み込みのフォントで、美咲ゴシック（門真なむ氏、自由に利用できるフォント。[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) を参照）のASCIIの文字を、幅4画素・高さ8画素で描きます。`LOAD-FONT` はBDFのフォントファイルを読んで使い（どのOSでも）、`SYSTEM-FONT` はシステムに登録されたフォントを名前で使います（Windows）。文字列はUTF-8として読み、フォントにない文字は1つの `?` で描きます（フォントに `?` もなければ描きません）。UTF-8でないバイトも1バイトごとに同じです。制御文字は描きません。

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
160 40 GFX-INIT
255 255 0 COLOR  S" Hello, Sigma!" 4 4 TEXT
2 TEXT-SCALE  0 255 255 COLOR
S" FORTH/Sigma" 2DUP TEXT-WIDTH  160 SWAP - 2/  20 TEXT     \ 中央にそろえる
SHOW
```

| 語 | スタック | 説明 |
| --- | --- | --- |
| `TEXT` | ( c-addr u x y -- ) | 文字列を、行の左上が x y になるように、今の色で描く。字の線の間の画素はそのまま。なめらかにしたシステムのフォントでは、縁の画素は今の色と画像の色を混ぜる。 |
| `TEXT-SCALE` | ( n -- ) | フォントの1画素を n×n 画素で描く。1〜256（ほかは `NUMBER ERROR !`）。初めは1。 |
| `TEXT-WIDTH` | ( c-addr u -- w ) | `TEXT` が今の倍率で描いたときの幅（画素）。画像は要らない。 |
| `TEXT-HEIGHT` | ( -- h ) | 今のフォントの1行の高さ（今の倍率で）。 |
| `LOAD-FONT` | ( c-addr u -- ) | 名前のBDFフォントファイルを読んで使う。開けないファイルはそのエラーを、読めるBDFフォントでないファイルは `FONT ERROR !`（THROW -272）を THROW し、フォントは元のまま。1行の高さは256画素まで、1字の幅は512画素まで。使っていたフォントは、新しいフォントを最後まで読み終えるまで残す。 |
| `SYSTEM-FONT` | ( c-addr u height -- ) | システムのその名前のフォント（`Consolas`、`MS Gothic`、`メイリオ` など）を、1行 height 画素（1〜256）で、灰色の濃淡でなめらかにして使う。U+10000以上の文字は `?` で描く。その名前のフォントがなければ `FONT ERROR !`、LinuxとmacOSでは `HOST FUNCTION UNAVAILABLE !`。 |
| `BUILTIN-FONT` | ( -- ) | 組み込みのフォントに戻す。 |
| `GFX-GLYPH-LOAD` | ( code -- advance \| -1 ) | 今のフォントの文字番号の字形を読み込み、ペンを進める幅を返す。フォントになければ -1。 |
| `GFX-GLYPH-BOX` | ( -- left width height ) | 読み込んだ字形の箱。ペンから `left` 画素右（負なら左）、行の上端から。 |
| `GFX-GLYPH-ALPHA` | ( x y -- a ) | 読み込んだ字形の箱の x y の濃さ。0（なし）〜255（全面）。箱の外は0。 |
| `GFX-FONT-HEIGHT` | ( -- h ) | 今のフォントの1行の高さ。 |
| `GFX-FONT-LOAD`, `GFX-FONT-SYSTEM`, `GFX-FONT-BUILTIN` | ( c-addr u -- ior ), ( c-addr u height -- ior ), ( -- ) | `LOAD-FONT`、`SYSTEM-FONT`、`BUILTIN-FONT` と同じだが、ior（0、ファイルのエラー、-272）を返す。 |

フォントは辞書の一部ではありません。`SAVE` と `SAVESYS` は保存せず、プログラムは画像がない状態で始まるのと同じく、組み込みのフォントで始まります。BDFのフォントは論理メモリの外に置きます。`LOAD-FONT` ではどのBDFフォントも使えます。例えば、漢字を含む美咲ゴシック全体（<https://littlelimit.net/misaki.htm> の `misaki_gothic.bdf`）を読み込めば、同じプログラムがどのOSでも同じ画素を描きます。システムのフォントは、OSによって描き方もフォントの名前も違います。

### Tcl/Tk

TCL の語は、Sigmaが別のプログラムとして起動するTcl/Tkのインタープリター（`wish`）でTclのスクリプトを実行します。最初に必要になったときに起動し、パイプでやり取りします。SigmaにTclのライブラリはリンクしません。これで、Tkの部品（ウィジェット）を使えるほか、`DISPLAY-TK` で画像をTkのウィンドウに表示できます。Sigma自身のウィンドウがないLinuxやmacOSでも使えます。Tcl/Tkが入っている必要があり、`TCL-PROGRAM` で指定したプログラム、なければ環境変数 `SIGMA_WISH`、なければ `PATH` の `wish`、Windowsではそれもなければ Git for Windows に付いているもの（`%ProgramW6432%`、`%ProgramFiles%`、`%LOCALAPPDATA%\Programs` の下の `Git\mingw64\bin\wish.exe`。ふつうは `C:\Program Files\Git\mingw64\bin\wish.exe`）を使います。Linuxでは `tk` のパッケージにあります。macOSでは `brew install tcl-tk` で入れます。システムの `/usr/bin/wish`（Tcl/Tk 8.5）は最近のmacOSでは起動しないので、Sigmaは `PATH` のそれを飛ばし、`PATH` にほかの `wish` がなければ、Homebrewのもの（`/opt/homebrew/bin/wish`、`/usr/local/bin/wish`）かMacPortsのもの（`/opt/local/bin/wish`）のうち、最初にあるものを使います。

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
S" expr {6 * 7}" TCL-EVAL TYPE                  \ 42
S" button .b -text Press -command {sigma_event pressed}; pack .b; wm deiconify ." TCL
: WAIT-PRESS   BEGIN TCL-EVENT 0= WHILE 10 MS REPEAT TYPE ;
WAIT-PRESS                                       \ ボタンを押すと pressed
```

`examples/calculator.fs` は、まとまったプログラムの例です。ボタンとキーはTkで、計算はForthで行う電卓です（`sigma.exe < examples/calculator.fs`）。

| 語 | スタック | 説明 |
| --- | --- | --- |
| `TCL` | ( c-addr u -- ) | Tclのスクリプト（UTF-8）を大域で実行する。失敗すると `TCL ERROR !`（THROW -273）。 |
| `TCL-EVAL` | ( c-addr u -- c-addr2 u2 ) | Tclのスクリプトを実行して結果を返す。結果は次のスクリプトまで有効。 |
| `TCL-ERROR$` | ( -- c-addr u ) | 最後に失敗したスクリプトのメッセージ。 |
| `TCL-EVENT` | ( -- c-addr u true \| false ) | Tcl側が `sigma_event` で送った次の文字列（ボタンの `-command` からなど）を、待たずに返す。文字列は次の `TCL-EVENT` まで有効。 |
| `TCL-PROGRAM` | ( c-addr u -- ) | 次に起動するプログラム（`PATH` の名前かパス）。空なら `SIGMA_WISH`、`wish`、Git for Windows のもの、macOSではHomebrewかMacPortsのもの。 |
| `TCL-STOP` | ( -- ) | プログラムを終える。次の `TCL` で起動し直す。Sigmaの終了時にも終える。プログラムが書いてSigmaがまだ読んでいないものは捨てる。ホストがプログラムの終わりを確かめられなかったときは `HOST FUNCTION ERROR !`。 |
| `DISPLAY-TK` | ( -- ) | `SHOW` で、画像をTkのウィンドウ `.` に表示する（PNGで送り、`DISPLAY-COLORS` の色数に従う）。そこで押したキーとマウスは `INKEY` と `MOUSE` に届く。ウィンドウを閉じると、次の `SHOW` まで隠れる。`WINDOW-SIZE` があれば、画像は入る最大の整数倍で表示し（Tkは整数倍でしか拡大しないため）、入らなければ整数分の1に縮めます。ウィンドウの大きさを変えたときも同じです。 |
| `GFX-TCL`、`GFX-TCL-ERROR`、`GFX-TCL-EVENT`、`GFX-TCL-PROGRAM`、`GFX-TCL-STOP`、`GFX-SHOW-TK` | | 下の層の語。`GFX-TCL` ( c-addr u -- c-addr2 u2 flag ) は THROW せず、結果か、真のフラグとメッセージを返す。 |

プログラムを起動できないときや、プログラムが終わったときは、`HOST FUNCTION ERROR !`（THROW -265）になり、次に使うときに起動し直します。スクリプトは終わるまで実行するので、待つスクリプト（`vwait` など）はSigmaも待たせます。その間にTkのウィンドウで Ctrl+C を押すと `USER INTERRUPT !` になり、プログラムを終えます（次のスクリプトで起動し直します）。`return`・`break`・`continue` で終わるスクリプトも結果を返し、エラーだけが `TCL ERROR !` です。結果とイベントはヒープに置き、`SAVE` と `SAVESYS` はその前にこれらを解放します。そのため、それより前に TCL の語が返した文字列は、その後は使えません。そのとき受け取りの途中だったメッセージは捨て、プログラムは動いたままです。Sigmaがまだ読んでいないものが4 MiBを超えてプログラムにたまっている間（Sigmaが読むのは TCL の語、`INKEY`、`KEY-HELD?`、`MOUSE` の中だけ）、プログラムは新しいイベント、押したキー、マウスの知らせを捨てます。結果とキーを離した知らせは必ず送ります。`SHOW` のたびに画像全体を送るので、大きな画像は更新が遅くなります。Tcl側の取り決めは `src/graphics/sigma_tk.tcl` にあります。

### キー、マウス、アニメーション

`INKEY` は、端末とウィンドウからキーを待たずに読みます。`MOUSE` は、マウスの下にある画像の画素を返します。`KEY`、`KEY?`、`ACCEPT` は変わらず、行を読みます（LinuxとmacOSの端末の `ACCEPT` は、Sigmaが行を編集します）。

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
80 40 GFX-INIT  DISPLAY-TERMINAL  MOUSE-ON
VARIABLE X  40 X !
: STEP ( -- flag )   \ q で偽
   INKEY  DUP K-LEFT = IF -1 X +! THEN  DUP K-RIGHT = IF 1 X +! THEN
   [CHAR] q <>
   MOUSE 1 AND IF PSET ELSE 2DROP THEN ;
: RUN   BEGIN  0 0 255 COLOR  X @ 20 3 FILL-CIRCLE  255 255 255 COLOR  33 FRAME  STEP 0= UNTIL  MOUSE-OFF ;
RUN
```

`examples/paddle.fs` は、これらの語で作ったゲームです。3方の壁で跳ね返るボールを、上下キーで動かすパッドで打ち返します（`sigma.exe examples/paddle.fs`）。`examples/runner.fs`（Classic Runner）はもっと大きな例で、はしごを登り、ロープにぶら下がり、穴を掘り、追ってくる敵をかわしながら金塊を集めるタイルのゲームです。下の行に、1コマの処理にかかった時間と、1秒に表示したコマ数を出します。`examples/hopper.fs`（Sky Hopper）は横スクロールのアクションゲームです。2つのコースを走って跳び、敵を踏み、殻を蹴り、ブロックを下から叩いてコインや体が大きくなるベリーを出し、最後の気球に乗ります。キーと、mapped のゲームパッドで操作できます。`examples/shmup.fs`（Sigma Storm）は縦スクロールのシューティングゲームです。3つのステージに、敵の編隊、途中の空母、部位を壊せるボスがあり、5段階の武器、ボム、得点を増やすチェインがあります。キーと、mapped のゲームパッドで操作でき、専用の曲と効果音があり、F1 で1コマにかかる時間を表示します。 `examples/shmup-c64.fs` と `examples/shmup-amiga.fs` は、`examples/shmup.fs` と同じ縦スクロールのシューティングゲームを、コモドール64と Amiga の画面、色、音の雰囲気にしたものです。`examples/klondike.fs` は、`MOUSE` で遊ぶカードゲームのクロンダイクです。カードや並びをドラッグして動かし、カードをクリックすると置ける場所へ送ります。1枚めくりと3枚めくり、Undo、ヒントがあります。カードはすべて起動時に描き、`GFX-HLINE` の線の集まりとして表示します。`examples/waterworks.fs`（Waterworks）は、青写真の上に水が来る前に管を置いて道を延ばすゲームです。岩、タンク、ポンプ、トンネル、排水口のある8つのステージがあり、マウスまたはキーで操作します。`examples/sweeper.fs`（Sonar Sweep）は、数字を手がかりに海底の機雷を探すゲームです。広さの違う3つの海域があり、最初に開くマスとその周りには機雷がありません。マウスまたはキーで操作します。`examples/pinball.fs`（Wyrm's Delve）は、ダンジョンを舞台にしたピンボールです。バンパーのモンスターにはHPがあり、当たるたびにダメージをサイコロで決めます。祠はd20を振り、モンスターを倒すとドラゴンが目覚めます。スピナー、一方通行のゲートがあるオービット、ランプ、キックバックもあります。玉の物理は固定小数点で1コマに8回計算します。

| 語 | スタック | 説明 |
| --- | --- | --- |
| `INKEY` | ( -- key \| -1 ) | 押されたキーを待たずに1つ返す。なければ -1。文字はそのバイト（UTF-8の文字は1バイトずつ順に）、Enter は13、Backspace は8、Tab は9、Esc は27。Ctrl+C は `USER INTERRUPT !`（-28）を THROW する。 |
| `K-UP`, `K-DOWN`, `K-LEFT`, `K-RIGHT`, `K-HOME`, `K-END`, `K-PRIOR`, `K-NEXT`, `K-INSERT`, `K-DELETE`, `K-F1` .. `K-F12` | ( -- key ) | 文字でないキーに `INKEY` が返す番号（256〜277）。 |
| `MOUSE` | ( -- x y buttons ) | 最後に動いたときにマウスの下にあった画像の画素と、押されているボタン（1 左、2 右、4 中）。位置が分からない間は -1 -1。その間に押されたキーは `INKEY` のために残る。 |
| `MOUSE-ON`, `MOUSE-OFF` | ( -- ) | 端末にマウスの報告を頼む、または止める。ウィンドウはいつも報告する。 |
| `FRAME` | ( ms -- ) | 前の `FRAME` から ms ミリ秒たつまで待ってから `SHOW` する。描いて `FRAME` を呼ぶループは一定の間隔で動く。描くのに時間がかかったときは待たない。 |
| `KEY-HELD?` | ( key -- flag ) | そのキー（1バイトの文字か、`K-UP` などの番号）を今押しているか。キーボードがキーを繰り返すのを待たずに（最初に約0.5秒待つ）、押している間動かすゲームに使う。Windowsのコンソール、ウィンドウ、Tkのウィンドウはキーを離したときと、フォーカスを失ったときを知らせる。LinuxとmacOSの端末は知らせないので、最後に押してから0.6秒は押しているとみなす（押し続けると繰り返されるので、押している間は続く。繰り返しが始まった後は、最後の繰り返しから0.12秒で、離すとすぐ止まる）。端末は最後に押したキーしか繰り返さないので、方向キーは、別の方向キーを押すと押していないことになる。その間に読んだキーは `INKEY` のために残る。 |
| `GFX-INKEY`, `GFX-MOUSE`, `GFX-KEY-HELD` | `INKEY`, `MOUSE`, `KEY-HELD?` と同じ | 下の層の語。 |
| `GFX-MOUSE-MODE` | ( flag -- ) | 真で `MOUSE-ON`、偽で `MOUSE-OFF` と同じ。 |

最初の `INKEY` か `MOUSE` で、端末はキーを1つずつ、エコーなしで渡すようになります。Sigmaは、次に行や `KEY` を読むとき、`SYSTEM` を実行するとき、終わるときに、プログラム向けに打たれた入力を捨てて、端末を行入力に戻します。キーを1つずつ渡している間は、Ctrl+C でSigmaは終わりません。Ctrl+C は `INKEY` に届き、`INKEY` が THROW するので、キーを読むループはこれで止められます（`INKEY` も `MOUSE` も呼ばなくなったループは止められません）。標準入力が端末でないときは、`INKEY` はウィンドウのキーだけを受け取ります。

LinuxとmacOSでは、文字でないキーは端末からエスケープシーケンスで届き、`INKEY` が解読します。バイトが分かれて届く並び（遅い回線など）は、残りを50 msまで待ち、その間に何も続かない Esc は Esc キーとします。マウスは、xterm のSGR形式の報告で届きます。多くの端末（xterm、GNOME Terminal、iTerm2、Windows Terminal など）が送ります。`MOUSE-ON` で頼み、`MOUSE-OFF`、行入力に戻るとき、終わるときに止めます。Windowsでは、コンソールがキーとマウスをそのまま渡します。キーを1つずつ渡している間は、コンソールのマウスでの範囲選択は止まります。ウィンドウで押したキーも `INKEY` に届き、ウィンドウのマウスは、引き伸ばした画像のうちマウスの下にある画素を返します。

端末でマウスの下の画素を求めるため、Sigmaは `SHOW` で画像を描いた後に、端末にカーソルの位置を問い合わせます（`MOUSE-ON` の後だけ）。そのため、位置は `MOUSE-ON` の後の最初の `SHOW` から分かります。半角ブロックでは1文字が2画素で、Sixelでは文字の大きさを端末から得るか、10×20画素と仮定します。

端末への `SHOW` は、間に何も書いていなければ、前に描いた画像の上に描きます。そのため、アニメーションは流れずに同じ場所で動きます。間に何か書いたとき（プロンプトなど）は、下に新しく描きます。Sixelでは、画像が占める行数を文字の高さから数えるので、端末によっては合わないことがあります。

### 数学座標と関数のグラフ

浮動小数点数の語がある版では、ライブラリは数学の座標でも描けます（`src/graphics/graphics_float.fs`。`-Dfloat=false` の版には、これらの語はありません）。`X-RANGE` と `Y-RANGE` で、画像に平面のどの部分を映すかを決めます。x は左端から右端へ向かって増え、y は下端から上端へ向かって増えます。どちらも初めは -1 から 1 です。点は、いちばん近い画素に描きます。

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
320 200 GFX-INIT
-3.2e0 3.2e0 X-RANGE  -1.5e0 1.5e0 Y-RANGE
128 128 128 COLOR  AXES
255 255 0 COLOR  ' FSIN PLOT
: PARABOLA ( F: x -- y )  FDUP F* 1e0 F- ;
0 255 255 COLOR  ' PARABOLA PLOT
SHOW
```

`examples/trig.fs` は、sin x・cos x・tan x のグラフを、格子、目盛りの文字、凡例とともに描きます。tan x が画像よりはるかに大きい所では `PLOT` に NaN を返し、漸近線のところでグラフを切ります（`sigma.exe examples/trig.fs`）。

| 語 | スタック | 説明 |
| --- | --- | --- |
| `X-RANGE` | ( F: lo hi -- ) | 左端を x = lo、右端を x = hi にする。 |
| `Y-RANGE` | ( F: lo hi -- ) | 下端を y = lo、上端を y = hi にする。 |
| `MPSET` | ( F: x y -- ) | 点 x y の画素を描く。 |
| `MLINE` | ( F: x1 y1 x2 y2 -- ) | 2点を結ぶ線。 |
| `AXES` | ( -- ) | x = 0 と y = 0 の軸を、画像の端から端まで描く。範囲の外にある軸は描かない。 |
| `PLOT` | ( xt -- ) | 関数 xt ( F: x -- y ) のグラフ。画像の各列の x での y を求め、隣の列どうしを線で結ぶ。 |

範囲は lo が hi より小さく、どちらも有限でなければなりません。そうでないと、`X-RANGE` と `Y-RANGE` は `NUMBER ERROR !` になり、範囲は元のままです。数でない座標（NaN）は何も描かず、`PLOT` は y が NaN のところ（関数が定義されないところなど）を空けます。画素の位置が -2^61 .. 2^61 を超えるとき（無限大を含む）は、`LINE` と同じくその限界まで寄せるので、そのような端を持つ線は向きが変わることがあります。

## サウンド

Sigma は、MSX BASIC の `PLAY` や `SOUND` のように音楽を鳴らします。音源は、MSX、Atari ST、NES、コモドール64、コナミの SCC、Amiga のものを使えます。録音した音（WAV ファイル）と、ProTracker のモジュール（MOD ファイル）も鳴らせます。音は専用の音のスレッドが作るので、音楽が鳴っている間もプログラムは先へ進みます。音の語は、起動したときの辞書にはありません。`REQUIRE-AUDIO` を最初に実行したときに、`AUDIO` 語彙、`SND-` の語、Forth で書いた音のライブラリ（`src/audio/audio.fs`、プログラムに組み込み済み）が加わります。2回目以降は何もしません。グラフィックスの語と同じく検索順序は変えないので、`ALSO AUDIO` で語を見えるようにします。

```forth
REQUIRE-AUDIO
ALSO AUDIO
S" T150 O4 L8 CDEFGAB>C" PLAY               \ 声部A。MSX BASIC の PLAY "..." と同じ
S" O4 C2" S" O4 E2" S" O4 G2" PLAY3         \ 和音。3つの声部が同時に始まる
BEEP
NES-SOUND                                   \ ここからは PLAY を NES で鳴らす
1 INSTRUMENT PULSE 25 DUTY 0 4 8 2 ADSR     \ 音色1: 幅25%のパルスで、だんだん小さくなる
: TUNE S" T120 L8 O4 @1 CEGE CEGE" S" T120 L4 O3 CGCG" S" T120 L2 O2 CG" S" T120 L8 O3 C O4 D# O3 C O4 D#" 4 PLAYS ;
TUNE
```

`PLAY` は、MSX と同じく、音符が声部の待ち行列（各32個）に入りきったところで戻ります。そのあとは、音楽がひとりでに進みます。待ち行列がいっぱいの間、`PLAY` は待ちます。このとき Ctrl+C を押すと、音楽を止めて `USER INTERRUPT !`（THROW -28）になります。待っていないときの Ctrl+C は、これまでどおりです。音の出力装置がないときも、語は同じ時間で、音を出さずに動きます（どちらなのかは `AUDIO?` で分かります）。

### MML（音楽の記述）

`PLAY` などの語は、MSX BASIC の MML（MSX Red Book が説明する MSX1 の ROM のもの）を受け付けます。大文字と小文字は同じに扱い、空白は読み飛ばします。声部ごとに、オクターブ、長さ、テンポ、音量、音色を、次の `PLAY` まで覚えています。`BEEP` で初期値に戻ります。

| コマンド | 意味 |
| --- | --- |
| `A`〜`G` | 音符。`+` か `#`（シャープ）か `-`（フラット）、長さ 1〜64（省略すると `L` の値）、付点（1つごとに1.5倍）を続けられる。`B+` は同じオクターブの `C`、`C-` は同じオクターブの `B` になる（ROM の表のとおり）。 |
| `R` | 休符。長さ 1〜64（省略すると4）と付点。 |
| `N` | 番号 0〜96 で音符を指定する。オクターブは n / 12 + 1、音は n を12で割った余り（`N36` は `O4 C`）。0 は休符。 |
| `O` | オクターブ 1〜8（初め4、数を省略すると4）。 |
| `<`、`>` | 1オクターブ下げる、上げる。 |
| `L` | 長さを書かない音符の長さ 1〜64（4: 4分音符）。 |
| `T` | テンポ 32〜255（1分間の4分音符の数、初め120）。音符の長さは 12000 / (長さ × テンポ) を1/50秒の単位にしたもの（5未満は5）。 |
| `V` | 音量 0〜15（8）。`S` を解除する。 |
| `S` | PSG のエンベロープの形 0〜15（0）。後ろの音符がこれを使う。 |
| `M` | PSG のエンベロープの周期 1〜65535（255）。 |
| `@` | 音色 0〜63（0）。音色のある機種で使う。 |

数を省略すると、かっこ内の既定値になります（ROM と同じ）。ただし `N` には数が必要です。これ以外の文字や範囲外の数は `INVALID MML !`（THROW -274）になり、その `PLAY` は何も鳴らしません。BASIC の変数を使う `X` と `=変数名;` は扱いません。Forth のプログラムで文字列をつないで渡してください。

定義の外の `S"` の文字列は1つずつ別の場所に置かれるので、8声の `PLAYS` も1行で書けます。くり返し鳴らす曲は、文字列が辞書に入る定義の中に書くのがよい方法です。

### MSX BASIC の語

| ワード | スタック | 説明 |
| --- | --- | --- |
| `REQUIRE-AUDIO` | ( -- ) | 音の語を読み込む（最初の1回だけ）。`REQUIRE-GRAPHICS` と同じく解析器が扱う語で、定義の中では使えない。 |
| `PLAY` | ( c-addr u -- ) | MML を声部Aで鳴らす。音符のない声部BとCも、次の `PLAY` をAと同時に始める。 |
| `PLAY2`、`PLAY3` | ( c-addr1 u1 c-addr2 u2 -- )、( c-addr1 u1 c-addr2 u2 c-addr3 u3 -- ) | 声部AとB、またはA、B、Cを同時に鳴らし始める。 |
| `PLAYS` | ( c-addr1 u1 ... c-addrn un n -- ) | 最初の n 声を同時に鳴らし始める。n は 1〜8。 |
| `PLAY?` | ( n -- flag ) | 声部 n（1〜8。0 ならいずれか）に、まだ鳴らす音符があるか。MSX BASIC の `PLAY(n)`。音符のない声部も、`PLAY` の区切りを音のスレッドが受け取るまで（1/50秒以内）は真になる。 |
| `SOUND` | ( reg value -- ) | PSG のレジスタ 0〜13 に値 0〜255 を書く（MSX BASIC の `SOUND`）。PSG は、どの機種を選んでいても鳴る。 |
| `BEEP` | ( -- ) | 音楽を止め、PSG と声部の設定を初めの状態にして、ビープ音（約1316 Hz、40 ms）を鳴らす。音のスレッドが音楽を止めてから戻る。 |
| `AUDIO?` | ( -- flag ) | 音が出力装置に届くか。実行中に出力が失敗すると（Linuxで音を流すコマンドが終わるなど）偽になり、プログラムを起動し直すまで音は出ない。 |

### 機種と音色

`PLAY` は8声あり、音符ごとにどの機種の音でも鳴らせます。`STYLE` を指定した音色は、どの声部で鳴らしてもその機種の音になります。それ以外の音符は、声部の機種の音になります。声部の機種は `MSX-SOUND` などの語や `CHIPS` で決めます。これらの語を実行すると、`BEEP` と同じく音楽が止まります（ビープ音は鳴りません）。MML の `@n` で音色 n を選びます。機種にない値はその機種で一番近い値になり、機種にできないことは無視します。

```forth
1 INSTRUMENT  NES STYLE  PULSE 25 DUTY  0 4 8 2 ADSR
2 INSTRUMENT  SCC STYLE  SAW
3 INSTRUMENT  C64 STYLE  SAW  1 700 10 FILTER
4 INSTRUMENT  NES STYLE  TRIANGLE
S" @1 CDEF" S" @2 EGAB" S" @3 O3 C2G2" S" @4 O2 C1" 4 PLAYS
```

同じ機種の声部は、どの声部であっても、その機種のミキサーを通り、機種が共有するものを共有します（NES のミキサー、C64 のフィルター、Amiga の出力フィルター）。MSX と Atari ST の声部は、3声ごとに1つの PSG を使い（声部1〜3、4〜6、7と8）、エンベロープはその中で共有します。声部の直前の音符と違う機種の音符を鳴らすと、直前の音符は終わります。機種ごとの音量は変えていないので、1つの機種に多くの声部を割り当てると、出力の上限で音が歪むことがあります。

| ワード | スタック | 説明 |
| --- | --- | --- |
| `MSX-SOUND` | ( -- ) | 声部を MSX の AY-3-8910（機種自身の声部は3声）の音にする。音の高さは MSX の ROM のとおり。起動したときはこの機種。この表の「機種自身の声部」は先頭の声部で、それより後ろの声部も同じ機種の音になるが、波形は固定されない。 |
| `ST-SOUND` | ( -- ) | Atari ST の YM2149（2 MHz、3声）。エンベロープの音量は32段。 |
| `NES-SOUND` | ( -- ) | NES（機種自身の声部は4声）。矩形波2つ（デューティは 12.5、25、50、75%）、三角波（音量はなく、`V0` で無音）、ノイズ。ノイズの声部では、`O3 C` から `O4 D#` の音符が、16種類の音を低いものから高いものへ選ぶ。この4声は、音色に `STYLE` がない限り、音色の波形によらず波形が固定される。 |
| `C64-SOUND` | ( -- ) | C64 の SID（3声）。三角波、のこぎり波、パルス、ノイズ。`RING`、`SYNC`、`FILTER` が使える。 |
| `SCC-SOUND` | ( -- ) | コナミの SCC（5声）。それぞれ、音色の32段の波形を鳴らす。 |
| `AMIGA-SOUND` | ( -- ) | Amiga の Paula（4声、左・右・右・左）。音色の標本を鳴らす。 |
| `CHIPS` | ( mask -- ) | 声部にいくつかの機種を割り当てる。`MSX`（1）、`ST`（2）、`NES`（4）、`C64`（8）、`SCC`（16）、`AMIGA`（32）を `OR` で足して渡す。声部はこの順に番号が付く。例えば `MSX SCC OR CHIPS` では、声部1〜3が PSG、4〜8が SCC。最後の機種の声部より後ろの声部は、最後の機種の音になる。機種の声部の合計が8を超えると、9声目以降は鳴らない。機種が1つもないときと、未知のビットがあるときは `NUMBER ERROR !`。`MSX` と `ST` の両方を選ぶと、`SOUND` と `BEEP` は MSX の PSG を使う。 |
| `INSTRUMENT` | ( n -- ) | 下の語で変える音色 n（0〜63）を選ぶ。 |
| `STYLE` | ( chip -- ) | どの声部で鳴らしても、音色をその機種の音にする。`MSX`、`ST`、`NES`、`C64`、`SCC`、`AMIGA` のどれか。0（初めの値）は、鳴らす声部の機種の音にする。これら以外は `NUMBER ERROR !`。NES では、`TRIANGLE` が三角波、`NOISE` がノイズ、ほかの波形は矩形波になる。PSG では音色の波形を使わない。 |
| `SQUARE`、`PULSE`、`TRIANGLE`、`SAW`、`NOISE` | ( -- ) | 音色の波形。C64 はそれぞれを使う。NES の矩形波は `PULSE` のデューティを使う。SCC と Amiga は、その形の32段の波形を作る。初めは `SQUARE`。 |
| `DUTY` | ( percent -- ) | `PULSE` の幅 0〜100（初め50）。 |
| `ADSR` | ( a d s r -- ) | エンベロープ。各 0〜15 で、SID と同じ。アタックは 2 ms〜8 s、ディケイとリリースはその3倍、サステインの大きさは s / 15。初めは `0 0 15 0`。音符が終わるとリリースが始まる。 |
| `RING`、`SYNC` | ( flag -- ) | C64 で、音色の三角波を1つ前の声部で変調する。または、その声部の周期ごとに波形を最初に戻す。C64 自身の3声は巡回する（1声目には3声目）。それ以外の声部は、番号が1つ小さい声部を使う（声部1には声部8）。 |
| `FILTER` | ( mode cutoff resonance -- ) | C64 で、音色をフィルターに通す。mode は 0 なし、1 ローパス、2 バンドパス、3 ハイパス。cutoff は 0〜2047（約 30 Hz〜12 kHz）、resonance は 0〜15。フィルターは全声部で1つで、フィルターを使う音符が鳴り始めるたびにその設定になる。 |
| `SCC-WAVE` | ( c-addr n -- ) | c-addr からの符号付きの32バイトを、SCC（と Amiga）での音色 n の波形にする。設定しないときは、音色の波形の語の形になる。 |

各機種は共通の部品で組み立て、資料に書かれた動きをまねています。音の高さは各機種の周期のレジスタに、音量はその段数に丸めます。ただし、C64 の合成波形と 6581 のフィルターの特性、NES のスイープと DPCM などは再現しません。

### 録音した音

標本 0〜63 は、辞書のメモリーとは別の 64 MiB の領域に置く、録音した音です。この領域は増えるだけで、標本を読み直すと新しい場所を使います。`FREE-SAMPLES` で空にします。

| ワード | スタック | 説明 |
| --- | --- | --- |
| `LOAD-SAMPLE` | ( c-addr u n -- ) | 8ビットか16ビットの PCM の WAV ファイル（モノラルかステレオ。ステレオはモノラルにまとめる）を、標本 n に読み込む。読めないファイルはそのエラー、そのような WAV でないファイルは `SAMPLE ERROR !`（THROW -276）、領域が足りなければ `OUT OF MEMORY !`。エラーのときは何も変わらない。データが、ファイルに書かれた大きさより前で終わっているときは、ある分だけを標本にする。 |
| `SAMPLE` | ( c-addr u rate n -- ) | c-addr からの符号付き8ビットの u バイトを、rate Hz（1000〜192000）で録音した標本 n にする。 |
| `LOOP-SAMPLE` | ( start end n -- ) | 標本 n を鳴らすとき、フレーム start から end までをくり返す。`0 0` でくり返さない。 |
| `SAMPLE-INSTRUMENT` | ( n -- ) | `INSTRUMENT` で選んだ音色が、Amiga で標本 n を鳴らすようにする。`O4 C` で標本そのままの速さになる。-1 で外す。 |
| `SFX` | ( n -- ) | 標本 n をその速さで1回、すぐに、曲と並べて鳴らす。どの機種でも鳴る。同時に4つまで。5つ目は一番古いものと入れ替わる。 |
| `FREE-SAMPLES` | ( -- ) | 音楽、効果音、モジュールを止め、すべての標本とモジュールを消す。 |
| `AMIGA-FILTER` | ( flag -- ) | Amiga の LED フィルター（約 3.3 kHz のローパス）を入れるか切るか。A500 の固定のローパス（約 4.9 kHz）は常にかかる。 |

### モジュール

| ワード | スタック | 説明 |
| --- | --- | --- |
| `LOAD-MOD` | ( c-addr u -- ) | ProTracker の4チャンネルのモジュール（`M.K.`、`M!K!`、`FLT4`、`4CHN`）を領域に読み込む。ほかのファイルは `MOD ERROR !`（THROW -277）、領域が足りなければ `OUT OF MEMORY !`。 |
| `PLAY-MOD` | ( flag -- ) | モジュールを最初から、`PLAY` や `SFX` と並べて鳴らす。flag が真なら、終わったあと最初からくり返す。flag が偽なら、演奏済みの行へ戻る曲（`Bxx`）はそこで終わる。 |
| `STOP-MOD` | ( -- ) | モジュールを止める。 |
| `MOD?` | ( -- flag ) | モジュールが鳴っているか。 |

モジュールは、Paula の周期で、Amiga と同じ左右の振り分けとフィルターで鳴ります（LED フィルターは `AMIGA-FILTER` と効果 `E0x` で切り替わります）。鳴らす効果は、アルペジオ、上下のポルタメント、トーンポルタメント、ビブラート、トレモロ、音量の変化、サンプルのオフセット、位置の移動、パターンの区切り、音量の設定、速さとテンポ、細かいポルタメントと細かい音量の変化、パターンのループ、リトリガー、ノートカット、ノートディレイ、パターンディレイです。ビブラートとトレモロは常に正弦波です（`E4x`、`E7x`）。`E3x`、`E5x`、`E8x`、`EFx` は何もしません。音符がなくサンプル番号だけの行は、新しい音を始めません。今の音が終わるかループが一周した時点で、新しいサンプルのループに切り替わり（すでに音が止まっていれば、すぐに）、新しいサンプルにループがなければ無音になります。識別子が `FLT4` のモジュールでは、番号だけの行は鳴っている音を変えません。

### 音の出力装置

| システム | 出力先 |
| --- | --- |
| Windows | waveOut、48 kHz 16ビット ステレオ。音符は、音のスレッドが受け取ってから約80 ms で鳴り始める。 |
| Linux（配布版、静的リンク） | `pacat`、`pw-play`、`aplay` のうち最初に起動できたコマンドに、パイプで送る（約40 ms）。 |
| Linux（ライブラリを読み込める版） | PulseAudio、次に ALSA、次に上のコマンド。 |
| macOS | AudioToolbox の AudioQueue で、既定の出力装置に送る。48 kHz 16ビット ステレオ（約80 ms）。フレームワークは実行時に読み込む。 |

`BEEP`、機種を選ぶ語、`CHIPS`、`FREE-SAMPLES`、`PLAY` が待っている間の Ctrl+C は、音楽、効果音、モジュールを止めます。音の状態（音色、標本、待ち行列）は辞書に含まれません。`SAVE` と `SAVESYS` は音の語とそれを使う語を保存しますが、音色の設定や標本の読み込みは、プログラムが起動してから行ってください。音の語を読み込んだ辞書は `SIGIMG44` で保存します。

`SND-` の語は、ライブラリを書くための基本の語です: `SND-PLAY`、`SND-PLAYS`、`SND-SOUND`、`SND-BEEP`、`SND-PLAYING`、`SND-DEVICE`、`SND-CHIP`、`SND-CHIPS`、`SND-INSTRUMENT`、`SND-WAVE`、`SND-DUTY`、`SND-ADSR`、`SND-RING`、`SND-SYNC`、`SND-FILTER`、`SND-WAVETABLE`、`SND-LOAD-SAMPLE`、`SND-SAMPLE`、`SND-LOOP-SAMPLE`、`SND-SAMPLE-INSTRUMENT`、`SND-SFX`、`SND-AMIGA-FILTER`、`SND-FREE-SAMPLES`、`SND-LOAD-MOD`、`SND-PLAY-MOD`、`SND-STOP-MOD`、`SND-MOD-PLAYING`、`SND-STYLE`。それぞれの説明は `HELP` で見られます。`SND-LOAD-SAMPLE` と `SND-LOAD-MOD` は、エラーを THROW せずに ior を返します。

エラー: `-Daudio=false` の版の `REQUIRE-AUDIO` は `AUDIO UNAVAILABLE !`（THROW -275）、範囲外の数は `NUMBER ERROR !`、音のスレッドを持たないホストでは `HOST FUNCTION UNAVAILABLE !` です。`REQUIRE-GRAPHICS` と同じく、ライブラリの読み込みに失敗したときは加えたものを取り除き、`FORGET` や `MARKER` で消したあとは `REQUIRE-AUDIO` でもう一度読み込めます。

`examples/music.fs` は、各機種で短い曲を鳴らし、いくつかの機種を1つの `PLAY` で鳴らし、`SAMPLE` で作った効果音を鳴らします。

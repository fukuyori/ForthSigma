# FORTH/Σ グラフィックスとサウンドのマニュアル

LinuxビルドはローカルX11/XWaylandのウィンドウを既定で有効にする。`-Dx11=false`で除外できる。自動表示は共通5秒の期限内でnative、Tk、端末の順に探索する。Wayland直接接続とnativeのTCP/SSH接続は未対応。検証した環境と制限は[Linux検証記録](LINUX_NATIVE_VALIDATION.md)を参照。

英語版（正）: [GRAPHICS_AND_SOUND.md](GRAPHICS_AND_SOUND.md)。この日本語版は英語版の訳です。内容が異なる場合は英語版に従ってください。

Sigma のグラフィックスとサウンドは、この移植版の拡張です。誌面の FORTH/Σ には、どちらもありません。このマニュアルでは、描画、文字、Tcl/Tk、キー、マウス、アニメーション（`REQUIRE-GRAPHICS`）と、音楽、音源、録音した音、モジュール（`REQUIRE-AUDIO`）を説明します。Sigma の起動、言語、ほかの語は[ユーザーマニュアル](USER_MANUAL.ja.md)を、`SHOW` の表示先と色数は[グラフィックモードのマニュアル](GRAPHICS_MODES.ja.md)を参照してください。

## Boingデモ

赤白の市松模様の球が、色パレットの切替で回転し、格子の前で跳ねます。各ファイルは別々のプロセスで実行します。3つともグラフィックスと浮動小数点の語が必要で、`-Daudio=false`のビルドでは無音で動きます。

| ソース | 描画画像 | 初期ウィンドウ | フレーム制御 |
| --- | --- | --- | --- |
| [boing.fs](../examples/boing.fs) | 320×200 | 960×600（画素を3倍表示） | 1フレーム16ms |
| [boing-hd.fs](../examples/boing-hd.fs) | 960×600 | 960×600 | 1フレーム16ms |
| [boing-hfr.fs](../examples/boing-hfr.fs) | 1920×1200 | 1280×800 | 120fps目標 |

リポジトリのルートから実行します。

```sh
zig build -Doptimize=ReleaseFast
zig-out/bin/sigma examples/boing-hd.fs
zig-out/bin/sigma examples/boing-hfr.fs
```

Spaceで一時停止・再開、QまたはEscで終了します。キー入力はフォーカスのある窓または端末へ送ります。画面に合わせて窓をリサイズ・最大化できます。HD版とHFR版は床の格子を6段にし、床と壁で異なる、ゴムボールの打撃を模した合成音を使います。

HFR版は前の球・影の領域だけ背景を戻し、経過時間で動きを進めるため、フレームレートが下がってもシミュレーションの速度は落ちません。物理計算は最大8msの刻みで進め、停止後の経過時間は100msまでに制限します。負荷を下げるには、`DETAIL`を6から4に変えて1280×800描画にするか、`TARGET-FPS`を120から60に変えます。インデックス画像のパレットに収まるよう、`DETAIL`は1〜10とします。

HFR版にはネイティブの窓を推奨します。Tkや端末への出力は遅くなる場合があります。LinuxのReleaseFast版を専用Xvfbで240回動かした短い試験では、描画ループは約110〜116回／秒でした。モニターの実表示fpsの測定ではありません。非同期の`SHOW`ではフレームがまとめられる場合があり、実表示はバックエンド、画面のリフレッシュレート、負荷に依存します。16msと120fpsは制御上の目標値で、達成を保証する値ではありません。

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
| `SHOW` | ( -- ) | 画像を表示します。ホストにSigma自身のウィンドウがあれば（Windows、macOS、X11またはXWaylandのLinux）ウィンドウに、なければデスクトップで `wish` が起動できればTkのウィンドウに（[グラフィックモードのマニュアル](GRAPHICS_MODES.ja.md)を参照）、それもだめなら端末に、または `DISPLAY-TERMINAL`・`DISPLAY-WINDOW`・`DISPLAY-TK` で決めた先に表示します。 |
| `DISPLAY-AUTO` | ( -- ) | 明示した表示先と、このプロセスで記憶した自動選択の結果を解除します。次の `SHOW` はSigma自身のウィンドウ、デスクトップならTk、端末の順に試し、起動できた表示先を記憶します。保存した辞書には自動選択であることだけを残し、選ばれた表示先は引き継ぎません。明示した `DISPLAY-WINDOW` と `DISPLAY-TK` は別の表示先へ切り替わりません。 |
| `DISPLAY-TERMINAL`、`DISPLAY-WINDOW` | ( -- ) | `SHOW` の表示先を端末、またはウィンドウにします。ホストにウィンドウがなければ、`DISPLAY-WINDOW` は `HOST FUNCTION UNAVAILABLE !` になります。 |
| `WINDOW-SIZE` | ( w h -- ) | 次の `SHOW` から、ウィンドウ（と `DISPLAY-TK` のTkのウィンドウ）で、画像を w×h 画素の大きさの領域に表示します。各辺は1〜16384で、0 0（初めの値）なら画像と同じ大きさです。画像は縦横の比を保って入る最大の大きさで中央に描き、余りは黒にします。たとえば `160 120 GFX-INIT 640 480 WINDOW-SIZE` で、1画素を4×4で表示します。画像そのものと端末への表示は変えません。 |
| `FULLSCREEN` | ( flag -- ) | Sigma自身のウィンドウで画面全体を覆う（真）か、元の位置と大きさのウィンドウに戻す（偽）かを切り替えます。画面の解像度は変えません。画像はウィンドウと同じく、縦横の比を保って入る最大の大きさで描き、余りは黒にします。フルスクリーンにするとキー入力のフォーカスを、システムが許す範囲で取ります（Windowsでは、利用者がほかのプログラムを前面で使っている間は取れません。その場合はウィンドウをクリックするとキーが届きます）。利用者はAlt+Enter（macOSではControl+Command+F）で解除でき、このキーは `INKEY` に届きません。`SHOW` が表示先を決める前なら、ウィンドウはフルスクリーンで開きます。ウィンドウを閉じても、次の `SHOW` はフルスクリーンで開き直します。`DISPLAY-TERMINAL` では `HOST FUNCTION UNAVAILABLE` です。Windows、macOS（フルスクリーンのSpaceになります）、Linux（ウィンドウマネージャーがEWMHのフルスクリーンで画面を覆います）のウィンドウと、`DISPLAY-TK` のTkのウィンドウ（`wm attributes -fullscreen`。画像はTkのとおり整数倍で拡大します）が対応します。 |
| `FULLSCREEN?` | ( -- flag ) | 今フルスクリーンを求めているかを返します。利用者がキーで解除した後は偽です。 |
| `MOUSE-CURSOR` | ( flag -- ) | ネイティブまたはTkのウィンドウの画像上で、マウスカーソルを表示する（真）か隠す（偽）かを切り替えます。初めは表示します。 |
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

Windowsのウィンドウは専用のスレッドで動くので、Forthが入力を待っている間も、動かす・大きさを変える（画像はそれに合わせて伸び縮みします）・閉じることができます。キー入力はコンソールのままです。`SHOW` のたびに今の画像を描き直し、画像の大きさか `WINDOW-SIZE` の大きさが変わればウィンドウの大きさも合わせます（`WINDOW-SIZE` がなければ、1600×1200画素より大きい画像や、タスクバーを除いた画面の作業領域に入らない画像は縮めて表示します）。大きさを合わせたウィンドウは、入る範囲で作業領域の中へ動かします。Windows 10 1703以降では、ウィンドウは画面ごとのDPIに対応していて、大きさは画面の画素で数えます。そのためWindowsが画像を引き伸ばすことはなく、拡大率が100%より大きい画面では、同じ `WINDOW-SIZE` でも、Windowsが拡大していた以前のSigmaより小さく見えます。DPIの違う画面へ移したウィンドウは、描画領域をDPIの比で拡縮します（100%で640×400なら150%で960×600）。それより古いWindowsでは、ウィンドウはDPIに対応しません。ウィンドウの大きさを変えると、画像は縦横の比を保って描き直し、余りは黒にします。`MOUSE` はマウスの下の画像の画素を返します。ウィンドウがフォーカスかマウスを失ったときは、押していたボタンを離したことにし（`MOUSE-EVENT` にも離したことが届きます）、ウィンドウを閉じたあとの `MOUSE` は -1 -1 を返します。閉じたウィンドウは、次の `SHOW` で開き直します（ウィンドウが閉じるのとちょうど同時に表示した画像は、そのときまで表示されないことがあります）。`SHOW` がウィンドウの作成を待つのは最大5秒で（自動表示が初めて表示先を選ぶときは、ウィンドウとTkのウィンドウで合わせて5秒、ウィンドウはそのうち最大2秒）、時間内に作れなければ、Sigmaが終わるまでウィンドウを作り直しません。自動表示では、初めて表示先を選ぶときならTkのウィンドウか端末へ進みます。すでにウィンドウを選んでいたときは、その `SHOW` が `HOST FUNCTION ERROR`（-265）になり、次の `SHOW` で次の表示先へ進みます。`DISPLAY-WINDOW` のときは -265 になります。macOSにもSigma自身のウィンドウ（AppKit）があり、LinuxにはX11またはXWaylandのウィンドウがあります（このページの冒頭を参照）。ほかでは、`SHOW` は、Tcl/Tkのあるデスクトップではそのウィンドウに、ほかでは端末に表示します。

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
| `IMAGE-MODE` | ( n -- ) | `COPY-RECT` と `PUT-IMAGE` が画素を置く方法。0 は上書き（初めの値）、1 は XOR、2 は加算（赤・緑・青の各色は255まで）、3 は `IMAGE-ALPHA` の濃さで混ぜます。透明色の画素は先に除きます。 |
| `IMAGE-ALPHA` | ( n -- ) | モード3で写すものの濃さ。0 は写さず、255 はそのまま、初めは128です。各色は `(写すもの × n + 元の色 × (255 − n) + 127) ÷ 255` です。 |
| `IMAGE-SCALE` | ( n -- ) | `COPY-RECT` と `PUT-IMAGE` は、1画素を n×n で描きます。1（初めの値）〜16で、長方形は描画先で w×n、h×n の大きさになります。反転、透明色、モードも合わせて効きます。 |
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

画像を指さないハンドル（作っていない、解放した、`SAVE` や `SAVESYS` の前から持っていた）は `INVALID IMAGE HANDLE !`（THROW -278）です。同じ画像の重なる場所へ反転または拡大して写すと `NUMBER ERROR !` になるので、別の画像を経由して写してください。`IMAGE-FLIP`、`IMAGE-MODE`、`IMAGE-ALPHA`、`IMAGE-SCALE` の範囲外の値も `NUMBER ERROR !` です。画像は画面と同じく辞書の一部ではありません。辞書を復元すると（`SAVESYS` で作った実行ファイルの起動も）すべて解放されるので、プログラムは起動後に画像を作ります。保存した辞書の変数に残したハンドルは、新しい画像が同じ位置と世代番号になると、偶然その画像を指すことがあります。ハンドルを残さずに、画像を作り直してください。`TRANSPARENT`、`IMAGE-FLIP`、`IMAGE-MODE`、`IMAGE-ALPHA`、`IMAGE-SCALE` の値は、`COLOR` と同じくライブラリの変数で、辞書と一緒に保存されます。下にある `GFX-` の語は、`GFX-IMAGE-NEW` ( w h -- img )、`GFX-IMAGE-FREE` ( img -- )、`GFX-IMAGE-SIZE` ( img -- w h )、`GFX-TARGET` ( img -- )、`GFX-TARGET@` ( -- img )、`GFX-COPY` ( src sx sy w h dx dy key flip mode alpha scale -- )、`GFX-IMAGE-LOAD` ( c-addr u key -- img ior ) です。`GFX-COPY` の key は透明色で、負の数なら透明色なしです。`GFX-IMAGE-LOAD` の key は透明な画素に付ける色です。

### 文字

`TEXT` は、文字列を今のフォントで描きます。初めは組み込みのフォントで、美咲ゴシック（門真なむ氏、自由に利用できるフォント。[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) を参照）のASCIIの文字を、幅4画素・高さ8画素で描きます。`LOAD-FONT` はBDFのフォントファイルを読んで使い（どのOSでも）、`SYSTEM-FONT` はシステムに登録されたフォントを名前で使います（Windows、macOS、Linux）。文字列はUTF-8として読み、フォントにない文字は1つの `?` で描きます（フォントに `?` もなければ描きません）。UTF-8でないバイトも1バイトごとに同じです。制御文字は描きません。

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
| `SYSTEM-FONT` | ( c-addr u height -- ) | システムのその名前のフォント（Windowsでは `Consolas`、`MS Gothic`、`メイリオ` など、macOSでは `Hiragino Sans`、`HiraginoSans-W3`、`ヒラギノ角ゴシック`、`Osaka` など、Linuxでは `DejaVu Sans`、`Noto Sans CJK JP` など）を、1行 height 画素（1〜256）で、灰色の濃淡でなめらかにして使う。macOSでは、ファミリー名、フルネーム、PostScript名と、それを利用者の言語で表した名前で探す。Linuxでは、Sigmaがフォントファイル（TrueTypeとOpenType：`.ttf`、`.otf`、`.ttc`、`.otc`）を自分で読む。`/usr/share/fonts`、`/usr/local/share/fonts`、`~/.local/share/fonts`（または `$XDG_DATA_HOME/fonts`）、`~/.fonts` の下を探し、ファミリー名、フルネーム、PostScript名のどれかが指定の名前と同じフォントを使う（どの言語の名前でもよく、ASCIIの大文字と小文字は区別しない）。ファミリー名で指定したときは、標準の太さのフォントを使う。名前に `/` があれば、フォントファイルのパスとして扱う（コレクションなら最初のフォント）。Sigmaにフォントは入っていない。アクセント付きの文字を2つの字形から組み立てる一部のOpenTypeフォント（URWの `C059` など）では、アクセントなしで描かれる。フォントファイルの破損は検査しないので、信頼できるファイルだけを指定すること。フォントにない文字は `?` で描き、ほかのフォントで補わない。WindowsではU+10000以上の文字も `?` で描く。その名前のフォントがなければ `FONT ERROR !`（Linuxでは、パスのファイルがフォントでないときも）。 |
| `BUILTIN-FONT` | ( -- ) | 組み込みのフォントに戻す。 |
| `GFX-GLYPH-LOAD` | ( code -- advance \| -1 ) | 今のフォントの文字番号の字形を読み込み、ペンを進める幅を返す。フォントになければ -1。 |
| `GFX-GLYPH-BOX` | ( -- left width height ) | 読み込んだ字形の箱。ペンから `left` 画素右（負なら左）、行の上端から。 |
| `GFX-GLYPH-ALPHA` | ( x y -- a ) | 読み込んだ字形の箱の x y の濃さ。0（なし）〜255（全面）。箱の外は0。 |
| `GFX-FONT-HEIGHT` | ( -- h ) | 今のフォントの1行の高さ。 |
| `GFX-FONT-LOAD`, `GFX-FONT-SYSTEM`, `GFX-FONT-BUILTIN` | ( c-addr u -- ior ), ( c-addr u height -- ior ), ( -- ) | `LOAD-FONT`、`SYSTEM-FONT`、`BUILTIN-FONT` と同じだが、ior（0、ファイルのエラー、-272）を返す。 |

フォントは辞書の一部ではありません。`SAVE` と `SAVESYS` は保存せず、プログラムは画像がない状態で始まるのと同じく、組み込みのフォントで始まります。BDFのフォントは論理メモリの外に置きます。`LOAD-FONT` ではどのBDFフォントも使えます。例えば、漢字を含む美咲ゴシック全体（<https://littlelimit.net/misaki.htm> の `misaki_gothic.bdf`）を読み込めば、同じプログラムがどのOSでも同じ画素を描きます。システムのフォントは、OSによって描き方もフォントの名前も違います。

### Tcl/Tk

TCL の語は、Sigmaが別のプログラムとして起動するTcl/Tkのインタープリター（`wish`）でTclのスクリプトを実行します。最初に必要になったときに起動し、パイプでやり取りします。SigmaにTclのライブラリはリンクしません。これで、Tkの部品（ウィジェット）を使えるほか、`DISPLAY-TK` で画像をTkのウィンドウに表示できます。Sigma自身のウィンドウがない環境でも使えます。Tcl/Tkが入っている必要があり、`TCL-PROGRAM` で指定したプログラム、なければ環境変数 `SIGMA_WISH`、なければ `PATH` の `wish`、Windowsではそれもなければ Git for Windows に付いているもの（`%ProgramW6432%`、`%ProgramFiles%`、`%LOCALAPPDATA%\Programs` の下の `Git\mingw64\bin\wish.exe`。ふつうは `C:\Program Files\Git\mingw64\bin\wish.exe`）を使います。Linuxでは `tk` のパッケージにあります。macOSでは `brew install tcl-tk` で入れます。システムの `/usr/bin/wish`（Tcl/Tk 8.5）は最近のmacOSでは起動しないので、Sigmaは `PATH` のそれを飛ばし、`PATH` にほかの `wish` がなければ、Homebrewのもの（`/opt/homebrew/bin/wish`、`/usr/local/bin/wish`）かMacPortsのもの（`/opt/local/bin/wish`）のうち、最初にあるものを使います。

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
S" expr {6 * 7}" TCL-EVAL TYPE                  \ 42
S" button .b -text Press -command {sigma_event pressed}; pack .b; wm deiconify ." TCL
: WAIT-PRESS   BEGIN TCL-EVENT 0= WHILE 10 MS REPEAT TYPE ;
WAIT-PRESS                                       \ ボタンを押すと pressed
```

`examples/calculator.fs` は、まとまったプログラムの例です。ボタンとキーはTkで、計算はForthで行う電卓です（`sigma.exe < examples/calculator.fs`）。 `examples/graphs-tk.fs` は、`examples/graphs.fs` と同じ8つのグラフを、Tkのcanvasに線、長方形、扇形、円、文字として描きます。位置の計算はForthで行い、1コマ分のTclのスクリプトをまとめて送ります。

| 語 | スタック | 説明 |
| --- | --- | --- |
| `TCL` | ( c-addr u -- ) | Tclのスクリプト（UTF-8）を大域で実行する。失敗すると `TCL ERROR !`（THROW -273）。 |
| `TCL-EVAL` | ( c-addr u -- c-addr2 u2 ) | Tclのスクリプトを実行して結果を返す。結果は次のスクリプトまで有効。 |
| `TCL-ERROR$` | ( -- c-addr u ) | 最後に失敗したスクリプトのメッセージ。 |
| `TCL-EVENT` | ( -- c-addr u true \| false ) | Tcl側が `sigma_event` で送った次の文字列（ボタンの `-command` からなど）を、待たずに返す。文字列は次の `TCL-EVENT` まで有効。 |
| `TCL-PROGRAM` | ( c-addr u -- ) | 次に起動するプログラム（`PATH` の名前かパス）。空なら `SIGMA_WISH`、`wish`、Git for Windows のもの、macOSではHomebrewかMacPortsのもの。 |
| `TCL-STOP` | ( -- ) | プログラムを終える。次の `TCL` で起動し直す。Sigmaの終了時にも終える。プログラムが書いてSigmaがまだ読んでいないものは捨てる。ホストがプログラムの終わりを確かめられなかったときは `HOST FUNCTION ERROR !`。 |
| `DISPLAY-TK` | ( -- ) | `SHOW` で、画像をTkのウィンドウ `.` に表示する（PNGで送り、`DISPLAY-COLORS` の色数に従う）。そこで押したキーとマウスは `INKEY` と `MOUSE` に届く。ウィンドウを閉じると、次の `SHOW` まで隠れる。`WINDOW-SIZE` があれば、画像は入る最大の整数倍で表示し（Tkは整数倍でしか拡大しないため）、入らなければ整数分の1に縮めます。ウィンドウの大きさを変えたときも同じです。 |
| `GFX-TCL`、`GFX-TCL-ERROR`、`GFX-TCL-EVENT`、`GFX-TCL-PROGRAM`、`GFX-TCL-STOP`、`GFX-SHOW-TK` | | 下の層の語。`GFX-TCL` ( c-addr u -- c-addr2 u2 flag ) は、スクリプトのエラーでは THROW せず、結果か、真のフラグとメッセージを返す。プログラムを起動できないときと、プログラムが終わったときは、この語も `HOST FUNCTION ERROR !` になる。 |

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

`examples/paddle.fs` は、これらの語で作ったゲームです。3方の壁で跳ね返るボールを、上下キーで動かすパッドで打ち返します（`sigma.exe examples/paddle.fs`）。`examples/runner.fs`（Classic Runner）はもっと大きな例で、はしごを登り、ロープにぶら下がり、穴を掘り、追ってくる敵をかわしながら金塊を集めるタイルのゲームです。下の行に、1コマの処理にかかった時間と、1秒に表示したコマ数を出します。`examples/hopper.fs`（Sky Hopper）は横スクロールのアクションゲームです。2つのコースを走って跳び、敵を踏み、殻を蹴り、ブロックを下から叩いてコインや体が大きくなるベリーを出し、最後の気球に乗ります。キーと、mapped のゲームパッドで操作できます。`examples/shmup.fs`（Sigma Storm）は縦スクロールのシューティングゲームです。3つのステージに、敵の編隊、途中の空母、部位を壊せるボスがあり、5段階の武器、ボム、得点を増やすチェインがあります。キーと、mapped のゲームパッドで操作でき、専用の曲と効果音があり、F1 で1コマにかかる時間を表示します。 `examples/shmup-c64.fs` と `examples/shmup-amiga.fs` は、`examples/shmup.fs` と同じ縦スクロールのシューティングゲームを、コモドール64と Amiga の画面、色、音の雰囲気にしたものです。この3本はゲーム用の語で描きます。絵はシート上のスプライトで、自機の弾は画素が重なったところで敵に当たります（`PIXEL-HIT?`）。背景は色番号の絵で、海の面では水の色が回ります（Amiga 版の copper は、行の帯ごとのパレットで `GFX-INDEXED` で描きます）。雲は半透明で、爆発、レーザー、弾は光を加算して光り、ボムとボスの爆発では行が横に揺れます（`RASTER-SCROLL`）。`examples/klondike.fs` は、`MOUSE` で遊ぶカードゲームのクロンダイクです。カードや並びをドラッグして動かし、カードをクリックすると置ける場所へ送ります。1枚めくりと3枚めくり、Undo、ヒントがあります。カードはすべて起動時に描き、`GFX-HLINE` の線の集まりとして表示します。`examples/waterworks.fs`（Waterworks）は、青写真の上に水が来る前に管を置いて道を延ばすゲームです。岩、タンク、ポンプ、トンネル、排水口のある8つのステージがあり、マウスまたはキーで操作します。`examples/sweeper.fs`（Sonar Sweep）は、数字を手がかりに海底の機雷を探すゲームです。広さの違う3つの海域があり、最初に開くマスとその周りには機雷がありません。マウスまたはキーで操作します。`examples/pinball.fs`（Ninth Inning）は、古い木製の台の写真をもとに盤面を配置した、野球場のピンボールです。ボーナス倍率を上げる4つのレーン、4つのドロップターゲット、3つのターゲット、ダグアウトとキックアウトの穴があり、塁に出た走者がホームに還ると得点になります。玉の物理は固定小数点で1コマに8回計算します。

| 語 | スタック | 説明 |
| --- | --- | --- |
| `INKEY` | ( -- key \| -1 ) | 押されたキーを待たずに1つ返す。なければ -1。文字はそのバイト（UTF-8の文字は1バイトずつ順に）、Enter は13、Backspace は8、Tab は9、Esc は27。Ctrl+C は `USER INTERRUPT !`（-28）を THROW する。 |
| `K-UP`, `K-DOWN`, `K-LEFT`, `K-RIGHT`, `K-HOME`, `K-END`, `K-PRIOR`, `K-NEXT`, `K-INSERT`, `K-DELETE`, `K-F1` .. `K-F12` | ( -- key ) | 文字でないキーに `INKEY` が返す番号（256〜277）。 |
| `MOUSE` | ( -- x y buttons ) | 最後に動いたときにマウスの下にあった画像の画素と、押されているボタン（1 左、2 右、4 中）。位置が分からない間は -1 -1。その間に押されたキーは `INKEY` のために残る。 |
| `MOUSE-EVENT` | ( -- x y button kind true \| false ) | まだ読んでいないマウスのイベントのうち最も古いもの。待たずに読み、なければ偽。kind は 1 押下、2 解放（button は 1 左、2 右、4 中）、3 ホイールの1刻み（button は 1 上（向こう側）、-1 下）で、x y はそのときの画像の画素。`MOUSE` と違い、2回の読み取りの間の押下と解放の両方を残す。64個まで残し、それを超えると古いものから捨てる。その間に読んだキーは `INKEY` のために残る。端末は `MOUSE-ON` の後にホイールを報告する（横の回転は報告しない）。Tk のウィンドウは `<MouseWheel>` と、X11 ではボタン4と5から報告する。 |
| `MOUSE-ON`, `MOUSE-OFF` | ( -- ) | 端末にマウスの報告を頼む、または止める。ウィンドウはいつも報告する。 |
| `FRAME` | ( ms -- ) | 前の `FRAME` から ms ミリ秒たつまで待ってから `SHOW` する。描いて `FRAME` を呼ぶループは一定の間隔で動く。描くのに時間がかかったときは待たない。 |
| `KEY-HELD?` | ( key -- flag ) | そのキー（1バイトの文字か、`K-UP` などの番号）を今押しているか。キーボードがキーを繰り返すのを待たずに（最初に約0.5秒待つ）、押している間動かすゲームに使う。Windowsのコンソール、ウィンドウ、Tkのウィンドウはキーを離したときと、フォーカスを失ったときを知らせる。LinuxとmacOSの端末は知らせないので、最後に押してから0.6秒は押しているとみなす（押し続けると繰り返されるので、押している間は続く。繰り返しが始まった後は、最後の繰り返しから0.12秒で、離すとすぐ止まる）。端末は最後に押したキーしか繰り返さないので、方向キーは、別の方向キーを押すと押していないことになる。その間に読んだキーは `INKEY` のために残る。 |
| `GFX-INKEY`, `GFX-MOUSE`, `GFX-KEY-HELD` | `INKEY`, `MOUSE`, `KEY-HELD?` と同じ | 下の層の語。 |
| `GFX-MOUSE-MODE` | ( flag -- ) | 真で `MOUSE-ON`、偽で `MOUSE-OFF` と同じ。 |

最初の `INKEY` か `MOUSE` で、端末はキーを1つずつ、エコーなしで渡すようになります。Sigmaは、次に行や `KEY` を読むとき、`SYSTEM` を実行するとき、終わるときに、プログラム向けに打たれた入力を捨てて、端末を行入力に戻します。キーを1つずつ渡している間は、Ctrl+C でSigmaは終わりません。Ctrl+C は `INKEY` に届き、`INKEY` が THROW するので、キーを読むループはこれで止められます（`INKEY` も `MOUSE` も呼ばなくなったループは止められません）。標準入力が端末でないときは、`INKEY` はウィンドウのキーだけを受け取ります。

LinuxとmacOSでは、文字でないキーは端末からエスケープシーケンスで届き、`INKEY` が解読します。バイトが分かれて届く並び（遅い回線など）は、残りを50 msまで待ち、その間に何も続かない Esc は Esc キーとします。マウスは、xterm のSGR形式の報告で届きます。多くの端末（xterm、GNOME Terminal、iTerm2、Windows Terminal など）が送ります。`MOUSE-ON` で頼み、`MOUSE-OFF`、行入力に戻るとき、終わるときに止めます。Windowsでは、コンソールがキーとマウスをそのまま渡します。キーを1つずつ渡している間は、コンソールのマウスでの範囲選択は止まります。ウィンドウで押したキーも `INKEY` に届き、ウィンドウのマウスは、引き伸ばした画像のうちマウスの下にある画素を返します。

端末でマウスの下の画素を求めるため、Sigmaは `SHOW` で画像を描いた後に、端末にカーソルの位置を問い合わせます（`MOUSE-ON` の後だけ）。そのため、位置は `MOUSE-ON` の後の最初の `SHOW` から分かります。半角ブロックでは1文字が2画素で、Sixelでは文字の大きさを端末から得るか、10×20画素と仮定します。

端末への `SHOW` は、間に何も書いていなければ、前に描いた画像の上に描きます。そのため、アニメーションは流れずに同じ場所で動きます。間に何か書いたとき（プロンプトなど）は、下に新しく描きます。Sixelでは、画像が占める行数を文字の高さから数えるので、端末によっては合わないことがあります。 `STDOUT WRITE-FILE`・`WRITE-LINE`の直接出力も次の画像を新しい位置に描く契機になります。通常のファイル出力や文字列だけへのキャプチャは再描画位置に影響しません。`SYSTEM`・`SH`・外部エディタのコールバックは出力量をVMで数えられないため、無出力や失敗時も安全側で次の画像を新しい位置から描きます。

### GUI

`REQUIRE-GUI` は GUI の語を `GUI` 語彙に読み込みます（グラフィックスの語が読み込まれていなければ、先に読み込みます）。`ALSO GUI` で使えるようになります。語はすべて Forth で書かれているので、GUI の語を読み込んだ辞書は、グラフィックスの語を読み込んだ辞書と同じ形式で保存されます。ボタン、チェックボックス、入力欄、リスト、メニューバーとプルダウンメニュー、ファンクションキー欄、パネル、ダイアログを、描画先の画像（`DRAW-TO`）に描きます。見た目は平らなもので、色と線の太さは設定で変えられます。名前はすべて `GUI-` で始まるので、プログラムの語を隠しません。

部品は毎フレーム描き直します。`GUI-BEGIN` と `GUI-END` の間で各部品の語を呼ぶと、その部品を描き、そのフレームで利用者が部品に何をしたかを返します。部品が表す値（チェックボックスのフラグ、入力欄の文字、リストの選択）は、プログラムの変数に持ちます。`GUI-BEGIN` は、マウス（`MOUSE-EVENT` を使うので、フレームの間のクリックも取りこぼしません）、キー、最初のゲームパッドを1回だけ読みます。どの部品も取らなかったキーは、次の `GUI-BEGIN` まで `GUI-KEY` で読めます。キーはフォーカスのある部品に行きます。クリックするとその部品に、Tab で次の部品にフォーカスが移ります。フォーカスのある部品がなければ、フォーカスを取れる最初の部品がフォーカスを持ちます。最初のゲームパッドは `GAMEPAD-MAPPED?` が真のときだけキーとして働きます。十字キーが矢印、A が Enter、B が Esc です。raw のパッドはGUIでは無視します。静的Linux musl版はevdevのraw入力を使います（[制限と検証状況](LINUX_NATIVE_VALIDATION.md)）。

確認したUSB 0583:a021の機器では、起動時と再接続後、機器から入力が報告されるまでrawの軸が-32768になります。この初期値を中立位置として扱わないでください。操作後に手を離した軸は128でした。evdevバックエンドは機器のデッドゾーンを適用しないため、raw軸を使うプログラム側で処理します。このバックエンドではmapped配置とGAMEPAD-MAPは利用できません。

部品には、フレームの中でプログラムが作った順に番号が付きます。GUI がフレームをまたいで持つ値は4つの変数にあり、プログラムは `BASE` と同じように読み書きできます。`GUI-FOCUSED` はキーが行く部品で、フォーカスを取れる部品の中で1から数えます（範囲の外なら、次のフレームで最初の部品が取ります）。`GUI-ACTIVE` は左ボタンが押された部品で、すべての部品の中で1から数え、なければ0です。`GUI-MENU-OPEN` はメニューバーの開いているメニューで、0から数え、なければ -1 です。`GUI-MENU-ITEM` は開いているメニューの強調している項目です。あるフレームでだけ作る部品があると、その後の部品の番号がずれます。そのようなプログラムは、`GUI-FOCUSED` を設定し直すか、その部品を最後に作ります。

| 語 | スタック | 動作 |
|---|---|---|
| `GUI-BEGIN`、`GUI-END` | ( -- ) | フレームの GUI を始める、終える。`GUI-END` は開いているプルダウンメニューをほかの部品の上に描きます。 |
| `GUI-BUTTON` | ( c-addr u x y -- flag ) | ボタン。クリックされたとき、またはフォーカスがあって Enter か Space が押されたときに真。大きさは `GUI-BUTTON-SIZE` ( c-addr u -- w h ) で分かります。 |
| `GUI-CHECK` | ( addr c-addr u x y -- flag ) | ラベル付きのチェックボックス。ボックスかラベルのクリック、または Space か Enter で addr のフラグが変わり、変わったときに真。 |
| `GUI-FIELD` | ( buf room len-addr x y w -- flag ) | 幅 w 画素の1行の入力欄。buf の文字列（room バイトまで、長さは len-addr）を編集します。`INKEY` が返す文字のバイト（UTF-8 も）、Backspace、Delete、左右の矢印、Home、End が使えます。TkのウィンドウとSigma自身のウィンドウ（Windows、macOS、X11またはXWaylandのLinux）では、フォーカスがある間、IMEで日本語を変換して入力できます。変換中の文字はカーソルの位置に下線つきで表示され、候補ウィンドウはカーソルに付いて動き、確定した文字だけが入ります。Enter が押されたときに真。 |
| `GUI-LIST` | ( c-addr u var x y w -- flag ) | 項目 "a\|b\|c" を縦に並べた、幅 w 画素のリスト（0 なら最も広い項目に合わせます）。var のセルが選んでいる項目で、マウスを項目の上に置くか、フォーカスがあるときの上下の矢印で選びます。項目をクリックしたとき、または Enter か Space で真。 |
| `GUI-LIST-XT` | ( xt n var x y w -- flag ) | 同じリストを、xt ( i -- c-addr u ) が返す n 個の項目で作ります。項目はプログラムのどのデータ（文字列の配列、ディレクトリの一覧など）にあってもよく、\| を含めることもできます。項目がなければ何も描きません。 |
| `GUI-MENUBAR` | ( c-addr u -- n ) | 項目 "a\|b\|c" の見出しを並べた、上端のバー。見出しをクリックするとそのメニューが開きます（もう一度で閉じる）。開いている間は、ほかの見出しの上にマウスを置くか、左右の矢印でそのメニューに移り、Esc で閉じます。開いているメニューの番号を返し、なければ -1。`GUI-BEGIN` のすぐ後に呼びます。 |
| `GUI-MENU` | ( c-addr u -- item \| -1 ) | `GUI-MENUBAR` のすぐ後で、開いているメニューの項目を描きます。"-" は区切り線、`~` で始まる項目は灰色で選べません。このフレームでクリックか Enter で選ばれた項目を返し、なければ -1。上下の矢印で選べる項目の間を移ります。メニューの外をクリックすると閉じます。メニューが開いている間は、キーとメニュー上のマウスはメニューが取ります。 |
| `GUI-FKEYS` | ( c-addr u -- n \| -1 ) | F1、F2… のラベル "a\|b\|c" を並べた、下端のバー。押されたキーかクリックされたラベルの番号（F1 は0）を返し、なければ -1。 |
| `GUI-PANEL` | ( x y w h -- ) | パネル。部品のまとまりの背景と枠を描きます。 |
| `GUI-TILES` | ( img size -- ) | パネルを、画像の9枚のタイルで描くようにします。タイルは各辺 size 画素で、画像の左上から3×3（角、辺、中央）。`0 0 GUI-TILES` で枠に戻ります。 |
| `GUI-LABEL` | ( c-addr u x y -- ) | `GUI-TEXT` の色の文字。 |
| `GUI-ENABLE` | ( flag -- ) | 偽にした後の部品は灰色で描き、入力を受けません。真にするか、次の `GUI-BEGIN` まで続きます。 |
| `GUI-KEY` | ( -- key \| -1 ) | このフレームでどの部品も取らなかった次のキー。 |
| `GUI-DIALOG` | ( c-addr u c-addr2 u2 -- n \| -1 ) | メッセージとボタン "a\|b" のダイアログを中央に描きます。このフレームで選ばれたボタンの番号（最初は0）を返し、なければ -1。Esc は最後のボタンです。 |
| `GUI-YES-NO` | ( c-addr u -- n ) | はい（Yes）といいえ（No）のダイアログ。はいなら1、いいえ（Esc も）なら0、答えがない間は -1。 |
| `GUI-ASK` | ( c-addr u -- flag ) | はい/いいえで尋ね、答えを待ちます。はいなら真。 |
| `GUI-MESSAGE` | ( c-addr u -- ) | メッセージを OK と一緒に出し、閉じられる（OK、Enter、Esc）まで待ちます。 |
| `GUI-CHOOSE` | ( c-addr u -- n ) | リスト "a\|b\|c" を中央に出し、選ばれるまで待ちます。最初の項目は0、Esc なら -1。 |
| `GUI-CHOOSE-XT` | ( xt n -- n ) | 同じことを、xt ( i -- c-addr u ) が返す n 個の項目で行います。項目がなければ、すぐに -1 を返します。 |

`GUI-ASK`、`GUI-MESSAGE`、`GUI-CHOOSE` は画面に描き、答えが出るまで毎フレーム画面を表示します（`SHOW`、`16 FRAME`）。始めたときの画面の上に描き、終わると画面を元に戻します。その間、プログラムは進みません。Ctrl+C で止まります（`USER INTERRUPT`）。

```forth
REQUIRE-GUI  ALSO GRAPHICS ALSO GUI
320 200 GFX-INIT
VARIABLE SOUND-ON   CREATE NAME 16 ALLOT  VARIABLE NAME-LEN
: SETTINGS ( -- )
   BEGIN
      GUI-BACKGROUND GUI-COLOR@ GFX-CLS
      GUI-BEGIN
      SOUND-ON S" Sound" 10 10 GUI-CHECK DROP
      NAME 16 NAME-LEN 10 30 120 GUI-FIELD DROP
      S" OK" 10 60 GUI-BUTTON
      GUI-END  SHOW  16 FRAME
   UNTIL ;
```

色は役割ごとに `GUI-COLOR!` ( rgb role -- ) で設定し、`GUI-COLOR@` ( role -- rgb ) で読みます。`GUI-DEFAULT` で、すべての色と線の太さが初めの値に戻ります。

| 役割 | 使うところ | 初めの値 |
|---|---|---|
| `GUI-BACKGROUND` | パネル、ダイアログ、メニュー、バー | F0F0F0 |
| `GUI-FACE` | ボタン | E1E1E1 |
| `GUI-HOVER` | マウスの下のボタン | EBEBEB |
| `GUI-PRESSED` | 押されているボタン | C8C8C8 |
| `GUI-TEXT` | 文字 | 000000 |
| `GUI-DISABLED` | 使えない部品の文字 | 8C8C8C |
| `GUI-BORDER` | 枠と線 | 8A8A8A |
| `GUI-FIELD-FACE` | 入力欄とチェックボックス | FFFFFF |
| `GUI-FOCUS` | フォーカスのある部品の枠 | 3A73D9 |
| `GUI-SELECTION` | リストやメニューで選んでいる項目 | 3A73D9 |
| `GUI-SELECTED-TEXT` | 選んでいる項目の文字 | FFFFFF |

`GUI-BORDER-WIDTH` ( n -- ) と `GUI-FOCUS-WIDTH` ( n -- ) で、枠とフォーカスの枠の太さを0〜8画素で設定します（初めは1）。ほかの値は `NUMBER ERROR !` です。文字は `TEXT` の字体と倍率を使い、部品の大きさは `TEXT-HEIGHT` に合わせます。入力欄は、カーソルが見える位置から文字を表示します。ほかのグラフィックスの語と同じく、GUI は辞書の外に何も持たず、設定とプログラムの変数の値は辞書と一緒に保存されます。

### スプライトとタイルマップ

`REQUIRE-GAME` はゲーム用の語を `GAME` 語彙に読み込みます（グラフィックスの語が読み込まれていなければ、先に読み込みます）。`ALSO GAME` で使えるようになります。語は、プログラムが作って持つデータを扱う小さな Forth の語です。スプライトと地図は辞書の中の構造体で、`SPRITE:` か `TILEMAP:` で作ります（配列なら `/SPRITE` バイトの領域に `INIT-SPRITE`）。そのフィールドは、プログラムが `@` と `!` で読み書きします。何をいつ動かし、描き、調べるかはプログラムのループが決め、ライブラリがプログラムを呼び返すことはありません。

| 語 | スタック | 動作 |
|---|---|---|
| `SPRITE:` | ( img sx sy w h "name" -- ) | 画像 img の sx sy にある w×h の長方形を表示するスプライトを定義します。位置は0 0、表示する、1コマ、反転なし、透明色なしで始まります。name はそのアドレスを返します。 |
| `INIT-SPRITE` | ( img sx sy w h spr -- ) | 同じことを spr の `/SPRITE` バイトに行います。配列で使います: `CREATE ENEMIES 8 /SPRITE * ALLOT`。 |
| `PUT-SPRITE` | ( x y spr -- ) | スプライトを x y に置きます。 |
| `SPRITE-ANIM` | ( n delay spr -- ) | 最初のコマの右に並んだ n コマのアニメーション。各コマを `ANIMATE` の delay 回分表示します。 |
| `ANIMATE` | ( spr -- ) | アニメーションを1段進めます。 |
| `DRAW-SPRITE` | ( spr -- ) | 表示するスプライトを、コマ、反転、透明色に従って描画先に描きます。 |
| `HIT?` | ( spr1 spr2 -- flag ) | 表示する2つのスプライトの長方形が重なっているか。 |
| `PIXEL-HIT?` | ( spr1 spr2 -- flag ) | 表示する2つのスプライトが、同じ場所に画素を表示しているか（透明色は除きます）。 |
| `SPRITE-PIXEL?` | ( x y spr -- flag ) | スプライトが x y に画素を表示しているか。 |
| `TILEMAP:` | ( img tw th cols rows "name" -- ) | cols×rows タイルの地図を定義します（すべてタイル0）。タイル n は、画像 img の左上から行に沿って n 枚目の tw×th の長方形です。name はそのアドレスを返します。 |
| `TILE@`、`TILE!` | ( col row map -- n )、( n col row map -- ) | タイル（0〜255）を読む、設定する。地図の外は `NUMBER ERROR !`。 |
| `>TILE` | ( x y map -- col row ) | 地図の画素 x y の下にあるタイル。 |
| `DRAW-TILEMAP` | ( sx sy x y w h map -- ) | 描画先の x y にある w×h の長方形に、地図をその画素 sx sy から見た絵を描きます。描くのはその長方形だけで、その中のタイルだけを計算します。地図の外と、地図の透明色の画素は、元のままにします。 |

スプライトのフィールド（それぞれアドレスを返します）は、`SPRITE-X`、`SPRITE-Y`、`SPRITE-IMAGE`、`SPRITE-SX`、`SPRITE-SY`、`SPRITE-W`、`SPRITE-H`、`SPRITE-FRAMES`、`SPRITE-FRAME`、`SPRITE-DELAY`、`SPRITE-TICK`、`SPRITE-FLIP`（`IMAGE-FLIP` と同じ）、`SPRITE-KEY`（透明色、なしは -1）、`SPRITE-SHOWN` です。地図のフィールドは `TILEMAP-IMAGE`、`TILEMAP-TW`、`TILEMAP-TH`、`TILEMAP-COLS`、`TILEMAP-ROWS`、`TILEMAP-KEY` で、タイルのバイトは行ごとに `TILEMAP-DATA` ( map -- addr ) にあります。Amiga のような2枚の背景は、2つの地図で作ります。奥の地図を描き、次に手前の地図を透明色付きで描きます。スクロールは sx と sy を変えるだけです。

```forth
REQUIRE-GAME  ALSO GRAPHICS ALSO GAME
256 192 GFX-INIT
S" tiles.png" LOAD-IMAGE CONSTANT SHEET
SHEET 16 16 32 12 TILEMAP: LEVEL
SHEET 0 32 16 16 SPRITE: HERO   4 6 HERO SPRITE-ANIM
VARIABLE SCROLL
: STEP ( -- )
   1 SCROLL +!  HERO ANIMATE
   SCROLL @ 0  0 0 256 192 LEVEL DRAW-TILEMAP
   HERO DRAW-SPRITE  SHOW 16 FRAME ;
```

下にある語は、任意の画像の画素の色を返す `GFX-PIXEL` ( img x y -- rgb | -1 ) と、任意のアドレスにあるタイルのバイトの地図を描く `GFX-TILEMAP` ( addr cols rows img tw th sx sy x y w h key -- ) です。構造体は辞書にあるので、`SAVE` と `SAVESYS` で保存されます。ただし、画像のハンドルは復元の後は無効なので、プログラムは起動後に画像を作り、`SPRITE-IMAGE` と `TILEMAP-IMAGE` を設定し直します。

### パレットと行ごとの効果

これもゲーム用の語です。パレットは256セルで、色番号0〜255の色を持ちます。色番号の絵は、画素ごとに1バイトを持ちます。パレットの色を変えると、次にその絵を描いたとき、その番号の画素がすべて変わります。色を順に回して水の流れや光の動きを表すのは、この方法です。行ごとの効果は、描いた後の描画先を、行ごとに表の自分のセルの値で変えます。走査線ごとにレジスタを書き換えたビデオチップと同じ効果です。色の数、1行に表示するスプライトの数、表の中身は、プログラムが決める数です。

| 語 | スタック | 動作 |
|---|---|---|
| `PALETTE:` | ( "name" -- ) | パレットを定義します（すべて黒）。name はそのアドレスを返します。 |
| `PALETTE!`、`PALETTE@` | ( rgb n pal -- )、( n pal -- rgb ) | 番号 n の色を設定する、読む。0〜255 の外は `NUMBER ERROR !`。 |
| `ROTATE-PALETTE` | ( first count pal -- ) | 番号 first から first + count - 1 の色を1つずつ上へ回します。各番号は1つ下の番号の色になり、first は最後の番号の色になります。 |
| `INDEXED:` | ( w h "name" -- ) | w×h の色番号の絵を定義します（すべて0）。フィールドは `INDEXED-W` と `INDEXED-H` で、バイトは行ごとに `INDEXED-DATA` ( pic -- addr ) にあります。 |
| `INDEX@`、`INDEX!` | ( x y pic -- n )、( n x y pic -- ) | 画素の色番号を読む、設定する。絵の外は `NUMBER ERROR !`。 |
| `DRAW-INDEXED` | ( x y pic pal key -- ) | 絵を描画先の x y に、パレットの色で描きます。番号 key の画素は描きません（なしは -1）。 |
| `RASTER-SCROLL` | ( table x y w h -- ) | x y にある w×h の長方形の各行を、h セルの表の自分のセルの数だけ右へずらします（負の数なら左）。片側から出た画素は反対側から入ります。 |
| `RASTER-COLOR` | ( table rgb x y w h -- ) | 長方形の各行で、色 rgb の画素を、表の自分のセルの色にします。 |
| `DRAW-SPRITES` | ( array n limit -- ) | `/SPRITE` 構造体の配列の n 個のスプライトを順に描きます。ただし各行には、その行に表示する最初の limit 個だけを描き、後のスプライトはその行が欠けます。limit が0なら、すべて描きます。 |

```forth
REQUIRE-GAME  ALSO GRAPHICS ALSO GAME
256 192 GFX-INIT
PALETTE: PAL   16 16 INDEXED: WAVE
$0000AA 1 PAL PALETTE!  $3355FF 2 PAL PALETTE!  $AACCFF 3 PAL PALETTE!
: MAKE-WAVE ( -- )   16 0 DO 16 0 DO  I J + 3 MOD 1+  I J WAVE INDEX!  LOOP LOOP ;  MAKE-WAVE
CREATE WOBBLE 192 CELLS ALLOT
: STEP ( n -- )
   192 0 DO  DUP I + 8 / 1 AND 2*  WOBBLE I CELLS + !  LOOP DROP
   1 3 PAL ROTATE-PALETTE
   0 GFX-CLS  100 80 WAVE PAL 0 DRAW-INDEXED
   WOBBLE 0 0 256 192 RASTER-SCROLL  SHOW 16 FRAME ;
```

下にある語は、任意のアドレスの色番号を任意の256セルの色で描く `GFX-INDEXED` ( addr w h palette x y key -- )、`GFX-ROW-SHIFT` ( table x y w h -- )、`GFX-ROW-COLOR` ( table rgb x y w h -- ) です。

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

`examples/trig.fs` は、sin x・cos x・tan x のグラフを、格子、目盛りの文字、凡例とともに描きます。tan x が画像よりはるかに大きい所では `PLOT` に NaN を返し、漸近線のところでグラフを切ります（`sigma.exe examples/trig.fs`）。`examples/graphs.fs` は、棒グラフ、折れ線グラフ、円グラフ、散布図と回帰直線、ヒストグラム、関数のグラフ、リサージュ図形、極座標のバラ曲線の8つを、描き進めるアニメーションで順に表示します（Space か Enter で次へ、Q か Esc で終了）。

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

Sigma は、MSX BASIC の `PLAY` のように音楽を鳴らします。音は、機種の制限を持たない16声の「標準の音」で作ります。録音した音（WAV ファイル）と、ProTracker のモジュール（MOD ファイル）も鳴らせます。機種らしさ（MSX、Atari ST、NES、コモドール64、コナミの SCC、Amiga）は、`include/` のライブラリが加えます。ライブラリは標準の音の語だけで書いてあります。音は専用の音のスレッドが作るので、音楽が鳴っている間もプログラムは先へ進みます。音の語は、起動したときの辞書にはありません。`REQUIRE-AUDIO` を最初に実行したときに、`AUDIO` 語彙、`SND-` の語、Forth で書いた音のライブラリ（`src/audio/audio.fs`、プログラムに組み込み済み）が加わります。2回目以降は何もしません。グラフィックスの語と同じく検索順序は変えないので、`ALSO AUDIO` で語を見えるようにします。

```forth
REQUIRE-AUDIO
ALSO AUDIO
S" T150 O4 L8 CDEFGAB>C" PLAY               \ 声部A。MSX BASIC の PLAY "..." と同じ
S" O4 C2" S" O4 E2" S" O4 G2" PLAY3         \ 和音。3つの声部が同時に始まる
BEEP
1 INSTRUMENT PULSE 16384 DUTY 5 150 35000 100 ADSR   \ 音色1: 幅1/4のパルスで、だんだん小さくなる
2 INSTRUMENT TRIANGLE
: TUNE S" T120 L8 O4 @1 V12 CEGE CEGE" S" T120 L4 O3 @2 V12 CGCG" PLAY2 ;
TUNE
REQUIRE nes-sound.fs                        \ include/ のライブラリ
NES-SOUND                                   \ ここからは、音色が NES の段階になる
TUNE
```

`PLAY` は、MSX と同じく、音符が声部の待ち行列（各32個）に入りきったところで戻ります。そのあとは、音楽がひとりでに進みます。待ち行列がいっぱいの間、`PLAY` は待ちます。このとき Ctrl+C を押すと、音楽を止めて `USER INTERRUPT !`（THROW -28）になります。待っていないときの Ctrl+C は、これまでどおりです。音の出力装置がないときも、語は同じ時間で、音を出さずに動きます（どちらなのかは `AUDIO?` で分かります）。

セッションが終わると、Sigmaは音声の処理を止めて出力装置を解放します。待ち行列の音楽を最後まで鳴らすまで待つ動作ではありません。音声の後始末が完了しない場合は、`audio shutdown incomplete`を表示し、終了コード1で終わります。

単位はどの語でも同じです。周波数は Hz、時間はミリ秒、割合は 0〜65535、音程の差はセント（半音の1/100）です。引数はすべて整数です。

### MML（音楽の記述）

`PLAY` などの語は、MSX BASIC の MML（MSX Red Book が説明する MSX1 の ROM のもの）を受け付けます。大文字と小文字は同じに扱い、空白は読み飛ばします。声部ごとに、オクターブ、長さ、テンポ、音量、音色を、次の `PLAY` まで覚えています。`0 PLAYS` のあとも覚えています。`BEEP` で初期値に戻ります。コマンドだけの `PLAY`（`S" @1 V12" PLAY`）で、次の `PLAY` のためにこれらを設定できます。

| コマンド | 意味 |
| --- | --- |
| `A`〜`G` | 音符。`+` か `#`（シャープ）か `-`（フラット）、長さ 1〜64（省略すると `L` の値）、付点（1つごとに1.5倍）を続けられる。`B+` は同じオクターブの `C`、`C-` は同じオクターブの `B` になる（ROM の表のとおり）。 |
| `R` | 休符。長さ 1〜64（省略すると4）と付点。 |
| `N` | 番号 0〜96 で音符を指定する。オクターブは n / 12 + 1、音は n を12で割った余り（`N36` は `O4 C`）。0 は休符。 |
| `O` | オクターブ 1〜8（初め4、数を省略すると4）。 |
| `<`、`>` | 1オクターブ下げる、上げる。 |
| `L` | 長さを書かない音符の長さ 1〜64（4: 4分音符）。 |
| `T` | テンポ 32〜255（1分間の4分音符の数、初め120）。音符の長さは 12000 / (長さ × テンポ) を1/50秒の単位にしたもの（5未満は5）。 |
| `V` | 音量 0〜15（8）。`V15` が最大で、1段下げるごとに 3 dB 小さくなり、`V0` は無音。`V-STEPS` を設定した音色（機種のライブラリが設定する）では、その16段の値になる。`V` は `S` を解除する。 |
| `S` | エンベロープの形 0〜15（0）。PSG の8種類の形のどれかで、後ろの音符が、音色のエンベロープの代わりにこれを使う。この音符は、`V` の値によらず最大の音量で鳴る。 |
| `M` | `S` のエンベロープの周期 1〜65535（255）。1回の上りまたは下りは、MSX と同じく 256 × M / 1789773 秒。 |
| `@` | 音色 0〜63（0）。 |
| `P` | 声部の左と右の大きさ。`P左,右` で、それぞれ -100〜100（百分率。負は逆相）。`P100,0` は左だけ、`P70,30` は左寄り、`P100,100` は中央。音色の `INSTRUMENT-PAN`、声の `VOICE-PAN` と掛け合わせる。`P` だけなら `P100,100`。 |
| `Y` | ビブラート。`Y深さ,速さ` で、深さはセント、速さは整数の Hz（1以上）。音色の `VIBRATO` の深さと速さを置き換える（始まるまでの時間は音色のもの）。`Y0` と `Y` だけは、音色のビブラートも止める。`Y` を書くまでは、音色のビブラートで鳴る。 |
| `K` | 音程に足すセント -100〜100（0）。 |
| `Q` | 音符の長さのうち鳴らす割合。8分のいくつかを 1〜8 で指定する（8）。`長さ × Q / 8`（付点を含む。1/50秒未満は1/50秒）で音符の終わりと同じように止め、残りは無音になる。音色の `NOTE-LIMIT` がそれより短ければ、そちらで止まる。 |
| `&` | 音符の後に書く。次の音符を鳴らし直さずにつなぐ。同じ高さならタイ、違う高さならスラーになる。エンベロープ、波形、ビブラートは続く。 |
| `_` | 音符の後に書く。`&` と同じくつなぎ、次の音符の高さへなめらかに移る。移る時間は音色の `PORTAMENTO`。それが 0 なら、次の音符の長さ全体で移る。 |

数を省略すると、かっこ内の既定値になります（ROM と同じ）。ただし `N` には数が必要です。これ以外の文字や範囲外の数は `INVALID MML !`（THROW -274）になり、その `PLAY` は何も鳴らしません。BASIC の変数を使う `X` と `=変数名;` は扱いません。Forth のプログラムで文字列をつないで渡してください。

`@`、`P`、`Y`、`K`、`Q`、`&`、`_` は Sigma で足した命令で、MSX BASIC にはありません。`P`、`Y`、`K`、`Q` は次に始まる音符から効き、次の `PLAY` へも `@` のあとへも残り、`BEEP` で初めの値に戻ります。命令と数の間、`,` の前後には空白を書けます。`P`、`K`、`P` の `,` の直後の `-` は符号です。音符の直後の `-` は、これまでどおりフラットです。数が1つだけの `P`、深さだけで速さのない `Y`、余分な `,` は誤りです。

`&` か `_` で次へつないだ音符は、長さの全部を鳴らします。`Q` は、つないだ音符の最後の1つにだけ効きます。2つの音符の間に命令を書けます（`C&>C`、`C_V12E`）。つないだ先の音符は新しい音量と `K` で鳴りますが、`P`、`Y`、音色は最初の音符が始まったときのままです。間の休符と `@`、`PLAY` の最後の音符の後の `&` と `_` は誤りです。次の `PLAY` へはつなぎません。最初の音符がすでに終わっているとき（エンベロープが 0 になった、`NOTE-LIMIT` で止まった）は、つないだ先の音符は鳴りません。

```forth
S" P100,0 O4 L4 C&E_>C2" S" P0,100 Y20,6 O3 L2 Q6 C G" PLAY2   \ 左: スラーとなめらかな移動。右: ビブラート、音を切る
```

定義の外の `S"` の文字列は1つずつ別の場所に置かれるので、8声の `PLAYS` も1行で書けます。くり返し鳴らす曲は、文字列が辞書に入る定義の中に書くのがよい方法です。

### 演奏の語

標準の音は16声です。`PLAY` は声1〜8、`SFX` と `PLAY-TONE` は声9〜12、モジュールは声13〜16を使います。互いに声を取り合いません。

| ワード | スタック | 説明 |
| --- | --- | --- |
| `REQUIRE-AUDIO` | ( -- ) | 音の語を読み込む（最初の1回だけ）。`REQUIRE-GRAPHICS` と同じく解析器が扱う語で、定義の中では使えない。 |
| `PLAY` | ( c-addr u -- ) | MML を声部Aで鳴らす。音符のない声部BとCも、次の `PLAY` をAと同時に始める。 |
| `PLAY2`、`PLAY3` | ( c-addr1 u1 c-addr2 u2 -- )、( c-addr1 u1 c-addr2 u2 c-addr3 u3 -- ) | 声部AとB、またはA、B、Cを同時に鳴らし始める。 |
| `PLAY-RESET` | ( -- ) | `0 PLAYS` と同じくMMLの演奏とその声を停止し、声部のMMLの設定（オクターブ、長さ、テンポ、音量、音色、`S` と `M`、`P`、`Y`、`K`、`Q`）を起動時の値に戻す。音は鳴らさない。SFX・MOD・標本・音色は保持する。`BEEP` は音を鳴らして同じことを行い、SFX と MOD も止める。 |
| `PLAYS` | ( c-addr1 u1 ... c-addrn un n -- ) | 最初の n 声を同時に鳴らし始める。n は 1〜8。`0 PLAYS` はMMLの演奏とその声を停止し、SFX・MOD・標本・音色・声部のMMLの設定を保持する。音のスレッドが停止を受け付けてから戻る。 |
| `PLAY?` | ( n -- flag ) | 声部 n（1〜8。0 ならいずれか）に、まだ鳴らす音符があるか。MSX BASIC の `PLAY(n)`。音符のない声部も、`PLAY` の区切りを音のスレッドが受け取るまで（1/50秒以内）は真になる。 |
| `PLAY-TONE` | ( hz ms -- ) | hz（0〜1000000）の矩形波を ms ミリ秒、音楽と並べて鳴らす。`SFX` の声の1つを使う。 |
| `BEEP` | ( -- ) | 音楽、効果音、モジュールを止め、声部のMMLの設定を初めの状態にして、ビープ音（約1316 Hz の矩形波を `V7` で 40 ms）を鳴らす。音のスレッドが音楽を止めてから戻る。音色と、すべての声にかかる設定は残る。 |
| `AUDIO?` | ( -- flag ) | 音が出力装置に届くか。実行中に出力が失敗すると（Linuxで音を流すコマンドが終わるなど）偽になり、プログラムを起動し直すまで音は出ない。 |

### 音色

MML の `@n` は音色 n で鳴らします。`INSTRUMENT` は、この表の語で変える音色を選びます。変更は、その音色で次に始まる音符から効きます。音色は、設定し直すまで、設定された内容を持ち続けます。

```forth
1 INSTRUMENT  PULSE 16384 DUTY  10 200 40000 300 ADSR  12 6 150 VIBRATO
2 INSTRUMENT  SAW  1 800 20000 FILTER  65535 20000 INSTRUMENT-PAN
S" @1 V12 CDEF" S" @2 V12 O3 C2G2" PLAY2
```

| ワード | スタック | 説明 |
| --- | --- | --- |
| `INSTRUMENT` | ( n -- ) | 下の語で変える音色 n（0〜63）を選ぶ。 |
| `SQUARE`、`PULSE`、`TRIANGLE`、`SAW`、`NOISE` | ( -- ) | 音色の波形。矩形波（幅が周期の半分のパルス。初めはこれ）、`DUTY` の幅のパルス、三角波、のこぎり波、シフトレジスタのノイズ。 |
| `DUTY` | ( ratio -- ) | `PULSE` の幅。1周期に対する割合 0〜65535（初め32768）。 |
| `WAVETABLE` | ( addr n -- ) | addr からのセルにある n 個（1〜65536）の符号付き16ビットの値を、音色の1周期の波形にする。標本の領域を n 個分使う。 |
| `SAMPLE-INSTRUMENT` | ( n -- ) | 音色が標本 n（0〜63）を音符で鳴らすようにする。`O4 C` で標本そのままの速さになる。-1 で外し、矩形波に戻す。 |
| `NOISE-LFSR` | ( bits tap -- ) | ノイズのシフトレジスタ。長さは bits（2〜32）ビットで、ビット tap（1〜bits - 1）とビット0を帰還する。初めは `15 1`。ノイズは音符の1周期に16回進むので、高い音符ほど明るいノイズになる。 |
| `NOISE-RATE` | ( hz -- ) | 音符によらず、ノイズを1秒に hz 回（1/1000 Hz 単位）進める。0 で、初めと同じく音符の1周期に16回。 |
| `NOISE-MIX` | ( mode -- ) | ノイズを音色の音と混ぜる。0 混ぜない、1 足す、2 ゲート（両方が高いときだけ高い。PSG の混ぜ方）。 |
| `ADSR` | ( attack-ms decay-ms sustain release-ms -- ) | エンベロープの簡単な書き方。直線のアタック、sustain（0〜65535）までの指数のディケイ、音符が止まるまでの保持、指数のリリース。`ENVELOPE` の区切りとして設定する。 |
| `ENVELOPE` | ( addr n loop release -- ) | addr からの n 個（0〜16）の区切りでエンベロープを書く。区切りは3セルで、到達する値（0〜65535）、時間（ミリ秒）、曲線（0 直線、1 指数）。loop は最後の区切りのあとに戻る区切りの番号、release は音符が止まるまで留まる区切りの番号（どちらも -1 でなし）。n = 0 でエンベロープなし。 |
| `PITCH-SWEEP` | ( cents ms -- ) | 音符が鳴っている間、ms ミリ秒ごとに音程を cents 変える（負で下がる）。 |
| `PITCH-SWEEP-LIMIT` | ( low-hz high-hz -- ) | 音程が low-hz〜high-hz の外にある間、音符を消音する。`0 0` で制限なし。 |
| `PORTAMENTO` | ( ms -- ) | 前の音符から ms ミリ秒かけて次の音符へ移る。0 でなし。 |
| `VIBRATO` | ( cents hz delay-ms -- ) | 深さ cents、速さ hz のビブラート。音符の開始から delay-ms 後に始まる。`0 0 0` でなし。 |
| `RING`、`SYNC` | ( voice -- ) | 音色の波形に、源の声（1〜16）の発振を掛ける。または、その声の1周期ごとに波形を最初に戻す。0 でなし。 |
| `PITCH-MOD` | ( voice cents -- ) | 源の声（1〜16）の出力で、音程を最大 cents 変える。声 0 でなし。 |
| `VOLUME-MOD` | ( voice ratio -- ) | 源の声（1〜16）の出力で、音量を最大 ratio（0〜65535）変える。声 0 でなし。 |
| `MOD-ONLY` | ( flag -- ) | 真なら、この音色の声は出力に混ぜず、変調の源にだけ使う。 |
| `PHASE-RESET` | ( flag -- ) | 真なら、音符ごとに波形を先頭から始める。 |
| `NOTE-LIMIT` | ( ms -- ) | 音符を、開始から ms ミリ秒で止める。0 で制限なし。 |
| `FILTER` | ( mode hz resonance -- ) | 音色を、その音色のフィルターに通す。mode は 0 なし、1 ローパス、2 バンドパス、3 ハイパス、4 ローパス＋ハイパス（ノッチ）、5 ローパス＋バンドパス、6 バンドパス＋ハイパス、7 三つすべて。周波数は 0〜1000000 Hz、resonance は 0〜65535。 |
| `INSTRUMENT-PAN` | ( left right -- ) | 音色の左右それぞれの音量 -65535〜65535（負は逆相）。初めは `65535 65535`。 |
| `REVERB-SEND` | ( ratio -- ) | 音色の音をリバーブへ送る量 0〜65535（初め0）。 |

時間は 0〜3600000 ミリ秒です。範囲外の数は `NUMBER ERROR !` になります。

まだ鳴っている声で次の音符が始まるとき、エンベロープは 0 からではなく、その声の今の音量から始まります。休符なしで続く音符の始まりごとに、ノイズが出ないようにするためです。鳴っていなかった声は 0 から始まります。

### 機種の段階

標準の音を、機種が持つ段階に丸める語です。次の節のライブラリはこれらの語で書いてあり、プログラムから直接使うこともできます。初めの6語は `INSTRUMENT` で選んだ音色に、あとの3語はすべての声に設定します。時計（clock）は 1/1000 Hz 単位で、Hz の整数にならない時計も指定できます。

| ワード | スタック | 説明 |
| --- | --- | --- |
| `PITCH-PERIOD` | ( clock divider offset min max -- ) | 音程を clock / (divider × (周期 + offset)) に丸める。周期は min〜max の整数（min + offset は1以上）。標本の音色では、再生の速さを丸める。clock 0 で丸めない。 |
| `PITCH-STEP` | ( clock bits -- ) | 音程を clock × n / 2^bits（n は整数、bits は 1〜32）に丸める。SID の周波数レジスタの形。clock 0 で丸めない。 |
| `VOLUME-STEPS` | ( addr n -- ) | 音量とエンベロープを、addr からのセルにある昇順の n 段（0〜128）の値（0〜65535）のうち、デシベルで最も近い段に丸める。0 で丸めない。 |
| `V-STEPS` | ( addr n -- ) | MML の `V0`〜`V15` が、addr からのセルにある16個の値（0〜65535）を選ぶようにする。機種の音量レジスタと同じ動き。n は16。0 で1段 3 dB に戻す。`S` のエンベロープには使わない。 |
| `DUTY-STEPS` | ( n -- ) | パルスの幅を n 段に丸める（0 と1周期全体にはしない）。0 で丸めない。 |
| `INTERPOLATION` | ( mode -- ) | 波形表と標本の読み方。0 は階段（初め）、1 は値の間を直線でつなぐ。 |
| `VOICE-LIMIT` | ( n -- ) | `PLAY` の声 1〜n だけを鳴らす（1〜8、初め8）。 |
| `MIXER` | ( mode -- ) | 声の混ぜ方。0 は足し算（初め）、1 は声1〜5を NES の式で混ぜる（声1・2を矩形波、声3を三角波、声4をノイズ、声5を DMC として扱い、その声の左右・フィルター・リバーブは使わない）。 |
| `OUTPUT-BITS` | ( bits rate -- ) | 出力を bits ビット（1〜16、0 で丸めない）に丸め、rate Hz（0 で毎フレーム）ごとに更新する。 |

### すべての声にかかる設定

すぐに効き、`BEEP` と停止のあとも残ります。

| ワード | スタック | 説明 |
| --- | --- | --- |
| `REVERB` | ( delay-ms feedback volume -- ) | リバーブ。遅れ 0〜341 ms、帰還 -65535〜65535、出力の量 0〜65535（0 で切る）。音色が `REVERB-SEND` で送った音にかかる。 |
| `REVERB-FIR` | ( addr n -- ) | リバーブの帰還に、addr からのセルにある n 個（0〜8）の符号付きの係数（128 を1とする）をかける。0 で係数なし。 |
| `VOICE-PAN` | ( left right voice -- ) | 声 1〜16 の左右それぞれの音量 -65535〜65535（負は逆相）。その声が何を鳴らしても効く。初めは `65535 65535`。音色の `INSTRUMENT-PAN`、MML の `P` と掛け合わせる。 |
| `MASTER-FILTER` | ( mode hz stage -- ) | すべての声にかけるフィルター。stage は 1 か 2 で、1段目が先にかかるので、2つを続けてかけられる。mode は 0 なし、1 ローパス、3 ハイパス（2極、1オクターブで 12 dB）、11 ローパス、13 ハイパス（1極、1オクターブで 6 dB）。周波数は hz。 |
| `TONE-CONTROL` | ( bass treble -- ) | 低音（約 200 Hz 以下）と高音（約 4 kHz 以上）を -12〜12 dB の範囲で増減する。 |
| `MASTER-VOLUME` | ( ratio -- ) | すべての声の音量 0〜65535（初め65535）。 |
| `VOICE-HOLD` | ( instrument hz volume voice -- ) | 声 1〜16 で、音色（0〜63）を hz（1/1000 Hz 単位）と音量（0〜65535）で、次の指示まで鳴らし続ける。同じ音色をもう一度指定すると、エンベロープを続けたまま、音程と音量が変わり、音色の今の設定（波形、デューティー、フィルターなど。エンベロープを除く）を取り込む。鳴っている途中の音色を変えるのに使う。別の音色では最初から鳴らす。エンベロープが 0 で終わっても、声は 0 のまま保つ。音量 0 でその場で止める。`PLAY`、`SFX`、モジュール、停止は、それぞれの声を取り戻す。 |
| `VOICE-OSC` | ( voice -- n ) | 声 1〜16 の発振の値 -32768〜32767。 |
| `VOICE-ENV` | ( voice -- ratio ) | 声のエンベロープの値 0〜65535。 |
| `VOICE-POS` | ( voice -- n ) | 声が鳴らしている標本の再生位置。標本を鳴らしていなければ -1。 |
| `VOICE-ENDS` | ( voice -- n ) | 声の標本が終わった回数とループした回数の合計。増え続ける。 |
| `VOICE-ON?` | ( voice -- flag ) | 声が鳴っているか。 |

`VOICE-` の語が読む値は、音のスレッドが数ミリ秒ごとに書きます。音のスレッドは Forth を呼ばないので、標本の終わりやループは、プログラムが `VOICE-ENDS` を読み直して知ります。大きな音の16声を同時に鳴らすと、出力の上限を超えて音が切れることがあります。このための音量の自動調整はしません。

### 機種のライブラリ

`include/` のファイルは、標準の音に機種らしさを加えます。上の節の語で設定を行う Forth のソースで、語は `AUDIO` 語彙に入ります。起動時の `FPATH` は、カレントディレクトリ、プログラムと同じフォルダーにある `include` の順なので、どのディレクトリからでも `REQUIRE msx-sound.fs` でライブラリを読み込めます（`FPATH` は[ユーザーマニュアル](USER_MANUAL.ja.md)を参照）。

```forth
REQUIRE-AUDIO  ALSO AUDIO
REQUIRE chips.fs
NES-SOUND                                    \ すべての音色が NES の段階になる
1 INSTRUMENT NES-TRIANGLE  2 INSTRUMENT NES-NOISE
S" O5 L8 CEGE" S" O5 L8 EGBG" S" @1 O3 L4 CG" S" @2 O8 L8 BBBB" 4 PLAYS
STANDARD-SOUND                               \ 機種をやめる
3 INSTRUMENT SCC STYLE  4 INSTRUMENT C64 STYLE SAW
S" @3 O4 L8 CDEF" S" @4 O3 L4 CG" PLAY2      \ 1つの PLAY で2つの機種
```

| ファイル | ワード | スタック | 説明 |
| --- | --- | --- | --- |
| `chip-sound.fs` | `STANDARD-SOUND` | ( -- ) | 標準の音に戻す。64の音色すべてから機種の段階をなくし、`VOICE-LIMIT`、`MIXER`、`OUTPUT-BITS`、`MASTER-FILTER`、`MOD-FILTER`、すべての声の `VOICE-PAN` を起動時の値に戻す。音色の波形やエンベロープなどと、`MASTER-VOLUME`、リバーブ、`TONE-CONTROL` は変えない。 |
| | `STANDARD-STEPS` | ( -- ) | 選んだ音色から機種の段階をなくす。 |
| `msx-sound.fs` | `MSX-SOUND` | ( -- ) | MSX の AY-3-8910（1789773 Hz）。3声、周期 1〜4095、AY の16段の音量、17ビットのノイズ。 |
| | `MSX-STEPS`、`AY-STEPS` | ( -- )、( clock -- ) | 選んだ音色を PSG の段階にする。時計は MSX のもの、または clock。 |
| | `SOUND` | ( reg value -- ) | PSG のレジスタ reg（0〜13）に value（0〜255）を書く（MSX BASIC の `SOUND`）。声1〜3を音色61〜63で鳴らし、途中で `INSTRUMENT` でこれらの音色を選ぶ。R7 の初めの値は、MSX BASIC と同じ 184（音程あり、ノイズなし）。`PLAY`、`BEEP`、停止はこれらの声を取り戻し、次の `SOUND` でまた鳴る。 |
| `st-sound.fs` | `ST-SOUND`、`ST-STEPS` | ( -- ) | Atari ST の YM2149（2 MHz）。3声と、1.5 dB 刻みの32段の音量。 |
| | `STE-SOUND` | ( -- ) | STE。`ST-SOUND` を5声にする（2声は標本用）。低音・高音の調整は `TONE-CONTROL` で行う。 |
| | `STE-LEFT`、`STE-RIGHT`、`STE-STEPS` | ( -- ) | 選んだ音色を STE の標本のチャンネルにする。標本を1秒に 50066 / 周期 個の速さで鳴らし（周期は 1〜8。STE の 1、2、4、8 だけではない）、左または右に置く。`STE-STEPS` は速さだけを設定する。2チャンネルの WAV は1つに混ぜて読み込むので、左と右は2つの標本を2つの声で鳴らす。 |
| `nes-sound.fs` | `NES-SOUND` | ( -- ) | NES の APU（NTSC）。5声を NES の式で混ぜる（`MIXER` 1）。11ビットのタイマー、16段の音量、8分の1刻みのデューティ。出力のフィルター（90 Hz のハイパスと 14 kHz のローパス、どちらも1極）を `MASTER-FILTER` の2段に設定する。 |
| | `NES-STEPS`、`NES-PULSE` | ( -- ) | 選んだ音色を矩形波の段階にする。`NES-PULSE` は波形もパルスにする。 |
| | `NES-TRIANGLE` | ( -- ) | 選んだ音色を32段の三角波にする。`V` によらず最大の音量で鳴る。呼ぶたびに領域を32個分使う。 |
| | `NES-NOISE` | ( -- ) | 選んだ音色をノイズにする。ノイズの周期は音符に従う（NES の16種類だけでなく、4〜4068 の整数）。低い音符は低い響き、高い音符はシャーという音になる。 |
| | `NES-SHORT-NOISE` | ( -- ) | `NES-NOISE` と同じで、ノイズを短い周期のモードにする。93（または31）回で繰り返し、金属的な音になる。 |
| | `NES-DMC` | ( -- ) | 選んだ音色を DMC にする。標本を鳴らす音色（`SAMPLE-INSTRUMENT`）に使う。標本を1秒に 1789773 / 周期 個の速さで鳴らし（周期は NES の16種類だけでなく、54〜428 の整数）、`V` によらず最大の音量で鳴る。声5で鳴らす。標本は DMC の1ビットごとに1つの値を持つ。1ビット差分は、先にプログラムで値に直しておく。 |
| `c64-sound.fs` | `C64-SOUND`、`C64-STEPS` | ( -- ) | C64 の SID（PAL）。3声、周波数レジスタ（985248 Hz × n / 2^24）、12ビットのパルス幅、23ビットのノイズ。 |
| | `C64-FILTER` | ( mode cutoff resonance -- ) | 選んだ音色に、SID のフィルターをレジスタの値で設定する。mode は SID のビットの和（1 ローパス、2 バンドパス、4 ハイパス。0 でなし）、cutoff は 0〜2047（30 Hz から、1段 5.8 Hz）、resonance は 0〜15。フィルターは声ごとに別で、6581 の歪みはない。鳴っている途中で動かすには、設定し直してから `VOICE-HOLD` でその音色を指定する。 |
| `scc-sound.fs` | `SCC-SOUND`、`SCC-STEPS` | ( -- ) | コナミの SCC。5声、3579545 / (32 × (周期 + 1)) Hz、16段の音量。 |
| | `SCC-WAVE` | ( c-addr n -- ) | c-addr からの符号付きの32バイトを、音色 n の波形にし、SCC の段階を設定する。実行後は音色 n が選ばれている。呼ぶたびに領域を32個分使う。 |
| `amiga-sound.fs` | `AMIGA-SOUND`、`AMIGA-STEPS` | ( -- ) | Amiga の Paula（PAL）。4声、標本を1秒に 3546895 / 周期 個の速さで鳴らす（周期は123以上）。65段の音量。A500 のローパス（1極、約 4.9 kHz）を `MASTER-FILTER` の1段目に設定する。声1・4を左、声2・3を右に置く（`VOICE-PAN`）。`VOICE-LIMIT` を大きくして鳴らすそのあとの声は、中央のまま。 |
| | `AMIGA-FILTER` | ( flag -- ) | LED フィルター（約 3.3 kHz のローパス。4.9 kHz のローパスのあとに、`MASTER-FILTER` の2段目としてかかる）を入れるか切るか。モジュールの効果 `E0x` も、モジュールの声に同じフィルターを使う。 |
| `chips.fs` | `STYLE` | ( chip -- ) | 選んだ音色を、`MSX`（1）、`ST`（2）、`NES`（4）、`C64`（8）、`SCC`（16）、`AMIGA`（32）の段階にする。0 で標準の音の段階にする。1つの `PLAY` の声部を、別々の機種の音にできる。これら以外は `NUMBER ERROR !`。このファイルは、上の6つのライブラリを読み込む。 |

`MSX-SOUND` などの語は、64の音色すべてに機種の段階を設定し（実行後は音色0が選ばれている）、`VOICE-LIMIT` で `PLAY` の声をその機種の声の数に限り、`MIXER`、`OUTPUT-BITS`、`MASTER-FILTER`、`MOD-FILTER`、声の `VOICE-PAN` をその機種の値にします。音楽は止めず、声部のMMLの設定も変えません。音楽は `0 PLAYS` で止め、音色と音量は MML で指定してください。機種より多い声を鳴らすには、機種の語のあとで `VOICE-LIMIT` を大きくします。`NES-TRIANGLE`、`NES-NOISE`、`NES-SHORT-NOISE`、`NES-DMC`、`STE-LEFT`、`STE-RIGHT`、`SCC-WAVE` は自分の段階を設定するので、音色の波形とエンベロープは、機種の語のあとで設定してください。

ライブラリは、資料に書かれた動きに従って、音の高さと音量を機種と同じように丸めます。次の点は再現しません。NES のデューティが4種類だけであること（8分の1刻みのどれも鳴る）、NES のノイズと DMC の周期が16種類だけであること、DMC の1ビット差分（プログラムで値に直す）。PSG の3声が1つのエンベロープと1つのノイズを共有すること（声ごとに別に進む）、1 ms より短いエンベロープの周期。C64 のフィルターが送った声をまとめた1つであることとその歪み（声ごとに別のフィルターになる）、合成波形（`WAVETABLE` で鳴らす）、8ビットのノイズの出力。機種をレジスタの単位で再現するモデルは別のライブラリで、[PCMストリーム](#pcmストリーム)で説明します。

### 録音した音

標本 0〜63 は、辞書のメモリーとは別の 64 MiB の領域に置く、録音した音です。この領域は増えるだけで、標本を読み直すと新しい場所を使います。`FREE-SAMPLES` で空にします。波形表も同じ領域に置きます。

| ワード | スタック | 説明 |
| --- | --- | --- |
| `LOAD-SAMPLE` | ( c-addr u n -- ) | 8ビットか16ビットの PCM の WAV ファイル（モノラルかステレオ。ステレオはモノラルにまとめる）を、標本 n に読み込む。読めないファイルはそのエラー、そのような WAV でないファイルは `SAMPLE ERROR !`（THROW -276）、領域が足りなければ `OUT OF MEMORY !`。エラーのときは何も変わらない。データが、ファイルに書かれた大きさより前で終わっているときは、ある分だけを標本にする。 |
| `SAMPLE` | ( c-addr u rate n -- ) | c-addr からの符号付き8ビットの u バイトを、rate Hz（1000〜192000）で録音した標本 n にする。 |
| `LOOP-SAMPLE` | ( start end n -- ) | 標本 n を鳴らすとき、フレーム start から end までをくり返す。`0 0` でくり返さない。 |
| `SFX` | ( n -- ) | 標本 n をその速さで1回、すぐに、曲と並べて、声9〜12で鳴らす。同時に4つまで。5つ目は一番古いものと入れ替わる。 |
| `FREE-SAMPLES` | ( -- ) | 音楽、効果音、モジュールを止め、すべての標本、波形表、モジュールを消す。 |

標本を MML の音符で鳴らすには、[音色](#音色)の `SAMPLE-INSTRUMENT` を使います。

### モジュール

| ワード | スタック | 説明 |
| --- | --- | --- |
| `LOAD-MOD` | ( c-addr u -- ) | ProTracker の4チャンネルのモジュール（`M.K.`、`M!K!`、`FLT4`、`4CHN`）を領域に読み込む。ほかのファイルは `MOD ERROR !`（THROW -277）、領域が足りなければ `OUT OF MEMORY !`。 |
| `PLAY-MOD` | ( flag -- ) | モジュールを最初から、`PLAY` や `SFX` と並べて、声13〜16で鳴らす。flag が真なら、終わったあと最初からくり返す。flag が偽なら、演奏済みの行に来たところで終わる（最後の行の後、または `Bxx`・`Dxx` で戻ったとき）。曲の終わりの `Dxx` がまだ演奏していない行へ移る場合は、その行を先に演奏する。 |
| `STOP-MOD` | ( -- ) | モジュールを止める。 |
| `MOD?` | ( -- flag ) | モジュールが鳴っているか。 |
| `MOD-FILTER` | ( mode hz -- ) | モジュールの効果 `E0x` が、モジュールの声に入り切りするフィルター。mode は `FILTER` と同じで、0（なし、初め）〜7。`AMIGA-SOUND` は、ここに Amiga の LED フィルターを設定する。 |

モジュールは、Paula の周期（PAL の時計）で鳴り、チャンネルは形式の決まりどおり左・右・右・左に振り分けます。鳴らす効果は、アルペジオ、上下のポルタメント、トーンポルタメント、ビブラート、トレモロ、音量の変化、サンプルのオフセット、位置の移動、パターンの区切り、音量の設定、速さとテンポ、細かいポルタメントと細かい音量の変化、パターンのループ、リトリガー、ノートカット、ノートディレイ、パターンディレイです。ビブラートとトレモロは常に正弦波です（`E4x`、`E7x`）。`E3x`、`E5x`、`E8x`、`EFx` は何もしません。音符がなくサンプル番号だけの行は、新しい音を始めません。今の音が終わるかループが一周した時点で、新しいサンプルのループに切り替わり（すでに音が止まっていれば、すぐに）、新しいサンプルにループがなければ無音になります。識別子が `FLT4` のモジュールでは、番号だけの行は鳴っている音を変えません。

### 音の出力装置

| システム | 出力先 |
| --- | --- |
| Windows | waveOut、48 kHz 16ビット ステレオ。音符は、音のスレッドが受け取ってから約80 ms で鳴り始める。 |
| Linux（配布版、静的リンク） | `pacat`、`pw-play`、`aplay` のうち最初に起動できたコマンドに、パイプで送る（約40 ms）。 |
| Linux（ライブラリを読み込める版） | PulseAudio、次に ALSA、次に上のコマンド。 |
| macOS | AudioToolbox の AudioQueue で、既定の出力装置に送る。48 kHz 16ビット ステレオ（約80 ms）。フレームワークは実行時に読み込む。 |

`BEEP`、`FREE-SAMPLES`、`PLAY` が待っている間の Ctrl+C は、音楽、効果音、モジュールを止めます。`0 PLAYS` は音楽だけ、`STOP-MOD` はモジュールだけを止めます。音量 0 の `VOICE-HOLD` は、1つの声を止めます（効果音は声9〜12）。音の状態（音色、標本、待ち行列）は辞書に含まれません。`SAVE` と `SAVESYS` は音の語とそれを使う語を保存しますが、音色の設定や標本の読み込みは、プログラムが起動してから行ってください。音の語を読み込んだ辞書は `SIGIMG47` で保存します。`SAVESYS` の前に読み込んだ `include/` のライブラリは保存したプログラムに入るので、そのプログラムには `include` フォルダーが要りません。

`SND-` の語は、ライブラリを書くための基本の語です: `SND-PLAY`、`SND-PLAYS`、`SND-PLAY-TONE`、`SND-BEEP`、`SND-PLAYING`、`SND-DEVICE`、`SND-INSTRUMENT`、`SND-WAVE`、`SND-DUTY`、`SND-ADSR`、`SND-RING`、`SND-SYNC`、`SND-FILTER`、`SND-WAVETABLE`、`SND-TONE`（そのほかの音色の語。番号で選ぶ）、`SND-GLOBAL`（すべての声にかかる設定の語）、`SND-VOICE`（値を読む `VOICE-` の語）、`SND-HOLD`、`SND-LOAD-SAMPLE`、`SND-SAMPLE`、`SND-LOOP-SAMPLE`、`SND-SAMPLE-INSTRUMENT`、`SND-SFX`、`SND-FREE-SAMPLES`、`SND-LOAD-MOD`、`SND-PLAY-MOD`、`SND-STOP-MOD`、`SND-MOD-PLAYING`、`SND-MOD-FILTER`。それぞれの説明は `HELP` で見られます。`SND-LOAD-SAMPLE` と `SND-LOAD-MOD` は、エラーを THROW せずに ior を返します。`SND-SOUND`、`SND-CHIP`、`SND-CHIPS`、`SND-STYLE`、`SND-AMIGA-FILTER` は、ほかの語の番号を変えないためだけに残してあり、実行すると `HOST FUNCTION UNAVAILABLE !`（THROW -21）になります。

エラー: `-Daudio=false` の版の `REQUIRE-AUDIO` は `AUDIO UNAVAILABLE !`（THROW -275）、範囲外の数は `NUMBER ERROR !`、音のスレッドを持たないホストでは `HOST FUNCTION UNAVAILABLE !` です。`REQUIRE-GRAPHICS` と同じく、ライブラリの読み込みに失敗したときは加えたものを取り除き、`FORGET` や `MARKER` で消したあとは `REQUIRE-AUDIO` でもう一度読み込めます。

`examples/music.fs` は、短い曲を、標準の音、各機種の段階、いくつかの機種を混ぜた1つの `PLAY` で鳴らし、`SAMPLE` で作った効果音を鳴らします。`examples/fur-elise.fs` は、ベートーヴェンの「エリーゼのために」の主部、最初の中間部、主部の再現（1〜58小節）を、プログラムが自分で作る標本のピアノで、Paula の段階で鳴らします。`examples/fur-elise-simple.fs` は、主部だけを2つの声部の `PLAY2` で鳴らす短いプログラムです。`examples/pastoral.fs` は、ベートーヴェンの交響曲第6番「田園」第1楽章の提示部（1〜138小節）を、弦と管の波形を作って8声で鳴らします。

## Physical keys

`REQUIRE-GRAPHICS GRAPHICS`で読み込みます。`SCAN-INPUT?`はnativeウィンドウの物理入力が利用可能かを調べ、`scan SCAN-SUPPORTED?`はそのキーの押下・解放に対応するかを調べます。ウィンドウを自動では開きません。端末・SIXEL・Tkだけでは未対応です。`scan SCAN-HELD?`は状態を読み、`KEY-EVENT`は`scan kind true`または空なら`false`だけを返します。INKEY/EKEY/KEYと独立したキューです。

番号はUSB HID Keyboard/Keypad page 0x07の0〜255。例は`SC-A`、`SC-LSHIFT`、`SC-RSHIFT`。範囲外は-24です。`SC-PRESS`（1）と`SC-RELEASE`（2）は実際の変化だけで、autorepeatは増えません。MacのCapsLock、WindowsのPause、Linuxの左右Windowsキー（GNOMEが解放を横取りする）等、両方の変化を得られないキーはSCAN-SUPPORTED?が偽です。キーボード配列の文字やIME確定文字の番号とは別です。 Windowsではusage53（USの`／~、JISの半角／全角位置）と136（カタカナ／ひらがな）も、IME処理後の通知で押下状態が残るため物理入力の対象外です。対応可否と保持は偽、物理イベントは生成しません。通常の文字入力・IME切替は維持します。

キューは256件。満杯になると先の256件を残して新しい履歴を捨てますが、状態更新は続きます。残りを読んだ後は`0 SC-RESYNC true`（種類3）を返し続けます。`addr KEY-RESYNC`は32バイトへ状態を写し、未読履歴を破棄して要求を消します。キーnはn/8バイト目のbit(n%8)。通信snapshot待ちの間は要求を消さず、最新状態が到着した後にもう一度読み直します。失われた短押しの回数や時刻は復元できません。不正な32バイト領域はホストを変更せず-9です。

```forth
REQUIRE-GRAPHICS GRAPHICS
SC-A SCAN-SUPPORTED? .
SC-LSHIFT SCAN-HELD? .
CREATE HELD-BITS 32 ALLOT
HELD-BITS KEY-RESYNC
: PRINT-EDGE KEY-EVENT IF . . ELSE ." none" THEN ;
PRINT-EDGE
```

フォーカス喪失・閉鎖は全解放し、閉鎖後も残った履歴を取り出せます。保存イメージに状態や履歴は入らず、復元成功時に境界を置きます。ただしOSやMacのpipeに未読で残り、復元後に届く通知は取り込みます。OS上の発生時刻による排除は保証しません。詳細と確認範囲は[設計](PHYSICAL_KEY_DESIGN.md)と[検証記録](PHYSICAL_KEY_IMPLEMENTATION.md)。

## PCMストリーム

`REQUIRE-AUDIO ALSO AUDIO`で、符号付き16bitリトルエンディアン、mono/stereoのチャンネル交互配置のPCMを使えます。MML・SFX・モジュールと混合します。入力は8000..192000Hz、容量は256..65536入力フレームの2の冪で、40ms..1秒に相当する範囲です。音声hostにつき1ストリームです。装置がなければ無音で消費し、`AUDIO?`で区別できます。

| 語 | スタック効果 | 意味 |
| --- | --- | --- |
| PCM-OPEN | hz channels capacity -- pcm ior | 開く。同一プロセス内で正のIDを割り当てる |
| PCM-WRITE | addr frames pcm -- written ior | 完全なフレーム単位でコピー。待機せず、満杯なら0,0 |
| PCM-QUEUED | pcm -- frames ior | engineが未消費の入力フレーム数。出力保持中の1フレームを含む |
| PCM-WAIT | frames ms pcm -- flag ior | 入力の空きを待つ。0msは照会、負数は無期限 |
| PCM-STOP | mode ms pcm -- flag ior | 0は破棄、1はengineで消費してから切り離す |
| PCM-CLOSE | pcm -- ior | 破棄と切離しを最大1000ms待つ。成功時だけIDを無効にする |
| PCM-UNDERRUNS | pcm -- u ior | 最初の出力後に空になった回数。飽和し、意図したdrain末尾は除外 |

```forth
REQUIRE-AUDIO ALSO AUDIO
CREATE PCM-ZERO 16384 ALLOT
PCM-ZERO 16384 0 FILL
48000 2 4096 PCM-OPEN THROW CONSTANT PCM-ID
PCM-ZERO 4096 PCM-ID PCM-WRITE THROW .
1 1000 PCM-ID PCM-STOP THROW .
PCM-ID PCM-CLOSE THROW
```

この例は無音を渡します。1フレームは各チャンネルのサンプル1個ずつで、stereo s16LEなら4byteです。WRITEは受理した入力をコピーするため、呼出し後に元の領域を再利用できます。QUEUEDとdrainはengineの消費を表し、装置の再生位置ではありません。周波数変換はsample holdで、アンチエイリアス処理はありません。

WAIT/STOPの期限切れはfalse,0、中断はTHROW -28です。切離し前にdrainを取り消した場合は受理済み入力を保ち、書込みを続けられます。切離し要求後はSTOPの再試行で応答を確認できます。CLOSEは期限切れで-528、中断で-516を返し、closingのIDを保持するため再試行できます。停止要求中・closingへのWRITE/WAITは-534、不正IDは-521です。不正数値はTHROW -24、不正メモリはTHROW -9で、副作用の前に検査します。hostやscope復元の失敗はTHROW -265です。WAITには容量と同じフレーム数も指定できます。

内部語`SND-PCM-OPEN`・`SND-PCM-WRITE`・`SND-PCM-QUEUED`・`SND-PCM-WAIT`・`SND-PCM-STOP`・`SND-PCM-CLOSE`・`SND-PCM-UNDERRUNS`も同じ効果です。audio=falseですべて除外し、graphics/debug/extensionには依存しません。IDは開いたStateが所有し、同一プロセス内では再利用しません。イメージに実行中ストリームは保存しません。所有中の完全復元はbusy（-528）、LOAD-DICTIONARYの追記は対象のPCMを保持します。保存アプリはPCM未所有で起動します。追加した7個のBuiltinタグで画像ABIが変わるため、古いイメージはソースから保存し直してください。[実装と検証の記録](PCM_PUBLIC_IMPLEMENTATION.md)も参照してください。

独自の[Forth合成例](../examples/pcm-synth.fs)は、音声を起動せず4声の汎用音源を定義します。[PCM送出例](../examples/pcm-synth-play.fs)は部分書込みとclose再試行に対応します。リポジトリ直下で`sigma examples/pcm-synth-play.fs -e "PS-DEMO-SETUP 96 FALSE PS-STREAM BYE"`を実行すると、約1秒分を合成して無音を渡します。TRUEを指定した場合だけ生成波形を出力します。特定チップのエミュレーションではありません。[仕様・測定・残件](PCM_SYNTH_PROTOTYPE.md)を参照してください。

[NES APUのForth例](NES_APU_FORTH.md)は、技術資料に基づくNTSCのpulse 2声・triangle・noiseと、envelope/length/sweep/linear counterを扱います。PCM生成中も予定された書込みのCPU時刻順を保ちます。Builtinは追加しません。CPU/PPUのバス競合・アナログフィルターは試作の対象外で、DMCは下記の拡張で扱います。`sigma examples/nes-apu-play.fs -e "NA-DEMO-SETUP 16 FALSE NA-STREAM BYE"`は無音を渡し、TRUEを明示した場合だけ生成波形を渡します。読み込むだけでは再生しません。

[DMC拡張](NES_DMC_FORTH.md)ではForth例に5声目、専用サンプルメモリ、reader/buffer/IRQ/loopと直接DAC書込みを追加しました。DMAの待ちは0とするモデルで、CPU/PPUのバス競合は対象外です。5声と8kHz直接DACの負荷を別に測定し、読み込むだけでは再生しません。

[C64 SIDのForthモデル](SID_FORTH.md)は、3声の時刻指定レジスタ、TEST/SYNC/RING、ADSRと独自の整数フィルター近似を扱います。合成波形、実際の6581/8580のアナログ特性、ROM互換は対象外です。`sigma examples/sid-play.fs -e "SI-DEMO-SETUP 16 FALSE SI-STREAM BYE"`は合成後に無音を送り、TRUEを明示すると生成音を送ります。読み込むだけでは再生しません。

[PaulaのForthレジスタモデル](PAULA_FORTH.md)は、4声ステレオの標本出力、DMA/手動DAT、IRQ mask、attachと時刻指定書込みを扱います。bus待ちを省いたモデルで、Agnusの競合・アナログfilter・ROM互換は含みません。`sigma examples/paula-play.fs -e "PA-DEMO-MEMORY PA-DEMO-SETUP 16 FALSE PA-STREAM BYE"`は合成後にステレオ無音を送り、TRUEだけ生成音を送ります。読込みだけでは再生しません。Mac受け入れ1147は1137の子に残しています。

[YM2149/STのForthモデル](YM2149_FORTH.md)は、既存ST-SOUND/SOUNDの非同期経路に、時刻指定・読取り・仮想I/OポートとST選択/dataのモデルを補います。点標本のPCMはnativeの内部step平均とは別です。nativeの固定音量0はPSG sourceを無音にし、envelope level1とcoupling filterの減衰は維持します。読込みだけでは再生しません。`sigma examples/ym2149-play.fs -e "YM-DEMO-SETUP 16 FALSE YM-STREAM BYE"`は無音を送り、TRUEだけ生成音を送ります。実周辺機器やST/TOS完全互換は対象外で、Mac受け入れ1154は1138の子に残しています。

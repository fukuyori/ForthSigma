# FORTH/Σ for Zig

英語版（正）: [README.md](https://github.com/fukuyori/ForthSigma/blob/main/README.md)。この日本語版は英語版の訳です。内容が異なる場合は英語版に従ってください。

FORTH/Σ（フォース・シグマ）の言語コアを、Zigで動くネイティブな移植版として実装するプロジェクトです。1982年の月刊アスキー誌面に掲載されたFORTH/Σの説明とZ80ソースリストを仕様調査の資料として使っています。Z80の命令や機械語を実行・エミュレートするものではありません。

## 現在の実装

- 64ビットセルと、既定で64 MiBの論理メモリ（辞書の32 MiB（うち120 KiBはシステム・入力・ブロック用で、残りがデータ領域）、同じ大きさの `ALLOCATE` のヒープ、64 KiBのローカル変数の領域）を使います。スタックは各4096要素です。大きさは、gforthと同じオプション（`-m`、`-d`、`-r`、`-f`、`-l`）で起動時に指定できます。真の値は-1で、除算は床関数除算です。
- 浮動小数点数（倍精度）を専用スタックで扱えます。`1E`、`1.5e0` のように `E` を含む数が浮動小数点数になり、`F+`、`F.`、`FSQRT`、`FCONSTANT` などのF系ワードを使えます。
- 対話入力、辞書検索、数値入力、ワード定義とコンパイルに対応しています。
- スタック操作、算術・比較・論理演算、メモリ操作、変数・定数・値・配列を使えます。
- IF ... ELSE ... THEN、BEGIN ... END/UNTIL、BEGIN ... AGAIN、BEGIN ... WHILE ... REPEAT、CASE ... ENDCASE、DO ... LOOP、DO ... +LOOP、LEAVE、EXITを使えます。
- IMMEDIATE、POSTPONE、RECURSE、CREATE ... DOES> でコンパイラを拡張できます。
- HEX、DEC、OCTによる基数変更、数値・文字・文字列の出力に対応しています。
- `S"` などの文字列、`123.` 形式の倍長整数（128ビット）、`<<# # #S #> #>>` による数値の書式、`ACCEPT`、`EVALUATE`、`KEY` を使えます。
- WORDS、FORGET、BYEを対話用ワードとして提供します。
- この移植版の拡張として、グラフィックス（`REQUIRE-GRAPHICS`）を使えます。メモリ上の画像に線、図形、塗りつぶし、グラフ、文字（組み込みのASCIIフォント、BDFフォント、Windowsではシステムのフォント）を描き、端末（半角ブロックかSixel）、Sigma自身のウィンドウ（Windows、macOS、X11またはXWaylandのLinux）、Tkのウィンドウに表示します。ほかにも画像を作って描いたり写し合ったりでき、PNG、BMP、PPM のファイルから読み込めます。キーとマウス（`INKEY`、`MOUSE`、`MOUSE-EVENT`）、毎フレーム描く GUI（`REQUIRE-GUI`）、ゲーム用のスプライト、タイルマップ、パレット（`REQUIRE-GAME`）と、Sigmaが起動する `wish` でのTcl/Tkのスクリプト（`TCL`、`TCL-EVAL`、`TCL-EVENT`）も使えます。Tcl/TkはSigmaにリンクしないので、TCL の語を使うにはTcl/Tkを入れておく必要があります。
- この移植版の拡張として、サウンド（`REQUIRE-AUDIO`）を使えます。MSX BASIC の `PLAY`、`BEEP` と MML を、音のスレッドがプログラムと並行して鳴らします。音は、16声の標準の音と音色（エンベロープ、フィルター、変調、リバーブ）で作ります。`include/` のライブラリで、MSX（`SOUND` を含む）、Atari ST、NES、C64、コナミの SCC、Amiga の機種らしさを、1つずつ、またはいくつか同時に加えられます。WAV ファイルの録音した音と効果音、ProTracker のモジュール（MOD ファイル）も鳴らせます。[サウンド](https://github.com/fukuyori/ForthSigma/blob/main/docs/GRAPHICS_AND_SOUND.ja.md#サウンド)と `examples/music.fs` を参照してください。
- この移植版の拡張として、EXTENSIONの語彙（`REQUIRE-EXTENSION`）を使えます。ホストのOS、端末のモードと大きさ、キー・マウス・貼り付けのイベントの待ち、プログラムと並行して動き取り消せる計算タスク、ファイルとパスの道具、書記素クラスター、実行の制限を扱います。[拡張機能のマニュアル](https://github.com/fukuyori/ForthSigma/blob/main/docs/EXTENSION.ja.md)を参照してください。
- 辞書、コンパイル済み定義、メモリ、入出力をホスト環境から分離し、他のOS・CPUへ移植しやすい構成にしています。

対応ワードと移植上の判断は[実装ノート](https://github.com/fukuyori/ForthSigma/blob/main/docs/IMPLEMENTATION.md)、資料から整理した言語仕様は[FORTH/Σ仕様書](https://github.com/fukuyori/ForthSigma/blob/main/docs/SPEC.ja.md)を参照してください。実装は開発中であり、誌面の全ワードや機種固有機能には対応していません。

使い方と現在登録されている組み込みワードの一覧は[ユーザーマニュアル](https://github.com/fukuyori/ForthSigma/blob/main/docs/USER_MANUAL.ja.md)を、グラフィックスとサウンドは[グラフィックスとサウンドのマニュアル](https://github.com/fukuyori/ForthSigma/blob/main/docs/GRAPHICS_AND_SOUND.ja.md)を、EXTENSIONの語彙は[拡張機能のマニュアル](https://github.com/fukuyori/ForthSigma/blob/main/docs/EXTENSION.ja.md)を、プログラムの悪いところの調べ方は[デバッグの手引き](https://github.com/fukuyori/ForthSigma/blob/main/docs/DEBUGGING.ja.md)を参照してください。

現在の全語・構文の日本語説明・使用例・注意点は[全ワードリファレンス](docs/WORD_REFERENCE.ja.md)と[読み方・使用例](docs/WORD_REFERENCE_GUIDE.ja.md)を参照してください。

利用者がデータを持つワードを作る定義用語（BUILDS/DOES）にも対応しています。

`SAVE filename`／`LOAD-DICTIONARY filename` で利用者定義語を保存・追加読み込みできます。単独実行ファイルは別の拡張語 `SAVESYS filename.exe` で作成します。
標準の`LOAD`は`blocks.fb`の番号付きブロックを実行します。保存済み辞書の読込は`LOAD-DICTIONARY filename`です。


ワードごとの対応状況は[互換性一覧](https://github.com/fukuyori/ForthSigma/blob/main/docs/COMPATIBILITY.ja.md)、資料で確定した仕様と移植上の判断の区別は[決定事項・保留事項](https://github.com/fukuyori/ForthSigma/blob/main/docs/DECISIONS.md)を参照してください。

現時点では、LIST、ソースファイルやエディタの操作、CP/Mのファイル機能、PC-8001のモニタ機能、Z80機械語を使うワードには対応していません。

### グラフィックモード

BASICの `SCREEN 1` のような番号付きの画面モードはありません。プログラムは `GFX-INIT` ( w h -- ) で任意の大きさ（各辺1〜16384画素）の画像を1枚作り、`SHOW` の表示先と色数を別々に選びます。画像そのものは常にフルカラーで、ファイルにもフルカラーで保存します。

| `SHOW` の表示先 | 語 | 使える環境 |
| --- | --- | --- |
| 端末、半角ブロック（1文字で2画素） | `DISPLAY-TERMINAL TERMINAL-BLOCKS` | すべてのOS |
| 端末、Sixel | `DISPLAY-TERMINAL TERMINAL-SIXEL` | Sixelに対応した端末 |
| Sigma自身のウィンドウ | `DISPLAY-WINDOW` | Windows、macOS、X11またはXWaylandのLinux |
| Tkのウィンドウ | `DISPLAY-TK` | Tcl/Tkが入っている環境 |

選ぶまでは、`SHOW` はホストにSigma自身のウィンドウがあればそこに表示します。ないときは、Tcl/Tkが入っていればデスクトップではTkのウィンドウに、ほかでは端末に半角ブロックで表示します。`DISPLAY-AUTO` で、次の `SHOW` がこの順に選び直します。Linuxでは `-Dx11=false` でX11のウィンドウを除いてビルドできます。`n DISPLAY-COLORS` で、フルカラー（0、既定）、白黒（2）、ANSIの16色（16）、xtermの256色（256）を選び、`TRUE DITHER` で減らした色をBayerの模様で混ぜます。`w h WINDOW-SIZE` で、ウィンドウとTkのウィンドウに画像を大きく表示します。たとえば `160 120 GFX-INIT 640 480 WINDOW-SIZE` で、1画素を4×4で表示します。

Tcl/TkはSigmaに含まれないので、Tkのウィンドウを使うには入れておきます。DebianとUbuntuでは `tk` パッケージ、FedoraとRHELでは `sudo dnf install tk`、Archでは `sudo pacman -S tk` で、どれも `PATH` に `wish` が入ります。

    sudo apt install tk

macOSでは `brew install tcl-tk` でTcl/Tkを入れます。macOSに付いているTcl/Tk 8.5（`/usr/bin/wish`）は、最近のmacOSでは起動したとたんに止められて動かないので、Sigmaはそれを飛ばし、`PATH` のほかの `wish`、なければHomebrewのもの（`/opt/homebrew/bin/wish` か `/usr/local/bin/wish`）かMacPortsのもの（`/opt/local/bin/wish`）を使います。別のものは環境変数 `SIGMA_WISH`（または `TCL-PROGRAM`）で指定します。Windowsでは、Git for Windows があれば Sigma がその `wish` を使うので、何も入れる必要はありません。Tcl/Tkがあれば、LinuxやmacOSのデスクトップでは `SHOW` を使うプログラムがウィンドウを開きます。たとえば `sigma examples/hopper.fs` です。

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
160 120 GFX-INIT  255 255 0 COLOR  80 60 40 CIRCLE
DISPLAY-TERMINAL  16 DISPLAY-COLORS  TRUE DITHER  SHOW
```

詳しくは[グラフィックモードのマニュアル](https://github.com/fukuyori/ForthSigma/blob/main/docs/GRAPHICS_MODES.ja.md)を参照してください。

## ビルドと実行

Zig 0.17.0をインストールした環境で、リポジトリのルートから実行します。

    zig build
    ./zig-out/bin/sigma.exe

LinuxとmacOSでも同じ `zig build` でビルドし、実行ファイルは `zig-out/bin/sigma` です。

    zig build
    ./zig-out/bin/sigma

Linuxで、`zig build` がディストリビューションのCライブラリのヘッダーで失敗する場合（`'gnu/stubs-32.h' not found`）は、musl向けを指定します。Zigに付属するヘッダーを使うビルドになります：`zig build -Dtarget=x86_64-linux-musl`。

コアの回帰テストはzig build testで実行できます。

別のZigターゲットを指定する場合はzig build -Dtarget=<triple>を使います。

現在の製品バージョンは [`VERSION`](https://github.com/fukuyori/ForthSigma/blob/main/VERSION) に記載しています。Windows向けリリースビルドとInno Setupインストーラーは次のPowerShellスクリプトで作成できます。インストーラー（`dist\installer\sigma-版番号-windows-x86_64-setup.exe`）は、実行ファイルと同じく `VERSION` の値を使います。

    .\scripts\build-release.ps1
    .\scripts\build-installer.ps1

`build-release.ps1` は、全部入り版（`dist\release`）とFORTH 2012プロファイル（`dist\release-forth2012`）をビルドします。後者は浮動小数点とファイルアクセスを含む標準ワードセットを残し、グラフィックス、サウンド、Sigmaの拡張語彙を除きます。`-Variant Full` または `-Variant Forth2012` で片方だけにでき、出力先は `-OutputDirectory` と `-Forth2012OutputDirectory` で変えられます。`-Target` を指定しない場合もCPUはbaseline（`-Dcpu=baseline`）です。インストーラーは全部入り版を使います。

LinuxとmacOSでは、次のスクリプトでリリースビルドを作ります。全部入り版（`dist/release/bin/sigma`）とFORTH 2012プロファイル（`dist/release-forth2012/bin/sigma`）をビルドします。後者は標準ワードセットを残し、グラフィックス、サウンド、Sigmaの拡張語彙を除きます。`--variant full` または `--variant forth2012` で片方だけにでき、出力先は `--output` と `--forth2012-output` で変えられます。`--target` を指定しない場合、LinuxではそのマシンのCPU向けmusl（`x86_64-linux-musl`または`aarch64-linux-musl`）、macOSではそのマシン向けbaseline CPU（`-Dcpu=baseline`）をビルドします。オプションは `--help` にあります。

    ./scripts/build-release.sh

別の対象向けには `--target` を付けます。Zigは別のOSやCPU向けにもビルドできるので、どのOSでも作れます。GitHub Actionsが使う対象は、Linux x86_64が `x86_64-linux-musl`、Linux arm64が `aarch64-linux-musl`、macOS arm64が `aarch64-macos` です。Linux向けは、共有ライブラリを使わない実行ファイルになり、どのディストリビューションでも動きます。

    ./scripts/build-release.sh --target aarch64-linux-musl

Linuxにはインストーラーがないので、実行ファイルを `PATH` のディレクトリにコピーします。macOSでも同じようにコピーして使えます。

    sudo install -m 755 dist/release/bin/sigma /usr/local/bin/sigma

GitHub Actions（`.github/workflows/release.yml`）は手動起動（Actions > Release > Run workflow）に加え、`v0.13.0`のように`VERSION`と一致する`v`付きタグのpushでも動きます。Windows x86_64、Linux x86_64・arm64、macOS arm64で2つのプロファイルをテスト・ビルドし、各ZIPを実行の成果物（artifact）に残します。すべてのZIPに実行ファイル、LICENSE、THIRD_PARTY_NOTICES.md、README.mdが入ります。全部入りZIPにはSigma固有の`include`ライブラリと`examples`のサンプルも入ります。FORTH 2012プロファイルのZIPにはどちらも入りません。VERSIONと一致するタグの全ジョブ成功後、Linux x86_64向けのZIP（`sigma-版番号-linux-x86_64.zip`と`sigma-版番号-linux-x86_64-forth2012.zip`）とSHA256をGitHub Releaseに公開します。他の対象のZIPはActionsのartifactに残します。各対象には全部入り版（`sigma-版番号-対象.zip`）とFORTH 2012プロファイル（`sigma-版番号-対象-forth2012.zip`）があります。テストはWindows x86_64、Linux x86_64・arm64、macOS arm64で実行します。Windows向けのZIPは、次のスクリプトで同じ名前に作ります（`dist\zip\sigma-版番号-windows-x86_64.zip`と`sigma-版番号-windows-x86_64-forth2012.zip`）。`-Variant Full`または`-Variant Forth2012`で片方を選べます。

    .\scripts\build-zip.ps1

LinuxとmacOSのZIPは、次のスクリプトでGitHub Actionsと同じ名前・中身のもの（`dist/zip/sigma-版番号-対象.zip` と `dist/zip/sigma-版番号-対象-forth2012.zip`）を作ります。全部入りZIPには`include`と`examples`が入り、FORTH 2012プロファイルにはどちらも入りません。対象は指定がなければそのマシンで、`--platform` で `linux-x86_64`、`linux-arm64`、`macos-arm64`、または全部（`all`）を選びます。`--variant full` または `--variant forth2012` で片方だけ作り、`--output` で出力先を指定します。`zip` コマンドが必要です。

    ./scripts/build-zip.sh
    ./scripts/build-zip.sh --platform all

対話プロンプトの前に、版番号とライセンスの2行（`FORTH/Sigma 0.13.0  MIT License`、`` Type `help' for basic help ``）を表示します。`HELP` で基本的な使い方、`HELP DUP` のように語名を付けるとその語の説明、`LICENSE` でライセンスの全文を表示します。

例:

    : SQUARE DUP * ;
    12 SQUARE .

Gforthと同じく、コマンドラインの引数はそれぞれ読み込むForthソースファイルの名前で、左から順に読み込みます。`-e 文字列` はその文字列を実行します。最後の引数の後は、`BYE` で終了していなければ対話プロンプトになります。引数でエラーが起きると、終了コード1で終了します。上の2行を `square.fs` に保存した場合の例:

    sigma.exe square.fs
    sigma.exe -e "12 DUP * . BYE"

Forthソースファイルは標準入力からも読み込めます。例:

    sigma.exe < square.fs

Boingデモは、市松模様の球が回転して跳ねるアニメーションです。[元の版](examples/boing.fs)は320×200、[HD版](examples/boing-hd.fs)は960×600、[HFR版](examples/boing-hfr.fs)は1920×1200で120fpsを目標に描画します。グラフィックスと浮動小数点の語が必要で、音は省略可能です。Spaceで一時停止・再開、QまたはEscで終了します。HFR版には高速ビルドを使います。

```sh
zig build -Doptimize=fast
zig-out/bin/sigma examples/boing-hfr.fs
```

HFR版は1280×800の窓で開き、リサイズできます。目標値はモニターの実表示fpsを保証しません。各版の違いと性能上の制限は[グラフィックスとサウンドのマニュアル](docs/GRAPHICS_AND_SOUND.ja.md)を参照してください。

`examples/calculator.fs` は、窓とボタンはTkで、計算はForthで行う電卓です。Tcl/Tkが必要で、Sigmaは `SIGMA_WISH`、なければ `PATH` の `wish` を使います。Windowsではそれもなければ Git for Windows の `wish`、macOSではシステムの `/usr/bin/wish` は飛ばし、それもなければHomebrewかMacPortsのものを使います。

    sigma.exe < examples/calculator.fs

この移植版の `SAVE filename`／`LOAD-DICTIONARY filename` は利用者定義語を辞書イメージとして保存・追加読み込みします。同名語は新しい定義が優先され、`FORGET` で新しい方を削除すると古い定義に戻ります。誌面の `LOAD`／`SAVE` はエディットバッファ操作であり、その機能は実装していません。登録語を含む単独実行ファイルは `SAVESYS` で作成します。

    SAVE words.sigma
    SAVESYS demo.exe

保存した実行ファイルは登録語を持って起動し、`sigma.exe` と同じ引数を受け付けます。引数なしなら対話プロンプトを開き、`demo.exe -e "12 SQUARE . BYE"` なら式を実行して終了します。サンプルは `12` の平方である `144` を表示します。

### 語のグループを除く

ビルドのオプションで、語のグループを除けます。プログラムを小さくしたいときや、そのグループを使わないホストのためです。オプションを付けなければ、すべてのグループを含みます。

| オプション | 除くもの | 大きさ |
|---|---|---|
| （なし） | — | 2,465,792バイト |
| `-Dfloat=false` | 浮動小数点の語、浮動小数点数のリテラル（`1e` など）、`F:` `F^` のローカル変数、`ENVIRONMENT?` の `FLOATING-STACK` `MAX-FLOAT`、CORE-MATH、グラフを描くグラフィックスの語（`PLOT` など） | 2,010,624バイト |
| `-Dfiles=false` | `INCLUDE`、`REQUIRE`、`OPEN-FILE`、`STDIN`、`SLURP-FILE`、`$...SLURP` の語など、ファイルを開く・読む・書く・取り込む語 | 2,381,824バイト |
| `-Dhelp=false` | `HELP`、`LICENSE` とその文章（起動時の表示も `help` を案内しなくなります） | 2,174,464バイト |
| `-Dtools=false` | `SEE`、`LOCATE`、`WHERE` | 2,416,640バイト |
| `-Dimage=false` | `SAVE`、`LOAD-DICTIONARY`、`SAVESYS` | 2,461,696バイト |
| `-Dgraphics=false` | `REQUIRE-GRAPHICS`、`GFX-` の語、グラフィックスのライブラリとそのフォント、Tcl/Tkの語 | 2,063,360バイト |
| `-Daudio=false` | `REQUIRE-AUDIO`、`SND-` の語、音のライブラリ、音のスレッド | 2,323,968バイト |
| `-Dextension=false` | `REQUIRE-EXTENSION`とEXTENSION語彙（`HOST-OS`を含む） | 2,290,688バイト |
| `-Ddebug=false` | デバッグ機能（エラーの後のバックトレース、`--max-steps`、`--trace`、`--profile`、`--debug-log`、`--lint`、`--format`、`--coverage`、語 `WATCH` `UNWATCH` `.COVER-RAW` `COV%` `.COVERAGE` `DBG` `BREAK:` `BREAK"` `~~BT` `~~1BT` `ONCE` `~~VALUE` `~~VARIABLE` `+LTRACE` `-LTRACE`） | 2,345,984バイト |
| `-Dfloat=false` から `-Daudio=false` までの7つ | その7つのすべて | 1,184,256バイト |
| その7つと `-Ddebug=false` | その7つとデバッグ機能 | 1,098,240バイト |
| 9つのオプションすべて | すべてのグループ | 969,216バイト |

大きさは、版0.13.0（コミット `f8fd8f0`）をリリースと同じ `-Doptimize=fast -Dcpu=baseline -Dstrip=true` でWindows x86_64向けにビルドしたものです（2026-11-28に測定）。同じ条件で、0.12.0の全部入りは1,837,568バイトでした。Linux（x86_64 musl）の全部入りは2,701,928バイトで、X11のウィンドウを除く `-Dx11=false` では2,486,984バイトです。オプションは組み合わせられます（例: `zig build -Doptimize=fast -Dfloat=false -Dhelp=false`）。ほかの組み合わせの大きさと、8つの小さなカーネルの速度（0.12.0・Gforthとの比較）は[サイズ測定・速度比較](docs/SIZE_SPEED_MEASUREMENT.md)にあります。


EXTENSIONの語彙は既定で含まれます。`REQUIRE-EXTENSION ALSO EXTENSION HOST-OS TYPE PREVIOUS` で、Sigmaが動いているOSの系列（`windows`、WSLとAndroidを含む`linux`、`macos`、`unknown`）を表示します。この語彙には、端末のモードと大きさ（`TERM-MODE!`、`TERM-MODE@`、`COLS`、`ROWS`）、キー・マウス・貼り付けのイベントの待ち（`EKEY-WAIT`、`EKEY-MOUSE`）、計算タスク、ファイルとパスの道具もあります。すべての語は[拡張機能のマニュアル](docs/EXTENSION.ja.md)に、タスクの使用例は[タスクAPIの説明](docs/README.ja.md#計算タスク)にあります。`-Dextension=false` では `REQUIRE-EXTENSION` は未定義の語（-13）になります。音と描画が内部で使う時計と待ちは残ります。

除いたグループの語は辞書になく、`HELP` の説明もありません。グループはそれぞれ独立しているので、ファイルの語を除いても、`SAVE`・`LOAD-DICTIONARY`・`SAVESYS` はイメージのファイルを書き読みし、`LOCATE` はソースファイルを読みます（それぞれのグループも除いた場合を除きます）。組み込み語の実行トークンは機能構成間で共通ですが、読込み先が除いた語群の追加組込み語や直接組込み命令を含むイメージは、変更前に`INVALID IMAGE`で拒否します。生の数値として保存した実行トークンを使う場合の`INVALID EXECUTION TOKEN`の防御も維持します。組込み語の表が異なる旧版イメージもABI照合で拒否します。

イメージの機能検査は、追加した組込み語と直接の組込み命令を対象とします。起動時から予約されている基本辞書の欄への通常の呼出しは従来どおり読み込めて、除いた語を実行したときに`INVALID EXECUTION TOKEN`になります。生の実行トークンをデータとして保存する場合とは別の制約です。

テストも同じオプションで実行でき（例: `zig build test -Dfloat=false`）、除いたグループを使うテストは飛ばします。

`zig build freestanding` は、コア（`src/forth.zig` と `src/core/`）を、ホストが呼ぶ処理（起動、1行の解釈、イメージの関数）からOSのないCortex-M0+向けにコンパイルします。その処理がZigの標準ライブラリを通してOSの機能を使うと失敗するので、マイコンなど独自のホストでもコアを使える状態を保てます。リンクはしないので、コアが自分で `extern` と宣言した関数は見つけられません。`zig build test` にも含まれます。

## Gforth・標準Forthとの関係

2026-10-28から、数値まわりと基本ワードを[Gforth](https://github.com/forthy42/gforth)の挙動に合わせ、教材ForthBasicMasterのサンプルが動くことを目標にしています。作業は6段階に分けており、段階1（64ビットセル、真=-1、床関数除算、全文字の名前照合、`TYPE ( addr u )`、基本標準ワード）、段階2（浮動小数点）、段階3（`S"` などの文字列、倍長整数、`<# #>` による数値書式）と、教材で使う小規模なワード（`WITHIN`、`:NONAME`、`STATE`、`MS`、`GETENV`、`SYSTEM` など）、`THROW`／`CATCH` と主なファイル操作（`OPEN-FILE`、`READ-LINE`、`WRITE-LINE` など）、`ALLOCATE` と動的文字列（`$!`、`$[]!` など）、ローカル変数（`{ a b -- c }`、`F:` などの型指定、`LOCALS|`）、ソースファイルの読み込み（`INCLUDE`、`REQUIRE` など）、`SEE`・`LOCATE`・`MARKER`、語彙（`VOCABULARY`、`ONLY`、`ALSO` など）と `[IF]` を実装済みで、6段階はすべて終わりました（[決定事項・保留事項](https://github.com/fukuyori/ForthSigma/blob/main/docs/DECISIONS.md)）。

この実装は**ANS Forth／Forth 2012準拠を保証する処理系ではありません**。調べた範囲の状況は、下の[Forth 2012の準拠状況](#forth-2012の準拠状況)にまとめています。Gforthと意味が衝突しないFORTH/Σ固有のワードは残しています。

| 項目 | FORTH/Σ資料 | 現在の移植版 |
| --- | --- | --- |
| セル幅 | 16ビット | 64ビット（Gforthの64ビット環境と同じ） |
| 真偽値 | 0が偽、1が真 | 0が偽、-1が真 |
| 名前の識別 | 長さと先頭5文字 | 名前全体（大小文字は区別しない） |
| TYPE | ( u addr -- ) | ( addr u -- ) |
| 文字列 | "..."は長さの後にアドレスを積む | "..."はアドレスの後に長さを積む。."も拡張として提供。S"、S\"、.\"も使える |
| 数値表示 | .は空白なし、16進4桁、8進6桁 | .は末尾に空白、ゼロ埋めなし、全基数で符号付き |
| 除算 | 資料で確定しない | 床関数除算。ゼロ除算はエラー |
| LEAVE | 次のLOOPで終了 | 即座にループを抜ける |
| DO | 開始値と終値が同じでも1回実行 | Forth 2012・Gforthと同じ。添字が一周するまで繰り返す。空の範囲を飛ばすには `?DO` を使う |
| 浮動小数点 | なし | 専用スタック、倍精度、`E` を含むリテラル |

標準側の定義は[Forth 2012 Standard](https://forth-standard.org/standard/index)を参照してください。個々の挙動と移植上の判断は、仕様書・実装ノート・決定事項に記録しています。

### Forth 2012の準拠状況

2026-11-17に、Forth 2012規格書の語の一覧（25語群・450項目、名前は435種類）と照合しました。全機能を有効にしたビルドは、450項目のうち446項目を備えています。

| 語群 | 利用可 / 項目数 | 利用不可 |
| --- | ---: | --- |
| CORE | 133 / 133 |  |
| CORE EXT | 49 / 49 |  |
| BLOCK | 8 / 8 |  |
| BLOCK EXT | 6 / 6 |  |
| DOUBLE | 20 / 20 |  |
| DOUBLE EXT | 3 / 3 |  |
| EXCEPTION | 2 / 2 |  |
| EXCEPTION EXT | 2 / 2 |  |
| FACILITY | 3 / 3 |  |
| FACILITY EXT | 37 / 37 |  |
| FILE | 21 / 21 |  |
| FILE EXT | 8 / 8 |  |
| FLOATING | 31 / 31 |  |
| FLOATING EXT | 48 / 48 |  |
| LOCAL | 1 / 1 |  |
| LOCAL EXT | 2 / 2 |  |
| MEMORY | 3 / 3 |  |
| TOOLS | 5 / 5 |  |
| TOOLS EXT | 18 / 22 | `;CODE`, `ASSEMBLER`, `CODE`, `EDITOR` |
| SEARCH | 9 / 9 |  |
| SEARCH EXT | 5 / 5 |  |
| STRING | 8 / 8 |  |
| STRING EXT | 3 / 3 |  |
| XCHAR | 10 / 10 |  |
| XCHAR EXT | 11 / 11 |  |

利用できない4語はプログラミングツール拡張の語で、アセンブラーまたはエディターを必要とします。語ごとの状況は[語の一覧](docs/forth2012-word-status.tsv)にあります。

この集計の意味と限界は次のとおりです。

- 名前の有無を数えたものです。大半の項目は `[DEFINED]` で確認しました。テキストインタープリターが構文として処理する語（`\`、`."`、`S"`、`S\"`、`C"`、`.(`、`ABORT"`、`[CHAR]`、`[']`、`[`、`]`、`POSTPONE`、`:NONAME`、`{:`、`LOCALS|`、`FORGET`）は、実際に動かして確認しました。
- 準拠試験ではありません。すべての語の動作を規格本文と比べたわけではありません。Sigmaは標準システムであるとは主張しません。
- 語群を外したビルド（`-Dfloat=false` など）では、使える語が減ります。

規格のテストスイート（[Forth-Standard/forth-standard-test-suite](https://github.com/Forth-Standard/forth-standard-test-suite)、バージョン0.13.4）を、2026-11-17に全機能のWindowsビルドで実行しました。`runtests.fth`（約1,920件）は最後まで実行でき、失敗の報告は文字列語群の2件です。

| 部分 | 結果 |
| --- | --- |
| Core、Core extension、Block、Double number、Exception、Facility、File-access、Locals、Memory-allocation、Programming-tools、Search-order | 失敗なし |
| String | 失敗2件。テストは置換名 `MAC3` を作り、`%mac3%` として使う。Sigmaは置換名の大文字と小文字を区別し、Gforth 1.0.2も同じで、Gforthも同じ2件が失敗する。規格はこの名前の大文字小文字の扱いを定めていない |
| 浮動小数点（`fp/runfptests.fth`） | 失敗なし。`fatan2-test`、`ieee-arith-test`、`ieee-fprox-test`、`fpzero-test`、`to-float-test` はエラー0件、`fpio-test` と `ak-fp-test` は完了、`paranoia` は失敗・欠陥・不備なし |

浮動小数点の部分では、テストハーネスを1か所変更しました。Forth 2012が廃止予定としている `FLOATING` の環境問合せにSigmaは「不明」と答えるため、`ttester.fs` の `HAS-FLOATING` を手で設定しています。表示を目で確かめる種類のテスト（文字の表示、数値の書式）は判定していません。スイート自身が「テストは網羅的ではない」と断っており、通過したことでSigmaが標準システムになるわけではありません。同じ日の最初の実行では10種類の相違が見つかり、その後に修正しました。[2回の実行とログ](docs/measurements/2026-11-17-forth2012-test-suite.json)。

規格本文と比べた動作は次のとおりです。

| 項目 | 規格 | Sigma |
| --- | --- | --- |
| 開始値と終値が同じ `DO` | 特別な扱いはない。`LOOP` は1を足した添字が終値と等しいときだけ終了する（6.1.1240、6.1.1800） | 2026-11-17から同じ。それ以前の版は本体を1回実行していた |
| 開始値と終値が同じ `?DO` | 本体を実行しない（6.2.0620） | 同じ |
| `+LOOP` | 添字が「終値−1」と「終値」の境界をまたいだら終了する（6.1.0140） | 同じ。負の増分でも同じ |
| `LEAVE`、`UNLOOP` | 直ちに抜ける。`EXIT` の前に `UNLOOP`（6.1.1760、6.1.2380） | 同じ |
| ループ制御パラメーター | 処理系はリターンスタックに置いてよい（3.2.3.3） | 専用のループスタックに置く。規格に沿ったプログラムでは違いが現れない |
| 構造体 | `BEGIN-STRUCTURE`、`+FIELD`、`FIELD:`、`CFIELD:`、`FFIELD:`、`SFFIELD:`、`DFFIELD:`、`END-STRUCTURE` | 利用可。試験用の構造体の大きさとオフセットはGforthと同じ |

### Gforthとの違い

SigmaはGforthと合わせられる範囲でGforthに従い、WSLで動かしたGforthと語を比べています。分かっている違いは次のとおりです。語ごとの記録は[互換性一覧](docs/COMPATIBILITY.ja.md)にあります。

| 項目 | Gforth | Sigma |
| --- | --- | --- |
| ループ制御パラメーター | リターンスタックに置く。ループの中の `R@` はループ添字を返し、`>R` の後の `I` は積んだ値を返す | 専用のループスタックに置く。`R@` はプログラムが積んだ値を返し、`I` は添字のまま。どちらの使い方も規格の範囲外 |
| `2RDROP EXIT` によるループ脱出 | 動く | プログラム自身のセルがリターンスタックにないと-6になる。両方で動く `UNLOOP EXIT` を使う |
| `CODE`、`END-CODE`、`;CODE`、`ASSEMBLER` | 利用可 | 利用不可（アセンブラーがない） |
| `SAVESYSTEM`、`'COLD`、`BOOTMESSAGE`、`SCRIPT?` | 利用可 | 利用不可。イメージの保存は `SAVESYS` |
| メモリー | ホストのアドレス | 独自のアドレスを持つ1つの論理メモリー（既定64 MiB）。`-m`、`-d`、`-r`、`-f`、`-l` で大きさを指定する |
| 空または未設定の `FPATH` | 空の検索パス | 従来どおりカレントディレクトリーからファイルを探す |
| `IS` | 遅延語 | `FVALUE`、`2VALUE`、`$VALUE` にも使える。対象外の語は-259 |
| パイプ | `BROKEN-PIPE-ERROR` は-2049 | 単方向だけ（`R/O` または `W/O`）。`BROKEN-PIPE-ERROR` は-544 |
| 浮動小数点関数 | Gforth自身の結果 | CORE-MATHによる正しい丸め。一部の結果がGforthと1 ulp異なる |
| `SEE` | Gforthの逆コンパイル表示 | 独自の形式。たとえばフィールドは `オフセット +FIELD 名前` |
| FORTH/Σの語 | なし | 衝突しない範囲で残している。たとえば `"..."` の文字列、`BEGIN ... END` |

ループの行は2026-11-17にGforth 1.0.2で実行して確かめました。その他の行は互換性一覧に記録した比較に基づき、その多くはGforth 0.7.9_20260410との比較です。

## 出典・参考資料

### FORTH/Σの一次資料

本プロジェクトでは、一ノ瀬敏彰／山口晶嗣による「FORTH/Σ」を、『エンサイクロペディア・アスキー』第11巻（ASCII 1982年4月号）から第13巻（同年9月号）までの連載誌面で参照しています。以下に各回の巻・号と誌面ページを示します。

| 資料 | 誌面ページ | 主な参照箇所 |
| --- | --- | --- |
| 一ノ瀬敏彰／山口晶嗣「FORTH/Σ」『エンサイクロペディア・アスキー 第11巻 ASCII 1982年4月号』 | pp. 108–117 | 概要、辞書、インタプリタ、制御構造、ユーザーズマニュアル、ワード表。 |
| 同「FORTH/Σ」『エンサイクロペディア・アスキー 第12巻 ASCII 1982年5月号』 | pp. 166–173 | PC-8001版の説明、メモリ配置、エディタ、機種固有ワード。 |
| 同「FORTH/Σ」『エンサイクロペディア・アスキー 第12巻 ASCII 1982年6月号』 | pp. 92–99 | 辞書検索、数値変換、定義作成、コンパイルと制御構造のZ80ソース。 |
| 同「FORTH/Σ」『エンサイクロペディア・アスキー 第12巻 ASCII 1982年7月号』 | pp. 178–185 | 定義、制御構造、メモリ、スタック、ワード一覧。 |
| 同「FORTH/Σ」『エンサイクロペディア・アスキー 第12巻 ASCII 1982年8月号』 | pp. 144–151 | 数値出力、算術処理などのソースリスト。 |
| 同「FORTH/Σ」『エンサイクロペディア・アスキー 第13巻 ASCII 1982年9月号』 | pp. 172–179 | CP/M版の編集・ファイル処理。 |

上記の誌面ページ情報は[FORTH/Σ仕様書](https://github.com/fukuyori/ForthSigma/blob/main/docs/SPEC.ja.md)に記録しています。誌面のZ80ソースは処理内容を調べるために参照したもので、移植版はZ80機械語や誌面のソースコードを収録・実行していません。

### 比較・照合に使った資料

- [Gforth](https://github.com/forthy42/gforth)のソースコードと[マニュアル](https://gforth.org/manual/)を、名前照合など資料で確定しない実装上の挙動を検討する際の比較資料として参照しています。FORTH/Σの仕様根拠ではありません。
- ForthBasicMasterの教材を、Forthの用語や利用例を確認するための参考資料として参照しています。FORTH/Σの仕様根拠ではありません。
- Forth 2012との違いは、[Forth 2012 Standard](https://forth-standard.org/standard/index)の該当する定義と比較しています。

### 資料とライセンスの範囲

MITライセンスは、このプロジェクトで作成したプログラムコードとドキュメントを対象とします。雑誌記事、その他の第三者資料はMITライセンスの対象ではありません。第三者資料はリポジトリに含めていません。出典を示すことは、第三者資料の複製・再配布許諾を意味しません。

## ライセンス

プロジェクトで作成したコードとドキュメントは[MIT License](https://github.com/fukuyori/ForthSigma/blob/main/LICENSE)で提供します。浮動小数点の数学関数（`FSIN` `FEXP` `FASIN` `F**` など）は、CORE-MATHのコード（MIT License、`src/core-math/`）と、FMA命令のないCPUではmuslの `fma`（MIT License、`src/fma/`）を使います。Linuxの `SYSTEM-FONT` は、フォントファイルの読み取りにstb_truetype（MIT License、`src/stb/`）を使います。著作権表示は[THIRD_PARTY_NOTICES.md](https://github.com/fukuyori/ForthSigma/blob/main/THIRD_PARTY_NOTICES.md)にあります。第三者資料の扱いは上記「資料とライセンスの範囲」を参照してください。

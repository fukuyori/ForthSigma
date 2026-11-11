# FORTH/Σ for Zig

英語版（正）: [README.md](https://github.com/fukuyori/ForthSigma/blob/main/README.md)。この日本語版は英語版の訳です。内容が異なる場合は英語版に従ってください。

FORTH/Σ（フォース・シグマ）の言語コアを、Zigで動くネイティブな移植版として実装するプロジェクトです。1982年の月刊アスキー誌面に掲載されたFORTH/Σの説明とZ80ソースリストを仕様調査の資料として使っています。Z80の命令や機械語を実行・エミュレートするものではありません。

## 現在の実装

- 64ビットセルと、既定で64 MiBの論理メモリ（辞書の32 MiB（うち80 KiBはシステム用で、残りがデータ領域）、同じ大きさの `ALLOCATE` のヒープ、64 KiBのローカル変数の領域）を使います。スタックは各4096要素です。大きさは、gforthと同じオプション（`-m`、`-d`、`-r`、`-f`、`-l`）で起動時に指定できます。真の値は-1で、除算は床関数除算です。
- 浮動小数点数（倍精度）を専用スタックで扱えます。`1E`、`1.5e0` のように `E` を含む数が浮動小数点数になり、`F+`、`F.`、`FSQRT`、`FCONSTANT` などのF系ワードを使えます。
- 対話入力、辞書検索、数値入力、ワード定義とコンパイルに対応しています。
- スタック操作、算術・比較・論理演算、メモリ操作、変数・定数・値・配列を使えます。
- IF ... ELSE ... THEN、BEGIN ... END/UNTIL、BEGIN ... AGAIN、BEGIN ... WHILE ... REPEAT、CASE ... ENDCASE、DO ... LOOP、DO ... +LOOP、LEAVE、EXITを使えます。
- IMMEDIATE、POSTPONE、RECURSE、CREATE ... DOES> でコンパイラを拡張できます。
- HEX、DEC、OCTによる基数変更、数値・文字・文字列の出力に対応しています。
- `S"` などの文字列、`123.` 形式の倍長整数（128ビット）、`<<# # #S #> #>>` による数値の書式、`ACCEPT`、`EVALUATE`、`KEY` を使えます。
- WORDS、FORGET、BYEを対話用ワードとして提供します。
- この移植版の拡張として、グラフィックス（`REQUIRE-GRAPHICS`）を使えます。メモリ上の画像に線、図形、塗りつぶし、グラフ、文字（組み込みのASCIIフォント、BDFフォント、Windowsではシステムのフォント）を描き、端末（半角ブロックかSixel）、Windowsのウィンドウ、Tkのウィンドウに表示します。ほかにも画像を作って描いたり写し合ったりでき、PNG、BMP、PPM のファイルから読み込めます。キーとマウス（`INKEY`、`MOUSE`、`MOUSE-EVENT`）、毎フレーム描く GUI（`REQUIRE-GUI`）、ゲーム用のスプライト、タイルマップ、パレット（`REQUIRE-GAME`）と、Sigmaが起動する `wish` でのTcl/Tkのスクリプト（`TCL`、`TCL-EVAL`、`TCL-EVENT`）も使えます。Tcl/TkはSigmaにリンクしないので、TCL の語を使うにはTcl/Tkを入れておく必要があります。
- この移植版の拡張として、サウンド（`REQUIRE-AUDIO`）を使えます。MSX BASIC の `PLAY`、`SOUND`、`BEEP` と MML を、音のスレッドがプログラムと並行して鳴らします。MSX、Atari ST、NES、C64、コナミの SCC、Amiga の音源を、1つずつ、またはいくつか同時に、音色を付けて鳴らせます。WAV ファイルの録音した音と効果音、ProTracker のモジュール（MOD ファイル）も鳴らせます。[サウンド](https://github.com/fukuyori/ForthSigma/blob/main/docs/GRAPHICS_AND_SOUND.ja.md#サウンド)と `examples/music.fs` を参照してください。
- 辞書、コンパイル済み定義、メモリ、入出力をホスト環境から分離し、他のOS・CPUへ移植しやすい構成にしています。

対応ワードと移植上の判断は[実装ノート](https://github.com/fukuyori/ForthSigma/blob/main/docs/IMPLEMENTATION.md)、資料から整理した言語仕様は[FORTH/Σ仕様書](https://github.com/fukuyori/ForthSigma/blob/main/docs/SPEC.ja.md)を参照してください。実装は開発中であり、誌面の全ワードや機種固有機能には対応していません。

使い方と現在登録されている組み込みワードの一覧は[ユーザーマニュアル](https://github.com/fukuyori/ForthSigma/blob/main/docs/USER_MANUAL.ja.md)を、グラフィックスとサウンドは[グラフィックスとサウンドのマニュアル](https://github.com/fukuyori/ForthSigma/blob/main/docs/GRAPHICS_AND_SOUND.ja.md)を、プログラムの悪いところの調べ方は[デバッグの手引き](https://github.com/fukuyori/ForthSigma/blob/main/docs/DEBUGGING.ja.md)を参照してください。

利用者がデータを持つワードを作る定義用語（BUILDS/DOES）にも対応しています。

`SAVE filename`／`LOAD filename` で利用者定義語を保存・追加読み込みできます。単独実行ファイルは別の拡張語 `SAVESYS filename.exe` で作成します。

ワードごとの対応状況は[互換性一覧](https://github.com/fukuyori/ForthSigma/blob/main/docs/COMPATIBILITY.ja.md)、資料で確定した仕様と移植上の判断の区別は[決定事項・保留事項](https://github.com/fukuyori/ForthSigma/blob/main/docs/DECISIONS.md)を参照してください。

現時点では、LIST、ソースファイルやエディタの操作、CP/Mのファイル機能、PC-8001のモニタ機能、Z80機械語を使うワードには対応していません。

### グラフィックモード

BASICの `SCREEN 1` のような番号付きの画面モードはありません。プログラムは `GFX-INIT` ( w h -- ) で任意の大きさ（各辺1〜16384画素）の画像を1枚作り、`SHOW` の表示先と色数を別々に選びます。画像そのものは常にフルカラーで、ファイルにもフルカラーで保存します。

| `SHOW` の表示先 | 語 | 使える環境 |
| --- | --- | --- |
| 端末、半角ブロック（1文字で2画素） | `DISPLAY-TERMINAL TERMINAL-BLOCKS` | すべてのOS |
| 端末、Sixel | `DISPLAY-TERMINAL TERMINAL-SIXEL` | Sixelに対応した端末 |
| ウィンドウ | `DISPLAY-WINDOW` | Windows |
| Tkのウィンドウ | `DISPLAY-TK` | Tcl/Tkが入っている環境 |

選ぶまでは、`SHOW` はWindowsではウィンドウに表示します。LinuxとmacOSでは、Tcl/Tkが入っていればデスクトップではTkのウィンドウに、ほかでは端末に半角ブロックで表示します。`n DISPLAY-COLORS` で、フルカラー（0、既定）、白黒（2）、ANSIの16色（16）、xtermの256色（256）を選び、`TRUE DITHER` で減らした色をBayerの模様で混ぜます。`w h WINDOW-SIZE` で、ウィンドウとTkのウィンドウに画像を大きく表示します。たとえば `160 120 GFX-INIT 640 480 WINDOW-SIZE` で、1画素を4×4で表示します。

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

コアの回帰テストはzig build testで実行できます。

Linux/macOSでは、生成されたzig-out/bin/sigmaを実行してください。別のZigターゲットを指定する場合はzig build -Dtarget=<triple>を使います。

現在の製品バージョンは [`VERSION`](https://github.com/fukuyori/ForthSigma/blob/main/VERSION) に記載しています。Windows向けリリースビルドとInno Setupインストーラーは次のPowerShellスクリプトで作成できます。インストーラー（`dist\installer\sigma-版番号-windows-x86_64-setup.exe`）は `VERSION` の値を使い、必要なら `-Version MAJOR.MINOR.PATCH` で上書きできます。

    .\scripts\build-release.ps1
    .\scripts\build-installer.ps1

`build-release.ps1` は、浮動小数点の語を含む版（`dist\release`）と除いた版（`dist\release-nofloat`）の両方をビルドします。`-Variant Float` または `-Variant NoFloat` で片方だけにでき、出力先は `-OutputDirectory` と `-NoFloatOutputDirectory` で変えられます。`-Target` を指定しないときもCPUはbaseline（`-Dcpu=baseline`）です。インストーラーは浮動小数点の語を含む版だけです。

署名する場合は `CODESIGN_CERT` に証明書ストア上の証明書サブジェクトを設定し、`-Sign` を指定します。署名時は実行ファイル、インストーラー、アンインストーラーを署名し、実行ファイルとインストーラーの署名を検証します。署名にはRFC 3161のタイムスタンプを付け、証明書の期限が切れた後も署名が有効なままになるようにします。タイムスタンプのサーバーは既定で `http://timestamp.digicert.com`（証明書のルートであるDigiCertのサーバー）で、環境変数 `CODESIGN_TIMESTAMP_URL` で変えられます。タイムスタンプが付かなかった場合はエラーにします。

    .\scripts\build-release.ps1 -Sign
    .\scripts\build-installer.ps1 -Sign

GitHub Actions（`.github/workflows/release.yml`）は、手で起動すると（Actions > Release > Run workflow）、Windows x86_64、Linux x86_64・arm32・arm64、macOS arm64でテストとビルドを行い、各ZIP（実行ファイル、LICENSE、THIRD_PARTY_NOTICES.md、README.md。マニュアルは README のリンクから GitHub で読む）を実行の成果物（artifact）として残します。タグのプッシュでは起動せず、リリースも作りません。リリースは、`v0.10.0` のように `VERSION` と同じ版番号のタグで、手で作ります。ZIPは対象ごとに、浮動小数点の語を含む版（`sigma-版番号-対象.zip`）と除いた版（`sigma-版番号-対象-nofloat.zip`）の2つです。テストはWindows x86_64、Linux x86_64・arm64、macOS arm64の実機で実行します。CIのWindows版は署名なしなので、リリースのWindows版には、次のスクリプトで作った同じ名前・同じ中身の署名付きZIP（`dist\zip\sigma-版番号-windows-x86_64.zip` と `dist\zip\sigma-版番号-windows-x86_64-nofloat.zip`）を使います。`-Variant Float` または `-Variant NoFloat` で片方だけ作ることもできます。

    .\scripts\build-zip.ps1 -Sign

macOSでは、次のスクリプトでインストーラーパッケージ（`dist/pkg/sigma-版番号-macos-universal.pkg`）を作り、署名し、Appleの公証を受けてチケットを添付（staple）します。パッケージは、ユニバーサルの実行ファイル（arm64とx86_64、macOS 11以降）を `/usr/local/bin/sigma` に、文書を `/usr/local/share/doc/sigma` に入れます。実行ファイルはキーチェーンの「Developer ID Application」の証明書でHardened Runtimeを付けて署名し、パッケージは「Developer ID Installer」の証明書で署名します。別の証明書は `--identity` と `--installer-identity` で指定します。公証の資格情報は、キーチェーンのプロファイル `notarytool`、`sigma`、`notary` のうちあるもの、`--profile` で指定したもの、または `--apple-id`、`--team-id`、`--password` です。`--variant nofloat` または `--variant both` で浮動小数点の語を除いた版も作り、`--arch arm64` または `--arch x86_64` で片方のアーキテクチャだけにし、`--skip-notarize` で署名だけにします。オプションの一覧は `--help` で表示します。

    xcrun notarytool store-credentials notarytool --apple-id <id> --team-id <team> --password <app-pw>   # 最初の1回だけ
    ./scripts/sign-and-notarize-macos.sh

対話プロンプトの前に、版番号とライセンスの2行（`FORTH/Sigma 0.10.0  MIT License`、`` Type `help' for basic help ``）を表示します。`HELP` で基本的な使い方、`HELP DUP` のように語名を付けるとその語の説明、`LICENSE` でライセンスの全文を表示します。

例:

    : SQUARE DUP * ;
    12 SQUARE .

Gforthと同じく、コマンドラインの引数はそれぞれ読み込むForthソースファイルの名前で、左から順に読み込みます。`-e 文字列` はその文字列を実行します。最後の引数の後は、`BYE` で終了していなければ対話プロンプトになります。引数でエラーが起きると、終了コード1で終了します。例:

    sigma.exe examples/demo.fs
    sigma.exe -e "12 DUP * . BYE"

Forthソースファイルは標準入力からも読み込めます。例:

    sigma.exe < examples/demo.fs

`examples/calculator.fs` は、窓とボタンはTkで、計算はForthで行う電卓です。Tcl/Tkが必要で、Sigmaは `SIGMA_WISH`、なければ `PATH` の `wish` を使います。Windowsではそれもなければ Git for Windows の `wish`、macOSではシステムの `/usr/bin/wish` は飛ばし、それもなければHomebrewかMacPortsのものを使います。

    sigma.exe < examples/calculator.fs

この移植版の `SAVE filename`／`LOAD filename` は利用者定義語を辞書イメージとして保存・追加読み込みします。同名語は新しい定義が優先され、`FORGET` で新しい方を削除すると古い定義に戻ります。誌面の `LOAD`／`SAVE` はエディットバッファ操作であり、その機能は実装していません。登録語を含む単独実行ファイルは `SAVESYS` で作成します。

    SAVE words.sigma
    SAVESYS demo.exe

保存した実行ファイルは登録語を持って起動し、`sigma.exe` と同じ引数を受け付けます。引数なしなら対話プロンプトを開き、`demo.exe -e "12 SQUARE . BYE"` なら式を実行して終了します。サンプルは `12` の平方である `144` を表示します。

### 語のグループを除く

ビルドのオプションで、語のグループを除けます。プログラムを小さくしたいときや、そのグループを使わないホストのためです。オプションを付けなければ、すべてのグループを含みます。

| オプション | 除くもの | 大きさ |
|---|---|---|
| （なし） | — | 1,033,728バイト |
| `-Dfloat=false` | 浮動小数点の語、浮動小数点数のリテラル（`1e` など）、`F:` `F^` のローカル変数、`ENVIRONMENT?` の `FLOATING-STACK` `MAX-FLOAT`、CORE-MATH、グラフを描くグラフィックスの語（`PLOT` など） | 644,096バイト |
| `-Dfiles=false` | `INCLUDE`、`REQUIRE`、`OPEN-FILE`、`STDIN`、`SLURP-FILE`、`$...SLURP` の語など、ファイルを開く・読む・書く・取り込む語 | 997,888バイト |
| `-Dhelp=false` | `HELP`、`LICENSE` とその文章（起動時の表示も `help` を案内しなくなります） | 935,936バイト |
| `-Dtools=false` | `SEE`、`LOCATE`、`WHERE` | 974,848バイト |
| `-Dimage=false` | `SAVE`、`LOAD`、`SAVESYS` | 1,031,680バイト |
| `-Dgraphics=false` | `REQUIRE-GRAPHICS`、`GFX-` の語、グラフィックスのライブラリとそのフォント、Tcl/Tkの語 | 894,976バイト |
| `-Daudio=false` | `REQUIRE-AUDIO`、`SND-` の語、音のライブラリ、音のスレッド | 955,904バイト |
| `-Ddebug=false` | デバッグ機能（エラーの後のバックトレース、`--max-steps`、`--trace`、`--profile`、`--debug-log`、`--lint`、`--format`、`--coverage`、語 `WATCH` `UNWATCH` `.COVER-RAW` `COV%` `.COVERAGE` `DBG` `BREAK:` `BREAK"` `~~BT` `~~1BT` `ONCE` `~~VALUE` `~~VARIABLE` `+LTRACE` `-LTRACE`） | 含む版より約15 KB小さい（2026-11-11に計測） |
| 7つすべて | `-Ddebug=false` を除く上のすべて | 299,008バイト |

大きさは、サウンドの語を加えた0.6.1（コミット `d5de15b`）をリリースと同じ `-Doptimize=fast` でWindows x86_64向けにビルドしたものです（2026-11-07に測定）。オプションは組み合わせられます（例: `zig build -Doptimize=fast -Dfloat=false -Dhelp=false`）。

除いたグループの語は辞書になく、`HELP` の説明もありません。グループはそれぞれ独立しているので、ファイルの語を除いても、`SAVE`・`LOAD`・`SAVESYS` はイメージのファイルを書き読みし、`LOCATE` はソースファイルを読みます（それぞれのグループも除いた場合を除きます）。組み込み語の実行トークンはどの版でも同じなので、ある版で保存したイメージは、グループの違う版でも読み込めます。その版で除いた語を実行すると `INVALID EXECUTION TOKEN` のエラーになり、`SEE` はその語を名前で表示します。グループを除いた以前の版（`-Dfloat=false` など）で保存したイメージは、組み込み語の実行トークンが違うので `INVALID IMAGE` になります。

テストも同じオプションで実行でき（例: `zig build test -Dfloat=false`）、除いたグループを使うテストは飛ばします。

`zig build freestanding` は、コア（`src/forth.zig` と `src/core/`）を、ホストが呼ぶ処理（起動、1行の解釈、イメージの関数）からOSのないCortex-M0+向けにコンパイルします。その処理がZigの標準ライブラリを通してOSの機能を使うと失敗するので、マイコンなど独自のホストでもコアを使える状態を保てます。リンクはしないので、コアが自分で `extern` と宣言した関数は見つけられません。`zig build test` にも含まれます。

## Gforth・標準Forthとの関係

2026-10-28から、数値まわりと基本ワードを[Gforth](https://github.com/forthy42/gforth)の挙動に合わせ、教材ForthBasicMasterのサンプルが動くことを目標にしています。作業は6段階に分けており、段階1（64ビットセル、真=-1、床関数除算、全文字の名前照合、`TYPE ( addr u )`、基本標準ワード）、段階2（浮動小数点）、段階3（`S"` などの文字列、倍長整数、`<# #>` による数値書式）と、教材で使う小規模なワード（`WITHIN`、`:NONAME`、`STATE`、`MS`、`GETENV`、`SYSTEM` など）、`THROW`／`CATCH` と主なファイル操作（`OPEN-FILE`、`READ-LINE`、`WRITE-LINE` など）、`ALLOCATE` と動的文字列（`$!`、`$[]!` など）、ローカル変数（`{ a b -- c }`、`F:` などの型指定、`LOCALS|`）、ソースファイルの読み込み（`INCLUDE`、`REQUIRE` など）、`SEE`・`LOCATE`・`MARKER`、語彙（`VOCABULARY`、`ONLY`、`ALSO` など）と `[IF]` を実装済みで、6段階はすべて終わりました（[決定事項・保留事項](https://github.com/fukuyori/ForthSigma/blob/main/docs/DECISIONS.md)）。

この実装は**ANS Forth／Forth 2012準拠を保証する処理系ではありません**。Gforthと意味が衝突しないFORTH/Σ固有のワードは残しています。

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
| DO | 開始値と終値が同じでも1回実行 | 資料どおり（Gforthとは異なる） |
| 浮動小数点 | なし | 専用スタック、倍精度、`E` を含むリテラル |

標準側の定義は[Forth 2012 Standard](https://forth-standard.org/standard/index)を参照してください。個々の挙動と移植上の判断は、仕様書・実装ノート・決定事項に記録しています。

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

プロジェクトで作成したコードとドキュメントは[MIT License](https://github.com/fukuyori/ForthSigma/blob/main/LICENSE)で提供します。浮動小数点の数学関数（`FSIN` `FEXP` `FASIN` `F**` など）は、CORE-MATHのコード（MIT License、`src/core-math/`）と、FMA命令のないCPUではmuslの `fma`（MIT License、`src/fma/`）を使います。著作権表示は[THIRD_PARTY_NOTICES.md](https://github.com/fukuyori/ForthSigma/blob/main/THIRD_PARTY_NOTICES.md)にあります。第三者資料の扱いは上記「資料とライセンスの範囲」を参照してください。

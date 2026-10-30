# FORTH/Σ for Zig

FORTH/Σ（フォース・シグマ）の言語コアを、Zigで動くネイティブな移植版として実装するプロジェクトです。1982年の月刊アスキー誌面に掲載されたFORTH/Σの説明とZ80ソースリストを仕様調査の資料として使っています。Z80の命令や機械語を実行・エミュレートするものではありません。

## 現在の実装

- 64ビットセルと2 MiBの論理メモリ（上半分は `ALLOCATE` のヒープとローカル変数の領域）を使います。真の値は-1で、除算は床関数除算です。
- 浮動小数点数（倍精度）を専用スタックで扱えます。`1E`、`1.5e0` のように `E` を含む数が浮動小数点数になり、`F+`、`F.`、`FSQRT`、`FCONSTANT` などのF系ワードを使えます。
- 対話入力、辞書検索、数値入力、ワード定義とコンパイルに対応しています。
- スタック操作、算術・比較・論理演算、メモリ操作、変数・定数・値・配列を使えます。
- IF ... ELSE ... THEN、BEGIN ... END/UNTIL、BEGIN ... AGAIN、BEGIN ... WHILE ... REPEAT、CASE ... ENDCASE、DO ... LOOP、DO ... +LOOP、LEAVE、EXITを使えます。
- IMMEDIATE、POSTPONE、RECURSE、CREATE ... DOES> でコンパイラを拡張できます。
- HEX、DEC、OCTによる基数変更、数値・文字・文字列の出力に対応しています。
- `S"` などの文字列、`123.` 形式の倍長整数（128ビット）、`<<# # #S #> #>>` による数値の書式、`ACCEPT`、`EVALUATE`、`KEY` を使えます。
- WORDS、FORGET、BYEを対話用ワードとして提供します。
- 辞書、コンパイル済み定義、メモリ、入出力をホスト環境から分離し、他のOS・CPUへ移植しやすい構成にしています。

対応ワードと移植上の判断は[実装ノート](forth/sigma/IMPLEMENTATION.md)、資料から整理した言語仕様は[FORTH/Σ仕様書](forth/sigma/SPEC.md)を参照してください。実装は開発中であり、誌面の全ワードや機種固有機能には対応していません。

使い方と現在登録されている組み込みワードの一覧は[ユーザーマニュアル](forth/sigma/USER_MANUAL.md)を参照してください。

利用者がデータを持つワードを作る定義用語（BUILDS/DOES）にも対応しています。

`SAVE filename`／`LOAD filename` で利用者定義語を保存・追加読み込みできます。単独実行ファイルは別の拡張語 `SAVESYS filename.exe` で作成します。

ワードごとの対応状況は[互換性一覧](forth/sigma/COMPATIBILITY.md)、資料で確定した仕様と移植上の判断の区別は[決定事項・保留事項](forth/sigma/DECISIONS.md)を参照してください。

現時点では、LIST、ソースファイルやエディタの操作、CP/Mのファイル機能、PC-8001のモニタ機能、Z80機械語を使うワードには対応していません。

## ビルドと実行

Zigをインストールした環境で、リポジトリのルートから実行します。

    zig build
    ./zig-out/bin/sigma.exe

コアの回帰テストはzig build testで実行できます。

Linux/macOSでは、生成されたzig-out/bin/sigmaを実行してください。別のZigターゲットを指定する場合はzig build -Dtarget=<triple>を使います。

現在の製品バージョンは [`VERSION`](VERSION) に記載しています。Windows向けリリースビルドとInno Setupインストーラーは次のPowerShellスクリプトで作成できます。インストーラーは `VERSION` の値を使い、必要なら `-Version MAJOR.MINOR.PATCH` で上書きできます。

    .\scripts\build-release.ps1
    .\scripts\build-installer.ps1

署名する場合は `CODESIGN_CERT` に証明書ストア上の証明書サブジェクトを設定し、`-Sign` を指定します。署名時は実行ファイル、インストーラー、アンインストーラーを署名し、実行ファイルとインストーラーの署名を検証します。

    .\scripts\build-release.ps1 -Sign
    .\scripts\build-installer.ps1 -Sign

`v0.1.0` のように `VERSION` と同じ版番号のタグをプッシュすると、GitHub Actions（`.github/workflows/release.yml`）がWindows x86_64、Linux x86_64・arm32・arm64、macOS arm64でテストとビルドを行い、各ZIP（実行ファイル、LICENSE、THIRD_PARTY_NOTICES.md、README.md、USER_MANUAL.md）を下書きのリリースに登録します。テストはWindows x86_64、Linux x86_64・arm64、macOS arm64の実機で実行します。CIのWindows版は署名なしなので、公開前に、次のスクリプトで作った同じ名前・同じ中身の署名付きZIP（`dist\zip\sigma-版番号-windows-x86_64.zip`）に差し替えます。

    .\scripts\build-zip.ps1 -Sign

引数なしで起動すると、版番号とライセンスの2行（`FORTH/Sigma 0.1.0  MIT License`、`` Type `help' for basic help ``）を表示して対話プロンプトになります。`HELP` で基本的な使い方、`HELP DUP` のように語名を付けるとその語の説明、`LICENSE` でライセンスの全文を表示します。

例:

    : SQUARE DUP * ;
    12 SQUARE .

Forthソースファイルは標準入力から読み込めます。例:

    sigma.exe < examples/demo.fs

この移植版の `SAVE filename`／`LOAD filename` は利用者定義語を辞書イメージとして保存・追加読み込みします。同名語は新しい定義が優先され、`FORGET` で新しい方を削除すると古い定義に戻ります。誌面の `LOAD`／`SAVE` はエディットバッファ操作であり、その機能は実装していません。登録語を含む単独実行ファイルは `SAVESYS` で作成します。

    SAVE words.sigma
    SAVESYS demo.exe

保存した実行ファイルは、引数なしなら登録語を持つ対話プロンプトを開きます。引数があれば、引数列をForth入力として一度実行して終了します。サンプルは `12` の平方である `144` を表示します。

## Gforth・標準Forthとの関係

2026-10-28から、数値まわりと基本ワードを[Gforth](https://github.com/forthy42/gforth)の挙動に合わせ、教材ForthBasicMasterのサンプルが動くことを目標にしています。作業は6段階に分けており、段階1（64ビットセル、真=-1、床関数除算、全文字の名前照合、`TYPE ( addr u )`、基本標準ワード）、段階2（浮動小数点）、段階3（`S"` などの文字列、倍長整数、`<# #>` による数値書式）と、教材で使う小規模なワード（`WITHIN`、`:NONAME`、`STATE`、`MS`、`GETENV`、`SYSTEM` など）、`THROW`／`CATCH` と主なファイル操作（`OPEN-FILE`、`READ-LINE`、`WRITE-LINE` など）、`ALLOCATE` と動的文字列（`$!`、`$[]!` など）、ローカル変数（`{ a b -- c }`、`F:` などの型指定、`LOCALS|`）、ソースファイルの読み込み（`INCLUDE`、`REQUIRE` など）、`SEE`・`LOCATE`・`MARKER`、語彙（`VOCABULARY`、`ONLY`、`ALSO` など）と `[IF]` を実装済みで、6段階はすべて終わりました（[決定事項・保留事項](forth/sigma/DECISIONS.md)）。

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

上記の誌面ページ情報は[FORTH/Σ仕様書](forth/sigma/SPEC.md)に記録しています。誌面のZ80ソースは処理内容を調べるために参照したもので、移植版はZ80機械語や誌面のソースコードを収録・実行していません。

### 比較・照合に使った資料

- [Gforth](https://github.com/forthy42/gforth)のソースコードと[マニュアル](https://gforth.org/manual/)を、名前照合など資料で確定しない実装上の挙動を検討する際の比較資料として参照しています。FORTH/Σの仕様根拠ではありません。
- ForthBasicMasterの教材を、Forthの用語や利用例を確認するための参考資料として参照しています。FORTH/Σの仕様根拠ではありません。
- Forth 2012との違いは、[Forth 2012 Standard](https://forth-standard.org/standard/index)の該当する定義と比較しています。

### 資料とライセンスの範囲

MITライセンスは、このプロジェクトで作成したプログラムコードとドキュメントを対象とします。雑誌記事、その他の第三者資料はMITライセンスの対象ではありません。第三者資料はリポジトリに含めていません。出典を示すことは、第三者資料の複製・再配布許諾を意味しません。

## ライセンス

プロジェクトで作成したコードとドキュメントは[MIT License](LICENSE)で提供します。浮動小数点の数学関数（`FSIN` `FCOS` `FTAN` `FEXP` `FLN`）は、CORE-MATHのコード（MIT License、`src/core-math/`）を使います。著作権表示は[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)にあります。第三者資料の扱いは上記「資料とライセンスの範囲」を参照してください。

# Gforth未対応ワードの実装フェーズ

Forth 2012の標準語を先に対応し、A〜Cの380語を、基本語、数値、メモリー、文字列、ファイル、入出力、コンパイラー、辞書、診断の順に関連付けて実装する計画。最初に仕様を確定し、最後に保存形式と3 OSの統合動作を確認する。依存関係はSigma向けの設計案であり、重要度とは別に管理する。

## 対象と重要度

比較基準はSigma `f1140c76814fb31b71c91743ca6cb7d99ad05054`と、指定されたGforthソース `/Users/fuk/source/forth/gforth/` の `c479e1eec66dd57a2441c3020177267ba70d3bdc`（実行版 `0.7.9_20260610 arm64`）。Gforthの `doc/gforth.texi.in`、`doc/2012-words`、辞書検索、および個別ソースを参照した。Sigmaは標準辞書に加えGRAPHICS・GUI・GAME・AUDIOと、辞書に登録されない専用構文を比較に含めた。

|重要度|意味|マニュアル掲載の未対応語|追加確認分|今回の対象|
|---|---|---:|---:|---:|
|A|Forth 2012の標準語と基本語を優先|39|0|39|
|B|汎用データ処理と入出力を推奨|181|1|182|
|C|開発支援と便利な構文を用途に応じて追加|157|2|159|
|D|要求が出るまで保留 または対応方針を別途検討|424|0|0|
|E|現在のSigmaでは対応不要|127|0|0|

追加確認分はBの`$VALUE`、Cの`MACRO:`と`[[`。マニュアル掲載分928語と合わせた931語の分類を[ワード別一覧](gforth-word-plan.tsv)に保存した。対象380語には全てフェーズと作業単位を割り当ててある。D/Eのフェーズ欄は空欄。`inventory`列は`manual`が928語の集計、`supplement`が追加3語を表す。

この380語に加え、既存構文の`IS`・`ACTION-OF`・`TO`・`+TO`をP07の先行作業で辞書化する（tque 457）。既存構文4語は未対応名の集計には加算しない。Forth 2012に定義された前3語はA、Gforth拡張の`+TO`は共通処理を整えるB相当として扱う。

この一覧は名前の不足を起点にしており、同名語の完全な意味互換を示さない。例えば`LOAD`はSigmaでは辞書イメージ読込、標準ではブロック読込である。`EKEY`は現在`KEY`と同じで、GRAPHICSのキー定数が存在しても特殊キー入力との互換は未完了である（[互換性一覧](COMPATIBILITY.ja.md#未実装機種依存)）。環境問い合わせのキー21件はワード数に含めない。

## 標準語を優先する方針

2026-11-12の利用者の指示により、EKEY>FKEYと修飾マスク3語をBからA、標準ブロック10語をDからAへ引き上げる。S01は既存の入力・ファイル・ヒープ基盤を利用し、P02以降のGforth拡張を待たない設計案とする。

アセンブラー関連8語（CODE、;CODE、ASSEMBLER、END-CODE、ABI-CODE、;ABI-CODE、FLUSH-ICACHE、INIT-ASM）は別途対応方針を検討し、今回の実装対象から外す。標準一覧にあるEDITORはGforthの既定辞書にないため、従来どおり本ワード比較の対象外とする。標準への完全準拠を宣言する計画ではない。

ワード別一覧のstandard_setとforth2012_section列に、比較元doc/2012-wordsの語群と節番号を記録する。標準に定義された語でも、今回除外したアセンブラーの3語には実装フェーズを割り当てない。

## 依存関係の根拠

|関連する機能|Gforth側の根拠|Sigmaでの実装順序案|
|---|---|---|
|標準キーと標準ブロック|`doc/2012-words`のFACILITY EXT・BLOCK・BLOCK EXTとマニュアルのSingle-key input・Blocks節|既存基盤へ接続するS01を、Gforth拡張のP01より先に置く。|
|メモリー配置とデータ構築|`stuff.fs`の整列・`SAVE-MEM-DICT`、`kernel/prim.fs`のアクセス語|既存の論理メモリーに幅と整列を追加し、辞書・構造体・バッファーの共通規則にする。P03→P04/P05/P08。|
|文字列値と置換|`substitute.fs`の`$VALUE`定義と`MACRO:`の別名、`kernel/stringk.fs`の動的文字列|既存の`$!`等を使う所有権と定義の寿命を確定してから、値・置換へ広げる。P03→P04。|
|出力取り込みとリダイレクト|`str-exec.fs`の`>STRING-EXECUTE`、`stuff.fs`の`INFILE-EXECUTE/OUTFILE-EXECUTE`|出力先の保存・切替・復元を共有する。文字列確保とファイル識別子が揃ってからP06へ進む。|
|CSVとファイル入力|`csv.fs`の`READ-CSV`と文字列処理|文字列とファイルの規則を確認した後に、コールバックを含むCSV読込を追加する。P04/P05→P06。|
|コンパイルトークンと無名定義とマクロ|`doc/gforth.texi.in`のCompilation token・Quotations・Macros節、`comp-i.fs`等|解釈とコンパイルの動作を揃え、`[: ;]`と`]] [[`へ進む。P07a→P07b。|
|名前と語彙と開発支援|`kernel/int.fs`の`NAME>LINK`、`kernel/tools.fs`の語彙走査、`except.fs`の位置表示|Sigmaの名前トークンと語彙を共通基盤にし、使用箇所・ソース移動・辞書表示へ接続する。P08→P09。|
|例外とバックトレース|`except.fs`の`CATCH-NOBT`と`NOTHROW`|既存のCATCHとバックトレース状態に接続する。DのTRY構文を追加する依存にはしない。|
|リターンスタックと浮動小数点|`stuff.fs`の`RPICK`、`locals.fs`の`F>R`|Sigmaのスタック表現・ループ・CATCHとの共存を確認し、P09で追加する。Dのスタックポインター語は前提にしない。|

Gforth側が内部語・TRY・USER等を用いている場合でも、その呼出し列をSigmaの依存関係として採用しない。公開動作を既存のSigma基盤へ対応させる設計とする。GforthのGPLソースは動作確認の参照に使い、実装コードの転用はライセンスを確認する。

## フェーズと着手条件

Forth 2012の標準語は、P00で仕様を確定後、S01で先に対応する。S01完了後にGforth拡張のP01以降へ進む。フェーズ番号は整理と推奨着手順を表す。P01完了後のP02・P03・P07は相互の完了を待たず進められる。表の依存は統合確認を含めた着手条件であり、Gforthの全ワードがこの順で定義されるという意味ではない。

|フェーズ|内容|対象語数|先行フェーズ|tque ID|
|---|---|---:|---|---|
|P00|仕様と比較基準の確定|0|なし|543|
|S01|Forth 2012の標準語を優先対応|14|P00|579|
|P01|基本語 A の補完|25|S01|544|
|P02|数値演算と数値入出力|65|P01|545|
|P03|メモリーとデータ配置|65|P01|546|
|P04|文字列と置換マクロ|33|P03|547|
|P05|ファイルとディレクトリ|30|P03|548|
|P06|入出力の切り替えとホスト連携|29|P04, P05|549|
|P07|コンパイラーと制御構文 既存4語の辞書化を含む|40＋既存4語|P01|550|
|P08|辞書と定義機能|29|P03, P07|551|
|P09|診断と開発支援|50|P02, P05, P06, P08|552|
|P10|統合と互換性の確認|0|S01, P02, P03, P04, P05, P06, P07, P08, P09|553|

## フェーズ別の作業と完了条件

### P00 仕様と比較基準の確定

2026-11-12 完了。対象384語の470ケースを比較用Gforthで実測し、Claude Codeの再レビューと文書指摘への対応を完了した。tque 543も完了。実装は次のS01から行う。

[仕様調査と決定事項](GFORTH_P00_SPEC.md)に記録する。LOADの改名、旧イメージ互換不要、GRAPHICSの定数維持と標準EKEY用語彙の分離は利用者が確定済み。

各語のスタック効果、語彙、所有権、例外、保存時の扱いを確認し、未確定の仕様を実装前に解消する。

対象380語それぞれのスタック効果、語彙、例外、所有権、コンパイル時の動作をGforthの資料・実行結果で確認する。個別仕様で決められない事項は実装前に利用者へ問い合わせ、推測で互換動作を定義しない。

特に次を確定する。

- LOADの名前は利用者の選択により確定。辞書イメージ読込をLOAD-DICTIONARYへ変更し、LOADはForth 2012のブロック実行とする。既存サンプル・HELP・マニュアルの辞書読込表記も変更対象に含める。LISTは現在の実装に登録されていないため、標準のブロック表示として追加する。
- `A,`・`ACONSTANT`・`AVARIABLE`・`AVALUE`等のアドレスと、SAVE/LOADによる再配置。
- EKEYのイベント表現と修飾マスク、GRAPHICSの同名定数との関係。
- `F*+`の丸め、幅別アクセス、文字列比較、乱数列の互換範囲。
- `CONTEXT/CURRENT`等の更新可能性、名前トークンの寿命、コンパイル専用語の解釈時エラー。
- 457の辞書化で生じる組み込み辞書境界の変更と、保存形式の改訂・旧イメージ読込の方針。他の語の追加による保存互換への影響もまとめて確認する。
- パイプ・時刻・ディレクトリ・編集コマンドのOS別差異と失敗時の動作。
- 例外・入力・出力先を一時変更する語の入れ子、QUIT/BYE、失敗時の復元範囲。

完了条件は、各作業単位の仕様と比較ケースが記録され、実装を妨げる未確定事項が解消されていること。対象外となる語が判明した場合は、理由と重要度・タスクの変更を記録する。

### S01 Forth 2012の標準語を優先対応

2026-11-13 実装とmacOS検証完了（tque 579/580/581、S01b子608/609/610完了）。利用者の指示によりWindows/Linux実機確認はP10配下607へ分離し、ここでは行わない。終了時保存を含む実ファイル検証は`python3 scripts/verify-blocks.py zig-out/bin/sigma`、キー入力は`python3 scripts/verify-ekey.py zig-out/bin/sigma`で再実行できる。辞書読込の現在名はLOAD-DICTIONARY、標準LOADはブロック実行である。P01は着手可能。

FACILITY EXTのキー4語とBLOCK/BLOCK EXTの10語を優先する。既存の入力・ファイル・ヒープ基盤を利用し、Gforth拡張の追加を待たずに進める。

#### S01a 標準の特殊キーと修飾マスク

対象 4語。tque ID: 580。

`EKEY>FKEY`, `K-ALT-MASK`, `K-CTRL-MASK`, `K-SHIFT-MASK`

完了条件: EKEY/EKEY>CHAR/EKEY>FKEYの連携、修飾マスク、GRAPHICSの同名キー定数、WindowsとPOSIXの入力、KEY/ACCEPT/行編集との共存を確認する。

#### S01b 標準のブロック操作

対象 10語。tque ID: 581。

`BLK`, `BLOCK`, `BUFFER`, `EMPTY-BUFFERS`, `FLUSH`, `LIST`, `SAVE-BUFFERS`, `SCR`, `THRU`, `UPDATE`

完了条件: ブロック番号、バッファーの再利用、UPDATEと保存、FLUSH/EMPTY-BUFFERS、BLK/SCR、LIST/THRU、I/O失敗を確認する。標準LOADおよび既存LOAD/LISTの意味・名前の衝突はP00で利用者と仕様を確定してから実装する。

### P01 基本語 A の補完

2026-11-13 完了（tque 544、子554/555/556）。P01a〜cの25語を実装し、現ビルドで比較スクリプト3本を通して計9,790ケースのGforth一致を確認した。Claude Codeレビューの文書3件・要確認1件に対応し、再レビューで新たな具体的問題なし。[レビュー記録](P01_REVIEW.md)に実測と対応を保存した。Windows/Linux実機確認はここでは行わない。

25語を先に揃え、以後の数値処理・メモリー処理の土台にする。

#### P01a 比較と最小最大

2026-11-13 完了（tque 554）。16語を実装し、既存33ケースと境界・コンパイル済み1,144ケース、合計1,177ケースでSigmaと指定Gforthが一致した。通常構成と全機能群無効構成のテスト、スタック不足、イメージ復元・追加後の実行を確認。再実行は`python3 scripts/verify-p01a.py zig-out/bin/sigma --gforth-build .work/gforth-audit/gforth-build`（比較用Gforthがある場合）。Gforthを指定しない場合はSigmaの期待値検査のみ行う。

対象 16語。tque ID: 554。

`0<=`, `D0<=`, `D0<>`, `D0>`, `D0>=`, `D<=`, `D<>`, `D>`, `D>=`, `DU<=`, `DU>`, `DU>=`, `U<=`, `U>=`, `UMAX`, `UMIN`

完了条件: 符号あり・なし、倍長、最小値・最大値、真=-1を比較する。

#### P01b 基本スタック操作

2026-11-13 完了（tque 555）。6語を実装し、既存6ケースと境界・コンパイル・リターンスタック4,054ケース、合計4,060ケースでSigmaと指定Gforthが一致した。通常・全機能群無効構成、スタック不足／容量境界、入れ子DOループ、CATCH/THROW・ローカル変数、イメージ復元・追加後の実行を確認。再実行は`python3 scripts/verify-p01b.py zig-out/bin/sigma --gforth-build .work/gforth-audit/gforth-build`。Gforth未指定時はSigmaの期待値検査のみ。

対象 6語。tque ID: 555。

`2NIP`, `2RDROP`, `2TUCK`, `FOURTH`, `RDROP`, `THIRD`

完了条件: スタックの順序、不足時の挙動、リターンスタックとループの共存を確認する。

#### P01c 倍長データの格納と回転

2026-11-13 完了（tque 556）。3語を実装し、既存5ケースと境界・コンパイル・格納順序4,548ケース、合計4,553ケースで指定64ビットGforthと一致した。2,は2!と同じ上位セル先の格納で、自動整列なし。容量不足では部分書込を行わない。ROL/RORは回転数をmod 64として扱う。通常・全機能群無効構成、イメージ復元・追加、生セル非再配置を確認。`python3 scripts/verify-p01c.py zig-out/bin/sigma --gforth-build .work/gforth-audit/gforth-build`で再実行できる。

対象 3語。tque ID: 556。

`2,`, `ROL`, `ROR`

完了条件: 2,のセル順序と辞書容量、ROL/RORの回転数境界を確認する。

### P02 数値演算と数値入出力

2026-11-13：P02a/b/cの65語を実装。[実装・検証記録](P02_IMPLEMENTATION.md)に境界仕様と指定Gforthとの差を記録。Windows/Linuxの確認はここでは行わず、別環境へ引き継ぐ。

整数・ビット・浮動小数点の境界条件を演算群ごとに統一する。

#### P02a 整数除算とビット演算

対象 32語。tque ID: 557。

`*/F`, `*/MODF`, `*/MODS`, `*/S`, `/F`, `/MODF`, `/MODS`, `/S`, `>POW2`, `ARSHIFT`, `CTZ`, `DARSHIFT`, `DLSHIFT`, `DROL`, `DROR`, `DRSHIFT`, `DU/MOD`, `LOG2`, `LROL`, `LROR`, `MODF`, `MODS`, `MUX`, `POW2?`, `U*/`, `U*/MOD`, `U/`, `U/MOD`, `UD/MOD`, `UMOD`, `WROL`, `WROR`

完了条件: 床関数・切り捨て除算、負数、0除算、桁あふれ、シフトと回転の境界を比較する。

#### P02b 浮動小数点演算

対象 16語。tque ID: 558。

`-INF`, `-INFINITY`, `1/F`, `F*+`, `F2*`, `F2/`, `FAXPY`, `FCOPYSIGN`, `FFOURTH`, `FTHIRD`, `F~ABS`, `F~REL`, `INF`, `INFINITY`, `NAN`, `V*`

完了条件: NaN・無限大・符号付き0、F*+の丸め、配列演算の要素数とストライドを確認する。

#### P02c 数値の変換と表示と乱数

対象 17語。tque ID: 559。

`>FLOAT1`, `BASE-EXECUTE`, `CONVERT`, `DEC.`, `DEC.R`, `DPL`, `E.`, `E.EXACT`, `E.P`, `FP.`, `H.`, `HEX.`, `RANDOM`, `RND`, `SEED!`, `UD.`, `UD.R`

完了条件: 入力消費位置、桁数、基数の復元、乱数の範囲・同一種での再現性を確認する。乱数列そのものの互換範囲はP00で決める。

### P03 メモリーとデータ配置

論理アドレス、幅、整列、確保と解放を共通化する。

#### P03a 幅と整列と特殊メモリーアクセス

対象 44語。tque ID: 560。2026-11-13に実装、[実装・検証記録](P03_IMPLEMENTATION.md)。P03bの型付き永続化とP03cの6語も実装済み。

`!@`, `*ALIGN`, `*ALIGNED`, `+!@`, `/L`, `/W`, `/X`, `C>S`, `CELL/`, `CHAR-`, `DFLOAT/`, `FLOAT`, `FLOAT/`, `L!`, `L>S`, `L@`, `LALIGN`, `LALIGNED`, `LBE`, `LLE`, `MAXALIGNED`, `SFLOAT/`, `TH`, `TH!`, `TH@`, `W!`, `W>S`, `W@`, `WALIGN`, `WALIGNED`, `WBE`, `WLE`, `X!`, `X>S`, `X@`, `XALIGN`, `XALIGNED`, `XBE`, `XD!`, `XD>S`, `XD@`, `XDBE`, `XDLE`, `XLE`

完了条件: W/L/X/XDの幅、符号拡張、エンディアン、未整列・範囲外アクセスを確認する。!@/+!@を並行処理用の原子操作と混同しない。

#### P03b 辞書データと構造体

対象15語。tque ID: 561。データ配置12語（615）・型付きアドレス3語と寿命追跡（616）・新形式SIGIMG45/46/47の保存/復元/追加（617〜630）を実装・検証済み。P03bは完了。旧形式は拒否し、生セルからアドレスを推測しない。[記録](P03_IMPLEMENTATION.md)。

`->HERE`, `2FIELD:`, `A,`, `ACONSTANT`, `AVARIABLE`, `L,`, `LFIELD:`, `MAXALIGN`, `MEM,`, `SAVE-MEM-DICT`, `W,`, `WFIELD:`, `X,`, `XD,`, `XFIELD:`

完了条件: データ配置、整列、アドレスの再配置、FORGET/MARKER、SAVE/LOADへの影響を確認する。

#### P03c ヒープと伸長バッファー

対象6語。tque ID: 562。実装済み。指定Gforthとの60ケース比較、通常/全機能群無効テスト、所有権・失敗保持・移動/縮小・型/保存復元の6回帰が成功。[記録](P03_IMPLEMENTATION.md)。

`ADJUST-BUFFER`, `BUFFER%`, `EXTEND-MEM`, `FREE-MEM-VAR`, `INIT-BUFFER`, `SAVE-MEM`

完了条件: 所有権、再確保失敗、解放後の状態、バッファー増大時の内容保持を確認する。

### P04 文字列と置換マクロ

動的文字列の所有権を揃えてから、文字列値と置換を追加する。

#### P04a 文字列操作とUnicode

対象28語。tque ID: 563。基本/借用文字列21語（632）は実装・323ケース比較と回帰済み。633の7語も実装し、編集48ケース・XC@+?非空301ケースとSigma空入力3ケースが成功。563/547は完了。[記録](P04_IMPLEMENTATION.md)。

`#BELL`, `#BS`, `#CR`, `#DEL`, `#EOF`, `#ESC`, `#FF`, `#LF`, `#TAB`, `APPEND`, `CAPSCOMPARE`, `CAPSSEARCH`, `CAPSSTRING-PREFIX?`, `CSTRING>SSTRING`, `DELETE`, `INSERT`, `INVALID-CHAR`, `NEWLINE`, `NOSPLIT?`, `S+`, `SAFE/STRING`, `SCAN-BACK`, `STR<`, `STRING,`, `STRING-SUFFIX?`, `TOUPPER`, `TYPEWHITE`, `XC@+?`

完了条件: 空文字列、重なる領域、容量、ASCII比較とUnicode変換の違い、壊れたUTF-8を確認する。>STRING-EXECUTEはP06へ分ける。

#### P04b 文字列値と置換

対象5語。tque ID: 564。単位内の先行作業: P04a（完了）。$VALUE/MACRO:（634）は27ケース比較・9回帰、マクロ語彙/置換3語（635）は50ケース比較・12回帰と保存/追加読込を確認。564/547は完了（auto）。635は6a9c4e3でpush済み。P04レビュー636も完了、指摘修正と9回帰を確認。[記録](P04_IMPLEMENTATION.md)。

`$VALUE`, `.SUBSTITUTE`, `MACRO:`, `MACROS-WORDLIST`, `REPLACER:`

完了条件: $VALUEのTO/+TOと寿命、MACRO:の別名、既存REPLACES/SUBSTITUTEとの関係、語彙と保存を確認する。

### P05 ファイルとディレクトリ

ファイル識別子とエラー処理を揃え、パス検索・ディレクトリ操作へ広げる。

#### P05a ファイル補助とパス検索

対象 16語。tque ID: 565。

`+FMODE`, `.INCLUDED`, `.PATH`, `ABSOLUTE-FILE?`, `ALSO-PATH`, `CLEAR-PATH`, `EMIT-FILE`, `FILE-EOF?`, `FILE>PATH`, `KEY-FILE`, `KEY?-FILE`, `OPEN-PATH-FILE`, `PATH+`, `PATH=`, `SLURP-FID`, `\\\`

完了条件: EOF、文字入力、全読込、相対パス、日本語ファイル名、検索順と読込済み一覧を確認する。

#### P05b ディレクトリと時刻

対象 14語。tque ID: 566。

`=MKDIR`, `>TIME&DATE&TZ`, `BASENAME`, `CLOSE-DIR`, `CPUTIME`, `DIRNAME`, `FILENAME-MATCH`, `GET-DIR`, `MKDIR-PARENTS`, `NS`, `NTIME`, `OPEN-DIR`, `READ-DIR`, `SET-DIR`

完了条件: 列挙の終端・ハンドル解放、既存ディレクトリ、作業ディレクトリ、時刻の単位と計測対象をOSごとに確認する。

### P06 入出力の切り替えとホスト連携

入力・出力先の入れ子と例外後の復元を共通化し、CSV、パイプ、特殊キーへ広げる。

#### P06a 入出力切り替えと出力の取り込み

対象 5語。tque ID: 567。

`>STRING-EXECUTE`, `INFILE-EXECUTE`, `INFILE-ID`, `OUTFILE-EXECUTE`, `OUTFILE-ID`

完了条件: 通常終了・THROW・入れ子実行で元の入力/出力先へ戻す。>STRING-EXECUTEの返却領域を呼出側でFREEできることを確認する。

#### P06b パイプとシェルとCSV

対象 9語。tque ID: 568。単位内の先行作業: P06a。

`.QUOTED-CSV`, `BROKEN-PIPE-ERROR`, `CLOSE-PIPE`, `CSV-QUOTE`, `CSV-SEPARATOR`, `OPEN-PIPE`, `READ-CSV`, `SH`, `SH-GET`

完了条件: 子プロセスの終了値、パイプ解放、閉じた出力先、SH-GETの返却領域、CSVの引用・改行・コールバックを確認する。

#### P06c 特殊キーと端末情報

対象 15語。tque ID: 569。

`AT-DELTAXY`, `FKEY.`, `FORM`, `K-BACKSPACE`, `K-ENTER`, `K-EOF`, `K-MUTE`, `K-PAUSE`, `K-SEL`, `K-TAB`, `K-VOLDOWN`, `K-VOLUP`, `K-WINCH`, `KEY-IOR`, `SIMPLE-FKEY-STRING`

完了条件: EKEYの符号化と修飾キー、GRAPHICSのK-*定数との関係、KEY/ACCEPT/行編集との共存、リダイレクト入力を確認する。

### P07 コンパイラーと制御構文

コンパイルトークン、無名定義、後回しコンパイル、ループを整える。

#### P07先行 既存構文4語の辞書化

対象は`IS`・`ACTION-OF`・`TO`・`+TO`。tque ID: 457。先行フェーズはP01。P07aはこの作業の完了後に進める。

現在のSigmaでは通常の代入と`ACTION-OF`は動くが、4語は辞書に登録されていない。Gforthとの実行比較では、`' IS`、`POSTPONE TO`、`POSTPONE IS`、`POSTPONE ACTION-OF`、`POSTPONE +TO`がGforthで成功し、Sigmaでは未定義語となった。

Gforthの`kernel/comp.fs`では`TO`・`IS`・`+TO`が解釈動作とコンパイル動作を分けて定義されている。次の例はGforthで`2 0`を表示し、コンパイル中でも`' TO`から取得した解釈動作がその場で値を更新することを確認できる。

```forth
1 VALUE V
' TO CONSTANT T
: M 2 T EXECUTE ; IMMEDIATE
: S M V ;
V . DEPTH .
```

設計案は、通常の名前解釈、`'`・`[']`・`NAME>INTERPRET`、`POSTPONE`・`NAME>COMPILE`が使う動作選択を共通化し、解釈とコンパイルを区別すること。既存の値代入・ローカル変数・DEFER処理を再利用する。即時語の登録とSTATEによる分岐だけで対応済みとしない。

辞書化では組み込み辞書の境界が変わる。現在のイメージ読込は組み込み語の位置と種類を照合するため、既存語の番号を維持する配置案だけでは旧イメージの互換を保証できない。保存形式の改訂と旧形式の扱いはP00で確定し、P10でも確認する。

完了条件は、通常の名前入力、辞書検索、`EXECUTE`、`POSTPONE`、解釈・コンパイルトークン、`SYNONYM`、再定義、検索順序が一貫すること。VALUE/FVALUE/2VALUE、DEFER、型付きローカル変数、不正な代入先、入力終端、例外、WATCH・使用箇所記録への影響を確認する。SAVE/LOAD/SAVESYSと機能を除いたビルドも検証する。P08の辞書・遅延語の拡張は、この動作選択を使う。

#### P07a コンパイルトークンと実行

対象 8語。tque ID: 570。単位内の先行作業: 457の辞書化。

`COMP'`, `COMPILE-ONLY`, `EXECUTE-EXIT`, `POSTPONE,`, `RESTRICT`, `SELECT`, `[COMP']`, `[NOOP]`

完了条件: 解釈・コンパイル・即時実行の違いとCOMPILE-ONLYの制約を確認する。

#### P07b 無名定義とマクロ

対象 6語。tque ID: 571。単位内の先行作業: P07a。

`;]`, `IN-COLON-DEF?`, `NONAME`, `[:`, `[[`, `]]`

完了条件: [: ;]の入れ子と実行トークン、]] [[の切替とリテラル、壊れた定義の巻戻しを確認する。捕捉付きクロージャーはDのままとする。

#### P07c ループと制御スタック

対象 18語。tque ID: 572。単位内の先行作業: P07a。

`+DO`, `-DO`, `-LOOP`, `-[DO`, `?DUP-0=-IF`, `?DUP-IF`, `ARRAY>MEM`, `CS-DROP`, `DELTA-I`, `DONE`, `FOR`, `I'`, `MEM+DO`, `MEM-DO`, `NEXT`, `U+DO`, `U-DO`, `U-[DO`

完了条件: 符号あり・なしの境界、0回実行、入れ子、LEAVE/EXIT、I/I'、制御スタックの不整合を確認する。

#### P07d 入力の一時切り替えと前方参照

対象 8語。tque ID: 573。単位内の先行作業: P07a。

`.UNRESOLVED`, `EXECUTE-PARSING`, `EXECUTE-PARSING-FILE`, `FORWARD`, `NAME`, `PARSE-WORD`, `RECURSIVE`, `STRING-PARSE`

完了条件: 一時入力の復元、>INとソース位置、未解決参照とRECURSIVE、例外時の状態を確認する。

### P08 辞書と定義機能

名前トークンと語彙を基盤に、定義名の指定、アドレス可能な値、遅延語を追加する。

#### P08a 名前トークンと語彙

対象 23語。tque ID: 574。

`.ID`, `.VOC`, `COMPILE-ONLY?`, `CONTEXT`, `CS-VOCABULARY`, `CS-WORDLIST`, `CURRENT`, `FIND-NAME-IN`, `IN`, `IN-WORDLIST`, `LATESTNT`, `MAP-VOCS`, `MWORDS`, `NAME>LINK`, `NEXTNAME`, `OBSOLETE?`, `ROOT`, `SEAL`, `TABLE`, `VLIST`, `VOCS`, `WORDLIST-WORDS`, `XT>NAME`

完了条件: 名前から実行/コンパイル動作への変換、検索順、名前のリンク、再定義とFORGET後の無効化を確認する。

#### P08b アドレス可能な値と遅延語

対象 6語。tque ID: 575。単位内の先行作業: P08a。

`:IS`, `ADDR`, `ADDRESSABLE:`, `AVALUE`, `PRESERVE`, `WRAP-XT`

完了条件: 値のアドレスとTO、遅延語の一時変更と復元、ラッパーの寿命、辞書保存と再配置を確認する。

### P09 診断と開発支援

例外診断、アサーション、位置情報の表示を既存デバッガーに接続する。

#### P09a 例外とアサーション

対象 15語。tque ID: 576。

`)`, `?ERRNO-THROW`, `?IOR`, `ASSERT-LEVEL`, `ASSERT0(`, `ASSERT1(`, `ASSERT2(`, `ASSERT3(`, `CATCH-NOBT`, `EXCEPTION`, `EXCEPTIONS`, `FAST-THROW`, `NOTHROW`, `WARNING"`, `WARNINGS`

完了条件: CATCH-NOBT/NOTHROWのバックトレース状態、FAST-THROWの伝播、errnoからiorへの変換、アサーションの有効レベルを確認する。TRY系は含めない。

#### P09b スタックとソース位置の表示

対象 30語。tque ID: 577。

`...`, `AFTER-LOCATE`, `B`, `BEFORE-LOCATE`, `BROWSE`, `BT`, `BW`, `CLEARSTACK`, `CLEARSTACKS`, `EDIT`, `EXPAND-WHERE`, `F.S-PRECISION`, `FANCY-AFTER-L`, `FCLEARSTACK`, `G`, `GG`, `L`, `LL`, `MAXDEPTH-.S`, `N`, `NT`, `NW`, `PREPEND-WHERE`, `SHORT-WHERE`, `TT`, `UNUSED-WORDS`, `WHEREG`, `WW`, `XT-LOCATE`, `\G`

完了条件: 表示・ソース移動・使用箇所・バックトレースの対応、デバッグ機能を除いた版、編集コマンド未設定時の動作を確認する。

#### P09c 追加のリターンスタック操作

対象 5語。tque ID: 578。

`F>R`, `FR>`, `FR@`, `R'@`, `RPICK`

完了条件: RPICK/R'@とF>R/FR>/FR@をループ、CATCH、再帰、ローカル変数と組み合わせる。CPUのRP@等を公開せず内部表現に合わせる。

### P10 統合と互換性の確認

全対象の組合せ、保存・復元、機能を除いた版、Windows・Linux・macOSでの動作を確認する。

- 全380語が各作業単位で実装・比較済みであり、未確認条件が残る場合は完了扱いにしない。
- 既存構文4語の辞書化も完了し、P07のコンパイルトークン・マクロ、P08の辞書・定義機能との組合せを確認する。
- 数値→文字列→CSV→ファイル、マクロ→無名定義→語彙、入出力切替→THROW→復元を組み合わせて確認する。
- SAVE/LOAD/SAVESYS、FORGET/MARKER、再定義、容量不足、壊れた定義の巻戻しを確認する。
- 浮動小数点・デバッグ等を除いたビルドで、依存する語の登録と動作が整合することを確認する。
- Windows・Linux・macOSのテストと実端末の確認を分けて記録する。クロスビルド成功を実機確認と同一視しない。既存のWindows確認タスク537〜540と連携する。
- HELP、互換性一覧、ユーザーマニュアル、決定事項を更新する。版番号を変更する場合はversion-update-checklist.mdに従う。パッケージ作成は本計画の作業に含めない。

## 共通の検証条件

各実装単位でスタック効果・結果・エラーをGforthと比較し、Sigmaの論理アドレスやホスト機能に由来する差異は互換性一覧へ記録する。辞書への登録だけで対応済みにせず、通常・境界・失敗・復元のケースを確認する。既存テストと対象の回帰テストを実行し、実行したOSとビルド構成を残す。

## 保留と対象外

Dの424語とEの127語は今回の実装タスクへ含めない。TRY系、標準対象10語以外のブロック拡張、FFI、タスク、認識器、オブジェクト指向、捕捉付きクロージャーは保留する。アセンブラー関連8語はEからDへ移し、対応方針を別途検討する。Gforth固有のスレッディング・起動・イメージ処理、MINOS2固有API等はEとする。標準LOADと既存LOAD/LISTの意味・名前の調整はP00で仕様を確定する。今回の標準語優先への変更前の対象外・見送り方針は[互換性一覧](COMPATIBILITY.ja.md#未実装機種依存)を参照。

## tqueとの対応

ForthSigma 121 → 次のフェーズ 415 → 本計画 542 の階層に登録する。各フェーズを親タスク、S01およびP01〜P09の各作業単位を子タスクとし、フェーズ間と作業単位間の依存を登録する。開始日・期日は未指定のため設定しない。

標準語の優先対応は579、その子のキー関連は580、ブロック関連は581で管理する。アセンブラー対応方針の検討は、本計画542の外に置いた415配下の582で管理し、本計画の完了条件や依存先には含めない。

旧440の内容は次の作業へ移管し、440自体は削除した。実装対象は542配下、優先度Dの保留項目は415直下で管理する。完了済み417の状態は変更しない。

|旧440の内容|移管先|扱い|
|---|---|---|
|`$VALUE`などの文字列語|P04aの563、P04bの564|今回の実装対象|
|`]] [[`|P07bの571|457の辞書化とP07aの後に実装|
|`EKEY>FKEY`と修飾マスク|S01aの580|標準語としてAで優先対応|
|その他のキー語と端末情報|P06cの569|今回の実装対象|
|標準ブロック10語|S01bの581|標準語としてAで優先対応|
|`LOAD/LIST`の意味と名前の調整|P00の543、S01bの581|仕様確定後に実装|
|`TRY ENDTRY RESTORE IFERROR`と関連する`ENDTRY-IFERROR`|415配下の583|Dとして保留。今回の実装計画542の完了条件には含めない|
|`+LOAD +THRU --> BLOCK-INCLUDED BLOCK-OFFSET GET-BLOCK-FID OPEN-BLOCKS UPDATED? USE`|415配下の584|Dとして保留。標準ブロック581の完了後に必要性を再検討|

583・584は保留項目の追跡用であり、登録によって実装を開始する判断はしない。A〜Cの380語と既存構文4語の集計は維持する。

既存457は415の直下からP07の550配下へ移し、4語の辞書化を実装するタスクとして管理する。457はP01の544に依存し、P07aの570は457に依存する。P07b以降とP08は、この先行関係を通じて辞書化の完了を待つ。457を別タスクとして重複登録せず、未対応名380語の集計は維持する。

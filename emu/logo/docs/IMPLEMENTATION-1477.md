# Task 1477 実装・検査報告

検査日: 2026-11-28。既存の `zig-out/bin/sigma.exe` を使用した。
仕様書は編集していない。Git 操作と Sigma の再ビルドは行っていない。
画面を開く経路と音声は実行していない。

## 作成・変更したファイル

- 作成: `emu/logo/logo.fs`、`emu/logo/test-logo.fs`。
- 作成: `emu/logo/examples/` の `square.lg`、`spiral.lg`、`branches.lg`、
  `colours.lg`、`edges.lg`、`values.lg`。すべて本タスクで作成した例。
- 作成: `emu/logo/README.md`、`emu/logo/README.ja.md`、本報告。
- 変更: `emu/logo/turtle.fs` の `TT@RUN-BODY` から `DISPLAY-WINDOW` を除去。
  `SHOW` に表示先の選択を任せる。改行は LF にそろえた。
- `test-turtle.fs` は変更していない。
- 実験用ソース、ログ、PNG、保存実行体は `.work/1477/` に限定した。

## 最終検査

| 実行したファイル | 最終行 | Sigma の終了状態 |
| --- | --- | ---: |
| `emu/logo/test-turtle.fs` | `passed 3415 failed 0` | 0 |
| `emu/logo/test-logo.fs` | `passed 19365 failed 0` | 0 |

LOGO 検査は、全命令・別名、UTF-8/BOM/CRLF、空白と符号、優先順位、
固定入力、前方参照・相互再帰、局所・大域・未代入、値の有無、入れ子終了、
レキシカルな REPCOUNT、値 IFELSE、乱数の範囲と整数性を検査した。
自己末尾呼出しは、複数入力の入替え、引数なし、IF/IFELSE の末尾枝、
入れ子 REPEAT 内の OUTPUT、局所未代入フラグの初期化を含めて検査した。
自己末尾ループは5,000〜6,000回の例を通した。一般再帰の深さの保証ではない。

小画像は LOGO ソースから作り、全画素を手計算した配列と比較した。
9×9の白5点、正方形、WRAP/WINDOW/FENCE、百分率色、偶数寸法の半画素、
小半径の円弧、初期 ASCII フォントの A を含む。
`square.lg` は全81画素を比較した。6例すべてが LOGO-HEADLESS で正常終了した。

成功・失敗を120組繰り返し、各呼出しで検索順の全要素、定義先、16進 BASE、
HERE、データ・浮動小数点スタック深さ、所有ファイルとヒープ領域、
マーカーと生成手続きの回収を検査した。画像は成功時に残り、失敗・中止時に回収される。
通常呼出しの最終深さは双方0。使用可能な追加ファイル枠は63、画像枠は256で、
反復前後で変わらなかった。ファイル枠の測定中は検査スクリプト自身の入力が開いている。

診断出力をファイルに捕捉し、ファイル名・行番号・分類の接頭辞を照合した。
lexical、translation、runtime に加え、仮の immediate 描画別名で
EVALUATE のコンパイル失敗を起こし、forth-compile と定義範囲1〜3行を確認した。
無引数 LOGO-MAIN の usage、存在しない入力の `?: runtime` も照合した。
中止コード -4205 の正常復帰・無診断・画像回収は、仮の描画別名から送出して検査した。
実際のキーや窓操作による中止を検査した意味ではない。
後始末の最初のエラー保持と、元のエラーを優先する規則も検査した。

--emit-forth と同じ書出し処理で保存した Forth を、別の画像とマーカー環境で
再評価し、直接実行と同じ手計算の白5点・黒76点になることを確認した。
表示を伴う実コマンドラインの成功経路は実行していない。

## 7.4節の実際の生成結果

下記は実際の変換器が書き出した内容である。各行末には ASCII の空白が1個ある。
`test-logo.fs` はこの内容を固定文字列と厳密に比較する。

```forth
ONLY FORTH 
FORWARD LG@P0 
ALSO LOGO 
: LG@P0 { F: LG@A0 -- } 
2 LG@AT LG@POLL 2 LG@AT LG@POLL 4e 2 LG@AT LG@POLL LG@COUNT 0 ?DO LG@POLL 2 LG@AT LG@POLL 2 LG@AT LG@POLL LG@A0 2 LG@AT LG@POLL LG@FD 
2 LG@AT LG@POLL 90e 2 LG@AT LG@POLL LG@RT 
LOOP 
; 
:NONAME 
5 LG@AT LG@POLL 3e 5 LG@AT LG@POLL LG@P0 
; EXECUTE 
```

仕様書に印刷された Forth との差は次のとおり。

| 差分 | 理由・対応 |
| --- | --- |
| `ONLY FORTH` と `ALSO LOGO` の2行を追加 | 前方宣言の検索順切替えを出力ファイル自身に含め、再評価でも LOGO の FORWARD を呼ばないようにした。定義先は常駐側で LOGO に設定する |
| 同じ行番号の `LG@AT LG@POLL` を繰り返す | 手続き入口、命令入口、変数参照、失敗し得る命令の実行直前を個別に記録する。同行の重複除去はしていない |
| 整数定数 `4` の代わりに `4e ... LG@COUNT` | LOGO 数値は浮動小数点で生成し、回数の切捨て・上限検査を共通化する。定数畳込みはしていない |
| `?DO` の直後に `LG@POLL` を追加 | 描画を含まない反復でも毎回中断を確認する。描画命令との重複検査の省略はしていない |
| `3e` と `LG@P0` の間に行5の位置設定を追加 | 入力式から戻った後、呼出元の命令位置へ戻す共通処理を通している |
| 改行、インデント、`;` の独立行、末尾空白 | 生成器は命令ごとに改行し、トークンを空白で連結する。空白配置は例示に合わせていない |

`FORWARD LG@P0`、浮動小数点仮引数 `LG@A0`、`?DO ... LOOP`、
全手続き完成後の `:NONAME ... ; EXECUTE` は例示と同じ構造である。
この BOX は自己末尾呼出しを含まないため、BEGIN/AGAIN と更新用一時ローカルは生成しない。

## 仕様の不明確な点・残る制約と文案

### 2章: 同じファイルの判定（残件）

現行の実装は、同じ綴りと FILE>REALPATH が同じ正規化パスを返す別表記を拒否する。
`./` を含む別表記は実コマンドラインでも拒否した。
しかし、`.work/1477/` に同一ファイルの異なるハードリンク名を作った実験では、
LG@SAME-FILE? は偽を返した。現行の公開 API で確認した FILE-METADATA は
サイズと更新時刻だけを返し、ファイルIDは返さない。これらを同一性の根拠には使えない。
**したがって、2章の「同じファイル」をハードリンクまで含める要件は未達である。**
このケースの実コマンドライン実行は、画面を開く経路へ進むため行っていない。
ハードリンクの別名を出力先に指定しないこと。

現行の公開 API の範囲に限定するなら、文案は
「入力と出力の綴り、または FILE>REALPATH で得る正規化パスが同じなら、書込み前に
エラーとする。異なるハードリンク名の同一性判定は対象外とする」。
元の要件を維持する場合は、OS のファイルIDを比較する公開 API が別途必要となる。
仕様書はどちらにも変更していない。

### 5.1・3.3節: RGB リテラルの符号

5.1節では符号を単項演算とし、3.3節では色成分を数リテラルに限定しているため、
`[-1 0 0]` の分類が明示されていない。符号付きリテラルは受け付け、
範囲外を runtime の -4201 とした。一般の色成分式は受け付けない。
文案: 「各成分は任意の単項符号1個を持てる数リテラルとする。
成分式は許さず、符号適用後の値で0〜100の範囲を検査する」。

### 6章 RANDOM・6.2節 REPEAT・S21: 上限検査の順序

端数を含む上限付近の入力について、切捨て前か後かが明示されていない。
切捨て後の整数に2147483647の上限を適用した。
RANDOM 2147483647.9 の受入れと、REPEAT 2147483647.9 の最初の反復から
STOP する検査が通った。文案: 「有限性を検査し、指定した方向へ切り捨て、
REPEAT の負数を0とした後、整数の上限2147483647を検査する」。

### 7.4節: 正確な出力と検査の挿入

「次の正確な本体」と、8章の操作前の位置設定、9章の入口・命令・反復の中断検査を、
同じテキスト生成規則としては一意に読めない。上記の差分を明示した実装とした。
文案: 「次は同行の位置設定、定数回数の検査、重複する中断検査を省いた
代表的な本体である。省略しない出力では、同じ意味を持つ追加検査を生成してよい」。
仕様書の印刷内容とのバイト一致は達成していない。固定した実出力との一致は検査した。

## 実験で確認した Sigma の挙動

| 実験 | 観測したこと |
| --- | --- |
| turtle.fs の既存検査 | DISPLAY-WINDOW 除去後も3415件成功。窓なしで状態と画素を検査できる |
| 語彙と FORWARD | 通常読込みは同名警告を2回表示する。TURTLE/LOGO の FORWARD と、FORTH の前方宣言を検索順で分離できる |
| 検索順 | LG@ENV の GET-ORDER は3要素で、先頭から LOGO・FORTH・Root。ONLY 単独の実測では Root が2要素となり、.S は検索できなくなる。コンパイル済みの検査語なら結果を表示できた |
| 前方宣言・局所 | 後続の手続き定義で前方宣言が解決され、相互再帰と64個の浮動小数点引数を使える。更新用一時値は実際に最適化する手続きだけに確保する |
| CS-PICK と AGAIN | BEGIN の制御位置を複製し、IF/IFELSE・入れ子の REPEAT を閉じる構造を保ったまま自己末尾ループへ戻れる |
| UNLOOP / EXIT | 手続き自身の入れ子ループだけを解放して STOP・OUTPUT できる。呼出元の反復は継続する |
| CATCH と MARKER | 検査した変換・コンパイル・実行失敗後に環境・深さ・HEREが戻る。スタック内容全体の復元は仮定していない |
| EVALUATE | immediate 別名がコンパイル中に投げた -13 を捕捉でき、マーカーで未完成のプログラムも回収できた。エラーの正確な内部バイト位置は得たと主張せず、断片のソース範囲を表示する |
| S\" | 解釈時・コンパイル時とも255バイトは成功し、256・400バイトは OUT OF MEMORY。LABEL は生成した CREATE/C, のバイト領域を参照する方式にし、300バイトの引用語を実行できた |
| UTF-8 と画像 | BOM/CRLF、UTF-8 引用語、引用符・バックスラッシュ入りの LABEL を実行できた。不正UTF-8は変換器が検査する。日本語の字形の目視確認はしていない |
| MKDIR-PARENTS | 既存の最終ディレクトリに対して -529 FILE EXISTS。検査ハーネスではこの場合だけ既存ディレクトリとして扱う |
| ファイル・画像 | 反復前後で追加ファイル63枠・画像256枠が同じ。生成出力の読戻しと、Forth API による PNG 保存が成功した |
| パス | FILE>REALPATH を使うと ./ の別表記を拒否できた。異なるハードリンク名は一致しなかった |
| NEXT-ARG | 下表の不正コマンドラインを入口で消費し、LOGO ファイルが後続の Forth 入力として扱われずに終了した |
| SAVESYS / APP-ENTRY! | 完成した LOGO-MAIN を登録して .work/1477/LOGO.EXE を作成できた。無引数起動はプロンプトへ入らず usage と状態1で終了した |
| PowerShell の引用 | README の全体をシングルクォートで囲む -e、倍にした apostrophe による Forth の tick、窓なし実行、PNG 保存、保存実行体の作成が実際に通った。実験時の出力先は .work/1477/ に置き換えた |

### 実コマンドラインで早期終了を確認したケース

以下はすべて終了状態1。画面を開く前に停止した。

- `--unknown`
- `--emit-forth`（出力先・入力なし）
- `--emit-forth .work/1477/out.fs`（入力なし）
- `emu/logo/examples/square.lg extra`
- `--emit-forth emu/logo/examples/square.lg emu/logo/examples/square.lg`
- `--emit-forth emu/logo/examples/./square.lg emu/logo/examples/square.lg`
- `.work/1477/not-found.lg`
- `--emit-forth .work/1477/out.fs --emit-forth emu/logo/examples/square.lg`

保存前の Sigma と SAVESYS コマンドは状態0。
保存実行体の無引数起動は `<command-line>:?: usage: invalid command line (-4202 )`
と使用法を表示して状態1。

## 検証していないこと

- 実際の窓、表示バックエンド、Esc、閉じる操作、速度、DPI、リサイズ、画面保持。
- 表示を伴う source 起動・保存実行体の正常プログラム実行と、実CLIによる
  --emit-forth 成功経路。書出し処理と再評価は窓なしで別に検査した。
- 異なるハードリンク名の拒否。上述の判定補助語の実験では拒否できないと確認した。
- OS の権限・ディスク枯渇・画像作成失敗・FREE 失敗など、実際の資源障害すべて。
  後始末エラーの優先規則は制御した例外で検査した。
- 保存実行体での正常な描画、非既定の -m/-l、保存後の深い一般再帰。
- Linux/macOS 等の別ホストと、ファイルシステムが実行中に変化する場合。
- 日本語の字形、変更されたフォント、UCBLogo の実機結果、乱数系列の一致。
- 一般再帰の容量限界、性能目標、強制終了時の回収。

実験ログと実行体は `.work/1477/` の一時成果物である。

## Review fix round 1: newline-aware pre-pass lookahead

Per specification 5.1, each pre-pass now tracks parenthesis/bracket depth.
The shared lookahead skips newline tokens only at positive depth. Applied to
LOCAL declaration collection, MAKE/THING global collection, LABEL index
assignment, and LABEL CREATE byte-array emission. Audited the remaining raw
lookaheads: TO headers and END line-boundary checks retain their newline rules.
The specification is unchanged.

Regression tests cover both reported LABEL examples, distinct FIRST/SECOND
byte arrays and the LG@S1 6 reference, LOCAL/MAKE/THING in brackets, THING in
parentheses, consecutive newlines, and rejected newlines at top level, in
procedure bodies, and after closing delimiters. Parentheses accept expressions;
LOCAL/MAKE/LABEL commands remain rejected there. THING-only globals translate
successfully and then raise the expected unassigned-variable runtime error.

Executed from the repository root in PowerShell using the existing Sigma,
without rebuilding Sigma or opening a display. Actual final lines and exit status:

```text
.\zig-out\bin\sigma.exe emu/logo/test-logo.fs
passed 19809 failed 0
exit status 0

.\zig-out\bin\sigma.exe emu/logo/test-turtle.fs
passed 3415 failed 0
exit status 0
```

Logs: `.work/1477/review-round1-logo.log` and
`.work/1477/review-round1-turtle.log`.

## 仕様の不明確な点の解決（2026-11-28）

「仕様の不明確な点・残る制約と文案」の4件は、利用者の承認により文案どおり仕様書へ反映した。
2章はハードリンクの別名を判定の対象外とし、3.3節、6章、6.2節、7.4節は現行の実装の挙動を仕様とした。
コードの変更はない。

## Windows check fix (task 1478)

LG@BUILTIN retained interpretation-state S" scratch addresses. SAVESYS does
not preserve those bytes, so even FD failed builtin lookup after restart.
LG@RESIDENT now copies both the spelling and target bytes into the dictionary
using HERE/ALLOT/MOVE before LG@BUILTIN stores their addresses.

Audit of logo.fs and turtle.fs: the other interpretation-state strings are
immediately consumed by LG@CHECK-CONTROL. Compiled literals reside in definitions;
PAD and pictured numeric output are copied immediately by LG@APPEND. Source,
token, variable and fragment slices belong to one invocation and are released;
LG@RESET clears resource slots before use. TURTLE-INIT already clears the saved
image handle and running flag before allocating a new canvas. No further
load-time transient addresses or host resources requiring a fix were found.
This audit concerns startup of the saved application, not a snapshot taken
during an active translation or display loop.

test-logo.fs uses SYSTEM and $? to build test-savesys.fs in a separate Sigma,
then starts .work/1478/HEADLESS.EXE and checks its exit status and success marker.
The saved APP-ENTRY calls LOGO-HEADLESS on square.lg and checks all 81 canvas
pixels. All test-logo scratch paths now use .work/1478/ to respect this task's
write boundary. colours.lg sets its background before drawing; new headless
checks confirm that the black palette stroke and orange arc remain.

Final tests from the repository root in PowerShell (existing Sigma, no rebuild,
no display):

```text
.\zig-out\bin\sigma.exe emu/logo/test-turtle.fs
passed 3415 failed 0
exit status 0

.\zig-out\bin\sigma.exe emu/logo/test-logo.fs
passed 19814 failed 0
exit status 0
```

Manual saved executable checks:

```powershell
.\zig-out\bin\sigma.exe emu/logo/logo.fs -e 'ALSO LOGO '' LOGO-MAIN APP-ENTRY! PREVIOUS SAVESYS .work/1478/LOGO.EXE BYE'
```

Build exited 0 (two `WARNING: SAME NAME WORD EXISTS` lines).

```text
.\.work\1478\LOGO.EXE
<command-line>:?: usage: invalid command line (-4202 )
Usage: LOGO [--emit-forth output.fs] input.lg
ERROR #-4202 !
BACKTRACE:
  LG@USAGE
  LG@ARGS
  LOGO-MAIN
STACK: <0>
exit status 1

.\.work\1478\HEADLESS.EXE
SAVESYS square pixels OK
exit status 0
```

The ordinary LOGO-MAIN path calls SHOW before executing the program, including
FD 1 / 0. Therefore that runtime check would open a window; it has not been run
under the no-display constraint. spiral.lg was exercised headlessly in the
source test suite, but was not passed to the ordinary LOGO.EXE.

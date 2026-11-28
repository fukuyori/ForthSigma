# Sigma用CHIP-8

64x32のCHIP-8命令を実装した独自のインタープリターです。
CHIP-48とCOSMAC VIPの動作をプロファイルで選べます。
SUPER-CHIP、XO-CHIPには対応しません。

リポジトリのルートから、既存の実行ファイルで起動します。

```powershell
zig-out/bin/sigma.exe emu/chip8/chip8.fs emu/roms/c8games/PONG
zig-out/bin/sigma.exe emu/chip8/chip8.fs emu/roms/c8games/PONG vip
zig-out/bin/sigma.exe emu/chip8/test-chip8.fs
zig-out/bin/sigma.exe emu/chip8/chip8.fs -e 'S" emu/roms/c8games/MAZE" CH8-LOAD 300 CH8-TICKS CH8-DUMP BYE'
```

ROMの後ろに任意で`vip`または`chip48`を指定できます。大小文字は区別しません。
省略時はCHIP-48です。不正なプロファイルや余分な引数があればusageを表示し、
窓を開かずに終了します。ROMとプロファイルはNEXT-ARGで消費するため、
Sigmaがプロファイル名をソースファイルとして読み込むことはありません。
引数1がない場合や`-`で始まる場合（`-e`など）は語の定義だけを行います。
ROMを開いて読み込んでからウィンドウのループに入ります。
ROMのパスもテストのINCLUDEも作業ディレクトリ基準です。
3584バイトを超えるROMは拒否します。

64x32の画像を640x320の窓に表示します。Escで終了、F5で保存したROMから
リセットします。窓を閉じても終了します。英字は大小両方に対応します。

```text
CHIP-8       PC
1 2 3 C      1 2 3 4
4 5 6 D      Q W E R
7 8 9 E      A S D F
A 0 B F      Z X C V
```

## プロファイルとオプション

6個のスイッチはVARIABLEなので`!`で設定できます。初期値はすべてFALSEです。
プロファイル名は、このエミュレーターでのオプションの組み合わせを表します。

| 動作 | CHIP-48プロファイル（既定） | VIPプロファイル |
|---|---|---|
| シフト元（`CH8-SHIFT-VY`） | FALSE: Vx | TRUE: VyをシフトしてVxへ |
| Fx55/Fx65後のI（`CH8-LOAD-INC`） | FALSE: 保持 | TRUE: x+1進める |
| 8xy1/2/3のVF（`CH8-LOGIC-VF`） | FALSE: VFへの追加書き込みなし | TRUE: Vxへの格納後にVFを0にする。x=Fでも0が優先 |
| 描画の待機（`CH8-DISPLAY-WAIT`） | FALSE: 命令数の上限まで実行 | TRUE: Dxynでそのtickの命令実行を打ち切る |
| 数字の字形（`CH8-VIP-FONT`） | FALSE: 一般的なフォント | TRUE: VIPのフォント |
| 描画のはみ出し（`CH8-WRAP`） | FALSE: 切り取り | FALSE: 切り取り |

`CH8-CHIP48 ( -- )`は6個すべてをFALSEにし、ファイル読み込み時に一度実行します。
`CH8-VIP ( -- )`は先頭5個をTRUE、CH8-WRAPをFALSEにします。
どちらもCH8-SPEED（初期値10、16667マイクロ秒のtickあたりの命令数）は変えません。
フォントの選択は、次のCH8-RESETまたはCH8-LOADで反映します。
どちらも$050から1文字5バイトです。VIPの実機では81xxのROM内でパターンが
重なっていますが、ここでは字形だけを再現して連続配置しています。

表示待ちは近似です。VIPは描画前に表示割り込みを待ちますが、ここでは
直ちに描画し、そのtickの命令実行を打ち切ります。これにより1 tickあたり
最大1個のスプライトになります。CH8-STEP単独の動作は変えません。
描画で打ち切った場合もCH8-TICKはタイマーを減らします。

描画開始位置は常に折り返します。はみ出した画素はCH8-WRAPがTRUEなら
折り返し、それ以外は切り取ります。描画はXORで、消えた画素があればVF=1、
Iは変えません。演算前に入力値を読み、算術・シフトのフラグや論理演算の
VFクリアは最後に書きます。x=Fでもフラグが優先します。
論理演算のクリアが無効ならVFへの追加書き込みはありませんが、x=Fなら
論理演算の結果がVFに入ります。7xkk、Fx1Eもフラグの追加書き込みはありません。
Iの演算は16ビット、メモリアクセスは下位12ビットです。BnnnはV0を使います。
Fx0Aはキーが押されて離されるまでPCを据え置き、タイマーは進めます。
同時に押されているキーがあれば番号の小さいものを選びます。

CH8-RUNは対話実行開始時にUTIMEから乱数の種を設定します。
CH8-RESETとCH8-TICKはホストの時計を参照しません。種の初期値は12345で、
CH8-SEEDを明示的に設定すれば窓なしの実行を再現できます。

`CH8-BLEND`（既定3）は表示する直近フレーム数です。1は合成なし、使用時に1〜4へ丸めます。毎 tick の画面を保存し、現在と過去の画面の論理和を表示します。最大 `CH8-BLEND - 1` tick（既定では約33 ms）の残像が残ります。CHIP-8の画面状態や衝突判定は変わりません。`00E0` と `CH8-RESET`（F5を含む）は履歴も消去します。どちらのプロファイルもこの変数を変更しません。初期値を編集するか、次のように設定できます。専用のコマンドライン引数はありません。

```powershell
zig-out/bin/sigma.exe emu/chip8/chip8.fs -e '1 CH8-BLEND ! S" emu/roms/c8games/PONG" CH8-PLAY BYE'
```

利用者のPONG測定（パドル静止、600 tick）では、599表示フレーム中のパドル欠落は合成なし265、直近2フレーム68、直近3フレーム0でした。XOR消去から再描画までが1 tickを超える場合もあります。`CH8-BLEND-FRAME ( -- )` はホスト出力なしで履歴と `CH8-SHOWN` を更新し、`CH8-PAINT` はその画像を描きます。

## VIPとの相違点

上記の選択可能な動作と表示待ち・フォントの近似に加え、次は意図的に未実装です。

- Fx0Aでキーを押している間の音。
- 音の最小値02。
- 12段のスタック。このエミュレーターは16段です。
- 機械語サブルーチン（0nnn）。クリアとreturn以外は無視します。
- 1802の命令ごとの実行時間。

## エラーと実行

未対応命令とスタック異常は診断を表示してTHROWします。
専用のTHROWコードは次のとおりです。

| コード | 定数 | 意味 |
|---|---|---|
| -4100 | CH8-ERR-ROM-SIZE | ROMが3584バイトを超える |
| -4101 | CH8-ERR-ROM-READ | ROM読み込みが指定バイト数に満たない |
| -4102 | CH8-ERR-OPCODE | 未対応または不正な命令 |
| -4103 | CH8-ERR-STACK-UNDERFLOW | スタックが空の状態でreturn |
| -4104 | CH8-ERR-STACK-OVERFLOW | スタックが満杯の状態でcall |

ファイル操作ではSigmaのファイルI/Oエラーもそのまま送出します。

対話実行の各tickは命令実行、タイマー減算、音声供給の順です。音声は任意の
48 kHz・モノラル・440 Hz PCMで、音声機能がない場合やオープン失敗時は無音です。
合成画像が表示済み画像と異なるときだけ、tickあたり最大1回再描画します。遅延時は追いつくまで処理し、
5 tickを超える遅延では時刻を再設定します。CH8-RUNは例外を捕捉して
PCMを閉じ、例外を再送出します。

公開語はCH8-LOAD / CH8-PLAY `( addr len -- )`、CH8-RESET、CH8-STEP、
CH8-TICK、CH8-TICKS `( n -- )`、CH8-DUMP、CH8-RUN、CH8-CHIP48、CH8-VIPです。
引数を記した語以外のスタック効果は`( -- )`です。
CH8-TICKはホストの入力・窓への出力・音声を処理しません。
状態はスクリプト内のCH8-名で参照できます。CH8-KEYSは16バイトの0/1で、
窓なしの入力にも使えます。

## 単独の実行ファイルの作り方

`SAVESYS` は、その時点の辞書を含めた単独の実行ファイルを書き出します。
`APP-ENTRY!` は、その実行ファイルが起動時に1回だけ呼ぶ語を登録します。
次のようなファイル（例：`make-chip8.fs`）を作ります。

```forth
INCLUDE emu/chip8/chip8.fs
' CH8-START APP-ENTRY!
SAVESYS CHIP8.EXE
BYE
```

リポジトリの直下で実行します。

```powershell
.\zig-out\bin\sigma.exe make-chip8.fs
```

ROMのパスを指定して起動します。続けて`vip`または`chip48`も指定できます。

```powershell
.\CHIP8.EXE emu\roms\c8games\PONG
.\CHIP8.EXE emu\roms\c8games\PONG vip
```

- `INCLUDE emu/chip8/chip8.fs`でエミュレーターを読み込みます。`chip8.fs`の
  最後の`CH8-START`は、ここでは引数がないので何もしません。Sigmaは処理する
  ファイル名を引数から取り除くためです。
- `' CH8-START APP-ENTRY!`で起動時の語を登録します。引数の扱いは
  `sigma emu/chip8/chip8.fs ...`と同じで、ROMのパスと省略できるプロファイル、
  または`padtest`を受け付けます。
- `SAVESYS CHIP8.EXE`で実行ファイルを書き出します。入口を登録してあるので、
  Forthのプロンプトに入らず`CH8-START`から始まります。

注意点：

- `CHIP8.EXE`の引数はすべてエミュレーターに渡ります。Sigmaのオプションを
  使うときは`CHIP8.EXE --sigma <オプション> -- <引数>`と書きます。
- `pads.txt`は、カレントフォルダーから見た`emu/chip8/pads.txt`を読みます。
  ほかのフォルダーで起動すると見つからず、ゲームパッドは既定の割り当てに
  なります（エラーにはなりません）。
- 使い方の表示は`Usage: sigma emu/chip8/chip8.fs ...`のままです。
- 引数なしで起動すると、何も表示せずに終了します（終了コード0）。
- `chip8.fs`を変えたときと`sigma.exe`を作り直したときは、実行ファイルも
  作り直します。辞書の形式が変わると、古い実行ファイルは起動時にエラーで
  止まります。
- 大きさは約16MBです。リポジトリの直下に作ると`git status`に未追跡として
  出ます。`.work/`の下に作れば無視されます。

## 検証

失敗したチェックは短いラベルと期待値・実際の値を表示し、最後に
`passed N failed M`を出力します。失敗時はBYE前にTHROWし、終了コード1です。
MAZEとPONGを窓なしで各300 tick実行し、MAZEを一度文字で表示します。
ROMはリポジトリに含めていません（`emu/roms/`はGitの対象外）。
`emu/roms/c8games/MAZE`または`PONG`がなければ、その検査を飛ばして
`INFO skipped, ROM not found:`の行を表示します。
今回の検査は3257件成功、0件失敗、終了コード0でした。標本を書かない無音のPCM開閉検査と、ST=0で書き込まない検査も実行します。
設定の検査データはテスト自身のコメント内に置き、一時ファイルは作成しません。
新しいスイッチの両設定、x=Fの論理演算、tickの打ち切り、STEP単独、
両フォント、プロファイルの6変数を検証しています。

存在しないROMでは、省略・`ViP`・`ChIp48`がいずれも窓のループ前のOPEN-FILEで
失敗しました（終了コード1）。不正なプロファイルはusageを表示しました（終了コード0）。
実際のキー操作・窓表示、実時間での進行、音声再生、CH8-RUNでのUTIMEによる
種の設定、Ctrl+C時の後始末は未検証です。音声機能なしの実行ファイルも未検証で、
その場合の語は条件付きで定義しています。

## 参照資料

- Cowgod, *Chip-8 Technical Reference v1.0*.
- Matthew Mikolay, *Mastering CHIP-8*.
- Laurence Muller, *How to write an emulator (CHIP-8 interpreter)*.
- RCA, *COSMAC VIP CDP18S711 Instruction Manual* (1978), section III Table I
  and Appendix C interpreter listing.
- Erik Bryntse, *SUPER-CHIP v1.1 documentation* (CHIP-48 instruction table only).

これらの資料からコードを取り込んでいません。VIPの要件とフォントのバイト列は
タスク1469で提示されたものを使いました。このラウンドでは外部資料へのアクセスは
行っていません。コードの書式は`examples/paddle.fs`に合わせています。

## ゲームパッド

パッド0のmapped（標準配置）とraw（未割当て）の両方を使える。`CH8-INPUT` ごとに `GAMEPAD-POLL` を1回呼び、負の戻り値なら次の `CH8-RUN` まで止める。パッドがなくてもキーボードを使える。`CH8-PAD-KEYS` と `CH8-PC-KEYS` を論理和で `CH8-KEYS` に合成し、`Fx0A` もこの状態で押下と解放を待つ。

入力は36個であり、`up down left right` が番号0〜3、`b0`〜`b31` が番号4〜35である。方向はハット0（上1・右2・下4・左8）と軸0（X）・軸1（Y）の論理和である。mappedではさらにボタン11〜14の十字キーを合わせる。軸が `-16384` 未満なら左または上、`16384` を超えれば右または下とする。`GAMEPAD-HATS`、`GAMEPAD-AXES`、`GAMEPAD-BUTTON-COUNT` で数を確認し、存在しない入力を問い合わせない。rawの軸は、その実行中に `-32768` 以外の値を受け取るまで無視し、その後は `-32768` も通常の値として使う。XとYは独立して判定する。

`bN` はSigmaのボタン番号Nであり、mappedなら標準配置、rawなら機器の番号である。別名 `a b x y back start l r` は順に `b0 b1 b2 b3 b4 b6 b9 b10` を表す。rawでは単にその番号を指し、機器に印刷された文字と一致するとは限らない。

割当て先は `-`（なし）、16進1桁の `0`〜`F`、`reset`（`F5`）、`quit`（`Esc`）である。`reset` と `quit` は各入力を押した瞬間だけ働く。既定値は `up=2 down=8 left=4 right=6 b0=5`、残りはなしである。mappedだけはさらに `b6=reset b4=quit` とする。rawでもファイルに明示した操作は有効である。

設定は作業ディレクトリ基準の `emu/chip8/pads.txt` に置き、リポジトリ直下から実行する。形式は `NAME input=target ...` である。`NAME` はROMのファイル名で、スラッシュとバックスラッシュの両方からディレクトリを除く。`*` は全ROMに適用する。英字は大小文字を区別しない。空行は無視し、`#` から行末まではコメントとする。1行は255文字までである。不正なトークンはファイル名・行番号・トークンを警告して無視し、残りを読む。ファイルがなければ警告しない。

適用順は組込み既定値、すべての `*` 行（ファイル順）、一致するすべてのROM行（ファイル順）である。行ごとに初期化せず、指定した入力だけを上書きする。同じ入力は最後の正しい指定を使う。ファイルを2回読み、設定を36セルの `CH8-PAD-OVERLAY` に蓄積する。`-2` は未指定である。実行中にパッドを初めて検出した際にmapped/rawの既定値を選び、その上に設定を重ねる。

`CH8-PLAY` とコマンドライン起動は設定を読む。`CH8-LOAD` 単独では設定を消去してraw用の既定値に戻し、最初の検出時に種類を選び直す。`CH8-RESET` は割当てと入力履歴を保つ。`CH8-RUN` は検出・押下端・軸の履歴を初期化する。

rawのボタン番号は次のコマンドで調べる。

```powershell
sigma emu/chip8/chip8.fs padtest
# リポジトリの既存実行ファイルを使う場合:
zig-out/bin/sigma.exe emu/chip8/chip8.fs padtest
```

引数1が大小文字を問わず `padtest` と完全一致すると、`CH8-PAD-TEST` を実行して終了する。窓は開かず音も鳴らさない。約100ミリ秒ごとにmappedフラグ、押している方向、ボタン番号を1行で表示する。キーボードのキーを押す（`INKEY`）か30秒経過すると終了する。表示された番号を使い、例えば `* b9=reset b8=quit` と設定する。

| 語・領域 | 動作 |
| --- | --- |
| `CH8-PAD-DEFAULT ( mapped -- )` | 種類に応じた組込み既定値を設定する。設定の上書きは行わない |
| `CH8-PAD! ( target input# -- )` | 入力0〜35に `-1`〜17を設定する。範囲外の引数は無視する |
| `CH8-PAD-LOAD ( rom-addr rom-u -- )` | 共通・ROM設定を読む |
| `CH8-PAD-LOAD-FILE ( rom-addr rom-u file-addr file-u -- )` | 指定ファイルから同じ規則で読む |
| `CH8-PAD-MAP` | 36セル。`-1` はなし、0〜15はキー、16はリセット、17は終了である |
| `CH8-PAD-KEYS`、`CH8-PC-KEYS` | 各16バイトのキー状態である |
| `CH8-MERGE-KEYS ( -- )` | 両配列を `CH8-KEYS` に合成する。ホスト入力は読まない |
| `CH8-PAD-STATE ( dirs buttons mapped -- )` | 方向ビット0〜3と32ビットのボタンマスクからキーと押下端を処理する。ホスト入力は読まない |
| `CH8-PAD-DIRS ( hat x y buttons mapped -- dirs )` | 方向を合成する |
| `CH8-PAD-AXIS-VALUE ( value axis mapped -- value )` | 軸0・1のraw初期値を抑制する |
| `CH8-PAD-PRINT ( dirs buttons mapped -- )` | 診断の1行を表示する |
| `CH8-PAD-TEST ( -- )` | 最大30秒間、窓なしで入力を表示する |

入力数・番号の根拠は `docs/WORD_REFERENCE.ja.md` の `GAMEPAD-HAT`、`GAMEPAD-HATS`、`GAMEPAD-AXES`、`GAMEPAD-AXIS`、`GAMEPAD-BUTTON-COUNT`、`GAMEPAD-BUTTONS` である。raw軸の初期値は `docs/GRAPHICS_AND_SOUND.ja.md` の366行による。添付した6個のROM設定の方向の意味は未確認である。自動検査はホスト入力なしの状態変換、設定解析・累積・優先順、別名、押下端、軸初期値、固定値の表示を対象とする。実機操作と診断の待機ループは実行していない。

診断表示の例は `mapped=0 directions=- buttons=-`、`mapped=0 directions=up,left buttons=0,9` です。空欄は `-`、複数の入力はコンマで区切ります。

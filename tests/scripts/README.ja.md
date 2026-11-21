# テストと検証のスクリプト

`zig build audio-lifecycle-check --prefix .work/1127/windows`は、停止要求を無視する
consumerの専用fixtureを作る。通常のinstall/releaseには含めない。
`python tests/scripts/verify-audio-shutdown.py .work/1127/windows/audio-check/x86_64-windows/probe.exe`
は自分で起動した子を3回実行し、領域保持とstatus1の終了を確認する。
Linux targetの生成probeはLinuxで実行する。[検証記録](../../docs/PCM_HOST_LIFETIME_IMPLEMENTATION.md)を参照。

`python tests/scripts/verify-saved-application.py PATH`は自分専用のSAVESYS実行体を作り、
起動語・引数・起動回避・破損画像・再保存・自己別名拒否と終了コードを検査する。
POSIXでは専用PTYで中断と端末設定の復元も照合する。機能除外版は`--no-debug`、
`--no-files`で期待結果を切り替える。Windows用の
`verify-saved-application-windows.py PATH`は非表示の専用consoleでCtrl+Cを確認する。
所有ファイルは`.work/1069`内へ作り後始末する。利用者のconsoleへ入力は送らない。
[検証結果とMac手順](../../docs/SAVED_APPLICATION_STARTUP_IMPLEMENTATION.md)を参照。

`verify-filesystem.py --sigma PATH --output PATH`は、実測したGforthのCOMPACT
1,010例、長いパス、実パスの容量・重複・リンク、通常fileのmetadata、SYNCの方向切替・
保留入力・EOF・拒否条件を所有する一時fileで確認します。
`zig cc -shared -DSIGMA_FS_TESTING src/host_filesystem_native.c -o .work/646/filesystem-native.dll`
でWindows用fixtureを作り、`verify-filesystem-native.py --library PATH`で確認します。
LinuxはGNU共有library（`-shared -fPIC -target x86_64-linux-gnu`）を使います。
native試験は1,000反復後のhandle/fd数と、Windowsの試験専用カウンターによる
open前のdevice拒否を確認します。シリアル機器は開きません。所有する試験fileは.work/646内です。

`verify-graphemes.py --sigma PATH`は、EXTENSIONのX-GRAPHEMEと
X-GRAPHEME-LASTをUnicode 18.0.0の固定GraphemeBreakTest全853ケースと照合します。
各クラスタを両端から照会する3,096項目の検査です。
`python scripts/make-grapheme-table.py --check`はオフライン再生成と公式入力の
SHA256を照合します。どちらもネットワークへアクセスしません。

リポジトリのルートから実行します。`test-*`は回帰テスト、`verify-*`は統合・比較の
確認、`probe-*`は参考結果の収集です。`gforth-p00/`にはP00のGforth参照テストが
あります。必要な参照ビルドはそのREADMEを確認してください。各スクリプトの
OS・参照実行環境の条件も満たす必要があります。

実行例:

```sh
python3 tests/scripts/test-word-reference.py --sigma zig-out/bin/sigma
python3 tests/scripts/test-line-editor.py --sigma zig-out/bin/sigma
python3 tests/scripts/verify-p10.py --sigma zig-out/bin/sigma --output .work/p10/report.json
python3 tests/scripts/verify-feature-matrix.py --platform macos
python3 tests/scripts/verify-debug-outputs.py --sigma zig-out/bin/sigma --out tests/scripts/debug-outputs/windows.json
python3 tests/scripts/verify-debug-outputs.py --compare tests/scripts/debug-outputs/macos.json tests/scripts/debug-outputs/windows.json
```

ビルド・配布・データ生成・文書生成・ベンチマークのコマンドは`scripts/`にあります。
`check-docs.py`、`word-reference.py`、その補助の`word_reference_examples.py`、
`benchmark-runtime.py`も同じです。`test-benchmark-runtime.py`にはLinuxの
プロセスCPU時計APIが必要です。

`debug-outputs/`には各OSで`verify-debug-outputs.py`が記録した結果があり、
`--compare`で比較できます。

`check-ime.fs`は合否を自動判定しない手動確認です。`GUI-FIELD`を表示し、IMEで
入力した日本語とそのバイト列を出力します。実行方法はファイル冒頭にあります。

`check-window.fs`もSigma自身のウィンドウの手動確認です。マウスの押下・解放・
ホイールを出力し、入力待ちや計算中の移動・リサイズ・閉じる操作を確認できます。
実行方法はファイル冒頭にあります。

`check-fullscreen.fs`は`FULLSCREEN`と`MOUSE-CURSOR`の手動確認です。ウィンドウが
フルスクリーンで開き、キーで解除・再びフルスクリーン・カーソルの表示切替を試せます。
キーと見る点はファイル冒頭にあります。

`check-auto-size.fs`は`WINDOW-SIZE 0 0`の手動確認です。3つの画像を順に表示し、
ウィンドウが画面の作業領域に収まることを確かめます。見る点はファイル冒頭にあります。

過去の測定JSONと外部レビュー原文には、記録当時のパスを残しています。
現在の実行コマンドは`tests/scripts/`を使います。

Linuxの実験用X11バックエンドは`zig build -Dx11=true`でビルドします。
`test-linux-native-window.py`は画素・黒余白・キー・閉じて再表示を確認し、
`SIGMA_TEST_RESIZE=1`でリサイズの再描画も確認します。private Xvfbだけで、
`SIGMA_TEST_REMAP=1`によるキーマップ変更と、`test-linux-xim-fixture.py`による
preeditの差分・Unicode確定・IMの生存確認を試せます。この2つは
`SIGMA_TEST_PRIVATE_XSERVER=1`が必要で、利用者のデスクトップには適用しません。
`SIGMA_TEST_CLOSE_AFTER=6`は初回作成期限の後に閉じて再表示する確認です。
`test-linux-x11-failures.py`は自分専用の一時ソケットで接続拒否・切断・無応答を確認します。
実行ファイルは`SIGMA_TEST_BINARY`で選べます。

`test-linux-display-budget.py`は実験用Linuxビルドで、自動探索全体の5秒期限、
PNG送信の詰まり、無応答・停止した子、少量ずつ続く応答、回収、再試行、失敗後の
明示的Tcl実行を確認します。一時的なwish代替プログラムと専用ローカルソケットを
使い、デスクトップには接続しません。プロセス起動とスケジューリングを含む
受け入れ許容値は5.25秒です。

`check-window-keys.fs`は特殊キー・リピート・フォーカス喪失の手動確認用に、
キーコードとAの押下状態を記録します。stdinを`/dev/null`にして端末入力を除外します。
Escapeで終了し、窓のCtrl+Cはキー読込と押下状態読込の両方で捕捉します。繰り返しの
コードとVM処理時刻は利用者の操作報告と照合します。手順はファイル先頭を参照してください。

`test-linux-window-colors.py`はフルカラー/2/16/256色とディザリングの8設定で、
整数倍率のリサイズ前後のnativeとTkの画素を比較します。
`test-linux-auto-display.py`は自動選択、選択済み表示先の切断、明示指定の失敗、
`DISPLAY-AUTO`での復帰を確認します。両方とも認証付きdepth24の専用Xvfbを起動し、
利用者のDISPLAYには接続しません。XvfbがPATHにない場合は`SIGMA_TEST_XVFB`、
実験用Linux実行ファイルには`SIGMA_TEST_BINARY`を指定します。Xvfb/wishがなければ
成功扱いにはせず、終了コード77でskipと報告します。
`test-linux-x11-support.py`は共通ヘルパーの途中行の期限、stderrの詰まり防止、
プロセスグループ回収、X11認証、skipの終了状態を確認します。

`check-window-display.fs`は色・リサイズ・画面間移動の手動確認です。色帯・灰色階調・
4つのクリック対象を表示し、0/2/6/5で色数、Dでディザリングを切り替えます。
デスクトップの表示設定は変更しません。手順はファイル先頭を参照してください。

### 子プロセス管理（643）

`verify-process-words.py --sigma PATH`は公開PROC語とFILE/AVAILABLEによる3ストリームの
大量入出力を確認します。`verify-process-interrupt.py --sigma PATH`は無期限待機の中断と
子プロセスの生存を確認します。Windowsの中断試験は専用の非表示consoleを作り、
その中だけにCtrl+Cを送ります。

制御したfixtureは`zig cc tests/process_wish_fixture.c -o .work/643/wish-fixture.exe`で作成し、
`verify-process-capacity.py --sigma PATH --fixture PATH`で64実プロセスと上限超過・再利用を、
`verify-process-tcl.py --sigma PATH --fixture PATH`でTcl内部予約枠・再起動・script削除・
終了時の子孫回収を確認します。Linux用fixtureは
`zig cc -target x86_64-linux-musl`で作成し、WSL内でLinux版Sigmaと実行します。
fixtureは実Tcl/TkやGUI表示の代用ではありません。

native C単体は`zig cc -shared -DSIGMA_PROC_TESTING src/host_process_native.c -o .work/643/process-native.dll`
と`verify-process-native.py --library PATH`で確認します。LinuxのPython ctypesにはGNU共有libraryを
使います。Linuxの子孫試験は専用helperのsubreaper設定を一時変更し、自分で起動した子孫を回収して
元へ戻します。製品Sigmaではsubreaperを設定しません。

各scriptの`--output PATH`でJSONの結果を保存できます。OS単体・公開語・Tcl protocol・実GUIを区別し、
Macのクロスコンパイルを実機確認の代わりにしません。

### EXEC-LIMITED (652)

`python tests/scripts/verify-execution-control.py Sigmaのパス`で公開予算・THROW・NSを確認します。Unixでは専用PTYでRaw文字・貼付け・未完成ESC保持、SIGINT、NS/Cooked KEYの中断とmode復元も調べます。`python tests/scripts/verify-execution-control-windows.py Sigma.exeのパス`は専用の非表示consoleにだけF1・日本語・貼付け・未完成ESC・Ctrl+Cを注入し、NS/KEY・満杯時の文字保持を調べます。利用者のconsoleへ入力・信号を送りません。stdoutをJSON記録へ保存できます。物理キーボードやMac実機の確認とは区別します。

## PCM公開語の検証

`python tests/scripts/verify-pcm-stream.py SIGMAのパス`は専用プロセスに無音PCMを渡し、書込み・満杯待機・drain・close、メモリエラーからの回復、二重open、保存アプリ、辞書追記を確認します。image除外構成には`--no-image`を付けます。

`python tests/scripts/verify-pcm-terminal.py SIGMAのパス`は専用の非表示WindowsコンソールかLinux PTYを使います。文字・日本語・未完成ESCとCtrl+Cを送り、WAIT/STOPの-28、CLOSEの-516と再試行、入力保持、端末設定復元を確認します。利用者のコンソールには入力しません。フレームはすべて0で、可聴音や物理キーの確認にはなりません。結果は[PCM検証記録](../../docs/PCM_PUBLIC_IMPLEMENTATION.md)を参照してください。

## Forth音源の試作

`python tests/scripts/verify-pcm-synth.py SIGMAのパス [--benchmark]`は、手計算した標本、独立したPythonのs16LE列、分割・レジスタ変更時の連続性、不正引数、強制した部分書込み・満杯・期限切れ・close失敗と、実PCMへの無音送出を確認します。benchmark指定時はwarm-up後のNTIME/CPUTIME差を7回測り、最終バッファのチェックサムも照合します。別の送出試験は外側の単調時計を使い、書込み・待機・アンダーラン回数とAUDIO?も記録します。実機の音源や可聴音を検証するものではありません。リポジトリ直下から実行してください。[範囲と結果](../../docs/PCM_SYNTH_PROTOTYPE.md)。

## NES APUのForthサブセット

`python tests/scripts/verify-nes-apu.py SIGMAのパス [--benchmark]`は、Forthの1クロック版・まとめ処理版の状態とPCMを独立したPythonモデルと比較します。frame/reset/IRQの境界、envelope/length/sweep/linear、時刻付き書込み、予定表の順序・容量、不正入力、実PCMへの無音送出を確認します。benchmark指定時は通常・1クロック版・最速noiseの負荷をwarm-up付き7processで測り、128件の時間指定書込みを含めます。この回帰負荷ではDMC再生を無効にし、CPU/PPU・バス競合・装置再生は含みません。5声の負荷はverify-nes-dmc.pyで扱います。長い予定表は専用の一時Forthファイルにし、CLIの-e長制限を避けます。[仕様・資料照合・結果](../../docs/NES_APU_FORTH.md)。

## NES DMCモデル

`python tests/scripts/verify-nes-dmc.py SIGMAのパス [--benchmark]`は全レート、コピーしたbuffer、loop/stop/restart、IRQ/status、番地の折返し、直接DACの境界、全32799 LUT項目とメモリ検査を照合します。8kHz直接DACで1024件を超えて登録し、全出力をPythonと比較します。benchmark指定時は通常/基準版/最速noise-DMC/直接DACを各7processで測定します。verify-nes-apu.pyは1134の固定出力SHAを保持します。独自データだけを使用し、ROM・実機DMA・可聴音の確認ではありません。[契約と測定](../../docs/NES_DMC_FORTH.md)。

## SIDレジスタとフィルター近似

`python tests/scripts/verify-sid.py SIGMAのパス [--benchmark]`は独立したPythonの1clock版とForthの両経路を比較します。時刻指定3声PCM、ADSR/同期/ノイズ境界、不正入力の状態保持、パルス/リング/配線の手計算値、全2048係数、64種のフィルターインパルスと8kHz予定表回収の全PCMを照合します。benchmarkは通常/基準版/最大フィルター・同期の混在/3声noise/8kHz書込みをwarm-up付き7processで測定します。`python scripts/sid-filter-coeffs.py --check`でDecimalの表を再生成せず検証します。音声試験は無音を送り、実際の6581/8580やROMを正解値とした検証ではありません。[契約と制限](../../docs/SID_FORTH.md)。

## Paulaステレオレジスタモデル

`python tests/scripts/verify-paula.py SIGMAのパス [--benchmark]`は独立したPythonの1tickモデルをForthの両経路・分割ステレオPCMと比較します。DMA/reload/IRQ、手動DAT保持、volume/attachの全mask、メモリ折返し/保持、不正値の原子性、予定表の回収を確認します。benchmarkは通常/基準版/最小周期/変調/8kHz volume・手動DATを各7processで測り、先に計時外で全PCMを照合します。音声試験は無音を送り、Macと生成音の実聴は別確認です。[契約と制限](../../docs/PAULA_FORTH.md)。

補助の`python tests/scripts/verify-paula-stream.py SIGMAのパス`は実PCMを開かず、ステレオcallbackと変調の手計算値の10検査を行います。部分/満杯からの再試行、非ゼロbyte列、4byte単位のoffset、cleanup例外、attachの交互動作を確認します。

## YM2149/STのレジスタと仮想ポート

`python tests/scripts/verify-ym2149.py SIGMAのパス [--benchmark]`は独立したPythonのmaster clockモデルをForth両経路と比較します。全16envelope、64mixer真理表、32係数、3072種I/O、ST select/data、不正値の原子性、予定表回収と全PCMを確認します。benchmarkは6負荷の全32768frameと37項目の状態を比較後、7つの新processを測り、warmup/reset後の計時終了状態もすべて照合します。`python tests/scripts/verify-ym2149-stream.py SIGMAのパス`はmono callback/cleanupと相対時刻/query/bus/reset状態の手計算を補います。`python scripts/ym2149-levels.py --check`で理想DAC表を検証し、native固定0の回帰は`zig build test`で実行します。実周辺機器や実機の正解値による検証ではありません。[契約と測定](../../docs/YM2149_FORTH.md)。

## PCM語群除外と実聴の受け入れ

CHIP-8音源は`python tests/scripts/verify-chip8-audio.py SIGMAのパス`で独立数理モデルと全PCM/状態を照合し、`python tests/scripts/verify-chip8-audio-stream.py SIGMAのパス`で非ゼロRAMだけのmono/cleanup fixtureを確認します。`python scripts/chip8-pitches.py --check`は全256整数stepを再生成照合します。リポジトリ直下から実行し、これらのコマンドは生成音を実装置へ送りません。[契約](../../docs/CHIP8_AUDIO_FORTH.md)。

`python tests/scripts/verify-pcm-exclusion.py SIGMAのパス --audio enabled`（または`disabled`）はEVALUATE/CATCHでREQUIRE-AUDIOを実行し、実際の名前検索とstack深さを照合します。音声は開きません。`python tests/scripts/pcm-listen.py SIGMAのパス --case 1`は無音で実行します。明示した`--audible`時だけ生成音を出します。case1..8でmono/stereo・MML/SFX混合・破棄/再open・drain・SAVESYS・前面端末でのCtrl+C/ACCEPTを確認します。実行JSONだけで利用者の実聴成功とはしません。[手順と残件](../../docs/PCM_LISTENING_ACCEPTANCE.md)。

## ZX Spectrum音源（1169）

`python tests/scripts/verify-zx-spectrum-audio.py PATH_TO_SIGMA` は全65536 OUT/IN port、AY mask/envelope、独立CPU-tickのPCM/状態、同tick順序とerror境界を検査する。音声装置は開かない。

`python tests/scripts/verify-zx-spectrum-audio-stream.py PATH_TO_SIGMA` はRAM callbackで部分送出・全byteのコピー・timeout/cleanup・streamの事前検査を確認する。生成音はメモリ内だけに保持する。[仕様・結果](../../docs/ZX_SPECTRUM_AUDIO_FORTH.md)を参照。速度測定の開始には別途確認が必要。

`python tests/scripts/measure-zx-spectrum-audio.py PATH_TO_SIGMA` は既定では計時せず、6負荷各32768frameを照合する。`--measure` は計時開始への利用者の了承後だけ使い、7回の別processで測定する。[準備レビュー](../../docs/reviews/1170-1171-review-response.md)を参照。

## SNES S-DSP音源（1174）

`python scripts/snes-tables.py --check` は512係数の生成表を再現確認する。

`python tests/scripts/verify-snes-dsp-audio.py PATH_TO_SIGMA --reference-doc CACHED_FULLSNES_HTML` は全BRR/Gauss/rate/register/ARAM、独立PCM/状態/全ARAM、時刻・queue/errorを検査する。元HTMLは[fullsnes](https://problemkaputt.de/fullsnes.htm)から取得したものを使い、記録済みhashを照合する。option省略時もnumeric pin hashを確認するが、元資料との別抽出は省略される。音声装置は開かない。

`python tests/scripts/verify-snes-dsp-audio-stream.py PATH_TO_SIGMA` は生成音をRAMだけへ送り、stereo4byte offset・prime/継続・partial/timeout/cleanup等19caseを検査する。[仕様・結果](../../docs/SNES_DSP_AUDIO_FORTH.md)を参照。

`python tests/scripts/measure-snes-dsp-audio.py PATH_TO_SIGMA` は既定では計時せず6負荷各16384frameを全PCM/状態/ARAMと照合する。`--measure` は計時開始への利用者の了承後だけ使う。

### S-DSP native frame kernel

`verify-snes-dsp-audio.py SIGMA --native` はForth個別検査に加えてnative frameのBRR全256×16×3、317 ENV、補間256位相×4履歴、FIR8タップを独立Pythonと照合します。`verify-snes-dsp-native.py SIGMA` は複数frame、DIV、切替え、reset、EXEC-LIMITED中断と再開、SAVESYS後の全state/ARAMを照合します。debug除外では `--no-debug` を指定します。

`verify-snes-dsp-audio-stream.py SIGMA --native` はRAM callbackのみを使います。`measure-snes-dsp-audio.py SIGMA --native` の既定も計時なしの6負荷照合です。`--measure` は新たな開始確認への返答後に限ります。audio除外ではnativeを指定せず参照Forthを検査します。一時スクリプトは `.work` に置きます。

### 標準の音

`python tests/scripts/listen-standard-sound.py PATH_TO_SIGMA` は標準の音を実際に聞く32のケースを鳴らします。1〜21は標準の音(PLAY、MML の V・S・M、BEEP、PLAY-TONE、音色の語、SAMPLE と SFX、MOD、全体の効果、16声の同時発音)、22〜32は `include/` の機種のライブラリ(各機種、SOUND、STYLE)です。各ケースの前に聞こえるはずの音を表示し、Enter を待ちます。`--list` はケースの一覧を表示し、`--case N` はケースを選び、`--silent` は `0 MASTER-VOLUME` で全ケースを動かして動作だけを確かめます。JSON は実行の記録だけで、聞こえた音は人が報告します。生成したプログラムと MOD ファイルは `.work/1201` に置きます。

`python tests/scripts/measure-standard-sound-load.py zig-out/audio-check/<arch>-<os>/sound-load(.exe)` は、エンジン単体での16声の3つの負荷(`zig build sound-load-check -Doptimize=ReleaseFast` でビルド)を、既定では計時せずに照合します。`--measure` は計時開始への利用者の了承後だけ使います。各負荷を計時なしで1回、計時ありで7回、それぞれ48 kHz ステレオ10秒分を合成します。

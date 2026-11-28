# Arduboyエミュレータの検討

2026-11-28 作成。tque 1481。仕様を決めるための調査と速度試作であり、エミュレータ本体の実装ではない。文体・構成は `docs/LOGO_TURTLE_STUDY.md` に合わせた。番号で回答できる判断点を5章にまとめる。推奨はロクの案であり、利用者の決定ではない。

## 1. 前提と調査の範囲

- 2026-11-19の決定に従い、エミュレータはSigma本体に組み込まず、`emu/chip8`、`emu/logo` と同じ外部Forthスクリプトに置く。
- 対象はATmega32u4、16 MHz、32 KiBプログラムフラッシュ、2.5 KiB SRAM、1 KiB EEPROM、128×64 SSD1306、方向4ボタンとA/Bである。Gamebuino、ATmega328P、PCD8544は対象に含めない。
- 利用者所有のRust版 `D:/home/source/rust/arduboy-emu` を読み取りだけで調べた。`crates/core/Cargo.toml` の版は0.8.1、ライセンスは `MIT OR Apache-2.0` である。Rust版は実行していない。
- 初回調査ではSigmaの再ビルド、Git操作、Web取得を行っていない。本改訂はClaudeによる最適化ビルドの再測定ログと利用者の報告を反映した。ロクは今回、再ビルド・再測定・Git操作・Web取得を行っていない。ハードウェアの一次資料との独立照合は未実施である。以下のハードウェア動作の根拠は指定されたRustソースであり、Rust版の説明にある「cycle-accurate」を実機互換の証明として扱わない。
- `tque show 1481` は保存先のlock作成でアクセス拒否となった。タイトル・説明・親子関係は再確認できていない。タスク番号と作業範囲は今回の依頼による。

## 2. Rust版から確認した対象範囲

### 2.1 CPU命令

根拠は `crates/core/src/opcodes.rs` の `Instruction` と `decode`、`cpu.rs` の `execute_inst` である。「実際の各ゲームが必要とする最小集合」はROMの逆アセンブルをしていないため未確認である。最初のCPU実装は次の集合を候補とする。試作の命令集合は4章に分けて記す。

| 分類 | 対応候補（Rust版でdecode・executeの分岐を確認） |
|---|---|
| 加減算 | ADD、ADC、SUB、SUBI、SBC、SBCI、ADIW、SBIW、INC、DEC、NEG |
| 論理 | AND、ANDI、OR、ORI、EOR、COM |
| 比較 | CP、CPC、CPI、CPSE |
| 乗算 | MUL、MULS、MULSU、FMUL、FMULS、FMULSU |
| 転送 | MOV、MOVW、LDI、LDS、STS、PUSH、POP、IN、OUT |
| 間接SRAM | LD/STのX・Y・Z、無更新・後置加算・前置減算、Y/Zの変位付きLDD/STD |
| プログラム読出し | LPM（R0、Rd、RdとZ後置加算） |
| シフト・ビット | LSR、ASR、ROR、SWAP、BST、BLD、SBI、CBI |
| 分岐・呼出し | RJMP、RCALL、RET、RETI、JMP、CALL、IJMP、ICALL、BRBS、BRBC、SBRC、SBRS、SBIC、SBIS |
| 状態 | BSET/BCLRの全8ビット（SEC/CLC、SEZ/CLZ、SEN/CLN、SEV/CLV、SES/CLS、SEH/CLH、SET/CLT、SEI/CLI） |
| その他 | NOP、SLEEP、WDR、BREAK、SPM（扱いは下記） |

BREQ/BRNEなどの条件名はBRBS/BRBC、LSLはADD Rd,Rd、ROLはADC Rd,Rd、CLRはEOR Rd,Rd、TSTはAND Rd,Rd、SERはLDI Rd,255などの別名として扱う。独立した命令ハンドラを増やす必要はない。

Rust版はELPMの3形式とEIJMP/EICALLも実装している。32 KiBの32u4を対象とする初期範囲では不要とする案である。対応機種の命令表との最終照合はCPU設計時に残る。SPMはRust版でも1サイクルの無操作、WDRも無操作、BREAKはデバッガ停止要求、未知命令は診断条件付きの1サイクル処理である。これらを完全実装と数えない。初期版はブートローダを通さずゲームを直接ロードし、自己書換え・watchdogは対象外、未知命令はPCとopcodeを出して停止する案を推奨する。

PCはワード単位、LPMはバイト単位である。JMP/CALL/LDS/STSは2ワードなので、スキップ命令も次の命令長を調べる必要がある。SREGはI/T/H/S/V/N/Z/Cを保持し、命令ごとの更新対象だけを書き換える。SBC/SBCI/CPCのZは旧Zとの連鎖を持つ。割込み時のPC保存、Iの解除、RETI、SEI直後の受付境界も別の検査項目とする。

### 2.2 サイクル、タイマー、PLL、ADC

| 項目 | 確認した参照と設計案 |
|---|---|
| CPU時間 | `cpu.rs` は命令ごとのサイクルを返し、分岐成立・不成立やスキップ長を区別する。ホストの経過時間とは分離した64ビットの累積AVRサイクルを持つ |
| Timer0 | `peripherals/timer8.rs`。8ビット、分周、比較一致・overflow・割込み。Arduinoのmillis/micros/delayを支えるため最初から含める |
| Timer1/3 | `peripherals/timer16.rs`。16ビット、WGM、比較値、分周、overflow/compare IRQ、出力比較。音とゲーム内の時間処理のため最初から含める |
| Timer4 | `peripherals/timer4.rs`。高速タイマー固有のレジスタとクロックを扱う。Timer0の複製では済まない。初期版にも含めるが、全モードの適合は段階別に明示する |
| PLL | `peripherals/pll.rs`。Rust版はwriteで即座にPLOCKを立て、発振安定の待ち時間を再現しない。初期案も待ちループを抜けられる機能近似とする。Timer4のPLL由来クロック比は別に扱う |
| ADC | `peripherals/adc.rs`。Rust版はxorshiftで値を作り、変換開始で即完了させる近似である。initRandomSeed用には固定seedを選べる疑似乱数と完了状態を設ける。実機のアナログ雑音や変換時間の一致は保証しない |

推奨する精度は「命令のサイクル数を維持し、次の周辺イベントまでまとめて進め、命令境界で割込みを受け付ける」方式である。すべての16 MHzクロックでForthのタイマー語を呼ぶ方式は避ける。I/O読書きの直前には時刻を同期し、同時発生イベントの優先順位を定義する。命令内部の厳密なバス位相、発振器・アナログ挙動までの一致は初期の合格条件に含めない。※推測：イベント単位の進行は毎命令で全タイマーを計算する方式より負担を減らせるが、削減量は未測定である。

### 2.3 SSD1306とSPI

`display.rs`、`peripherals/spi.rs`、`lib.rs` のSPDR処理と `flush_spi` を参照した。SPI送信を受け、CS、DC、resetのGPIOを解釈してコマンド列とデータ列を分ける。AVRのSPI完了フラグとポーリングも必要であり、単にSRAMの画面バッファを読む方式では足りない。

初期コマンド候補は、20（addressing mode）、21（column range）、22（page range）、00–1F（column）、B0–B7（page）、40–7F（start line）、81（contrast）、8D（charge pump）、A0/A1（segment remap）、A4/A5（RAM/all-on）、A6/A7（normal/inverse）、A8（multiplex）、AE/AF（off/on）、C0/C8（scan direction）、D3/D5/D9/DA/DB（offset/clock/precharge/COM/VCOMH）、E3（NOP）である。値は16進表記である。スクロール26–2Fは追加範囲の判断対象とする。

Rust版は21/22、81、AE/AF、A6/A7の状態を持ち、20/A8/D3/D5/D9/DA/DB/8Dは引数1バイトを読み飛ばす。00–1F、40–7F、A0/A1、A4/A5、C0/C8は状態を更新しない。データの送りはcolumnからpageへの順で固定されている。したがってRust版を「全addressing modeと回転表示の正解」とは扱えない。Sigma版は1024バイトのGDDRAMを正本として保持し、表示時に128×64の色番号へ展開する案である。未対応コマンドは記録し、引数をopcodeと取り違えないようにする。

### 2.4 EEPROM、音、入力、追加機能

| 項目 | 根拠と候補 |
|---|---|
| EEPROM | `memory.rs`、`peripherals/eeprom.rs`、`lib.rs`。1 KiB。EEAR/EEDR/EECR、read/writeの制御と書込み許可の時刻をモデル化する。ゲームごとの `.eep` に保存し、欠損時はFF、長さ違いはエラーとする案。dirty管理、明示保存、正常終了時保存、同一ファイルの同時起動、書込み失敗を設計する。SAVESYSをゲームの保存領域の代わりにしない |
| 音 | `lib.rs` の説明とGPIO処理はTimer3 CTC、Timer1 CTC、PC6/PB5の直接反転を扱う。Timer4利用もタイマーとGPIOの出力経路で検査する。音符APIに変換するだけでは高速GPIOやPWMを失うため、AVR時刻付きの端子変化をPCM標本に積分し、SigmaのPCMストリームへ出す案。Arduboyの2端子間の差をモノラルにする。Rust版の左右別出力は参照版独自の表現であり実機スピーカー配置とは分ける |
| ボタン | `lib.rs::set_button` はactive-low、上PF7、下PF4、左PF5、右PF6、A=PE6、B=PB4。DDRx/PORTx/PINxとpull-up、出力状態との合成が必要。PC側は矢印＋Z/X、Esc終了、F5リセットを推奨。割当変更を可能にする |
| FX | `peripherals/fx_flash.rs` はW25Q128、16 MiB、PD1 CS、03/0B読出し、9F ID、AB復帰、05 status、B9 sleep、06/04 write enable/disable、02 page program、20 sector eraseを持つ。初期版から外し、非FXゲームの受け入れ後に追加する案。採用時はデータとセーブ領域、配置アドレス、永続化、SPIのOLEDとの選択を決める |
| USB serial | `lib.rs` はUSBレジスタと送出バッファを持つ。初期はUSB機器としてホストに接続せず、起動待ちを解く最小状態と送信ログまで。実USB列挙、書込み器、ブートローダは対象外とする案。待ちループが残ったらPC/I/Oログで調べる |
| LED | `lib.rs` はGPIOからLED状態を扱う。初期は状態を保持・snapshotに出力し、RGBのUI表示は後段とする案。PWM輝度は時間積分を別途検査する |

### 2.5 ファイル形式

`.hex` はIntel HEXとして、レコード長、checksum、EOF、アドレス拡張、32 KiB境界、重複・空白領域を検査する。Rust版の `hex.rs` を比較対象にする。任意のELF/DWARFは初期には不要である。

`.arduboy` はZIPであり、`arduboy_file.rs` はstored/deflateを展開してinfo.json、hex、FX bin/saveを取り出す。Sigmaの `docs/WORD_REFERENCE.md` に公開ZIP展開ワードは見つからず、`src` のinflateはPNG読込み内部の `graphics_decode.zig` にある。PNG内部の展開器があることとForthからZIPを読めることは別である。

推奨は初期の入力を展開済みhexに限り、利用者が事前にZIPを展開することとする。代案は外部変換スクリプトを別成果物にするか、ForthでZIP/deflateを作ることである。storedだけの対応は一般的な圧縮済みarduboyを読めないため、対応済みとは呼ばない。アーカイブ対応を加える際はサイズ上限、CRC、entry選択、パス逸脱、複数ゲーム、info.jsonの参照名を設計する。

## 3. Sigmaの既存機能と不足

| 分野 | 既存の機能と利用例 | Arduboy側で作るもの |
|---|---|---|
| 描画 | `REQUIRE-GRAPHICS`、GFX-INIT、GFX-INDEXED、SHOW、WINDOW-SIZE。`emu/chip8/chip8.fs::CH8-PAINT` は色番号の画面を一括転送する | GDDRAM、コマンド状態、128×64への展開、整数倍率の表示 |
| 画素転送1000/1001 | `GFX-RGB ( addr w h stride x y key -- )` は4バイト画素。既存GFX-INDEXEDで白黒には足りる。1001の背景試作では8画素を表でまとめて展開した | SSD1306の縦8ビットから行順への転置。1001のNES型タイル処理をそのまま必要としない |
| 音998/999 | REQUIRE-AUDIO、PCM-OPEN/WRITE/QUEUED/WAIT/STOP/CLOSE/UNDERRUNS。CHIP-8は48 kHz monoのPCMを送る | AVR端子出力の標本化、音量、無音時も進む時刻、partial write・中断・再開・終了時の後始末。既存PSG等はAVRの代わりにならない |
| 入力997 | KEY-HELD?、INKEY、K-UP等。物理入力はSCAN-INPUT?、SCAN-SUPPORTED?、SCAN-HELD?、KEY-EVENT、KEY-RESYNC。対応backendは別に確認する | 6ボタンのGPIO合成、設定、フォーカス喪失時の解放。初期はCHIP-8同様KEY-HELD?でも足りる案 |
| ファイル | OPEN-FILE、READ-FILE、WRITE-FILE、CLOSE-FILE、NEXT-ARG。CHIP-8 README/specはROMをNEXT-ARGで消費してheadlessとUIを分離する | hex parser、EEPROMファイル、診断、任意のZIP層 |
| 時間・実行 | UTIME、MS、EXECUTE、CREATE/ALLOT、byte/cell読書き。CHIP-8は16667µsのtickと遅れの再同期を持つ | AVR命令decode、bus、IRQ、仮想サイクル、実時間への同期。遅れを理由にAVR内部のサイクルを捨てない |
| 保存アプリ | SAVESYS、APP-ENTRY!。`docs/SAVED_APPLICATION_STARTUP_IMPLEMENTATION.md` | 起動時の画像・音声handle再作成、ALLOCATE領域の再確保。辞書保存とEEPROM/状態保存は別にする |

根拠は `docs/WORD_REFERENCE.md`、`docs/EMULATOR_CORE_PLAN.md` の997–1001と保存アプリの節、`emu/chip8/chip8.fs` と `README.ja.md` である。古い計画段落には未実装時点の記述が残るため、追記の実装記録と公開ワードを優先した。利用機能の存在は確認したが、今回の既存バイナリで画像・音声・入力の実機動作を試してはいない。

## 4. 速度試作と測定

### 4.1 予算と試作の内容

16 MHzでは毎秒16,000,000 AVRサイクル、60 Hzの1フレームに約266,667サイクルを処理する必要がある。命令数とサイクル数は同じではない。今回の試作は1周34命令・47サイクル、1命令平均約1.382サイクルである。この構成を実時間で進めるには約1,157万命令/秒が要る。

`bench/avr-bench.fs` は65536 entryのexecution token表を起動時に作る。表は8バイトcellでは512 KiBであり、ROMの各16ビットopcodeからハンドラへ直接移る。実行時にPCからopcodeをfetchし、レジスタ番号・即値を取り出す。第2案は同じmask判定器を毎命令実行し、表を使わない。表の構築時間は計時に含めない。

実装した集合はNOP、LDI、MOV、ADD、ADC、SUB、SUBI、CP、CPI、AND、OR、EOR、INC、DEC、LSR、ROR、BRBS/BRBC（BREQ/BRNEを含む全SREG bit）、RJMP、RCALL、RET、LD/ST X+、LDS/STS、IN/OUT、PUSH/POPである。算術・論理・shiftのSREG更新と非更新ビットの保持、branchの1/2サイクル、2ワードLDS/STS、AVRスタックのbyte順を処理する。未知命令はTHROWする。

手組みのループには即値、算術、比較、論理、shift、SRAM転送、I/O、stack、成立するBREQ、RCALL/RET、RJMPを混ぜた。初期値を毎周セットし、100,000周、3,400,000命令、4,700,000サイクルを実行する。ループは全対応命令の頻度を代表するものではなく、実ゲームの速度は未測定である。

タイマーフックは各命令のサイクルを加え、256でwrapし、overflow件数を増やす。4個のタイマー、分周、WGM、IRQ配送は含まない。メモリは64 KiBの平坦な配列で、SREGのIN/OUTのみ特別扱いする。SPのI/O alias、SPI、EEPROM、画面、PCM、入力、実際の32u4 bus制約は未実装である。したがって結果はフルエミュレータの性能保証ではない。

### 4.2 正しさの確認

`bench/avr-check.fs` は次を検査する。独立したPythonの符号付き算術・桁上がり・半桁借りから期待hashを作る補助を `.work/arduboy/oracle-addsub.py` と `oracle-unary.py` に残した。これは参照Rust版の実行結果ではない。

- ADD/ADC/SUB系フラグ：全8ビット入力対とcarryの262,144ケース。I/T保持も含め、Forthの結果列の32ビットrolling hashを照合した。
- INC/DEC/LSR/ROR：全入力×全初期SREGの262,144ケースでフラグ列hashを照合した。結果レジスタ全ケースの独立比較は未実施であり、ループ内の結果確認とは区別する。
- BRBS/BRBC：全SREG×8bit×2条件の4,096ケースで負offset、成立・不成立のPCとサイクルを直接検査した。
- 追加検査では、ループ1周後の全32レジスタと64 KiBデータ配列を独立した期待画像とbyte単位で比較し、SREG=2、47サイクルも直接照合して成功した。
- ループ1周と測定各回：R16/R20/R21/R22/R23=160、SRAM[512]/[768]=160、SP=2815、PC=0、データスタック深さ0。hookありはoverflow×256+remainder=累積サイクルも確認した。1周34命令・47サイクルを出力した。

hash照合には衝突の可能性があり、全命令・全operandの適合試験を代替しない。MOV/論理/転送等の全境界網羅、正offset branch、stack境界、割込みは今後のCPU試験で扱う。生ログは `.work/arduboy/correctness.txt` にある。

### 4.3 測定条件と全結果

主結果は `zig build -Doptimize=fast --prefix .work/arduboy/fast` で作った `.work/arduboy/fast/bin/sigma.exe` による。`scripts/build-release.ps1` も `-Doptimize=fast` を指定する。Claude が2026-11-28にビルド・測定した実行体は約2.6 MB、ソースはHEAD `1476448` と同じでローカル変更なしの状態である。このソース同一性は今回Gitで再確認していない。

各条件3回の生ログを確認した。計時はForthのUTIME（epoch基準のµs、下位cell）で実行ループだけを囲み、初期化・表構築・検証・出力を除く。単調時計ではないため時計補正を受ける可能性がある。ホストの他アプリによる影響は分離できていない。

- mode 0：表dispatch、フックなし。
- mode 1：表dispatch、毎命令のタイマーフックあり。
- mode 2：maskを順に調べるdispatch、フックなし。

再現時はPowerShellからリポジトリルートで、必ず `-Doptimize=fast` の実行体を使う。以下はビルド、正しさの再検証、各modeを別processで3回測るコマンドである。今回はこれらを再実行せず、既存ログを照合した。

```powershell
zig build -Doptimize=fast --prefix .work/arduboy/fast
./.work/arduboy/fast/bin/sigma.exe emu/arduboy/bench/avr-check.fs
foreach ($run in 1..3) {
    foreach ($mode in 0..2) {
        ./.work/arduboy/fast/bin/sigma.exe emu/arduboy/bench/avr-bench.fs -e "$mode AB-MEASURE BYE" | Tee-Object -FilePath ".work/arduboy/fast-run-$run-mode-$mode.txt"
    }
}
```

| 条件 | 回 | µs | 命令/秒 | サイクル/秒 | 16 MHz比 |
|---|---:|---:|---:|---:|---:|
| 表・hookなし | 1 | 832,351 | 4,084,815 | 5,646,656 | 35.29% |
| 表・hookあり | 1 | 918,839 | 3,700,321 | 5,115,150 | 31.97% |
| mask判定・hookなし | 1 | 1,352,828 | 2,513,253 | 3,474,203 | 21.71% |
| 表・hookなし | 2 | 828,009 | 4,106,235 | 5,676,266 | 35.48% |
| 表・hookあり | 2 | 916,926 | 3,708,041 | 5,125,822 | 32.04% |
| mask判定・hookなし | 2 | 1,377,811 | 2,467,682 | 3,411,208 | 21.32% |
| 表・hookなし | 3 | 830,359 | 4,094,614 | 5,660,202 | 35.38% |
| 表・hookあり | 3 | 905,832 | 3,753,455 | 5,188,600 | 32.43% |
| mask判定・hookなし | 3 | 1,331,562 | 2,553,392 | 3,529,689 | 22.06% |

全9回でvalidation=PASS、depth=0であった。サイクル/秒の中央値は順に5,660,202、5,125,822、3,474,203。hookありの中央値は16 MHzの約32.04%であり、16,000,000 / 5,125,822 ≒ **3.12倍**の高速化が必要である。表示・音声・実タイマーを加える前の値である。

表はmask判定より中央値で約1.63倍速く、hook追加で表dispatchのthroughputは約9.4%低下した。軽いhookを全部省いても35.38%なので、それだけでは実時間に届かない。生ログは `.work/arduboy/fast-run-1-mode-0.txt` から `fast-run-3-mode-2.txt` にある。平均化せず全回を示した。

旧測定は `zig-out/bin/sigma.exe` のDebugビルド（15,864,320 byte、sigma.pdbを伴う）であり、hookあり中央値519,625サイクル/秒、約3.25%、必要速度約30.8倍だった。Claude が sigma.pdb の存在と最適化ビルドとの大きさの差から確認した。この値は経緯を残すための注記に限り、方式の判断には使わない。


### 4.4 方式の比較と推奨

| 方式 | 利点 | 制約と判断 |
|---|---|---|
| (a) Forthだけ、実時間未達を許す | 2026-11-19の外部スクリプト方針を保てる。命令・周辺回路の学習と比較に使える | 速度低下を明示する。仮想時計と音程をどう扱うかも決める必要がある |
| (b) Forthを最適化する | hot wordのlocals削減、レジスタ別dispatchの特殊化、decode済みoperand、基本block、cycle差分によるタイマー更新で繰返し処理を減らせる | ※推測：細粒度の処理削減を積み重ねる余地はあるが、各手法の倍率は未測定で、合計3.12倍以上を得られる根拠はない。自己書換えを認める場合はdecode cache失効も必要である |
| (c) SigmaのZig本体にnative AVR coreを加える | 大量の細粒度Forth実行をまとめられる | 既決の外部スクリプト方針を変更する利用者判断が必要。今回の範囲では実装しない。native版の速度も未測定であり、16 MHzを保証しない |

推奨は(b)の追加評価を先に行うことである。Debugの約30.8倍という不足から、最適化ビルドでは約3.12倍に評価が変わったため、外部Forth方針を保った最適化を測る価値がある。ただし、純Forthによる実時間プレイは実証されていない。

※推測：SPI/OLED、実際のTimer0/1/3/4、割込み、音声生成と表示を加えると、同じAVRサイクル数を処理するホスト時間は増える。追加負荷はゲームのI/O頻度、タイマーモード、音声方式に依存するため、実測に基づく割合はまだ出せない。計画用の仮定としてmode 1に対し時間が25～100%増える場合を置くと、到達率は約25.6～16.0%、必要な高速化は約3.9～6.2倍になる。この範囲は予測の上下限ではなく感度を見るための仮定であり、これ以上の負荷も否定できない。

※推測：hot wordのlocalsを減らせば変数の出し入れを、レジスタ別に特殊化したハンドラなら毎命令のoperand抽出を減らせる。一方、表dispatchの改善1.63倍は既に主結果に含まれており、今後の倍率に再加算できない。タイマーを毎命令呼ぶ代わりにcycle差分で次のイベントまでまとめて進めれば周辺処理の増加を抑えられるが、I/OアクセスとIRQ受付の境界は維持する必要がある。これらは局所的な負担の削減であり、Forthの命令実行・メモリアクセス全体をnative化する効果と同一視できない。

追加評価ではまず参照試作との状態・サイクル一致を保ってCPU側の改善を測り、次に実タイマー・IRQ・SPI/OLED・音声を含む代表ROMで全体速度を測る。未達でも低速を許容するなら(a)、実時間が必須で未達なら(c)のnative AVR coreを検討する。※推測：native coreはCPU・bus・イベント進行をまとめることでForth語呼出しの負担を広く減らせるが、native版も未測定であり、実時間到達を保証しない。

`docs/SNES_DSP_NATIVE_DESIGN.md` の前例では、状態・キュー・APIをForth側に保ち、同期的な有界kernelだけをnativeへ分け、参照Forthとの全状態比較を行った。AVRでも同じ分離が候補になるが、任意I/OのたびのForth callbackは速度を損なう可能性がある（※推測）。CPUだけをnativeにするか、busとイベント進行まで含めるかは別の設計項目である。ホストpointerを公開せず、借用buffer、状態commit、中断、SAVESYS ABI、無機能ビルドを定義する必要がある。

## 5. 決める項目

各行に選択肢、推奨、その理由を記す。例として「1-1は②、2-1は①」のように回答できる。

| 番号 | 項目 | 選択肢 | 推奨と理由 |
|---|---|---|---|
| 1-1 | 速度と実装方式 | ①Forthのみで低速を許容 ②Forth最適化の追加評価 ③方針を変更してnative coreを検討 | ②。最適化ビルドでは約32.04%・必要約3.12倍なので、外部Forthの改善余地を追加測定する。全周辺込みの実時間プレイは未実証。未達時は低速を許せば①、実時間必須なら③を検討する |
| 1-2 | 初期の機種とCPU範囲 | ①32u4と2.1節の通常ゲーム命令 ②FXや他AVRも同時 | ①。32u4だけでも周辺機器の検査量があるためである |
| 1-3 | 非対応命令・周辺アクセス | ①診断して停止 ②警告して続行 ③黙って無視 | ①。起動失敗の原因と誤動作を追えるためである。既知の機能近似は個別に宣言する |
| 2-1 | サイクル精度 | ①命令サイクル＋イベント境界 ②各クロックの詳細再現 ③フレーム単位の近似 | ①。タイマーと音の時間を保ちつつ毎clock処理を避けるためである |
| 2-2 | タイマー | ①0/1/3/4を段階的に検査 ②0だけ先行 | ①。音や時間待ちがTimer0だけとは限らないためである |
| 2-3 | PLL/ADC | ①lock・変換完了は機能近似、seed固定可能 ②安定・変換時間まで再現 | ①。まず起動と乱数seedの再現性を得るためである |
| 3-1 | OLED対応 | ①基本addressingと反転・向き・on/off ②Rust版相当の読み飛ばし ③scrollも同時 | ①。コマンドの意味を省いて動くゲームだけに依存しないためである。scrollは後段とする |
| 3-2 | 音の表現 | ①端子差からmono PCM ②Rust版同様の端子別stereo ③初期は無音 | ①。GPIO反転とタイマー出力を共通の時刻で扱い、1つのスピーカーの差動出力に対応させるためである |
| 3-3 | ボタン | ①矢印＋Z/X、変更可 ②固定割当 ③最初からgamepad必須 | ①。6ボタンを既存入力で扱えるためである。gamepadは追加可能とする |
| 4-1 | EEPROM保存 | ①ゲーム別eep＋明示/正常終了保存 ②共通1ファイル ③保存なし | ①。ゲーム間の上書きを防ぎ、通常の再起動後も保持するためである。ファイル名衝突と同時起動の方針は詳細設計で定める |
| 4-2 | FX flash | ①初期対象外 ②読出しだけ ③save/eraseまで同時 | ①。16 MiB、SPI選択、別の永続化を初期受け入れから分けるためである |
| 4-3 | 入力形式 | ①展開済みhex ②外部変換も提供 ③Forth ZIP/deflate | ①。公開ZIP語がなく、CPU評価から圧縮処理を分けるためである |
| 4-4 | USB serial | ①起動に必要な最小状態＋送信ログ ②完全USB ③完全対象外 | ①。ゲームの待機と診断を扱い、ホストUSB接続は要求しないためである |
| 4-5 | LED | ①状態/snapshotのみ先行 ②RGB UI/PWMも同時 ③無視 | ①。CPU側の状態を失わずUIを後段にできるためである |
| 5-1 | 比較検証 | ①自作test＋許可後Rust headless比較 ②自作testのみ | ①。独立した実装との比較で配線や時刻の誤りを見つけるためである。Rust実行は別途許可を受ける |
| 5-2 | 起動・配布 | ①外部fsから先行、後にSAVESYS ②最初から保存実行体を配布 | ①。仕様変更の多い段階で保存画像の互換と配布を増やさないためである |

## 6. テストの進め方

1. 窓・音声出力を開かないCPU実行語を作り、命令ごとのレジスタ、SREG、PC、SP、メモリ副作用とサイクルを検査する。全operand、carry-chain、32bit命令skip、分岐正負、stack上下限、割込み受付とRETIを含める。
2. 自作ROMでTimer0/1/3/4の分周・WGM・overflow/compare・IRQ優先順位、PLL待ち、ADC完了、EEPROM許可窓、SPI完了・CS/DCを個別に検査する。test ROMの期待値は参照実装だけに依存させない。
3. SSD1306はコマンド列と1024byteのGDDRAM、展開後8192画素を検査する。Rust版が省いた機能の不一致は参照側の仕様差として切り分ける。snapshotが同じでも割込みや音が正しいとは言えない。
4. 利用者の許可を得てからRust版の `--headless --frames N --snapshot F` を同じROM、seed、初期EEPROM、ボタン投入時刻で実行し、画面・CPU状態・I/Oイベントを比較する。READMEではsnapshotは指定frameの表示を出力する。形式の正規化方法は実出力を見て決める。今回、このコマンドは実行していない。
5. ゲームROMは許可された自作・再配布可能なものを選び、ライセンスを記録する。ネットから取得する場合も事前許可を受ける。動作ゲーム一覧と未対応アクセスを残す。
6. PCMは無音sinkでcycleからsampleへの変換、端子差、partial write、queue満杯、underrun、停止/再開を検査した後、実際の入力・画面・音を利用者と確認する。Windows/Linux/Macの実機結果は分ける。最後に選定ゲームを使い、CPU＋全周辺＋表示＋音声込みの速度を別途測る。

## 7. ライセンスと再利用

Rust版 `LICENSE-MIT` は `Copyright (c) 2025 arduboy-emu contributors`、`Cargo.toml` はMITまたはApache-2.0の選択である。MITを選ぶ場合はコードの翻訳・移植・変更と配布が可能であり、取り込む相当部分に著作権表示と許諾全文を付す。Apache-2.0を選ぶ場合は同ライセンスの添付、変更表示、該当NOTICEの保持等を確認する。著者が利用者であっても、配布時の通知は省かない。

再利用候補はopcode mask、CPU/周辺の状態遷移、テストである。取り込むファイル・元版・選択したライセンス・変更箇所を `emu/arduboy/` 内の通知文書に記録する案である。miniz_oxide、serde等の依存物やゲームROMの権利はRustプロジェクト本体と別なので、一括して同じ許諾とは扱わない。今回のbenchは独自のForth試作であり、Rustコード本文・依存ライブラリ・ゲームROMをコピーしていない。命令分類と動作の確認には上記Rustソースを参照した。

## 8. 決定後の作業分割案

| 順 | 作業 | 完了の判断 |
|---|---|---|
| 1 | 5章の回答を決定記録に残す。CPU/周辺/loader/UIの責務と状態形式を設計する | 初期範囲、精度、速度目標と対象外が確定している |
| 2 | 1-1で②ならhot wordのlocals削減・レジスタ別dispatch・cycle差分のevent batchingの追加試作と全周辺込みの測定、③ならnative境界設計と有界kernelの別評価 | 参照Forthとの状態一致と、承認を得た測定から採否を決める。未達なら実時間を要件から外すか方式を再検討する |
| 3 | CPUとbus、hex loader、headless runner | 2.1節の確定命令とSREG、stack、skip、例外の試験が通る |
| 4 | Timer0/1/3/4、IRQ、PLL、ADC、SPI、EEPROM | 自作ROMのcycle/state/IRQと保存失敗の試験が通る |
| 5 | SSD1306、GPIO入力、音のPCM変換 | headless画面と波形検査が通る |
| 6 | 許可後のRust比較とゲームの互換検証 | 不一致を解析し、宣言した対象ゲームの証拠を残す |
| 7 | UI、設定、EEPROM保存、SAVESYS起動、OS別受け入れ | 画面・操作・実聴・停止/再開と全体速度を確認する |
| 8 | FX/arduboy ZIP/LED表示等の追加判断、利用者向け日英文書 | 初期版の合格とは別の範囲で管理する |

この分割は登録案であり、tqueへの追加・完了更新は行っていない。README.md/README.ja.mdとエミュレータ本体は今回の成果物に含めない。

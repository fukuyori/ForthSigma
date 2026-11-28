# Arduboy エミュレータ仕様書

作成日：2026-11-28  
管理タスク：tque 1482（後続実装・検査：1483〜1488）

## 1. 対象、根拠、範囲

ForthSigma の全機能版上で動く外部 Forth スクリプトを `emu/arduboy/` に作る。対象は ATmega32u4、16 MHz、SSD1306 128×64 の通常の Arduboy だけである。`docs/DECISIONS.md`「Arduboyエミュレータの方針」（2026-11-28）と [STUDY.md](STUDY.md) 5章の承認済み16項目を優先する。1-1は②、残りは①である。

Forth 側の最適化を試し、全周辺込みで測る。実時間未達時に低速を最終仕様として採用することも、Sigma 本体へ native core を追加することも、ここでは決めない。測定後に利用者が決める。実時間到達・全ゲーム互換・電気的挙動の再現を保証する文書ではない。

構成・公開入口・診断・仕様選択の書き方は `emu/logo/docs/SPECIFICATION.md`、状態・窓なし検査・入力・PCM の分離は `emu/chip8/docs/SPECIFICATION.md` と両実装に合わせる。CHIP-8 の `CH8-` 接頭辞と LOGO の専用語彙・予約接頭辞を参考にする。

読取り専用の参考実装は `D:/home/source/rust/arduboy-emu` の `crates/core/src/{opcodes,cpu,memory,lib,hex,display}.rs` と `peripherals/*.rs` である。本タスクでは実行していない。Rust 版の多機種対応、未対応アクセスの無視、端子別stereoを要件にはしない。Sigma 語の根拠は `docs/WORD_REFERENCE.md` と `docs/USER_MANUAL.md` である。実装の成功と設計上の規則を区別する。

対象外は FX flash、`.arduboy` ZIP 展開、ELF/DWARF、他のAVR・Gamebuino・別配線の自動判別、USBホスト接続・実列挙・書込み器・ブートローダ、flash自己書換え、watchdog reset、外部クロック・入力捕獲、OLED scroll、LEDの窓表示・PWM輝度積分、gamepad、巻戻し・ゲーム全状態の永続保存である。SAVESYSは後段とし、最初はスクリプトから動かす。配布物・インストーラーは本タスクでは作らない。

## 2. ファイル、名前、責務

以下は後続実装の配置であり、現存実装を表すものではない。includeはリポジトリ直下を作業ディレクトリとして解決する。

| ファイル | 責務 | 内部語の接頭辞 |
| --- | --- | --- |
| `state.fs` | 全状態の領域、初期化、検査用コピー | `AB@STATE-` |
| `bus.fs` | data/flash読書き、I/O dispatch、同期、範囲検査 | `AB@BUS-` |
| `cpu.fs` | decode、命令、flag、stack、IRQ受付 | `AB@CPU-` |
| `peripherals/timers.fs` | Timer0/1/3/4、分周・比較・出力 | `AB@TIMER-` |
| `peripherals/irq.fs` | pending/mask、優先順位、次イベント | `AB@IRQ-` |
| `peripherals/pll-adc.fs` | PLL近似、ADC、seed | `AB@PLL-`、`AB@ADC-` |
| `peripherals/spi.fs` | SPI完了、CS/DC、OLED配送 | `AB@SPI-` |
| `peripherals/eeprom.fs` | EEPROM許可窓・busy・dirty | `AB@EE-` |
| `peripherals/gpio.fs` | DDR/PORT/PIN、ボタン、LED、端子選択 | `AB@GPIO-` |
| `peripherals/usb.fs` | 最小USB register、送信記録 | `AB@USB-` |
| `ssd1306.fs` | command parser、GDDRAM、画素展開 | `AB@OLED-` |
| `sound.fs` | 端子差、PCM積分、sink、実出力 | `AB@SOUND-` |
| `loader.fs` | HEX、EEPROMファイル、パス | `AB@LOAD-` |
| `ui.fs` | 窓、入力設定、pacing、終了、資源回収 | `AB@UI-` |
| `arduboy.fs` | 全体読込み、公開API、引数、AB-MAIN | `AB@MAIN-` |
| `tests/run.fs`、`tests/test-*.fs` | 窓なし検査 | `AB@TEST-` |
| `tests/roms/` | 自作ROMの手組みデータ・期待値・AVRソース | — |
| `bench/`、`docs/` | 有界測定、仕様・根拠・結果 | — |
| `README.md`、`README.ja.md` | 利用手順、後段の保存アプリ作成方法 | — |
| `CREDITS.md`、`LICENSE-MIT-RUST.txt` | 移植元・変更箇所とMIT全文 | — |

全定義を `ARDUBOY` 語彙に置く。公開語は `AB-`、補助語・定数・領域は予約接頭辞 `AB@` とする。`CPU`、`RESET`、`STEP`、`IN`等をFORTH/Rootへ定義しない。入口だけが語彙を作り、子ファイルは定義先を変えない。既存の同名語彙・予約名との衝突は上書きせずエラーにする。

読込み前に `GET-ORDER`、`GET-CURRENT`、`BASE @` を専用領域へ保存し、正常・失敗とも `SET-ORDER`、`SET-CURRENT`、`BASE !` で復元する。GRAPHICS/AUDIOの語は内部別名へ結び、利用者の検索順に依存させない。単一インスタンスとし、並行実行・実行中の再読込みは対象外である。

## 3. 状態とreset

アドレスは特記しない限り16進のdata byte addressである。flashは **32 KiB = 32768 byte = 16384 word** であり、32K個の16bit wordではない。PCはword、LPMのZとHEXはbyte単位である。

| 状態 | 表現・正本 | 起動時／reset |
| --- | --- | --- |
| R0〜R31 | data `0000..001F` の32 byte | 0 |
| I/O | `0020..005F`、extended I/O `0060..00FF` | 下記以外0 |
| SRAM | `0100..0AFF` の2560 byte | 0 |
| flash | 32768 byte、fetch時にlittle endianでword化 | LOAD時FF埋め後配置、resetで保持 |
| EEPROM | 別領域1024 byte | 初回FF、正常eepで置換、resetで保持 |
| PC | cell、`0000..3FFF` word | 0、bootloader経由なし |
| SP | 16bit、SPL=`5D`/SPH=`5E`のalias | `0AFF` |
| SREG | byte、`5F`と同一正本 | 0、bit7..0=I/T/H/S/V/N/Z/C |
| cycle | 非負64bit累積AVR cycle | 0 |
| CPU制御 | sleep mode、停止理由、命令開始PC | awake、停止なし |
| IRQ | sourceごとのflag/mask、vector、SEI遅延 | flag/mask/遅延0 |
| timer | counter/TOP/OCR/buffer/方向/分周残余/同期cycle/出力latch | counter/control/残余0、停止、OCR4C=FF |
| PLL/ADC/SPI/EE | register、完了期限、read latch、許可期限、busy内容 | 0、処理なし |
| GPIO | DDR/PORT、外部入力、実効端子、ボタン6bit、LED | DDR/PORT0、ボタン解放、LED消灯 |
| OLED | 1024byte GDDRAM、parser、address/mode、表示属性 | RAM0、page mode、column/page0、範囲全体、off、通常向き/表示、contrast7F |
| 音声 | 端子、sample位相、積分値、生成sample数 | 0 |
| host | 画像/PCM/file handle、実時計基準、キー設定、dirty | 起動ごとに再作成、キー既定、dirty偽 |

dataは2816byteとし、register/SREG/SPの別コピーで不整合にしない。X=R27:R26、Y=R29:R28、Z=R31:R30である。CPUキャッシュはI/Oから直ちに同じ値が読める必要がある。範囲外data/flash、未実装I/Oは診断停止する。平坦な64KiB RAMで代用しない。未実装I/Oへのゼロ書込みも拒否し、明記した状態保持専用registerだけを例外とする。

reset値は本エミュレータの決定的初期値であり、実機の未定義SRAM値の再現ではない。`AB-RESET`/F5はflash、EEPROM、EEPROM dirty、設定を保持し、他を表へ戻す。未完了EEPROM書込みは取消し、完了済みbyteは保持する。PCM queueを破棄し実時計基準を張り直す。ボタンを一旦解放し次pollで反映する。

永続化するゲーム状態はEEPROMだけである。CPU/RAM/OLED/timer/乱数進行は保存しない。検査snapshotは比較用コピーであり再開用save stateではない。機械状態、設定seed、cycle、I/O、周辺、GDDRAM、PCM位相、USB列を含め、host pointerやpaddingを含めない。

## 4. CPU

### 4.1 最初の命令集合

判定は `(opcode AND mask) = value`。mask/valueは16進、32bit命令は先頭wordを判定する。`—`はSREG不変、列挙したflagだけを更新する。以下にない命令は非対応である。Rust `opcodes.rs`/`cpu.rs`の分類を参照したが、未知命令の無操作処理は採用しない。

| mnemonic / 形式 | mask | value | word | cycle | flag |
| --- | --- | --- | ---: | --- | --- |
| NOP | FFFF | 0000 | 1 | 1 | — |
| ADD | FC00 | 0C00 | 1 | 1 | H S V N Z C |
| ADC | FC00 | 1C00 | 1 | 1 | H S V N Z C |
| SUB | FC00 | 1800 | 1 | 1 | H S V N Z C |
| SUBI | F000 | 5000 | 1 | 1 | H S V N Z C |
| SBC | FC00 | 0800 | 1 | 1 | H S V N Z C |
| SBCI | F000 | 4000 | 1 | 1 | H S V N Z C |
| CP | FC00 | 1400 | 1 | 1 | H S V N Z C |
| CPC | FC00 | 0400 | 1 | 1 | H S V N Z C |
| CPI | F000 | 3000 | 1 | 1 | H S V N Z C |
| CPSE | FC00 | 1000 | 1 | 1/2/3 | — |
| AND | FC00 | 2000 | 1 | 1 | S V N Z |
| ANDI | F000 | 7000 | 1 | 1 | S V N Z |
| OR | FC00 | 2800 | 1 | 1 | S V N Z |
| ORI | F000 | 6000 | 1 | 1 | S V N Z |
| EOR | FC00 | 2400 | 1 | 1 | S V N Z |
| COM | FE0F | 9400 | 1 | 1 | S V N Z C |
| NEG | FE0F | 9401 | 1 | 1 | H S V N Z C |
| INC | FE0F | 9403 | 1 | 1 | S V N Z |
| DEC | FE0F | 940A | 1 | 1 | S V N Z |
| ADIW | FF00 | 9600 | 1 | 2 | S V N Z C |
| SBIW | FF00 | 9700 | 1 | 2 | S V N Z C |
| MUL | FC00 | 9C00 | 1 | 2 | Z C |
| MULS | FF00 | 0200 | 1 | 2 | Z C |
| MULSU | FF88 | 0300 | 1 | 2 | Z C |
| FMUL | FF88 | 0308 | 1 | 2 | Z C |
| FMULS | FF88 | 0380 | 1 | 2 | Z C |
| FMULSU | FF88 | 0388 | 1 | 2 | Z C |
| MOV | FC00 | 2C00 | 1 | 1 | — |
| MOVW | FF00 | 0100 | 1 | 1 | — |
| LDI | F000 | E000 | 1 | 1 | — |
| LDS Rd,k | FE0F | 9000 | 2 | 2 | — |
| STS k,Rr | FE0F | 9200 | 2 | 2 | — |
| LD Rd,X | FE0F | 900C | 1 | 2 | — |
| LD Rd,X+ | FE0F | 900D | 1 | 2 | — |
| LD Rd,-X | FE0F | 900E | 1 | 2 | — |
| LD Rd,Y | FE0F | 8008 | 1 | 2 | — |
| LD Rd,Y+ | FE0F | 9009 | 1 | 2 | — |
| LD Rd,-Y | FE0F | 900A | 1 | 2 | — |
| LDD Rd,Y+q | D208 | 8008 | 1 | 2 | — |
| LD Rd,Z | FE0F | 8000 | 1 | 2 | — |
| LD Rd,Z+ | FE0F | 9001 | 1 | 2 | — |
| LD Rd,-Z | FE0F | 9002 | 1 | 2 | — |
| LDD Rd,Z+q | D208 | 8000 | 1 | 2 | — |
| ST X,Rr | FE0F | 920C | 1 | 2 | — |
| ST X+,Rr | FE0F | 920D | 1 | 2 | — |
| ST -X,Rr | FE0F | 920E | 1 | 2 | — |
| ST Y,Rr | FE0F | 8208 | 1 | 2 | — |
| ST Y+,Rr | FE0F | 9209 | 1 | 2 | — |
| ST -Y,Rr | FE0F | 920A | 1 | 2 | — |
| STD Y+q,Rr | D208 | 8208 | 1 | 2 | — |
| ST Z,Rr | FE0F | 8200 | 1 | 2 | — |
| ST Z+,Rr | FE0F | 9201 | 1 | 2 | — |
| ST -Z,Rr | FE0F | 9202 | 1 | 2 | — |
| STD Z+q,Rr | D208 | 8200 | 1 | 2 | — |
| PUSH | FE0F | 920F | 1 | 2 | — |
| POP | FE0F | 900F | 1 | 2 | — |
| IN | F800 | B000 | 1 | 1 | — |
| OUT | F800 | B800 | 1 | 1 | —（宛先SREGなら全bit置換） |
| LPM R0,Z | FFFF | 95C8 | 1 | 3 | — |
| LPM Rd,Z | FE0F | 9004 | 1 | 3 | — |
| LPM Rd,Z+ | FE0F | 9005 | 1 | 3 | — |
| LSR | FE0F | 9406 | 1 | 1 | S V N Z C |
| ASR | FE0F | 9405 | 1 | 1 | S V N Z C |
| ROR | FE0F | 9407 | 1 | 1 | S V N Z C |
| SWAP | FE0F | 9402 | 1 | 1 | — |
| BST | FE08 | FA00 | 1 | 1 | T |
| BLD | FE08 | F800 | 1 | 1 | — |
| SBI | FF00 | 9A00 | 1 | 2 | — |
| CBI | FF00 | 9800 | 1 | 2 | — |
| RJMP | F000 | C000 | 1 | 2 | — |
| RCALL | F000 | D000 | 1 | 3 | — |
| JMP | FE0E | 940C | 2 | 3 | — |
| CALL | FE0E | 940E | 2 | 4 | — |
| IJMP | FFFF | 9409 | 1 | 2 | — |
| ICALL | FFFF | 9509 | 1 | 3 | — |
| RET | FFFF | 9508 | 1 | 4 | — |
| RETI | FFFF | 9518 | 1 | 4 | I=1 |
| BRBS | FC00 | F000 | 1 | 1/2 | — |
| BRBC | FC00 | F400 | 1 | 1/2 | — |
| SBRC | FE08 | FC00 | 1 | 1/2/3 | — |
| SBRS | FE08 | FE00 | 1 | 1/2/3 | — |
| SBIC | FF00 | 9900 | 1 | 1/2/3 | — |
| SBIS | FF00 | 9B00 | 1 | 1/2/3 | — |
| BSET s | FF8F | 9408 | 1 | 1 | 指定bit=1 |
| BCLR s | FF8F | 9488 | 1 | 1 | 指定bit=0 |
| SLEEP | FFFF | 9588 | 1 | 1 | — |
| WDR | FFFF | 95A8 | 1 | 1 | —（watchdog無効の無操作） |
| BREAK | FFFF | 9598 | 1 | 0 | —（診断停止、未commit） |
| SPM / SPM Z+ | FFFF | 95E8 / 95F8 | 1 | 0 | —（非対応停止） |

BSET/BCLRの別名も全て対象とする。SEC/CLC=9408/9488、SEZ/CLZ=9418/9498、SEN/CLN=9428/94A8、SEV/CLV=9438/94B8、SES/CLS=9448/94C8、SEH/CLH=9458/94D8、SET/CLT=9468/94E8、SEI/CLI=9478/94F8。各maskはFFFF、1cycleである。BREQ/BRNE等はBRBS/BRBC、LSL/ROL/CLR/TST/SER/SBR/CBRは上表の別表記とする。ELPM、EIJMP/EICALL、DES、XCH/LAS/LAC/LATは対象外である。

decodeは32bit判定、完全一致、その他maskの順。LD/ST Y/Zのq=0はLDD/STDと同じ動作であり二重登録しない。通常d=`(w>>4)&31`、r=`(w&15)|((w>>5)&16)`、即値K=`(w&15)|((w>>4)&F0)`、即値対象dは16〜31。MOVWは4bit番号を2倍、MULSは16加算、MULSU/FMUL系は3bit番号に16加算。ADIW/SBIWのdは24+2×`((w>>4)&3)`、K=`(w&15)|((w>>2)&30)`。q=`(w&7)|((w>>7)&18)|((w>>8)&20)`。IN/OUTのdata addressは`20+(w&F)+((w>>5)&30)`、SBI系は`20+((w>>3)&1F)`。式中F/F0/18/20/30/1Fは16進である。

相対offsetはRJMP/RCALLの下位12bit、BRxxの`(w>>3)&7F`を符号拡張し次PCへ加える。JMP/CALL先は`next | ((((w>>3)&3E)|(w&1))<<16)`である。範囲外への移動は停止する。

### 4.2 演算と副作用

8/16bit演算は各幅の下位を結果とする。加算のH/Cはbit3/7のcarry、減算はborrow、Nは結果最上位、S=N xor V。ADD/ADCのVは同符号入力から異符号結果、SUB/SBC/CP系は異符号入力から被減数と異符号結果で立つ。Zは通常結果0、SBC/SBCI/CPCだけは旧Z AND 結果0。ADCのZは連鎖型にしない。比較はregisterへ結果を書かない。

論理演算はV=0。COMは反転、C=1、V=0。NEGは0−Rd、Vは旧Rd=80、Cは結果非0、Hは結果bit3 OR旧bit3。INCは旧7F、DECは旧80でVを立て、C/Hを保持する。ADIWのV=`~old15 & result15`、C=`old15 & ~result15`、SBIWはV=`old15 & ~result15`、C=`~old15 & result15`。N/Z/Sは16bit結果から求める。

MUL系はR1:R0へ16bit結果を入れる。Cはシフト前の積bit15、Zは格納結果0。FMUL系は積を1bit左へずらす。MULは両方unsigned、MULS/FMULSは両方signed、MULSU/FMULSUはdがsigned、rがunsigned。LSRはN=0、ASRは符号保持、RORは旧Cをbit7へ入れる。C=旧bit0、V=N xor C、S=N xor V、Z=結果0。BSTは指定bitをTへ、BLDは逆である。非更新flagは全命令で保持する。

ポインタはbyte単位、16bitで増減し、前置減算はアクセス前、後置加算は後に行う。ポインタと対象registerが重なる未定義形式（例：LD R26,X+、ST -Z,R30）は診断する。LPMのZはbyte address、flash外はエラー。未配置FFも有効byteだがfetchしたFFFFは未知命令である。

PUSHはdata[SP]へ書いてSPを減らし、POPは増やして読む。return PCはword addressの下位byte、上位byteの順にPUSHし、復帰は逆順。CALL/RCALLは自身の後のPCを保存する。SRAM外へstackアクセスする前に停止する。SPはソフトから変更できるため隠れたcall深度は設けず、RETの空もアクセス範囲で判定する。

### 4.3 skip、IRQ、sleep、停止

skip命令は不成立1、16bit skip2、32bit skip3cycle。次命令を実行せず、先頭wordがJMP/CALL/LDS/STSのmaskなら2word、それ以外は1wordを飛ばす。第2wordをdecodeしない。末端で必要wordが不足すれば範囲エラー。

IRQは命令完了・周辺イベント反映後、I=1かつflag AND maskが非0ならvectorの小さい順に1個受け付ける。flagは回数queueでなく1bitで、無効中も立て、重複発生は合流する。受付時に選んだflagをclearし、次PCを2byte PUSH、I=0、vectorへ移り4cycle追加する。その間も周辺を進める。SREGは自動保存しない。SEI直後とRETI復帰先では1命令完了まで次IRQを遅らせる。CLIは直ちに禁止する。

| source | vector（word） |
| --- | --- |
| Timer1 COMPA/B/C/OVF | 0022 / 0024 / 0026 / 0028 |
| Timer0 COMPA/B/OVF | 002A / 002C / 002E |
| SPI / ADC / EEPROM ready | 0030 / 003A / 003C |
| Timer3 COMPA/B/C/OVF | 0040 / 0042 / 0044 / 0046 |
| Timer4 COMPA/B/D/OVF | 004C / 004E / 0050 / 0052 |

**参照元の不一致：** Rust `peripherals/mod.rs`と`timer4.rs`のTimer4定数は一致しない。2026-11-28に [avr-libc iom32u4.h](https://github.com/avrdudes/avr-libc/blob/main/include/avr/iom32u4.h) を照合し、COMPA/B/D/OVFのvector番号38/39/40/41を確認した。1vectorが2wordなので上表の004C/004E/0050/0052を採用する。Rustの定数へ合わせて試験期待値を作らない。

SLEEPはSMCR(53)のSE=0なら1cycleの無操作。SE=1かつidleなら次PCでsleepし、命令をfetchせず次イベントまでcycleを進める。許可IRQでwakeし受付する。wake追加遅延は4cycleの機能近似とする。I=0ではpendingを保持してsleepを続ける。idle以外は非対応。イベントなしの単独AB-STEPはcycleを進めず0を返す。AB-RUN-CYCLESは指定期限までsleep時間を進め、UIは短い有界実行を繰り返して入力確認を続ける。

BREAK/SPM/未知opcode/未対応周辺設定は命令開始PC/opcode/cycleを保存し診断停止する。停止後のSTEPはresetまで同じエラーを返す。可能な限り事前検査し、不正命令/addressでPC/registerをcommitしない。副作用開始後のhost失敗は巻戻さず失敗地点を残す。

## 5. 時間モデル

仮想時間はcycle/16000000秒。実時計の遅れを埋めるため命令・timer tick・IRQ・PCMを捨てない。I/Oは命令開始時刻tへ周辺を同期してから操作し、命令完了までのイベントを時刻順に反映する。命令内部のbus位相は再現しない近似である。

周辺はlast-cycleと分周残余を持ち、deltaと残余から進むtick数を求める。次のcompare/overflow/端子変化/SPI・EEPROM完了/sample境界までを計算し、tickごとのForth呼出しを避ける。I/OとIRQ可能境界を飛び越してbatchしない。delta上限で余ったcycleを捨てない。

同時刻は予約済み周辺完了・timerイベント、GPIO出力確定、音声区間確定、外部ボタン投入、次命令I/Oの順とする。IRQは全反映後の命令境界で選ぶ。W1Cと同時のflagは先に発生させて書込みでclearする。STEP/batchでこの順を一致させる。

host表示は60Hzを目標とし締切は起点+floor(n×1000000/60)µs、仮想frameはfloor(n×16000000/60)cycleとする。266666/266667の端数を累積し固定16667µsの長期ずれを避ける。境界を越える命令は完了し超過cycleを次frameへ持ち越す。

余裕がある場合だけUTIME/MSで待つ。UTIMEはepoch時計で単調性がないため逆行・1秒超の跳躍では実時計基準を張り直し記録する。遅い場合は待たず、最新の完成状態を最大60回/実秒で描く。仮想frameは捨てないが、古い画像を順にSHOWする必要はない。入力/Esc/closeは高々4096命令または4096cycleのsleep区間ごとにも確認する。

PCMは仮想時間基準で48kHz生成しhostも48kHz再生する。速度不足でも再標本化・pitch変更・timer加速は行わない。連続生成できた部分の音程は保つが、供給不足時は無音区間・underrunが生じ、画面との実時間同期を保証しない。低速時に連続した低い音へ引き延ばす方式にはしない。低速の最終許容判断は測定後である。

## 6. busと周辺

### 6.1 registerとtimer

IN/OUTはI/O addressへ20を加え、LDS/STS/LD/STも同じbusへ通す。以下を初期対応registerとする。予約bitはread=0/write無視、存在する未対応機能の有効化は停止。状態保持だけのregisterは限定して明記する。

| 機能 | register（data address、16進） |
| --- | --- |
| GPIO | PINB/DDRB/PORTB=23/24/25、C=26/27/28、D=29/2A/2B、E=2C/2D/2E、F=2F/30/31 |
| Timer0 | TIFR0=35、TCCR0A/B=44/45、TCNT0=46、OCR0A/B=47/48、TIMSK0=6E |
| Timer1 | TIFR1=36、TIMSK1=6F、TCCR1A/B/C=80/81/82、TCNT1L/H=84/85、ICR1L/H=86/87、OCR1AL/H=88/89、BL/H=8A/8B、CL/H=8C/8D |
| Timer3 | TIFR3=38、TIMSK3=71、TCCR3A/B/C=90/91/92、TCNT3L/H=94/95、ICR3L/H=96/97、OCR3AL/H=98/99、BL/H=9A/9B、CL/H=9C/9D |
| Timer4 | TIFR4=39、TIMSK4=72、TCNT4=BE、TC4H=BF、TCCR4A..E=C0..C4、OCR4A/B/C/D=CF/D0/D1/D2、DT4=D4 |
| 共通 | GTCCR=43、PLLCSR=49、PLLFRQ=52、SMCR=53、MCUSR=54、MCUCR=55、SPMCSR=57、WDTCSR=60、CLKPR=61、PRR0/1=64/65 |
| ADC | ADCL/H=78/79、ADCSRA/B=7A/7B、ADMUX=7C、DIDR2/0/1=7D/7E/7F |
| SPI | SPCR/SPSR/SPDR=4C/4D/4E |
| EEPROM | EECR/EEDR/EEARL/H=3F/40/41/42 |

Timer0は8bit、1/3は16bit、4は10bit。0/1/3のCS=0停止、1..5は1/8/64/256/1024分周、6/7外部時計は非対応。Timer4のCS=0停止、1..15は1,2,4,...16384分周。変更時は同期して残余を0へ戻す。GTCCRのTSMは同期停止、PSRSYNC/PSRASYは対象分周残余を0へ戻す近似とする。

| timer | 受入れWGM | TOPと数え方 |
| --- | --- | --- |
| 0 | 0/2/3/7 | normal FF / CTC OCR0A / fast PWM FF / fast PWM OCR0A |
| 0 | 1/5 | phase correct FF / OCR0A |
| 1/3 | 0/4/12 | normal FFFF / CTC OCRA / CTC ICR |
| 1/3 | 1/2/3、5/6/7 | phase correct 8/9/10bit、fast PWM 8/9/10bit |
| 1/3 | 8/9、10/11、14/15 | phase/frequency correct ICR/OCRA、phase correct ICR/OCRA、fast PWM ICR/OCRA |
| 4 | PWM4x=0（WGM任意） / PWM4x=1かつWGM=0/1 | normal OCR4C / fast PWM OCR4C / phase-frequency correct OCR4C。WGM=2/3のPWM6は非対応 |

normal/fastは0..TOPを上り次tickで0。Timer0/1/3のnormalのOVFは最大値からのwrap、fastはTOP境界。CTCは一致でflag/出力、次tickで0、周期TOP+1であり、OVFは比較clearではなく最大counter値でのみ立つ。Timer4のnormalもOCR4CをTOPとし、そのTOPでOVFを立てる。両方向PWMは0..TOP..0、周期2×TOP、OVFはBOTTOM。TOP=0のPWMは非対応診断。OCR bufferはphase correctのTOP、phase-frequency correctのBOTTOM、fastはTimer0/4のTOP・Timer1/3のBOTTOMで反映しnormal/CTCは即時。ICRをTOPに使う場合は書込み時に更新する。

非PWMのCOM=0切離し/1反転/2clear/3set。PWMのCOM=2は上り一致clear・下り一致set、fastはBOTTOM set・一致clear、COM=3は逆。PWMのCOM=1は初期非対応。OCR=0/TOPの端点は0%/100%の定常出力とする。16bit操作はhigh仮置き→lowでcommit、low読出し→high latch。Timer4はTC4H下位2bitを次のlow操作と組み合わせる。TCNT書込み後は直後1timer tickのcompareを抑制。FOCは非PWMの出力だけを変えflagを立てない。

TIFRはW1C、TIMSKはIRQ許可。0/1/3のTOV=bit0、OCFA/B=bit1/2、1/3のOCFC=bit3。4はTOV=bit2、OCFA/B/D=bit6/5/7。capture、Timer4 fault/dead-time/enhanced/complementary PWMは有効化で停止、DT4は0のみ受理する。DDR出力時はtimer COMがPORTより優先し切離し後はPORTへ戻す。端子経路はOC3A→PC6、OC1A→PB5、OC4A→PC7、OC4B→PB6、OC4D→PD7、OC0A→PB7、OC0B→PD0とする。

Rust版の単純wrapやTimer4の「WGM=1はCTC」をコピーしない。Timer4は[Atmel ATmega16U4/32U4 datasheet](https://cdn-shop.adafruit.com/product-files/1086/1086%20datasheet.pdf) のWaveform Generation Mode Bit Description（PWM4x/WGM41..40）に従い、normal/fast/phase-frequencyだけを初期受入れにする。PWM6は対象外である。端点等の適合は実装試験で確認する。※推測：この集合で全ゲームを扱えるとは限らない。非対応modeが出たらtraceを根拠に追加を判断する。

PRR0はADC/SPI/Timer0/1、PRR1はTimer3/4の停止を反映する。GPIOR0/1/2=3E/4A/4Bは読書き保持、ACSR=50は比較器無効化と状態保持のみ受理しACIE/ACICの有効化で停止する。未対応USART/TWIの電源断bitは保持だけを許す。CLKPRは保護解除窓と除数1だけを扱い16MHz以外への変更は停止する。MCUSRはreset時0で保持、MCUCRのJTD/PUDは保持とpull-up制御、vector移設は非対応。SPMCSRは0保持のみ。WDTCSRは保護解除と無効化だけを受理し有効化は停止する。Arduino初期化のための限定対応である。

### 6.2 PLL、ADC、SPI、EEPROM

PLLCSRのPLLEで同じI/O完了時にPLOCK=1、解除時0。PINDIV/PLLFRQは保持する。PLLFRQのPLLTM1:0=0ならTimer4は16MHz、非0なら固定64MHz（CPUの4倍）とする機能近似を選ぶ。後者でPLL無効ならtimerは停止する。PCKEという32u4にないbitを作らない。実周波数調整・発振安定時間・USB時計は再現しない。比率残余を保持してdelta分割で時刻がずれないようにする。

ADCはADEN AND ADSCで同じI/O完了時に10bit値生成、ADSC clear、ADIF set。ADIEならIRQ。ADIFはW1C、ADLARで左詰め、ADCL→ADCH latchを扱う。ADMUX/ADCSRB/DIDRは選択保持だけで電圧は再現しない。ADATE free runningは非対応診断。乱数は32bit xorshift13/17/5の次状態下位10bit、既定seed=1、AB-SEED!で非0値を指定しresetで同seedへ戻す。自動seed設定はAB-AUTO-SEED（既定偽）の変数で選ぶ。自動seedを選ぶ場合はUI開始時UTIME下位32bit（0なら1）を一度設定し記録する。

SPIはmaster/8bit。SPCRのSPE/MSTR/DORD/CPOL/CPHA/SPR、SPSRのSPI2X/SPIF/WCOL、SPDRを扱う。SPR=0..3は4/16/64/128分周、SPI2Xで半分。SPDR writeから8×除数cycle後完了しSPIFを立てSPIEならIRQ。busy中の再writeはWCOLを立て元転送を維持。SPSRでflagを読み次のSPDRアクセスでSPIF/WCOL clear。MISO=FF。OLED用はMSB first/mode0のみ受理し他の有効転送は停止。SPE=0時writeはlatchのみ。

OLEDはCS=PD6 active-low、DC=PD4（0command/1data）、RESET=PD7 active-low。転送開始時CS/DCを保持し完了時配送する。busy中のCS/DC/RESET変化は非対応タイミング診断。CS highでも完了flagは立つが配送しない。RESET lowはparser/表示制御をresetしRAMを0にする決定的近似。PD1をFX選択として使う転送は対象外である。

EEPROMはEEAR下位10bit、EEDR、EECRのEERE/EEPE/EEMPE/EERIE/EEPMを扱う。EEMPE操作から4cycle未満でEEPEが立つ場合のみ開始。EEPM=00は54400cycle、01/10は28800cycle後完了の固定近似。11はエラー。開始時address/data/modeをlatchし、完了時00=値、01=FF、10=旧値AND値。busy中の再要求/EEREは開始しない。通常EEREは即読出し＋CPU4cycle、EEPE開始はCPU2cycleを追加する。非busy AND EERIEはreadyのlevel要求となり、受付後も条件が続けば再要求する。

実際に内容が変わった時dirtyを立てる。EEMPEの自動clear、busy read、期限前後1cycle、reset中断を検査する。Rustの即時書換えをbusy時間の正解にはしない。

### 6.3 GPIO、ボタン、LED

| ボタン番号/bit | 端子 | 既定キー |
| --- | --- | --- |
| 0 Up | PF7 | K-UP |
| 1 Down | PF4 | K-DOWN |
| 2 Left | PF5 | K-LEFT |
| 3 Right | PF6 | K-RIGHT |
| 4 A | PE6 | Z/z |
| 5 B | PB4 | X/x |

Rust `lib.rs::set_button`の通常Arduboy分岐と一致する。押下はlow。入力は押下0、解放時PORT pull-up有効なら1、floatingは本実装では0。PUDはpull-upを無効にする。出力PINはtimer overrideまたはPORTを返しボタンで強制しない。PINx writeの1bitだけPORT latchを反転する。雑音・短絡電流は再現しない。

LEDはR=PB6/G=PB7/B=PB5、TX=PD5、RX=PB0のactive-low実効出力を保持する。DDR入力なら消灯。snapshotへon/offとGPIO/timer latchを出し、PWM平均輝度を作らない。PC7はTimer4 OC4Aとスピーカーが共有する端子であり、GPIOと同じ正本を参照する。

### 6.4 SSD1306

GDDRAMは1024byte、index=page×128+column、bit0がpage上側。向き等を適用した8192byte色番号framebufferと分け、表示反転でRAMを変えない。

| command（16進） | 引数byte | 動作 |
| --- | ---: | --- |
| 00..0F / 10..1F | 0 | page modeのcolumn下位/上位nibble |
| 20 | 1 | 0 horizontal / 1 vertical / 2 page、3はエラー |
| 21 / 22 | 2 | column0..127 / page0..7のstart,end、start<=end |
| B0..B7 | 0 | page |
| 40..7F | 0 | start line0..63 |
| 81 | 1 | contrast保持、白の強さへ反映しない |
| 8D | 1 | charge pump保持、10/14のみ |
| A0 / A1 | 0 | segment normal / remap |
| A4 / A5 | 0 | RAM / all-on |
| A6 / A7 | 0 | normal / invert |
| A8 | 1 | multiplex、初期は3Fのみ |
| AE / AF | 0 | off / on |
| C0 / C8 | 0 | COM normal / reverse |
| D3 | 1 | offset0..63 |
| D5 / D9 / DA / DB | 1 | clock/precharge/COM/VCOMHを保持する近似 |
| E3 | 0 | NOP |

引数待ちはbyte間・CS解除を越えて保持する。引数待ちにDC=1が来たらエラー。未知command、scroll26..2F、範囲外引数はbyteとparser位置を示して停止。D5/D9/DA/DBは1byte保持だけで電気的効果なしと明示した例外である。

horizontalはcolumn増加、end後startへ戻しpage増加。verticalはpageを先に増加。page modeはcolumnだけ0..127でwrap。画素(x,y)はA1ならc=127−x、A0ならc=x、C8ならv=63−y、C0ならv=y、r=(v+start-line−offset) mod64を読む。all-onでRAMの代わりに1、次にinvert、offなら最終0。この順序を期待式とする。contrast/pumpでRAMを消さない。

### 6.5 音声

通常Arduboyの端子は [Arduboy2Core.h](https://github.com/MLXXXp/Arduboy2/blob/master/src/Arduboy2Core.h) のARDUBOY_10を2026-11-28に照合した。SPEAKER_1=PC6、SPEAKER_2=PC7、RGB_ON=LOWである。RustのPC6/PB5・RGB active-highとは差があるため、通常実機の配線を優先する。Rust比較ではこの仕様差を分離する。


PC6/PC7の実効出力からlevel=PC6−PC7（−1/0/+1）をmono値とする。DDR入力端子の寄与は0。COM出力はPORTより優先。同値は0、逆相は正負の交互出力。端子別stereoや推定toneへの置換をしない。GPIO bit-bang/compare/PWMを共通経路へ通す。

標本nの区間は仮想cycleの[n×16000000/48000,(n+1)×16000000/48000)。端子変化ごとの面積を整数有理数で積分し、平均level×16384を0方向丸めでs16LEにする。端数位相を持ち越し1仮想秒で48000標本を生成する。端子変更時刻までの旧level区間を先に積分してから新levelへ切り替える。無音でも位相を進める。DC除去・アナログfilter・実スピーカー特性は対象外。

headlessはメモリsinkをAB-PCM-READで有界chunkごとに回収する。長時間runnerはsinkが満杯になる前にhash/標本数を更新して排出し、無断破棄しない。UIは`48000 1 4096 PCM-OPEN`。`PCM-WRITE ( addr frames pcm -- written ior )`のpartial分だけ消費し残りを保持する。満杯ならPCM-QUEUED/PCM-WAITで短く待ちEsc/closeを確認する。有限buffer上限9600標本（200ms）、古い音を捨てずCPUを止め送出待ちする。PCM-UNDERRUNS/最大queueを記録。reset/終了はPCM-STOPで破棄後PCM-CLOSEしhandle無効化。失敗を黙って無音へ変えず、明示AB-MUTEだけが無音sinkへ切り替える。

### 6.6 USB serial最小状態

ホストUSBへ接続しない。USBCON=D8はUSBE保持、USBSTA=D9は08、UDADDR=E3は80 OR書込み値。UENUM=E9は下位3bitでendpoint0..6、UEINTX=E8は送信readyのA1、UESTA0X/1X=EE/EFは61/00、UEBCLX/HX=F2/F3は40/00を返す。Rustと同じ起動用近似であり実機register全意味ではない。

UDCON=E0、UDINT/UDIEN=E1/E2、UERST=EA、UECONX=EB、UECFG0X/1X=EC/ED、UEIENX=F0、UHWCON=D7、USBINT=DAは状態保持専用。UDINT/UEINTXのclearは受理するがready近似値を次readでも返す。UEDATX=F1 writeはendpoint>=3ならcycle/ep/byteを送信記録へ追加、readは0（受信なし）。USB IRQ/受信packetを生成しない。

ログは`ARDUBOY serial cycle=... ep=... byte=HH`とし診断へ無加工の文字列を混ぜない。headlessは64KiB送信byte上限、満杯は資源エラー。UIは逐次出力し蓄積を抑える。待機が解けないROMはPC/I/O traceで原因を確かめ、根拠なくready bitを増やさない。

## 7. loaderとEEPROMファイル

### 7.1 Intel HEX

ASCII、BOMなし、LF/CRLF、空行と両端space/tabを許す。内部空白・コメント・コロンなし非空行はエラー。`:LLAAAATT[DD...]CC`の正確な長さ（コロンを除き2×(LL+5)文字）、偶数桁、hex数字、全byte合計mod256=0を検査。lineは1始まり。

00=data、01=EOF（LL=0/address=0）、02=segment（LL=2/address=0、値<<4）、04=linear（LL=2/address=0、値<<16）。03/05=startはLL=4/address=0を検証して無視しentry=0。02/04はbaseを置換。未知typeはエラー。EOFは必ず1個、後続非空行はエラー。dataが0byteもエラー。

base+address+lengthをoverflowなしで求め0000..7FFFへ制限する。16bit address境界跨ぎ、範囲超過、同値でも重複addressはエラー。未配置FF、奇数address/byte数を許し命令境界を推測しない。最大入力1MiB、両端空白を除く1行521文字。全検証を一時flash/配置bitmapで行い失敗時に現ROMを置換しない。Rustの読み飛ばし・範囲切捨ては採用しない。

### 7.2 EEPROMパスと保存

game.hexに同じフォルダーのgame.eepを対応させる。FILE>REALPATHでROMを正規化し最後の拡張子を除き.eepを付ける。拡張子なしなら追加。HEXと同一パスは拒否。headerなし1024byte、欠損FF、長さ違い/読取り失敗はエラー。

AB-SAVE-EEPROMによる明示保存とEsc/close/正常終了で保存する。dirty偽なら書かない。正常終了は進行中EE書込み期限までCPUを追加実行せず周辺を進め、完了後保存する。異常停止は自動保存しないがForthから明示保存可。F5は保存ではない。

同じ保存先への同時起動は初期版の対象外とし、同じゲームは1プロセスだけで起動する。公開語に排他的ファイル作成・lock解除の組を確認できないため、CREATE-FILEや存在確認を排他lockとみなさない。保存前に開始時（直前保存後はその時点）の1024byte画像とdisk内容を比較し、外部変更・欠損/存在の変化なら上書きせず競合エラーにする。ただし比較とrenameの間の競合まで防ぐ規則ではない。hardlink/別名・ネットワークFSも含め同時書込みは保証しない。これは既決方針のゲーム別保存を単一プロセスで実装する範囲指定である。

保存は同フォルダーの.eep.tmpへ1024byteを書きFLUSH-FILE/CLOSE-FILE成功後、既存eepを.eep.bakへ退避、tmpをeepへRENAME-FILE、最後にbak削除しdirty clear。bak既存は復旧要求で停止。rename失敗は可能ならbakを戻し各パスを診断する。旧eepを先に削除しない。クラッシュ時の完全原子性は保証しない。次回tmp/bak残存なら自動上書きせず復旧要求。保存失敗は終了状態1。

AB-LOAD/headlessはEEPROMをFFとしdiskへ触れない。AB-PLAYだけがパス/eepを用意する。ROM検査で隣接ファイルを書き換えないためである。

## 8. host、公開API、起動、診断

### 8.1 公開語

読込み後`ALSO ARDUBOY`で使う。byte値0..255、flagはForth真偽値。検査語も範囲を検査し内部offsetを公開しない。初期版は64bit cellホストを対象とする。

| 語 | stack | 意味 |
| --- | --- | --- |
| AB-LOAD | `( addr u -- )` | HEX配置、EEPROM FF、全reset。hostなし |
| AB-RESET | `( -- )` | 3章のreset |
| AB-STEP | `( -- cycles )` | 1命令と完了境界IRQ、追加cycle込み。sleepは次イベントまで |
| AB-RUN-CYCLES | `( budget -- actual )` | 非負budget以上になる最初の命令境界まで、0なら何もしない |
| AB-HEADLESS | `( addr u budget -- actual )` | LOAD→有界実行、disk保存なし |
| AB-BUTTONS! | `( mask -- )` | bits0..5、1=押下、現在cycleへ投入 |
| AB-SEED! | `( seed -- )` | 次reset用の非0 seed |
| AB-REG@ / AB-REG! | `( reg -- byte )` / `( byte reg -- )` | R0..31検査 |
| AB-DATA@ / AB-DATA! | `( address -- byte )` / `( byte address -- )` | bus経由、I/O副作用あり |
| AB-PC@ / AB-SP@ / AB-SREG@ / AB-CYCLES@ | `( -- n )` | 状態参照 |
| AB-FLASH! | `( byte address -- )` | 窓なし停止中のテストROM配置、cache失効 |
| AB-EEPROM@ / AB-EEPROM! | `( index -- byte )` / `( byte index -- )` | !はbusy中不可、dirty設定 |
| AB-FRAMEBUFFER / AB-GDDRAM | `( -- addr u )` | 借用read-only、8192/1024byte |
| AB-PCM-READ | `( addr capacity -- frames )` | headless sinkから最大capacity標本を取り出す |
| AB-SNAPSHOT | `( addr capacity -- used )` | 比較用コピー、容量不足は書込み前にエラー |
| AB-KEY! | `( key button -- )` | button0..5へSigma key code設定 |
| AB-KEY-DEFAULTS | `( -- )` | 矢印/Z/Xへ戻す |
| AB-PAINT | `( -- )` | 展開/画像転送、SHOWしない |
| AB-RUN | `( -- )` | ロード済み機械をUI実行 |
| AB-PLAY | `( addr u -- )` | HEX/eep/UI/正常保存/回収 |
| AB-SAVE-EEPROM | `( -- )` | PLAYの保存先へ明示保存、設定なしはエラー |
| AB-DISPOSE | `( -- )` | host資源回収、複数回可、機械状態保持 |
| AB-MAIN | `( -- )` | 引数とcommand line終了 |

AB-SCALEは1..16/既定4、AB-MUTEは既定偽の変数。キー設定はAB-KEY!方式とし初期版に設定ファイルparserを加えない。同じキーを複数ボタンへ割当可、Esc/F5はゲームへ割当不可。

snapshotはversion=1、整数little endian。固定順はversion u32、PC/SP u16、SREG/sleep/stop u8、cycle u64、R32byte、I/O224byte、SRAM2560byte、flash32768byte、EEPROM1024byte、GDDRAM1024byte、各周辺のtag u16/length u32/payload列。payloadのfield順/幅は最初の比較実装時にdocs/STATE_FORMAT.mdへ固定し同versionで変更しない。未知tagは比較エラー。snapshotへhost handleを入れない。

### 8.2 窓・入力・終了

REQUIRE-GRAPHICS、`128 64 GFX-INIT`、scale倍のWINDOW-SIZE、`1 WINDOW-FIT`、`FALSE WINDOW-SMOOTH`。0黒/1白をGFX-INDEXEDで転送しSHOWする。リサイズで元画素を変えず整数倍率と余白を使う。headlessはGFX-INIT/SHOW/PCM-OPENを呼ばない。PCM sink/入力投入と実ホストを交換可能にする。

KEY-HELD?とK-UP/DOWN/LEFT/RIGHTを使い英字は大小OR。INKEYをdrainし27で終了、F5 reset。WINDOW-FOCUSED?偽なら全ボタン解放。TRUE WINDOW-KEEP-OPENとWINDOW-CLOSESでclose要求を確認し、その後SHOWで開き直さない。PCM待ちにも入力確認する。

CATCHで最初のエラーを保持しPCM停止/close、窓close、file close、環境復元を成功・失敗とも実行する。後始末エラーで元エラーを上書きしない。正常終了の保存失敗は失敗へ切り替える。強制終了の回収は保証しない。

```powershell
sigma emu/arduboy/arduboy.fs path/to/game.hex
sigma emu/arduboy/arduboy.fs -e 'ALSO ARDUBOY S" path/to/game.hex" 16000000 AB-HEADLESS . PREVIOUS BYE'
```

NEXT-ARGでROM引数を消費しSigmaにForthとして読ませない。無引数/先頭-eはライブラリ読込みだけ。通常起動はHEX1個、未知option/余分な引数は使用法エラー。後段の保存アプリはAB-MAINをAPP-ENTRY!登録し、その入口の無引数は使用法エラー。保存host handleは再利用しない。

正常/Esc/close/headless budget終了は状態0。使用法/読込み/非対応/実行/保存/後始末失敗は1。command lineは診断1回後、**元エラーをTHROWせずQUIT**しSigmaのERROR/BACKTRACEを重ねない。成功のソース起動はBYE。ライブラリAPIは正常復帰または元例外THROWで、QUIT/BYEを呼ばない。

### 8.3 診断

英語prefixとkey=valueを使う。位置なしは?、PC/opcode/addressは大文字16進、cycle/lineは十進。I/Oにはread/write/address/value/peripheralを添える。ファイル名の改行等はescapeする。

```text
ARDUBOY error phase=cpu code=-4302 file="game.hex" line=? pc=0123 bytepc=0246 opcode=FFFF cycle=12345: unsupported opcode
ARDUBOY error phase=loader code=-4301 file="game.hex" line=7 pc=? cycle=0: checksum mismatch
```

| code | 用途 |
| --- | --- |
| -4300 | 使用法/設定 |
| -4301 | HEX形式/長さ/範囲/checksum |
| -4302 | 未対応opcode/SPM |
| -4303 | data/flash/stack範囲、未定義operand重複 |
| -4304 | 未対応I/O/mode/command |
| -4305 | BREAK診断停止 |
| -4306 | eep形式/競合/復旧要求 |
| -4307 | snapshot/sink/資源容量 |

host iorは元値を残し元例外を維持。Esc/closeはerrorを出さない。直近256件のcycle/pc/opcode/read-write/address/value/eventを環状保持し、要求時だけ出力する。未対応をゲーム破損と断定しない。

## 9. 試験

tests/run.fsはライブラリだけを読み各検査をCATCHで分離する。失敗行は`FAIL name expected=... actual=...`、最後は`passed N failed M skipped K`。failed>0ならQUITで状態1。窓/音声デバイスを開かない。期待値は手計算・独立算術式とし同じdecodeから生成しない。

各命令は通常/境界、全register位置、即値最小最大、PC/SP/memory/cycle/SREGの変更・保持bitを照合する。8bit算術は全入力対×carryとZ連鎖、単項/shiftは全byte×初期SREG。ADIW/SBIWは0000/7FFF/8000/FFFFとcarry境界、乗算は符号/fractional/C/Z。hashに加えて代表ケースの全register/dataをbyte比較する。

全32bit形式のskip、16bit skip、不成立、末端、不正命令、正負branch、CALL/RET byte順、stack上下端、SEI/CLI/RETI、I=0 pending、同時IRQ、sleep/wakeを検査する。同じROMをSTEPとbatchで実行し全状態/cycle/端子列の一致を要求する。

自作ROMはtests/romsへ手組みword配列・HEX出力器・各wordのmnemonic/operand/cycle注釈と期待値を置く。low→high byteで格納しchecksumを独立再計算する。外部ゲームを自動downloadしない。

2026-11-28、PowerShellのGet-Command avr-gccで調べた範囲ではPATH上にavr-gccは見つからなかった。全ディスクの不在確認ではない。必須試験は手組みで成立させる。後に利用可能なら版を記録し`avr-gcc -mmcu=atmega32u4 -DF_CPU=16000000UL -Os ...`と`avr-objcopy -O ihex -R .eeprom ...`で自作C/assemblyも生成する。未導入ならinstallせず任意試験をskipする。再現ソースはemu/arduboy、生成物/ログは.work/arduboyへ置く。

| 分野 | 必須確認 |
| --- | --- |
| Timer0/1/3/4 | 全対応分周/WGM、期限前後1cycle、latch/buffer/W1C/mask、合流/優先、COM/DDR、delta分割不変、PLL比率 |
| PLL/ADC | enable/disable、lock、seed、ADLAR、ADIF/ADIE、reset再現 |
| SPI/OLED | 8×分周完了、SPIF clear順、busy/WCOL、CS/DC/reset、全commandと引数不足、各mode wrap |
| 画面 | 全1024byte/8192画素、start/offset/remap/COM/invert/all-on/offを独立式と比較 |
| 音 | 同値/逆相/片端子入力、GPIO/timer切替、sample境界、1秒48000標本、STEP/batch、partial/full/underrun擬似sink |
| EEPROM | FF、許可窓/busy/3mode/IRQ/reset、dirty、正常/異常終了、eep長、外部変更競合、保存各段階失敗と復旧 |
| HEX | LL/checksum/EOF/type02/04/03/05/7FFF端/重複/空白/BOM/不正桁、失敗時ROM不変 |
| USB/GPIO/LED | ready/endpoint/送信上限、6ボタン同時、pull-up/PUD/PIN toggle、active-low |
| 起動/診断 | 無引数/-e/引数消費、診断1回/QUIT1/正常0/API THROW、反復初期化/解放 |

窓・DPI・同時押し・focus喪失・Esc/close/F5・実聴・device失敗・長期pacingはOS別実機検査とする。headless成功と混同しない。

Rust比較は**実行許可後のみ**。同ROM/seed/eep/button cycle/期限で、実際の対応引数を確認してheadless/snapshotを使う。CPU/RAM/GDDRAM/端子/IRQを正規化し比較する。OLED/SPI/EEPROM/Timer4/mono等の既知仕様差を分け、Rust一致だけを正解にしない。本タスクでは実行していない。

## 10. 速度目標と1483

必ず**-Doptimize=fastで作られたSigma**を使い、パス/サイズ/SHA256/条件を記録する。Debugを採否基準にしない。本タスクでは再ビルド・測定しない。既存fast実行体の条件を測定担当が確認する。

1483はlocals削減、register別dispatch、decode済みoperand、cycle差分event batchingを比較する。基本blockもI/O/IRQ/branch/sleep/停止境界を保持しflash検査書込みでcache失効。変更ごとに状態一致後に測る。

CPUのみ、timer/IRQ追加、全周辺+画面展開+PCM sink、UI+実PCMの4段階を分ける。1483時点で全周辺未完成なら試作の制限を明記し最終方式決定の証拠にしない。1484〜1488の実装へ置換後、同じ手順を再測定する。

自作負荷は(1)算術/SRAM/branch、(2)Timer0 IRQ＋毎仮想frame SPI1024byte、(3)Timer1/3/4＋GPIO音＋ADC/EEPROM/ボタン/USB送信/LEDの統合負荷。全周辺を実際に動かしincludeだけで数えない。許可済み実ゲームは別に名前/ライセンス/条件を記録する。

warm-up2仮想秒、計測最低10仮想秒、別processで3回。初期化/表構築/出力は計時外、CPU/bus/IRQ/周辺/PCM生成/画面展開は内。UIはSHOW/送出/待機込み。PowerShellのSystem.Diagnostics.Stopwatchによる外側wall timeを併記する。UTIME時計補正runは除外理由を残し再測定する。都合のよいrunだけを選ばない。

全3回のcycle/s、命令/s、wall秒、16MHz比、仮想/実時間比、frame処理最大/95percentile、表示数、PCM生成/送出数、underrun増分、最大queue、入力poll最大間隔を記録する。既存benchの32.04%は小さなhook込みであり全周辺値へ流用しない。

実時間到達は、対象ROMの全3回で無待機throughputが16000000cycle/s以上、UI有効60実秒で仮想/実時間0.99〜1.01、AVR時間を捨てず、warm-up後underrun増分0、入力/終了poll間隔50ms以下を満たすこととする。表示は最大60Hzでゲーム自体のFPS60は要求しない。表示/音を省いて合格にしない。

未達時は必要倍率=16000000/実測cycle毎秒とボトルネックを示し、低速Forth継続/native検討の推奨と影響を報告する。**利用者が選ぶまで方式を変更しない**。native APIを独自追加したり周辺を省略して合格扱いにしない。

## 11. ライセンスと確認の限界

Rust移植はMITを選ぶ。LICENSE-MIT-RUST.txtへ元のCopyrightと許諾全文を保存する。翻訳・改変したソース先頭に元ファイル/MIT/変更の旨を記す。CREDITS.mdへ元プロジェクト/読取り元/取得日/各元ファイルSHA256/移植先/変更点を残す。Gitなしでも元版を識別するためである。

本仕様のopcode/配線/register確認にも参照したため両通知を同時に置く。依存crate、ゲームROM、Arduboy2コードは一括して同じ許諾としない。取り込む時に個別確認する。

このタスクは読取りと文書整合性確認だけで、CPU適合・timer・USB起動・表示・音・保存・速度の実装成功は未確認である。Timer4/PWMの境界動作は実装時に一次資料の表と突き合わせて試験する。技術確認は根拠を取得して解決し誤りがあれば理由付きで仕様を修正する。利用者の追加判断が必要なのは実測未達時の方式であり、現時点で未達を確定した意味ではない。

## 12. 仕様選択

承認済み方針に数値・手順がなかった部分を以下で具体化した。

| 番号 | 選択と理由 |
| --- | --- |
| S01 | ARDUBOY語彙＋AB-/AB@。他ライブラリの一般名を上書きしないため |
| S02 | flash32768byte/PC word。HEX/LPM/fetchの単位混同を防ぐため |
| S03 | data2816byteとSREG/SP alias。試作の平坦RAMによる制約漏れを防ぐため |
| S04 | 決定的resetとflash/EEPROM/設定保持。試験とF5の再現性のため |
| S05 | 未対応/範囲外は停止。誤動作を無操作で隠さないため |
| S06 | WDR無操作、SPM拒否、BREAK診断。対象外を実装済みに見せないため |
| S07 | IRQ bit合流とvector順。無効期間の発生を保持するため |
| S08 | 命令開始I/O、完了IRQ、同時刻順固定。batch粒度による差を防ぐため |
| S09 | 60分周の余り累積。長期ずれを避けるため |
| S10 | 仮想cycle保持と48kHz固定。遅れとpitch変更を分離するため |
| S11 | timerのWGM/未対応bit明示。名称だけの対応完了を防ぐため |
| S12 | PLL即lock/固定比率、ADC即完了/seed指定。機能近似を再現可能にするため |
| S13 | SPIは8×分周後完了。poll/IRQ/配送を同じ時刻で試験するため |
| S14 | EEPROM許可窓と固定busy。待機/完了時刻を失わないため |
| S15 | OLED RAMと表示変換を分離。反転/向き/addressingの検査のため |
| S16 | 端子差を積分しmono PCM。GPIO/PWMを共通経路で扱うため |
| S17 | floating入力0、出力PINは実効値。試験の不定値を避けるため |
| S18 | キー再設定は公開語。変更可能性を満たしparserを増やさないため |
| S19 | eep1024byte、単一プロセス＋外部変更検出、tmp/bak。公開APIの範囲で競合と保存失敗を扱うため |
| S20 | headlessはEEPROM disk不使用。検査で利用者データを書き換えないため |
| S21 | USB ready近似/送信列、LED状態のみ。実USB/輝度再現を約束しないため |
| S22 | CLI診断後QUIT、API THROW。LOGOの終了規則に合わせるため |
| S23 | HEX厳格検査/一時配置。壊れたROMを部分実行しないため |
| S24 | 手組みROM必須。avr-gcc導入に依存しない独立期待値のため |
| S25 | fast/全周辺/全run/UI60秒。CPU速度と実プレイを混同しないため |
| S26 | snapshotはversion付き比較コピー。save stateと責任を分けるため |
| S27 | MIT全文と元hash。移植範囲の通知と追跡のため |

# サウンド機能の調査と仕様の整理

2026-11-07 作成。サウンド機能（MSX BASIC 風のレトロなサウンドと、より高度なサウンド）を設計するための調査の記録。参考にする機種は MSX、Atari ST、C64、NES、Amiga。

- 調べた内容は、各節に出典の URL を付けた。出典で確かめられなかったことは「未確認」、推測は「※推測」と書いた。
- エミュレーターやプレイヤーのコード（reSID・UAE などの GPL のもの、MAME・ST-Sound・pt2-clone などのそのほかのもの）は転記していない。参照したのは、コメントに書かれた動作と数値だけ。forthz の実装は、公開資料に書かれた動作から独自に書く。
- 数値の多くは、Web ページの取得時に要約を経ている。実装の前に、使う数値を原典で確かめる。

## 1. 機種の比較

| 項目 | MSX（AY-3-8910） | Atari ST（YM2149） | C64（SID） | NES（2A03） | Amiga（Paula） |
|---|---|---|---|---|---|
| 音の数 | 矩形波3 + ノイズ（各音に混ぜる） | MSX と同じ（STE は PCM 2ch を追加） | 3 | パルス2、三角波1、ノイズ1、DPCM 1 | PCM 4 |
| 波形 | 50%の矩形波 | 同左 | 三角波、のこぎり波、パルス（12ビットの幅）、ノイズ、重ね合わせ | パルス（12.5/25/50/75%）、4ビットの段々の三角波、ノイズ（長と短）、1ビット差分 | 符号付き8ビットのサンプル |
| 音の高さ | 12ビットの周期、clock/(16×TP) | 同左 | 16ビット、Fn×clock/2^24 | 11ビット、CPU/(16×(t+1)) | 周期、clock/周期 |
| 音量 | 4ビット、対数 | 4ビット（エンベロープは5ビット）、対数 | 4ビットのマスター、8ビットのエンベロープ | 4ビット（三角波はなし） | 0〜64、線形 |
| エンベロープ | ハードウェア1つを共用、8種類の形 | 同左（32段） | 音ごとの ADSR | 減衰（ループ可）、長さカウンター、スイープ | なし（ソフトで書き換え） |
| 変調 | なし | なし（タイマーで音量を書き換える技法） | リング変調、ハードシンク | スイープ | 音量・周期の変調（アタッチ） |
| フィルター | なし | なし（STE は低音と高音） | 状態変数フィルター（LP/BP/HP、共振） | 出力のハイパスとローパスだけ | RC ローパス + 切り替え式の LED フィルター |
| ミキサー | 対数の表 | 同左 | 線形 | 非直線の式 | 固定のステレオ（0・3 が左、1・2 が右） |
| クロック | 1.7897725 MHz | 2 MHz | PAL 985248 Hz / NTSC 1022727 Hz | NTSC 1.789773 MHz / PAL 1.662607 MHz | PAL 3546895 Hz / NTSC 3579545 Hz |
| 曲の進み方 | 垂直同期の割り込み（50/60 Hz） | 50 Hz（Timer C） | フレーム（VBI）か CIA タイマー | フレームカウンター（240 Hz の段階） | tick = 2.5/BPM 秒（125 BPM で50 Hz） |
| 音楽の文化 | MML（PLAY） | YM 形式（レジスタのダンプ） | SID 形式（6502 のコード） | MML（MCK）、トラッカー | MOD（トラッカー） |

## 2. forthz への整理（調査から分かったこと）

### 2.1 共通の合成エンジンで表せるもの

調査した5機種の音は、次の部品の組み合わせで表せる。

| 部品 | 使う機種 |
|---|---|
| 位相アキュムレーターの発振器（パルス幅可変、三角波、のこぎり波） | SID、NES、AY（50%固定） |
| 段々の波形（4ビットの三角波など）と短い波形表 | NES の三角波、SCC、N163、AHX |
| LFSR のノイズ（17/15/23ビット、タップは機種ごと） | AY/YM、NES、SID |
| PCM（符号付き8ビット、ゼロ次ホールド、ループ、1ビット差分） | Paula、STE、NES の DPCM |
| エンベロープ: AY の8種類の形、SID の ADSR（指数近似）、NES の減衰 | 各機種 |
| 変調: リング変調、ハードシンク、スイープ、音量・周期の変調 | SID、NES、Paula |
| フィルター: 状態変数フィルター、1次・2次のローパスとハイパス | SID、NES、Amiga |
| ミキサー: 対数の表、線形、NES の非直線の式、固定のステレオ | 各機種 |

機種の「設定」は、これらの部品の数、値の範囲、クロック、ミキサーを決めたものになる。前回の案（共通の部品と機種の設定）は、調査の結果と合っている。

### 2.2 時間の扱い

- 音の高さはチップのクロックで決まる（AY は clock/16、SID は毎サイクル）。forthz では、出力の周波数（48 kHz の見込み）で直接合成し、矩形波などの不連続点は BLEP 型の帯域制限で折り返し雑音を抑える。チップのクロックで全サイクルを数える方法は、正確だが計算量が大きい。
- 曲の進み方（音符の切り替え、エンベロープやマクロの1段）は、各機種とも 50/60 Hz 前後の「フレーム」が単位。forthz の演奏の処理も、フレーム（tick）を単位にすると、MSX の PLAY、NES の MML のマクロ、MOD の tick を同じ仕組みで扱える。

### 2.3 MSX BASIC の動作で、そのまま再現できるもの

- `PLAY` の MML（第4章「MSX BASIC のサウンド」の表）、音の高さの約数の表、長さの式 `12000 / (L × T)` ticks。
- 声部ごとの待ち行列と、「入りきるまで戻らない」動き。PLAY 文ごとに3声の頭がそろう同期。
- `PLAY(n)` に当たる、演奏中かどうかの問い合わせ。
- `SOUND` のレジスタの範囲（R7 の上位2ビットは強制）。
- `BEEP` の音（1316 Hz、音量7、40 ms）と、その後の初期化。

確かめが必要な点: 引数を省略したときの値、60 Hz の日本版 ROM での長さの定数、範囲外の値のときのエラー。

### 2.4 出力層

- Windows: WASAPI（共有モード、イベント駆動、既定10 ms）を本命、waveOut を予備とする案が調査から出た。waveOut だけなら作業量は小さいが、遅れは20〜50 ms の見込み（実測は未確認）。
- Linux: WSLg では ALSA の `default` がないという報告があり、PulseAudio の経路が確実。静的リンクの musl 版は dlopen できないので、`pacat` などの外部のコマンドへパイプで送る案になる。
- 音のスレッドでは、ロック、メモリーの確保、待つ呼び出しを避ける。Forth 側からは、ロックを使わない待ち行列で命令を送る。

## 3. 決めていただきたい点（調査を受けて改訂）

1. **再現の程度**: (a) 共通の部品と機種の設定で雰囲気を再現、(b) 各チップをレジスタの単位で正確にエミュレート、(c) (a) を基本にし、AY（MSX の `SOUND`）だけはレジスタの単位で扱う。推奨は (c)。SID の合成波形や 6581 のフィルターは実測の表がないと正確に再現できず、(b) は資料の面でも難しい。
2. **対象にする追加の音源**: SCC（作業量は小さい）、OPLL（FM、作業量が大きい）、STE の PCM、NES の拡張音源（VRC6 など）のどれを含めるか。
3. **曲のファイル**: MOD の再生、YM 形式の再生（YM は LHA の展開が必要）を対象に含めるか。SID 形式は 6502 のエミュレーションが要るので、対象外を勧める。
4. **出力層**: Windows は WASAPI と waveOut のどちらから作るか。Linux の静的リンクの版で、外部のコマンドへのパイプを認めるか。
5. **MSX との互換**: `PLAY` が待ち行列に入りきるまで待つ動きを再現するか（ゲーム向けに、待たない版も設けるか）。
6. **`PLAY` の受け取り方**: 3つの文字列の渡し方（`PLAY` を1音にして `PLAY2` `PLAY3` を設ける、最後に数を渡す、など）。
7. **辞書の保存**: 音色の定義などを `SAVE` や `SAVESYS` で保存しないこと（推奨）でよいか。

---

## 4. 調査の詳細（機種ごと）

## AY-3-8910 / YM2149（MSX と Atari ST の PSG）

出典: [GI-DS] GI AY-3-8910 データシート http://map.grauw.nl/resources/sound/generalinstrument_ay-3-8910.pdf 、[YM-DS] Yamaha YM2149 データシート http://www.ym2149.com/ym2149.pdf 、[TH] MSX2 Technical Handbook 第5章 https://github.com/Konamiman/MSX2-Technical-Handbook/blob/master/md/Chapter5a.md 、[RB] The MSX Red Book https://github.com/gseidler/The-MSX-Red-Book/blob/master/the_msx_red_book.md 、[MAME] ay8910.cpp/.h のコメント（BSD-3）https://github.com/mamedev/mame/blob/master/src/devices/sound/ay8910.cpp 、[WIKI-PLAY] https://www.msx.org/wiki/PLAY 、[WIKI-PLAYF] https://www.msx.org/wiki/PLAY() 、[WIKI-SOUND] https://www.msx.org/wiki/SOUND 、[WIKI-BEEP] https://www.msx.org/wiki/BEEP 、差異 https://maidavale.org/blog/ay-ym-differences/

### レジスタ [GI-DS][YM-DS][TH]

| Reg | 内容 | ビット |
|---|---|---|
| R0/R1, R2/R3, R4/R5 | ch A/B/C のトーン周期 | 下位8 + 上位4 = 12ビットの TP |
| R6 | ノイズ周期 | 5ビット |
| R7 | ミキサーと I/O | bit0-2 トーン A/B/C、bit3-5 ノイズ A/B/C（0 で有効）、bit6/7 ポート A/B の向き（1 で出力） |
| R8/R9/R10 | 音量 | bit3-0 固定音量、bit4 = 1 でエンベロープ |
| R11/R12 | エンベロープ周期 | 16ビット（R11 下位） |
| R13 | エンベロープの形 | CONT ATT ALT HOLD |
| R14/R15 | I/O ポート | |

### 周波数 [GI-DS][YM-DS][TH]

- トーン: f = clock / (16 × TP)。MSX では 111860.78 / TP Hz（TP 1〜4095）。
- ノイズ: f = clock / (16 × NP)（NP 1〜31）。
- エンベロープ: f = clock / (256 × EP)。MSX では1周期 = 143.03493 × EP µs。AY は1周期16段、YM は32段（長さは同じ）。
- 周期0: トーンとノイズは1と同じ、エンベロープは1の半分 [MAME]（データシートに記載なし）。
- クロック: MSX 1.7897725 MHz [TH][RB]、Atari ST 2 MHz（YM 形式の文書と ST-Sound。Atari の一次資料は未確認）。

### ミキサー [MAME]

- 出力 = (トーン | トーン無効) & (ノイズ | ノイズ無効)。両方を無効にすると常に1で、音量レジスタがそのまま出力になる（デジドラムに使う）。

### エンベロープの形（R13）

| R13 | 波形 |
|---|---|
| 0〜3, 9 | `\___` 1回下がって0のまま |
| 4〜7, 15 | `/___` 1回上がって0へ落ちる |
| 8 | `\\\\` 下がるのこぎり波の繰り返し |
| 10 | `\/\/` 三角波（下から） |
| 11 | `\¯¯¯` 下がって最大のまま |
| 12 | `////` 上がるのこぎり波の繰り返し |
| 13 | `/¯¯¯` 上がって最大のまま |
| 14 | `/\/\` 三角波（上から） |

R13 を書くとエンベロープは最初からやり直す。

### ノイズと DAC

- ノイズ: 17ビットの LFSR、入力 = bit0 XOR bit3、出力 bit0、初期値1（AY と YM の実機で確認と [MAME] のコメント）。
- DAC は対数。AY の実測（Matthew Westcott、パブリックドメイン、[MAME] に引用、DC オフセットを含む電圧）:

| L | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| V | 1.147 | 1.162 | 1.169 | 1.178 | 1.192 | 1.213 | 1.238 | 1.299 | 1.336 | 1.457 | 1.573 | 1.707 | 1.882 | 2.06 | 2.32 | 2.58 |

- 近似式: vol(i) = exp(i/2 − 7.5)（[MAME] による、1段約4.3 dB）。
- YM2149 の正規化した値（データシートの図）: 15 = 1、14 = .707、13 = .5、12 = .354、11 = .25、10 = .177、9 = .125（1段約 −3 dB）。5ビットのエンベロープは間を約 −1.5 dB で埋める。9未満は読めず未確認。
- AY の実測は1段の比が一定でなく、YM の「1段3 dB」と合わない（出典の食い違い）。

### YM2149 と AY の違い [YM-DS]

| 項目 | AY-3-8910 | YM2149 |
|---|---|---|
| エンベロープ | 16段 | 32段 |
| ピン26 | TEST | /SEL（Low でクロック1/2） |
| クロック | 1〜2 MHz | 1〜4 MHz（/SEL High では最大2 MHz） |
| DC オフセット | 約0.2 V | 約2 V |
| 未使用ビットの読み出し | 0 | 書いた値（MAME は不明としている） |

## MSX BASIC のサウンド

### SOUND reg, val [WIKI-SOUND][RB]

- R14、R15、R7 の上位2ビットは変えられない（R7 の bit7/6 は I/O 保護のため常に 10 に強制）。
- 範囲: R0/2/4 0〜255、R1/3/5 0〜15、R6 0〜31、R7 128〜191、R8〜10 0〜16（16 でエンベロープ）、R11/R12 0〜255、R13 0〜15。範囲外のときのエラーは未確認。
- 初期化（GICINI）: R0 = 55h、R7 = B8h、R11 = 0Bh、ほかは0 [TH]。

### BEEP [RB][WIKI-BEEP]

- 1316 Hz（O6 の E）を音量7で40 ms。その後 GICINI で PSG と PLAY の作業領域を初期化する（MML の値も初期値に戻る）。MSX2 以降は `SET BEEP 音色,音量`（各1〜4）。

### PLAY [RB][WIKI-PLAY]

- `PLAY A$[,B$[,C$]]`（4つ以上は Syntax error）。拡張: `PLAY #n,...`（#2/#3 は MSX-MUSIC の FM）。

| コマンド | 意味 | 範囲 | 初期値 |
|---|---|---|---|
| A〜G[+#-][長さ][.] | 音符。B+ や C- も可 | 長さ 1〜64 | L の値 |
| `.` | 長さ × 1.5（複数可） | | |
| O n | オクターブ | 1〜8 | 4 |
| L n | 既定の長さ | 1〜64 | 4 |
| T n | テンポ（4分音符/分） | 32〜255 | 120 |
| V n | 音量（エンベロープを解除） | 0〜15 | 8 |
| R n | 休符 | 1〜64 | 4 |
| N n | 音番号（0 は休符） | 0〜96 | 必須 |
| S n | エンベロープの形 | 0〜15 | 0 |
| M n | エンベロープ周期 | 1〜65535 | 255 |
| `<` `>` | オクターブ ∓1 | | |
| X 変数; | 文字列変数を MML として展開 | | |
| =変数; | 数値の引数に変数 | | |

- 小文字は大文字にする。表にない文字は Illegal function call。数値に式は書けない。
- 引数を省略したときの値は出典で食い違う（1 / 既定値 / 前回の値、未確認）。
- V と S は同じバイトに書き、後に書いた方が有効。S のときは音符ごとに R13 を書き直す（エンベロープが音符ごとにやり直す）。
- 音の高さ: O1 の約数 C = 3421、C+ = 3228、D = 3047、D+ = 2876、E = 2715、F = 2562、F+ = 2419、G = 2283、G+ = 2155、A = 2034、A+ = 1920、B = 1812 をオクターブごとに半分にする [RB]。O4 の A = 254（約440.4 Hz）[TH]。
- 長さ: ticks = 12000 / (L × T)、付点ごとに × 1.5、5未満は5。L4・T120 で25 ticks = 50 Hz で0.5秒 [RB]（UK 版の ROM。60 Hz の日本版の定数は未確認）。
- 待ち行列: 声部ごとに128バイト。MML を3/5/7バイトの小包にして入れる。足りなくなると空くまで待つので、**PLAY は待ち行列に入りきるまで戻らないことがある**。入りきれば演奏の終わりは待たない。
- 同期: 3声すべてが止まったときだけ、次の PLAY 文の組を同時に始める（PLAY 文ごとに3声の頭がそろう）。
- 演奏は垂直同期の割り込み（UK 機で20 ms ごと）で進む。CTRL-STOP で止まる。

### PLAY(n) [WIKI-PLAYF]

- n = 0 は全体、1〜3 は各声部。演奏中なら −1、終われば 0。PLAY の直後は −1。

## MSX の拡張音源（概要）

- Konami SCC（http://web.archive.org/web/2012id_/http://bifi.msxnet.org/msxnet/tech/scc.html）: 5音の波形メモリー（32バイト、符号付き8ビット）、12ビットの周期、4ビットの音量、エンベロープなし。ch4 と ch5 は波形を共用（SCC+ は独立）。f = 3579545 / (32 × (TP+1))。
- MSX-MUSIC / YM2413 OPLL（https://bitsavers.mirrorservice.org/components/yamaha/YM2413_198604.pdf）: 2オペレーターの FM、旋律9音または旋律6音 + リズム5音。内蔵音色15 + ユーザー音色1（同時に1つ）。正確に合成するには内部の EG、位相、ログサインの表などの実装が必要で、作業量が大きい。

## Atari ST

出典: Dosound/Giaccess https://freemint.github.io/tos.hyp/en/xbios_interface.html 、https://st-news.com/issues/st-news-volume-2-issue-3/education/the-xbios-dosound-function 、YM 形式 http://leonard.oxg.free.fr/ymformat.html 、STE の DMA https://discmaster.textfiles.com/view/22208/VECTRONIX2.iso/FILES_01/STE_ADRE.LZH/STEPROGR.DOC

- YM2149（2 MHz）。$FF8800 で選択と読み出し、$FF8802 で書き込み。ポート A はディスクやプリンターの制御に使われる。
- Dosound（XBIOS 32）: `00〜0F data` レジスタへ書く、`80 data` 一時レジスタへ、`81 reg inc end` 一時レジスタを書いて inc を足すのを end まで tick ごとに繰り返す、`82 n` n tick 待つ（0 で終わり）。tick は50 Hz。
- Giaccess（XBIOS 28）: レジスタの読み書き。
- MFP タイマーの技法（クロック 2,457,600 Hz、÷4〜÷200、8ビットのカウント）:
  - デジドラム: トーンとノイズを無効にした声部の音量に、タイマーの周期でサンプルを書く。
  - SID ボイス: タイマーで音量を0と最大の間で切り替え、矩形波と掛け合わせる（C64 風の音）。
  - Sinus-SID: 4ビットの正弦波のデジドラム。
  - Sync-Buzzer: タイマーで R13 を書き、エンベロープをやり直し続ける。
- STE の DMA サウンド: 符号付き8ビット、ステレオ（ワードの上位が左）またはモノラル、6258 / 12517 / 25033 / 50066 Hz、1回再生か繰り返し、開始と終了のアドレスは二重バッファ。LMC1992 で音量（−80〜0 dB）、低音と高音（±12 dB）、YM との混合。
- YM 形式（YM2!〜YM6!）: 50 Hz ごとのレジスタのダンプ（YM5/YM6 は16バイト/フレーム）。ヘッダにクロック、フレームの周波数、ループの位置、デジドラム。YM6 は1フレームに効果を2つ（SID、デジドラム、Sinus-SID、Sync-Buzzer）。公開されているファイルはほぼ LHA で圧縮されている。

## C64 の SID（MOS 6581 / 8580）

出典: [DS] MOS 6581 データシート http://www.6502.org/documents/datasheets/mos/mos_6581_sid.pdf 、[YAN] Bob Yannes へのインタビュー https://landley.net/history/mirror/commodore/yannes.html 、[WIKI-C64] https://www.c64-wiki.com/wiki/SID 、[WP] https://en.wikipedia.org/wiki/MOS_Technology_6581 、[OXY] https://www.oxyron.de/html/registers_sid.html 、[R-ENV] https://docs.rs/resid-rs/latest/src/resid/envelope.rs.html 、[R-ENV-OLD] https://sources.debian.org/src/lmms/0.4.10-2.3/plugins/sid/envelope.cc 、[R-WAVE] https://docs.rs/resid-rs/latest/src/resid/wave.rs.html 、[R-FLT] https://sources.debian.org/src/lmms/0.4.10-2.3/plugins/sid/filter.cc 、[R-VOICE] https://sources.debian.org/src/lmms/0.4.10-2.3/plugins/sid/voice.cc 、[CH20] https://gist.github.com/munshkr/30f35e39905e63876ff7 、[HVSC] https://www.hvsc.c64.org/download/C64Music/DOCUMENTS/SID_file_format.txt
reSID 系（GPL）はコメントにある動作と数値だけを参照し、コードは見ていない。

### レジスタ（$D400〜$D41C）[DS]

ボイス1（ボイス2は +7、ボイス3は +14）:

| Offset | 名前 | 内容 |
|---|---|---|
| $00/$01 | FREQ LO/HI | 16ビットの周波数 |
| $02/$03 | PW LO/HI | 12ビットのパルス幅 |
| $04 | CONTROL | NOISE PULSE SAW TRI TEST RING SYNC GATE（bit7→0） |
| $05 | AD | Attack（上位4）/ Decay（下位4） |
| $06 | SR | Sustain（上位4）/ Release（下位4） |

| Addr | 名前 | 内容 |
|---|---|---|
| $D415/$D416 | FC LO/HI | 11ビットのカットオフ（LO の下位3ビット + HI 8ビット） |
| $D417 | RES/FILT | RES（上位4）、FILT EX、FILT3、FILT2、FILT1 |
| $D418 | MODE/VOL | 3OFF、HP、BP、LP、VOL（下位4） |
| $D419/$D41A | POTX/POTY | パドル（読み出し） |
| $D41B | OSC3 | オシレーター3の上位8ビット（読み出し） |
| $D41C | ENV3 | ボイス3のエンベロープ（読み出し） |

- SYNC と RING の相手: ボイス1 ← オシレーター3、ボイス2 ← 1、ボイス3 ← 2。
- PW: デューティ = PW / 40.95 %。0 と $FFF は一定の DC、$800 で50%。
- フィルターのモードは足し合わせ（LP + HP でノッチ）。3OFF はフィルターを通らないボイス3を消す（変調源専用にする）。VOL は16段の線形。

### オシレーター

- 24ビットの位相アキュムレーターに毎サイクル FREQ を加える。Fout = Fn × Fclk / 16777216 [DS]。
- クロック: PAL ≈ 985248.6 Hz（17734475/18）、NTSC ≈ 1022727.3 Hz（14318182/14）[OXY]。
- 波形（12ビット）[YAN][R-WAVE]:
  - のこぎり波: 上位12ビット。
  - 三角波: MSB が1なら下位11ビットを反転し、左へ1ビットシフト。
  - パルス: 上位12ビットを PW と比べて全0か全1（比べる向きは未確認）。
  - ノイズ: 23ビット LFSR（bit22 XOR bit17 → bit0、左シフト）[OXY]。アキュムレーターの bit19 でクロック [R-WAVE]。出力に使う8ビットの番号は出典で2ずれている（[R-WAVE] 22,20,16,13,11,7,4,2 / [OXY] 20,18,14,11,9,5,2,0、未確認）。
- TEST: アキュムレーターを0に保つ。戻すと LFSR は 0x7FFFF8 [R-WAVE]。
- ハードシンク: 相手の MSB が 0→1 になったサイクルで自分を0にする [R-WAVE]。
- リング変調: 三角波の MSB を「自分の MSB XOR 相手の MSB」に置き換える [R-WAVE]。
- 合成波形: データシートは「論理 AND」とするが、実際の値は単純な AND と違い、reSID は 6581/8580 別の実測の表を使う。ノイズと他の波形を重ねると LFSR が0で埋まって鳴らなくなる [DS][YAN]。

### ADSR [DS][R-ENV][R-ENV-OLD]

- 8ビットのアップダウンカウンター。Attack は線形、Decay/Release は区分線形の指数近似。

| 値 | Attack | Decay/Release | 周期（サイクル） |
|---|---|---|---|
| 0 | 2 ms | 6 ms | 9 |
| 1 | 8 ms | 24 ms | 32 |
| 2 | 16 ms | 48 ms | 63 |
| 3 | 24 ms | 72 ms | 95 |
| 4 | 38 ms | 114 ms | 149 |
| 5 | 56 ms | 168 ms | 220 |
| 6 | 68 ms | 204 ms | 267 |
| 7 | 80 ms | 240 ms | 313 |
| 8 | 100 ms | 300 ms | 392 |
| 9 | 250 ms | 750 ms | 977 |
| 10 | 500 ms | 1.5 s | 1954 |
| 11 | 800 ms | 2.4 s | 3126 |
| 12 | 1 s | 3 s | 3907 |
| 13 | 3 s | 9 s | 11720 |
| 14 | 5 s | 15 s | 19532 |
| 15 | 8 s | 24 s | 31251 |

- 指数近似の分周: エンベロープ値 255 で1、93 で2、54 で4、26 で8、14 で16、6 で30、0 で1。
- Sustain: 16段で、実効のレベルは $00, $11, …, $FF。
- 0 に達すると止まり、Attack へ移るまで動かない。
- ADSR バグ: レートカウンター（15ビット。旧版の記述では16ビット）は状態が変わってもリセットされず、新しい周期より大きい値にいると 0x8000 まで数えて戻る。最大約33 ms エンベロープが動かない。回避策は「ハードリスタート」（具体的な手順は未確認）。

### フィルター [DS][YAN][R-FLT][WP]

- 2つの積分器による状態変数フィルター。LP/HP 12 dB/oct、BP 6 dB/oct。共振は4ビット。
- FC は11ビットで線形とデータシートは書くが、範囲の記述がページで食い違う（30 Hz〜10 kHz / 30 Hz〜12 kHz）。
- 実機: 6581（470 pF）は約220 Hz〜18 kHz で tanh 状の非線形、個体差が大きく歪む。8580 は約30 Hz〜12 kHz でほぼ線形、共振が強い。
- reSID のモデルでは Q ≈ 0.707 + res/15（近似）。
- 6581 の音量レジスタのデジ再生: 出力に DC オフセットがあるため、VOL を書き換えると4ビットのサンプルになる。8580 は小さい [CH20]。

### 出力と 6581/8580 の違い

- 波形の D/A（12ビット）→ エンベロープの乗算 D/A（8ビット）→ フィルターまたは直接 → マスター音量（4ビット）[YAN]。
- 6581 のボイスのゼロ点は理想の 0x800 ではなく実測 0x380 付近で非対称。8580 はオフセットなし [R-VOICE]。

| 項目 | 6581 | 8580 |
|---|---|---|
| 電源 | 12 V（NMOS） | 9 V（HMOS-II） |
| フィルターのコンデンサ | 470 pF | 22 nF |
| カットオフ | 非線形、個体差大 | ほぼ線形 |
| 合成波形 | 小さく濁る | 大きく明瞭 |
| DC オフセット / $D418 デジ | あり / よく鳴る | ほぼなし / 小さい |

### SID ファイル（PSID/RSID）[HVSC]

- 見出しはビッグエンディアン。magicID、version（1〜4）、dataOffset、load/init/play のアドレス、曲数、開始の曲、speed、name/author/released（各32バイト）、flags（クロック PAL/NTSC、SID のモデル）。6502 のコードを含むので、再生には CPU のエミュレーションが必要（参考のみ）。

### 未確認・食い違い

ノイズの出力ビット、レートカウンターの幅、フィルターの範囲、TEST 中のパルスの値（DC か 0xFFF か）、パルスの比較の向き、波形 × エンベロープの式、ハードリスタートの手順、C64 Programmer's Reference Guide は参照していない。

## NES / ファミコン（2A03 NTSC / 2A07 PAL）の APU

主な出典は NESdev Wiki（2026-11-07 に取得）。エミュレーターのソースは参照していない。

### クロック（https://www.nesdev.org/wiki/Cycle_reference_chart）

| 方式 | マスタークロック | 分周 | CPU | フレーム |
|---|---|---|---|---|
| NTSC (2A03) | 21.477272 MHz | ÷12 | 1.789773 MHz | 60.00 Hz |
| PAL (2A07) | 26.601712 MHz | ÷16 | 1.662607 MHz | 50.00 Hz |
| Dendy | 26.601712 MHz | ÷15 | 1.773448 MHz | 59.46 Hz |

APU サイクル = 2 CPU サイクル。

### レジスタ（https://www.nesdev.org/wiki/APU）

| アドレス | ch | ビット | 意味 |
|---|---|---|---|
| $4000/$4004 | Pulse1/2 | `DDLC VVVV` | D=デューティ、L=エンベロープのループ兼長さ停止、C=固定音量、V=音量またはエンベロープ周期 |
| $4001/$4005 | Sweep | `EPPP NSSS` | E=有効、P=周期、N=反転、S=シフト |
| $4002/$4006 | Timer lo | `TTTT TTTT` | |
| $4003/$4007 | Len/Timer hi | `LLLL LTTT` | 書くとエンベロープ再始動、位相リセット |
| $4008 | Triangle | `CRRR RRRR` | C=長さ停止兼リニアカウンター制御、R=再ロード値 |
| $400A/$400B | Tri timer | | $400B を書くとリニアカウンターの reload フラグ |
| $400C | Noise | `--LC VVVV` | |
| $400E | Noise | `M--- PPPP` | M=短周期モード、P=周期の番号 |
| $400F | Noise len | `LLLL L---` | |
| $4010 | DMC | `IL-- RRRR` | IRQ、ループ、レート |
| $4011 | DMC | `-DDD DDDD` | 7ビットの出力レベルを直接設定 |
| $4012 | DMC | アドレス = $C000 + A×64 | |
| $4013 | DMC | 長さ = L×16 + 1 バイト | |
| $4015 W/R | Status | `---D NT21` / `IF-D NT21` | チャンネル有効化／状態 |
| $4017 | Frame | `MI-- ----` | M=モード（4-step/5-step）、I=IRQ 禁止 |

### パルス（https://www.nesdev.org/wiki/APU_Pulse）

- f = f_CPU / (16 × (t+1))、t は11ビット。
- デューティ（出力順8ステップ）: 0 = `01000000`（12.5%）、1 = `01100000`（25%）、2 = `01111000`（50%）、3 = `10011111`（75%）。
- 無音になる条件: シーケンサーの出力0、スイープの目標周期 > $7FF、長さカウンター0、t < 8。
- エンベロープ（https://www.nesdev.org/wiki/APU_Envelope）: クオーターフレーム（約240 Hz NTSC）で動く。開始時に減衰レベル15、V+1 回ごとに1減る。0 で L=1 なら15へ戻る。C=1 なら V がそのまま音量。
- スイープ（https://www.nesdev.org/wiki/APU_Sweep）: 変化量 = 周期 >> S。反転は Pulse1 が1の補数（−c−1）、Pulse2 が2の補数（−c）。ハーフフレームで更新。目標 > $7FF でミュート（E=0 でも）。PAL のハーフフレームを「96 Hz」とする記述の根拠は未確認（計算では約100 Hz）。
- 長さカウンター（ハーフフレームで1減る）の表:

| idx | 値 | idx | 値 | idx | 値 | idx | 値 |
|---|---|---|---|---|---|---|---|
| $00 | 10 | $08 | 160 | $10 | 12 | $18 | 192 |
| $01 | 254 | $09 | 8 | $11 | 16 | $19 | 24 |
| $02 | 20 | $0A | 60 | $12 | 24 | $1A | 72 |
| $03 | 2 | $0B | 10 | $13 | 18 | $1B | 26 |
| $04 | 40 | $0C | 14 | $14 | 48 | $1C | 16 |
| $05 | 4 | $0D | 12 | $15 | 20 | $1D | 28 |
| $06 | 80 | $0E | 26 | $16 | 96 | $1E | 32 |
| $07 | 6 | $0F | 14 | $17 | 22 | $1F | 30 |

### 三角波（https://www.nesdev.org/wiki/APU_Triangle）

- 32ステップの4ビット: 15,14,…,0,0,1,…,15。f = f_CPU / (32 × (t+1))（同じ t ならパルスより1オクターブ低い）。
- 音量の制御はない。リニアカウンター（クオーターフレーム）と長さカウンターの両方が0でないときだけ進み、止まると値を保つ。
- 周期0で超音波（55.9 kHz）になり、平均の値が出る（ポップ音の原因）。

### ノイズ（https://www.nesdev.org/wiki/APU_Noise）

- 15ビット LFSR、初期値1。feedback = bit0 XOR（M=1 なら bit6、M=0 なら bit1）、右へシフトし bit14 へ入れる。
- 周期: M=0 で32767ステップ、M=1 で93または31ステップ。bit0 = 1 のとき出力0。
- 周期の表（CPU サイクル）:

| P | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | A | B | C | D | E | F |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| NTSC | 4 | 8 | 16 | 32 | 64 | 96 | 128 | 160 | 202 | 254 | 380 | 508 | 762 | 1016 | 2034 | 4068 |
| PAL | 4 | 8 | 14 | 30 | 60 | 88 | 118 | 148 | 188 | 236 | 354 | 472 | 708 | 944 | 1890 | 3778 |

### DMC（https://www.nesdev.org/wiki/APU_DMC）

- 1ビットの差分: 1 なら +2（126未満のとき）、0 なら −2（1より大きいとき）。出力レベルは7ビット（0〜127）。LSB から読む。
- ループ、IRQ（ループなしで終わったとき）。$4011 に続けて書けば PCM を鳴らせる。
- レート（CPU サイクル/ビット）:

| R | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | A | B | C | D | E | F |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| NTSC | 428 | 380 | 340 | 320 | 286 | 254 | 226 | 214 | 190 | 160 | 142 | 128 | 106 | 84 | 72 | 54 |
| PAL | 398 | 354 | 316 | 298 | 276 | 236 | 210 | 198 | 176 | 148 | 132 | 118 | 98 | 78 | 66 | 50 |

NTSC の R=F は約33.1 kHz、R=0 は約4.18 kHz。

### フレームカウンター（https://www.nesdev.org/wiki/APU_Frame_Counter）

- Q（クオーター）= エンベロープとリニアカウンター、H（ハーフ）= 長さカウンターとスイープ。
- 4-step（NTSC、APU サイクル）: 3728.5 Q / 7456.5 Q+H / 11185.5 Q / 14914.5 Q+H と IRQ。IRQ の周期は29830 CPU サイクル（PAL 33254）。
- 5-step: 3728 Q / 7456 Q+H / 11185 Q / 14914 なし / 18640 Q+H、IRQ なし。
- .5 の表記は取得結果の要約で一部落ちている可能性あり（未確認）。

### ミキサー（https://www.nesdev.org/wiki/APU_Mixer）

- `pulse_out = 95.88 / (8128 / (p1 + p2) + 100)`
- `tnd_out = 159.79 / (1 / (t/8227 + n/12241 + d/22638) + 100)`（分母の和が0なら0）
- 表による近似: `pulse_table[n] = 95.52 / (8128.0/n + 100)`（31要素）、`tnd_table[n] = 163.67 / (24329.0/n + 100)`（203要素、n = 3t + 2n + d）。
- 線形近似: `0.00752*(p1+p2)`、`0.00851*t + 0.00494*n + 0.00335*d`。
- 出力フィルター: NES は1次ハイパス90 Hz と1次ローパス14 kHz。ファミコンは1次ハイパス37 Hz。440 Hz のハイパスは旧版の Wiki（ミラー）にはあるが現行版にはない（出典の食い違い）。

### ファミコンの拡張音源（各チップの NESdev Wiki のページ）

- VRC6: パルス2（デューティ 1/16〜8/16、4ビット音量）、のこぎり波1。
- VRC7: YM2413 派生の FM 6音、固定音色15 + ユーザー1、リズムなし。
- FDS: 64ステップ × 6ビットの波形表1音、変調表で FM 風の音程変化、音量エンベロープ。
- MMC5: パルス2（スイープなし）、8ビット PCM 1。
- Namco 163: 最大8音の4ビット波形メモリー（128バイトの RAM を共用）。時分割の出力のため、8音で14.9 kHz の切り替え雑音。
- Sunsoft 5B: YM2149F 相当（Gimmick! のみが使用）。
- https://www.nesdev.org/wiki/Expansion_audio は404で取得できず。

### NES 向けの MML とトラッカー

- MCK/PPMCK（https://wikiwiki.jp/mck/MML%E3%83%AA%E3%83%95%E3%82%A1%E3%83%AC%E3%83%B3%E3%82%B9）: `t` `l` `o` `v` `q` `D`（デチューン）、`s`（ハードウェアのスイープ）。マクロ `@n={…}`（デューティ列）、`@v`（音量列）、`@EP`（音程の加算列）、`@EN`（音符の加算列）、`@MP`（ソフトウェアの LFO）。`|` 以降がループ部分。`@DPCM`、ループの `L`、`[ … | … ]n`。`@MP` の引数の数は資料により3つと4つで食い違う。
- FamiTracker（https://dn-programming-core-management.github.io/Dn-help/hlp/2a03.htm）: 楽器は、フレームごとに進む列（音量、アルペジオ、音程、デューティ）。各列にループ点 `|` とリリース点 `/`。
- 共通する考え方: 「フレーム単位の値の列 + ループ点 + リリース点」を音量・デューティ・音程・音符の各列に同じ形で持たせる。

## Amiga の Paula と ProTracker の MOD 形式

出典: [A] Amiga Hardware Reference Manual 第5章 https://www.amigarealm.com/computing/knowledge/hardref/ch5.htm 、[A2] 音量の節 https://scratch.grimore.org/HARDWARE_MANUAL_GUIDE/node00dc.html 、[B] 付録B https://sblive.w10.site/ZX-Spectrum/AMIGAHardware/APPENDIXB.html 、[C] ADKCON https://amigadev.grimore.org/Hardware_Manual_guide/node0194.html 、[D] Free Pascal の Amiga 定数 https://www.freepascal.org/daily/packages/amunits/hardware/ 、[E] pt2-clone の pt2_paula.c のコメント（BSD-3）https://raw.githubusercontent.com/8bitbubsy/pt2-clone/master/src/pt2_paula.c 、[G] https://forum.renoise.com/t/disabling-amiga-internal-filter/46412 、[H] https://www.aes.id.au/modformat.html 、[I] FMODDOC https://resources.openmpt.org/resources/FMODDOC.txt 、[J] https://wiki.openmpt.org/Manual:_Effect_Reference 、[K] https://wiki.openmpt.org/Development:_Test_Cases/MOD 、[L] AHX http://ftp.modland.com/pub/documents/format_documentation/Abyss%27%20Highest%20eXperience%20(.ahx).txt

### レジスタ（$DFF000 からのオフセット）[B]

| レジスタ | ch0 | ch1 | ch2 | ch3 | 内容 |
|---|---|---|---|---|---|
| AUDxLCH/LCL | 0A0/0A2 | 0B0/0B2 | 0C0/0C2 | 0D0/0D2 | 開始アドレス（チップ RAM、ワード境界） |
| AUDxLEN | 0A4 | 0B4 | 0C4 | 0D4 | 長さ（ワード単位） |
| AUDxPER | 0A6 | 0B6 | 0C6 | 0D6 | 周期（クロック数/サンプル） |
| AUDxVOL | 0A8 | 0B8 | 0C8 | 0D8 | 音量 0〜64 |
| AUDxDAT | 0AA | 0BA | 0CA | 0DA | データ（2サンプル） |

- DMACON（096）: bit15 SET/CLR、bit9 DMAEN、bit0〜3 AUD0EN〜AUD3EN [A]。
- ADKCON（09E）の変調ビット: bit7 USE3PN、6 USE2P3、5 USE1P2、4 USE0P1、3 USE3VN、2 USE2V3、1 USE1V2、0 USE0V1 [C][D]（一部は並びからの推定）。
- INTENA/INTREQ: AUD0 = bit7、AUD3 = bit10 [D]。AUD1 = 8、AUD2 = 9 は推定（未確認）。

### 動作

- サンプルは符号付き8ビット、1ワードに2サンプル（上位バイトが先）[A]。
- 周波数 = クロック / 周期。クロックは NTSC 3,579,545 Hz、PAL 3,546,895 Hz [A]。例: 周期428 で PAL 8287.14 Hz、NTSC 8363.42 Hz [I]。
- 最小周期は NTSC 124、PAL 123（DMA の上限は28,867サンプル/秒）[A]。pt2-clone は113未満を113に丸め、周期0を65536として扱う [E]（出典間で違う）。
- 音量 0〜64、64 = 0 dB、32 = −6.0 dB、1 = −36.1 dB で、振幅に比例 [A2]。HRM は「6ビット」としながら64を最大とする矛盾がある。
- ステレオ: ch0 と ch3 が左、ch1 と ch2 が右に固定 [A]。
- 変調（アタッチ）: そのチャンネルは音を出さず、データで1つ上のチャンネルの音量（bit6〜0）または周期（16ビット）を変える [A]。
- DMA: 再生の開始時に LC/LEN を内部へ写し、直後に割り込み。そこで LC/LEN を書き換えると次の区間から有効。書き換えなければ同じ区間を繰り返す [A]。周期は次に読むとき、音量はサンプルを取るときに反映 [E]。
- MOD の一般的な使い方: 最初は全体を1回鳴らし、その後ループの区間を指すように書き換える [K]。

### 出力フィルター

| 項目 | pt2-clone [E] | フォーラム [G] |
|---|---|---|
| A500 の固定 RC ローパス | 約4421 Hz、6 dB/oct | 4900 Hz |
| LED フィルター（切り替え式） | 2次 Sallen-Key、約3091 Hz、Q≈0.66 | 3275 Hz、12 dB/oct Butterworth |
| A1200 の固定フィルター | 約34.4 kHz（実質なし） | 実質なし |
| ハイパス | 約5.1 Hz（A500）、5.3 Hz（A1200） | |

- LED フィルターは電源 LED の明るさの制御と共通のビットで切り替え、MOD の E0x がこれを使う [A]。
- 補間をせず、サンプルを周期の間そのまま保つ（ゼロ次ホールド）。一次資料での明示は未確認。

### MOD 形式 [H][I]

| オフセット | サイズ | 内容 |
|---|---|---|
| 0 | 20 | 曲名 |
| 20 | 30×31 | サンプルの見出し |
| 950 | 1 | 曲の長さ（1〜128） |
| 951 | 1 | restart（慣例で127） |
| 952 | 128 | 順序表 |
| 1080 | 4 | 署名（"M.K."、"M!K!"、"FLT4"、"4CHN"/"6CHN"/"8CHN"）。なければ15サンプルの形式 |
| 1084〜 | | パターン、続いてサンプル |

- サンプルの見出し（30バイト）: 名前22、長さ2（ワード）、ファインチューン1（下位4ビット、−8〜7、1/8半音）、音量1（0〜64）、ループ開始2、ループ長2（すべてビッグエンディアン）。
- パターン: 64行 × 4チャンネル × 4バイト。セル = `wwwwxxxx xxxxxxxx yyyyzzzz zzzzzzzz`（サンプル番号 = wwww と yyyy、周期12ビット、エフェクト12ビット）。
- 周期の表（ファインチューン0）:

| 音 | C | C# | D | D# | E | F | F# | G | G# | A | A# | B |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 856 | 808 | 762 | 720 | 678 | 640 | 604 | 570 | 538 | 508 | 480 | 453 |
| 2 | 428 | 404 | 381 | 360 | 339 | 320 | 302 | 285 | 269 | 254 | 240 | 226 |
| 3 | 214 | 202 | 190 | 180 | 170 | 160 | 151 | 143 | 135 | 127 | 120 | 113 |

  16通りのファインチューンの表は [I] にある。

- エフェクト: 0xy アルペジオ、1xx/2xx ポルタメント上下、3xx トーンポルタメント、4xy ビブラート、5xy/6xy 継続 + 音量スライド、7xy トレモロ、8xx（PT では未使用）、9xx サンプルオフセット（xx×256。単位は出典で食い違う）、Axy 音量スライド、Bxx ジャンプ、Cxx 音量、Dxx パターンブレイク（行は10進）、E0x フィルター、E1x/E2x 細かいポルタメント、E3x グリッサンド、E4x/E7x 波形、E5x ファインチューン、E6x パターンループ、E9x リトリガー、EAx/EBx 細かい音量、ECx カット、EDx ディレイ、EEx パターンディレイ、EFx インバートループ、Fxx 速さ/テンポ。
- 初期値 speed 6、BPM 125。Fxx は 00〜1Fh が speed、20h 以上が BPM（[I][J]、[H] は境界が1ずれる）。1 tick = 2.5/BPM 秒（125 BPM で50 Hz）。
- ビブラートの sine の表（32要素）: `0,24,49,74,97,120,141,161,180,197,212,224,235,244,250,253,255,253,250,244,235,224,212,197,180,161,141,120,97,74,49,24`。変化量 = 値 × 深さ / 128（トレモロは / 64）[I]。
- トラッカーによって解釈が分かれる動作は [K] のテストケースに一覧がある（音符なしのサンプル切り替えは現在のループの後に効く、など）。

### AHX（Amiga の合成型チップチューン）[L]

- 4チャンネル、4〜128サンプルの短い波形（三角波、のこぎり波、矩形波、ノイズ）をループし、パルス幅の変調、フィルターの変調、ADSR、ビブラートを毎フレーム書き換えて C64 風の音を作る。後継の HivelyTracker は16チャンネル。

### ライセンス（参照のみ）

- MOD 形式は事実上の公開形式。libmodplug はパブリックドメイン、libxmp は現在 MIT（古い版は LGPL）、libopenmpt は BSD-3、pt2-clone は BSD-3、UAE 系は GPL。コードは使わない。

## 音の出力層とスレッド

### Windows: waveOut（winmm）

- `waveOutOpen`（`WAVE_MAPPER`）→ `waveOutPrepareHeader` → `waveOutWrite`。通知は `CALLBACK_EVENT` を自前のスレッドで待つ形が素直（https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/nf-mmeapi-waveoutopen）。
- `CALLBACK_FUNCTION` の中で他の wave 関数を呼ぶとデッドロックする（https://learn.microsoft.com/en-us/previous-versions/dd743869(v=vs.85)）。
- 装置がない: `waveOutGetNumDevs` が0、`waveOutOpen` は `MMSYSERR_BADDEVICEID` / `MMSYSERR_NODRIVER` など（実際にどれが返るかは未確認）。
- 形式: 16ビット PCM が最も安全。float は `WAVEFORMATEXTENSIBLE` で指定できるが waveOut で受け付けられるかは未確認。
- 遅れ: 公式の値はない。体験談では20〜50 ms 程度（未確認）。Vista 以降、MME は共有モードのオーディオエンジンの上で動く。

### Windows: WASAPI（共有モード、イベント駆動）

- 手順: `CoInitializeEx` → `IMMDeviceEnumerator` → 既定の出力装置 → `Activate(IID_IAudioClient)` → `GetMixFormat` → `Initialize(SHARED, EVENTCALLBACK, 0, 0, fmt)` → `SetEventHandle` → `GetService(IAudioRenderClient)` → 「イベント待ち → `GetCurrentPadding` → `GetBuffer` → 書く → `ReleaseBuffer`」（https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-iaudioclient-initialize）。
- 既定の周期は10 ms。`IAudioClient3` なら標準の HDAudio で 2.66〜10 ms（https://learn.microsoft.com/en-us/windows-hardware/drivers/audio/low-latency-audio）。
- `AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM` で形式とサンプリング周波数の変換をエンジンに任せられる。
- 装置の抜き差しで `AUDCLNT_E_DEVICE_INVALIDATED`。作り直しが必要。
- Zig からは COM の vtable を手書きする（4つのインターフェース、数百行の見込み、※推測）。

### Linux

- ALSA（libasound.so.2）: `snd_pcm_open` → `snd_pcm_set_params`（全体の遅れを µs で指定）→ `snd_pcm_writei`、アンダーランは `snd_pcm_recover`（https://www.alsa-project.org/alsa-doc/alsa-lib/group___p_c_m.html）。
- PulseAudio Simple API（libpulse-simple.so.0）: `pa_simple_new` → `pa_simple_write`（ブロックする）。自前のスレッドで回す設計に合う（https://freedesktop.org/software/pulseaudio/doxygen/simple.html）。
- WSLg は PulseAudio のサーバーを動かし、`PULSE_SERVER` を設定済み（https://github.com/microsoft/wslg）。WSLg では ALSA の `default` がないという報告があり、確実なのは PulseAudio の経路。
- PipeWire: `pw-play` は標準入力の raw を読める（既定 48000 Hz、2 ch、s16）。pipewire-pulse の互換性の公式の記述は未確認。
- 静的リンクの musl 版（dlopen できない）: (a) 外部のコマンド `pacat` / `pw-play` / `aplay` へパイプで送る（依存なし、実装は小さい）、(b) PulseAudio のネイティブのプロトコルを自前で実装（仕様書がなく作業量が大きい）、(c) OSS `/dev/dsp`（既定では使えないことが多いと推測）。

### SDL3 と小さいライブラリ

- SDL3: `SDL_OpenAudioDeviceStream` とコールバック（任意のスレッドから、SDL のロックの中で呼ばれる）。zlib ライセンス。静的 musl では使えない。
- miniaudio: パブリックドメインまたは MIT-0。WASAPI/WinMM/ALSA/PulseAudio などに対応。既定で実行時にリンクするので静的 musl では動かないと推測。
- sokol_audio: zlib。Linux の既定は PulseAudio をリンク。

### 比較

| 方法 | 遅れの目安 | 依存 | 静的 musl | 作業量 |
|---|---|---|---|---|
| waveOut | 20〜50 ms（未確認） | OS 標準 | 対象外 | 小 |
| WASAPI | 10 ms + 装置 | OS 標準 | 対象外 | 中 |
| ALSA（dlopen） | 指定できる | libasound | 不可 | 小〜中 |
| PulseAudio Simple（dlopen） | サーバー次第 | libpulse-simple | 不可 | 小 |
| 外部コマンドへのパイプ | パイプ + サーバー（未確認） | コマンドの存在 | 可 | 小 |
| SDL3（dlopen） | 未確認 | SDL3 | 不可 | 小 |

### スレッドと合成

- 音のスレッドではロック、メモリーの確保、ファイル I/O、待つ呼び出しを避け、ロックを使わない待ち行列を使う。
- Windows: `AvSetMmThreadCharacteristicsW("Games" / "Pro Audio")` で優先度を上げる（失敗は無視）（https://learn.microsoft.com/en-us/windows/win32/api/avrt/nf-avrt-avsetmmthreadcharacteristicsw）。
- Linux の SCHED_FIFO は一般の利用者では `RLIMIT_RTPRIO` が0のため使えないことが多い（https://man7.org/linux/man-pages/man7/sched.7.html）。
- 48 kHz で合成すれば多くの経路で変換を避けられる見込み（※推測）。
- 矩形波の折り返し雑音: BLEP / PolyBLEP（不連続点の前後だけを補正）。blip_buf（Shay Green）は LGPL なので、コードは使わず「状態が変わる時刻に帯域制限したステップを足す」考え方だけを参考にする（http://www.slack.net/~ant/libs/audio.html）。

### 調査した者の推奨（提案）

1. Windows は WASAPI を本命にし、waveOut を予備にする。
2. Linux（動的リンク）は PulseAudio Simple を第一、ALSA を予備にする。
3. 静的 musl は `pacat` → `pw-play` → `aplay` の順にパイプで送る。
4. SDL3、miniaudio、sokol_audio は主な経路にしない（参考資料にする）。
5. 合成は48 kHz 固定、BLEP 型の帯域制限、コアの API は「N フレームを作る」決定的な関数にする。


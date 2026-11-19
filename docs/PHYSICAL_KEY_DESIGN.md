# 物理キーの詳細設計（997）

2026-11-19。管理：997／1079（設計）→1080（実装）→1081（Windows/Linux自動受け入れ）。**設計・実装・統合レビュー・自動受け入れと1087（Windows US）・1089（Windows JIS追加確認）は完了。リモート81294afのMac1082・Linux JIS1090の実機記録も統合済み（tqueは両方完了）。旧Linux US1088は取り込み時のtqueでは見つからず、先行WSLg記録は実装記録に保持する。**

[設計レビュー原文](reviews/997-design-claude-review.md)、[採否・対応](reviews/997-review-response.md)、[実装・検証記録](PHYSICAL_KEY_IMPLEMENTATION.md)を区別する。

## 目的と配置

利用者決定は、物理キーをEKEYへ混ぜずGRAPHICSの別の語で読むこと。文字列・IME確定文字・端末のエスケープ列からキー位置を推定しない。USB HID Keyboard/Keypad usage page 0x07の8ビット番号を使う。0〜3は通常キーとして生成しない。ページの違う音量・メディアキーやFnは対象外。

`KEY-HELD?` の文字／特殊キーと同時16個の契約は維持する。新しい状態は256ビット、押下／解放のキューは256件。INKEY、EKEY、KEY、KEY?の読取りと独立し、物理キーの読取りも文字入力を消費しない。端末・SIXEL・Tkでは対応を偽装しない。nativeウィンドウの入力が対象。

| 配置 | 責任 |
|---|---|
| 本体コアの内部部品 | ホスト非依存の番号、Event、Tracker、範囲／論理メモリ検査、Writerのoptional interface。一般のInputEventには物理キーを追加しない |
| GRAPHICSディスパッチ | 公開語、定数、ホスト呼出し。graphics=falseでは公開しない。EXTENSIONのEKEYには語を置かない |
| nativeホスト | Windowsのメッセージ、AppKit子プロセス、X11/XKBをホスト所有のTrackerに渡す。UIスレッドからForth Stateには触らない |
| AUDIO | 追加なし |

900/1064の所有権・画像境界に従う。共有するのは純粋な内部の型であり、メインの入力資源をワーカーへ共有しない。

## 公開語

| GRAPHICSの語 | スタック効果 | 契約 |
|---|---|---|
| SCAN-INPUT? | `( -- flag )` | nativeウィンドウが開き、対応付けが利用可能ならtrue。ウィンドウを自動で開かない |
| SCAN-SUPPORTED? | `( scan -- flag )` | 現在の入力元が、そのキーの実際の押下と解放を両方届けられるならtrue。範囲外は-24、未対応／予約0〜3はfalse |
| SCAN-HELD? | `( scan -- flag )` | 最後に取り込んだ状態。0〜255を受理し、範囲外は-24。未対応時はfalse |
| KEY-EVENT | `( -- scan kind true \| false )` | kind=1押下、2解放、3再同期要求。履歴→再同期要求→falseの順。available=falseでも閉鎖前の履歴と再同期要求を読む。3ではscan=0 |
| KEY-RESYNC | `( addr -- )` | 論理メモリ内の32バイトへ、番号nの状態を`addr+n/8`のbit(n%8)として写し、履歴を消す。通常は再同期要求も消す。通信snapshot待ちの場合は要求を残す |
| SC-A…SC-Z、SC-0…SC-9 | `( -- scan )` | 印字文字ではなくキー位置。各OS表と一致させる |
| SC-LSHIFT/SC-RSHIFT等 | `( -- scan )` | 左右CTRL/SHIFT/ALT/GUI（224〜231）。矢印、編集、F1〜F24、テンキー、国際キーも対応表にある番号を定数化 |

kindはSC-PRESS=1、SC-RELEASE=2、SC-RESYNC=3として公開する。下位の組込み入口はGFX-SCAN-INPUT?、GFX-SCAN-SUPPORTED?、GFX-SCAN-HELD?、GFX-KEY-EVENT、GFX-KEY-RESYNCの5語。SC-*は既存K-*と同じくgraphics.fsのCONSTANTで定義する。

既存Builtin番号と登録順を動かさず、所定の末尾へ追加する。組込み語の追加で辞書ABIは変わり、builtin_count／ABIの異なる既存イメージは現行の検査で拒否される。形式番号と旧イメージ互換を混同しない。定数一覧、英日リファレンス・HELP・使用例は実装時に同時更新する。

ホストのoptional opsが無い場合は未対応として扱う。SCAN-INPUT?、SCAN-SUPPORTED?、SCAN-HELD?はfalse。KEY-EVENTはfalse。KEY-RESYNCはアドレス検査後に全0を写す。端末・SIXEL・Tkだけの場合も同じ。ただし以前のnativeウィンドウの解放履歴はKEY-EVENTから取り出せる。

## 状態機械と有界の履歴

`src/core/physical_keys.zig` のTrackerは`bitmap[32]`、`events[256]`、head/count、resync_required、staleを持つ。available、supported bitmap、通信の連番はホスト側に置く。ヒープ確保、時計、OS依存はない。

押下はfalse→true、解放はtrue→falseだけを記録する。同じ状態の通知（autorepeat含む）は記録しない。押して離してからVMが読む場合も2件残す。

257件目でoverflowしたら、先の256件を残し、resync_required=trueとする。heldの更新は続ける。その間は新しいedgeを入れず、KEY-EVENTは残った履歴を順に返し、その後は毎回`0 SC-RESYNC true`を返す。KEY-RESYNCを早く呼べば未読履歴も捨てる。全履歴を読み終える義務はない。

KEY-RESYNCはbitmapの採取と履歴／要求のackを同一ロック内で行い、その後のedgeから再び順序を保証する。ただしstale=true（通信で最新状態を取り寄せ中）なら要求を消さない。最新snapshotを受けた時点でstaleを解除し、古い履歴を破棄して改めて再同期要求を立てる。消費側は新しいsnapshotをKEY-RESYNCで採取してackする。

短押しの履歴が失われたことは通知できるが、失われた時刻／回数は復元できない。638の端末デコーダの「キー／文字を捨てない」とは別の保証で、[共通ルール4節](ASYNC_COMMON_RULES.md)の種類B1に従う。SCAN-HELD?は履歴を消費しない。stale中のbitmapは最後に得た情報なので、権威ある最新状態の保証は再同期要求が消えた後に限る。

### フォーカス・閉鎖・境界

- フォーカス喪失：既存の短押しを保って、heldキーすべての解放edgeを追加する。満杯なら通常のoverflow。全heldは必ず0になる。
- 閉鎖／接続切断／子終了：全解放し、全0が確定したのでstaleを解除してからavailable=false。履歴と再同期要求は残す。再openでは旧履歴を勝手に消さず、新しい実際の通知から追跡する。
- 辞書復元成功／XKB物理対応表の変更：boundaryでheld=0、履歴clear、stale=false、再同期要求=true。復元前のTracker履歴を残さない。
- フォーカス再取得／復元境界では押下状態を推定して補わない。既に押したままのキーは、次に届く実際の通知から追跡する。

境界はホストTrackerに取り込まれた状態を消す。**OSやMacのpipeにまだ残っていて、境界より後に取り込む通知は、新しい到着通知として処理する。OS上の発生時刻を基準に過去の通知を排除する保証はしない。** 全OSで同じ境界を採り、入力世代handshakeを追加しない。この範囲をマニュアルと復元試験にも明記する。

## ホスト口・ロック・復元

Writerのoptional PhysicalKeyOpsはavailable、supported、held、next、resync、resetを持つ。ホストが既存の所有lockでTrackerを保護する。WindowsはSRW lock、Linuxは既存guard、Mac親側はVMスレッドだけで読むので追加lockなし。Mac子側の状態／連番／dirtyは短いphysical_guardで保護する。stdout_lockはtry-lockだけを使い、取得できなければdirty snapshotへ集約する。純粋なTracker自身はロックを持たない。

ロック中にOS待機やIPCをしない。resyncは一度のロックで値を作業領域へコピーし、履歴を消す。releaseAllも一度のロックで全解放する。呼出し元が同じlockを再帰取得しないよう、既存のロック保持範囲と照合して接続する。

KEY-RESYNCの手順は次のとおり。

1. `State.memoryAddress(addr, 32)`で検査。失敗はInvalidAddress（-9）。ホストにもメモリにも触らない。整列は要求しない。
2. `ops.resync(ctx, *[32]u8)`でZig側の作業領域へ写す。失敗しないホスト口とする。
3. 論理メモリへ32バイトをコピーし、`address_registry.written(self, addr, 32, false)`で書込みを通知する。

範囲外のscanはInvalidNumber（-24）。値の絞り込みより前に検査する。エラー番号は`src/core/defs.zig`のerror表で確認済み。

辞書イメージにheld／キュー／OS番号／ポインタを保存しない。`image_restore.apply`内の`words_graphics.clearImage(state)`の隣で、非失敗のphysical reset口を呼ぶ。preflight失敗時は呼ばない。resetはTracker境界だけを変更し、OS／IPC待機や子への命令を行わない。

### ワーカーとの境界

GRAPHICS入力はowner-only資源。ただしForthワーカー実行文脈・語のガードは現時点では未実装（1049〜1053の計画）。997で存在しないガード／専用エラーを実装済みとしない。将来のワーカーWriterはPhysicalKeyOps=nullとし、語の静的／動的な許可検査でも上記5語を入力・UIとして禁止する。既存の資源台帳WrongOwnerを、Forth語の実行ガードとして流用しない。

## Windows

WM_KEYDOWN/WM_SYSKEYDOWN/WM_KEYUP/WM_SYSKEYUPの先頭で、lParamのSet1 make code（bit16〜23）と拡張bit24からHIDへ変換する。WM_SYSKEYUPは新たに取り込む。VKだけでUS文字配列を組み立てない。

左右Shift/Ctrl/Alt/GUI、通常Enter/テンキーEnter、通常slash/テンキーdivide、ナビゲーション／テンキーを区別する。Alt+Enter等のホストshortcutも物理通知は分岐前に取り込む。WM_CHAR/IMEは従来どおり。

Windowsではusage53（USのgrave／JISの半角全角位置）と136（カタカナ／ひらがな）をsupported=falseとし、物理状態・edge・snapshotへ入れない。JIS実機でIME処理後の通常通知にup→downが記録され、保持が残ったための制約。53はUS配列でも同じ物理位置を対象外とする。文字入力・IME切替は既存経路を維持する。Raw Inputへの切替は行わない。

Pause（非拡張0x45）とPrintScreenはsupported=false。NumLockは拡張0x45で区別する。両Shift時の欠落keyupは16msのUIタイマーでGetKeyStateと照合し、解放だけを補う。タイマーを作れなければ左右Shiftもunsupportedにする。電源・音量などのシステムキーもWindows/Macではunsupportedとする。対応しない合成通知を推測で補わない。WM_KILLFOCUSで全解放、WM_DESTROYで全解放後にunavailable。複数キーボードの個別識別、Raw Input、グローバルフックは範囲外。

## macOS

keyCode→HIDは固定表。修飾のflagsChangedは左右のdevice-dependent maskとaggregate maskを照合する。CapsLockはtoggle状態を物理heldにせずsupported=false。Fnなどページ外も対象外。

物理通知はNSApplication派生クラスのsendEvent:で、親クラスへ渡す前にKeyDown/KeyUp/FlagsChangedを取り込む案を採用する。sharedApplicationより前にクラスを登録する。※推測です：viewへ届かないCommand併用時の通知も拾えると見込む。Objective-Cの呼出し／メソッド登録を実装時に一次資料で確認し、1082で実際のCommand+キーとkey equivalentを試す。文字用viewのkeyDown/insertText経路は維持する。

### 親子IPCと損失復旧

現在のoutputInputは非keep行を捨て、keep用2048バイトも満杯なら捨てる。そのまま使って損失なしとはしない。物理行は独立した損失復旧を持つ。

- `INPUT SCAN <seq> <usage> <0|1>`：実際のedge。子ごとの単調増加連番。
- `INPUT SCANSNAP <seq> <64桁hex>`：その連番までを反映した全32バイト状態。
- 親→子`SCANSYNC`：最新snapshotを要求。

子は状態・連番・dirtyをphysical_guardで保護する。stdout_lockはtry-lockとし、出力スレッドがblocking write中でも物理キーの状態更新と命令の読取りを進める。SCANの非blocking writeに失敗したらdirtyとし、以後edgeを送らず最新snapshotを保持する。最新snapshotの送信が成功してからedge送信を再開する。行は512バイト以下で、既存stdout出力と同じlock下でatomicに送る。物理行をkeep用キューへ入れない。

最後の解放だけを落とした場合にも回復するため、命令読取りスレッドのreadParentLoopを`poll(fd0, 16ms)`を伴う方式へ変更し、各周期にsnapshotの送信を試す。新しいNSTimerが既にあるとは扱わない。AppKitスレッドは待たせない。通常のFRAME／QUITやEOFの終了処理を維持する。stdoutが書けない場合もコマンド入力を進める。

親はenqueueInputLineで物理行を処理する。pollだけでなくSHOW中のreadUntil/readFrameStatusやclose中にも取り込む。連番飛び／不正な物理行はTracker.transportLostでstaleと再同期要求を立て、SCANSYNCを非blocking送信する。送れなければ次の読取り機会に再送。9バイト全部の送信が成功したら再送待ちを消し、同じ要求をポーリングごとに重複送信しない。読取り時は待たずに取得できるデータだけを処理し、GUI待機へ入らない。

SCANSNAP到着までKEY-RESYNCは最後のbitmapをコピーして履歴を消すが、要求を消さない。snapshot受信後に要求を立て直す。子のdirty再送は、親からの要求が書けなくても最新状態を送る。子ごとに連番を初期化し、新しいpipeを開くstartChildで親の受信状態も初期化する。復元時の世代handshakeは行わず、前節の到着順の境界を適用する。復元resetでもホスト側の期待連番／SCANSYNC再送待ちは消さず、後から届くsnapshotで再同期要求を立て直す。

子側フォーカス喪失・終了前の全解放と、親のEOF時の全解放を実装する。親が死んだときの子終了の既存契約を保つ。IPCに対して無制限のスレッド／バッファを追加しない。連番はu64のwrapping加算。Receiverもwrapを許し、古いsnapshotは半周の差で拒否する。通常のstdoutのblocking出力は既存契約のままだが、物理側はstdoutを待たない。

## Linux X11

982/994〜996の既存X11入力へ接続する。keycodeから固定8を引いてevdev番号とみなす方法は採用しない。XKB GetNamesの4バイトkey name（AD01、AC01、LFSH等）からHIDへの表を作り、keysymは文字入力だけに使う。対応名のあるusageだけsupported=true。

Connectionへxkb_opcodeを保存し、NamesNotifyも購読する。GetNamesのUnavailable／消費済みX11 error packetだけをcatchして物理機能をunsupportedにする。期限切れ・途中読取り・イベント退避満杯はプロトコルの継続安全性がないため伝播し、既存の切断処理へ渡す。X11のPAUSは実際の解放を保証しないのでunsupported。正式名COMPもMenuとして受理する。NewKeyboardNotify/NamesNotifyで再取得し、対応表が実際に変わった場合だけboundary。取得失敗もboundaryとし、次の通知で回復を試す。keysymだけのMapNotifyで物理表を失効させない。

detectable autorepeatが無い場合は、既存の同一keycode/timestampのrelease/press対の抑止を通してからTrackerへ渡す。受信直後のphysical_down=falseをTrackerへ反映せず、保留releaseがrepeat対とならずに確定した時だけ解放する。FocusOut、切断、closeで全解放。Wayland直接接続、evdev keyboard専有、グローバル入力は追加しない。

### XKB wire形式の確認

2026-11-19、[xcb-protoのXKB定義](https://github.com/freedesktop-unofficial-mirror/xcb__proto/blob/master/src/xkb.xml)をGitHub APIから確認。GetNamesはminor opcode17、deviceSpec=UseCoreKbd 0x100、whichのKeyNames=bit9。要求bodyはdeviceSpec u16、pad2、which u32（X11共通4バイトheaderとは別）。KeyNameは4バイト。

replyは共通8バイトに続き、which u32（offset8）、min/maxKeyCode（12/13）、nTypes（14）、groupNames（15）、virtualMods u16（16）、firstKey/nKeys（18/19）、indicators u32（20）、nRadioGroups/nKeyAliases（24/25）、nKTLevels u16（26）、pad4（28）。KeyNamesだけを要求し、reply.whichもそれだけであることを検査する。valueListはoffset32からnKeys×4バイト。firstKey+nKeysは広い整数で計算して256以下、reply長も検査してから読む。既存little-endian読取り口を使い、ホスト構造体をwireへcastしない。

NamesNotifyのxkbTypeは6。SelectEventsの選択bitとdetail、aliases、未知名の扱い、無効長、名前なし、マップ変更による失効は1084でprotocol定義と照合して実装・試験する。

## 実装順と完了条件

1. 1079：詳細設計のClaude Codeレビューと採否／修正記録。
2. 1080：1083 pure Tracker→1084 native host／Writer Ops→1085 GRAPHICS語・定数・検査・復元reset・語参照→1086統合レビュー。コードは段階ごとにClaude Codeレビュー。
3. 1081：Windows/Linuxでnative入力と公開語を実行し、Macクロスコンパイル、除外構成を確認。短押し、全状態、範囲外、左右修飾、repeat、focus、overflow、stale snapshot、文字入力独立、復元成功／失敗、optional opsなし、IPC欠落を検証。ワーカーの実行ガード試験は1049〜1053へ引き継ぐ。
4. 1082：Mac実機でAppKit、Command併用、左右修飾、focus、最後の解放の通信損失と回復、全体／除外構成を実行。コンパイル／合成イベントと実機確認を区別する。

5. 実キーボードはOS・配列ごとに分離する。1087：Windows US（完了）、1088：Linux US、1089：Windows JIS追加確認（完了、53/136対象外）、1090：Linux JIS。国際キー・左右同時押下と片方解放・IME併用を対象OSで確認し、合成通知で完了にはしない。

JIS/USの実キーボード・IMEを試していない場合はその旨を記録し、自動テストだけで実機確認済みとしない。997は実機まで閉じない。1042のfocus/close通知は本物理入力の全解放経路を再利用し、別のheld表を作らない。

## 参照とライセンス

既存実装：`src/core/host_interface.zig`、`graphics_input.zig`、`words_graphics.zig`、`image_restore.zig`、`src/host_window{,_macos,_linux}.zig`、`src/host_x11.zig`。共通規則：[ASYNC_COMMON_RULES](ASYNC_COMMON_RULES.md)、[CORE_EXTENSION_DETAILED_DESIGN](CORE_EXTENSION_DETAILED_DESIGN.md)。

2026-11-19にGitHub APIから確認したSDL一次実装：[HID対応番号](https://github.com/libsdl-org/SDL/blob/main/include/SDL3/SDL_scancode.h)、[Windows変換表](https://github.com/libsdl-org/SDL/blob/main/src/events/scancodes_windows.h)、[Darwin変換表](https://github.com/libsdl-org/SDL/blob/main/src/events/scancodes_darwin.h)、[AppKit修飾処理](https://github.com/libsdl-org/SDL/blob/main/src/video/cocoa/SDL_cocoakeyboard.m)。表やアルゴリズムを翻案する場合はzlib許諾の著作権・免責・条件を残し、改変版と明記して第三者表示へ追加する。SDLライブラリへの新規依存は導入しない。xcb-protoのXMLをコードへ翻案する場合もMIT許諾の表示条件を確認する。

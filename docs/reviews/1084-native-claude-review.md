# 1084 Claude Codeホスト接続レビュー原文

2026-11-19。読み取り専用。指摘後に修正したため原文と最終コードは区別する。レビュー自体は実行試験をしていない。

## 依頼

```text
Read-only implementation review for task1084 native physical-key input (part of997). Read docs/PHYSICAL_KEY_DESIGN.md, src/core/physical_keys.zig Host/Ops, src/physical_key_map.zig, src/physical_key_protocol.zig, src/host_window.zig physical ops and WndProc hooks, src/host_window_linux.zig physicalNames/event/key/run/entry, src/host_x11.zig enableDetectableRepeat/physicalNames/parsePhysicalNames, src/host_window_macos.zig physical wrapper/receiver/child sender/applicationSendEvent/readParentLoop, src/main.zig Writer wiring. Do not edit files or execute commands. User explicitly requests Claude Code review while continuing development. Identify concrete high/medium bugs and exact fixes, especially lock ownership, closure/reopen, unsupported behavior, XKB selects/length/failure/reload/autorepeat, Windows Set1 special codes, Mac snapshot loss/latest state/seq/atomic pipe writes/EOF/binary FRAME interleaving/blocked stdout/timer fairness, ObjC sendEvent/super ABI. Mapping table includes original SDL zlib notice; actual physical keyboard and Mac runtime remain unverified. Public words and docs are being added separately, don't treat their incompleteness as a native implementation defect. Return concise Japanese ranked findings, no speculation as fact. No tests claimed.

```

## 原文

# task1084 native物理キー入力 実装レビュー

ファイルは読むだけで、編集もコマンド・テストの実行もしていません。挙げた問題点はすべてコードを読んで判断したもので、実機では確かめていません。Windows/macOSのOS側の挙動に関わる項目は、根拠を項目ごとに書いています。

## High

**H1. Mac親：`SCANSYNC`を送りすぎ、届いたsnapshotのたびに履歴が消える**
- 場所：`src/host_window_macos.zig:18-21`
- 内容：`sync_pending`の間、`physical()`を呼ぶたびに`SCANSYNC`を書いています。たとえば`SCAN-HELD?`をポーリングするループでは、要求が大量に出ます。
- 結果：子は要求の数だけ`SCANSNAP`を返します。Receiverは最初のsnapshotで`sync_pending=false`にしますが、続くsnapshotも受理します（seqが古くないため）。そのたびに`replaceSnapshot`の`loseHistory`が走り、間に届いたedgeが捨てられ、再同期要求も立ち直します。
- 修正：Receiverに`sync_sent`を追加します。
  - 書込みが成功したら`true`にし、snapshotを受けたら`false`に戻します。
  - 再送するのは、書込みが失敗したとき（EAGAIN）と、一定時間内に返答がないときだけにします。
  - 子側でも、`SCANSYNC`を受けたら`physical_dirty=true`にするだけにし、送信はループ先頭の`physicalFlush`に任せて1回にまとめます。

**H2. Windows：Pause・PrintScreenの扱いが設計と合っていない**
- 場所：`src/physical_key_map.zig:22`（index 69＝非拡張の0x45→83）、`src/host_window.zig:1019`
- Pause：Win32のlParamでは、NumLockが拡張付きの0xE045、Pauseが拡張なしの0x45で届くという理解です。この表では、Pauseを押すとNumLock（83）のedgeになります。この理解は、設計が参照しているSDLの`WindowsScanCodeToSDLScanCode`の0x45特例と照合してください。
- PrintScreen：Windowsは通常WM_KEYDOWNを送りません。SDLは、keyupの時点で押下を合成して補っていると記憶しています（一次資料での確認が必要です）。この実装は押下を補わないので、release-onlyで、Trackerには一度も押下が記録されません。それでもsupportループが70を`supported=true`にしています。設計の「両edgeを取れないキーはsupported=false」に反します。
- 修正：
  - `windowsScan`で、拡張なしの0x45を0にします。
  - `support`ループで70と72を除外します。どちらも実際の解放時刻は取れません。

## Medium

**M1. Mac親：閉鎖後に届いた物理行で、staleが残り続ける**
- 場所：`src/physical_key_protocol.zig:23`、`src/host_window_macos.zig:654`
- 内容：`!host.has(scan)`は、`available=false`のときもBad扱いになり、`transportLost`でstale=trueになります。`CLOSED`やEOFの後に`SCAN`行が来た場合です。
- 結果：再openの`startChild`は`physical_receiver = .{}`で`sync_pending=false`に戻しますが、`tracker.stale`はそのままです。`SCANSYNC`は送られず、新しい子のedgeは`if (!host.tracker.stale)`で全部捨てられます。子が自分でdirtyになるまで、この状態から抜けません。
- 発生しやすさ：起き得る経路は確認できていません。ただ、起きると回復しません。
- 修正：
  - `accept`で、`!host.available`なら物理行を読み捨てて`true`を返します。
  - `startChild`では`.sync_pending = physical_state.tracker.stale`として、要求を引き継ぎます。

**M2. Windows：左右Shiftを同時に押すと、片方が押されたままになる**
- 内容：両Shiftを押して片方を離すと、WM_KEYUPが届かないというWindowsの挙動です。この知識はSDL2のポーリング処理のコメントによるもので、実機では確認していません。現在の実装には、これを補う処理がありません（`src/host_window.zig:1043-1049`）。
- 修正：VK_SHIFT（0x10）のWM_KEYUP/WM_SYSKEYUPを処理した後、`GetKeyState(VK_LSHIFT/VK_RSHIFT)`の上位bitを見ます。離れているのにheldのままになっている225/229だけを解放します。押下は補いません。

**M3. Linux：`physicalNames`がすべてのエラーを握りつぶし、X11の通信がずれたまま続く可能性がある**
- 場所：`src/host_window_linux.zig:345`、`src/host_x11.zig:305-315`
- 内容：GetNamesへのサーバーのエラー（kind 0）を「未対応」とするのは安全です。しかし、次の場合もcatchされます。
  - `reply()`のイベント退避が満杯になったとき：イベントを1件読んで捨て、replyは未読のまま残ります。
  - 期限切れで途中まで読んだとき。
- 結果：未読のreplyが残ると、後で`event()`の`kind == 1`で`error.Failed`になり、ウィンドウごと落ちます。
- 修正：X11のエラーpacketを区別できるerror（例：`error.XError`）を`next`/`reply`に設けます。`physicalNames`でcatchするのはそれと`Unavailable`だけにし、他は呼出し元へ伝えます。

**M4. Mac子：stdoutが書けないとき、命令読取りスレッドがロック待ちで回り続ける**
- 場所：`src/host_window_macos.zig:1377-1381`（`physicalFlush`）、`:1629`（`SCANSYNC`処理）、`:1723-1733`（`output()`）
- 内容：`output()`は、`stdout_lock`を持ったままブロッキングwriteします（`CLOSED`、`FRAME-READY`、`ERROR`）。この間、読取りスレッドの`physicalFlush`はspinlockで回り続け、命令を読めません。設計の「stdoutが書けない場合もコマンド入力を進める」を満たしません。AppKitスレッドの`physicalChildEdge`も同じロックで回ります。
- 修正：
  - `physicalFlush`と`SCANSYNC`の処理は`cmpxchg`による1回だけのtry-lockにし、取れなければその周期は送信を飛ばします。
  - 状態と連番は、短時間だけ持つ別のロックで保護します。stdoutはtry-lockでだけ扱い、失敗したらdirtyにします。

## Low

- **L1. Mac `darwin[63]`（Fn）→231**：flagsの照合でほぼ何も起きませんが、設計は「Fnは対象外」です。0にしておくのが明確です（`src/physical_key_map.zig:23`）。
- **L2. Mac修飾キー**：device-dependent bitを出さないキーボードの場合です。aggregateで代用しているため、両Shiftを押してから右を離すと、229が残り得ます（`:1414`）。Apple純正キーボードでは問題になりません。
- **L3. 音量キーとPowerの扱い**：127〜129（Mute/VolUp/VolDown）と102（Power）がWindows・Mac両方の表で`supported=true`になります。設計の「ページの違う音量・メディアキーは対象外」と一致していません。表から除くか文書に書くか、どちらかに決める必要があります。
- **L4. X11の`PAUS`**：ハードウェア上、実際の解放時刻はありません。H2に合わせるなら`supported=false`です。
- **L5. XKBのMenuキー**：xkeyboard-configのevdevでは、正式名が`COMP`で`MENU`は別名だと理解しています（要照合）。GetNamesは正式名を返すので、Menuキーが未対応になる可能性があります。
- **L6. 表の長さ**：`windows`/`darwin`は`[_]u8`なので、長さを型で保証していません。windows表が256件ちょうどかは数えていません（未確認）。`[256]u8`/`[128]u8`に変えてください。
- **L7. コメント**：`src/host_x11.zig:333`のコメントは「NewKeyboardNotify + MapNotify」ですが、値0x43はNamesNotify（bit6）も含みます。値は正しく、コメントだけ直せば済みます。

## 問題を確認しなかった項目（コードを読んだ範囲）

- **ロック**：Windowsの`windowGone`→`close`、WM_KILLFOCUS、hookと`physical()`は、それぞれ1回ずつロックを取っていて、二重に取る箇所はありません。Linuxの`key`/`releaseFocus`/`physicalNames`/`physicalQuery`も同じです。
- **XKBの要求形式**：GetNamesの要求body、reply長と`first+count≤256`の検査、SelectEventsの`selectAll`は、設計に書いたwire形式と一致しています。
- **XKBの再取得**：NewKeyboardNotify/NamesNotifyで、対応表が変わった場合と取得失敗の場合だけboundaryにしています。
- **autorepeat**：対になったrelease/pressをTrackerへ渡さない流れになっています。
- **Mac子の送信**：
  - 物理行は128バイト以下で、PIPE_BUF以内の非blocking writeです。
  - dirtyのときはedgeを止め、最新snapshotが送れたら再開します。
  - 送るsnapshotは送信時点の連番の状態です。
  - EOFでQUITを積みます。
- **FRAMEとの混在**：途中で失敗した場合は`failChild`で子を終了させるので、`SCANSYNC`が画素データに混ざる経路は見当たりません。
- **ObjCの呼出し**：`objc_msgSendSuper`と{receiver, NSApplication}の組合せ、`v@:@`、`sharedApplication`より前のクラス登録、modifier maskの値。
- **SDLの許諾表示**：zlib許諾の表示と「Altered」の明記があります。

物理キーボード、Mac実機、JIS/USでの実地確認はまだです。

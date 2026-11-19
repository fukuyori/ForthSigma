# 997 Claude Code設計レビュー原文

2026-11-19。読み取り専用。実装・実行結果・採否とは区別する。

## 依頼

```text
Read-only design review for task997/1079. Read docs/PHYSICAL_KEY_DESIGN.md and verify against docs/EMULATOR_CORE_PLAN.md section8, ASYNC_COMMON_RULES.md, CORE_EXTENSION_DETAILED_DESIGN.md owner-only/restore rules; src/core/host_interface.zig, words_graphics.zig, image_restore.zig; src/host_window.zig Windows key paths; src/host_window_linux.zig event and repeat; src/host_x11.zig; src/host_window_macos.zig keyDown/keyUp, outputInput and parent IPC. Do not change files or run commands. User delegated concrete design decisions to review. Return concise Japanese ranked issues and exact adopted resolutions, not questions. Resolve especially: availability vs pending resync on close; bitmap snapshot address validation and all-or-none semantics; worker guard; no-window behavior; reset during dictionary restore with old native queued events; Mac child generation handshake and loss snapshot acknowledgement without blocking UI; CapsLock truthful API; XKB key names failure/reload. Can simplify architecture if existing project supports it. State what must be source-verified before implementation. This review is design-only; don't claim tests. Conclude whether design task can be closed after corrections.

```

## 原文

# 997/1079 設計レビュー結果（読取りのみ）

レモンさん、クロです。読取りだけで照合しました。ファイルの変更、コマンドの実行、ビルド、テストはしていません。

## 結論

下の修正を設計書に入れて、採否を別文書に記録すれば、設計タスク1079は閉じられます。設計の段階で決めるべき点はすべて採用案に落としました。残りは、1080の実装時にソースや一次資料で確かめる項目と、1082のMac実機確認です。

## 重要度順の指摘と採用した解決

### 1.【高】ワーカーのガードが、存在しない既存契約を前提にしている
- 根拠：`src/` にはForthのワーカーVMもタスクランタイムもありません（`worker` の一致は `main.zig` のテスト1件だけ）。また `runtime_base.zig` の `WrongOwner` は資源台帳用で、語の実行を止める仕組みではありません。
- **採用**：ガードは構造で行います。`Writer.physical_key_ops` を任意の項目（`gamepad_ops` と同じ形）にし、ワーカー用のWriterではnullにします。nullのときの動作は「未対応」と同じです。CORE_EXTENSION_DETAILED_DESIGN §11の監査表の方針（許可しないcallbackはnull、入力・UIは初期許可に含めない）に合わせます。4つの語は、1049/1052で作る禁止語の表へ「入力・UI」として登録します。997ではガードのコードを書きません。設計書の「既存の共通エラー契約を使う」は、この記述に置き換えます。

### 2.【高】Macの世代番号と待ち合わせは不要。設計を簡単にできる
- 根拠：親側の `poll`/`readChildInput`/`enqueueInputLine` は、すべてForthを実行するスレッドで動き、親にUIスレッドはありません。子プロセスは `startChild` ごとに新しいpipeで起動します。
- **採用**：
  - 世代番号、ready応答、復元時の子への通知は**やめます**。連番は子プロセスごとに0から数え、`startChild` で親の受信側も初期化します。
  - 復元時のresetは、親のTrackerだけを境界状態にします（IPCもOSの待機もしません）。pipeに残っていた古いSCAN行は、0の状態の上に辺として適用します。この扱いは後の6と同じです。
  - 親のTrackerにはロックを付けません（触るのは1つのスレッドだけ）。
  - SCAN行の処理は `enqueueInputLine` に置きます。こうすると、`readUntil` と `readFrameStatus`（SHOW中）や `close` の読取りでも行を失いません。

### 3.【高】Macの損失を知らせるsnapshotの再送に、16msのtimerが存在しない
- 根拠：子にNSTimerはありません。親からの命令を読むスレッド `readParentLoop` は `read(0)` で止まったまま待ちます。また、`outputInput` はkeep用の溜まりがある間、新しい行を書きません。
- **採用**：
  - 子の256個の状態、連番、dirtyの印は、既存の `stdout_lock` の下に置きます。SCAN行はkeep用の2048バイトを使いません。待たずに書けなかったらdirtyにし、それ以降の辺は送らずにsnapshotだけを溜めます。
  - 読むスレッドは `poll(0, 16ms)` で待つ形に変え、時間切れのたびに `stdout_lock` の下でsnapshotの送信を試みます。AppKitのスレッドを止めません。
  - 行は `INPUT SCAN <seq> <usage> <0|1>` と `INPUT SCANSNAP <seq> <64桁hex>` の2種類で、512バイト以下です。
  - 親が連番の飛びを見たら、待たない書込みで `SCANSYNC\n` を送ります。書けなかったら、次の読取りのときに再送します。
- **KEY-RESYNCの扱い**：Trackerに `stale`（正しい状態の到着待ち）を足します。staleの間のKEY-RESYNCは、bitmapを写して履歴を消しますが、`resync_required` は**消しません**。SCANSNAPを受けたら状態を置き換えて、staleを解除し、resyncを立て直します。待つ処理は一切入れません。

### 4.【高】Macのkey upが欠けて、押したままに見える危険
- **採用**：物理キーの入口はviewの `keyDown:`/`keyUp:` ではなく、**NSApplicationの派生クラスの `sendEvent:`** に置き、KeyDown/KeyUp/FlagsChangedを先に取り込んでから親クラスへ渡します。派生クラスは `sharedApplication`（`host_window_macos.zig:1708`）より前に登録します。※推測です：Commandを押している間のkeyUpや、key equivalentに使われたkeyDownがviewへ届かない問題を、これで避けられると見ています。1082の実機で確認する項目です。
- 左右の修飾キーは、flagsChangedのkeyCodeとデバイス依存のmaskで判定します。

### 5.【高】「対応外」を正しく伝える公開語がない（CapsLockなど）
- **採用**：`SCAN-SUPPORTED? ( scan -- flag )` を追加します（内部名 `GFX-SCAN-SUPPORTED?`）。現在のホストが、そのキーの実際の押下と解放を両方届けられるときだけtrueを返します。
  - Mac：CapsLockはfalse。toggleの状態をheldとして返しません。
  - Windows：解放だけ、または押下だけしか届かないキーは、検証してから表でfalseにします。
  - X11：XKBの名前表に対応があるusageだけtrueです。
- 範囲外は他の語と同じく例外にします。番号は1、未対応のときはfalseです。

### 6.【中】availabilityと再同期要求の優先順（閉じたとき）
- **採用**：
  - 閉じる（WM_DESTROY、X11のDestroy/WM_DELETE、Macの子の終了）のは、**フォーカス喪失と同じ扱い**です。押されているキーごとに解放の辺を足し（満杯ならあふれ）、その後に `available=false` にします。履歴は捨てません。
  - **境界**（held=0、履歴を消す、resync_required=true）にするのは、辞書の復元と、X11で名前表が実際に変わったときだけです。開くときには立てません。
  - 優先順：KEY-EVENTは、キューの辺 → あふれ／境界によるRESYNC → false、の順で返します。availableとは無関係です。SCAN-HELD?は、未対応のときfalseです。KEY-RESYNCは常に働き、未対応なら全0を写してresyncを消します。
- 境界の後に押下を補わない規則はフォーカスの再取得と同じで、全OSで共通です。復元より前に押されたままのキーは、次の実際の押下から追跡します。

### 7.【中】あふれの扱いが共通の取り決めと食い違っている
- 根拠：ASYNC_COMMON_RULES §4と決定が要る点#8は「新しいものを捨て、印を立てる」です。設計書は「履歴を全部消す」としています。
- **採用**：共通の取り決めに合わせます。最初の256件を残し、それ以降の辺は捨ててresyncを立てます。KEY-EVENTは残した辺を返し終えてから、`0 SC-RESYNC true` を、KEY-RESYNCが呼ばれるまで返し続けます。早い短押しの情報が残るので、こちらのほうが得られる情報が多くなります。

### 8.【中】KEY-RESYNCのアドレス検査と全部か無しか
- 根拠：書込み禁止の領域という区別はありません。あるのは `State.memoryAddress` の範囲検査だけです。一括書込みのたびに `address_registry.written` を呼ぶのが慣例です（`gamepad.zig:77` など）。
- **採用**：
  1. `memoryAddress(addr, 32)` で検査し、失敗したら `InvalidAddress` をTHROWします。このときホストを呼びません。
  2. `ops.resync(ctx, *[32]u8)` は、ホストのロックの下でZig側の作業領域へ写し、履歴を消します。この段階は失敗しません。
  3. 論理メモリへ32バイトを写し、`written(self, addr, 32, false)` を呼びます。

  失敗すると、メモリもホストも変わりません。成功すると、32バイトを全部書いて状態を消します。整列は求めません。「書込み可能領域」という文言は「論理メモリ内の32バイト」に直します。

### 9.【中】復元時のresetの位置
- **採用**：`image_restore.apply` の中で、`words_graphics.clearImage(state)` の隣に `physical_keys.reset(state)` を置きます（`image_restore.zig:101`）。applyは失敗しない関数なので、`ops.reset` も `fn(?*anyopaque) void` にし、ホストのロックの下で境界状態にするだけにします。preflightに失敗した場合は呼ばれません。OSのメッセージキューにまだ残っている古いWM_KEY*（Windows）やX11のイベントは、6の規則で0の状態の上に適用されるので、世代番号はいりません。

### 10.【中】ロックの規則を簡単にする
- **採用**：共通のTrackerはロックを持たない純粋な構造体にし、各ホストの既存のロックで守ります（Windowsの `lock`（SRW）、Linuxの `guard`、Macの親はロックなし）。設計書の「独立した短いロック」と「ロックの順序の規則」は削ります。

### 11.【中】X11のXKB名前表の取得失敗と再読込み
- 根拠：`enableDetectableRepeat` はXKBのopcodeを保存せず、選択するイベントはNewKeyboard+Mapだけです。`event` が見ているのは `bytes[1]==0/1` だけで、map_dirtyの経路では `try` の失敗がウィンドウのループまで伝わります。
- **採用**：
  - `Connection` に `xkb_opcode` を保存します。
  - GetNames（key names）の失敗は `catch` して物理機能をunsupportedにします（`available=false`）。ウィンドウとINKEY/IMEは止めません。
  - NewKeyboardNotifyとNamesNotifyを受けたら取り直します。keycode→HIDの表が**実際に変わったときだけ**境界にし、取得に失敗したら境界にしてunsupportedにします。次の通知で再び試します。
  - MapNotify（keysymだけの変更）は物理表の境界にしません。
  - 自動repeatの抑止：trackerへの解放は、保留していた解放をペアにならずに流すとき（`host_window_linux.zig:648` と `:1115`）だけ渡します。解放を受けた時点で `physical_down=false` にしている箇所（:674）は、物理表への反映に使いません。

### 12.【中】Windowsの経路の不足
- 根拠：WM_SYSKEYUP（0x0105）は処理していません。Alt+Enterは `return 0` で途中で抜けます。
- **採用**：WM_KEYDOWN/KEYUP/SYSKEYDOWN/SYSKEYUPの先頭で、lParamのbit16〜23とbit24から物理の辺を取り込みます。Alt+Enterの分岐やDefWindowProcへ渡すより前です。WM_DESTROYでは6の閉じる処理、WM_KILLFOCUSではフォーカス喪失の処理をします。

### 13.【低】ABIについての記述
- 根拠：組込み語を足すとABIの署名が変わります（ASYNC_COMMON_RULES §8）。
- **採用**：「イメージ形式を変更せず」を「形式は同じだが、ABIの署名が変わり、古いイメージは読めない」に直します。SC-*の定数は既存のK-*と同じく `graphics.fs` の `CONSTANT` で定義し、組込み語は5語（`SCAN-SUPPORTED?` を含む）だけにします。

### 14.【低】ウィンドウがないとき
- **採用**：SCAN-INPUT?はfalseで、ウィンドウを自動では開きません。SCAN-HELD?は範囲を検査してからfalseを返します。KEY-EVENTは6の優先順に従います。KEY-RESYNCは検査してから全0を写します。端末、SIXEL、Tkのウィンドウでも同じです。graphics=falseのビルドでは語自体がありません。

## 実装前にソースや一次資料で確かめること（1080）
- `InvalidNumber` と `InvalidAddress` のTHROW番号（-24、-9）。今回の照合では、`main.zig` の -21 しか確認できていません。
- XKBのGetNamesとNamesNotifyのwire形式、選択するときのbit、aliasの扱い。X11の一次資料で確認します。
- Windows：Pause、PrintScreen、NumLockのscan codeと拡張bit、左右Shiftを両方押したときの解放の届き方。SDLの表を照合し、取り込むならzlibの表示を付けます。
- Mac：NSApplicationの派生クラスで `sendEvent:` を差し替えられること、flagsChangedのkeyCodeと左右のmask。`readParentLoop` を `poll` 型に変えたときに、FRAMEの受信と `output()` の待つ書込みとの関係。
- `main.zig` でWriterの各ホストの口をどう結線しているか（`gamepad_ops` と同じ形でよいか）。

## 実装と受け入れでの扱い
- 自動テストの結果を、配列や実機の確認として記録しません。
- Macの `sendEvent:` の効果、Commandを押している間のkeyUp、pipeが詰まったときの最後の解放の復旧は、1082の実機で確認します。

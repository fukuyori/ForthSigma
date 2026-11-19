# 638 最終レビュー原文

2026-11-19、読み取り専用。レビュー時点の指摘であり、現状の未解決一覧ではない。実行結果と採否は638-review-response.mdおよび実装記録を参照。

## 依頼

```text
Read-only final638 review. Previous findings in .work/638-review/implementation-result.json, file scope decision in file-scope-result.json. Current updates: EKEY-WAIT now stdin-only including redirected stdin; nonstdin INFILE rejects-21 before consuming, legacy EKEY/EKEY? selected files use old route unchanged; per-handle buffering followup1078 under639. Thus no new decoder backlog is created inside selected files, outer decoder saved/restored. beforeBytes flushes native32bytes via checked existing64-slot unread, byte-only embed ACCEPT fallback drains prefix+key_fn and CRLF. EOF peek retains EOF until consumption, restart resets paste/buttons preserving escape age, SGR128/horizontal ignored explicitly evenbyEKEY? (documenting this accepted filter), motion restores pressed button. New standard host pops raw lookahead3 directly and sourceRead no longer calls legacy buffered_key_fn. Separate mode_generation tracking means standard input no longer steals GRAPHICS restart bool. Clock arithmetic nowchecked (escape deadline), zero polling caps64source items; Win.next filters atmost32native records percall. Tests: 13pure/integration cases inclscope rejection, image reset, EOFpeek, restart; prior Win full suite passed, LinuxPTY10 +637PTY13 +NS, Windowsnative3 +old36+6378+ConPTY passed. Current finaltests rerunning. Read changed functions and testnewcases, identify concrete remaining issues (especially byte API fallback, EOF, parser overflow, stdio buffering). Do not modify or execute commands. Japanese, no permission questions.
```

## 原文

# 638 最終レビュー結果(読み取りのみ)

ファイルの変更とコマンドの実行はしていません。テスト結果は私は確認していないので、未確認です。`.work/638-review/final-result.json` は空でした。

読んだファイルは次のとおりです。
- `standard_event.zig`、`standard_sequence.zig`、`event_input.zig`、`input_redirect.zig`
- `words_extension.zig` の EKEY-WAIT、`words_xchar.zig` の `nextKey`、`words_terminal.zig` の `keyIor`、`graphics_input.zig` の `readInput`
- `host_input.zig:1-300`
- `main.zig` の lookahead・unread・`terminalStandardEvent`・`terminalRead`・redirected stdin
- `event_queue_test.zig` の13件

## 残っている問題(重要度の高い順)

**1. POSIX では、標準入力が GRAPHICS の restart フラグをまだ消費している(中)**
- 場所: `host_input.zig:189-192`、`host_input.zig:146-149`
- 何が起きるか:
  - `nextStandardPacket` の POSIX 側は `while (next())` を使っています。`next()` は `restarted` が true だと false に戻して `.restarted` を返し、それを `else => {}` が捨てます。
  - その結果、EKEY のあとの INKEY は restart を受け取れません。cooked 期間より前に端末から保持したキーが、捨てられずに残ります。
  - `mode_generation` で分けたので直ったのは Windows 側(`windows.next(true)` を直接呼ぶ)だけです。
- 修正: POSIX 側は `takePendingByte()` と `std.c.read(0, …)` を直接使い、`next()` を経由しないようにします。

**2. stdin → ファイル → stdin と入れ子にすると、2つ目の stdin デコーダーができる(低〜中)**
- 場所: `input_redirect.zig:16-28`
- 何が起きるか: 内側の `INFILE-EXECUTE` に stdin を渡すと、`changed` が true になり、新しい空のデコーダーで読みます。
  - 外側の EKEY? が先読みしたバイトは見えないまま、新しいバイトが先に読まれます(順序の逆転)。
  - 抜けるときは、内側に残ったバイト(先読み分や、timeout で途中まで読んだ UTF-8)を捨てます。
- 修正案:
  - 推奨: ファイルに入るときにデコーダーを入れ替えないようにします。代わりに `words_xchar.zig:132` の `takeByte`、`words_terminal.zig:19` と `input_redirect.zig:65` の `length` 判定を `selected(self) == null` のときだけ行います。選択ファイル側ではデコーダーに何も溜まらないので、この方法で足ります。
  - 最小案: 入れ替える前と、内側の stdin スコープを抜ける前に、`beforeBytes` でホストの lookahead へ戻します。

**3. バイトだけの埋込みホストで ACCEPT を使うと、CR のあとで1キー余分に待つ(低)**
- 場所: `input_redirect.zig:84-87`
- 何が起きるか: CR を読むと、LF かどうかを調べるために `key()` を必ず呼びます。対話型の `key_fn` はこれで止まり、次のキーが押されるまで ACCEPT が返りません。
- テスト `event_queue_test.zig:196` の偽ホストは止まらないので、この問題を検出できません。
- 修正: CR のあとは、`pending_key`・`pending_event_bytes`・デコーダーにバイトがあるとき、または `key_ready_fn` が true のときだけ、もう1バイト読みます。

**4. deferred のパケットが、バイト API をまたぐと順序が逆転する(低)**
- 場所: `event_input.zig:161-175`、`graphics_input.zig:478`
- 何が起きるか:
  - `beforeBytes` と GRAPHICS の `readInput` はバイトしか処理せず、`deferred` を残します。deferred に入るのは、Windows の特殊キー・マウス・WINCH などです。
  - 例: EKEY? で矢印キーを覗いた → ACCEPT で1行読んだ → EKEY が古い矢印キーを返す。
  - 旧経路の `pending_standard_event` も同じ動きなので、退行ではありません。
- 対処: 仕様として設計書に書くか、`beforeBytes` で paste と同じように破棄するかを決めてください。

**5. 途中まで届いたエスケープ列の最中に deferred が来ると、列が分かれる(低)**
- 場所: `standard_event.zig:127` の `self.deferred != null` で `ended` になる箇所
- 何が起きるか: POSIX ではリサイズの確認(`host_input.zig:177`)がバイトより先に行われます。`ESC [` まで届いた時点で WINCH が来ると、ESC が単独で確定し、残りの `1;5A` は文字として出ます。
- 対処: deferred は1個までという制約から来ているので、既知の制限として設計書に書くことを推奨します。直すなら、エスケープ列が途中の間は deferred があっても読み続けるように変えます。

**6. KEY? を使うと ESC の待ち時間がリセットされる(低)**
- 場所: `event_input.zig:163`
- 何が起きるか: `beforeBytes` は `escape_at = null` を無条件に実行します。unread_fn のないホストでは、途中の ESC がデコーダーに残ったまま待ち時間だけリセットされるので、KEY? → EKEY で 50ms の待ちが延びます。「escape の経過時間を保つ」という方針に反します。
- 修正: `length` が 0 になったときだけリセットします(`consume` が既にリセットしています)。

## 欠陥ではないが整理できる点
- `event_input.zig:58,75` の `selected(self) != null` の分岐は、到達しません。`modern()` の154行目で選択ファイルを拒否するので、`modern()` の157行目の `interrupts`/`controls` の条件も常に真です。`controls = false` の経路を通るのは、テスト139だけです。
- 次のテストがありません。
  - 主ホストの経路: デコーダー → `terminalUnread` → `readByte` で順序が保たれること、32バイトを戻せること
  - 上の1(POSIX の restart)と2(stdin の入れ子)

## 問題なしと確認した点
- **パーサーのあふれ**: `length` が32に達すると必ず ESC を確定します(106行)。paste 中の途中マーカーは6バイト以下、UTF-8 は4バイト以下です。deferred がある間は `ended` なので読み足しません。このため 166行の assert には到達しません。
- **EOF**: 先読みしても EOF が残り、消費したときだけ消えます(144-145行)。バイトが届くと消えます(163行)。
- **restart**: paste と buttons だけを消し、`escape_at` は残します。テスト176で確認されています。
- **ms=0**: 64回で打ち切ります。時刻の加算はオーバーフローを検査しており、テスト152で確認されています。
- **beforeBytes の容量**: デコーダーにバイトがあるとき、lookahead は空です。`terminalStandardEvent` が lookahead を先に取り出すためです。容量は 1+64 で、最大32バイトに足ります。
- **stdio のバッファ**: リダイレクトされた stdin は、POSIX では `read(0)`、Windows では `ReadFile` で1バイトずつ読みます(`main.zig:1276-1289`)。stdio のバッファがないので、poll や PeekNamedPipe から隠れるデータはありません。ハンドルごとのバッファは 1078 の範囲です。
- **新しいホストの lookahead**: `terminalStandardEvent` は lookahead を直接取り出し、byte 3 もそのまま渡します。`sourceRead` は `buffered_key_fn` を呼びません。

1〜3 は修正を推奨します。4〜6 は修正するか、設計書に書くかの判断をお願いします。

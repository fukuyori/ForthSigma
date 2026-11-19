# 1085 Claude Code公開語レビュー原文

2026-11-19。読み取り専用。指摘後に修正したため原文と最終コードは区別する。レビュー自体は実行試験をしていない。

## 依頼

```text
Read-only review of task1085 physical-key public words and tests. Read src/core/words_graphics.zig new gfx_scan_input/supported/held/key_event/key_resync and definitions/words/library_words, src/core/defs.zig appended enums, src/core/image_restore.zig reset hook, src/graphics/graphics.fs physical aliases and SC constants, src/tests/physical_key_test.zig, new HELP entries in src/core/help_text.zig, docs/PHYSICAL_KEY_DESIGN.md public contracts. Do not edit files or run commands. Focus on stack/memory atomicity, host consumption before failures, address_registry.written, range checks, availability/unsupported behavior, graphics=false ABI and saved-image reset/preflight, library registration scope and old Builtin IDs, aliases/constants correctness, meaningful test omissions. Native backend review is running separately. Verified so far: Windows native message-injection acceptance5 stages, full Zig tests, Mac compile; actual physical keyboards and Mac runtime unverified. Return concise Japanese concrete ranked findings and exact fixes. Don't claim execution.

```

## 原文

# task1085 物理キー公開語 読取りレビュー

レモン、ファイルを読んだだけのレビューです。編集もコマンドの実行もしていません。依頼の観点はほぼ問題ありませんでした。指摘は下の4件です。

## 指摘（重要度順）

### 1. 【中】`SC-FRONT` = 165 の根拠がない
- `src/graphics/graphics.fs:750` で `165 CONSTANT SC-FRONT` を定義しています。HELP の `src/core/help_text.zig:1561` にも「usage 165 for FRONT」とあります。
- `src/physical_key_map.zig` には 165 も FRONT も出てきません。どのホストもこの値を返さないため、このキーは常に未対応です。
- HID Usage Tables の page 0x07 では 0xA5〜0xAF が Reserved だったと記憶しています。本セッションでは原典を見ていないので未確認です。この記憶が正しければ、存在しない番号を定数として公開していることになります。
- 修正案：原典で 0xA5 が Reserved と確認できたら、次の4か所から `SC-FRONT` を削除します。
  - `graphics.fs:750`
  - `words_graphics.zig:61` の `library_words` にある `"SC-FRONT"`
  - `help_text.zig:1561`
  - リファレンス文書と `translations.ja.tsv` の該当行

  公開前なので、辞書イメージの互換性は気にしなくてよいはずです。

### 2. 【中】SC-* 定数とホストの対応表を突き合わせる試験がない
- SC-* の値は目で照合し、0x04〜0xA4、0xB0〜0xDD、0xE0〜0xE7 は HID の並びと一致していました。ただ、この一致を自動で確かめる試験がありません。
- `help_test` で確かめているのは名前が定義されていることだけで、値は見ていません。
- 修正案：`physical_key_test.zig` に試験を追加します。
  - `REQUIRE-GRAPHICS GRAPHICS` を実行してから、`library_words` の `SC-` で始まる語をすべて解釈し、値が 0〜255 に収まることと重複がないことを確かめます。kind の3語は除きます。
  - 加えて、`windowsScan` / `darwinScan` / `xkbScan` が返しうる 4 以上の値について、すべて対応する SC-* 定数があることを確かめます。

  これで 1 のような定数も、取りこぼしも検出できます。

### 3. 【低】KEY-RESYNC の `address_registry.written` が試験されていない
- `words_graphics.zig:112` の呼び出し方は、引数（address、32、full_cell=false）を含めて設計どおりです。
- ただ、再配置記録のあるセルを KEY-RESYNC で上書きしたときに、その記録が無効になるかを確かめる試験がありません。他の書込み語の既存試験に合わせて1件追加することを勧めます。

### 4. 【低】HELP の文言
- `help_text.zig:1396-1397` の「First256」は空白が抜けています。「First 256」に直します。
- `SCAN-SUPPORTED?`（`help_text.zig:1392-1393`）には、設計にある「予約 0〜3 は false」が書かれていません。追記します。

## 問題がなかった観点
- **スタックと例外**：`SCAN-HELD?` と `KEY-RESYNC` は値を pop してから検査します。これは `C!`（`words_memory.zig:49`）など既存の語と同じやり方です。CATCH で深さも戻るので、問題ないと判断しました。
- **ホスト状態を変える前の失敗**：KEY-RESYNC は `memoryAddress` の検査に通ってから `ops.resync` を呼びます。KEY-EVENT は 3 セル分の空きを確かめてから `next` を呼びます。`push` の溢れ判定（`forth.zig:2425`）とも合っています。
  - なお、イベントがない場合も3セル分の空きを要求します。空きが1〜2セルだと false を積めるのに StackOverflow になりますが、`Ops` に先読みの口がないので、安全側の扱いとして許容範囲です。
- **範囲検査**：0〜255 の外は `InvalidNumber`（-24）、アドレスの範囲外は `InvalidAddress`（-9）を返します。
- **ホスト口がない場合（unavailable）**：4語は false、KEY-RESYNC は全0を写します。設計 38 行と一致しています。
- **graphics=false**：5語は `words` に含まれているので除外されます。`main.zig:2364` でも ops は `graphics and host_window.available` のときだけ設定されます。
- **辞書の互換性**：Builtin の追加は enum の末尾（`defs.zig:1131-1135`）、`definitions` の追加も末尾で、既存の番号は動いていません。
- **語の登録範囲**：KEY-EVENT などの名前は既存の語と衝突していません。
- **復元時のリセット**：`image_restore.zig:102` は apply の中、`clearImage` の隣にあります。検査（preflight）で失敗した場合は呼ばれず、そのことを試験も確かめています。
  - 補足：保存イメージを起動時に復元すると、ウィンドウを開く前でも最初の KEY-EVENT が `0 3 -1` を返します。設計 56 行の「復元成功で再同期要求」どおりの動きです。

## 補足
実機キーボードでの確認と Mac 上での実行は、ご提示のとおり未確認のままです。

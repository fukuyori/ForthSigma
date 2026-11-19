# 640 設計レビュー原文

2026-11-20。Claude Code読み取り専用レビュー。

# 640 設計レビュー（UAX #29 rev 49 / strict UTF-8）

レモン、レビュー結果です。編集とコマンド実行はしていません。読んだのは `.work/640/review/design.md`、`docs/GRAPHEME_DESIGN.md`、`src/core/words_xchar.zig`、`words_extension.zig`、`image_format.zig`、`forth.zig` の `memoryAddress`、`tests/data/unicode-18.0.0/*`、`THIRD_PARTY_NOTICES.md` です。

## 高

### H1. 入力全体を検査するので、前方の反復も O(n²) になる
- **問題**: 設計の「入力全体を strict UTF-8 として検査し、先頭クラスタ後の不正も報告する」に従うと、X-GRAPHEME は1回呼ぶたびに残りの全長 n を読みます。`2DUP X-GRAPHEME /STRING` で k 個のクラスタを順に進むと O(n·k) です。普通の文字列では O(n²) になります。設計書が注意書きに挙げているのは末尾を繰り返し削除する場合だけで、前方の分は書かれていません。
- **解決案（推奨はA）**:
  - **A**: 検査範囲を「走査した範囲」に限ります。前方は先頭クラスタと、境界を決めるための次の1コードポイントまでです。その範囲に不正があれば -24 を返し、後ろは読みません。「途中から切り出した文字列は元の text と境界が一致しない」という既存の定義とも合います。
  - **B**: 全体検査を残し、前方も1回 O(n)、反復すると O(n²) であることを HELP に明記します。
  - **C**: 不正な列を U+FFFD 相当の単独クラスタとして扱い、THROW しません。既存の寛容な XCHAR 語と同じ方針です。
  - A と C は「先頭クラスタ後の不正も報告する」という仕様を変えるため、レモンの判断が必要です。

### H2. 「Extend*」が二通りの意味で使われ、どちらか区別されていない
試験データで次のことを確認しました。
- 18.0.0 の GB9c は Consonant が前になくても成立します（`GraphemeBreakTest.txt:179` `÷ 094D × 0915 ÷`）。
- Linker のなかには GCB=Other のものがあります（`1CF5..1CF6`、`11A3A` は Lo）。この場合も 9.3 で結合します（`GraphemeBreakTest.txt:659` `÷ 1CF5 × 0915 ÷`）。
- GB9c の Extend* は **InCB=Extend** の意味です。ZWJ（U+200D）は InCB=Extend に含まれます（`DerivedCoreProperties.txt:13625`）。ZWNJ（U+200C）は GCB=Extend ですが InCB=Extend ではありません。
- GB11 の Extend* は **GCB=Extend** の意味です。

設計の「Extended_Pictographic Extend* と ZWJ の状態」と「InCB Linker Extend* の状態」は、この2つを区別していません。取り違えると誤判定になります。

**解決案**: 設計書に次の遷移を明記します。
- GB9c 状態:
  - InCB=Linker で立てる（GCB は問わない）
  - InCB=Extend なら保持する（ZWJ を含む）
  - それ以外なら解除する
  - 次が InCB=Consonant で状態が立っていれば ×
- GB11 状態:
  - ExtPict で立てる
  - GCB=Extend なら保持する
  - GCB=ZWJ なら「ZWJ 直後」に移す
  - それ以外なら解除する
- 判定の優先順位: GB3〜5（CR/LF/Control）を GB9c より先に適用し、GB999 より GB9c を優先します。

## 中

### M1. 公式試験に入っていない GB9c と ZWJ の組合せは独自試験が必要
`094D 200D 0915` と `094D 200C 0915` は公式試験に含まれていません（Grep で確認）。次を独自試験に加えることを提案します。
- `094D 200D 0915` → 1クラスタ
- `094D 200C 0915` → 分割
- `1F600 094D 200D 1F600` → GB11 で結合（094D は GCB=Extend）
- `1F600 1CF5 200D 1F600` → 分割（1CF5 は GCB=Other）
- `094D 1CF5 0915` → `094D | 1CF5 0915`

### M2. 既存の `decode` を strict 判定に使ってはいけない
`words_xchar.zig:37` の `decode` は次の入力を `valid=true` として通します。
- 過長形
- サロゲート
- 先頭バイト F5〜F7 のうち U+10FFFF 以下になるもの

**解決案**: strict 判定用の復号関数を別に作ります。既存コードで使われている `std.unicode.utf8ValidateSlice`（`source_diagnostics.zig:124` など）に相当する判定です。拒否するもの、受け入れるものを試験で列挙します。
- 拒否: C0/C1、F5–FF、E0 80–9F、ED A0–BF、F0 80–8F、F4 90 以上、単独の継続バイト、末尾で途切れた列、途切れた後に ASCII が続く列
- 受け入れる境界値: U+007F/0080/07FF/0800/D7FF/E000/FFFF/10000/10FFFF

※Zig 標準関数がサロゲートを拒否するかは、この版では未確認です。試験で確定させてください。

### M3. 失敗時にスタックを保つため、pop ではなく peek で実装する
既存の `x_size` などは先に pop するので、-9 で失敗すると引数が消えます。設計は「成功するまでスタックを変更しない」としています。

**解決案**: `x_fetch_plus_string`（`words_xchar.zig:295`）と同じ方式にします。
1. `requireDepth(2)` を呼ぶ
2. `peek(0)` / `peek(1)` で引数を読む
3. 範囲を検査し、UTF-8 と境界を計算する
4. 成功したら `data_depth -= 1` として、最上段を結果で置き換える

-9 の場合も -24 の場合も、スタックが元のまま残ることを試験します。

### M4. 末尾探索は先頭からの走査をやめ、後方参照で計算できる
H1 で A を選ぶ場合、X-GRAPHEME-LAST は末尾から次の範囲だけを見れば決まります。
- 最後のクラスタ
- GB9c の InCB=Extend 列
- GB11 の Extend 列
- GB12/13 の RI 列の偶奇を数える範囲

その範囲だけ strict 検査すれば足ります。最悪の O(n²) が残るのは長い RI 列だけになります。前方と後方が別の実装になるので、GraphemeBreakTest を両方向で照合する意味も大きくなります。いまの設計では末尾も前方走査なので、両方向の照合はほぼ同じ処理を2回試すだけです。

### M5. 表を3回二分探索するより、1つの表にまとめる
**解決案**: 生成器で GCB(4bit)、ExtPict(1bit)、InCB(2bit) を1バイトに詰めます。区間を1つの表に統合し、二分探索を1回にします。さらに次の2点で表を小さく、速くできます。
- ASCII は表を引かずに判定する
- Hangul LV/LVT は `(cp-0xAC00)%28` で計算する（GraphemeBreakProperty では1語ずつ約400行並んでいます）

生成器は `@missing`（GCB=Other、InCB=None）を既定値として扱う必要があります。

### M6. 製品に入る生成表が THIRD_PARTY_NOTICES に載っていない
`THIRD_PARTY_NOTICES.md:3-11` は試験データだけを説明しています。また、冒頭の導入文（13行目「FORTH/Sigma includes the following…」）より前に置かれています。

**解決案**: 導入文の後ろへ移します。そのうえで、既存の 15.1.0 の項（124行目）と同じ形で、生成表のファイル名、生成器、使う語（X-GRAPHEME / X-GRAPHEME-LAST）を書きます。

### M7. -24 を不正 UTF-8 に使う根拠
-24 は規格では「invalid numeric argument」です。既存では `error.InvalidNumber` に割り当てられ、TERM-MODE! の不正マスクに使われています。不正 UTF-8 に使うと、表示される意味が合いません。

**解決案（どちらか）**:
- -24 を採用する根拠を設計書に一文で書く
- 専用の例外を設け、メッセージで区別できるようにする

どちらにするかはレモンの判断が必要です。

## 判断が必要な事項
1. H1: A / B / C のどれにしますか。推奨は A で、M4 の後方参照による末尾探索も同時に採用する案です。
2. M7: -24 のままにしますか、専用の例外にしますか。

上の2点が決まれば、H2・M1〜M6 の内容は設計書に反映できる状態です。

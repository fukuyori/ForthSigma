# 997 Claude Code Trackerレビュー原文

2026-11-19。読み取り専用。実装・実行結果・採否とは区別する。

## 依頼

```text
Read-only implementation review. Inspect src/core/physical_keys.zig (standalone pure 256-key state + 256-event ring, now imported by src/forth_test.zig) against docs/PHYSICAL_KEY_DESIGN.md queue/focus/overflow sections only. Do not change files or execute commands. This is an implementation foundation, not integrated with host or public Forth words. 8 standalone tests passed with Zig0.17.1 on Windows; do not claim additional tests. Identify substantive correctness issues, especially exact capacity, state updates after overflow, all held bits released despite overflow, resync sticky, wrap, and atomicity obligations of future host wrappers. Return concise Japanese review. If no blocking issues, state so and list remaining host integration responsibilities without requesting user decisions.

```

## 原文

# 物理キー Tracker 実装レビュー（読み取りのみ）

**結論：ブロッキングになる問題は見つかりませんでした。** 確認したのは `src/core/physical_keys.zig` 全体と、`docs/PHYSICAL_KEY_DESIGN.md` の 29〜45 行目（状態機械・フォーカス・overflow・ホスト口）です。ファイルの変更やコマンドの実行はしていません。テストについては、ご提示の「Zig 0.17.1 / Windows で単体テスト 8 件が成功」以外は主張しません。`src/forth_test.zig:4` で import されていることは確認しました。

## 指定された観点の確認

- **容量ちょうど**
  - `count == capacity` を判定してから `loseHistory()` を呼ぶため、256 件までは失われず、257 件目で overflow します（`:28-31`）。設計の「257件目でoverflow」と一致しています。
- **overflow 後の状態更新**
  - bitmap を書き換えてから `resync_required` と満杯を判定するため、overflow 中も、overflow を起こした edge 自体も状態に反映されます（`:26-31`）。
- **overflow 中のフォーカス喪失**
  - `releaseAll` は各キーで `update` を呼び、`update` は bit を先に消してから return します。そのため途中で overflow しても、4〜255 の bit はすべて解放されます（`:57-59`）。テスト「focus release overflow still clears every held bit」の内容とも一致しています。
- **再同期要求が消えないこと**
  - `next()` は `resync_required` の間は何も消費せず、毎回 `{0, .resync}` を返します。要求を消すのは `resync()` だけです。overflow 中は新しい edge をためません（`:27`）。
- **リングの折り返し**
  - 書き込み位置は `(head + count) % capacity`、読み出し後は `head = (head+1) % capacity` です。`count` の上限は 256 なので、usize のあふれもありません。
- **ビット配置**
  - 番号 n は `bitmap[n/8]` の bit(n%8) で、KEY-RESYNC の `addr+n/8` の bit(n%8) と一致しています。予約番号 0〜3 は `update` では無視し、`replaceSnapshot` では `&= 0xf0` で外しています。
- **世代境界**
  - `boundary` は全 0 にして再同期要求を立てます。空の状態でも要求を立てる点は設計どおりです。

## ブロッキングではない差分（設計書と揃える範囲）

1. 設計書（31 行目）では Tracker が `available` を持つとありますが、実装にはありません。ホスト側のラッパーに置く想定であれば、設計書の記述をそちらに合わせるのが妥当です。
2. 設計書（41 行目）の `focusLost` は、実装では `releaseAll` という名前です。`reset` は `boundary` に相当します。名前の対応表を設計書に載せておけば十分です。
3. 再同期要求が立っていなくても、`resync()` は未読の履歴を捨てます。設計書の「履歴と再同期要求を消す」に合っていますが、マニュアルにもはっきり書いておくべき挙動です。
4. 今の 8 件ではカバーしていないケースがあります。いずれもコードを読む限りは正しいので、ブロッキングではありません。
   - head が 0 でない（折り返し中の）状態からの overflow
   - 再同期要求中に `boundary` や `replaceSnapshot` を重ねて呼ぶ場合

## ホスト統合で守るべきこと

- **ロックの範囲**
  - `update`・`releaseAll`・`boundary`・`replaceSnapshot`・`next`・`resync`・`held` は、すべて同じ短いロックの中で呼びます。
  - `releaseAll` は 252 回の `update` をまとめて 1 回のロックで囲みます。途中で VM が割り込んで、一部だけ解放された状態を読まないようにするためです。
- **KEY-RESYNC の手順**
  - アドレスの検査はロックの前に済ませます。検査に失敗したら Tracker には触りません。
  - `resync()` によるコピーと履歴の消去は 1 回のロックで行います。VM メモリへの書き込みは、ロックを外してから戻り値のコピーで行えば十分です。
- **ロック中にしないこと**
  - ロックを持ったまま、既存の window lock・IPC・OS 待機に入りません。Mac では IPC を先に読み切ってから Tracker のロックを取ります。
- **`available` と境界の扱い**
  - `available` はラッパーで管理します。未対応になったときに境界の再同期通知を返すかどうかの優先順位は、設計書 37 行目にあるとおりレビューで確定させ、ラッパー側に実装します。
- **イメージ復元**
  - `image_restore.apply` が成功した後だけ、失敗しない `boundary` 相当を呼びます。preflight で失敗した場合は呼びません。
  - Mac では、同時に入力の世代境界を子プロセスへ伝え、旧世代の SCAN を捨てます。送信に失敗したら physical capability を止めます。
- **変換とその他の制約**
  - `Kind` は `@intFromEnum` で 1/2/3 に変換し、再同期のときは scan=0 にします。
  - 文字入力用の既存 InputEvent キューとは独立させます。
  - ワーカーからは読ませません（owner-only の制限を適用します）。
  - optional ops を持たない Writer では「機能なし」を返します。

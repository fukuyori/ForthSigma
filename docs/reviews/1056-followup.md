# Claude Code追加確認原文

2026-11-19。セッション`09df8c8b-5e81-4846-9b9e-e89461d4b83b`、約166秒。読み取り専用。

レモン、1056 の追加確認の結果です。固定コピー `.work/1056-review/followup/src/` のコードを読んだ範囲では、前回の修正による新しい高・中の問題は見つかりませんでした。I01・I03・I05・I06 はコード上で修正を確認しました。ビルドと試験は実行していないので、試験が通るかどうかは未確認です。

## 新しい指摘（4件、すべて低）

### 1. 【低】拒否の試験は既定のビルドでは動かず、巻戻しの確認も一部だけ
- **場所:** `tests/extension_test.zig:166-203`、`tests/graphics_test.zig:434-460`
- **条件:**
  - 拒否の試験は、除外された構成でだけ動きます。全部を有効にした既定のビルドの `zig build test` では、何も確かめずに通ります。
  - 作業ツリーの `tests/scripts/verify-extension-matrix.py:41-46` を Grep と Read で見たところ、次の構成は含まれていました。
    - graphics・audio・extension を外した各構成
    - files を外した構成、debug を外した構成（image は有効）
  - したがって、マトリクスを実行すれば試験は動きます。ただし、このスクリプトは固定コピーの外にあります。
  - 「辞書は変わらない」の確認は `word_count` と `data_here` だけです。`names_used`、`code_count`、heap の top、語彙リストの数は見ていません。
- **修正案:** 確認に `names_used`、`code_count`、`heapTop()`、`wordlistCount()` を足す。あわせて、「既定ビルドではスキップされ、マトリクスで確かめる」と試験のコメントか文書に書く。

### 2. 【低】除外 builtin のある辞書を SAVE しても失敗しなくなった
- **場所:** `image_format.zig:342-364`（除外の条件を外した部分）、`image_encoder.zig:68`
- **内容:**
  - 以前は、SAVE の中で保存結果を読み直す検査が、除外 builtin を見つけると失敗していました。
  - 今は SAVE が成功し、同じビルドで LOAD したときに拒否されます。
  - 通常の操作でこういう辞書ができる経路は、今回読んだ範囲では見つけていません（fixture や直接の書換えだけ、※推測です）。
- **修正案:** ご説明どおり意図した変更であれば、コードはこのままで構いません。設計文書に「SAVE は形式だけを確かめ、ビルドの機能による判定は読込み時に行う」と一行あると、利用者の誤解を防げます。

### 3. 【低】HELP の HOST-OS の説明と文書の内容が揃っていない可能性
- **場所:** `help_text.zig:1302`
- **内容:**
  - HELP は "target OS family" と WSL/Android の扱いを説明しています。
  - 一方、ご説明にあった「値は今後増えることがある。知らない値は unknown として扱う」と「Wine の例」は書かれていません。
  - 文書側の記述は、固定コピーに docs が入っていないため未確認です。
- **修正案:** HELP に "more values may be added; treat unrecognized ones as unknown" の一文を足す。

### 4. 【低】I02 案(a) で生じる非対称の文書化（未確認）
- **内容:**
  - `-Dfloat=false` のビルドでは、`fliteral` や float 局所変数の `+TO` が出す直接の `.builtin` Op が、今回の `validateOperation`（`image_features.zig:7-11`）で拒否されます。
  - 一方、F+ などの通常の呼出しは読み込めて、実行時に -261 になります。
- **修正案:** 文書の I02 案(a) の説明に、この「float の直接 Op も拒否の対象」という例が入っているか確認してください。debug の `.dbg` では、直接 Op の拒否を試験で確かめています（`extension_test.zig:168`）。

## 修正を確認した前回の指摘

- **I01:**
  - **wire codec:** `image_format.zig` の `validateWords` と `validateCode` から、除外の条件がなくなっていました。
  - **共通の検査:** `image_features.zig` が追加されていました。
  - **経路:** restore と typed append は、どちらも `image_restore_plan.zig:29-33` を通ります。`image_append_plan.zig:27` が `full.prepare` を呼んでいます。
    - State append では `dictionary_image.zig:101-102` で検査しています。
    - LOAD（`main.zig:1592-1593`）と埋め込みイメージ（`:2194`）も、この経路を通ります。
  - **graphics の試験:** `graphics_test.zig:434-460` は、3つの経路すべてで拒否されること、辞書が変わらないこと、実行時防御が働くことを確かめる内容になっていました。
  - **extension の試験:** 4つの群の語と直接 Op が 3つの経路すべてで拒否されることと、基本辞書の欄への `call_builtin` が読み込めて実行時に -261 になることの試験がありました（`extension_test.zig:166-223`）。
  - **実行時防御:** `forth.zig:2064` と `:2248` で働いています。
- **I03:** 範囲の検査（`dictionary_image.zig:100`）が、除外の検査（`:101`）より前に来ていました。試験は `extension_test.zig:225-236` にあります。
- **I05:**
  - `words_help.zig:55` に extension の判定が明示されていました。
  - `:145-151` は、`library_words` と `definitions` を順に見る形になっていました。
- **I06:** `memory_map.zig:292-296` に、`where_style` → 記録セル → HOST-OS の欄 → `timezone` の順で重ならないことを確かめる comptime 検査がありました。

## 未確認の事項

- ビルドと試験の結果、特に次の2つの試験が通るかどうか
  - `extension_test.zig:222` が `error.InvalidExecutionToken` になるか
  - `graphics_test.zig:459` が `error.InvalidExecutionToken` になるか
- 文書の記述
  - HOST-OS の OS 系統、未知の値の扱い、Wine の例
  - 任意の Forth の副作用は巻き戻さないこと
  - I02 案(a) の説明
  - `docs/reviews/1056-design.md` の番地の記述
- 作業ツリーと固定コピーの差

## 読んだ範囲と実施しなかったこと

- **全文を読んだもの:** `image_features.zig`、`image_restore_plan.zig`、`image_format.zig`、`tests/extension_test.zig`、前回のレビュー `docs/reviews/1056-implementation.md`
- **一部を読んだもの:**
  - `dictionary_image.zig` 1-300行、`words_help.zig` 1-179行
  - `graphics_test.zig` 420-479行、`image_encoder.zig` 25-84行
  - `defs.zig` 20-99行、1324-1349行
  - 作業ツリーの `verify-extension-matrix.py` 1-80行
- **Grep だけで確認したもの:** `memory_map.zig`、`library_loading.zig`、`words_extension.zig`、`help_text.zig`、`main.zig`、`forth.zig`、`words_debug.zig`、`words_audio.zig`、`words_files.zig`、`freestanding_check.zig`
- **重点として指定された中で読まなかった部分:** `memory_map.zig` は Grep で該当する行だけを確認し、全文は読んでいません。
- **実施しなかったこと:** 実行、ビルド、試験、編集、Git の操作、外部へのアクセスは、いずれも行っていません。

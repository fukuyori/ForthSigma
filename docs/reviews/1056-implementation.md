# Claude Code実装レビュー原文

2026-11-19。セッション`d4e077c1-e5a3-4745-a607-79f2f49f257a`、約304秒。読み取り専用。

レモン、1056/1036 実装のレビュー結果です。対象は固定コピー `.work/1056-review/implementation/src/` と `build.zig` だけで、元の `src` は見ていません。高の1件はコードを読んだうえでの予測で、試験は実行していません。

## 指摘（重大度順、7件）

### 1. 【高・現在の欠陥】`-Dgraphics=false` で既存の試験が失敗する見込み（未実行）
- **場所:** `src/tests/graphics_test.zig:434-456`。試験名は「a build without graphics loads a SIGIMG46 image and refuses to run its GFX- words」です。
- **内容:**
  - この試験は、graphics を除いたビルドの中で `appendWord("GFX-INIT", .builtin, .gfx_init, 0)` を行います。そのあと保存・復元が成功し、実行時に -261 になることを確かめています。
  - 今回の `image_format.zig:309` は、`builtin_count` 以降にある除外 builtin 語を拒否します。
  - さらに `image_encoder.zig:68` で、保存した出力を `format.parse` にかけ直しています（Grepで確認）。
  - このため SAVE か restore のどちらかが `InvalidImage` になり、試験は `try` のところで失敗するはずです。今回の挙動変更と正反対のことを確かめる試験です。
- **再現:** `-Dgraphics=false` で試験を実行する（未実行。実行中の8通りの結果で確かめられます）。
- **修正案:**
  - この試験を、SAVE または restore が `InvalidImage` になることを確かめる内容に書き換えます。
  - あわせて、除外 builtin を拒否する試験を足します。対象は image_format と State append の事前検査の両方で、audio、extension、files、debug の除外構成についても同じ形で入れます。
  - 現在、`src/tests` には拒否を確かめる試験が一つもありません（Grepで確認）。

### 2. 【中・ご判断が必要】除外検査で拒否されるかどうかが、コードの符号化の形で変わる
- **場所:**
  - `image_format.zig:351` は直接の `.builtin` Op だけを拒否します。
  - `image_encoder.zig:44-48` は、起動時の builtin の呼出しを `.call_builtin`（語番号）として保存します。
- **内容:**
  - 起動時の除外語（files、tools、debug、float など）を、通常の呼出し・`.execution_token`・`.call` で参照するコードは拒否されません。この場合は実行時に -261 になります。
  - 一方、内部で直接 `.builtin` Op を出す箇所は拒否されます。例は `definers.zig:285` の局所変数の `+TO` 加算（float の場合）や、`quotations.zig:162` の `fliteral` です。
  - その結果、同じ float を使うイメージでも、書き方によって読める・読めないが分かれます。
- **修正案（どちらかをご判断ください）:**
  - (a) 文書に「拒否するのは遅延語群の builtin 語と内部の直接 Op だけ。起動時の語の呼出しは実行時に -261」と正確に書く。
  - (b) Op が起動時の除外欄を参照している場合も拒否する。データに保存した xt は、これまでどおり -261 で防ぎます。
  - 推奨は (a) です。(b) にすると、たとえば `-Dfiles=false` で INCLUDED を使うイメージがすべて読めなくなり、影響が大きいためです。

### 3. 【低〜中・現在の欠陥】State append の事前検査が、整合性の検査より前にある
- **場所:** `dictionary_image.zig:100-105` の事前検査が、`:132` の `source.word_count < source.builtin_count` の検査より先に実行されます。
- **再現条件:** `word_count < builtin_count` になっている壊れた source State を渡したとき（例: freestanding の `sigma_append_image`）。
  - スライス `source.words[builtin_count..word_count]` が、Debug と ReleaseSafe では panic、ReleaseFast では未定義動作になります。
  - 以前は `:132` の検査が先にあったため、この順序の問題は今回の変更で入ったものです。
- **修正案:** `:132` の検査を `:100` より前に移します。

### 4. 【低】名前と意味のずれ（新語の仕様の確認）
- **文字列の仕様は問題ありません。**
  - ASCII 小文字で最長7バイト、固定の8バイト欄に収まります。
  - 戻り値は `( -- c-addr u )` で、gforth の文字列を返す語と同じ形です。
  - 小文字の4種類に限っているため、比較しやすいです。
- **名前には次のずれがあります。** `HOST-OS` が返すのは、実行中のホストではなく、ビルド時のターゲット（comptime）です。
  - Wine で動かしている Windows 版は "windows" を返します。
  - 実際の OS の上で freestanding の core を独自のホストに組み込んだ場合は "unknown" を返します。
  - HELP の文（`help_text.zig:1302`）は "target OS family" と書いており、こちらは正確です。
- **"unknown" の範囲:** freestanding と、既知だが対象外の OS（freebsd、ios など）が同じ値になります。将来 OS を足すと、"unknown" で判定しているプログラムの動きが変わります。
- **修正案:**
  - 文書に「ビルド対象の OS 系統。値は今後増えることがある。知らない値は unknown として扱う」と書きます。
  - 名前は `HOST-OS` のままでも運用できます。意味を名前に合わせたい場合は `TARGET-OS` も選べます。
- gforth には環境問い合わせの `os-type`（"linux-gnu" のような文字列を返す）があったと記憶しています（※推測です。WSL の gforth では確認していません）。

### 5. 【低・将来の問題】HELP の判定が、たまたま正しく動いている
- **場所:** `words_help.zig:54` の group_word の判定には extension が入っていません。
  - それでも読込み後の `HELP HOST-OS` で説明文が出るのは、`isGraphicsWord` から呼ばれる `isGroupWord`（`library_loading.zig:80`）が、どの `.builtin` 語にも真を返すためです。
- **場所:** `words_help.zig:144` は "HOST-OS" という名前を直接書いて判定しています。extension に語を足したとき、`-Dextension=false` で HELP 一覧から外し忘れる原因になります。
- **修正案:**
  - `:54` に extension の判定を明示的に足します。
  - `:144` は `words_extension.definitions` と `library_words` を順に見る形にします。

### 6. 【低】メモリ配置の保護と、文書の番地
- **場所:** `memory_map.zig:289-291`。`0x0dc0`（語群の記録セル）と `0x0dc8..0x0dcf`（HOST-OS の文字列）について、`where_style_address` や `timezone_buffer_address` と重ならないことを確かめるコンパイル時の検査（`:166-179` の並び）がありません。
  - 計算で求めたオフセットが 0xdc0〜0xdff の範囲を使っていないことは、Grep で確認しました。
- **文書の差分:** 設計レビュー原文 `docs/reviews/1056-design.md:83-84` では、記録セルが 0x0dc8、文字列欄が 0x0dc0 で、実装と逆です。ご説明の値（文字列 0xdc8、記録セル 0xdc0）は実装と一致しているので、文書を実装に合わせてください。
- **修正案:** `host_os_buffer_address + 8 <= timezone_buffer_address` と `extension_vocabulary_address >= where_style_address + 8` の comptime 検査を足します。

### 7. 【低・将来の問題】読込みに失敗したときの巻き戻しで、戻らないもの
- **戻るものは確認しました**（`library_loading.zig:86-152`）:
  - 辞書（forgetFrom）
  - 語彙リストの数、大文字小文字の区別と警告のフラグ
  - current と検索順序
  - 読込み済みファイルのフラグ
  - pending と制御の深さ
  - BASE と名前の状態（いずれも defer で戻ります）
- **戻らないもの:**
  - ライブラリが失敗の前にスタックへ積んだ値
  - 定義中でないときに `]` で入った compiling 状態
  - ソースファイル表の名前の欄（再試行のときは再利用されます）
- 現在の `extension.fs` はコメントだけなので、出荷するライブラリでは起きません。他の語群と共通の性質なので、将来この語群に Forth のライブラリを足すときの注意点として扱ってください。

## 確認して問題がなかった点
- **HOST-OS の書込み:**
  - スタックを先に確かめるので、結果が半分だけ残ったり、欄が書き換わったりしません。
  - registry へ通知しています（timezone と同じ形）。
- **イメージ復元との関係:**
  - 復元では、保存した側の OS の文字列が 0xdc8 に戻ります。それでも HOST-OS は呼ぶたびに書き直すので、正しい値を返します。
  - 短い名前を書いたあとに前の文字が残ることはありますが、長さが正しいので害はありません。
  - 保存済みの c-addr を復元後に使うと古い値になります。これは「次の呼出しまたはイメージ復元まで有効」という仕様どおりです。
- **読込み済みの判定（`isLoaded`）:** 記録セルの値の範囲と「語彙の次が `host_os` の builtin 語か」を確かめているので、FORGET や他の語群が同じ番号に入った場合も誤判定しません。
- **append の2経路:**
  - `library_groups.zig` に共通化されています。
  - typed append の事前検査（`image_append_plan.prepare`）は State を変更しません。
  - State append では、ファイル表を変更するのはすべての error 検査の後です。
- **起動時の欄:** `image_restore_plan.zig:29-32` は kind と builtin だけを照合し、名前なしの欄は拒否していません。
- **復元の経路:** LOAD（`main.zig:1592-1593`）と埋め込みイメージ（`:2194`）は、どちらも `format.parse` を通ります（Grepで確認）。
- **ビルド構成:**
  - REQUIRE-EXTENSION の parser 分岐は有効なときだけです。除外構成では通常の未定義語になり、試験の `:10-23` と一致しています。
  - `host_os` は enum の末尾にあり、`executeBuiltin` の除外の防御も働いています。
  - freestanding のビルドでは comptime の `.freestanding` から "unknown" になり、OS のサービスには到達しません。

## 読んだ範囲と実施しなかったこと
- **全文を読んだもの:**
  - `words_extension.zig`、`library_groups.zig`、`library_loading.zig`、`memory_map.zig`
  - `image_format.zig`、`image_append.zig`、`image_append_plan.zig`、`image_restore_plan.zig`、`image_restore.zig`
  - `freestanding_check.zig`、`extension_test.zig`、`extension.fs`
  - 設計レビュー原文 `docs/reviews/1056-design.md`
- **一部を読んだもの:**
  - `dictionary_image.zig` 1-290行
  - `defs.zig` 20-89行、1110-1125行
  - `forth.zig` 905-980行、1255-1294行、1380-1405行、2050-2079行、2238-2261行
  - `words_help.zig` 1-172行、`image_encoder.zig` 30-64行
  - `graphics_test.zig` 425-464行、`dictionary_test.zig` 20-69行
- **Grep だけで確認したもの:** `build.zig`、`address_registry.zig`、`help_text.zig`、`main.zig`、`audio_test.zig`、`zoned_time.zig`、`words_text.zig`、`definers.zig`、`quotations.zig`
- **実施しなかったこと:** 編集、ビルド、試験、Git、外部アクセス、WSL の gforth での確認、`tests/scripts` と更新中の文書の確認は、いずれも行っていません。

# Windows表示支援 最終残件と検証レビュー

Claude Code読み取り専用。実行はロクが別途実施。

レモン、指定範囲を読み取り専用で確認しました。使ったのは Read / Grep だけで、実行・変更・ネットワークアクセス・他agentはありません。ビルドやスクリプトの実行結果は**未確認**です。

## 結論
残存Highは**なし**です。Mediumは文書の書き方に関する2件で、どちらも再実行のあとに直せば足ります。

## M1：解消を確認
- `src/tests/graphics_test.zig:3453-3455` の期待値は `17\nsigma_keep_open 0`、`19\nsigma_window_closes`、`18\nsigma_window_close` です。文字数はそれぞれ17、19、18で合っています。
- `src/core/tcl.zig:381` は `"{d}\n"` を付けてから本文を送り、`tcl.zig:422`、`:428`、`:437` は `command.len` を長さとして渡しています。
- このため `18\nsigma_window_close` が `19\nsigma_window_closes` の一部として一致することはありません。suffixの取り違えは解消しています。

## M2：記述とテストが一致
- `src/graphics/sigma_tk.tcl:86-89` では、`sigma_keep_open 0` は `sigma_close_pending` を消すだけで、ウィンドウを閉じません。
- `verify-windows-tk-close.py:28-29` は disable-pending で開いたまま(-1)、そのあとの要求で閉じる(0)ことをassertしています。
- `graphics.fs:367-368`、HELP(`help_text.zig:1208`)、英日の `GRAPHICS_AND_SOUND*.md:770` も同じ意味で書かれています。
- `host_window.zig` と `host_window_linux.zig` は今回読んでいません。レモンが確認済みとのことなので、それに従いました。

## Medium
1. **`docs/DRAWING_SPEED_VALIDATION.md:4`、`:43-44`**
   - clip追加前との比較ではないことは `:26` に、計算ループを変えていないことは `:43-44` に書かれています。
   - ただ、「JSONのSHA-256・working_tree・revisionは先行ビルドのもので、最終の実行体とは一致しない」とはっきり書いた文がありません。
   - `measure-display-drawing.py:71-74` はこれらを測定時の値として記録します。5本を再実行しても、この速度JSONだけは古いhashのまま残ります。`:4` か `:43` に1文足すことを勧めます。
   - なお「ループ未変更」の裏付けとなる差分は、今回確認していません(未確認)。
2. **結果の記述の時制と鮮度**
   - `WINDOWS_TK_DISPLAY_VALIDATION.md:59` は「〜を確認する」と予定の形で、実施済みかどうかが読み取れません。
   - `WINDOWS_DISPLAY_CONTRACT_VALIDATION.md:9` の「すべて終了コード0」と各JSONのhashは、HELPを直す前のビルドのものです。
   - 再ビルドと5本の再実行のあと、本文を新しいJSONに合わせて過去形で書き直す必要があります。

## Low(必要なら)
- `verify-windows-display-contract.py:43`:VSYNCは0/-1のどちらでも通ります。文書 `:26` の「この環境では真」はJSONを根拠にしていますが、JSONは読んでいません。
- 同じく `:144`:小窓は `>=` しか見ていません。文書 `:36` の120×40もJSONの値です(未読)。
- 同じく `:87-91`:Tkを選択しているときのvsyncが0かどうかはassertしていません。この点は `verify-windows-tk-frames.py:49-50` で確認されています。
- `verify-windows-tk-close.py:59` と `verify-windows-tk-frames.py:51` は、contractスクリプトと違って working_tree/revision を記録していません。binaryのSHA-256は記録しています。
- `DRAWING_SPEED_VALIDATION.md:3` にはレモンの呼び名と発言がそのまま入っています。リポジトリの文書としてそれでよいか、念のため確認してください。

ほかに、tk-closeの17段階は `sigma_tk.tcl:86-129` の動きと突き合わせて、期待値がすべて矛盾しないことを確認しました。frames の6段階、DRAWINGの中央値とCPUTIMEの刻み(15.625ms単位)とも、計算上は合っています。

## 実際に読んだ範囲
- 全文:`tests/scripts/measure-display-drawing.py`、`verify-windows-display-contract.py`、`verify-windows-tk-close.py`、`verify-windows-tk-frames.py`、`docs/DRAWING_SPEED_VALIDATION.md`、`WINDOWS_TK_DISPLAY_VALIDATION.md`、`WINDOWS_DISPLAY_CONTRACT_VALIDATION.md`
- 部分:`src/tests/graphics_test.zig:3425-3464`、`src/core/tcl.zig:380-449`、`src/graphics/sigma_tk.tcl:80-129`、`src/graphics/graphics.fs:330-379`
- Grepのみ:`graphics.fs:271`、`help_text.zig:1193-1209`、`GRAPHICS_AND_SOUND*.md`
- 未読:`windows_display_test_support.py`、`measurements/*.json`、`reviews/*`、`verify-windows-tk-state.py`、`verify-windows-tk-smooth.py`、`host_window*.zig`
# Windows表示支援 最終Claude Codeレビュー

読み取り専用。実行検証はロクが別途実施。

レモン、読み取り専用レビューの結果です。使ったのは Read/Grep だけで、ビルド・テスト・スクリプトは一つも実行していません。ご報告の5本成功とJSONの再作成は、こちらでは「未確認」です。以下はコードを読んだうえでの指摘です。時間の都合で、文書4本と verify-windows-*.py の各本体、`measure-display-drawing.py` は読んでいません。

## 結論
High はありません。確認した範囲では、ご提示の仕様どおりに実装されています。Medium は2件で、1件はテストの欠陥、もう1件は仕様が決まっていない点です。

## Medium

**M1. 新回帰の明示的closeの確認が、どんな場合でも成功します**
- 場所: `src/tests/graphics_test.zig:3455`
- 内容: `indexOf(..., "sigma_window_close")` は、直前の行で確認している `sigma_window_closes` の中にも含まれる文字列です。そのため、`WINDOW-CLOSE` がスクリプトを送らなくなっても、このテストは通ります。
- 再現条件: `graphics.fs:370` の `2 GFX-TK-WINDOW-CLOSE DROP` を消しても、3455行は成功します(※コードから推測です。実行はしていません)。
- 修正案: `request` は `"{len}\n"` の後に本文を送ります(`tcl.zig:381`)。そこで `"18\nsigma_window_close"` を照合すると、長さで区別できます。照合する文字列は `"19\nsigma_window_closes"` と `"17\nsigma_keep_open 0"` にそろえてください。送られた順序も確かめるなら、`indexOf` の位置を比べる方法もあります。

**M2. 保持中のclose要求がある状態で `FALSE WINDOW-KEEP-OPEN` にすると、close要求が消えます**
- 場所: `src/graphics/sigma_tk.tcl:86-89`
- 内容: `sigma_keep_open 0` は `sigma_close_pending` を0にするだけで、`wm withdraw` はしません。ユーザーが一度閉じる操作をしていても、窓は開いたままになります。ただし、閉じた回数は `W` で通知済みです。次にユーザーが閉じれば、KEEP-OPENが偽なので窓は閉じます。
- 判断: いただいた仕様には、この場合の扱いが書かれていません。次の2案のどちらにするか、ご指示ください。
  - (a) 現状のまま「保持は捨てる。窓は開いたまま」とし、文書(`graphics.fs:358-368` と HELP)にそう書く
  - (b) 保持中なら `sigma_window_close` を呼んで閉じる
- native側(`host_window.zig` の `windowClose(0)`)がこの場合どう動くかは、今回読んでいないので未確認です。

## Low(必要なものだけ)
- **L1.** `tcl.zig:426-433` の `windowKeepOpen` は、`request` が失敗すると `errdefer halt` で wish を止め、その `HostFailed` を表に出さずに戻ります。設定するだけの語で wish が止まっても、利用者には見えません。仕様の「照会では起動しない」とは矛盾しません。ただ、この止まり方は文書に一言あると親切です。
- **L2.** `sigma_show` は毎回 `sigma_keep_open $keep_open` を呼びます(`sigma_tk.tcl:170`)。値が同じなら pending は保たれるので、問題はありません。restart後に最初の SHOW を行うまでは wish 側が既定値の0のままですが、その間は窓がないので影響はありません。

## 前回の指摘と仕様の確認結果(コードを読んだ範囲)
- **Tcl結果を固定バッファで保持:** `fixed_text[96]` に入り、96を超えると読み捨てます(`tcl.zig:269-279`)。利用者の `result`/`error_text` は上書きされません。
- **未起動の wish を起動しない:** `windowStateCommand` と `windowKeepOpen` は、どちらも最初に `running` を確認しています(`tcl.zig:427, 436`)。
- **TCL-STOP と restart で close 数を維持:** `stop` は W だけを `dispatch` します(`tcl.zig:507`)。restart では `window_closes_seen` だけを0に戻し、`window_closes` 自体は残ります(`tcl.zig:150`)。`observeCloses` は飽和加算です。
- **確認済みにする語:** WINDOW-CLOSES の `sigma_window_closes` だけが pending を0にします(`sigma_tk.tcl:91-94`)。それ以外の照会と W 受信は pending を変えません。
- **未確認の二度目のclose:** withdraw します(`sigma_tk.tcl:124-128`)。
- **明示的close:** 回数を増やしません(`sigma_tk.tcl:96-103`)。
- **CLOSE と照会の切替:** `(TK-SHOWN?)` で、選択中の Tk と native を切り替えています(`graphics.fs:271, 356-370`)。
- **フレーム3語:** Tk 選択中は `0 0` と FALSE を返し、native の値を流用していません(`graphics.fs:441-445`)。
- **`sigma_show` の48バイトバッファ:** `WINDOW-SIZE` が `max_side` で制限されているので、`catch unreachable` に届かないと判断しました(`words_graphics.zig:300`)。ただし `max_side` の値そのものは未確認です。
- **検証支援コード:** `KILL_ON_JOB_CLOSE`、子プロセス数0の期限付き確認、KEY ゲート、queue の読み出し期限を、`windows_display_test_support.py:61-169` で確認しました。

M1 の修正と M2 の方針は、ご指示があれば対応します。
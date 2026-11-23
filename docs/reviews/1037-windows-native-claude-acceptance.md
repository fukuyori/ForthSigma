**結論：今回の差分に high/medium のバグは見つかりませんでした。**

### 復元シーケンス（`src/host_window.zig`）
- **WM_SIZE → タイマー → placeOn の順序（`:1881-1882`, `:1750-1753`）は正しい。**
  - タイマー 0x5344 は発火するたびに必ず Kill されます。
  - `IsIconic` ガードがあるので、最小化中に発火しても何もせず、pending は次の復元で使われます。
  - SIZE_MAXSHOW/MAXHIDE のような関係ない WM_SIZE で起動されても、同じガードで無害です。
  - 無限ループや再入の連鎖は起きません。
- **restoring 経路（`:1057-1075`）**：最初の SetWindowPos の前に `restore_place_pending=false` にしているので、途中で再入する WM_SIZE がタイマーを張り直すことはありません。
- **最大化からの復元（`:1022-1029`）**
  - `ShowWindow(noactivate)` の中で同期的に来る WM_SIZE が、pending=true の状態でタイマーを張ります。
  - その直後の再帰 placeOn が pending を false にするので、後から発火するタイマーは何もしません。
  - 再帰は `IsZoomed` ガードで深さ 1 に収まります。
- **iconic 経路（`:1043-1046`）**：pending 中は最初の寸法と DPI を残すので、続けて何度も移動しても値がずれません。
- **fullscreen 経路（`:1031-1037`）**：iconic のときは入らず、復元後に pending を false にして画面に合わせます。依頼の説明どおりです。
- **後始末**：`wm_destroy`（`:2044`）で pending が戻ります。新しい HWND は `run` の `fullscreen_on=false`（`:1649`）から始まります。

### Low（任意・簡単に）
1. **`:1882`**：SetTimer が失敗したときは `PostMessageW(wm_place)` に切り替わります。これは実機で上書きが見られた経路そのものです。失敗はまれで影響も限られますが、コメントで一言触れておくとよいです。
2. **`:1015`**：`cast orelse return` と、`:1042` の `GetWindowPlacement` 失敗時の return では pending がそのまま残ります。ただし次の WM_SIZE でもう一度試すだけなので、際限なく繰り返すことはありません。
3. **フルスクリーンの最小化中にモニタを移して、そのままフルスクリーンを解除し、それから復元する場合**：`applyFullscreen` の解除処理（`:1489-1498`）は pending をクリアしません。そのため復元時の restoring 経路（`:1058-1061`）は、`windowed_place` ではなく、フルスクリーン時の normal 矩形（モニタ全体の大きさ）から作った `restore_size` を使います。結果、ウィンドウは作業領域いっぱいになります。範囲の狭いケースで、動作は有限です。

### テスト補助
- **`windows_display_test_support.py:190-213`（`SigmaSession.close`）**：finally を入れ子にしているので、job、プロセス、ストリーム、stderr、一時ディレクトリが確実に後始末されます。reader が生きている間は stdout を閉じない条件も妥当です。
- **`verify-windows-display-hotplug.py`**
  - 再接続後の index は rect で取り直しています（`:197`）。device 名は再接続後の値と比べます（`:199-201`）。
  - `centered()`（`:90-96`）の `next()` は、`wait_for` の `consistent` で short-circuit されるため、StopIteration にはなりません。
  - fullscreen の被覆チェック（`:159`, `:177`）に問題は見つかりませんでした。
  - Low：`:16` が import している `windows_monitor_probe.py` がスナップショットに含まれていません。そのため `rect`/`work` が `[x,y,w,h]` 形式かどうか（`:159`, `:177`, `:96` の比較の前提）は、このスナップショットだけでは確認できませんでした。

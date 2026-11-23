# tque1037 Windows 修正の再レビュー（`.work/1037/windows-followup` のみ）

**結論:** 重大度「高」の不具合はありません。中程度で確定した欠陥は1件で、Zig 本体ではなく物理ホットプラグ記録スクリプトにあります。前回の M1〜M4 は、ソース上どれも意図どおり直っています。残りは低い指摘、実機で確かめるべき仮説、テストの抜けです。

- 読んだもの: 前回レビュー、`host_window.zig` 全体、Python スクリプト7本すべて。
- 使った道具: Read/Grep/Glob のみ。実行・編集・ネットワークは使っていません。
- 実行結果（75Hz/60Hz の測定、復元成功など）は報告として扱い、私は再現していません。

---

## 中（ソースで確定）

### N1. ホットプラグ記録の「再接続」判定に HMONITOR 値が入っており、成立しない可能性が高い
- **場所:** `tests/scripts/verify-windows-display-hotplug.py:151`。比較している行は `windows_monitor_probe.py:51` の `id=int(handle)` を含みます。
- **ソースで確定していること:** `r['independent'] == initial` は、`id`（HMONITOR）まで含めて完全に一致することを求めています。
- **実機で確かめる仮説:**
  - 再接続したモニターには新しい HMONITOR が割り当てられると考えられます。他のモニターの値も変わることがあります。そうなると、この条件は `--timeout` まで成立せず、手順の一番肝心なところで `TimeoutError` になります。
  - GDI のデバイス名（`\\.\DISPLAYn`）の番号も振り直されると、`:159` の `next(...)` が `StopIteration` になります。
- **修正案:**
  ```python
  def topology(rows): return [{k: v for k, v in m.items() if k != 'id'} for m in rows]
  wait_for('reconnected', lambda r: topology(r['independent']) == topology(initial), args.timeout)
  ```
  - `:159` は、デバイス名が見つからなければ `target['rect']` で引き直します。
  - HMONITOR が変わったかどうか自体を記録に残すことを勧めます（前回の実験項目2）。
- `--preflight` はトポロジーを変えないので、この問題は表に出ません。報告済みの preflight 合格は、この欠陥がないことの根拠になりません。

---

## M1〜M4 の評価

### M1（HWND を作る前のリセット）: 解消
- `fullscreen_on = false` が `CreateWindowExW` の前（`:1611`）に移りました。`wm_destroy`（`:1994`）でも false に戻します。
- 競合はありません。`open()` は前のスレッドの終了を待ってから新しいスレッドを作ります（`:1233-1240`）。`broken` の後は二度と開きません。
- テストは前回挙げた2つの手順を両方含みます。`verify-windows-window-on.py:89-97` の `reopen-as-normal`、`reopen-still-full` → `restore-after-reopen` です。

### M2（全画面中の掛け直しと、画面外に出た戻り先の補正）: ソース上は妥当。物理的な抜き差しでは未検証
- **掛け直し:** `WM_DISPLAYCHANGE` から `wm_display_layout` を投げ直し、全画面なら矩形を取り直します（`:1846-1867`）。合成した `WM_DISPLAYCHANGE` のテスト（`window-on.py:132-135`）は、この経路を実際に通ります。別の処理が偶然元に戻して合格する、という偽陽性はありません。
- **戻り先の補正（`:1454-1456`）:** `MONITOR_DEFAULTTONULL` の使い方も、作業領域の中央に置き直す処理も正しいです。
- **テストの抜け:**
  - どの自動テストも、戻り先を画面外に置けません。ホットプラグ記録にも全画面の段階がありません。そのため、補正処理と「切断で退避した後の掛け直し」は、実機ではまだ検証されていません。
  - 対策案: 判定を純粋関数（例 `restoreRect(place, on_screen: bool, work)`）に切り出して単体テストにする。ホットプラグ記録に、全画面中の切断という段階を加える。
- **低:** 戻り先の矩形が、残ったモニターに一部だけ重なる場合は補正されません（一部が画面外のまま戻ります）。

### M3（独立した照合）: 解消
- 照合している項目:
  - MONITORINFO と DEVMODE の矩形（`windows_monitor_probe.py:46-50`）
  - 作業領域、DPI、主画面
  - 前処理の probe との行単位の一致
  - Python 側の `MonitorFromWindow`、`GetDpiForWindow`、`GetClientRect`（`window-on.py:117-128, 178-183`）
- **残る低い点:** `DISPLAY-HZ` は独立に照合していません。`snapshot()` が `dmDisplayFrequency`（オフセット184）を記録していないためです。足すのは簡単です。

### M4（合成の成功を必須にし、呼び出しごとの時間を記録）: 解消
- `verify-windows-native-frames.py:63-64` は、合成が有効なら `-1` を必須にしています。
- `measure-windows-vsync.py:50` は、全サンプルの成功を必須にしています。
- **注意:** `measure` は静止画で測っています。mixed-refresh の `status: pass` は「手順が完了した」という意味です。モニターごとの周期の違いを確かめたものではありません。スクリプトの `limitations` もそう書いており、整合しています。

---

## testVsyncFailures（`host_window.zig:886-953`）
本物の worker、イベント、タイムアウトの処理を通っており、見た範囲では正しいです。

**各段階の評価:**
- **関数なし:** `loaded=true; flush=null` で即 false を返します。`LoadLibraryExW` の経路は通りません。これは合成の差し替えで、DwmFlush が実在しない環境とは別物です（報告の `limitations` にもそう書かれています）。
- **HRESULT が失敗:** false を返します。ただし、タイムアウトによる false と区別していません。
  - 修正案: 戻り時間が `vsync_limit_ms` 未満であることと、ロック下で `Vsync.result == -1` であることを確かめる。
- **ブロックと100ms のタイムアウト、busy 中の再試行:** 正しいです。`entered` を待ってから busy を確かめているので順序も確定しています。
- **古い完了通知:** `done` を消費せずに `busy` が解けるのを待ちます（`:940-948`）。そのうえで失敗値を返させるので、`ResetEvent`（`:872`）を外せば高い確率で検出できます。
- **回復:** 正しいです。
- **後始末（`:900-924`）:**
  - コメントの「残っている偽の flush を終わらせる」は不正確です。`entered` は手動リセットなので、`WaitForSingleObject(entered)` はすぐ戻ります。
  - ただし実害はありません。`request` は自動リセットで、worker は flush から戻った後に `test_stop` を見直して終了します。
  - ハンドルは worker の終了を待ってから閉じています。
- **低:** 冒頭の `expect(worker == null and !loaded)`（`:897`）は、同じテストバイナリの別のテストが先に VSYNC-WAIT を呼んでいると、順序次第で失敗します。スナップショットの外は確かめていません。

## 保存した通常矩形の DPI 換算（`:1930-1938`, `:1444`, `:1016-1021`）
- `windowed_dpi` は全画面に入るときに取り、`WM_DPICHANGED` のたびに `dpiScaledFrom` で換算して更新しています。これは通常表示の移動（`WM_GETDPISCALEDSIZE`）と同じ論理サイズの規則です。
- `placeOn` の全画面の分岐は、同期で届く `WM_DPICHANGED` の後で中央に置き直しています。
- テストでは `fullscreen-move` → `restore` のピクセル照合（`window-on.py:186`）が検証します。
- **低（仮説）:** 全画面中に元のモニターが一度消えて戻ると、`windowed_place` は退避先の DPI で換算されたまま、元のモニターへ戻ります。復元のときにもう一度 `WM_DPICHANGED` が来るので、サイズは直りますが、位置は Windows の提案矩形になります。

## 最小化中・最大化中の WINDOW-ON（`:1008-1032`）
- **L1（ソースで確定、影響は仮説）: 活性化の指定**
  - 最小化の分岐では、`GetWindowPlacement` が返す `showCmd`（通常は `SW_SHOWMINIMIZED`=2）をそのまま `SetWindowPlacement` に渡しています。この値は活性化を伴います。
  - 最大化の分岐の `SW_RESTORE`(9) と `SW_SHOWMAXIMIZED`(3) も活性化を伴います。
  - 通常表示の移動は `no_activate` を付けており、`:1664` の「コンソールがキーボードを持ち続ける」という方針とずれています。実際に前面が奪われるかは、フォアグラウンドロック次第の仮説です。
  - 修正案: 最小化の分岐では `placement.show = 7`（`SW_SHOWMINNOACTIVE`）にする。最大化の分岐の復元は `SW_SHOWNOACTIVATE`(4) にする。最大化には活性化しない ShowWindow の指定がないので、文書に明記するのが現実的です。
- **L2（防御）:** 最大化の分岐は再帰します（`:1012`）。復元に失敗して `IsZoomed` のままだと無限に再帰します。`ShowWindow(…)` の後に `if (IsZoomed(handle) != 0) return;` を入れれば防げます。
- **L3（仮説、テストが感知できない）: 作業領域基準の座標**
  - 変換には移動先モニターの `work - monitor` の差を使っています。Windows がどのモニターの差で座標を戻すかは実機で確かめる必要があります。
  - 全モニターでタスクバーが下にあると dx=dy=0 になり、変換が正しくても誤っていても結果は同じです。Windows 11 の標準構成がこれに当たります。報告済みの合格は、この点の根拠になりません。
  - 実験案: 上端や左端にアプリバーがある構成で試す。
- **L4（仮説）:** `wm_display_layout` は最小化された全画面窓にも `SetWindowPos` を掛けます。`IsIconic(handle) == 0` の条件を足すのが安全です。

## 新しいスクリプト
- **hotplug 記録:** 表示設定を変える呼び出しはなく、読み取り専用です。ただし N1 があります。報告の `physical_hotplug_tested=False` と `observed-awaiting-operator-confirmation` は正直な状態表示です。
- **mixed-refresh:**
  - フラグは正しいです。`CDS_TEST`(2) で事前に確かめ、本番の変更は flags 0 です。`CDS_UPDATEREGISTRY` はどこにもありません。`dmFields`(72) を `DM_DISPLAYFREQUENCY` だけに絞り、`dmDisplayFrequency`(184) を書き換えています。オフセットも正しいです。
  - watchdog は、変更の前に ready まで起動しています。復元は `restore` ファイルか90秒の期限で始まり、15秒まで再試行します。`pass` の条件は「測定完了」「復元確認」「watchdog の終了コード 0」「最終構成が一致」の全部で、状態表示は正しいです。
  - **低:**
    1. watchdog はジョブから外れていません。親が kill-on-close ジョブの中で動いていると、親と一緒に終了する可能性があります（仮説）。対策は `CREATE_BREAKAWAY_FROM_JOB` を試し、拒否されたら今の起動方法に戻すことです。
    2. watchdog が復元に失敗したとき、親は最後の復元を試みません。
    3. `final_monitors == initial` は HMONITOR まで比べます。値が変わる環境では、正しく戻っていても失敗と判定されます（偽陽性ではなく偽陰性の側です）。
- **SigmaSession の変更（`windows_display_test_support.py:141-146, 206`）:**
  - 一時ディレクトリの `accept.fs` に書いて引数で渡す方式は、行の受け渡しやジョブの扱いを変えていません。
  - **低:** `close()` は `process.wait(timeout=5)` が例外を出すと、ジョブのハンドルを閉じず、一時ディレクトリも消さずに抜けます。`try/finally` で順に片付けてください。
  - **低:** `write_text` は Windows で改行を CRLF にします。既存のテストは合格と報告されているので問題ないはずです。スナップショット外で SigmaSession を使うスクリプトへの影響は確かめていません。
- **frames:** 前回の L6 は、待機に入った後で閉じ、待った時間を確かめる方式（`:78-85`）に変わり、解消しています。

## 次の実験（優先順）
1. N1 を直した後、物理的な抜き差しをして、HMONITOR とデバイス名が変わるかを記録する。
2. 全画面のまま、その窓があるモニターを切断する。窓が退避先を覆うこと（M2 の掛け直し）と、全画面を解除すると作業領域の中央へ戻ること（補正）を確かめる。
3. 最小化と最大化での WINDOW-ON の前後で `GetForegroundWindow` を記録し、L1 を確かめる。上端や左端にアプリバーがある構成で、L3 を確かめる。

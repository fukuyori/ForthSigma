# tque1037 Windows 表示先選択とフレーム待機のレビュー

**結論:** 重大度「高」の不具合はありませんでした。ソースを読んで確定できた中程度の欠陥は2件（M1、M2）です。加えて、テストが誤って合格しうる箇所（偽陽性）が2件（M3、M4）あります。VSYNC-WAIT と WINDOW-PAINT-WAIT の同期処理（イベント、ロック、`busy` フラグ）は読んだ限り正しいです。

ドキュメントにある実行結果は報告として扱い、私自身は何も実行していません。対象はスナップショット `.work/1037/windows-review/` だけです。

---

## 中程度（ソースから確定）

### M1. 全画面のまま閉じた窓を、WINDOW-ON 指定ありで開き直すと配置が壊れる
- **場所:** `src/host_window.zig:1504`（`placeOn`）、`:1531`（`fullscreen_on = false`）、`:1833-1842`（`wm_destroy`）
- **原因:** `wm_destroy` が `fullscreen_on` を戻しません。次に `run()` が呼ぶ `placeOn` は、古い `fullscreen_on == true` を見て全画面用の分岐（`:905-908`）に入ります。その結果、通常枠のスタイルのまま窓がモニター全体に広がります。リセットはその後の `:1531` で行われますが、もう遅いです。
- **再現 1:** `TRUE FULLSCREEN` → `WINDOW-CLOSE` → `FALSE FULLSCREEN` → `k WINDOW-ON` → `SHOW`
  - `applyFullscreen` は、希望（false）と現状（false）が同じなので何もせず戻ります。
  - 枠付きの通常窓が、作業領域ではなくモニター矩形いっぱいのまま残ります。
- **再現 2:** 全画面の希望を残したまま開き直す場合
  - 開いた直後は正しく全画面になります。
  - ただし `windowed_place` にモニター矩形が保存されるので、`FALSE FULLSCREEN` で戻すと作業領域中央に戻りません。
- **条件:** WINDOW-ON 未指定なら `placeOn` は何もしないので起きません。指定した場合だけ起きます。
- **修正案:** `run()` で `fullscreen_on = false;` を `placeOn(handle)` の前（`:1504` より前）に移します。念のため `wm_destroy` でも false に戻します。
- **テスト:** 上の2つの手順を `verify-windows-window-on.py` の段階に加えます。期待値はどちらも「通常表示で作業領域中央、高さは作業領域以下」です。今の21段階は全画面中に閉じる操作を一度もしないので、この不具合を検出できません。

### M2. 全画面中の画面構成変更を追いかけず、全画面解除時の戻り先も検証していない
- **場所:** `src/host_window.zig:1711-1714`、`:1326-1330`
- **ソースで確定していること:**
  - `WM_DISPLAYCHANGE` では状態を記録して変更回数を増やすだけで、全画面窓をモニター全体に掛け直しません。
  - 全画面解除時は `windowed_place` をそのまま `SetWindowPos` に渡します。その位置に今もモニターがあるかは確かめていません。
- **実機が必要な仮説:**
  - 全画面のモニターの解像度を変えたり切断したりすると、窓が古いサイズのまま残る。
  - 戻り先が切断済みモニターの座標になり、窓が画面外へ出る。
- **修正案（今の契約「全画面は表示中のモニターを覆う／解除で作業領域中央へ」に沿う形）:**
  - `wm_display_change` で、自分宛てに専用メッセージを `PostMessageW` します。そのハンドラで `fullscreen_on` なら、`MonitorFromWindow` と `GetMonitorInfoW` で矩形を取り直して掛け直します。Windows による窓の退避が終わってから処理するためです。
  - `applyFullscreen` の解除処理では、`MonitorFromRect(&windowed_place, MONITOR_DEFAULTTONULL)` が null なら、`windowed_place = centered(windowed_place, 現在モニターの作業領域)` に直してから戻します。

## 中程度（テストが誤って合格しうる箇所）

### M3. 「独立に取得した矩形」での照合のうち、期待値側は Sigma 自身の情報
- **場所:** `tests/scripts/verify-windows-window-on.py:80-86`、`:97`、`:104-109`
- **独立しているもの:** 窓の実際の位置（Python 側の `GetWindowRect`）だけです。
- **独立していないもの:**
  - 期待値のモニター矩形と作業領域は、Sigma の `DISPLAYS` の出力です。
  - 表示先の一致確認（`display == target`）も Sigma の `WINDOW-DISPLAY` です。
- **影響:** `host_display` の列挙と `placeOn` はどちらも、同じ DPI 認識状態で `GetMonitorInfoW` を使います。そのため、列挙自体の誤り（取り違え、仮想化された座標、索引のずれ）があっても両方が同じように間違え、テストは合格します。ドキュメント17行目の「別のWin32接続」が独立と言えるのは、窓の実際の位置だけです。
- **修正案:**
  1. Python 側で、per-monitor DPI aware v2 の状態で `EnumDisplayMonitors` と `GetMonitorInfoW(MONITORINFOEX)` を呼び、デバイス名・矩形・作業領域・主画面フラグの集合を Sigma の一覧と突き合わせる。
  2. 別系統の API である `EnumDisplaySettingsW(szDevice, ENUM_CURRENT_SETTINGS)` の `dmPosition` と `dmPelsWidth/Height` で、矩形を照合する。これは DPI 認識状態に左右されない物理値です。
  3. 表示先は、Python 側の `MonitorFromWindow(hwnd)` の結果から Python の一覧の索引を引き、Sigma の `target` 矩形と一致するかで判定する。
  4. 段階ごとに、テスト対象のプロセス内で取った列挙を、事前の probe プロセスの列挙と矩形まで比べる。今は数（`:80`）だけで、コメント（`:58-59`）の主張より弱いです。

### M4. VSYNC-WAIT が false でも合格する
- **場所:** `tests/scripts/verify-windows-native-frames.py:56`（`row[3] in (0, -1)`）
- **影響:** VSYNC-WAIT が常に失敗する実装でも合格します。DwmFlush はモニターごとの処理ではないので、「3画面それぞれで実行」という段階分けにはモニター間の差を検出する力がありません。ドキュメント34行目のレート値は `DISPLAY-HZ` の出力で、待機周期を測ったものではありません。ここはドキュメント35行目でも自ら注記しています。
- **修正案:**
  - DWM がある環境では `row[3] == -1` を必須にします。
  - 連続 N 回（例: 240回）呼んだときの間隔の中央値と p95 を JSON に記録します。

---

## 低（確定した欠落、または小さな問題）

- **L1. 作業領域だけの変更では WINDOW-CHANGES が増えない（`:1711` 付近）**
  - タスクバーの移動などで起きる `WM_SETTINGCHANGE`（`wparam == SPI_SETWORKAREA` 0x2F）を処理していません。`DISPLAY-WORK` の値は変わるので、契約の「displays change」に当たります。
  - 修正案: `0x001A && wparam == 0x2F` のときに `noteWindow(handle, true)` を呼ぶ。
  - 窓のない**別の**モニターの倍率変更で `WM_DISPLAYCHANGE` が届くかは仮説で、実験で確かめる必要があります。
- **L2. 全画面のまま異なる DPI のモニターへ移ると、解除後のサイズが DPI 換算されない（`:905-906`）**
  - `windowed_place` は移動元モニターの物理ピクセルのまま中央に置かれます。
  - 通常表示での移動では `WM_DPICHANGED` で論理サイズが保たれるので、挙動が一致しません。
  - 修正案: `GetDpiForMonitor` で新旧の DPI を取り、`dpiScaledSize` と同じ換算を `windowed_place` にかける。
- **L3. 最小化中・最大化中の WINDOW-ON（`:910-913`、仮説）**
  - 最小化中に `GetWindowRect` を呼ぶと、アイコン化された位置（-32000付近）が返ります。復元したときに元のモニターへ戻る可能性があります。
  - 修正案: `IsIconic` または最大化中なら、`GetWindowPlacement`/`SetWindowPlacement` で `rcNormalPosition` を中央に置き直す。
  - 3画面の環境があれば、物理的な抜き差しなしで確かめられます。
- **L4. 初回から異なる DPI のモニターに開くと、サイズが作成時のモニター基準になる（`:1490-1504`、仮説）**
  - 枠のサイズは、既定位置（主画面）の DPI で計算されます。非表示の窓に `WM_DPICHANGED` が届くかによって、クライアント領域が変わります。
  - `open-i` の段階はサイズを検証していません。
  - 修正案: 指定モニターがあれば、その作業領域の左上で `CreateWindowExW` してから `windowSize` を計算する。
  - テスト追加案: `GetClientRect` と `GetDpiForWindow` を、`WINDOW-PIXELS` と照合する。
- **L5. 通常表示での移動の検証が中央配置だけ（`verify-windows-window-on.py:106-109`）**
  - サイズが保たれたか、DPI 換算されたかを見ていません。
  - 通常表示での移動は 0→1 と 2→0 の2方向だけなので、100%↔125% の往復は片方向しか検証されていない可能性が高いです。JSON の索引と倍率の対応で確認してください。
  - WINDOW-CHANGES は一度も読んでいません。
- **L6. 「閉じた窓への待機」テストが別の理由でも合格しうる（`verify-windows-native-frames.py:67-75`）**
  - `send` の 0.1 秒後に `WM_CLOSE` を送るので、Forth がまだ待機に入っていなければ「窓なしで即 false」でも同じ `0 0` が出ます。
  - 修正案: 待機直前に印となる行を出し、Python はそれを受け取ってから 300ms 後に `WM_CLOSE` を送る。Forth 側で待機の経過時間を出力し、250ms 以上 2秒未満であることを確かめる。
- **L7. 古い HMONITOR の値が別のモニターに再利用される可能性（`:902-904`、仮説）**
  - `GetMonitorInfoW` が成功すれば、別のモニターへ置いてしまいます。
  - 防御的な修正案: `windowPlace` の時点で `szDevice` を `place_monitor` と一緒に保存し、`placeOn` で一致を確かめる。
  - 契約は「DISPLAYS が取った HMONITOR」のままとし、再接続後は `DISPLAYS` と `WINDOW-ON` を呼び直す必要があることをドキュメントに明記するよう勧めます。

## 問題なしと確認した点
- **VSYNC-WAIT（`:813-826`、`:841-857`）:**
  - タイムアウト後の呼び出しは `busy` を見て即 false を返します。
  - worker の完了時に残った `done` の通知は、次の呼び出しがロック下の `ResetEvent` で消します。
  - 結果の読み出しもロック下です。
  - 前の呼び出しの完了通知で誤って起きる競合はありません。
- **WINDOW-PAINT-WAIT（`:757-778`、`:499-507`、`:1603-1609`）:**
  - 状態をループで見直すので、古い自動リセットのシグナルで起きても誤りになりません。
  - 窓を破棄すると `SetEvent` で即座に起きます。
- **`host_display.zig`:** DISPLAYCONFIG の構造体サイズ（PathInfo 72B、ModeInfo 64B）と DEVMODE のオフセットは正しいです。

---

## 次の実験（優先順）

1. **M1 の再現**（ハードウェア不要）。修正後に、上の2手順を自動テストに加えます。

2. **物理的な切断と再接続**
   - 各段階で `DISPLAYS`（HMONITOR 値とデバイス名）、`WINDOW-DISPLAY`、`WINDOW-CHANGES`、`GetWindowRect` を記録します。
   - 切断・再接続の前後で、HMONITOR の値が変わるかを全モニターについて確かめます（切断していないモニターも含めて）。
   - 次の4つの状態でそれぞれ試します: 通常表示・全画面・最小化・窓を閉じたまま WINDOW-ON 指定。
   - 再接続後に再表示して、既定位置に出るか誤配置されるかを見ます。
   - 全画面中に切断したとき、窓が退避先のモニターを覆うかを確かめます（M2）。
   - 窓のない別のモニターで倍率と作業領域を変え、WINDOW-CHANGES が増えるかを確かめます（L1）。

3. **リフレッシュレートが異なる構成**（例: 144Hz と 60Hz）
   - 窓をそれぞれのモニターに置いた状態で、VSYNC-WAIT を連続 600回呼び、間隔の分布を取ります。
   - 静止画のときと、毎回 SHOW するときの両方で測ります。
   - 主画面を入れ替えて繰り返します。
   - これで、DwmFlush がどのモニターの周期に従うか、表示内容が変わらないときに即座に戻るかが分かります。

4. **DwmFlush が使えない場合**
   - `Vsync` の読み込みと worker 起動を分け、テスト用に flush を差し替えられるようにします。
   - 差し替えた flush で、次の3つを単体テストにします:
     - 永久にブロックする flush: 1回目が約100msで false、2回目が即 false、解放後に true。
     - E_FAIL を返す flush: false。
     - `flush == null`: false。
   - 実環境では、Win7 の Basic テーマなど DWM 合成が無効にできる VM があれば確かめます。

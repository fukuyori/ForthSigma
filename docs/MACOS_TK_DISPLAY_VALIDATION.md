# macOSのTk表示支援の検証

2026-11-23、macOS 27.2.1（arm64）、Homebrewのwish（Tcl/Tk 9.1.0）、Zig 0.17.1。`6d0cb36`に本作業の未コミット変更（`sigma_tk.tcl`の`<Unmap>`での放し）を加えた実行体。
実行体のSHA-256は各JSONに記録している。Windows版の検証（[WINDOWS_TK_DISPLAY_VALIDATION.md](WINDOWS_TK_DISPLAY_VALIDATION.md)）と同じ手順を、macOS用に移したスクリプトで行った。
どれもTclの`wm`・`focus`・`event generate`と、インストール済みの`WM_DELETE_WINDOW`ハンドラーを呼ぶ合成の操作である。物理ボタン、実際のIME変換、画面への実提示は確認していない。
スクリプトはSigmaを新しいプロセスグループで起動し、終了時にwishとAppKitの子プロセスが残っていないことを確かめる（`tests/scripts/macos_display_test_support.py`）。

## 状態通知（1299）

`python3 tests/scripts/verify-macos-tk-state.py --output docs/measurements/2026-11-23-macos-tk-state.json`

23段階が成功。[結果](measurements/2026-11-23-macos-tk-state.json)。Windowsと同じ段階（画像へのフォーカス、別toplevel、IME用widget、合成のキー保持、最小化と復帰、close/reopen、TCL-STOP/restart、イベントキュー満杯、fullscreenでのclose/reopen、nativeとの切替え、SAVESYS実行体の新規起動）を確認した。

macOSで見つかった違いが2つある。

- 最小化で押されたままのキーが放されなかった。Aqua Tkは`wm iconify`で`<FocusOut>`を送らず、`<Unmap>`だけを送る（wishだけの試験でも同じ）。Sigmaは`<FocusOut>`でキーを放していたので、最小化しても`KEY-HELD?`が真のままだった。`sigma_tk.tcl`で、トップレベル`.`の`<Unmap>`でも`sigma_keys_released`を呼ぶようにした。WindowsとLinuxでは`<FocusOut>`ですでに放しているので、二度目は何もしない。WindowsとLinuxでの再実行は1342に残す。
- 合成のキー入力`event generate ... -keysym a -keycode 65`は、Aquaでは文字`A`（大文字）になる（65はWindowsのAのキーコード）。macOS用のスクリプトでは`-keysym a`だけにした。Sigmaの動作の違いではなく、試験の入力の違いである。

## 閉じる要求の保留（1338）

`python3 tests/scripts/verify-macos-tk-close.py --output docs/measurements/2026-11-23-macos-tk-close.json`

17段階が成功。[結果](measurements/2026-11-23-macos-tk-close.json)。Windowsと同じ期待値（保留、確認、未確認の二度目でのwithdraw、明示的closeを数えない、設定を偽へ戻す、wish再起動への引継ぎ、nativeとの併用、表示label破棄後、利用者のTCL-EVAL結果の保持）がそのまま成り立った。

## フレーム提示（1304）

`python3 tests/scripts/verify-macos-tk-frames.py --output docs/measurements/2026-11-23-macos-tk-frames.json`

6段階が成功。[結果](measurements/2026-11-23-macos-tk-frames.json)。Tk選択中の`WINDOW-FRAMES`は0 0、`WINDOW-PAINT-WAIT`と`VSYNC-WAIT`は偽で、nativeの値を流用しない（1300の決まり）。nativeを選ぶと、1302で実装したmacOSのnativeの値（1 1、待ちは真）になる。Tkの描画完了は未対応のまま。

## 表示領域と拡大（1288）

`python3 tests/scripts/verify-macos-tk-window.py --output docs/measurements/2026-11-23-macos-tk-window.json`

9通り（Tkの窓3つの大きさ×`WINDOW-FIT` 0〜2）が成功。[結果](measurements/2026-11-23-macos-tk-window.json)。Tkは`WINDOW-FIT`によらず整数倍で中央に置き、`sigma_view_rect`の値は独立に計算した整数倍の規則と一致した。

macOSでは、Tkのウィンドウの`WINDOW-PIXELS`は0 0、`WINDOW-IMAGE-RECT`は0が4つである。AquaのTkの`winfo id`はmacOSのウィンドウ番号ではなく、ホストが物理ピクセルの大きさを聞けないため。文書の対応表のとおり。

## 補間

`python3 tests/scripts/verify-macos-tk-smooth.py --output docs/measurements/2026-11-23-macos-tk-smooth.json`

[結果](measurements/2026-11-23-macos-tk-smooth.json)。Windowsと同じく、`WINDOW-SMOOTH`の真偽どちらでもTkのphotoは最近傍の期待画素と一致した。Tkの表示経路では補間は未対応で、指定を覚えるだけである。

## 確認

`zig build test`は1373成功・31 skip。`check-docs.py`の指摘は0件。

# Windowsの表示先選択とフレーム待機

2026-11-23、現在のWindows通常ビルドで実行した。通常ビルドと`zig build test`は成功。
後者にはWindowsでの`win32.testCentered`も含む。各結果JSONに実行体SHA-256を記録し、
Tk Unmap回帰確認と同じ`50afff149fa50a626867bc72b7d54aac2d058d139ac0edb0a23408f765af52f4`だった。

## 表示先選択（1344）

`python tests/scripts/verify-windows-window-on.py --output docs/measurements/2026-11-23-windows-window-on.json`

[結果JSON](measurements/2026-11-23-windows-window-on.json)。3画面で21段階が成功。
主画面2560×1440・100%、左画面1920×1080・100%、右画面1920×1080・125%という構成。
選択だけでは窓を開かないこと、各画面での新規表示、表示中の移動、全画面への切替え、
全画面のまま別画面へ移動、通常表示への復帰、-1指定での位置維持を確認した。
WINDOW-DISPLAYとFULLSCREEN?に加え、所有プロセスのSigmaGraphicsWindowだけを列挙し、
別のWin32接続のGetWindowRectで外枠座標を取得した。
通常表示は作業領域中央、全画面はモニター矩形との完全一致を照合した。
検証プロセスもper-monitor DPI awareとし、100%と125%の間の移動を同じ座標系で照合した。

画面構成や倍率の変更は行っていない。物理切断、不在画面指定のまま再表示、再接続後の維持と
明示的な再選択は未確認なので、1344全体は未完了とする。

## フレーム待機（1276）

`python tests/scripts/verify-windows-native-frames.py --output docs/measurements/2026-11-23-windows-native-frames.json`

[結果JSON](measurements/2026-11-23-windows-native-frames.json)。現在の語名はWINDOW-PAINT-WAITであり、
旧SHOW-WAITは現在の辞書には存在しない。
通常描画後の待機成功、所有窓をShowWindowで最小化して新たにSHOWした後の150ms待機失敗、
最小化中の5000ms待機開始後にWM_CLOSEを送り、期限前に偽と閉状態が返ること、
閉じた後の待機失敗、再表示後の待機成功を確認した。
子プロセスは専用jobで管理し、正常終了時の残存プロセスがないことも共通ヘルパーで照合した。

3画面それぞれでVSYNC-WAITを実行し、取得したレートは59951/1000、60/1、60/1 Hzだった。
これだけでは大きく異なるリフレッシュレートでの待機周期や物理的な提示を確認したことにはならない。
DwmFlushを利用できない環境も未確認であり、1276全体は未完了とする。

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

## Claude Codeレビュー後の再確認

同日、1037の継続作業として固定スナップショットへのClaude Codeレビューを依頼した。
[初回](reviews/1037-windows-native-claude-review.md)、[再レビュー](reviews/1037-windows-native-claude-followup.md)、
[最終レビュー](reviews/1037-windows-native-claude-final.md)。いずれもRead/Grep/Globのみの静的レビューで、
実行検証は別途行った。[対応記録](reviews/1037-windows-native-review-response.md)。

### 表示先選択の93段階

`python tests/scripts/verify-windows-window-on.py --sigma .work/1037/windows-final5/bin/sigma.exe --output docs/measurements/2026-11-23-windows-window-on-reviewed.json`

[結果JSON](measurements/2026-11-23-windows-window-on-reviewed.json)。3画面で93段階が成功。
従来の21段階に、全画面でcloseした後の通常表示・全画面での再表示、全画面解除、
最小化中の移動と復帰、最大化中の移動、最大化へ戻る最小化、最小化された全画面の移動、最小化中に全画面を解除してから復帰する場合を追加した。
100%から125%、125%から100%への復帰でクライアントの160×100／200×125も照合する。
主画面の作業領域は左端48ピクセルを除く構成で、作業領域基準の配置を確認した。
合成WM_DISPLAYCHANGEでは所有する全画面窓だけを一度100×100へ縮め、通知後に画面全体へ戻ることを確認。
合成WM_SETTINGCHANGE/SPI_SETWORKAREAではWINDOW-CHANGESが増えることを確認した。
これらの通知は物理切断を代用するものではない。

期待値も独立に取得するよう補強した。PythonでMONITORINFOEXのデバイス名・矩形・作業領域・主画面・DPIを列挙し、
別APIのDEVMODEの位置と幅・高さとも照合する。窓の所属はMonitorFromWindow、DPIはGetDpiForWindow、
クライアント寸法はGetClientRectで照合する。事前プローブとの全項目の一致と、終了時の構成維持も確認する。

実際に再現して修正した不具合は、全画面のまま閉じた状態の次のHWNDへの持越し、
全画面移動後の通常サイズのDPI換算、最小化中の選択が復帰位置へ反映されない問題、最大化中の移動である。
復帰途中の矩形を使うと高さ0や枠のDPI差を含む寸法ずれが起きたため、Windowsの保存位置から通常サイズとDPIを保持する。
さらに内部ログで、復帰中の通知から送ったメッセージがWindowsの復帰処理に再入し、修正した矩形を後から上書きされる順序を確認した。
再配置は低優先度のWM_TIMERで復帰処理後に行い、DPI切替え後の寸法でも再設定する。
最大化中の移動は通常表示で配置して再最大化するため、最後の最大化で活性化する可能性がある。

### フレーム待機と異常系

`python tests/scripts/verify-windows-native-frames.py --sigma .work/1037/windows-final5/bin/sigma.exe --output docs/measurements/2026-11-23-windows-native-frames-reviewed.json`

[結果JSON](measurements/2026-11-23-windows-native-frames-reviewed.json)。DWM合成が有効な環境ではVSYNC-WAITの成功を必須にした。
待機途中のcloseは、Forth内部の待機時間も取得し、250ms以上2秒未満で閉状態と偽が返ることを確認する。
閉じる前に待機へ入っていなかった場合に合格しない条件である。

`zig build test`のWindowsホストテストには、実際の待機スレッドとイベントを使う異常系を追加した。
関数なし、HRESULT失敗、ブロックした関数の100ms期限、処理中の再呼出し、古い完了通知、解放後の回復を確認する。
テスト内の関数差替えであり、DwmFlushのないOS・合成を利用できない実環境での受け入れとは区別する。
通常ビルド・テストは成功。Tk状態通知23段階、close制御17段階、フレーム情報6段階、補間の回帰も成功した。
Tk状態通知の最終実行は[結果JSON](measurements/2026-11-23-windows-tk-state-reviewed.json)に残す。

### VSYNC-WAITの周期測定

`python tests/scripts/measure-windows-vsync.py --sigma .work/1037/windows-fast-final4/bin/sigma.exe --output docs/measurements/2026-11-23-windows-vsync-timing-reviewed.json`

`python tests/scripts/measure-windows-mixed-refresh.py --sigma .work/1037/windows-fast-final4/bin/sigma.exe --output docs/measurements/2026-11-23-windows-mixed-refresh-reviewed.json`

[通常構成](measurements/2026-11-23-windows-vsync-timing-reviewed.json)、[75Hz/60Hz混在](measurements/2026-11-23-windows-mixed-refresh-reviewed.json)。
前者は各画面120回×3巡、後者は120回×2巡。画面の順番を巡回し、全呼出しの成否と時間を保存する。
初回測定では通常構成の中央値は約16.65ms、主画面74.971Hz・他60Hzでは約13.35msだった。
計測は最後の全画面最小化の低指摘修正より前の同じVSYNC-WAIT実装で行った。各実行体の指紋と測定値はリンク先JSONを参照する。
窓を60Hzの画面へ置いても主画面側に近い周期になり、VSYNC-WAITを窓のある画面の垂直同期とは扱えない。
画面への物理提示や、毎回SHOWする負荷での周期を測った結果ではない。

混在測定は同じ解像度で列挙済みの75HzモードをCDS_TESTで確認し、一時的に周波数だけを変更する。
レジストリ保存のフラグは使わない。変更前に別プロセスのwatchdogへ元のDEVMODEを渡し、
通常終了時と90秒期限で復元できるようにした。成功は復元結果・元モード・元の画面配置/DPIを照合してから記録する。
再接続で変わり得るHMONITORを構成復元の条件にしない。
[親の異常終了試験](measurements/2026-11-23-windows-refresh-watchdog.json)では、親がos._exitでfinallyを通らず終了しても、
別プロセスが元の設定へ戻すことを確認した。この試験用期限は5秒で、通常測定の90秒とは別である。

### 物理切断の記録準備と残件

`verify-windows-display-hotplug.py`は設定変更を行わず、操作者による副画面の切断・再接続を記録する。
通常表示と全画面の`--preflight`は成功した。
[通常の事前確認](measurements/2026-11-23-windows-hotplug-preflight.json)、
[全画面の事前確認](measurements/2026-11-23-windows-hotplug-fullscreen-preflight.json)。
これは抜き差しの確認ではない。再接続はハンドルやGDI番号ではなく矩形・作業領域・DPI・主画面の構成で判定し、
変わったハンドルとデバイス名も別途記録する。最終状態は操作者の確認待ちとして保存する。

実際の切断を行う場合は次を実行し、表示された副画面のケーブルを切断し、再接続の表示後に同じケーブルを戻す。
切断中の通知、画面不在のままclose/reopen、再接続後10秒の位置維持、明示的選択まで記録する。
`--fullscreen`では切断後の全画面の被覆と解除後の中央配置も確認する。

```powershell
python tests/scripts/verify-windows-display-hotplug.py --sigma .work/1037/windows-final5/bin/sigma.exe --fullscreen --output docs/measurements/windows-physical-hotplug.json
```

1344の物理切断・再接続と、1276のDwmFlush非対応実環境は未確認なので、両タスクは未完了を維持する。

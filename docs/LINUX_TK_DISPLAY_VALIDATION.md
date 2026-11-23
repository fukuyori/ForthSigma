# LinuxのTk表示支援・追加検証

2026-11-23、Linux x86_64 / XWayland、Zig 0.17.1、HEAD `e7514502c1a8d667037cc5557013ee37d4377ee8`に未コミットの表示支援修正を加えた状態。`zig build`で通常実行体を作り直し、以下を順番に実行した。実行体のSHA-256は各JSONに記録。Sigmaと子プロセスは専用のプロセスグループで管理する。

## 状態通知の回帰（1346、親1342）

`python3 tests/scripts/verify-linux-tk-state.py > docs/measurements/2026-11-23-linux-tk-state-regression.json`

23段階が成功。[結果](measurements/2026-11-23-linux-tk-state-regression.json)。フォーカス、IME用widget、合成キー保持、最小化時のキー解放、復帰、close/reopen、wish再起動、イベントキュー満杯、fullscreen、nativeとの切替え、保存アプリの初期状態を確認した。1299で追加したトップレベルのUnmap時のキー解放を含む実行体である。Windowsの子1347は未確認。1342はOS別の確認を集約する親として維持する。

## 閉じる要求の保留（1337）

`python3 tests/scripts/verify-linux-tk-close.py --output docs/measurements/2026-11-23-linux-tk-close-regression.json`

17段階が成功。[結果](measurements/2026-11-23-linux-tk-close-regression.json)。最初の要求の保留、WINDOW-CLOSESでの確認、他の状態照会では確認しないこと、未確認の二度目で閉じること、明示的closeを数えないこと、設定解除、wish再起動への設定引継ぎを確認した。nativeとTkを併用してTkだけを閉じること、表示label破棄後の操作、TCL-EVALの結果を保持することも確認した。

## フレーム情報（1303）

`python3 tests/scripts/verify-linux-tk-frames.py --output docs/measurements/2026-11-23-linux-tk-frames-regression.json`

6段階が成功。[結果](measurements/2026-11-23-linux-tk-frames-regression.json)。Windows1300・macOS1304と同じ未対応の契約をLinux実機で確認した。Tk選択中はWINDOW-FRAMESが0/0、WINDOW-PAINT-WAITとVSYNC-WAITは偽。30回連続SHOW・update idletasks後も同じ。nativeを選ぶと1/1・待機成功、Tkへ戻すと再び0/0・偽となり、nativeを閉じてもTkの値は変わらない。

1303は親1277の「実装または未対応として記録する」のうち、未対応を記録する確認として完了。Tkの描画完了通知は実装していない。以前の調査用verify-linux-tk-frame-gap.pyも現行値で再実行したが、今回の契約確認は上記の専用スクリプトで記録した。

## 範囲と残件

状態通知はX11のWMメッセージとTclの合成操作、close制御はインストール済みTclハンドラーの呼出しによる。物理ボタン、実際のIME変換、画面への実提示を確認した記録ではない。通常ビルドは成功。初回確認の後にnativeのWINDOW-ONを修正しており、最終実行体で再実行した記録へ更新した。初回JSONにはcommitと環境情報を採取後に付記していたが、再実行後のJSONは上記コマンドの出力そのものである。

1037全体は未完了。Linux1345・1336は後続の物理切断・再接続確認を含めて完了した。残る葉はWindowsの1276・1344・1347（親1342）。

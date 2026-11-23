# WindowsのTk表示支援・追加検証

2026-11-23、Windows / Zig 0.17.1。`d29bdbe`に本作業の未コミット変更を加えた実行体。
実行体のSHA-256は各JSONに記録。物理ボタン・実際のIME変換・画面への実提示は確認していない。

## 状態通知（1295）

`python tests/scripts/verify-windows-tk-state.py --output docs/measurements/2026-11-23-windows-tk-state.json`

23段階が成功。[結果](measurements/2026-11-23-windows-tk-state.json)。
選択だけではwishを起動しないこと、画像表示、画像へのフォーカス、別toplevelへのフォーカス、IME用widgetへのフォーカス、
合成のキー保持、最小化による解放、復帰、close/reopen、TCL-STOP/restart、イベントキュー満杯、
fullscreenでのclose/reopen、nativeとの切替え、SAVESYS実行体の新規起動を確認した。
Tclのwm/focusとインストール済みWM_DELETE_WINDOWハンドラーを呼ぶ合成操作である。
close回数はセッション間で保持し、新しい保存アプリでは0になる。

## 閉じる要求の保留（1326）

`python tests/scripts/verify-windows-tk-close.py --output docs/measurements/2026-11-23-windows-tk-close.json`

17段階が成功。[結果](measurements/2026-11-23-windows-tk-close.json)。
WINDOW-KEEP-OPENの既定偽、設定前の非起動、SHOW時の設定引渡し、最初のclose要求の保留、
WINDOW-CLOSESによる確認、他の3つの状態照会では確認しないこと、未確認の二度目でのwithdraw、
明示的closeを数えないこと、設定を偽へ戻すと保留だけを捨てて窓を閉じないこと（既存nativeと同じ）、wish再起動への設定引継ぎ、nativeとの併用、
表示label破棄後の操作、利用者のTCL-EVAL結果の保持を確認した。

プログラムのWINDOW-CLOSEは選択中のTkだけを閉じ、nativeは開いたまま。
WINDOW-KEEP-OPENの設定は両方へ適用する。内側のGFX-TK-WINDOW-CLOSEは固定バッファで応答を受け、
ユーザーのTCL結果を上書きしない。画像を渡す際のTclコマンドに設定を含め、未起動のwishを設定だけで起動しない。
新しいBuiltinで保存辞書ABIが変わるため、以前の保存アプリと辞書イメージは作り直す。
Linux/macOSの共通コードにも反映されるが、この記録はWindowsでの実行であり他OSの受け入れではない。

## 補間（1318）

`python tests/scripts/verify-windows-tk-smooth.py --output docs/measurements/2026-11-23-windows-tk-smooth.json`

[結果](measurements/2026-11-23-windows-tk-smooth.json)。2×2の4色画像を整数倍で100×100へ拡大したTk photoをPPMで読み戻し、
真・偽それぞれ30,000バイトのRGBを独立に構成した最近傍の期待画素と照合して一致。
WINDOW-SMOOTHは現在のTk表示経路では未対応として記録する。
Tk一般に補間できないという結論ではなく、Sigmaの現在のphoto zoom/subsample経路の制限である。

## フレーム情報（1300）

`python tests/scripts/verify-windows-tk-frames.py --output docs/measurements/2026-11-23-windows-tk-frames.json`

[結果](measurements/2026-11-23-windows-tk-frames.json)。現在のTcl通信には同じ描画接続での完了通知がなく、
sigma_showの応答やupdate idletasksを、サーバーでの描画完了や物理提示として扱うことはできない。
今回、Tk選択中のWINDOW-FRAMESは0/0、WINDOW-PAINT-WAITとVSYNC-WAITは偽を返すよう修正した。
Tk単独と30回連続SHOW、idle処理、nativeとの併用、nativeを明示的に閉じた後の6段階で確認した。
nativeを選べば元の1/1と待機成功を取得でき、Tkを再選択すると再び0/0と偽になる。
従来の「Tkを選んでいてもnativeの番号と待ちを返す」挙動を受け入れ値にはしない。

1300は「実装または未対応を記録する」のうち未対応の明示として完了。
Tk描画完了を実装したという意味ではない。Linux1303/macOS1304の実機確認と、
将来Tk描画完了を識別する仕組みを作る作業は区別する。

## 回帰と残件

通常とgraphics除外のzig build test、通常とgraphics除外のビルド、全語リファレンスと英日文書整合が成功した。
共通のプロセス回収はwindows_display_test_support.pyに集約。KEYゲート後のjob割当、KILL_ON_JOB_CLOSE、
成功時の子プロセス数0、期限付きの出力読取りを使う。
状態通知macOS1299、Tk close制御のLinux/macOS実行、物理ボタン・IME変換、
表示先選択1039、その他のMac固有機能、物理構成変更は別の確認として残す。


## 最終再実行

HELP明確化後の同一Windows通常実行体で表示支援5本を再実行し、全て成功した。
各JSONの通常実行体SHA-256は同一。通常テスト1371成功・25skip、graphics除外1201成功・191skip。
全語リファレンスは実辞書との照合、EKEYS35値、文書例28件、単独使用例424件が成功。文書チェックは指摘0件。
Linux x86_64 muslとmacOS arm64のクロスビルドも、最終HELP明確化直前の同じ動作実装で成功。
クロスビルドは他OSでの実行確認ではない。

最終通常実行体のSHA-256：`e51ad9acfbc2b61c1eab985a71b43fba6c6364dcd3476706aa631e728c3869be`。表示支援5本とアルファ画像1310が同じ実行体であることを現物hashから再照合した。graphics除外実行体はHELP明確化前の同じ動作実装で、最終通常実行体とは別hashとして記録している。

この文書の「最終」はTk表示支援の検証段階を指す。その後のRGBA PNG保存追加1339は別の実行体・別の検証記録（[PNG保存](PNG_ALPHA_SAVE.md)）であり、上記hashを新機能追加後の実行体hashとは扱わない。

## Unmap時のキー解放の再確認（1347）

2026-11-23、Linux側で追加されたトップレベルのUnmap時のキー解放を含む現在のWindows通常ビルドで、
`python tests/scripts/verify-windows-tk-state.py --output docs/measurements/2026-11-23-windows-tk-state-unmap.json`
を実行し、23段階すべて成功した。[結果JSON](measurements/2026-11-23-windows-tk-state-unmap.json)。
held段階のキー保持は-1、minimized段階で0へ変わり、最小化状態は-1、復帰後は0となった。
close/reopen、TCL-STOP/restart、nativeとの切替え、保存アプリの新規起動も成功した。
操作は既存スクリプトのTclによる合成操作である。実行体SHA-256は
`50afff149fa50a626867bc72b7d54aac2d058d139ac0edb0a23408f765af52f4`。
通常ビルドと`zig build test`も成功した。1347のWindows回帰確認を完了とする。

# CHIP-8 Windows/Linux受け入れ：レビュー評価（2026-11-20）

[計画レビュー](1165-1166-plan-claude-review.md)、[修正後レビュー](1165-1166-final-claude-review.md)。どちらもRead/Glob/Grepだけで、実行していない。最終のコード指摘はHigh/Mediumなし。

| 指摘 | 判断と対応 |
| --- | --- |
| H1 warmup出力の残存 | 採用。毎回RESET/初期queue後、OUT65536byteをA5で埋め、先頭/末尾と初期24状態を計時外で確認。期待PCMにA5がないことも検査。全計時の全PCM/終了状態を独立Pythonと比較 |
| H2 queue消費と状態値 | 採用。semantic22値に加えCOUNT/INDEXも別に照合。denseのcompaction後の件数をPython側で計算し一致を確認。code0/stderr空/DEPTH0も全件必須 |
| H3 CPU時間の粗さ | wallを主指標、CPUは参考値と明記。Windows実装はGetProcessTimesをμsへ変換、Linuxはgetrusage。観測deltaのgcdを保存するが校正した分解能とは呼ばない。CPU比による性能判断をしない |
| M1 denseの生成コスト | パターン生成/所有コピー/queue回収/描画込みと明記。model単独コストとの差引き推定はしない |
| M2 端数frame/有効率/予定 | 残り2frameも描画。128変更列は予定API、即時APIは機能試験側。timer有効frame数/割合も記録。pendingが少ないcompactionを大容量回収のworst caseとは扱わない |
| M3 warmup/順序/外れ値 | 全負荷を一度warmupしRESETしてから計時、7回のfresh processの順序を回転。中央値、全raw値、外れ値を除外しない方針を明記 |
| M4 計測前の利用者確認 | 最終レビューが示したClaude引継ぎの実ファイルを読んで、レモンの事前確認指示を確認した。今回の事前確認なしの数値は信頼性の低い参考値として保存し、正式採否には使わない。スクリプトを用意した状態で、確認後の再測定を待つ |

最終Lowの回転順は7回に対し6負荷なので1位置が重複することを制限として残す。所有コピーは測定コードだけで保証せず、1164の独立検査（元buffer書換え/512pending pattern回収）を根拠にする。CPU gcdの0は数学的には値を変えないが、名前は校正を意味しない。ソースSHAはロクが全件を現在のファイルと照合した。

Windows/Linuxのclassicはtimer60で約1秒鳴り、合計192block（約2秒）の後半は無音になることをレモンが確認。XOはpitch247→199を各192block聞き、1オクターブ低くなることを確認。連続XOには2秒ごとの正timer再設定を600件用意し、位相を保ってCtrl+C待ちを続けた。物理Ctrl+C後の停止、CATCH=-28/handle=0、約3秒の再再生とREPLAY-OKを両OSで確認した。Linuxの最初の未確認実行は破棄せず保全し、再テストへのＯＫだけを採用。

[サイズ・参考速度・実聴記録](../measurements/2026-11-20-chip8-os-acceptance.json)。1165/1166は正式再測定を残して未完了。Mac1167は別タスクで未完了。

最終追記：レモンに他アプリを止める機会を設けて開始確認を取り、ＯＫの後に正式再測定を実行した。全検証に成功し、参考値を残したままreportsへ正式値を保存。実聴/サイズ/測定/採否の記録が揃い1165/1166を完了した。Mac1167は未完了。技術的な測定スクリプトは最終レビュー後に変更していない。

# tque 1397：Windowsでの追加題材の実機確認

2026-11-26、Windows 11 Pro 26300、AMD Ryzen 7 7700、電源プラン「バランス」、Zig 0.17.1、main `333f8af`（作業ツリーに1402・1403の未コミットの変更。製品のsrc/・build.zigの変更はない）。時間の測定はレモンの指示（2026-11-26「時間測定は、いつ開始してもよい」）で行った。他のアプリは止めていない。[英語版](TASK_CONTROL_IMPL_1397.md)も参照。

## 1. 滞留とSnapshot（1396）

`run-acceptance.py --mode measure --only workloads snapshot`、計画v7（SHA-256 `9d1546a7…b467b`）を独立2回。証拠は `.work/acceptance/20261125T222653Z-9e889cf3`（run1）と `20261125T232847Z-738a482e`（run2）。

| 指標 | run1の最大 | run2の最大 | 目安 |
|---|---:|---:|---:|
| G1 enqueued→acquired（3場面） | 0.121 ms | 0.033 ms | 50 ms |
| G2 enqueued→acquired | 0.018 ms | 0.076 ms | 100 ms |
| T1 enqueued→acquired | 0.060 ms | 0.029 ms | 100 ms |
| I1 enqueued→acquired | 25.7 ms | 23.2 ms | 200 ms |
| Snapshot取得（snapshot_main_ns、300回） | 13.29 ms | 13.15 ms | 50 ms（D07は100 ms） |

滞留とSnapshotは両runとも目安内。ほかに、I1の公開→回収が100 msを超えた（run1は48,046件中5件・最大115.9 ms、run2は48,021件中1件・最大102.1 ms）。I1の`queue_waiting`は最大4（上限4）、Snapshotの大きさは3,620,330 bytes（上限4 MiBの80%超）で、どちらも80%規則で追加の試行の対象になった。

## 2. 複合待機と公平性（1395、AC-18・19・20）

`manual-acceptance-tty.py --cases mixed`（計測用ビルド `.work/1397/acceptance`）。AC-18（実供給元の複合待機）、AC-19・20（同じプロセスでT1・I1・ファイル読み・端末入出力が各区間で進む）がすべて成功。証拠は `.work/1397/mixed/results.json`。速さの目安は持たない。

## 3. ネイティブ画面と音（1394、AC-02・05・25、D07）

時刻を記録する実行（`SIGMA_ACCEPTANCE_SMOKE=0`）で、負荷あり（`.work/1397/native-load`）と基準（`--native-baseline`、`.work/1397/native-baseline`）を採り、計画v7で取り込んだ（経路 `.work/acceptance/20261126T011354Z-a741d948`、検索 `20261126T011355Z-69290fc2`）。

| 指標 | 経路（G1） | 検索（T1） | 目安 |
|---|---:|---:|---:|
| 入力→画面（backendの描画完了）の最大 | 13.15 ms（6件） | 15.32 ms（6件） | 33.34 ms |
| 入力→端末（writer完了）の最大 | 14.18 ms | 15.87 ms | 50 ms |
| 60 Hzのフレーム期限の超過（負荷あり） | 120中7 | 20中1 | 基準と比べる |
| 同（基準） | 31中0 | 5中0 | — |

入力→画面・入力→端末は目安内。フレーム期限の超過は、基準と負荷ありのフレーム数がそろわないため、計画の規則で比較できず**未確認**とする。確認方法：同じフレーム数・入力列で基準を採る手順をrunnerに加える（tque 1405）。終点はbackendの描画完了とwriter完了で、OS・compositor・パネルの発光は含まない。

目視と聴取（レモン、2026-11-26）：自動の実行は速すぎて読み取れなかったため、題材を別のコンソールで起動し、レモンがキーを押して確かめた。

- G1（`task-native-path.fs`）：nで要求を出すとRequestedが増え、Generationが追いつく。連続の要求でGenerationが減らない。fの後もGenerationと絵が前のまま残る。問題なし。
- T1（`task-native-search.fs`）：a・bで同じことを確かめ、問題なし。
- BYE（`task-native-bye.fs`）：レモンの返答は「OK」。Claudeはこれを、音が鳴り、qで止まり、窓が閉じた意味と受け取って記録した。Sigma（PID 37544）とconhost（PID 31448）の終了は、Claudeがプロセスの一覧で確認した。

計測用ビルドは管理の1巡ごとに`ACCEPTANCE`行を出すため、手で起動するとBYEの案内の行が流れて見えなかった。手で確かめるときの実行体と手順は tque 1404 で定める。

## 4. 判定

- 滞留・Snapshot・入力→画面・入力→端末：Windowsで目安内。
- AC-18・19・20：成功。AC-25（G1・T1の画面）とAC-05（音と窓を持ったままのBYE）：目視・聴取で確認。
- 未確認：フレーム期限の追加の超過（1405）。I1の公開→回収の100 ms超過は、受入れの要約で既存の扱いと合わせて記録する。

# 1394：タスクのネイティブ描画と資源の終了

[English](TASK_CONTROL_IMPL_1394.md)

2026-11-25、ロク。開始時はmain `8ad71bb`。実装とWindowsの機能確認を実施。本測定、窓の内容の目視、聴取、macOS・Linuxでの実行は未確認。commit・branch・tag・push・tque変更は行っていない。

最終確認時のHEADは、83832ffを経て1390の`47c169b`へ進んでいた。このセッションではGitの変更操作は行っていない。各ビルドとネイティブ実行のソース・実行体の証拠はそれぞれのログに保持し、開始時のHEADを最終HEADとは扱わない。

## 1. 範囲と所有

U1 / AC-02/05/25向けに、G1（256×256開放盤面）、T1（1MiB検索）の窓版と、音・窓・workerを保持してBYEする題材を追加した。指定されたbuild.zig、src/forth.zig、src/core/runtime_base.zig、tests/scripts/single-vm-ab.pyは編集していない（git diffで確認）。既存・並行作業の音および画面・音の文書の差分は保持した。tque show 1394は保存先lockへのAccess deniedで失敗。現行の題名・親・状態は未確認。保存先へアクセス可能な環境で照会のみを再実行する。

## 2. 題材と観測

`tests/task/task-native-common.fs`が描画とkind=5待機を共有する。`task-native-path.fs`と`task-native-search.fs`は既存workerと世代の鮮度判定を使う。窓内に採用した結果のGenerationと現在要求のRequestedを別々に描き、経路の頂点、検索件数・保存件数も表示する。n、a/bで差し替え、fで許可されたゼロ除算のworkerを失敗させ、qで終了する。失敗世代で以前の絵を置き換えない。描画を確認したフレームごとに`NATIVE-DRAW generation=… frame=… requested=…`を端末へ出す。連続入力では世代7まで確認し、途中の全要求が成功することを前提にしない。

`task-native-bye.fs`は440Hzの持続音と窓を保持する。busy workerの有限期限が切れたら更新し、qでは新しいworkerのRUNNINGを確認して直ちにBYEする。この時点で音・窓・task・Snapshotを保持し、題材自身では解放せずアプリの終了処理に任せる。RUNNINGの表明、終了コード0、端末復旧、所有プロセスの残存なしを観測した。実際に音が鳴って止まったことと窓が消えたことは、人の観察が必要であり、終了コードから推定しない。

手動ツールに`--native-paint --cases native`と、初回結果の取得後は投入を止めて同じ描画を続ける`--native-baseline`を追加した。既存のJob/sessionによる封じ込めと回収処理は変更していない。自己検査は成功（所有した子・孫の回収、外側のダミーの生存、起動失敗の保護）。POSIXでの安全性の実行確認はClaudeがmacOS/Linuxで行う。AC全体の判定は未確認を維持する。

## 3. 時刻の端点と集計

`src/host_paint_trace.zig`はtask-acceptanceだけで有効。固定長リングをロックで保護し、backendスレッドの記録を受け、所有スレッドがロック内でコピーして外で出力する。溢れは欠測として明示する。通常ビルドには時計呼出しも記録領域も残さない。3 backendのフレーム要求・完了番号と、`host_task_wait.zig`のkind=5登録・PAINTEDを記録する。macOSは子の時計を引き算せず、親がPAINTEDを処理した時刻を完了とする。

入力はホストがキーを最初に取得した時（先にpeekした場合はその時）を、その後の要求世代へ関連付ける。端末の終点はNATIVE-DRAW行がwriterから排出された時で、出力の滞留・エラー時は端点を残さず欠測にする。端末エミュレーターがピクセルへ描く時刻ではない。画面の終点は、その行に対応するフレームのbackend描画完了。物理キーの押下、OS入力待ち、compositorの提示、パネルの発光は含まない。本作業で扱うD07の終点は描画完了であり、物理提示の合格は主張しない。

runnerのpaint群は、単一プロセスの既存PAINTTRACEログを取り込むだけで、測定負荷を起動しない。smokeは時計0のまま、差分や統計を計算しない。measureの取込みには既存の承認情報と固定した計画のハッシュを必要とする。要求・完了、待ちの端点を照合し、入力→画面33.34ms・入力→端末50msの統計と超過数、各フレームの60Hz期限を残す。最初のフレームは窓を開くので定常周期の集計だけから除き、2番目の要求を基点に1/60秒の期限を算出する。後続のpainted-through番号から未描画フレームの完了を補完しない。欠測・重複・逆転・溢れを検出する。

タスクなしの基準は、ソース・ビルド・backend・表示周期・入力・描画負荷・フレーム数を揃え、基準自身が期限内である条件で追加超過を判断する。runnerは超過数の差と端点数の一致を参考として出すが、環境・負荷をClaudeが確認するまで比較可能とは判定しない。描く結果の形が違う場合も確認が必要。集計器は仮の時刻によって、端点の照合、smokeの除外、欠測・溢れ・不正な端点を検査した。実時間の測定ではない。

## 4. 計画の固定

回数・独立run・供給間隔・追加規則は変更していない。以下を期待値として固定する。測定直前に原本から期待値を作り直さない。

| Plan | SHA-256 |
|---|---|
| Windows/Linux v7 | `9d1546a7899f16f9630c982192c1151b2c7c0dcff66a99d3171f58fd7b1b467b` |
| macOS v5 | `8e65bf5ede134c3ca2c396618fe76b03efe6538e62e13cd0715c7c02e30c85b2` |

対象OSの固定値を--plan-sha256へ渡す。smoke取込みは時間測定の承認を必要としない。ネイティブの本測定は利用者が時間の測定を確認してからClaudeが行う。

## 5. 通常ビルドの.text

同じチェックアウトでReleaseFast / debug=false / strip=true / acceptance=falseを比較した。今回変更した追跡済みZigの6ファイルを一時的にHEADの内容（LFへ統一）へ戻して対照を作り、作業中のバイト列へ復元した。変更後もLFで、音の差分を含む他のファイルは両方で同じ状態を使った。branch・worktreeは作っていない。最初の事前ビルドと途中の不一致は履歴として保持し、最終比較の代わりにしていない。

PEの.text全体（ファイル上のpaddingを含む）が一致。論理サイズは両方1,532,806 B、ファイル上は両方1,532,928 B、SHA-256は`40a55252d6cc9f369ee041f7969f63188d96d73615854960f2f85f3aab61330e`。証拠は`.work/1394/text-comparison.json`、`normal-same-checkout-before/`、`normal-final3/`、`build-normalized-baseline.py`。コードのバイト列の比較であり、AC-29の性能受入れやtque 1390の作業ではない。

## 6. Windowsの検証

指定の7項目はすべて成功。testとdebug=falseのtestは各25/25ビルド工程、runtime-testは8/8、計測用ビルドは終了コード0、題材は17群、文書はfindings 0、変更したZigの書式検査も成功した。安全性の自己検査と仮の時刻による集計器の検査も成功。

最終確認の証拠は`.work/1394/`に保存。`accepted-test.log`（zig build test）、`accepted-plain.log`（test -Ddebug=false）、`accepted-runtime.log`（runtime-test）、`accepted-build.log`（-Dtask-acceptance=true、既存sigma.exeがロックされていたため専用prefix）、`accepted-examples.log`（verify-task-examples.py）、`accepted-docs.log`（check-docs.py）、`accepted-fmt.log`（変更したZigの7ファイル）。日本語の説明を照合した後、文書のソース指紋も更新した。公開語・バージョンの追加変更はない。

ネイティブConPTYの記録は`native-final/results.json`と各場面の生出力・イベント・process採取、基準の短い確認は`native-baseline-smoke/`。G1/T1は世代1、2、失敗3の後も2を保持、4、連続差し替えで7まで進み、強制回収なしで自然終了、終了コード0。最初の`native-tty-smoke/`は、ConPTYが行末空白を省いたため確認用パターンが時間切れになった。語の境界を使うように直し、失敗した実行は成功した実行と分けて保持。その後のヘッダー整理で一時的にworkerのINCLUDEDが抜けた失敗はnative-final-uiに保存した。復元後、native-finalで最終ソースを再確認して成功した。pipeの確認は補助で、端末受入れの代わりにはしない。集計器のsmoke取込みもrunner自身の.work/acceptance内に記録した。

## 7. 残る実機受入れ

ClaudeがmacOS・Linux/X11で、手順書のビルド・ネイティブ題材・基準・ツールの安全性自己検査・指定試験を再実行する。ローカルの表示可能なセッションで、窓内のGeneration/RequestedとNATIVE-DRAW、fの後の保持、BYEによる窓の閉鎖を目視し、音が鳴り止んだことを人が記録する。process/thread/audio/windowの生存期間と終了も採取し、macOSの子孫は間欠採取だけでなくfork/exit寿命を追う。端末ピクセル更新の計時は端末描画の観測端点を追加し、writer完了だけで達成としない。利用者の確認後、SIGMA_ACCEPTANCE_SMOKE=0で同条件の基準・負荷ログを採り、固定した計画のハッシュで取り込む。観測不足を保持し、終了コード0や統計だけでAC全体を合格にしない。今回、実時刻の目安との照合は行っていない。

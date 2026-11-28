# ForthSigma 作業引き継ぎ

## 再開時の要点（2026-11-28、版番号 0.13.1）

- 0.13.0はタグ`v0.13.0`（コミット`6fb2477`）でリリースした。CIのZigは0.17.1。インストーラーとmacOSパッケージは全部入りとFORTH 2012プロファイルの2種類を作る（Windowsは別製品として入り、PATHへ追加する。FORTH 2012の実行ファイル名は`sigma-forth2012`）。
- その後、Windowsのwishの探し方（カレントディレクトリを探さない）とワークフローのアクションの固定を直し、利用者指定で`VERSION`を0.13.1へ更新した。
- `examples/`はデモだけにし、試験用のスクリプトは`tests/integration/`・`tests/audio/`・`tests/task/`・`tests/scripts/`へ移した。アイコンは`assets/icon/`にある。
- 未着手：Windowsの速度の悪化と「定数・変数」カーネルの増加の調査（tque 1467）。

## 再開時の要点（2026-11-28、統合受け入れ 1057 完了・版番号 0.13.0）

- 613全体の統合受け入れ（1057）は **合格（2026-11-28、レモンの決定 A）**。結果は [結果台帳](INTEGRATION_ACCEPTANCE_1057_RESULTS.ja.md) の末尾（合格1,405・不合格0・未確認0・適用外539。補足の59セルと表外の事項はレモンの決定で確認不要）。tque の 1057・1415・1447 は完了。
- 利用者指定で`VERSION`を0.13.0へ更新し、表示例とCHANGELOG（0.13.0、2026-11-28）を合わせた。タグの作成・プッシュと配布物の作成は未実施。

## 再開時の要点（2026-11-26、タスク制御 1048 完了）

- タスク制御の受入れは **合格（2026-11-26、レモンの決定 案1）**。全ACの判定と根拠は [受入れの要約](TASK_CONTROL_ACCEPTANCE_SUMMARY.ja.md) の2節・3a節。tque の 1048・1054 と、その下の 1388〜1409 はすべて完了（1388 は実装せずに理由を記録して閉じた）。
- 各OSの記録：[1397](TASK_CONTROL_IMPL_1397.ja.md)・[1407](TASK_CONTROL_IMPL_1407.ja.md)（Windows）、[1398](TASK_CONTROL_IMPL_1398.ja.md)（Linux）、[1399](TASK_CONTROL_IMPL_1399.ja.md)（macOS）、[1391](TASK_CONTROL_IMPL_1391.ja.md)（単一VM）。途中で直したもの：[1401](TASK_CONTROL_IMPL_1401.ja.md)（埋め込むテキストの改行）、[1406](TASK_CONTROL_IMPL_1406.ja.md)（Linuxの描画の高速化）、[1408](TASK_CONTROL_IMPL_1408.ja.md)（投入時の入口の検査のキャッシュ）、1404・1405（手で確かめる手順、基準と負荷ありの組）。
- 計画は Windows/Linux v8（`377be53a…`）、macOS v6（`ae2fabd1…`）。60 Hzの期限は各フレームの要求→完了で判定する（レモンの決定 案1）。
- 測定の注意：Windowsの測定中に他の処理（PDBの解析など）を走らせると、I1の公開→回収が100 msを超えることがあった。他のアプリを止めて測り直すと最大72 msだった。
- 機械：Mac（192.168.12.16）はスリープでネットワークから外れることがある。Linux機には Xvfb と `kernel.perf_event_paranoid=2`（レモンが設定）がある。eslogger は Mac のターミナルにフルディスクアクセスが必要。

## 再開時の要点（2026-11-25、タスク制御 1054 の後続）

### 状態（2026-11-25 21時台に確認）

- main は `8ad71bb`（origin と一致）。Linux・Mac の作業ツリーも `8ad71bb`。
- 1382・1383（実機受入れ）は完了。受入れ全体の判定は「未確認（受入れ保留）」で、ACごと・OSごとの記録は [TASK_CONTROL_ACCEPTANCE_SUMMARY.ja.md](TASK_CONTROL_ACCEPTANCE_SUMMARY.ja.md)。未確認はすべて後続のタスクに結び付けてある。
- 完了したタスク：1395（複合待機の実供給元・同じプロセスでの公平性）、1396（滞留の端点。Snapshotの「投入可能」は `TASK-SNAPSHOT` がIDを返した時点＝決定A）、1400（extension=false の除外）。
- 実行中（この引き継ぎの時点）：
  - **1390**（単一VM A/A′/B の仕組み）：Linux の codex が Linux の作業ツリーで作業中。コミットさせない。終わったら `/tmp/fz-t1390-out.txt` を読み、Linux で `git add -N` してから差分を取り、レビューして Windows に取り込む。
  - **1394**（ネイティブ画面の題材と描画の時刻、音と窓を持ったままの終了）：Windows の codex が `D:/home/source/zig/forthz` で作業中。触らないファイルとして build.zig・forth.zig・runtime_base.zig・single-vm-ab.py を伝えてある。
- 未着手：1391〜1393（各OSの単一VM測定）、1397〜1399（各OSでの追加題材の実機確認）、1401（埋め込むライブラリの改行コードで実行ファイルが変わる件）。
- 作業ツリーで `src/host_audio.zig`・`docs/IMPLEMENTATION.md` が変更に見えるのは改行コードだけ（中身は HEAD と同じ）。コミットに含めない。

### 進め方（利用者の決定と方針）

- 各PCの codex・Claude Code を、効率がよい作業に使う（2026-11-25）。呼び方・キャッシュの設定・サンドボックスの制限は記憶 `remote-agents-on-test-machines` にある。ssh は PowerShell のものを使う（Git Bash の ssh は鍵が違い拒否される）。リモートの codex にはコミットさせない。
- 未確認は放置しない：「未確認とし、確認方法を提案する」。提案は tque に登録する（手順書にも明記）。
- 時間の測定は、実施の前に利用者へ時期を確認する。1396 の滞留の本測定、1391〜1393、1397〜1399 はこれに当たる。
- 手動の確認は `tests/scripts/manual-acceptance-tty.py`（ConPTY・pty で自動）。後始末は Job Object／専用のセッションだけに届く作り。過去に親PIDだけで判定して無関係の Brother のプロセスを止めたことがあるので、後始末に関わる変更は必ずレビューし、実行前後で外部のプロセスの生存を確かめる。
- macOS の手動の確認は、子孫のプロセスの行方を証明しきれないため「未確認」になる（確認方法：1399 のネイティブの fork・exit の追跡）。
- 通常のビルドの .text の比較は、同じ取り出しの中で行う。取り出しが違うと、埋め込むライブラリの改行コードで差が出る（1401）。

### 次にやること

1. 1390・1394 の結果をレビューし、3 OS で試験を通してコミット。tque を完了にする。
2. 計画（v7 / macOS v5 など）の固定ハッシュを確かめ、利用者に測定の時期を確認してから、1396 の滞留、1391〜1393、1397〜1399 を実施する。窓の目視と、音を聞く部分は利用者に頼む。Linux の画面の試験はデスクトップにログインした状態で、`DISPLAY=:0` と Xwayland の `XAUTHORITY`（`/run/user/1000/.mutter-Xwaylandauth.*`）を付ける。
3. 結果で [受入れの要約](TASK_CONTROL_ACCEPTANCE_SUMMARY.ja.md) を更新し、親の 1054・1048 の完了を判断する。
4. 1401 を進める。

## 再開時の要点（2026-11-24、タスク制御1382 実機受入れ。1382・1383 は 2026-11-25 に完了）

### 状態

- 1382（親1054→1048）はtodo。tqueは未更新。G1〜06-H（〜1381）は完了済みでmainにコミット・プッシュ済み（`6a1b387`）。
- 1382の変更28ファイルは、worktree `D:/tmp/forthz-1382`（HEAD `6a1b387`、detached）に**未コミット**で置いてある。この引き継ぎもその中にある。mainには入っていない。
- Linux機（`ssh fuk@192.168.12.12`、`/home/fuk/source/zig/ForthSigma`）は差分を外して`6a1b387`のまま、変更なし。測定時はpatchを当て、終わったら`git apply -R`で外す。
- 2026-11-24 21時台に開始した修正後の再測定は、利用者の指示で中断した。両機とも測定プロセスは残っていない。中断したrunは不完全なので使わない。

### 作業の進め方（利用者の決定）

- codexが実装・修正し、Claudeがレビューする。codexへの依頼は `codex exec -s workspace-write -C D:/tmp/forthz-1382` に引用符付きheredocのプロンプトで渡す。codexはgit操作をしない。gitとLinux機の操作はClaudeが行う。
- 試行回数は縮小案A：取消しは位相ごとに100回、ネイティブ処理5種×3位相、対話は10分×1回、メモリは3回。最大値が目安の80%を超えたら追加試行する（計画v3 §6）。
- 計画 `docs/TASK_CONTROL_ACCEPTANCE_PLAN.md` はv3で固定し、SHA-256は `7b341c1b6f6b12eeab2c6aa5bf31f24cde48c4e8bb555a89856744496dfc6032`。`.gitattributes`で`-text`にしてあり、Windows・Linuxで一致を確認済み。計画を変えたら、再レビューのうえで再固定する。
- 測定はWindowsの他アプリを止めた状態で行う。再開する時期は利用者に確認する。質問は1つずつ、平文で行う。

### 済んだこと

- 測定器（`-Dtask-acceptance`、既定off、通常ビルドからは除去）・題材・runner・英日の手順書を作成した。測定前レビューの11点はcodexが修正済み。
- 本測定（修正前のソース）をWindows・Linuxで完了した。結果は `.work/acceptance/20261124T103616Z-d293af93`・`20261124T114824Z-42f4b3be`（Windows）、`.work/acceptance-linux/20261124T104746Z-72d85108`・`20261124T115919Z-67af5f0d`（Linux）。分析は `docs/TASK_CONTROL_IMPL_1382.md` の10・11節。
  - 目安内：要求→停止（最大 Win 1.69ms／Linux 1.23ms）、要求→回収（72ms／1.46ms）、管理1巡（0.48ms／0.45ms）、入力→状態（0.59ms／0.29ms）、Snapshot取得、G2・I1の投入→公開、起動時間・サイズ。
  - 目安超過：T1投入→公開（全件、最大 Win 503ms／Linux 966ms、目安200ms）、対話の公開→回収（Win 11,796件・Linux 9,812件、最大約1秒、目安100ms）、LinuxのG1投入→公開（2,437件、最大165ms、目安100ms）、Windowsの待ち取消し1件（54ms、目安10ms）。
  - 80%超過で追加試行の対象：WinのG1（87.7ms）、回収測定の公開→回収（91.6ms）、Snapshotの大きさ3.6MB、queue_waiting=4。
  - 欠測：生成段階の位相の多く。ネイティブ処理のROLL・SEARCHは「測定できない」として打切り。
- 測定後の改善をcodexが実施した（12節）。**Claudeはまだレビューしていない。**
  - 題材は、公開の後の次のメイン巡で回収する形にした（ATICK/APACE、task-console.fsのTC-POLL）。測定区間は変えていない。
  - T1の検索は、SCAN/SKIP/COMPAREを64KiB以内の塊で使う形にした。正しさの試験を12件追加した。
  - 54msの件は、原因が確定しない。改善の対象外とし、再測定で確かめる。

### 次にやること（順に）

1. codexの12節の変更をClaudeがレビューする。主な差分は `tests/scripts/acceptance-fixtures.py`、`tests/task/task-search-worker.fs`、`tests/task/task-console.fs`、`tests/scripts/verify-task-examples.py`、`tests/scripts/diagnose-task-workloads.py`。指摘があればcodexが直す。そのあと、`zig build test`・`zig build runtime-test`・`verify-task-examples.py`・`check-docs.py` をClaudeが実行する。
2. 利用者に再開の時期を確認し、再測定を行う。コマンドは `docs/TASK_CONTROL_IMPL_1382.md` の12.4節にある。
   - 両OS：workloadsを独立に2回。
   - Windows：queuedを1000回。
   - Linux：G1・T1の診断。この値は判定に使わない。
   - Linuxへの差分は `git -C D:/tmp/forthz-1382 add -A -N . && git diff HEAD --binary -- . ':!.work' …` で作り、scpしてnohupで実行する。1つのOSにつき約2.5時間かかる。
3. 結果を目安と照合する。そのうえで、次の2点を利用者に1つずつ尋ねる。
   - 残る超過を、コードで直すか、目安を見直すか。
   - 欠測の位相とROLL・SEARCHを、未確認として残すか、計画を変えるか。
4. 手で確かめる項目（実際の端末・画面・キー入力・Ctrl+C）の手順を、利用者に1つずつ渡す。
5. mainへの取込み、Windows・Linuxでの試験、コミット・プッシュ（チェックポイントでは許可済み）、tqueで1382を完了にする。続いて1383（macOS、利用者のMacが必要）、1388（任意）、親の1054・1048へ進む。

## 再開時の要点（2026-11-23、1037）

- 1037は93%。Linuxの物理抜き差し1336・表示先選択1345、共通受け入れ1047は完了。残る実行環境はWindows。
- 1342をOS別の子へ分割。Linux1346は既存の23段階成功を移管してdone/auto100%。Windows1347はtodo/auto0%。親1342は未完了・auto50%。分割時の再実行はしていない。

| 次の対象 | 内容 | 進捗・実施方法 |
|---|---|---|
| 1347（親1342） | WindowsのTkキー解放の回帰確認 | 0%。Windowsで通常ビルド後、`python tests/scripts/verify-windows-tk-state.py --output <結果JSON>`の23段階を確認。Unmap処理後の最小化・キー解放・復帰・wish再起動・保存アプリが対象 |
| 1344（親1039） | WindowsのWINDOW-ON実機確認 | 50%。作成前の指定、表示中の移動、DPI差、全画面中の移動、対象画面の切断を実機確認。仕様は[詳細設計](CORE_EXTENSION_DETAILED_DESIGN.md)の1039節 |
| 1276（親1043） | Windowsのフレーム提示の実機確認 | 0%。最小化・閉じた直後・待ち中に閉じる場合、異なるHzの画面、DwmFlush未対応時を確認 |

Windowsの実機確認をLinuxの実行結果やクロスコンパイルだけで完了にしない。1347が済めば親1342・1042の完了条件を再照会し、1043の依存も確認する。

今回のLinux修正は、窓の移動通知より遅いRandR更新でWINDOW-CHANGESが増えない問題への対応。RandRとroot作業領域の通知を購読し、関係ないroot属性はキーリピート処理の前に捨てる。通常ビルド、追加回帰3件を含むホスト186成功・17skip（他はキャッシュ）、表示先38段階、合成通知、実際の抜き差しが成功。[修正とレビュー](reviews/1037-linux-randr-changes-review-response.md)。

物理試験の原記録1361サンプルはgzipで保存し、事後の操作者申告とSHA-256で結び付けた。見やすい要約は別ファイル。[最終実機記録](LINUX_DISPLAY_HOTPLUG_VALIDATION.md#最終実機確認完了)。コード・確認記録・この引き継ぎを同じコミットで管理する。

## Linuxの物理抜き差し完了（1336・1345・1047、2026-11-23）

- 最終の同じSigmaで、DP-3切断後の主画面移動と生存、画面不在中のclose/reopen、同じEDIDでの再接続、10秒の主画面維持、明示的WINDOW-ONでの副画面中央への移動が全て成功。320×200を維持し、変更回数は2→切断後4→再起動後6→再接続後8/14→明示移動20と更新された。
- 利用者の「nuita」「刺した」を事後の操作者申告として原JSONのSHA-256に結び付けた。原記録1361サンプルは不変のgzip、見やすい派生要約と確認JSONは別ファイル。[記録と手順](LINUX_DISPLAY_HOTPLUG_VALIDATION.md#最終実機確認完了)。原JSON自体の状態は書き換えていない。
- 1336・1345をdone/autoへ更新。共通受け入れ1333〜1336全件の完了を再照会し、親1047もdone。1037は93%。残る未完了の葉はWindowsの1344（表示先）、1347（Tkキー解放、親1342）、1276（フレーム提示）。
- RandR通知の修正、回帰3件、通常38段階、合成通知の検査、Claude Codeレビューの記録は以下の節と関連文書を参照。今回の修正・最終実機記録は本引き継ぎと同じコミットに含める。

## Linux実機切断でWINDOW-CHANGESの欠落を検出（1336・1345、2026-11-23）

- 実機でDRM disconnected/EDID消失と2→1画面、窓が主画面へ移って生存することを観測したが、WINDOW-CHANGESが2のままで失敗。[記録と経過](LINUX_DISPLAY_HOTPLUG_VALIDATION.md)。事前の意図的な失敗テストとは別の製品側の不具合。
- ConfigureNotifyより遅くRandRの一覧が更新される場合にキャッシュが取り残される。RandRの画面/CRTC/出力/リソース変更とrootの作業領域/デスクトップ変更を購読し、再照会と変更回数の更新を追加。回帰3件とホスト186成功・17skip、通常ビルド成功。他テストはキャッシュ。合成RandR通知で寸法不変のまま回数増加を確認し、通常の表示先選択38段階も成功。
- 修正後は300秒内に再切断が検出されずincompleteで終了。操作者の事後申告まで含む物理合格は未確定なので、1336・1345はまだ完了にしない。[レビューと修正確認](reviews/1037-linux-randr-changes-review-response.md)。

## Linuxの物理抜き差し記録の準備（1336・1345、2026-11-23）

- `verify-linux-display-hotplug.py`を追加。同じSigmaと独立X接続で矩形・作業領域・窓の位置/サイズを照合し、DRM statusとEDIDで切断・再接続を観測する。切断時の生存、対象画面がない間のclose/reopen、再接続後10秒間の主画面維持、明示的選択後の中央位置を記録する。[手順と制限](LINUX_DISPLAY_HOTPLUG_VALIDATION.md)。
- 事前確認、操作なしのincomplete、意図的なSigma無応答のfailと子回収、preflight/未完了/最適化モードでの確認拒否の6ケースが成功。記録機構へのClaude Codeレビューの中指摘6件と再レビューの3件を修正し、最終再確認は中程度以上の実バグなし。[対応](reviews/1037-linux-hotplug-review-response.md)。
- 物理切断は未検出。電源断等との区別には実操作後の操作者の明示的申告も必要。確認は元記録のSHA-256に結び付けた別ファイルに残し、元記録を書き換えない。1336は50%、1345は90%、1037は92%のまま。物理確認として完了にしない。次の実施では主画面を接続したまま、案内に従って副画面DP-3の映像ケーブルを抜き差しする。

## Claude CodeレビューとLinux追加確認（1037、2026-11-23）

- 利用者の指示でClaude Codeに3回の静的レビューを依頼し、期限、キャンセル、通常サイズの縮小、遷移中の連続指定、普通のWM復帰との区別、復元プロセスの指摘を修正。[対応とレビュー原文](reviews/1037-linux-window-on-review-response.md)。3回目は中以上の新規問題なし。その後の低指摘と、保留中のWINDOW-ONを加える実行検証で見つけた内部フラグの条件も修正した。
- 通常2画面で38段階、1倍＋2倍でも38段階が成功。WMの要求拒否と保留からの復旧、移動中のSHOWも確認。倍率変更後はRandRより作業領域の更新が遅れるため両方を待つ。[配置](LINUX_WINDOW_ON_VALIDATION.md)、[混在倍率・復元](LINUX_MIXED_SCALE_VALIDATION.md)。
- LinuxのDISPLAY-RECT等はXピクセル。混在時の主画面は物理2560×1440に対し5120×2880、DISPLAY-SCALEは0/0。HELP・英日ガイドと全語リファレンスを修正した。
- 最終実行体でTkの状態23・close17・未対応のフレーム契約6段階も再実行して成功。記録JSONはスクリプトの直接出力とし、後付けのcommit情報は付けない。
- tque再照会：1037は92%、1345は90%、1336は50%。1037全体は未完了。Linux1345・1336の物理切断・再接続、Windows1276・1344・1342が残る。通常ビルドとzig build test成功。

## Linuxの表示先選択（1345、2026-11-23）

- 現在の2画面でWINDOW-ONの起動前指定、表示中の移動、全画面中の移動と解除、-1と不正番号を確認する13段階が成功。[検証](LINUX_WINDOW_ON_VALIDATION.md)。画面構成は変更しない。
- 全画面解除後に左上へ寄る不具合を修正。通常時のサイズと枠の厚みで中央位置を計算し、全画面の入り直しで通常矩形を取り直さない。復元サイズは従来どおりWMに任せる。通常ビルド・zig build test成功。
- 1345は物理切断・再接続などを残して未完了。1336の倍率差・物理接続変更、Windows1276・1344・1342も残る。

## LinuxのTk追加確認（1337・1303・1342、2026-11-23）

- 通常ビルド後、状態通知23段階、close制御17段階、フレーム契約6段階をLinux x86_64/XWaylandで順番に実行して成功。[検証と結果](LINUX_TK_DISPLAY_VALIDATION.md)。本体の実装変更はない。
- 1337は完了。1267配下全件の完了を照合し、親1267も完了にした。
- 1303はWindows1300・macOS1304と同じ未対応の契約（Tkはフレーム0/0・待ちは偽、nativeの値を混ぜない）の実機確認として完了。Tk描画完了通知の実装完了ではない。1277配下全件を照合し、親1277も完了にした。
- 1342はLinux側が完了、Windows側を残して50%。1037全体は未完了。残りはWindows1276・1344・1342、Linux1345・1336。Linuxの表示先選択1345は現在の画面間でのWINDOW-ON確認と物理切断時の確認、1336は倍率差と物理接続変更が必要。

## GFX-RGBのmacOS確認（1294、2026-11-23）

- `zig build test`の「GFX-RGB draws colors of four bytes each from memory」がmacOSで成功。1001の背景試作を記録JSONの`sources`から`.work/1001/`へ取り出し（SHA-256一致）、`measure.py`を`--measure`なしで実行して照合が成功。6つの照合値はWindowsの記録と同じ。時間は測っていない。[記録](measurements/2026-11-23-background-prototype-macos.json)。
- 1294は完了。親1255は100%（完了の印は未）。このMacで進められる作業はほぼ済み。残りはLinux（1336、1303、1337、1345、1342）とWindows（1276、1344、1342）の機械が要る。

## 表示先選択 WINDOW-ON（1039、2026-11-23）

- 利用者が仕様を決定し、3つのOSとも書くよう指示。語は`WINDOW-ON ( i -- )`（-1は指定なし）。開く前なら次の`SHOW`でその画面、開いていれば作業領域の中央へすぐ移す。成功は返さず`WINDOW-DISPLAY`で確かめる。フルスクリーンなら解いて移して覆う。外された画面はシステムに任せ、戻っても移さない。詳細は設計文書の1039節。
- 新しい基本語`GFX-WINDOW-ON`（Builtinの最後）。古い保存アプリ・辞書イメージは作り直す。
- macOS（1343、完了）：実機で全場面を確認。フルスクリーンを抜けた直後はAppKitが元の枠へ戻すので0.4秒待ってから移す。
- Windows（1344）・Linux（1345）：コードを書き、クロスビルドとテストのコンパイルまで。実機確認が残る（各50%）。
- 作業中に`src/host_window_linux.zig`を誤って空にし、HEADから戻して変更を入れ直した（差分は+67行のみ）。
- 1039は66%。

## macOSの共通受け入れ（1335、2026-11-23）

- Linuxの共通確認を`tests/scripts/verify-macos-display-contract.py`へ移し、通常とgraphicsなしの実行体で6群（端末、Tkの対応表、エラー、表示先の切替え、保存アプリ、graphicsなし）が成功。[検証](MACOS_DISPLAY_CONTRACT_VALIDATION.md)。X11なしの群はmacOSに対応するビルドがないので除いた。
- 1335は完了。1047は75%（残り1336 Linuxの物理構成）、1037は80%。
- このMacで進められる表示支援はほぼ済み。残りはWindows・Linuxの機械が要るもの（1336、1342、1276、1303、1337）と、macOSでできる1294（GFX-RGBの背景試作の照合）。

## macOSのTk確認（1288・1299・1304・1338、2026-11-23）

- Windowsのスクリプトを`tests/scripts/verify-macos-tk-*.py`へ移し（プロセスグループで所有する`macos_display_test_support.py`）、Homebrewのwish（Tk 9.1.0）で状態23段階・close 17段階・フレーム6段階・表示領域9通り・補間を確認。[検証](MACOS_TK_DISPLAY_VALIDATION.md)、記録は`docs/measurements/2026-11-23-macos-tk-*.json`。Tclからの合成操作。
- 不具合修正：Aqua Tkは最小化で`<FocusOut>`を送らず`<Unmap>`だけなので、押されたキーが放されなかった。`sigma_tk.tcl`で`.`の`<Unmap>`でも`sigma_keys_released`を呼ぶ。WindowsとLinuxでの再実行は1342（1042の下）。
- macOSのTkの`WINDOW-PIXELS`・`WINDOW-IMAGE-RECT`は0（Aquaの`winfo id`はmacOSのウィンドウ番号でない）。
- 4件と1040・1270・1274は完了。1042は95%、1037は80%。

## macOSのWINDOW-FRAMES・WINDOW-PAINT-WAIT（1302、2026-11-23）

- 親が受け取られた画像を数え、子は新しい画像を描いたあと一度`INPUT PAINTED seq`を送る。`WINDOW-PAINT-WAIT`はLinuxと同じく読みながら待つ。`VSYNC-WAIT`は偽のまま（`CVDisplayLink`はmacOS 15で非推奨、子のdisplay linkでは待つたびにパイプ往復。理由は設計文書）。
- 実機（自動）：50回連続SHOW直後51 32→待って51 51、SHOW+待ちは約16.7 ms（60 Hz）、閉じたあとは偽。macOSは最小化中も描くので待ちは真（Linuxとの違いを英日ガイドに記載）。
- 1302は完了。1277は66%、1043は55%。macOSネイティブの個別タスクは一通り済み。残りはmacOSのTk（1288・1299・1304・1338）と共通受け入れ1335。

## macOSのWINDOW-KEEP-OPEN・WINDOW-CLOSE（1328、2026-11-23）

- AppKit子が「保留する」「保留した要求が未読」をatomicで持ち、`windowShouldClose:`で閉じるかを決めて`INPUT CLOSE-ASKED 1/0`を送る。親は`KEEP-OPEN 0/1`（起動時にも）と、`WINDOW-CLOSES`を読んだときの`CLOSES-SEEN`を送る。`WINDOW-CLOSE`は既存の`close`で数えない。
- 実機（利用者の操作）：保留・読む間は閉じない、`WINDOW-CLOSE`は数えない、読まない間は2回目で閉じる、保留なしは1回で閉じる。回数2→2→4→5。
- 1328は完了。1267は71%（残り1337 LinuxのTk、1338 macOSのTk）、1042は84%。

## macOSの状態4語（1297、2026-11-23）

- AppKit子が`INPUT STATE f m`（`isKeyWindow`・`isMiniaturized`）と、利用者が閉じたときだけ呼ばれる`windowShouldClose:`から`INPUT CLOSE-ASKED`を送る。親の`WindowSize`が開閉・キー入力・最小化・閉じた回数を持つ。閉じる要求の保留は1328。
- 実機：キー入力の出入り、閉じる・開き直し・再度閉じるで回数1→2を確認。最小化はステージマネージャーを切って確認（真・大きさそのまま・戻すと偽）。ステージマネージャー有効時は最小化ボタンでも最小化されず、macOSも`WINDOW-MINIMIZED?`も偽（ガイドに記載）。1266の最小化の記録はステージマネージャー中だったため設計文書で訂正。
- 1297は完了。1270は83%、1042は80%。次のおすすめは1328。

## macOSのWINDOW-SMOOTH（1320、2026-11-23）

- 親が`SMOOTH 0/1`で子へ送る（起動時にも）。子の`scaleImage`が、補間ありで倍率が整数でないときに`window_layout.smoothRows`（覆う部分の平均、Windows・Linuxと同じ）を使う。整数倍・メモリ不足は最も近い画素。単体テスト追加（host 173成功）。
- 実機：1画素の市松模様を縮めて、補間なしは縞・むら、ありは一様な灰色を利用者が目視確認。速度は測っていない。
- 1320・1290は完了。1040は95%（残りは1288 macOSのTkと1272の残り）。

## macOSのWINDOW-FIT・WINDOW-IMAGE-RECT（1286、2026-11-23）

- AppKit子の描画・マウス・IME候補位置の配置計算を`window_layout.placeFit`にそろえ、親が`FIT n`で子へ送る（起動時にも）。`WINDOW-IMAGE-RECT`は親が1266の大きさ・最後の`SHOW`の画像・`WINDOW-FIT`から計算。`host_window.fit_available`を追加。
- 実機：200×120を700×500で0/1/2の値がガイドの例どおり。見た目は利用者が目視（この端末はScreen Recording権限がなく、ウィンドウを撮影できない）。クリックは白い点で102 61、左上で1 0、余白で7 -12。
- 1286は完了。1040は92%、1274は80%（残り1288、macOSのTk）。`WINDOW-SMOOTH`のmacOS版は1320。

## macOSのWINDOW-PIXELS・WINDOW-CHANGES（1266、2026-11-23）

- AppKit子が内容ビューの大きさ（backing pixel）を`INPUT WINDOW w h c`で親へ送り、親の`WindowSize`が大きさと変化の回数を持つ。送るのは起動直後・リサイズ・backing scale変更・画面の移動・ディスプレイ構成の変更。macOSの`window_state_fn`は大きさと回数だけで、状態4語・`WINDOW-IMAGE-RECT`・`WINDOW-FRAMES`は偽/0のまま（1297・1286・1302）。`host_window.state_size_available`を追加。
- 実機：開く・`WINDOW-SIZE`・フルスクリーン・モード変更・外部1倍画面への移動（320 240）・枠ドラッグ・主画面へ戻す・最小化と復帰・閉じるボタンを確認。1つの変化が何回かに数えられることがある（モード変更で3〜5回）と英日ガイドに記載。詳細は設計文書。
- 1266・1041は完了。単体テスト追加（host 171成功）、Windows・Linux・x86 macOSのクロスビルド、graphics=falseのテスト、文書・単語リファレンスのチェック成功。
- 注意：クロスビルドは`zig-out/bin/sigma`を上書きする。実機確認の前にネイティブで`zig build`し直す。

## 描画のmacOSテスト記録と、追加しない決定（2026-11-23）

- 1308・1313・1317：macOS 27.2.1（arm64）、`592e5a3`でステージしたテスト実行体を直接実行し、コア1193成功・10skip、ホスト170成功・21skip、失敗0。CLIP!・アルファ・回転のテストはskipなし。親1279も完了。
- 1340（拡大コピーの補間）・1341（アルファ付きで描く語）・1330（縮小の平均方式）は、利用者がおすすめどおり「追加しない」と決定。代わりの方法（角度0の`COPY-ROTATED-RECT`＋`IMAGE-SMOOTH`、透明な画像に描いて`IMAGE-MODE` 5で重ねる、縮めた画像を前もって用意）を実行して確かめ、英日ガイドに追記。1309・1281・1283・1044・1045・1046も完了。1037はauto74%。
- 1038も完了。次の候補は1266（macOSの`WINDOW-PIXELS`/`WINDOW-CHANGES`）。

## macOSのディスプレイ情報の実機確認（1259、2026-11-23）

- 1259はdone。実装は`8968a66`〜`7e660b5`と、この節の画面IDの照合。値の詳細は[設計文書](CORE_EXTENSION_DETAILED_DESIGN.md)の「macOSの接続・配置変更の実機確認」、利用者向けには[英](GRAPHICS_AND_SOUND.md)・[日](GRAPHICS_AND_SOUND.ja.md)の`DISPLAY-`語の段落。
- 方法：ネイティブウィンドウを開いた1つのSigmaプロセスで`DISPLAYS`・`DISPLAY-RECT`・`DISPLAY-WORK`・`DISPLAY-SCALE`・`DISPLAY-HZ`・`DISPLAY-PRIMARY`・`WINDOW-DISPLAY`を1秒ごとに記録し、別プロセスのSwiftでCG（`CGGetOnlineDisplayList`・`CGDisplayBounds`・ミラー・モード）とNSScreen（`frame`・`visibleFrame`・`backingScaleFactor`）を1秒ごとに記録して照合。記録用スクリプトは一時ディレクトリに置いたもので、リポジトリには入れていない。
- 構成：内蔵（CG ID 1、2倍）＋左の外部JH-105TF（ID 3、1倍）。どの変更も次の1秒以内の`DISPLAYS`に反映され、全項目が基準と一致。
  - 非0の混在倍率の辺沿いオフセット：外部を-562 pt上へ→`DISPLAY-RECT` y=-1124（親2倍）。主画面を1倍にすると-562。
  - 解像度変更（1280×854、1600×1066）、実行中のbacking scale変更（外部960×640@2x、主画面1920×1200@1x。`CGConfigureDisplayWithDisplayMode`の`.forSession`で切替え、元へ戻した）。
  - ミラー：NSScreenと同じく1台と数える。抜き差し：抜くと1台（macOSが内蔵を1710×1112 ptへ変更）、挿し直すと同じID・添字で復帰。
  - ウィンドウのある外部を抜くとmacOSがウィンドウを移して`WINDOW-DISPLAY`=0、挿し直すと戻して1。抜いた直後約1秒はCGとNSScreenが食い違うが、Sigmaの記録に混ざった状態は出なかった。
- 画面IDの再利用：macOSは取り外したモニターのCG IDを別のモニターに与えうるため、保持する画面の名前をCG ID＋ベンダー・型番・シリアルのダイジェストにした（`displayKey`、プローブ子とAppKit子で共通）。別モニターなら`WINDOW-DISPLAY`は-1。単体テストと、同じモニターの抜き差しで一致し続けることを実機確認。別のモニターでの実機確認は手元にないためしていない。シリアルのない同型2台は見分けられない。
- `host_display_macos.zig`のテストが`zig build test`に入っていなかったので`main.zig`のテスト一覧へ追加。既存の配置・プロトコルのテストも実行され成功。
- 親1038はauto100%だが未完了のまま。macOSの共通受け入れ1335、Tkの状態語1299・close 1338は残る。
- 確認：`scripts/check-docs.py`指摘0、`scripts/word-reference.py --check`成功、`tests/scripts/test-word-reference.py`成功、`git diff --check`成功。`zig build test`（host 170成功・21skip）、`-Dgraphics=false`のテスト（1186成功・199skip）、x86_64-macosのクロスビルド、通常ビルドが成功。

## アルファ付きPNG保存（1339、2026-11-23）

- 利用者が追加を承認し、コミット・pushも指示した。SAVE-PNGはRGBのまま、SAVE-PNG-ALPHAとGFX-SAVE-PNG-ALPHAを追加。[仕様と検証](PNG_ALPHA_SAVE.md)。RGBA8の全画素、透明なRGBの保持、画面の不透明さ、clip/表示色数の非適用、CRC/zlib/ブロック境界、Sigma再読込みを通常・files除外の各5寸法で確認。通常テスト1373成功・25skip、graphics除外1201成功・193skip、文書チェック指摘0。[レビュー](reviews/2026-11-23-png-alpha-response.md)はHigh/Mediumなし。
- 1339はdone(auto100%)。1309はtodo・auto33%、1037はtodo・auto66%。1309は保存追加と残る判断を分割。1339が保存実装・検証、1340が拡大時のアルファ補間の要否、1341がアルファ付き描画語の要否。1309全体は未完了。新Builtinにより古い保存アプリ・辞書イメージは再作成する。
- 以下のWindows表示支援と速度・アルファ見た目の記録は、このRGBA保存追加前の実行体による検証。その時点のhashと範囲を保持し、今回の新しい実行体によるPNG保存の記録と混同しない。

## Windowsの表示支援を継続（2026-11-23、1295・1300・1306・1310・1314・1318・1326・1334）

- レモンからClaude Codeレビューと、できるだけ止めずに1037を進める指示。速度測定は確認不要と明示許可された。コミット・タグ・pushは依頼されていない。
- [Windows共通確認](WINDOWS_DISPLAY_CONTRACT_VALIDATION.md)をレビュー指摘に沿って9項目へ補強。Tkとnativeでサイズを変えて出どころを検査、倍率・小窓・working_treeを記録。プロセス回収を専用jobに集約し、KEYゲート、KILL_ON_JOB_CLOSE、成功時の子プロセス数0、期限付き読取りで検査する。
- [Tk追加検証](WINDOWS_TK_DISPLAY_VALIDATION.md)：1295の状態通知23段階、1326のclose保留17段階。共通実装でWINDOW-CLOSEはTk選択中ならTkをwithdrawし、KEEP-OPENは両backendへ設定。WINDOW-CLOSESだけが保留を確認済みにし、未確認の二度目は閉じる。TCL結果を上書きしない。Builtin追加で古い保存アプリ・辞書イメージは作り直す。
- 1300は現行Tcl通信に描画完了の通知がないため、未対応として明示。Tk選択中の公開フレーム語は0/0・偽を返し、native併用でもnativeの結果を流用しない。実際のTk描画完了の実装ではない。1318もTkのWINDOW-SMOOTH未対応を画素照合で記録。
- [速度測定](DRAWING_SPEED_VALIDATION.md)：クリップ有無の等しい仕事量、回転の3倍率×2補間を独立process・予備1回＋本測定7回で比較。全試行checksum一致。現在の経路間の測定であり、実装追加前との性能退行やゲーム全体の速度ではない。
- [アルファの煙・輪郭確認](ALPHA_VISUAL_VALIDATION.md)：Windows版Sigmaの合成結果614,400バイトを独立した期待値と照合し、生成PNGの煙の重なりと輪郭も確認した（1310）。画面への実提示とは区別する。
- Claude Codeの原文・採否は[レビュー対応](reviews/2026-11-23-windows-display-response.md)。作業中の追加レビューは途中のソースと旧JSONの不一致を指摘したため、その後の同じ最終実行体で検証と記録を作り直す。
- 最終状態：1295・1300・1306・1310・1314・1318・1326はdone(auto100%)。1334も9項目で再確認。1037はtodo・auto66%。通常1371成功・25skip、graphics除外1201成功・191skip、実辞書照合・例28件＋424件・文書チェック指摘0。最終の追加レビューはHigh/Mediumなし。
- Linux/macOSのTk close実行確認は1337・1338へ登録。1303・1304、Mac固有の既存タスク、物理画面の接続変更、未決の1309・1330と表示先選択1039は保持する。この節の変更もRGBA保存追加とまとめてコミット対象とした。

## 残件1303・1336の再確認（2026-11-23）

- この節はWindows継続前の調査記録。表示支援1037は全完了ではない。1303はTk描画完了の実装と実機受け入れ、1336は異なる倍率での実測と物理接続・切断が残る。1298の状態通知完了で、これらも完了したとは扱わない。
- `verify-linux-tk-frame-gap.py`で1303の未実装状態を再現。TkでSHOWを30回送り、Tclの`update idletasks`を呼んでも回数は0/0、待ちは偽。nativeを並行して開くと、Tkを選んでもnativeの1/1と待ちの真を返す。nativeを閉じるとTkは開いたまま待ちは偽に戻る。このスクリプトは未実装の調査用であり、Tkの受け入れ成功ではない。実装時に期待値を置き換える。[記録](measurements/2026-11-23-linux-tk-frame-gap.json)。
- 1336の事前調査：Mutterの現在の2画面はともに倍率1。副画面を倍率2にする構成を`ApplyMonitorsConfig`のmethod 0（verifyのみ）で検証できた。画面構成は変更していない。`inspect-linux-monitor-config.py --verify-secondary-scale 2`で再現できる。layout-mode 1はlogicalであり、副画面の幅が1920から960になる候補では主画面のxも1920から960にして隣接させる。[記録](measurements/2026-11-23-linux-monitor-preflight.json)。
- 以後の実測では、元構成の保存・検証と、親プロセス停止時にも動く独立した復元処理を先に用意してから一時構成を適用する。ソフトウェアでの無効化は物理ケーブルの抜き差しとは別の確認として記録する。今回のverifyだけで倍率差・切断を受け入れ済みとはしない。

- [Opus 5.5レビュー対応](reviews/2026-11-23-linux-remaining-response.md)。今回の調査は実装完了の承認ではない。

## Tkの状態通知をLinuxで先行（1298、2026-11-23）

- Windows1295の実機確認待ちで止めず、Tkの共通実装をLinuxで先行。公開の4語はTk選択中はTk、それ以外はnativeを問い合わせる。聞くだけではwishを起動しない。
- closeは従来のwithdrawのまま。絶対回数のW制御と内部状態応答は固定バッファで、ヒープ枯渇・partial SAVE/復元・利用者のTCL結果の寿命を検証。受信済み回数はstop/restartをまたぎ、新しいStateと保存アプリでは0。stopは通常の入力を取り込まず上限内のWだけ記録し、cleanup失敗は次回再試行する。
- XWaylandでTkの最小化キャッシュが更新されないことを実機で再現し、X11入りでは祖先WM_STATEを優先する受け口を追加。取得不能ならTkの値。毎回のX接続には全体2秒・祖先32段の上限がある。
- `verify-linux-tk-state.py`は23段階と実際のSAVESYS初期化が成功。通常イベントキュー満杯、IME用focus、最小化・復帰、フルスクリーンclose/reopen、backend切替えを含む。合成の操作で、物理ボタン・実際のIME変換は未確認。
- WINDOW-CLOSE/KEEP-OPEN、CHANGES、FRAMES/PAINT-WAITはnativeのまま。Windows1295とmacOS1299の実機確認、Tkのclose制御1326とフレーム1303は残す。内部Builtin追加で古い保存イメージは作り直す。
- 最終確認：通常・X11なし・graphicsなしの回帰テスト成功（25/25・24/24・22/22ステップ）、文書チェック指摘0。GUIは通常構成で23段階を実機確認。Windows x86_64 GNU・macOS arm64のクロスビルド成功は、実行確認とは区別する。
- [検証記録](measurements/2026-11-23-linux-tk-state.json)、[レビュー対応](reviews/2026-11-23-tk-state-response.md)。この節の変更は未コミット。

## 表示支援のLinux共通受け入れ（1333、2026-11-23）

- 1047のLinuxで実行できる共通条件を1333に分け、通常・X11なし・graphicsなしの3実行体で確認した。`verify-linux-display-contract.py`は対応表・エラー・バックエンド切替え・実際のSAVESYS新規起動・graphics除外の正負の対照を含む10群。子プロセスとwishは所有するプロセスグループで終了回収する。
- `graphics_test.zig`に、実行中復元で現在のfit/smooth/keep-open・表示一覧を保持して画像・クリップを消し、ホストの問合せ・設定・閉じるコールバックを呼ばないテストを追加。新しいStateでは`restoreFreshImage`を使い、実行時設定が画像から持ち越されず、辞書のライブラリ変数だけ保存値となることを確認。
- 実機の2画面間の移動も`verify-linux-monitor-moves.py`で確認。主画面基準のDISPLAY-RECTとXルート座標の原点差（現在はx方向1920）を照合して、所有ウィンドウだけを移動した。所属画面、サイズ維持、変更回数の増加が一致。構成・倍率・リフレッシュレートは変更していない。
- 1047全体は残す。共通受け入れのWindows1334、macOS1335、Linuxの物理倍率差・接続変更1336を追加した。表示先選択1039、Tkの状態通知とフレーム提示、macOSの個別実装も既存タスクを保持。
- 通常・graphicsなし・X11なしの`zig build test`が成功（25/25・22/22・24/24ステップ。サブテスト数はキャッシュの有無で異なる）。Opus 5.5レビューの初回指摘は再確認で解消、追加の期限・終了出力の2件も修正して再実行。
- [検証記録](measurements/2026-11-23-linux-display-contract.json)、[レビュー対応](reviews/2026-11-23-linux-display-contract-response.md)。この節の変更は`d63b1cd`にコミット済み。

## Linuxの描画完了待ち修正とOpus 5.5レビュー（2026-11-23）

- 1332完了：最小化中に描画した画像を完了数に反映しないまま復帰すると、Mutter/XWaylandからMapNotifyやExposeが来ず待機がタイムアウトする場合を修正。公開状態の最小化→通常の変化と、描画側の`paint_deferred`の両方で再描画を要求する。再作成時は保留をリセットする。
- 実機の`verify-linux-window-restore.py`で、初回描画を明示的に待つ／待たない2ケース、最小化中の2枚目の保留、復帰後2/2、待機中の閉じる要求で偽になることを確認。初回描画前の最小化を保証するテストではない。公開前に復帰する経路はXサーバー不要の単体テストを追加。
- レビューは利用者指定のClaude Code **Opus 5.5**。80aa871と1332初稿を別々に読み取り専用で依頼し、指摘対応後に再確認。「修正が必要な具体的なバグは残っていません」。残るテストの0.5秒待ちと倍率1の条件は制限として記録。[原文](reviews/2026-11-23-linux-window-opus55.md)。
- Tk側も補強：GetWindowAttributesでピックスマップIDを拒否、整数倍率と中央配置の独立した期待値、専用toplevelをdestroy/updateした後の照合。XWaylandの単位はXサーバーピクセルで物理ピクセルと異なる場合があると英日文書・全語リファレンスに明記。毎回の接続と最大待ち時間も明記した。接続キャッシュと性能測定は行っていない。
- 最終確認：`zig build`成功、`zig build test`は25/25ステップ成功（ホスト182成功・17 skip、新規の公開前復帰テストを含む。coreはキャッシュ）、`check-docs.py`は指摘0件。最終ビルドで2本の実機スクリプトも成功。
- [復帰確認の記録](measurements/2026-11-23-linux-window-restore.json)、[Tkの追試を含む記録](measurements/2026-11-23-linux-window-acceptance.json)。この節の実装・レビュー記録は`8b3160f`にコミット済み。

## Linux実機の表示支援の確認（2026-11-23）

- Ubuntu実機、Linux 7.0.0-43-generic / x86_64、Wayland / MutterのXWayland `:0`、Zig 0.17.1。基準は`23b00de`。この節の実装・検証記録は`80aa871`にコミット済み。速度は測っていない。
- 1331完了：ICCCMの`WM_CHANGE_STATE`（IconicState）と`_NET_ACTIVE_WINDOW`で最小化・復帰を要求し、`WINDOW-MINIMIZED?`が0→-1→0、`WINDOW-OPEN?`が-1のままであることを確認。物理ボタン操作は試していない。
- 1287完了：Tkの`WINDOW-PIXELS`と`WINDOW-IMAGE-RECT`が0だったため、Linuxの`window_size_fn`にXの`GetGeometry`を実装。別接続で2秒以内、無効ID・破棄後は0 0。`verify-linux-tk-window.py`で3サイズ×3設定の9件、SHOW前、withdraw時、無効IDと破棄後を確認。Tkの整数倍配置は`WINDOW-FIT`によらず同じ。物理ディスプレイ倍率とMOUSEは未確認。
- 通常ビルド成功。変更前の`zig build test`は1357成功・27 skip。変更後も25/25ステップ成功（ホスト181成功・17 skip、coreはキャッシュ）。`-Dx11=false`のビルドも12/12成功。
- 残件1332を追加：ネイティブウィンドウの最小化・復帰の確認で、`WINDOW-FRAMES`が1 0のまま、`2000 WINDOW-PAINT-WAIT`が偽だった。遮蔽などの環境条件か実装の問題かは未判定。この実行をフレーム待機の受け入れ成功とはしない。
- [結果・再現用ソース](measurements/2026-11-23-linux-window-acceptance.json)。Tkの再実行は`python3 tests/scripts/verify-linux-tk-window.py`。状態通知1298とフレーム提示1303はTkの先行実装待ちで未完了を維持。

## 標準の音と機種の突き合わせ、既定FPATHの確認、配布スクリプトの手直し（2026-11-22）

### 状態

- この節は`2546d43`の次のコミットに入る。その前の2つ（`24415dd` `9582bcb`）と`2546d43`が、この日の1239の作業である。
- コミットとプッシュは、レモンの指示があったときだけ行う（2026-11-21からの決まり）。
- `zig build test`は1243の修正（`src/main.zig`）のあとに成功した。そのあと変えたのはスクリプトと文書だけ。`word-reference.py --check`と`check-docs.py`（指摘0件）は、この節を書く直前に成功を確認した。
- レモンは当面、版番号を上げない。`VERSION`は変えていない。

### この日に終わったこと

- 1239（標準の音が各機種の機能を満たすかの突き合わせ）：結果と扱いは[SOUND_CORE_DESIGN_STUDY.md](SOUND_CORE_DESIGN_STUDY.md)の11節、決定は[DECISIONS.md](DECISIONS.md)の「標準の音と機種の突き合わせ（1239）」の行。
  - A：`VOICE-HOLD`で、鳴っている声に同じ音色を指定すると、エンベロープを続けたまま音色の今の設定を取り込む（鳴っている途中のパルス幅・フィルター・波形の変更）。
  - B：波形の組合せは標準の音に含めず、`WAVETABLE`で鳴らす。圧縮形式の展開は1188で扱う。
  - C：`MASTER-FILTER ( mode hz stage -- )`を2段の直列にし、1極（11、13）を足した。スタック効果が変わった。
  - D：PSGの共有のエンベロープ・ノイズと、1 msより短いエンベロープは、満たさない点として残す。
  - E：声ごとの左右は`VOICE-PAN ( left right voice -- )`。音色ごとの左右は`INSTRUMENT-PAN ( left right -- )`に改名した。`AMIGA-SOUND`が声1〜4を左・右・右・左に置く。
  - F：`FILTER`のモード5〜7、`MIXER 1`の声5（DMC）、ライブラリの`NES-SHORT-NOISE` `NES-DMC` `C64-FILTER` `STE-SOUND` `STE-STEPS` `STE-LEFT` `STE-RIGHT`、Amigaの周期の下限123。
  - 実聴のケース33〜40を`tests/scripts/listen-standard-sound.py`に足し、新旧の比較をやり直した（[測定](measurements/2026-11-22-chip-libraries-compare.json)）。
- 1194（既定の`FPATH`の各OS確認）をOSごとのタスクに分けた。結果は[SOUND_CORE_DESIGN_STUDY.md](SOUND_CORE_DESIGN_STUDY.md)の4節。
  - Windows（1244）は完了：絶対パス・ジャンクション・UNC共有からの起動、レモンが作ったZIPとインストーラー（インストール先の確認を含む）。
  - 1243：Windowsで実行ファイルへのシンボリックリンクから起動したときも、リンク先の隣の`include`を使うようにした（`src/main.zig`の`windowsLinkTarget`）。
  - Linux（1245）：WSLでの6通りの起動（1249）と、レモンがWSLで作ったZIP（1251）は完了。実機（1250）も完了：Ubuntu 26.04.1 LTS（カーネル7.0.0-43-generic、x86_64）で`build-zip.sh`のZIPを展開し、`verify-default-fpath.sh`の6通りがすべてPASS（[測定記録](measurements/2026-11-22-linux-zip-acceptance.json)、ZIPとログは`.work/1250-linux/`）。これで1194は3つのOSとも完了。
  - macOS（1246）：実機で完了（macOS 27.2.1 / arm64 / Zig 0.17.1）。`zig build`、`zig build test`（1321成功・31 skip）、6通りの起動とライブラリ読込みが成功。証跡は`.work/1252-macos/`。相対パス計算でmacOSの一時ディレクトリのsymlinkを考慮していなかったため、確認スクリプトを修正した。
  - macOS配布物（1253）：通常版・浮動小数点なし版のZIPを作成し、各ZIPに22ライブラリが含まれることを確認。展開後の両実行ファイルで別フォルダーから起動する6通りすべてと、2ライブラリの読込みが成功。詳細・SHA256は[測定記録](measurements/2026-11-22-macos-zip-acceptance.json)、ZIPと実行ログは`.work/1253-macos/`。
  - Linuxの実機とMacで実行する確認用のスクリプトは`tests/scripts/verify-default-fpath.sh`（`sigma`の場所を渡す）。
- 配布スクリプト：
  - `build-zip.ps1` `build-installer.ps1` `build-zip.sh`から版番号の引数を外した。配布物の名前は常に`VERSION`の値になる。
  - 2026-11-22の利用者指示で、CIとWindows/Linux/macOSのZIPを「全部入り」と「FORTH 2012プロファイル」の2種類に変更した。プロファイルは浮動小数点などの標準ワードセットを残し、graphics/audio/extensionを無効化する。ZIPには`-forth2012`を付け、Sigma固有`include/`と`examples/`は全部入りだけに含める。macOS 27.2.1 / arm64 / Zig 0.17.1で4構成の`zig build test`（全部入り1321/1352成功・31 skip、floatなし1240/1311・71 skip、新プロファイル1100/1334・234 skip、追加縮小構成792/1305・513 skip）が成功した。Mac向け両ZIPも生成し、展開後の算術実行と機能群の有効・無効を確認した。Windows x86_64、Linux x86_64/arm64も両プロファイルをクロスビルドできた。Linux arm32はZig 0.17.1で64-bit atomicエラーとなることを確認し、利用者指示でCIとZIP対象から外した。成果物は`.work/profile-validation/`。GitHub Actionsの実行とWindows/LinuxのZIP生成は未確認。インストーラーとmacOS個別PKGの`-nofloat`選択は対象外。
  - `.gitattributes`を作り、`*.sh`は常にLFで取り出す（WSLから`#!`で起動できなかったため）。
  - `build-release.sh`は、WSLでリポジトリがWindowsのフォルダーにあるとき、Zigのキャッシュを`~/.cache/forth-sigma/zig-cache`に置く（`.zig-cache`の中の名前変更が`AccessDenied`になるため）。
  - レモンのWSLにZig 0.17.1を入れた（`~/.local/zig-0.17.1`、`~/.local/bin/zig`からのリンク。Ubuntuの0.14.1は`/usr/bin/zig`に残した）。
- SNESの受け入れの確認手順を[SNES_DSP_AUDIO_FORTH.md](SNES_DSP_AUDIO_FORTH.md)の最後の節に書いた。実聴とCtrl+Cの確認は`tests/scripts/accept-snes-dsp-audio.py`（引数なし、`--play`、`--interrupt`）にまとめた。

### 未確認・残り

- 実聴（2026-11-22、Linux実機）：1240（ケース33・34）と1241（ケース28・36〜38・40）は、レモンが「説明どおり」と確認して完了。1242はケース35・39と`fur-elise`・`pastoral`・`music`に加え、`shmup-amiga`の曲（ゲームを起動せず曲だけ約13秒）もレモンが「OK」と確認して完了。1237は`music`・`fur-elise`・`pastoral`が「問題なし」、`hopper`・`shmup`・`shmup-c64`・`shmup-amiga`の曲（ゲームを起動せず曲だけ約13秒ずつ）が「OK」。`try/`のmario（BGMと効果音の停止）は、レモンが1237の対象外と決めたので（2026-11-22）、1237は`examples/`の7本で完了。marioの音の実聴はマリオ移植の側（958など）に残る。ゲームの中の効果音は聞いていない。[記録](measurements/2026-11-22-listening-linux.json)。
- 新旧の比較で、NESの三角波のゼロ交差から求めた周波数が220.2 Hzから281.8 Hzになった。足したのは直線のフィルターだけなので測り方の値と推測しているが、波形は見ていない。ケース25でベースの音程を聞けば確かめられる。
- `accept-snes-dsp-audio.py`のMac `--play`と`--interrupt`は、サンドボックス外の実機出力経路で実行済み。Windows/Linuxでの同スクリプトの聴取確認は未実施。
- 1238（音を出さずに声部のMMLの設定を初期値へ戻す語）：`PLAY-RESET ( -- )`を足して完了した（`3d34d8c`の次のコミット）。音楽を止めて8声のMMLの設定を起動時の値に戻し、効果音とモジュールは止めない。基本語は`SND-GLOBAL`のキー10。音は聞いていない（鳴らない語なので、聞くものはない）。
- 1177（SNESのMacでの受け入れ）：2026-11-22完了。macOS 27.2.1 / arm64 / Zig 0.17.1。4構成ビルド、16構成照合、6負荷のForth/native照合、実機出力の左右再生、Ctrl+C停止・再再生、6負荷×7回のnative計測が成功。利用者が最終再生の出音を確認した（「でた」）。隔離実行では出力デバイスが隠れて無音だったため、実機音声試験はサンドボックス外でやり直した。`src/host_audio.zig`も既定出力なしで`AUDIO?`が真になる誤検知を修正。最小実時間比28.04倍。結果は[SNES_DSP_AUDIO_FORTH.md](SNES_DSP_AUDIO_FORTH.md)、測定・実機ログは`docs/measurements/2026-11-22-snes-dsp-macos-{timing,acceptance}.json`と`2026-11-22-snes-dsp-macos-final-play.json`。
- 1205（標準の音のMac実機再生と16声負荷）：macOS 27.2.1 / arm64。標準音21ケースを実機出力で順に再生し、レモンが「問題なし」と確認。無音モードの21ケースもすべて終了コード0・stderrなし。16声負荷はエンジン単体を各480,000 frame・7回計時し、square16 129.5倍、full16 50.9倍、table16 105.8倍のリアルタイム比。全ケース16声が発音中、非無音・非クリップ。tque #1205完了。測定・再生記録は[負荷JSON](measurements/2026-11-22-standard-sound-load-macos.json)と[ケース記録](measurements/2026-11-22-standard-sound-listen-macos.json)。
- Pythonのスクリプトも常にLFで取り出すようにした（利用者の決定、2026-11-22。`.gitattributes`に`*.py text eol=lf`）。この作業フォルダーでCRLFか混在だった139本をLFに直した。リポジトリの中身は変わらない。WSLから`#!`で直接起動できることを、`tests/scripts/verify-debug-outputs.py --help`で確かめた。
- 1188（`SNES-FRAMES`の置き換え）：2026-11-22、**`SNES-FRAMES`を本体に残す**とレモンが決めて完了。Linux実機でForthのSNESモデルの内訳を測り、フレームを作る語を書き直して2〜3.7倍速くした（結果は全検査で同じ。8声が実時間の1.4〜1.5倍、最大音程の負荷は0.74倍。`SNES-FRAMES`を使うと11〜16倍）。細かい3部品（展開・補間・FIR）を本体に足しても、見積もりでは8声が約2倍、最大音程が0.9〜1.0倍どまりなので、置き換えは取りやめた。部品は作っていない（見積もりだけ）。詳細は[SOUND_CORE_DESIGN_STUDY.md](SOUND_CORE_DESIGN_STUDY.md)の12節。足したスクリプトは`tests/scripts/profile-snes-dsp-audio.py`。Windows・Macでは、書き直したモデルの検査をまだ実行していない（未確認）。
  - `zig build test`で`host_resize`の試験（SIGWINCHの設定を戻す確認）が1回失敗し、続く2回は成功した。Zigのソースは変えていない。`sigaction`のマスクを128バイト丸ごと比べていたためで、2026-11-22にWSLで3回続けて失敗したときの出力で、違いが105バイト目以降（カーネルが持たない部分。Cライブラリがメモリにあった値を残す）だけにあることを確かめた。Linuxではカーネルが持つ8バイトだけを比べるようにテストを直し、WSLで3回続けて成功した。
- 1182（Apple IIのMac受け入れ）：2026-11-22完了。macOS 27.2.1 / arm64 / Apple M5 / Zig 0.17.1。ReleaseFastの4構成で独立照合20群が成功して結果一致、再生ラッパー19件は音声ありの3構成で成功。6負荷×7回の計測は実時間比77.66倍（スピーカー）〜7.49倍（カードへ8 kHzでバス書込み）。実機再生とCtrl+C後の停止・再生を利用者が「問題なし」と確認。アンダーラン0、ハンドル0、プロセスの残りなし。[結果と測定記録](measurements/2026-11-22-apple2-audio-macos-acceptance.json)。作業ログは`.work/1182-macos/`。
- 1180（Apple IIのWindows受け入れ）：2026-11-22完了。Windows 11 Pro 10.0.26300（AMD Ryzen 7 7700）、Zig 0.17.1、`a12b41e`のReleaseFastの4構成で、照合20群と再生ラッパー19件（音声ありの3構成）が成功し、結果は構成の間でも、Linux（1181）の記録とも同じ。レモンがほかのアプリを止めたあとの計時は、6負荷×7回の中央値で実時間の54.30倍（スピーカー）〜5.82倍（カードへ8 kHzでバス書込み）。レモンが3つの音とCtrl+Cの停止・再再生を「ok」と確認（`CATCH=-28`、ハンドル0、アンダーラン0、プロセスの残りなし）。Ctrl+Cの確認は、`python`をコマンドプロンプトから直接起動した窓で行った。PowerShellのスクリプトの中で出力をパイプへ流した窓では、Ctrl+Cでパイプごと終わり、試験にならなかった（理由は調べていない）。結果は[APPLE2_AUDIO_FORTH.md](APPLE2_AUDIO_FORTH.md)の「Windowsの受け入れ」と[測定記録](measurements/2026-11-22-apple2-audio-windows-acceptance.json)。作業ファイルは`.work/1180-windows/`。これでApple II（1178）は3つのOSとも完了。
- 1181（Apple IIのLinux受け入れ）：2026-11-22完了。Linux実機（Ubuntu 26.04.1 LTS、PipeWire、`pw-play`経由）。ReleaseFastの4構成（通常・debugなし・floatなし・audioなし）で照合20群が成功して結果が一致、再生ラッパー19件は音声ありの3構成で成功。レモンが他のアプリを止めたあとの計時は、6負荷×7回の中央値で実時間の28.5倍（スピーカー）〜2.74倍（カードへ8 kHzでバス書込み）。レモンが3つの音を「説明どおり」、Ctrl+Cの停止と再再生を「OK」と確認（CATCH=-28、ハンドル0、アンダーラン0、プロセスの残りなし）。結果は[APPLE2_AUDIO_FORTH.md](APPLE2_AUDIO_FORTH.md)の「Linuxの受け入れ」と[測定記録](measurements/2026-11-22-apple2-audio-linux-acceptance.json)。足したスクリプトは`tests/scripts/measure-apple2-audio.py`と`tests/scripts/accept-apple2-audio.py`で、1180・1182でも同じものを使う。
- 1179（Apple IIの仕様・Forth実装・独立検証）：2026-11-22完了。対象はレモンの決定で「Apple II／II+（NTSC）の内蔵スピーカーとMockingboard（6522経由のAY-3-8910 2個）」。モデルは`include/apple2-audio.fs`（接頭辞`A2-`、48 kHzステレオ、左＝スピーカー＋1個目のAY、右＝スピーカー＋2個目）。Linux実機（Ubuntu 26.04.1 LTS）の`zig build`の実行ファイルで、独立モデルとの照合20群、再生ラッパー19件、共通の語42件が成功。別のClaudeのレビューはHighなし・Medium 1件（ピンでリセット中のAYが進んでいた。直した）・Low 11件（10件対応、1件は既存のラッパーと同じ形なので残した）。仕様・資料の確認箇所・採否の論点は[APPLE2_AUDIO_FORTH.md](APPLE2_AUDIO_FORTH.md)、記録は[測定JSON](measurements/2026-11-22-apple2-audio.json)と[レビュー対応](reviews/1179-review-response.md)。
  - レモンが「おすすめどおり」（今の形のまま）と決めた点（2026-11-22、仕様書の「採否の論点」）：6522のタイマーと割込みを入れるか（今は入れていない。Mockingboardの検出や割込みで演奏するプログラムは、このモデルだけでは動かない）、スピーカーの波形（サイクル数の平均、結合コンデンサーなし）、左右と音量の比。
  - 速度は参考値だけ（ほかのアプリを止めていない）：ReleaseFastでカードのデモが実時間の約3〜4.5倍。`zig build`の既定（Debug）では実時間に間に合わず、無音の送出でアンダーランが出る。正式の測定は1180・1181で、レモンの了承のあと。
  - Windows（1180）、Linux（1181）、Mac（1182）の受け入れは完了。手順は`tests/scripts/accept-apple2-audio.py`（引数なし、`--play`、`--interrupt`）と`measure-apple2-audio.py`。
- 1204（標準の音のLinux実機再生と16声負荷）：2026-11-22完了。Ubuntu 26.04.1 LTS（カーネル7.0.0-43-generic、x86_64、Intel Core i7-8700K）。標準音21ケースを実機出力で順に再生し、レモンが「問題なし」と確認。無音モードの21ケースもすべて終了コード0・stderrなし。16声負荷はレモンが他のアプリを止めたあと、エンジン単体を各480,000 frame・7回計時し、square16 63.2倍、full16 17.5倍、table16 53.2倍のリアルタイム比。全ケース16声が発音中、非無音・非クリップ。これで1201は3つのOSとも完了。測定・再生記録は[負荷JSON](measurements/2026-11-22-standard-sound-load-linux.json)と[ケース記録](measurements/2026-11-22-standard-sound-listen-linux.json)、実行ログは`.work/1204-linux/`。

### 次の候補

1. 1140（音源対象一覧の最終採否）は2026-11-22に完了し、親の999（本体10 音源チップのレジスタ書込み）も完了にした。レモンの決定は3点：8対象は各文書が宣言したモデルで確定、対象外にしてきた変種は保留、機種によらない本体の部品は足さない（`SNES-FRAMES`は残す）。表と保留の一覧は[AUDIO_TARGET_AUDIT.md](AUDIO_TARGET_AUDIT.md)の「最終採否」、決定は[DECISIONS.md](DECISIONS.md)の「音源対象一覧の最終採否（1140）」の行。同じ表の`SNES-FRAMES`の行も、1188の決定（本体に残す）に合わせた。
2. 1000（本体11 直接色の画素転送）は2026-11-22に完了。`GFX-RGB ( addr w h stride x y key -- )`を本体に足した（1画素4バイトの`$RRGGBB`、`stride`は行の間隔で0はw×4、透明色あり、反転と拡大はなし。レモンの決定）。`zig build test`、`-Dgraphics=false`の`zig build test`、`-Dfloat=false`の`zig build`、`word-reference.py --check`、`check-docs.py`（指摘0件）はWindowsで成功。LinuxとmacOSでは実行していない。速度は測っていない。記録は[EMULATOR_CORE_PLAN.md](EMULATOR_CORE_PLAN.md)の11節の「実装」と[DECISIONS.md](DECISIONS.md)の「直接色の画素転送（1000）」の行。確認に使ったファイルは`.work/1000/`。
3. 1001（本体12 描画の補助）：2026-11-22完了（レモンの決定：測った範囲では本体に置く処理はない。不足が出たらタスクを足す）。これで1003（エミュレータ向け拡張）も完了にした。`GFX-RGB`のLinux・macOSでの確認は1255（1057の子）に登録した。試作は`.work/`にあってGitにないので、ほかの機械では測定記録のJSONの`sources`から取り出す。次の候補は、613（本体の機能拡張、50%）の残りの1037（ゲーム表示の支援。最初は1038のディスプレイ情報）と1048（タスク制御。最初は1049の方式比較）、またはマリオの移植381。以下は測定の内容。NESに似せた背景1画面をForthで試作し、Windowsで測った（2026-11-22、レモンがほかのアプリを止めたあと）。1画素ずつの復号は4277 µs（60 Hzの1コマの約26%）、8画素を1セルにまとめる書き方は691 µs（約4%）、色番号から32ビットへの変換は1969 µs（約12%）、画像への転送は`GFX-INDEXED`も`GFX-RGB`も約25 µs。この背景については本体に置く処理は見つからなかった。スプライト、優先順位、4枚以上のビットプレーンは測っていない。結果は[EMULATOR_CORE_PLAN.md](EMULATOR_CORE_PLAN.md)の12節と[測定記録](measurements/2026-11-22-background-prototype-windows.json)（試作のソースを含む）。試作は`.work/1001/`（`bg.fs`、`measure.py`）。
4. 1038（ディスプレイ情報）：Windowsの実装まで完了（2026-11-22、`d337c97`の次のコミットに入る）。語は`DISPLAYS ( -- n )` `DISPLAY-RECT` `DISPLAY-WORK` `DISPLAY-SCALE` `DISPLAY-HZ` `DISPLAY-PRIMARY` `WINDOW-DISPLAY`（レモンの決定：保持は1つで値ごとの語、物理ピクセル、取れない値は分母0、最初はWindowsだけ）。`zig build test`、`-Dgraphics=false`の`zig build test`、`-Dfloat=false`の`zig build`、LinuxとmacOS向けのクロスビルド、`word-reference.py --check`、`check-docs.py`（指摘0件）が成功。この機械の4台（どれも100%）で値を確かめた。拡大率の違う構成（1257）は完了：レモンが1台を150%にした状態で、`DISPLAY-RECT`が物理ピクセル（1920×1080）、`DISPLAY-SCALE`が3 2を返し、ウィンドウをドラッグすると`WINDOW-DISPLAY`が0→2→0→1→0と変わった。接続の変更（1261）は1回確かめた：1台（番号3）をなくすと`DISPLAYS`は3になり、残りの番号は同じで位置だけ変わり、戻すと元と同じになった。ウィンドウのあるディスプレイや主ディスプレイをなくす場合は試しておらず、1039（表示先の選択）で確かめる（レモンの決定で1261は完了）。Tk（1260）は完了：Tkから取れるのは主ディスプレイとデスクトップ全体の大きさだけで、座標は拡大率の違う構成で物理ピクセルと合わないので、Tkのウィンドウの識別子（`winfo id .`）をホストへ渡してWindowsに所属を聞く形にした（`GFX-WINDOW-DISPLAY ( id -- i )`）。レモンがTkのウィンドウをドラッグして、`WINDOW-DISPLAY`が0→2→0→1と変わることを確かめた。この機械の`wish`は`C:\msys64\ucrt64\bin\wish.exe`で、PATHにも`SIGMA_WISH`にもないので、`TCL-PROGRAM`で指定する。残りはtqueの1038の子：Linux（1258）、macOS（1259）。どちらもそのOSのTkを含む。記録は[CORE_EXTENSION_DETAILED_DESIGN.md](CORE_EXTENSION_DETAILED_DESIGN.md)の9.1節。試作と確認用のファイルは`.work/1038/`。

5. 1041（実サイズと変更通知）：Windowsの実装まで完了（2026-11-22、`18b1e4f`の次のコミットに入る）。語は`WINDOW-PIXELS ( -- w h )`と`WINDOW-CHANGES ( -- n )`（レモンの決定：キューを使わず回数と今の値、拡大率の語は足さない、最初はWindowsのネイティブウィンドウだけ）。実行ファイルで、開く・`WINDOW-SIZE`・フルスクリーン・戻すのたびに大きさが変わり、回数が1つずつ増えることを確かめた。枠のドラッグ、拡大率の違うディスプレイへの移動、構成の変化、最小化、閉じたときは確かめていない。残りはtqueの1041の子（Tk、Linux、macOS、Windowsの残りの確認）。記録は[CORE_EXTENSION_DETAILED_DESIGN.md](CORE_EXTENSION_DETAILED_DESIGN.md)の9.2節。
6. Codexのレビュー（2026-11-22、レモンの指示）：`d337c97` `a704778` `18b1e4f`を読取り専用で見てもらい、Highなし・Medium 2件・Low 2件。対応：DPIの状態を切り替えられないときは拡大率を不明にした、ホスト自身のウィンドウの所属はウィンドウのスレッドが覚えた値を読む形にした、`DISPLAYS`が0になる条件の文書を実装に合わせた、`GFX-RGB`の大きなstrideと極端な座標のテストを足した。残したもの：`GFX-RGB`の実行制限に当たった場合のテスト、Tkを通る経路のテスト、Win32の構造体の大きさのテスト。続けて1041の変更も見てもらい、Highなし・Medium 2件・Low 1件。対応：`WINDOW-PIXELS`の幅と高さを同じ時点の値にした（基本語は`GFX-WINDOW-STATE ( -- w h n )`）、最初の`SHOW`が表示とフルスクリーンの適用のあとに戻るようにした、古いWindowsでの大きさの単位を文書に書いた。依頼の形は「使うコマンド」の節のとおり（`codex exec -s read-only … < /dev/null`）。

7. 1042（ウィンドウの状態通知）：Windowsの実装まで完了（2026-11-22、`c33017c`の次のコミットに入る）。語は`WINDOW-OPEN?` `WINDOW-FOCUSED?` `WINDOW-MINIMIZED?` `WINDOW-CLOSES`。語の形はレモンの決定（2026-11-22）。閉じる動作は変えていない。1041の残りの確認（1263）も、外からウィンドウを操作するスクリプト`.work/1042/drive.ps1`で済ませた：大きさの変更、4台の間の移動（150%のディスプレイで大きさが1.5倍）、最小化、最大化、閉じる、開き直し。Codexのレビュー（Highなし・Medium 1件・Low 2件）にも対応した：最初の`SHOW`は表示とフルスクリーンの適用のあとにだけ成功する（待ち時間が切れたら失敗し、遅れたウィンドウは破棄）、フルスクリーンでのフォーカスの説明を直した、Windowsの側のテストを足した。Tkのウィンドウの実サイズ（1264）も実装した：`WINDOW-PIXELS`はTkで表示しているとき、Tkのウィンドウの大きさを物理ピクセルで返す（125%のディスプレイで、Tkの640×400に対して800×500）。`WINDOW-CHANGES`はTkのウィンドウの変化を数えない。Codexのレビュー（Highなし・Medium 3件・Low 2件）にも対応した：表示前にTkを起動しないようにした（`GFX-TCL?`）、切替えに失敗したら大きさを返さない、「変化を取りこぼさない」という説明を外した。`MOUSE`の値（1273）は、主ディスプレイ・125%のディスプレイ・フルスクリーンの3つで、3つの置き方とも計算どおりだった。ディスプレイの構成の変化（1268）は確かめた：1台をなくす・戻す・ほかのディスプレイの拡大率を変える、の4回すべてで`WINDOW-CHANGES`が増えた（戻したときは、一覧の変化より0.25秒ほど遅れた）。解像度の変更は試していない。残り：、閉じる要求を保留する方式（1267）、Tk・Linux・macOS。

8. 1040（表示領域と拡大）：Windowsの実装まで完了（2026-11-22、`743dbdd`の次のコミットに入る）。語は`WINDOW-FIT ( n -- )`（0は比を保つ、1は整数倍、2は全体）と`WINDOW-IMAGE-RECT ( -- x y w h )`。語の形はレモンの決定（2026-11-22）。`.work/1040/look.ps1`で画面の画素を読み、3つの置き方の表示を確かめた。残り：等倍の置き方・余白の色・補間（1272）、`MOUSE`の画素の実機確認、Tk・Linux・macOS。

9. 1043（フレーム提示）：Windowsの実装まで完了（2026-11-22、`2fe8292`の次のコミットに入る）。語は`WINDOW-FRAMES ( -- shown painted-through )` `WINDOW-PAINT-WAIT ( ms -- flag )` `VSYNC-WAIT ( -- flag )`。`SHOW`は変えていない。語の形はレモンの決定（2026-11-22）。実行ファイルで、待たない`SHOW`の連続では描いた数が遅れ、`WINDOW-PAINT-WAIT`で追い付くこと、`VSYNC-WAIT` 120回が約2秒（60 Hz）であることを確かめた。1040へのCodexの指摘（配置を変えたときのマウスの画素とIMEの位置）にも対応した。Codexのレビュー（High 1件・Medium 4件・Low 1件）にも対応した：`VSYNC-WAIT`は専用のスレッドで`DwmFlush`を呼んで0.1秒まで待つ、画像の全体を描いたときだけ描いた数を進める、`WINDOW-PAINT-WAIT`はホストが期限を持つ、破棄で待ちを起こす、システムのDLLはシステムのフォルダーから読む。最小化中・復帰・閉じたあとの`WINDOW-PAINT-WAIT`は`.work/1043/drive.ps1`で確かめた。残りはtqueの1043の子（待っている途中で閉じた場合、リフレッシュレートの違うディスプレイ、Tk・Linux・macOS）。

10. 1044（クリッピング）：実装まで完了（2026-11-22、`74a47eb`の次のコミットに入る）。語は`CLIP! ( x y w h -- )` `CLIP@ ( -- x y w h )` `NO-CLIP`。本体で画素を書く9つの基本語すべてに入れ、`PAINT`は描ける部分の端で止まるようにした。OSに依存しない実装で、ホストの変更はない。語の形はレモンの決定（2026-11-22）。Codexのレビュー（Highなし・Medium 1件・Low 2件）にも対応した：拡大コピーの始まりの計算を128ビットにした、コピーと`CLIP!`のテストを足した、`CLS`の説明を直した。残り：GUIの語との組合せの確認、速度への影響の測定（測る前にレモンへ確認する）。

11. 1046（画素ごとのアルファ）：実装まで完了（2026-11-22、1044と同じ次のコミットに入る）。語は`IMAGE-KEEP-ALPHA ( flag -- )`、`IMAGE-MODE`の4と5、`GFX-ALPHA-PSET ( x y a -- )` `GFX-ALPHA-CLS ( a -- )` `GFX-IMAGE-ALPHA@ ( img x y -- a | -1 )`。内部の形式は変えず、画面は常に不透明のまま。今までのテストは変えずに通っている。OSに依存しない実装で、ホストの変更はない。語の形はレモンの決定（2026-11-22）。Codexのレビュー（Highなし・Medium 1件・Low 4件）にも対応した：アルファを残す読込みは別の基本語`GFX-IMAGE-LOAD-ALPHA`にして`GFX-IMAGE-LOAD`の引数の意味を元のままにした、文書の3か所を直した、テストを足した。スプライト・GUI・`PIXEL-HIT?`・文字はアルファを見ない（今までどおり）。残り（1281）：アルファ付きPNGの保存、今までの語をアルファに対応させるかの判断、実際の絵での見た目の確認、BMPのアルファのマスクのテスト用ファイル。

12. 1045（回転と任意倍率の拡縮）：実装まで完了（2026-11-22、1044・1046と同じ次のコミットに入る）。語は`COPY-ROTATED-RECT` `PUT-ROTATED` `IMAGE-SMOOTH`。角度は100分の1度、倍率は1000分の1で、計算は整数だけ（`src/core/graphics_rotate.zig`）。語の形はレモンの決定（2026-11-22）。`.work/1045/picture.fs`で絵を保存して目で確かめた。Codexのレビュー（Highなし・Medium 3件）にも対応した：調べる範囲を広げた（64倍で端が欠けていた）、位置を商と余りで進めて誤差が積み重ならないようにした、補間なしのときの画素の置き方を`COPY-RECT`と同じにした。残り：速度の測定（測る前にレモンへ確認する）、LinuxとmacOSでのテスト。これで表示支援1037の機能の項目（1038〜1046）は、Windowsと共通の部分の実装がひととおり済んだ。残りは各OSのホスト（Linux・macOS・Tk）と、1047（共通仕様と受け入れ確認）。

22. 1285・1319（Linuxのウィンドウでの`WINDOW-FIT`と`WINDOW-SMOOTH`）：Windowsと同じ計算（`window_layout`）で実装した（2026-11-22、1265と同じコミットに入る）。WSLで、ウィンドウの画素をXから読んで確かめた（`.work/x11ctl.py`の`row`）。閉じる要求の保留（1327）もLinuxに入れ、Windowsと同じ確認の手順で同じ値になった。フレーム提示（1301）もLinuxに入れた（`WINDOW-FRAMES`と`WINDOW-PAINT-WAIT`。`VSYNC-WAIT`は偽のまま）。Linuxで残るのはTkのタスク。

21. 1265・1296（Linuxのウィンドウの状態）：`WINDOW-PIXELS` `WINDOW-CHANGES` `WINDOW-DISPLAY` `WINDOW-OPEN?` `WINDOW-FOCUSED?` `WINDOW-MINIMIZED?` `WINDOW-CLOSES` `WINDOW-IMAGE-RECT`を、LinuxのXのウィンドウで返すようにした（2026-11-22、`8154b8e`の次のコミットに入る）。WSLで、大きさの変更、モニター間の移動、閉じる、開き直しを確かめた。最小化はWSLでは確かめられていない（1331）。**WSLでの確認の注意**：`/tmp`はWSLが休止すると消えるので、ビルドは`~/.cache/sigma`に置く（`.work/wsl-test.sh`）。ウィンドウは`.work/x11ctl.py`（Xへ直接指示を出すPython。`move` `size` `iconify` `map` `delete` `where`）で動かす。xdotoolなどは入っていない。Windowsの側からの`SetWindowPos`やWM_CLOSEは、WSLのウィンドウには効かなかった。

20. 1258（ディスプレイ情報 Linux）：XのRandR 1.5で`DISPLAYS`を実装した（2026-11-22、`1a00c60`の次のコミットに入る）。WSLのUbuntu（WSLg）で4台を返し、`xrandr`とWindowsの値に一致した。拡大率は返さない（Xサーバーが知らない）。返事を読む部分は`src/display_randr.zig`、問い合わせは`src/host_display_linux.zig`。WSLgは、ウィンドウが1つも開いていない間は640×480の1台だけを返すことがある（確認のときはウィンドウを開いてから比べた）。Linuxのウィンドウの語（`WINDOW-DISPLAY`など）は1265・1296で実装した（21）。

19. 1323（回転・拡縮の大きな画像での見た目）：640×480の絵を回してPNGで見た（2026-11-22）。1.3倍では正しく、補間ありで線がなめらかになる。0.45倍では、補間なしだと細い線が切れ、補間ありでも濃さにむらが出る（まわりの4画素しか読まないため）。縮小で覆う部分の平均を取る方式を足すかどうかは、レモンの判断が要る（1330）。

18. 1322（BMPのアルファ）：アルファのマスクを持つBMPはテスト用のファイルにすでにあったので、`IMAGE-KEEP-ALPHA`で読むテストだけを足した（2026-11-22、1321と同じコミットに入る）。コードは変えていない。

17. 1321（クリッピングとほかのライブラリの組合せ）：コードは変えず、テストと文書を足した（2026-11-22、`1a00c60`の次のコミットに入る）。`DRAW-SPRITES`は`CLIP!`に関係なく行ごとの数を数える。GUIの語は描画だけが切り取られ、マウスに反応する範囲は変わらない。WSLのLinuxでも`zig build test`が成功した。

16. 1267（閉じる要求の保留）：レモンが1つずつ決めて、Windowsのウィンドウに実装した（2026-11-22、`95a34c6`の次のコミットに入る）。`WINDOW-KEEP-OPEN ( flag -- )`を真にすると利用者が閉じようとしてもウィンドウは残り、`WINDOW-CLOSES`に数える。`WINDOW-CLOSE ( -- )`でプログラムが閉じる。プログラムが`WINDOW-CLOSES`を読まないうちにもう一度閉じようとすると消える。外から`WM_CLOSE`を送って確かめた。Tk・Linux・macOSは子のタスクに登録した。tqueのタスクは、1つの機械・1種類の作業ごとに分ける（レモンの指示。WindowsとWSLのLinuxで一度にできるものは1つでよい。WSLにはZig 0.17.1とWSLg、wishがある）。Codexのレビュー（Medium 1件・Low 1件）を受けて、回数の読取りと「読んだ」印を同じロックの中で一度に行う形にした（基本語は`GFX-WINDOW-CLOSES ( -- n )`）。WSLのLinux（Ubuntu、Zig 0.17.1）で`zig build test`が3回成功した（`bash -l`で起動する。そうしないと古いZig 0.14.1が使われる。キャッシュと出力は`/tmp`。手順は`.work/wsl-test.sh`）。`GFX-RGB`のLinuxでの確認（1324）も済んだ：WSLで`zig build test`が成功し、背景試作の照合（`python3 .work/1001/measure.py /tmp/sigma-out/bin/sigma`、時間は測らない）が6つの処理とも期待の値と一致した（実行ファイルのSHA-256は`1165154d4a33c0b3781711f9ee20c62660aad79b6716914fb63adead3f0eded7`、手順は`.work/wsl-rgb.sh`）。macOSは1294に残る。実際の閉じるボタンとAlt+F4、フルスクリーンでの確認（1329）も、レモンの操作で済んだ：決めたとおりに動いた。

15. 1272（表示領域の残り）：レモンが1つずつ決めた（2026-11-22、`d48d2e2`の次のコミットに入る）。等倍の置き方、余白の色、座標変換の語は作らない。ウィンドウへの拡大・縮小の補間`WINDOW-SMOOTH ( flag -- )`を足した（初めは偽。Windowsのウィンドウ）。回転用の`IMAGE-SMOOTH`はそのまま。方式（覆う部分の平均）はこちらで選び、レモンの確認を受けていない。画面の画素で表示を確かめた。描画時間（1289）を測った：リリースビルドで、200フレームの平均が、真は1.5〜6ミリ秒、偽は0.2〜0.8ミリ秒（整数倍では同じ）。記録は`docs/measurements/2026-11-22-window-smooth-windows.json`。そのあと割り算を減らし（1292）、真は0.9〜4.3ミリ秒になった（200フレームの平均の中央値。描く画素は同じ。記録は`docs/measurements/2026-11-22-window-smooth-faster-windows.json`）。

14. 1284（Tkのウィンドウでの表示領域）：`WINDOW-IMAGE-RECT`がTkのウィンドウでも長方形を物理ピクセルで返すようにした（2026-11-22、`b5c7ddf`の次のコミットに入る）。`WINDOW-FIT`はTkでは効かない：Tkの画像は整数倍にしかできないので、今までどおり比を保った整数倍で置く。この扱いはこちらのおすすめで、レモンの確認を受けていない。1274は1284〜1288に分けた（1285 Linux、1286 macOS、1287 TkのLinux、1288 TkのmacOS）。

13. 1047（共通仕様と受け入れ確認）：対応表と共通の取り決めを書いた（2026-11-22、`862d925`の次のコミットに入る）。利用者向けの文書（英日）に「ディスプレイとウィンドウの語が使える範囲」の表、[CORE_EXTENSION_DETAILED_DESIGN.md](CORE_EXTENSION_DETAILED_DESIGN.md)の10.4節に、能力の取得とエラー、状態の持ち主と辞書イメージ、受け入れの状況、レモンの確認を受けていない語の一覧。Windowsの表の値は`.work/1047/table.fs`で確かめた（ホスト自身のウィンドウを開いていない状態での値）。Codexのレビュー（Highなし・Medium 3件・Low 2件）を受けて、表の条件、`DISPLAY-`の語のエラー、動いているSigmaへの復元で残る状態を書き直した。1047は、LinuxとmacOSの実機確認が済むまで完了にしない。語の名前とスタックは、Codexの意見を受けてレモンが1つずつ決め、8語の名前を変えて定数を9つ足した（DECISIONS.mdの「表示支援の語の名前」、設計書10.4節の最後の表）。古い名前は残していない。`IMAGE-SMOOTH`の名前は1272を決めるときに一緒に決める。1264（Tkでの`WINDOW-PIXELS`の単位）はレモンの確認を受けていない。

## サウンド再設計：標準の音と機種のライブラリまで完了、V-STEPSは未コミット（2026-11-21）

### 状態

- 最新のコミットは`58bc7ba`（`git status -sb`は`## main...origin/main`）。この節を書いた時点で、tque 1206の`V-STEPS`の変更（本体、`include/`のライブラリ7本、テスト、HELP、翻訳、設計書、DECISIONS.md、語の一覧、照合スクリプト`tests/scripts/compare-chip-libraries.py`、`tests/data/chip-compare/`、`docs/measurements/2026-11-21-chip-libraries-compare.json`）は未コミット。コミットとプッシュはレモンの指示を待つ。
- 2026-11-21にレモンから「コミット、プッシュは指示なく行わないように」。以前の「作業ごとにコミット・プッシュ」は取り消された。Codexのレビューは続けるが、コミットは指示があったときだけ行う。
- `zig build test`、`-Daudio=false`・`-Dfloat=false`・`freestanding`のビルド、`word-reference.py --check`、`check-docs.py`（指摘0件）は、この節を書く直前に成功を確認した。

### この日に終わったこと

- 1189（本体の標準の音）：16声（`PLAY`は声1〜8、`SFX`は9〜12、MODは13〜16）、音色の語、全体の効果（`REVERB`ほか）、声の状態の語（`VOICE-OSC`ほか）。機種の設定と機種名の語は本体から外した（古い基本語は名前と位置を残して-21）。コミットは`e90b6f6` `e40574c` `5473ad3`。
- 1201/1203（Windowsの実聴と16声の負荷）：21ケースの実聴はレモンがOK。負荷はエンジン単体で、全部の機能を使う16声が実時間の32.5倍（[測定](measurements/2026-11-21-standard-sound-load.json)）。1202：16声を`V12`で鳴らすと出力が飽和するが、そのままにする（利用者の決定）。
- 1190（エフェクトの受け口と機種らしさのライブラリ）：本体に`PITCH-PERIOD` `PITCH-STEP` `VOLUME-STEPS` `DUTY-STEPS` `INTERPOLATION` `VOICE-LIMIT` `MIXER` `OUTPUT-BITS`、`SOUND`のための`VOICE-HOLD`（基本語`SND-HOLD`をBuiltinの最後に追加）と`NOISE-RATE`。`include/`に`chip-sound.fs`（`STANDARD-SOUND`）、`msx-sound.fs`（`MSX-SOUND` `SOUND`）、`st-sound.fs`、`nes-sound.fs`、`c64-sound.fs`、`scc-sound.fs`（`SCC-WAVE`）、`amiga-sound.fs`（`AMIGA-FILTER`）、`chips.fs`（`STYLE`と定数`MSX`〜`AMIGA`）。コミットは`9e5860a`。
- MMLの`S` `M`の時間を、1回の上りか下りで256×M÷1789773秒に直した（それまで16倍長かった。利用者の決定A）。
- 1207（ライブラリの実聴）：ケース3と22〜32をWindowsでレモンがOK。
- 1206（削除前の機種の設定との照合）：音程・波形・倍音はほぼ一致。`V`の効き方が違ったので`V-STEPS ( addr n -- )`を足し（利用者の決定A）、各ライブラリが旧と同じ表を設定するようにした（未コミット）。照合し直すと、`V`を変えたケースの新旧の差は機種ごとの一定の倍率だけになった。全体の倍率は合わせない。
- 決定の一覧は[DECISIONS.md](DECISIONS.md)の「本体のサウンド機能の再設計」の表、詳細は[SOUND_CORE_DESIGN_STUDY.md](SOUND_CORE_DESIGN_STUDY.md)の3.10節と4節の末尾。
- `docs/LITERATE_PROGRAMMING_CONCEPT.md`（レモンの構想）を`58bc7ba`でコミットした。

### 未確認・残り

- `V-STEPS`で機種のライブラリの`V`の音量が変わった（例：MSXの`V12`が前より大きい）。実聴のケース22〜28は変わった後で聞き直していない。
- MSXのO7のA：旧は周期31（切り捨て、3608 Hz）、新は周期32（最も近い、3496 Hz）。MSX BASICがどちらかは未確認。
- ライブラリで表せていない点（設計書4節）：NESのデューティー4種類・ノイズの周期の表、Amigaの声ごとの左右、PSGのエンベロープ（1 ms単位）とノイズの3声での共有、C64のフィルターとSIDの8ビットのノイズ、SIDの16ビットの上限。
- 未完了のタスク：1204・1205（Linux・Macの実聴と負荷）、1237（1192で書き換えたプログラムの実聴）、1238（MMLの設定を初期値へ戻す語の要否）、1239（標準の音が各機種の機能を満たすかの突き合わせ）、1188（`SNES-FRAMES`の置き換え、測定は事前確認）、1194（既定`FPATH`の各OS確認）、1179〜1182（Apple II）、1140。
- 次に勧めるのは1192（動かないプログラムを直す）。

### 使うコマンド

- 実聴：`python tests/scripts/listen-standard-sound.py zig-out/bin/sigma.exe [--case N] [--list] [--silent]`。32ケース（1〜21は標準の音、22〜32は機種のライブラリ）。`--silent`は音量0で動作だけ確かめる。
- 負荷：`zig build sound-load-check -Doptimize=ReleaseFast`のあと`python tests/scripts/measure-standard-sound-load.py zig-out/audio-check/x86_64-windows/sound-load.exe`。`--measure`は、レモンが他のアプリを止めてからだけ。
- 照合：`python tests/scripts/compare-chip-libraries.py [--new COMMIT|WORKTREE]`。`.work/1206/run-*`に自分のworktreeを作って消す。新しい側の設定は`new_probe.zig`に書き直したもので`include/`は読まない（ライブラリを変えたら`new_probe.zig`も変え、`audio_test`の確認も合わせる）。
- Codexのレビュー：`codex exec -s read-only -C . -o <scratchpad>/codex-<task>-final.txt "<依頼>" < /dev/null`をバックグラウンドで。

### 作業の注意

- Bashのheredocでは`\\`が`\`に潰れる。Zigの文字列やPythonのスクリプトはWriteツールでファイルに書いてから実行するか、Editで直す。
- `check-docs.py`の出力を他のコマンドと同じファイルへまとめて書くと、前の行が消える。別々に実行して確かめる。
- Forthの局所変数は大文字小文字を区別しないので、語の名前（例：`noise`と`NOISE`）と重ねない。`msx-sound.fs`でスタックが1つ残る誤りになった。
- 語の一覧は`python scripts/word-reference.py --record-reviewed-sources`、`--sigma zig-out/bin/sigma.exe`で生成、`--check --sigma ...`で確認。新しい語は`words_audio.zig`の`library_words`に登録し、テストの中に正しい使い方の行がないと「usage examples missing」になる。


## SNES Windows/Linux完了・Mac1177残し、次はApple IIの範囲確認（2026-11-20）

Linux1176は左低音→右高音と物理Ctrl+C停止/低音再再生をレモンが確認。CATCH=-28/handle0/accepted155136、replay98304/underrun0/stack0/code0/timeoutなし。Linux4構成・通常6負荷の速度/サイズも記録済み。従来同様のUbuntu26.04.1/WSL2→pacat/PulseAudio/WSLg範囲で1176完了。physical Linux/direct ALSAの合格ではない。[仕様/結果](SNES_DSP_AUDIO_FORTH.md)、[全結果](measurements/2026-11-20-snes-dsp-os-acceptance.json)、[追レビュー](reviews/1176-linux-followup-claude-review.md)。

最初の無音補助ログのLEFT行欠落は、POSIXでreadlineとcommunicateを混ぜた取り込みの欠落を再現し、元ログを残した。全量ファイル回収の無音機能再試験で両ラベル/前後AUDIO?=-1/全統計を確認し、pacatの親がSigmaであることも記録。音源本体/実行体を直したのではなく記録補助だけを修正。Linuxlauncher実行前後とsnapshotのhashを補い、latest statusも統一した。追レビューはこれらを踏まえblocking High/Mediumなし（状態更新条件を実施済み）。

Sigma/pacat残留なし、owned WSL sleep1800はPID310とcmdline照合後にSIGTERMし、Windows controller29088退出を確認。追加のpersistent保持用processは起動していない。旧actual-run helper snapshotと後のmetadata修正版を区別する。

1174/1183/1175/1176完了、Mac1177と親1173は未完了auto80%。Windows初回連続試験の未合格・仮想既定出力/物理機器未同定の制限も保持する。次の1179は対象モデル/追加音源を先に利用者と確定する。提案は初代Apple II（NTSC）の内蔵speakerを先行し、MockingboardとIIgs DOCを別扱いとすること。現時点でApple II実装には未着手、承認済み仕様ではない。cached RedbookのC030/PEEK toggle資料と現task1178/1179を確認した。検証記録作成時点では未コミットだった。利用者からコミット/プッシュの指示を受領し、公開結果はGitのHEAD/originで確認する。一時helperは.work。以下は各時点の履歴。


## SNES Linuxの左右音確認ＯＫ・物理Ctrl+C開始確認待ち（2026-11-20）

Linux/WSLの左低音→右高音は各98304frame/handle0/underrun0/stack0/code0で完了し、レモンからＯＫ。人の確認として記録した。次は了承後.work/1175-1176/launch-linux-interrupt.ps1で新しいSNES Linux Ctrl+C test窓を開く。高音を約1秒聴いて、その窓でCtrl+Cを1回。500ms後の低音約3秒、CATCH=-28/handle0・replay98304/underrun0/stack0/code0を確認する。

Linux固有の両tone全PCM/state/ARAM、両OS RAM模擬control、全source/silent gateと--check-readyは成功。実際のWSL物理信号は未検証。共有supervisorはレビュー済み、Win actual-run snapshotと、後のLinux tone-proof選択対応版を区別して保存した。[全記録](measurements/2026-11-20-snes-dsp-os-acceptance.json)。Windows1175完了、Linux1176/Mac1177と親1173（auto60%）は未完了。owned WSL sleep1800はLinux後に本人確認して回収する。追加速度測定/コミット/プッシュなし。以下は各時点の履歴。


## SNES Windows1175完了・Linux1176の実聴開始確認待ち（2026-11-20）

Windows物理Ctrl+CはCATCH=-28/handle0/accepted81856、500ms後の低音98304frameはhandle0/underrun0/stack0/code0、レモンからＯＫ。終了後Sigma残留なし。最終ClaudeはHigh0/Medium3で、状態表記を修正し、次の制限を明記して宣言Windows範囲を閉じる評価に従い1175完了。[結果と範囲](SNES_DSP_AUDIO_FORTH.md)、[レビュー](reviews/1175-windows-final-claude-review.md)、[全記録](measurements/2026-11-20-snes-dsp-os-acceptance.json)。

確認は物理WindowsホストのwaveOut既定経路。試験後defaultはCABLE Input (VB-Audio Virtual Cable)、後段物理機器と再生時open handleのendpointは未同定。初回連続ステレオの未合格は保存し、連続試験が再合格したとは言わない。右初回/元の左単独再試験・raw参照・物理停止/再再生はそれぞれ確認済み。原因特定や本体/設定修正による恒久解決の主張はしない。

Linuxは初回Pulse接続拒否とsocketなしを記録。owned WSL接続保持中にsocket生成とRDPSink接続成功を確認し、追加の同一process無音送出は前後AUDIO?=-1/2段階98304frame/underrun0/handle0/stack0/code0。実pacat sink inputを記録し、Ubuntu26.04.1/WSL2→PulseAudio17/RDPSinkと識別。generated Linux音と物理Ctrl+Cは未実施。了承後 `wsl --exec python3 .work/1175-1176/acceptance.py linux --play` で左低音→右高音各約3秒を確認する。両gateは成功。owned sleep1800はPID記録済みで、Linux完了後に本人確認して回収。1176/1177と親1173（auto60%）は未完了。追加速度測定/コミット/プッシュなし。一時helperは.work。以下は各時点の履歴。


## SNES左低音の再確認ＯＫ・Windows物理Ctrl+C準備（2026-11-20）

元と同じSNES左低音の単独再試験はtechnical checks成功後にレモンからＯＫ。初回「右しか聞こえなかった」の失敗を保持し、原因特定やcode/設定修正による解決とは主張しない。右音は初回、左音は単独再試験で確認された記録として扱う。

次は了承後.work/1175-1176/launch-windows-interrupt.ps1で可視SNES Ctrl+C test窓を開く。高音を約1秒聴いてCtrl+Cを1回。CATCH=-28/handle0、500ms後に低音約3秒、再生handle0/underrun0/98304frame/stack0/code0を確認する。高音は最長30秒（1875block）で終了。全ソース/無音試験gate、両音の全PCM/state/ARAMとRAM模擬中断/replayを検証済みだが、実際の物理試験は未実施。[全準備](measurements/2026-11-20-snes-dsp-os-acceptance.json)のlistening_preparation.physical_interrupt_preparation。ClaudeレビューはHighなし・Medium1件を反映済み。両toneとRAM検証の一致を起動条件にし、--check-ready成功。親deadline45秒、accepted-frame表示、実Python.exe解決、PowerShell parser確認も追加した。1175/1176/1177と親1173は未完了。以下は各時点の履歴。


## SNES raw左右確認ＯＫ・元の左低音を単独再確認待ち（2026-11-20）

raw440Hzの左→右→両側（各2秒）はtechnical checks全成功後にレモンからＯＫ。試聴確認返答として記録した。元のSNES左低音が聞こえなかった報告は消さず、原因は未特定のまま。

次は元と同じ451/16/0・192block/98304frame・同音量の左低音のみを、1秒の予告後に約3秒出す。元の全PCM/state/ARAM proofと送出RAM captureのhashを照合し、無音実装置ではhandle0/underrun0/98304frame・stack0/code0。新helperは.work/1175-1176/left-recheck.pyで、了承後だけ--play実行する。[全記録](measurements/2026-11-20-snes-dsp-os-acceptance.json)のwindows_left_channel_investigation。生成音の再確認は未実施、設定/本体/実行体の変更なし。1175/1176/1177と親1173は未完了。以下は各時点の履歴。


## SNES Windows左側の実聴未合格・同一周波数で切り分け（2026-11-20）

レモンから「右しか聞こえなかった」と報告。Windows1175を完了にせず、左右実聴は未合格で保存した。技術上のhandle0/underrun0/code0を、人の確認成功として扱わない。

SD-SENDがPCM-WRITEへ渡す全98304frameをRAM callbackで捕捉し、独立PythonのPCMと全byte一致。左音は左98231非ゼロ/peak849・右全ゼロ、右音は左全ゼロ・右98245非ゼロ/peak849。ただし実装置出力の録音ではなく、原因は未特定。音の高さとchannelを分けるため、S-DSPの合成を通さない同じ440Hz/peak849のraw PCMを左→右→両側各2秒で出すテストを準備。全入力byteの照合、S-DSP frame0、実装置のゼロ送出3段階handle0/underrun0/64000frame・stack0/code0、--check-ready成功。[全記録](measurements/2026-11-20-snes-dsp-os-acceptance.json)のwindows_left_channel_investigation。

了承後だけ `python .work/1175-1176/channel-check.py --play` を実行する。切り分け音はまだ再生していない。prodコード/設定/実行体を変更せず、追加の速度測定もしていない。Claudeへ狭い範囲の確認を依頼済み。1175/1176/1177と親1173は未完了。以下は各時点の履歴。


## SNES Windows実聴準備済み（2026-11-20）

次は左だけの低音→500ms間隔→右だけの高音を各98304frame（約3.072秒）確認する。共通setupとnative PCM/266state/queue2/fullARAMを独立Pythonで両OS照合し、反対側channel全ゼロも確認。両OSは同じfixtureのFALSE送出のみ実装置で実行し、各handle0/underrun0/98304frame、DEPTH0/code0。生成音の実聴はまだ行っていない。[準備ソース/全記録](measurements/2026-11-20-snes-dsp-os-acceptance.json)のlistening_preparation。

一時helperは.work/1175-1176。了承後の実行は `python .work/1175-1176/acceptance.py windows --play`。物理Ctrl+C試験は準備のみで、RAM内模擬THROWによるcleanup/replayの両OS検査は物理合格に数えない。実際には別の可視テスト窓で約1秒後Ctrl+Cを1回押して低音再生を確認する予定。1175/1176/1177と親1173は未完了。追加の速度測定・コミット/プッシュはしていない。以下は各時点の履歴。


Claude準備レビューのMedium3件（全ソースの固定、無音実行の前提化、逐次表示）を反映し、両OSの--check-readyも成功。peak<=2048。レビュー原文とこちらの修正検証を区別して記録した。

## SNES native速度測定済み・次はOS実聴/物理中断（2026-11-20）

レモンの新たなＯＫ後、検証済みの通常版をWindows→WSL/Linuxで6負荷各16384frame×7回測定。全回の全PCM/266state/queue2/fullARAM、初期ARAM reset/前状態/A5とForth版との一致を確認し、7値の中央値も再計算した。[全値と採否](measurements/2026-11-20-snes-dsp-os-acceptance.json)のnative_candidate_timings、[結果表](SNES_DSP_AUDIO_FORTH.md)。

全6負荷で実時間を満たし、最小余裕はWindows28.69倍/Linux30.34倍（dense8kHz）。従来不足したBRR/filter3/maxpitchは36.21/36.94倍で、ARSHIFT Forth比72.96/66.41倍。次の再生受け入れにはnative候補を採用し、参照Forthは既定として保持する。SPC700/ROM/実装置込みの結果ではない。

1183完了、1175/1176は速度/サイズを記録済みだが実聴・物理Ctrl+C停止/再再生が残る。Mac1177と親1173（auto40%）も未完了。今回生成音の装置再生・コミット/プッシュ・追加ビルドはしていない。一時スクリプトは.workへ置く。以下は各時点の履歴。



## SNES native1183完了・速度測定の開始確認待ち（2026-11-20）

mainを0f33455へff-onlyでプルし、YM2149/CHIP-8/ZX SpectrumのMac受け入れ完了記録を取り込んだ。EMULATOR_CORE_PLANの競合は両側を保持して解消し、作業中のSNES変更も保持した。コミット/プッシュは行っていない。一時スクリプトは.work/1183へ置いた。

ARSHIFT後も最重BRRはWindows0.496倍/Linux0.556倍で実時間不足だったため、既定方針に従い同期・借用bufferのnative frame kernel1183を実装。[新測定と採否](measurements/2026-11-20-snes-dsp-os-acceptance.json)、[native全36report/全ソース・指紋・実行体](measurements/2026-11-20-snes-dsp-native.json)、[設計](SNES_DSP_NATIVE_DESIGN.md)、[レビュー評価](reviews/1183-review-response.md)。最終ClaudeはHigh/Mediumなし。

8構成で参照Forth19モデル群、音声有効6構成でnative23群・両backend各19RAM群を照合。nativeはBRR256×16×3、317ENV、Gauss256×4、FIR8tapと非自明なfeedback/MVOL境界も通す。6構成で一括frame/DIV/切替え/reset/SAVESYS、通常2構成でEXEC-LIMITED中断後k-frameとPythonの全state/ARAM・queue/retryを確認。両OS各6負荷は両backendで計時なしの全PCM/266state/queue2/fullARAM照合が成功。no-audioでは語が未定義で、旧ABI/native依存画像の拒否も両OS成功。core1130/host162成功（skip10/15）、全reportの現物binary/source hashを照合した。

通常版サイズはWindows2161664（旧比+15872）/Linux2371680（+15328）byte。HEREは両OS122880→218640（増分95760、logical領域のみ）。Forthのキューと所有ARAMを保持し、参照版を既定、nativeは明示adapter。新実行体へ読ませる旧画像はABI署名不一致なので再作成が必要。

1183完了、1175/1176/1177と親1173は未完了auto40%。次は新たな開始確認への返答後だけ、通常版の `measure-snes-dsp-audio.py PATH --native --measure` をWindows→WSL/Linuxで順に実行する。nativeの速度は未測定で、実時間採用・実聴/物理中断再再生・Mac受け入れを完了としない。以下は各時点の履歴。


## CHIP-8/ZX SpectrumのMac受け入れ1167/1172（2026-11-20）

この節を最新状態とする。基点main `c205820`。macOS 27.2.1 / Apple M5で1167（CHIP-8）と1172（ZX Spectrum）を実施し合格、tqueの1167・1172と親1163・1168を完了にした。全検査がWindowsの記録と一致し、通常構成の速度は全負荷でWindows/Linuxより余裕があった（CHIP-8最重50.59倍、ZX最重5.34倍）。Ghosttyで実聴とCtrl+C中断・再再生を確認した。結果は[CHIP-8](CHIP8_AUDIO_FORTH.md)、[ZX Spectrum](ZX_SPECTRUM_AUDIO_FORTH.md)の冒頭の節。

## YM2149のMac実機受け入れ1154（2026-11-20）

この節を最新状態とする。基点main `53ebe81`。macOS 27.2.1 / Apple M5で固定音量0修正を含む新ビルドを作り、native回帰・core1126/host152成功、YM2149の3構成の全検査がWindowsと一致、Ghosttyで実聴とCtrl+C中断・再再生を確認した。1154と親1138を完了にした。結果は[YM2149の記録](YM2149_FORTH.md#mac実機受け入れ11542026-11-20)。

## SNES初回速度測定で実時間未達・ARSHIFT候補検証済み（2026-11-20）

レモンの開始確認へのＯＫ後、Windows→WSL/Linuxで6負荷各16384frame×7processを測定し、全回のPCM/266state/queue2/fullARAMと前状態/ARAM reset/A5を照合した。最重filter3/maxpitchは実時間比Windows0.425倍/Linux0.503倍、Windows echoも0.983倍。初回版で宣言全負荷の実時間採用には不足する。[全7値・旧source・候補検証](measurements/2026-11-20-snes-dsp-os-acceptance.json)、[結果と採否](SNES_DSP_AUDIO_FORTH.md)。

まずForthのSD-ASRをFM/MODによるfloorから既存ARSHIFTへのaliasへ変更した候補を作成。native/ABI/API/harnessは不変。使用shift1/4/5/6/7/10/11の旧helper/候補/独立Pythonの境界115vectorを両OSで直接比較し、8構成×20モデル群（新helperの1344vector含む）・6構成×19RAM群が成功した。6負荷の計時なし検証でも全PCM/ARAM hash・state/queueが初回版と完全一致、oracle brr/Model/demo AST不変を確認。HERE95752byte増分のまま、native332source/8binary現物hashも不変。[候補レビュー](reviews/1175-1176-arshift-claude-review.md)は使用範囲で同値として評価を推奨しているが、改善幅は未測定。

次は新たな計時開始確認への返答後、同じmeasureスクリプトをWindows→Linuxで--measure実行し、候補の7値と旧版の比を別に記録する。旧値は上書きしない。なお不足すれば本体移行判断を具体化する。生成音の実聴は未実施。1174完了、1175/1176/1177と親1173は未完了。Mac1177は対応機能の子に残す。今回コミット/プッシュは行っていない。以下は各作業時点の記録。


## SNES1174完了・Windows/Linux測定の開始確認待ち（2026-11-20）

承認された標準S-DSPの8声/BRR/Gauss/ADSR/GAIN/noise/PMON/stereo/echoFIRをForthで実装し1174完了。[仕様・制限・結果](SNES_DSP_AUDIO_FORTH.md)、[14report/全ソース・指紋・来歴](measurements/2026-11-20-snes-dsp-audio.json)、[レビュー原文と評価](reviews/1174-review-response.md)。8構成×19モデル群、音声有効6構成×19stereo RAM caseが成功。10統合caseの全PCM/266state/全ARAM、一括/分割、BRR/Gauss/rate/317ENV/全reg/ARAM/手計算/error境界を検査。8構成すべて保存HTMLからGaussを別抽出して照合した。最終ClaudeはHigh/Mediumなし、Lowも検査追加後に全構成成功。

両OSの実PCM経路で各8192frameをFALSEのゼロのみ送出しAUDIO?=-1/handle0/underrun0/stack0/code0。Linux最初のAUDIO?=0回は参考に保存し、接続保持後の実経路を確認した。残留Sigma/pacatなし、保持用owned sleep120も終了済み。HEREはWindows122880→218632（logical増分95752byte、RSSではない）、再生bufferは別。native332ソース不変で既検証8binaryを再利用。CPU/ROM/実機微細slot互換の完了とは主張せず、宣言差分を仕様に明記。

親1173は未完了auto25%、Windows1175/Linux1176/Mac1177も未完了。999は未完了auto75%。次の1175/1176用6負荷各16384frameのハーネスは両OSで計時せず、全PCM/266state/queue2/fullARAMと前状態/全ARAM resetを照合した。[準備記録](measurements/2026-11-20-snes-dsp-os-preparation.json)、[計画レビュー](reviews/1175-1176-review-response.md)はHigh/Mediumなし。-Oは入口で拒否、未計時roundを明示。速度/採否/実聴は未実施。

次はレモンの計時開始への返答後、Windows→WSL/Linuxを順に `python tests/scripts/measure-snes-dsp-audio.py PATH_TO_SIGMA --measure` で7回ずつ測定する。開始確認は必須で、タイムアウトや機能検査は測定の代用ではない。Mac1177は残し、完了まで親1173を未完了に維持。今回コミット/プッシュは行っていない。以下は各作業時点の記録。


## ZX Windows1170/Linux1171完了・次はSNES1174の範囲確認（2026-11-20）

レモンがLinux物理再試験の停止→低音再生を確認し、最終追レビューHigh/Mediumなしで1171を完了。Windows1170も完了。[仕様・結果](ZX_SPECTRUM_AUDIO_FORTH.md)、[全値/ログ/ソース](measurements/2026-11-20-zx-spectrum-os-acceptance.json)、[最終レビュー評価](reviews/1170-1171-review-response.md)。

Linux物理は2回中、試験用の非可聴B/C/noise周期を変えた2回目で成功。初回exit=-2とcleanup未確認を保存。プログラムSIGINT診断は物理受け入れに数えず、NativeScope外のCtrl+Cは終了し得る制約を維持した。Linuxの残留Sigma/pacatなし、owned keepaliveはcmdline確認後停止済み。再生wrapperの初回最大4096frame供給修正は6構成×19RAM検査成功、純粋core/native不変・速度再測定なし。

1169/1170/1171完了、Mac1172未完了のため親1168は未完了auto75%、999は未完了auto68%。次はSNES1174。標準S-DSPの8声/BRR、envelope/noise、pitch modulation、echo/8tap FIRを対象とし、SPC700 CPUは別扱いとする案をレモンが承認済み。既存資料 `.work/1139/snes.pdf/.txt` のDSP register表とBRR章を確認したが、SDK/ROM/他実装コードはコピーせず、補間/境界/時刻とモデル範囲は資料とClaudeレビューで設計する。SNES実装には未着手。この範囲のコミット・プッシュ依頼を受領した。公開結果はGitの状態で確認する。以下は各作業時点の記録。


## Linux物理Ctrl+C初回失敗・診断と再試験準備（2026-11-20）

初回はREADY後SIGINT exit=-2、CATCH/再再生なしで1171未完了。失敗source/JSONを保存。[全記録](measurements/2026-11-20-zx-spectrum-os-acceptance.json)、[診断レビュー/評価](reviews/1170-1171-review-response.md)。無音の制御診断はSigCgtを確認してSIGSTOPで固定後にSIGINT/SIGCONTを注入し、捕捉なしはexit-2、捕捉ありはCATCH=-28/handle0→replay underrun0/DEPTH0/code0。物理受け入れの代替にはしない。元の失敗時の命令位置は特定できない。

再試験用Linux helperのみ非可聴B/C period4095、noise31へ変更。AY高/低音各49152frameの全PCM/39状態を独立Pythonと照合し、元の実聴PCMともhash一致。192/288block無音送出もunderrun0/handle0。native/core/wrapper不変、追加速度測定なし。物理捕捉が必ず成功するとは保証しない。

次は了承後 `.work/1170-1171/launch-linux-interrupt.ps1` を開く（引数linux linux-r2）。新しい結果はlinux-r2-interruptへ分ける。まだ生成音を再生していない。Windows1170完了、Linux1171/Mac1172と親1168は未完了。WSL保持用owned sleep1800はLinux完了後に本人確認して停止。コミット/プッシュは行っていない。以下は各作業時点の記録。


## Linux128K実聴済み・物理Ctrl+C準備（2026-11-20）

レモンがLinux128Kの高音→低音→低音+断続beeperを確認した。全段階underrun0/handle0/49152frame/stack0/code0。Linux48Kも実聴済み。[全記録](measurements/2026-11-20-zx-spectrum-os-acceptance.json)。

次は了承後、`.work/1170-1171/launch-linux-interrupt.ps1` で可視PowerShellからWSL/python3のinterrupt.py linuxを実行する。連続約440Hzを1秒ほど聴いたら、そのテスト窓でCtrl+Cを1回。停止後500msの間を置いて低い約220Hzが約3秒再生される。CATCH=-28/handle0、replay handle0/underrun0、DEPTH0/code0を確認する。まだ起動していない。タイトルはEncodedCommand方式でWindowsの引用符問題を避ける。

Windows1170完了、Linux1171/Mac1172と親1168は未完了。WSL保持用owned sleep1800はLinux完了後に本人確認して停止する。コミット/プッシュは行っていない。以下は各作業時点の記録。


## Linux48K実聴済み・128K準備完了（2026-11-20）

レモンがLinux48Kのブザー約1秒→無音約1秒を確認。underrun0/handle0/98304frame/stack0/code0。[全記録](measurements/2026-11-20-zx-spectrum-os-acceptance.json)。Linux128Kの3段階（AY約440Hz→約220Hz→低音+断続beeper、各1.024秒）は全段階の無音実PCMがunderrun0/handle0で、各全PCM/状態も独立期待値とLinux上で一致した。生成音はまだ鳴らしていない。

次は了承後、`.work/1170-1171/linux-128k.fs` をWSL/Linux通常binaryで実行する。その後物理Ctrl+C。Windows1170完了、Linux1171/Mac1172と親1168は未完了。WSL保持用sleep1800はownedで、Linux完了後にkeepalive.pidとcmdlineを確認して停止する。コミット/プッシュは行っていない。以下は各作業時点の記録。


## Windows1170完了・Linux48K実聴準備（2026-11-20）

レモンが物理Ctrl+Cで停止後の低音再生も確認し、Windows1170を完了にした。48K/128K実聴とCATCH=-28/handle0、再生underrun0/DEPTH0/code0が揃った。[全記録](measurements/2026-11-20-zx-spectrum-os-acceptance.json)。親1168は未完了auto50%、Linux1171/Mac1172は未完了。

WSLg Pulseは初回connection refused、ownedWSL sleep1800で保持後pactl infoとAUDIO?=-1を確認した。RDPSink/44100Hz stereo、model入力48000Hz mono。Linux48Kの約440Hzブザー→無音の無音版はunderrun0/handle0/98304frame/code0。生成音はまだ鳴らしていない。次は了承後、`.work/1170-1171/linux-48k.fs` をWSLの通常Linux binaryで実行する。保持用のowned processはkeepalive.pidで識別し、Linux受け入れ後に本人確認して停止する。Windowsテスト窓は終了したSigmaの後にPowerShellが残るだけで、勝手に閉じない。コミット/プッシュは行っていない。以下は各作業時点の記録。


## Windows物理Ctrl+C/再生ログ成功・実聴詳細待ち（2026-11-20）

可視テストでCATCH=-28/handle0、REPLAY-OK handle0/underrun0、DEPTH0/code0を確認した。レモンは「音は鳴った」とログを提示。停止後に低い音が約3秒鳴る順序の実聴確認はまだ明示されていないため1170は未完了。Sigma processは終了済み。[全記録](measurements/2026-11-20-zx-spectrum-os-acceptance.json)。

冒頭のZX command-not-foundはStart-Process -Commandのタイトル設定で引用符が失われたもの。無音のlabel代入だけで同じエラーを再現し、EncodedCommand方式で文字列全体の出力/stderr0を確認した。次回用 `.work/1170-1171/launch-windows-interrupt.ps1` は修正済みだが、音声テストは再実行していない。1170/1171/1172と親1168は未完了。コミット/プッシュは行っていない。以下は各作業時点の記録。


## Windows128K実聴確認済み・物理Ctrl+C準備（2026-11-20）

レモンがAY高音→低音→低音+断続beeperの3段階を確認した。全段階underrun0/handle0/49152frame/stack0/code0。[記録](measurements/2026-11-20-zx-spectrum-os-acceptance.json)に保存した。Windows48K修正版も実聴済み。

次はWindowsの物理Ctrl+C。`.work/1170-1171/interrupt.py windows` を可視PowerShellから実行し、約440Hzの連続音を1秒ほど聴いたらCtrl+Cを1回。CATCH=-28/handle0で停止し、500ms後、約220Hzを3.072秒再生する。replay handle0/underrun0、DEPTH0、code0を確認する。監督PythonだけSIGINTを捕捉し、Sigmaへ物理入力が届く構成。まだ起動していない。割込み前streamのunderrunはclose後に照会できないため0とは記録しない。

1170/1171/1172と親1168は未完了。コミット/プッシュは行っていない。以下は各作業時点の記録。


## Windows48K修正版の実聴確認済み・128K準備完了（2026-11-20）

レモンが修正版の約440Hzブザー約1秒→無音約1秒を確認した。underrun0/handle0/98304frame/stack0/code0。[記録](measurements/2026-11-20-zx-spectrum-os-acceptance.json)に保存した。

次のWindows128KはAY高音約440Hz→低音約220Hz→低音に断続的なbeeperが重なる3段階（各96block=1.024秒）。無音の実PCMは全段階underrun0/handle0/49152frame/code0。各段階の全PCM/39状態/queueを独立Pythonと照合済み。生成音はまだ鳴らしていない。1170/1171/1172と親1168は未完了。次は128K実聴への了承後に `.work/1170-1171/windows-128k.fs` を通常Windows binaryで実行する。コミット/プッシュは行っていない。以下は各作業時点の記録。


## ZX初期供給不足を修正・無音検証完了（2026-11-20）

レモンが最初のWindows48Kブザー→無音を実聴確認した。underrunはWindowsの初期8×480frame連続renderに対して初回512frameしか渡さない経路で再現し、ZX wrapperの初回だけ最大4096frameをまとめて公開するよう修正。1block/8blockだけを変える比較で対照1/1/1、修正48K0/0/0・128K0/0/0。6構成×19RAM検査とClaudeレビュー（High/Mediumなし）も成功した。[結果/ログ/ソース](measurements/2026-11-20-zx-spectrum-os-acceptance.json)、[評価](reviews/1170-1171-review-response.md)。native/coreと測定source不変、速度再測定なし。

追加の生成音は鳴らしていない。次は修正版で同じWindows48Kブザー→無音を再確認し、その後128K・物理Ctrl+Cへ進む。Windows1170/Linux1171/Mac1172と親1168は未完了。今回コミット/プッシュは行っていない。以下は各作業時点の記録。


## ZX Spectrum Windows実聴でunderrun検出（2026-11-20）

レモンのＯＫ後、約440Hz/約1秒→無音約1秒をWindowsで1回再生した。code0/handle0/98304frame/ULA0/stack0だがunderrun2で、実聴の返答も未受領のため受け入れは保留。追加の生成音は鳴らしていない。無音3回はunderrun0/1/1、事前に2048frame合成する無音3回も2/1/2で解消せず、原因未特定。最初の影響例はblock4/5で増加している。[全ログ/実行source](measurements/2026-11-20-zx-spectrum-os-acceptance.json)に保存。1170/1171/1172と親1168は未完了。次は実聴の返答を受け、初期送出とconsumerのログを調査する。速度測定は再実行していない。以下は各作業時点の記録。


## ZX Spectrum Windows/Linuxの速度・サイズ記録（2026-11-20）

レモンの開始確認へのＯＫ後、通常構成の6負荷32768frame×7processをWindows→WSL/Linuxの順に測定し、全回のPCM/状態/queueとRESET/A5を照合した。実時間比の中央値は48K beeperが78.81倍/91.59倍、最小の128K period0が3.59倍/4.14倍。[全値・指紋](measurements/2026-11-20-zx-spectrum-os-acceptance.json)、[結果と採否](ZX_SPECTRUM_AUDIO_FORTH.md)。測定範囲の音源はForthを維持するが、CPU/ROM全体・任意trace・実装置再生の保証ではない。

サイズはnative不変でWindows2145792byte/Linux2356352byte、logical辞書増分25160byte。Windows1170/Linux1171は生成音の実聴・物理Ctrl+C後の停止/再再生待ち、Mac1172も未完了。親1168は未完了auto25%、999は未完了auto61%。次はWindowsの48K beeper約1秒→無音約1秒の実聴から行う。コミット/プッシュは行っていない。以下は各作業時点の記録。


## ZX Spectrum実装1169完了（2026-11-20）

レモンが48K beeper/128K beeper+AYを承認した。[仕様・結果](ZX_SPECTRUM_AUDIO_FORTH.md)、[全検査データ/ソース指紋](measurements/2026-11-20-zx-spectrum-audio.json)、[レビュー対応](reviews/1169-review-response.md)を保存した。全port/register byte、16envelope手書き列、独立CPU tick/全PCM/状態、queue/error/time上限を8構成で照合。音声有効6構成の11RAM送出検査、両OSの各8192frame無音実PCMも成功。最終ClaudeはHigh/Mediumなし。native332ソース不変、HERE増分25160byte（RSSではない）。

1169完了、親1168は未完了・auto25%。999は未完了・auto61%。Windows1170/Linux1171/Mac1172のサイズ/速度・採否・生成音の実聴は未完了。速度測定は準備を済ませ、開始確認への返答後に実行する。Macの確認は対応featureの子タスクに残す。今回の差分は未コミットで、コミット/プッシュは行っていない。1170/1171用の6負荷32768frame測定ハーネスは両OSで計時なしの全PCM/状態検証に成功し、[準備記録](measurements/2026-11-20-zx-spectrum-os-preparation.json)と[計画レビュー](reviews/1170-1171-review-response.md)を保存した。計時開始の返答待ち。以下は各作業時点の記録。

## CHIP-8 Windows/Linux受け入れ1165/1166完了（2026-11-20）

レモンの開始確認へのＯＫ後、6負荷32768frame×7processをWindows→WSL/Linuxで正式再測定した。最重の8kHz pattern/pitch更新は実時間比Windows33.78倍/Linux38.23倍。全PCM/状態・A5/RESET・queue件数/stack0を照合。実聴は両OSでclassicのtimer停止、XO高低の切替、物理Ctrl+C後の停止/再再生を確認し、handle0/underrun0/code0。宣言した音源はForth維持とし、CPU/ROM全体の性能は主張しない。[結果/採否](CHIP8_AUDIO_FORTH.md)、[全データ](measurements/2026-11-20-chip8-os-acceptance.json)、[レビュー](reviews/1165-1166-review-response.md)。

1164/1165/1166完了、Mac1167は未完了のため親1163は未完了・auto75%。YMのMac1154はtodo。999は未完了・auto59%。次はZX Spectrum1169の対象モデル/音源範囲を確定して仕様・実装へ進む。事前確認なしの速度値は参考値として保全し正式値とは分離した。今回の差分は未コミット。以下の測定待ち等は各作業時点の記録。

## CHIP-8 Windows/Linux実聴完了・正式測定待ち（2026-11-20）

レモンがclassicのtimer停止、XOの1オクターブ切替、両OSの物理Ctrl+C後の停止/再再生を確認した。全回code0、handle0、underrun0。8構成のサイズも記録済み。測定ハーネスをClaude指摘で修正し、A5 buffer/初期状態・全PCM/状態/queue件数・順序回転を確認したが、開始前の利用者確認がなかったため速度は信頼性の低い参考値として保存し、正式な測定と採否を保留する。[全記録](measurements/2026-11-20-chip8-os-acceptance.json)、[レビュー評価](reviews/1165-1166-review-response.md)。1165/1166は再測定待ち、Mac1167も未完了。再開時はレモンが他アプリを止められるよう開始確認を取り、約15秒でWindows→WSL/Linuxを順に再測定する。今回コミット/プッシュは行っていない。

## CHIP-8/XO音源の実装1164完了（2026-11-20）

レモンが原型/SUPER-CHIPのブザーとXO-CHIP pattern/pitchを承認した。[仕様・結果](CHIP8_AUDIO_FORTH.md)、[全生データ/ソース指紋・本文](measurements/2026-11-20-chip8-audio.json)、[レビュー評価](reviews/1164-review-response.md)を保存。modern timer>0 gate、固定440Hzブザー、16byte所有コピー、Q32 pitch/phase、60Hz境界と時刻付きqueueをForthに追加した。CPU/ROMや原機speakerの電気特性は対象外で、native/Builtin/ABIは変更していない。

Windows/Linuxの通常・除外の8構成で各13モデル検査群、音声有効6構成で各11RAM送出/cleanup検査成功。全256pitch/65536frame、512pending patternの回収と2730event、同tick順、250境界のphaseを独立数理/手計算と照合。無音の実PCMも両OSで成功、最終ClaudeはHigh/Mediumなし。辞書HERE増加43120byteはlogical値でRSSではない。性能測定・生成音の実聴は未実施。

1164を完了、Windows1165/Linux1166/Mac1167は未完了のまま。親1163は未完了・auto25%、999は未完了・auto55%。次は1165/1166のサイズ/速度・採否と生成音の実聴へ進む。YMのMac1154はtodo。監査1139と今回の実装差分は未コミットで、コミット/プッシュは今回行っていない。

## 音源8対象の先行照合1139完了（2026-11-20）

[8対象の音源監査](AUDIO_TARGET_AUDIT.md)と[資料/ソース指紋・タスク出力](measurements/2026-11-20-audio-target-audit.json)を保存した。CHIP-8、ZX Spectrum、SNES、Apple IIに機種固有の状態/時刻/PCM生成の不足があり、機種別親1163/1168/1173/1178を999直下へ追加。各機種に仕様実装・Windows・Linux・Macの子を置き、Macの未確認を末尾へまとめない。1140は新4件への依存も保持し、モデル/変種の対象と保留理由を最終確認する。Forth先行は既存の利用者決定で、今回最終採否を決めていない。[レビュー評価](reviews/1139-review-response.md)、最終High/Mediumなし。

1139は完了、新4機種は未着手。YM2149のMac1154はtodo、1138は未完了・auto80%。999は未完了・auto52%（未着手4枝を追加したため表示が下がった。工数比ではない）。1140は未完了で依存待ち。次はCHIP-8の仕様/実装1164から着手し、対象変種と波形・timer境界を先に確定する。今回の監査差分は未コミット。

## Linux実聴5件の完了（2026-11-20）

WSL Ubuntu26.04.1へpulseaudio-utilsを導入し、Linux静的musl版→pacat→WSLg PulseAudio RDPSink→Windows出力で、レモンがPCM全8項目、NES4声/DMC単独/混合、SID3声、Paula4声stereo/左右分離、YM2149デモ/noise/envelopeの計20caseを聞いて確認した。各音源の物理Ctrl+C後の停止・再再生はCATCH=-28、handle=0、REPLAY-OK handle=0、PCMはclose0/hello入力、全process code0。記録したunderrunはすべて0。最後にPulse sink-inputとpacat processが残らないことも確認した。[環境・全コマンド・実聴結果・ソース本文](measurements/2026-11-20-linux-audio-listening.json)。Linux実機ALSA装置の確認とは区別する。

1149/1151/1158/1156/1162と親1133/998/1132/1136/1137を完了。1138はtodo・auto80%、Mac1154はtodo。999は未完了・auto68%。今回のLinux記録は未コミット。以下のLinux未確認やAUDIO?=0は当時の状態。

## Linux PCM実聴1149と親998の完了（2026-11-20）

WSL Ubuntu26.04.1へpulseaudio-utilsと依存ライブラリを導入し、静的musl版Sigmaのpacat pipe経由でWSLg PulseAudio RDPSinkへ出力した。AUDIO?=-1を確認し、レモンがmono/stereo左右・MML/SFX混合・破棄と再開・drain後停止・保存アプリ・物理Ctrl+C後の停止とhello入力の全8項目を実聴してＯＫと回答。case1〜7のunderrun0、case8はCATCH=-28/CLOSE=0、全process code0。1149・1133・998を完了した。[環境・コマンド・実聴記録](measurements/2026-11-20-linux-audio-listening.json)。これはWSL/Linux実行体からPulseAudioを経た実出力の確認で、Linux実機のALSA装置確認とは区別する。以降のLinux未確認・AUDIO?=0は当時の記録。

## 今回のコミット対象（2026-11-20）

YM2149のForthモデル・native固定音量0修正と検証/測定、PCM語群除外の再確認1159/1160、Windows実聴1148/1150/1157/1155/1161の受け入れ記録を含む。Linux実聴1149/1151/1158/1156/1162とYM2149のMac1154は未完了のまま各機能配下に残す。以下は作業時点の履歴であり、未コミット等の記述も当時の状態。

## WindowsのPaula/YM2149実聴1155・1161完了（2026-11-20）

レモンがPaula4声stereo・左だけ/右だけ、YM2149デモ・noise単独/envelope音量変化を実聴し、両例の物理Ctrl+C後の停止と再再生を確認した。CATCH=-28、handle=0、REPLAY-OK handle=0、code0、記録したunderrun0を保存し1155/1161を完了。[Paula](PAULA_FORTH.md)、[YM2149](YM2149_FORTH.md)、[全生データ](measurements/2026-11-20-paula-ym-windows-listening.json)。Linux1156/1162、YMのMac1154は未完了。親1137は未完了・auto80%、1138は未完了・auto60%、999は未完了・auto57%。今回コミット/プッシュは行っていない。

## YM2149のOS別実聴タスク追加（2026-11-20）

1138直下にWindows1161・Linux1162を追加し、1153へ依存させた。両方未完了・0%。3声/ノイズ/envelopeの実聴、Ctrl+C後の停止・再再生とhandle解放、OS/版/装置を確認する。Mac1154も維持し、親1138は未完了・auto40%。[確認範囲](YM2149_FORTH.md)。末尾の統合タスクへ移さない。

## WindowsのNES/SID実聴1150・1157完了（2026-11-20）

レモンがNES4声・DMC単独・4声＋DMC、SID3声を実聴し、両例の物理Ctrl+C後の停止と再再生を確認。CATCH=-28、handle=0、REPLAY-OK handle=0、underrun0、code0を保存し1150/1157を完了した。[NESの記録](NES_DMC_FORTH.md)、[SIDの記録](SID_FORTH.md)、[原データ](measurements/2026-11-20-nes-sid-windows-listening.json)。Linux実聴1151/1158が未完了のため親1132/1136はともに未完了・auto80%。999は未完了・auto55%。機能ごとの確認を末尾へ集約しない。今回コミット/プッシュは行っていない。

## Windows実聴1148の受け入れ完了（2026-11-20）

レモンがWindows実装置で8項目を順番に聞き、各項目をokで確認した。48000Hz mono、22050Hz stereo左右、MML/SFXとの混合、破棄と再open、drain後の停止、SAVESYS保存アプリの2音を確認。最後は前面のPowerShellで物理Ctrl+Cを押し、CATCH=-28/CLOSE=0、続くhelloのACCEPTとcode0を記録し、中断後の音の停止も追加確認した。case1〜7のUNDERRUNSはすべて0。Windows11 Pro 10.0.26300、waveOut既定出力（個別endpoint表示名は未取得）。[全実行記録と利用者の確認](measurements/2026-11-20-pcm-windows-listening.json)。

1148を完了。Linux1149は未完了・0%、1133は未完了・auto50%、998は未完了・auto94%。現WSLはAUDIO?=0のため、Linuxの実聴成功とは扱わない。以下の「Windows実聴未確認」はこの受け入れ以前の履歴。

## PCM998の再確認と実聴準備（2026-11-20）

Windows1159/Linux1160の語群除外再確認を完了し998は未完了・auto88%。旧[DEFINED]の0 0を除外の証拠とした部分は撤回。実行したREQUIRE-AUDIOをCATCHで捕捉して無効版-275、有効版でAUDIO内のPCM語を確認し、元の16構成と新4実行体で成功した。残件は1133配下の実聴1148/1149。[現在の検査記録](PCM_PUBLIC_IMPLEMENTATION.md)、[実聴の手順と8項目](PCM_LISTENING_ACCEPTANCE.md)。スクリプト既定は無音。現WSLはAUDIO?=0で音声client library未導入、実聴成功とは扱わない。YM2149の未コミット差分は保持する。

## 現在状態：Atari ST YM2149の実装・Windows/Linux検証（2026-11-20）

基点mainはcf080b4（Paulaまでpush済み）。今回のYM2149差分は未コミット。1152（監査と実装）・1153（Windows/Linux検証と測定）を完了し、Mac1154を1138の子に残した。1138は未完了・auto66%、999はauto49%。PaulaのMac1147は完了し、Windows実聴1155/Linux実聴1156が未完了のためPaula1137はtodo・auto60%。Macの確認まで親タスクの完了とはしない。以下は各作業時点の履歴で、この節を優先する。

[YM2149の契約・資料・結果](YM2149_FORTH.md)、[レビュー評価](reviews/1138-review-response.md)、[全測定・ソース本文](measurements/2026-11-20-ym2149.json)を参照。3声/noise/全16envelope、時刻指定、raw読取り、2つのI/O latchとFF8800/FF8802のbyte busをForthに追加した。既存native YMの固定音量0が微小出力になる問題も修正し、非ゼロ固定音量・envelope level1と停止後のfilter tailを保持する回帰検査を追加した。Builtin/ABIは追加しない。

両OSの通常・debug/graphics/extension除外・さらにfloat除外の6構成で各11検査群と補助12検査が成功。audio除外の2構成でも全512frame/状態が一致。全8実行体はnative修正後の新ビルド。native Windows全体検査成功、Linux core1126成功/10skip、host167成功/17skip、失敗0。通常負荷は実時間比Windows9.532倍/Linux11.431倍、全period1は3.212/3.834倍。各6負荷32768frameの全PCM/状態と、各7計時の最終37状態を独立Pythonと照合した。辞書HERE増加25152byte、通常実行体はPCM1128保存済み版比Windows+512/Linux+48byte。最終ClaudeレビューはHigh/Mediumなし。

Mac1154では新ビルドのnative fixed-zero回帰・core/host検査、Forth通常/除外構成・サイズ/速度と生成音の実聴・中断/資源回収を確認する。Windows/Linuxのfixtureは実聴を証明しない。次は1139で8対象の既存音源経路と不足を照合し、追加不要の根拠または必要な機種別タスクを記録する。1140の最終採否は各機能のMac確認を含む依存が済むまで完了にしない。

## 最新追記：PaulaのMac実機受け入れ1147（2026-11-20）

この節を最新状態とする。基点main `cf080b4`。macOS 27.2.1 / Apple M5で1147を実施し合格、tqueの1147を完了にした。各音源のWindows/Linux実聴を機能ごとの子へ移した（NES1150/1151→1132、SID1157/1158→1136、Paula1155/1156→1137）ため、親1132/1136/1137は未完了。合成中のCtrl+CをEXEC-LIMITEDで捕捉する例の修正は、合成が約2.8倍遅くなるため取り消し、文書に記載した。3構成の全検査がWindowsと一致し、Ghosttyで4声stereo・左右の分離・Ctrl+C中断と再再生を実聴で確認した。結果は[Paulaの記録](PAULA_FORTH.md#mac実機受け入れ1147)。

## 現在状態：Mac受け入れ結果の取り込み（2026-11-20）

mainは9baef92（NES/DMC・SIDのMac受け入れ記録まで取り込み済み）。1144/1143と親1132/1136は完了。Paulaの1145/1146は完了、Mac1147と親1137は未完了（auto66%）のまま。999はauto52%。未コミットのPaula実装・測定・タスク配置の文書は保全した。以下の節は各作業時点の記録であり、Mac未確認や古い進捗表示は、この現在状態と各Mac受け入れ節を優先する。

## 最新追記：NES/SID音源例のMac実機受け入れ1144/1143（2026-11-20）

この節を最新状態とする。基点main `1f1a67c`。macOS 27.2.1 / Apple M5で1144（NES APU/DMC）と1143（SID）を実施し合格した。tqueの1144・1143を完了にした（親1132・1136は後に実聴の子を移したため未完了）。全検査がWindows/Linuxの記録と一致し、Ghosttyで実聴とCtrl+C中断・再再生を確認した。結果は[NES](NES_DMC_FORTH.md#mac実機受け入れ1144)、[SID](SID_FORTH.md#mac実機受け入れ1143)。合成中のCtrl+CはOS終了になる（既存規則、20回中7回）。Windows/Linuxの実聴はNES 1150/1151、SID 1157/1158で未確認。

## 最新追記：Paulaの実装・Windows/Linux確認、Mac未完了（2026-11-20）

Paula実装時のmainは1f1a67c（SIDまでpush済み）。今回のPaulaとタスク配置修正の文書は未コミット。1145のレジスタモデルと1146のWindows/Linux検証・測定を完了した。Mac受け入れ1147は1137の子で未完了に残し、親1137は未完了・auto66%。Macの確認までタスク全体の完了とはしない。999はauto42%（子タスクの均等平均）。

[契約・資料・検証と測定](PAULA_FORTH.md)、[レビュー評価と原文](reviews/1137-review-response.md)、[生データ・コマンド・ソース本文](measurements/2026-11-20-paula.json)を参照。4声stereo、DMA/手動DATの1word保持、IRQ、attachと予定書込みをForthに追加。Agnusのslot/CPU/Copper競合・IRQ pipeline、analog/LEDfilter・実機/ROM互換はモデルに含めない。既存AMIGA-SOUND/Builtinは変更しない。

Windows/Linuxの通常・debug/graphics/extension除外・さらにfloat除外の6構成で各10検査群と補助10検査が成功。全256attach mask、全128volume値、512KiB全memory、固定PCM、6負荷の全32768frameを照合した。stereo部分書込みは実装置を開かないfixtureで非ゼロデータの4byte offset/全byteコピーを検証し、oddLEN3の位相resetも手計算・負の対照で補った。最終ClaudeレビューはHigh/Mediumなし。実聴成功とは区別する。

通常まとめ版はWindows約9.44倍、Linux約10.46倍、変調負荷は約5.52/6.44倍。音源単独の宣言範囲をForthで維持する採否で、Amiga全体の性能ではない。辞書増加549616byte（512KiB memoryと24KiB queueが中心）、本体実行ファイルの増加0。再開時はGit/tqueとJSONのLF指紋を照合する。

Mac側は1147でverify-paula.py/verify-paula-stream.pyの通常/除外・全PCM照合、サイズと速度、生成音のstereo実聴・中断と回収を実施し、OS/CPU/版と結果を記録する。既存PCMのMac1130完了とは別。PCM実聴は998→1133→Windows1148/Linux1149、SID/NESのMacは1136→1143/1132→1144に残す。次の実装はAtari ST1138の既存レジスタ経路の充足・不足監査。以下は各時点の履歴。

PCM実聴1133は、Windows1148とLinux1149の子タスクに分割した。両方とも未完了・0%。OSごとに実装置の確認と実聴結果を記録し、両方が済むまで親1133を完了にしない。

## 最新追記：実機確認を各機能の配下へ移動（2026-11-20）

利用者の「最後にまとめないで」に従い、1057の末尾へ集約していた未確認を移動した。1133（Windows/Linux PCM実聴）は998 PCM配下、1143（Mac SID）は1136 SID配下、1144（Mac NES APU/DMC）は1132 NES配下で管理する。確認を残す親998/1136/1132は未完了へ戻し、実装・検証済みの子タスクは完了を維持した。依存先は完了済みの実装・受け入れ項目へ付け替え、子から親への循環依存を避けた。

現在は998=auto85%、1136=auto66%、1132=auto66%、999=auto33%。均等平均であり、実装を取り消した意味ではない。3件は着手可能で、他機種の実装を待つ条件はない。Mac確認を残して次の実装へ進めることと、確認自体を最後の工程へ移すことは区別する。以下の1136/1132/998完了や999=42%等は、確認タスクを各機能へ戻す前の記録。

## 最新追記：SID1136の決定的モデル・実測・採否完了（2026-11-20）

mainは8eff166（NES/DMCと対象修正までpush済み）。今回のSID差分は未コミット。1141/1142/1136を完了し、999は7枝の均等平均auto42%になった。6581/8580のアナログ再現やROM互換の完了ではない。既存C64-SOUND/Builtinを変更せず、宣言したレジスタ/ADSR/波形・時刻指定と独自Q16フィルターをForthで維持する。

[SIDの契約・制限・実測](SID_FORTH.md)、[レビュー評価と原文](reviews/1136-review-response.md)、[全測定・ソース本文](measurements/2026-11-20-sid.json)を参照。Windows/Linuxの通常・debug/graphics/extension除外・floatも除外した6構成で各12検査群成功。5負荷すべて32768frameの全PCM/終了状態をPythonと照合し、7processずつ測定した。最終ClaudeレビューはHigh/Mediumなし。Windows通常約2.53倍、重い混在約1.03倍。単独音源でも余裕が小さく、C64全体の実時間性を立証していない。辞書増加41688byte、本体実行ファイルの増加0。

Mac上のSID例、生成波形の実聴、実機/ROM照合は未確認として残す。既存PCMのMac1130は完了済み。次はAmiga Paula1137の再現範囲・DMA/IRQ契約を資料と照合し、既存近似を調べてForth側の試作へ進む。Atari ST1138、対象一覧の先行照合1139、依存付き最終採否1140も未完了。以下の28%等とSID未着手は各時点の履歴。

## 最新追記：DMCと5声モデル・採否1135/1132完了（2026-11-20）

mainは816129a（汎用試作までpush済み）。4声/DMC・対象一覧修正の今回の差分は未コミット。DMCのreader/buffer/DAC/loop/IRQ、専用32KB map、非線形5声混合と8kHz直接DACをForth側に追加し、1135とNES1132のモデル・実測・採否を完了した。定義したzero DMA-delayのAPU単独の範囲はForthに維持する。CPU/PPUや実機DMA/bus競合、ROM互換を完了した意味ではない。

[現行5声の契約・結果](NES_DMC_FORTH.md)、[レビュー採否](reviews/1135-review-response.md)、[全測定・ソース指紋](measurements/2026-11-20-nes-dmc.json)を参照。Windows/Linuxの通常/除外の4構成で回帰12+DMC8検査群が成功し、最終ClaudeレビューはHigh/Mediumなし。旧1134の生データは変更せず、当時のソース本文と固定出力SHAを保存した。Mac上の新しいNES例と生成波形の実聴は未確認。既存PCMのMac1130は完了済み。

999は7枝のauto28%。共通1131とNES1132が100、SID1136/Paula1137/ST1138/先行照合1139/最終採否1140は0で、工数比ではない。最終1140は機種別作業と照合に依存する。不足を見つけたら子タスクと1140の依存へ追加する。次はSID1136の資料・再現範囲の確定と実装/実測、または先行照合1139を進める。以下の21%/25%とDMC未着手は各時点の履歴。

## 最新追記：DMC実装・対象一覧の完了条件（2026-11-20、作業中）

NES DMC1135を実装・検証中。5声の現行契約は[NES DMCの記録](NES_DMC_FORTH.md)を参照。旧4声の拒否契約や測定は1134時点の履歴としてソース本文とともに保持する。

1139を先行照合、1140を最終採否へ分離した。1140はNES1132/SID1136/Paula1137/ST1138/照合1139に依存し、先に完了できない。不足が見つかれば機種別タスクと1140の依存へ追加し、分母が増えると均等平均の表示が下がる場合もある。現在999は7枝のauto21%で、DMC工程はまだ完了にしていない。以下の25%/6枝は1140追加前の履歴。

## 最新追記：音源の対象漏れ・進捗の修正（2026-11-20）

NESを最初に進める指示は、他機種を対象外にする決定ではない。999にC64 SID1136・Amiga Paula1137・Atari ST YM2149の充足/不足確認1138、および上位計画8機種の照合1139を追加した。SID/Paulaはレジスタ対応Forth実装・実測が未着手。Atari STには既存ST-SOUND/SOUNDのYM2149レジスタ経路があり、不足を監査して必要部分を進める。機種別一覧は[計画の対象表](EMULATOR_CORE_PLAN.md#音源の対象と現在状態999)を参照。

999はauto25%。共通試作1131=100、NES1132=50、SID1136/Paula1137/ST1138/対象照合1139=0の6枝を均等平均した表示で、工数や対応機種数の達成率ではない。旧75%はSID等が未登録だった時点の値で、現在進捗として扱わない。NESの測定結果から他機種の本体移行の採否を決めない。下の工程記録は各時点の履歴。

## 最新追記：NES APUのForth 4声試作1134（2026-11-20）

現在のmainは816129a（汎用合成1131までcommit/push済み）。利用者がNES APUを最初の機種に指定し、NTSC 4声のレジスタモデルと予定書込み、frame IRQ、まとめ処理をForth側に追加した。今回の差分は未コミット。1134完了、1132は50%。対象漏れ修正後の999は25%（子タスクの均等平均）。次は1135のDMCと残る互換性・負荷再測定。既存PCMのMac1130はdde0547で完了済みで、今回のNES例のMac実行は未確認。

[仕様・資料・測定と採否](NES_APU_FORTH.md)、[レビュー採否](reviews/1134-review-response.md)、[原データ](measurements/2026-11-20-nes-apu.json)を参照。4構成各12検査群が成功。1クロック版/まとめ処理版/Pythonの出力・状態を照合し、累計1024件で止まった予定表を未処理1024件と領域回収へ直した。Claudeの実装・文書再レビューまで反映し、High/Mediumの残件なし。

定義したNTSC 4声の範囲はForthに維持し、本体への追加は行わない。DMC/DMA、CPU/PPUの実行やバス競合、実機/ROM互換、生成波形の実聴、analog filteringは未確認・未実装として分ける。この結果をNES全体の実時間性能と扱わない。再開時はGit/tqueとJSONのソース指紋を照合する。以下は各時点の履歴。

## 最新追記：PCMのMac実機受け入れ1130（2026-11-20）

この節を最新状態とする。基点main `9d1c528`。macOS 27.2.1 / Apple M5でPCM06（1130）を実施し合格した。tqueの1130と親998を完了にした。core1124成功・host152成功、11構成、専用PTY、AudioQueue実装置での1000回開閉（fd/thread不変）・再生中終了50回、Ghosttyでの実聴（単独・左右・混合・破棄と再開・drain・保存アプリ）とCtrl+C中断を確認した。結果は[実装記録](PCM_PUBLIC_IMPLEMENTATION.md#mac実機受け入れ1130)。以下の「Mac実機1130は未完了」は当時の記録。LinuxのPulseAudio/ALSA実装置とWindowsの実聴は未確認のまま（tque 1133）。

## Forth音源の先行試作1131（2026-11-20、Mac受け入れ統合前の記録）

現在のmainは9d1c528（PCM公開語/host寿命/Windows/Linux確認までcommit/push済み）。その後999の先行子1131として、独自4声のForth合成・PCM送出例と検証/測定を追加した。今回の差分は未コミット。Mac実機1130は未完了で残す。

1131完了、999は50%。次は1132の機種別Forth音源・実測と採否判断。今回の汎用試作をNES/SID/Paulaの再現や本体移行不要の証拠とは扱わない。[試作仕様と結果](PCM_SYNTH_PROTOTYPE.md)、[Claude採否](reviews/1131-review-response.md)、[生データ](measurements/2026-11-20-pcm-synth.json)を参照。通常/除外のWindows/Linux各18検査群が成功。ClaudeのMedium試験不足2件を補強し、再レビューは解決済み・新しいHigh/Mediumなし。可聴確認はしていない。

999の着手依存は利用者の「Macを残して進める」指示に合わせ、1064と完了済み1129へ変更した。998全体と1130は完了にしていない。再開時はGit/tqueとJSONのソース指紋を照合する。以下は各時点の履歴。

## PCM公開語・Windows/Linux自動確認（2026-11-20）

この節を最新状態とする。基点mainは416caf9（PCM設計/内部までpush済み）。その後1127・1128・1129を実装/自動検証し、差分は未コミット。1128/1129はtque完了、親998は83%。Mac実機1130は未完了で残す。保存アプリのMac受け入れ1124/1069/1066はc822e53で統合済み。

[PCM公開語の実装・検証記録](PCM_PUBLIC_IMPLEMENTATION.md)、[Claudeレビュー採否](reviews/1128-review-response.md)、[測定一次データ](measurements/2026-11-20-pcm-public.json)を参照。7公開語、State所有、CLOSE中断時の再試行、完全復元busy/辞書追記保持、英日HELPを実装した。Claude最終静的レビューはHigh/Mediumなし。Windows/Linuxの22構成、専用console/PTY入力保持、core各1124成功、host162/167成功、zig build test、全参考書の照合が成功。可聴音・Linux実音声装置・Mac実機は未確認。

再開時はGit/tqueと最新JSONのソース指紋を照合する。以下の「未実装」「次は1128」等は各時点の履歴。次のMac受け入れは1130のタイトルと親998を再照合して進める。

2026-11-20追記：PCM設計/内部は416caf9でcommit/push済み。続いて音声host停止・回収1127を完了し、次は1128の公開語/所有管理。host差分は未コミット。Mac1130は未確認。[最新引継ぎ](CORE_EXTENSION_HANDOFF_2026-11-19.md)、[1127結果](PCM_HOST_LIFETIME_IMPLEMENTATION.md)を参照。

2026-11-20統合追記：c822e53の保存アプリMac受け入れを統合済み（1124/1069/1066完了）。PCMは設計1125・内部1126を完了し、次はhost寿命1127。PCMのMac1130は未実施。以下は各時点の記録。

2026-11-20追記：保存アプリは6512916でcommit/push済み。Mac1124を残し、PCM998の設計・内部リング1125/1126へ進んだ。次はhost寿命1127。[最新引継ぎ](CORE_EXTENSION_HANDOFF_2026-11-19.md)と[PCM実装範囲](PCM_STREAM_IMPLEMENTATION.md)を参照。PCM公開語/host回収は未実装、PCM差分は未コミット。

2026-11-20追記：保存アプリ起動基盤は設計・実装・Windows/Linux受け入れを完了し、Mac実機を残した。[最新引継ぎ](CORE_EXTENSION_HANDOFF_2026-11-19.md)と[実装・Mac手順](SAVED_APPLICATION_STARTUP_IMPLEMENTATION.md)を参照。サイズ/速度記録と起動機能は未コミット。

2026-11-19追記：本体拡張613の最新状態・未コミット実装・次工程は[613の引継ぎ](CORE_EXTENSION_HANDOFF_2026-11-19.md)を参照。以下の各節は記載日の記録。

更新日：2026-11-18。現在状態はこの文書、実装経緯は各フェーズ記録とgit履歴を参照する。tqueの表示番号は振り直されるため、再開時はタスク名と親子関係で照合する。

## 0.12.0のリリース準備（2026-11-18）

- 利用者指定で`VERSION`を0.12.0へ更新し、README・利用者マニュアル・デバッグ文書とソースコメントの表示例を合わせた。
- CHANGELOGの未公開の変更を0.12.0（2026-11-18）へまとめた。
- 実機での未確認事項は以下の記録を保持する。コミット・タグ作成・プッシュ・配布物作成は未実施。

## ネイティブウィンドウの3 OS共通化とフルスクリーン（#1005 / #1013 / #1014、2026-11-18）

### 現在の状態

- Windowsのウィンドウを3 OS共通の契約（[決定事項G3](DECISIONS.md)、[検討書10.10](NATIVE_WINDOW_STUDY.md)）に合わせた：画面ごとのDPI対応とDPIの違う画面への移動、`WINDOW-SIZE 0 0`を作業領域にも収める、作成の待ちを最大5秒、最近傍での描画、1文字単位の入力とCtrl+Cの優先、フォーカス喪失・閉鎖時のマウスの解放、`GUI-FIELD`のIME、自動表示の探索をTkと合わせて5秒。結果は[Windowsの受け入れ記録](WINDOWS_NATIVE_VALIDATION.md)にあり、物理キーボード・マウスでの確認も利用者が済ませた。
- `WINDOW-SIZE 0 0`の作業領域への収まりをmacOS（`visibleFrame`）とLinux（`_NET_WORKAREA`）にも入れた。計算は3 OS共通の`src/window_layout.zig`。macOSの描画矩形も同じ規則にした。
- フルスクリーン（[決定事項G10](DECISIONS.md)）：`FULLSCREEN`・`FULLSCREEN?`・`MOUSE-CURSOR`を、Windows・Linux（EWMH）・macOS（フルスクリーンのSpace）のウィンドウとTkのウィンドウに実装した。Windowsは利用者が実際のAlt+Enterで確認済み。LinuxはWSLgのXWaylandで確認済み（[Linuxの記録](LINUX_NATIVE_VALIDATION.md)の末尾）。**macOSは一度もMacで動かしていない**（クロスビルドとCodexのレビューのみ）。
- 組込み語`GFX-FULLSCREEN`・`GFX-FULLSCREEN?`・`GFX-MOUSE-CURSOR`を加えたため、これより前に`SAVE`した辞書イメージは`INVALID IMAGE`で拒否される。ソースから保存し直す。
- 各変更はCodexのレビューを受けて指摘を直してからコミットした。

### Macで行うこと（このWindows機ではできない）

準備：リポジトリのルートで`zig build`。

1. **フルスクリーン（tque「フルスクリーン受け入れ（macOS）」、#1019の子）**
   - Sigma自身のウィンドウ：`zig-out/bin/sigma tests/scripts/check-fullscreen.fs`
   - Tkのウィンドウ：`zig-out/bin/sigma -e "REQUIRE-GRAPHICS ALSO GRAPHICS DISPLAY-TK" tests/scripts/check-fullscreen.fs`
   - 期待：起動するとフルスクリーンのSpaceになり、端末に`fullscreen: 1`。Control+Command+Fで元のウィンドウに戻り`fullscreen: 0`、`key ...`の行は出ない。`F`で再びフルスクリーン、`W`でウィンドウへ、Enterだけではフルスクリーンのまま（`key 13`）、`C`で画像の上のカーソルが消える（タイトルバーの上では消えない）・もう一度で戻る、`Q`で終了。
   - あわせて：緑のボタンで入る・出ると`fullscreen:`の表示が変わること、フルスクリーン中にウィンドウを閉じると次の画像で再びフルスクリーンで開くこと、Command+Tab・Dockとの切り替え。
   - 見つかりやすい問題の候補（未確認）：フルスクリーンで開くとき一度通常のウィンドウを経由すること、Control+Command+Fがシステムの操作に先に取られること、透明なカーソルが表示されること。
2. **`WINDOW-SIZE 0 0`の作業領域（tque「0 0の作業領域制限の確認（macOS）」、#1023の子）**
   - `zig-out/bin/sigma tests/scripts/check-auto-size.fs`
   - 期待：320×200・1600×1200・4000×1000の画像が順に4秒ずつ出る。どれもウィンドウ（タイトルバーと枠を含む）がメニューバーとDockを避けて画面に収まり、円が丸いまま。
3. 結果は[macOSの受け入れ記録](MACOS_P10_VALIDATION.md)か新しい記録に、macOSの版・機種・画面の大きさと倍率とともに書き、tqueを完了にする。

### Linuxの#907レビュー修正（2026-11-18）

`WINDOW-SIZE 0 0`の上限を、Xineramaで特定した現在の画面と`_NET_WORKAREA`の交差で制限する修正を追加した。表示前はポインターの画面を使い、取得不能時は従来のデスクトップ全体へ戻る。回帰と制限は[Linuxの記録](LINUX_NATIVE_VALIDATION.md)の末尾。Linux実機の3画像表示は利用者確認と座標ログの照合で合格し、#1035を完了。#1032で発見したSigma自身のウィンドウの位置復元とTkのカーソル切替を修正。実デスクトップの自動再テストと利用者の物理操作による再確認が成功し、#1032も完了。結果は同じLinuxの記録の末尾。

### Linux実機確認（#1032・#1035は2026-11-18に完了）

以下は確認に使用した手順。Ubuntu 26.04.1 LTS／GNOME Shell 50.1／XWaylandで完了し、結果と制限は[Linuxの記録](LINUX_NATIVE_VALIDATION.md)の末尾を参照。他環境での確認済みを意味しない。

準備：リポジトリのルートで`zig build`（X11ウィンドウは既定で有効）。ウィンドウマネージャーのある実際のデスクトップで行う。

1. **フルスクリーン（tque「フルスクリーン受け入れ（Linux）」、#1019の子）**：手順と期待する結果は[Linuxの記録の「物理キーボードでの確認手順」](LINUX_NATIVE_VALIDATION.md)にある。解除キーはAlt+Enter。Sigma自身のウィンドウとTkのウィンドウの両方で行う。
2. **`WINDOW-SIZE 0 0`の作業領域（tque「0 0の作業領域制限の確認（Linux）」、#1023の子）**：`zig-out/bin/sigma tests/scripts/check-auto-size.fs`。ウィンドウ（枠を含む）がパネルを避けて画面に収まること。WSLgには`_NET_WORKAREA`がなく、仮の値を設定してしか確かめていない。最初のウィンドウはウィンドウマネージャーの枠の大きさを知らないため、枠の分だけはみ出す場合がある（記録しておく）。
3. 結果は[Linuxの記録](LINUX_NATIVE_VALIDATION.md)に、ディストリビューションと版、X11かXWaylandか、ウィンドウマネージャーまたはデスクトップ環境の名前と版とともに書き、tqueを完了にする。

### どのタスクにも入っていない未確認事項

- Sigma自身のウィンドウが開けないとき、自動表示がTk・端末へ切り替わるかの実機確認（Windows）。普通の環境ではウィンドウの作成が失敗しないため、確かめる方法がない。試験用に失敗させるスイッチを加える案を利用者に示したが、加えるかは決まっていない。

## macOS AppKitウィンドウとIME（#917 / #975 / #922、2026-11-17）

### 現在の状態

- #975「GUI-FIELDのIMEを実機確認」と#922「macOS AppKit受け入れ」は完了し、全子の完了を確かめて親の#917「macOS」も完了にした（2026-11-17）。6章の8項目の結果は[検討書10.13の「#922追加確認」](NATIVE_WINDOW_STUDY.md#1013-macos作業計画912-913-922)にある。
- #922の確認で`src/host_window_macos.zig`の不具合を3件直した：親がシグナルで終了すると子とウィンドウが残る、閉じる操作と`SHOW`が重なると-265になる、後から起動した`wish`がウィンドウ用パイプを継承する。子の終了時に親がキー解放とマウス`-1 -1`を補う処理と、ウィンドウの題名（「FORTH/Sigma graphics」）も直した。このうち閉じる操作と`SHOW`の競合は、合成クリックの試験に加え、利用者が計算中に閉じて開き直ることを最終のビルドで確かめた。
- Codexのレビュー（[原文](MACOS_WINDOW_CODEX_REVIEW.md)、[対応](MACOS_WINDOW_REVIEW_RESPONSE.md)）を受け、入力キューとパイプが満杯のときにキー解放とマウスボタンの変化を失わないよう直した。修正後のビルドでも、利用者の操作でIME、ホイールの通知、計算中に閉じたウィンドウの再表示を確かめた。
- 利用者の決定（2026-11-17）：macOSでは初回の`SHOW`でウィンドウが前面になりキーの入力先になる動作を仕様とする（決定G3の追記）。
- `GFX-AUTO-DISPLAY`・`GFX-AUTO-DISPLAY!`を`definitions`の末尾側（IME用2語の前）へ移した。直前のリリースで保存したグラフィックス辞書は`INVALID IMAGE`で拒否されるので、ソースから保存し直す。
- CHANGELOGの`[Unreleased]`に、macOSのネイティブウィンドウ、`DISPLAY-AUTO`、`GUI-FIELD`のIMEを追記した。版番号は変えていない。
- 修正後に`zig build`、`zig build test`、`-Dgraphics=false`、`-Dfiles=false`、x86_64 macOS／Linux muslのクロスビルド、`python3 scripts/word-reference.py --check --sigma zig-out/bin/sigma`、`python3 scripts/check-docs.py`（指摘0件）、`git diff --check`が成功。
- 利用者の操作による確認用に`tests/scripts/check-window.fs`を追加した（物理マウス、入力待ち中・計算中の移動・リサイズ・閉じる操作）。

### 確認の対象外とした項目

- 外部ディスプレイでの画面間移動と倍率の違う画面、SSH経由（GUIが使えない場合）の自動選択：この環境では試せず、利用者が対象外と決めた（2026-11-17）。未確認項目としてtqueへ登録しない。
- x86_64のMacがなく、x86_64はクロスビルドの成功だけ。従来どおり確認項目にしない。
- 性能は測定値の記録にとどめ、合否を付けていない。

### 既知の確認結果

- スクロールの慣性：トラックパッドを弾いた後の分も通常のホイール通知として届く（利用者の操作と端末ログ）。
- 実表示の描画回数：診断用ビルドで、毎秒30回の描画を5120×2880の画像まで保ち、6400×3600では毎秒約25回だった。描画は毎秒60回が上限。数値は検討書10.13の「実表示の描画回数」。
- IME（#975）：インライン表示、候補位置、確定のUTF-8、取消、空の変換・フォーカス喪失後の入力が合格。
- 物理マウス：左右ボタンの押下・解放とホイール上下を端末ログで照合した。
- 0.11.2で`SAVE`したグラフィックス辞書（`SIGIMG46`）は、今回のビルドで`INVALID IMAGE`として拒否される（組込み語が4つ増えABI署名が変わったため）。ソースから保存し直せば読める。
- 署名・公証は#922の受け入れ対象から除外した。インストーラーの作成・署名・公証・Gatekeeper評価は実施しない。
- 仕様と受け入れ条件の詳細：[ネイティブウィンドウ検討書 10.13](NATIVE_WINDOW_STUDY.md#1013-macos作業計画912-913-922)、IME実装経緯：[10.9〜10.12](NATIVE_WINDOW_STUDY.md#109-共通仕様の推奨案2026-11-17tque-909の検討)。

## GitHub ActionsのEKEY最適化失敗の修正（2026-11-15）

`v0.11.0`の[Release実行](https://github.com/fukuyori/ForthSigma/actions/runs/43675216095)で、Windows・Ubuntuの`-Dcpu=baseline -Doptimize=fast`におけるP06a入力切替とEKEY UTF-8の2件が失敗。テストスクリプト移動前のコミット`4802167`で発生した。

公式配布のZig 0.17.0を`.work/ekey-ci/`へ取得し、公式indexのSHA256と照合。macOS arm64でも同じ2件を再現した。診断ログでは`{195,169}`等の入力バイトが正しいのに、デコード結果が233ではなく195となる。最小再現でも符号付きi64からu8への直接`@intCast`を含むUTF-8デコードが失敗し、0.17.1では成功した。0.17.0のLinux x86_64向けLLVM IRでは当該変換に`trunc nuw nsw`が付き、符号なしセルを経由する修正後は`trunc nuw`となることを確認した。

`src/core/event_input.zig`のイベント→バイト変換を符号なしセル経由の共通ヘルパーへ変更。Checkedビルドの範囲検査は維持する。EKEY?経由の1〜4バイト境界、不正・不完全UTF-8、後続KEYバイト保持の回帰を追加した。語義・仕様の変更はない。生成リファレンスのEKEY?使用例は新しい回帰テストの抜粋へ更新され、英日で参照先を確認してソース指紋も更新した。

Zig 0.17.0の修正後fastテストは1063成功・7 skip（コア1001成功・5 skip、ホスト62成功・2 skip）。Linux x86_64向けEKEYテストのクロスコンパイルも成功。Zig 0.17.0の通常テストも1063成功・7 skip、fast実行体のビルド、EKEYパイプ・POSIX PTY、P10統合37件が成功。文書チェック指摘0件。クロスコンパイルをWindows/Linux実機の実行結果と混同しない。証跡は`.work/ekey-ci/`の`before-0170-fast.log`・`diagnostic.log`・`cast-{before,after}.log`・`cast-0171.log`・`after-0170-fast.log`・`ir-cast-comparison.txt`と生成IR。利用者から既存`v0.11.0`タグの削除、修正のコミット、同名タグの再作成とpushを明示指示された。EKEY修正はCHANGELOGの0.11.0へ含める。公開コミットとタグの実際の状態はGit履歴・リモートを照合する。Actionsの修正後結果は別途確認する。

## テストスクリプトの配置変更（2026-11-15）

`test-*`・`verify-*`・`probe-*`と`gforth-p00/`の99ファイルを`tests/scripts/`へ移動した。実行は引き続きリポジトリルートから行う。呼出し元・文書のパスとテストのルート解決・importを更新。生成・ビルド・配布・ベンチマーク本体と文書チェックは`scripts/`に保持する。[実行例と区分](../tests/scripts/README.md)を参照。測定JSONのハッシュ対象パスと外部レビュー原文は当時の記録として保持する。

移動後にPython97ファイルの構文、リファレンス回帰5件＋動作19件、署名スクリプトのモック9件、行編集18件、P10統合37件、ランタイム13件、debug除外マトリックスの単体・ビルド・統合36件を確認して成功。文書チェック指摘0件。Linux専用ベンチマークテストはimportのみ確認し、Gforth比較・Windows専用試験は再実行していない。証跡は`.work/script-move/`。

## バージョン更新（2026-11-15）

利用者指定で製品バージョンを0.11.0へ更新し、チェックリストの表示例・ログ例・変更履歴・開発記録を更新した。過去の測定記録は変更しない。パッケージ・タグは作成していない。

2026-11-17、利用者指定で製品バージョンを0.11.1へ更新し、同じ箇所を更新した。各OSのデバッグ機能の出力の記録（`tests/scripts/debug-outputs`）は0.11.0で記録したもので、変更していない。

同日、利用者指定で製品バージョンを0.11.2へ更新し、同じ箇所を更新した。0.11.1の後の変更は `GFX-TCL` の説明だけで、動作と辞書ABIは変わらない。

## macOS P10検証と計画542の完了（2026-11-15）

macOS 27.2 arm64・Zig 0.17.1で、`16945a5`を対象に通常版・8単独機能除外版のビルド・単体・P10統合・構成間保存読込を実行し、計312件が成功した。通常単体は1062成功・7 skip。ランタイム13件、文書チェック指摘0件、実行時辞書照合・標準キー35件・出力例28件・使用例132件も成功。[macOS P10検証](MACOS_P10_VALIDATION.md)に環境・件数・実行方法を記録。証跡は`.work/p10/macos/`。

`verify-feature-matrix.py`に`--platform macos`を追加した。アプリケーション実装・版番号の変更なし。tqueをコマンドで照会し、752 → 742 → 553 → 542の順に全子の完了を照合してdoneにした。最後に542配下すべてがdone・auto100%であることを再照会した（`tasks-before.json`・`tasks-after.json`）。コミット・タグ・pushは行っていない。

今回のP10残作業は完了。VM速度改善は計画・レビューのみで試作未実施のまま。次の実装に自動着手せず、利用者の指示に従う。以下の過去の未完了記述は当時の記録であり、現在状態はこの節を優先する。

## Linuxネイティブ追加確認と元作業ツリーへの統合（2026-11-15）

利用者の#553のLinux確認依頼により、`9d26340`を基準とする別作業ツリーで実施。通常版・8単独機能除外版のLinux版Zigビルドランナー、P10計312件、境界482件、PTY/FIFO24件、POSIX統合10件、ランタイム13件、文書チェックが成功。詳細・証跡は[Linux P10検証](LINUX_P10_VALIDATION.md)。tque #754はdone・auto100%。macOS実機の#752は未実施のまま残し、#742・#553・#542を完了にはしない。

その後の利用者の統合指示により、元の`/home/fuk/source/zig/ForthSigma`を`9d26340`へfast-forwardし、Linux検証の修正・文書・`.work/p10`の成果物を反映した。元の未コミットCATCH変更はstash「Preserve pre-integration CATCH changes 2026-11-15」と`/tmp/ForthSigma-catch-before-integration.patch`に退避。最新mainに別実装のCATCH再帰対策があるため古い本体差分は重ねず、元の深い再帰・SYNONYM/EXECUTE/DEFER・上限捕捉・ローカル復元の回帰テストを追加保持した。

`verify-feature-matrix.py`へLinux直接実行を追加し、glibcで不定となるシグナルマスク予約領域の比較をテストから除いた。日本語説明への影響なしと確認しソース指紋を更新。今回の変更には検証基盤・回帰テスト・記録を含む。統合後は1063件成功・6 skip、通常ビルド・P10統合37件・文書チェック指摘0件。参照行番号も更新した。別worktreeの全変更と検証成果物を元フォルダーに保持し、別worktreeは削除済み。詳細はLinux P10検証記録を参照。

## VM速度改善の計画・レビュー

利用者の依頼で[速度改善計画](VM_PERFORMANCE_PLAN.md)を作成した後、Claude Codeへレビューを依頼し、指摘をソースと照合して改訂、限定的な再確認まで完了した。[採否と結果](VM_PERFORMANCE_REVIEW.md)、[初回原文](VM_PERFORMANCE_CLAUDE_REVIEW.md)、[再確認原文](VM_PERFORMANCE_CLAUDE_FOLLOWUP.md)を別々に保存。モデル表示claude-sonnet-5-5、実際のツールは初回Read/Grep計10回・再確認計5回で、コマンド・編集はない。再確認は「重大な残存問題なし、条件付きで安全な実験計画」との結果で、改善を保証するものではない。

計画は、同一バイナリーA/Aと生成コードを確認した後、Runningを値で渡して局所保持する小規模案を最初に検証する。無条件の外側書戻しを削除し、エラー時PC・全ヘルパーの状態更新・CATCH復帰を維持する。停止検査の移動は全副作用境界を示せる場合だけ。境界退出方式へ自動的に拡大せず、VM複製・機能削除・JIT・アセンブラーは見送る。CATCH専用測定、サイズ各1%以内、メモリー容量を増やさないことも基準にした。

続いて利用者の指示でagy CLI 1.5.9にもレビューを依頼し、Gforth固定版c479e1eのengine・threaded・prim・exceptを[参照調査](GFORTH_VM_REFERENCE.md)へ整理した。[agy報告](VM_PERFORMANCE_AGY_REVIEW.md)と[採否](VM_PERFORMANCE_REVIEW.md)を保存。実際の履歴はread_file 14回・13ファイル、SUCCESS。モデル名は結果に明示なし。コマンド・編集のツール呼出しはなく、ソースハッシュも照合した。CLIのplan指定はslash禁止との併用で無効警告があり、実際はrequest-reviewだったため、plan強制とは扱わない。

agy指摘は、CATCH成功用0の容量不足＋外側CATCHなしでの失敗PC／バックトレース、BYE時の全継続解除、外側・内側resumeCatchの状態引渡し、δ_iの分母固定などを反映した。生成コードで過剰な展開が確認できた場合だけ、例外ヘルパーの非インライン化・cold配置を試すA2も追加。Gforthの局所状態・例外境界の考え方を参考にするが、GPLコード転用・生スタック混在・computed goto・TOS全面キャッシュは行わない。改善率の保証はなく、指摘反映後の追記全体を再レビュー済みとも扱わない。

原因調査の[根拠データ](measurements/2026-11-15-vm-diagnosis.json)も共有用に保存。f1140c7全体の変更で整数演算+59.0%、LOOP+37.9%を再現したが、個別の生成命令の原因は未特定。改善案の試作・A/A校正・新たな生成コード調査はまだ行っていない。本改善計画のtque登録・完了操作も未実施。測定・計画・レビューの文書と根拠データは、測定器テストの修正とまとめて記録する。

## 最新の測定結果

2026-11-17、利用者の指示で[サイズ測定・速度比較](SIZE_SPEED_MEASUREMENT.md)を同じ条件で取り直し、[生データ](measurements/2026-11-17-size-speed.json)を保存した。対象はSigma 0.11.0、`f1d641c`のアプリケーション実装。12構成のビルドと起動確認・機能除外の確認が両OSで成功した。通常版はWindows 1,809,408バイト、Linux musl 1,891,456バイト（前回比+2,560、+3,456バイト）。グラフィックス・浮動小数点なしはWindows 1,110,528バイト、Linux 1,139,040バイト。速度はWSL2のCPU0で8カーネルを各1億反復・7回測定し、全チェックサムが一致した。CPU時間の中央値比の幾何平均は、SigmaがGforth 1.0.2通常版の2.59倍、fast版の7.46倍。Sigmaの所要時間は前回比で8項目すべて短くなり、15.8〜34.9%、幾何平均25.7%の短縮だった。2時点の実行体全体の比較であり、個々の変更の寄与は分離していない。実表示・音声再生、Windows版の速度は未確認。以下は前回の記録である。

2026-11-15、利用者の指示で[サイズ測定・速度比較](SIZE_SPEED_MEASUREMENT.md)を実施し、[生データ](measurements/2026-11-15-size-speed.json)を保存した。対象は`50e661e`のアプリケーション実装。Zig 0.17.0、fast・baseline CPU・stripでWindows/Linuxの通常・浮動小数点なし・グラフィックスと浮動小数点なし・グラフィックス単独除外・サウンド単独除外・最小の12構成をビルドし、各起動確認が成功した。通常版はWindows 1,806,848バイト、Linux musl 1,888,000バイト。利用者指定のグラフィックスなしはgraphics=falseとfloat=falseを同時指定し、Windows 1,107,968バイト、Linux 1,135,488バイト。追加構成の起動と機能除外も確認済み。 グラフィックス単独除外はWindows 1,554,944バイト、Linux 1,646,240バイト。サウンド単独除外はWindows 1,724,416バイト、Linux 1,791,576バイト。両単独除外で浮動小数点の動作を確認。サウンド単独除外では画像生成も成功した。浮動小数点だけを外した構成の整数描画・画素読戻しも両OS計4ケース成功。実表示・音声再生は未確認。

速度はWSL2のCPU0で8カーネルを各1億反復、ウォームアップ1回を除外して7回測定し、全チェックサムが一致した。起動・コンパイルを除いたCPU時間の中央値比の幾何平均は、SigmaがGforth 1.0.2通常版の3.50倍、fast版の10.06倍。実用全般の速度ではなく、旧表からの性能退行とも断定しない。旧Gforth 0.7.9はlibgfdisasm2.la欠落で起動失敗し除外。環境やインストールは修復していない。

測定器のテストがPythonへ非対応の-eを渡していたため、`tests/scripts/test-benchmark-runtime.py`のテスト用起動方法を修正し3件成功。測定本体・アプリケーション実装は変更していない。記録対象は測定レポート・生JSON・改善計画・レビューと採否・索引・実装ノート・本引継ぎ・上記テスト。実行体・ビルドログ・事前試行は`.work/measure-20261115/`。

## 直前の見送り検討と公開記録

利用者の最終方針は「システムが巨大になるなら見送る」。582（アセンブラー8語）、583（TRY系5語）、584（Gforth固有ブロック拡張9語）は、この方針に基づき対応を見送った。各タスクは「対応要否の検討」を完了したもので、機能を実装したという意味ではない。利用者の指示で結論をタイトルへ記載し、3件ともdone・auto100%を今回再照会した。当初の584→583という実装案は採用しない。具体的な用途と新たな指示がない限り実装を再開しない。

ワードリファレンスの作成・実装照合・Claude Codeレビュー修正は`7b9e4dd`へ、582〜584の見送り記録は`50e661e`へコミット・push済み。今回の測定後にもorigin/mainの実際の先端が`50e661e9758cf41234da84946204930bb09a09af`であることを照合した。次の4文書はその公開記録であり、未追跡ファイルではない。

| ファイル | 公開時の変更 | 内容 |
| --- | --- | --- |
| `docs/GFORTH_ASSEMBLER_REVIEW.md` | 新規追加 | 582の8語を見送る理由、VM・ABI・保存・寿命管理への影響 |
| `docs/GFORTH_DEFERRED_WORDS_REVIEW.md` | 新規追加 | 583・584の検討、最終の見送り判断、検討完了の記録 |
| `docs/GFORTH_WORD_PHASES.md` | 更新 | 582〜584の結論と検討書への参照 |
| `docs/HANDOFF.md` | 更新 | 本引継ぎ |

検討書2件も含めて公開済み。

次に残る実装計画側の確認はmacOS実機のP10検証（今回752）。今回の再照会では742がtodo・auto90%、親553がtodo・auto95%、計画542がtodo・auto99%、752がtodo・auto0%。753「すべてのワードの説明をドキュメント化する」はdone・auto100%。582〜584は542の外にある検討項目であり、完了にしてもP10・542の完了にはならない。

見送り検討時の作業は静的調査、文書編集、tqueの更新・再照会で、その段階ではビルド・実行試験は再実施していない。その後に行ったサイズ・速度測定は冒頭のとおり。以下のOS別件数や全ワードの実行確認は、前の実装・検証で得た記録であり、今回すべてを再実行したという意味ではない。

## 現在状態

- 582は機械語実行・CPU/OS別ABI・保存と寿命管理への影響から、規模を抑える方針に基づき8語とも対応を見送ると決定。[アセンブラー対応検討](GFORTH_ASSEMBLER_REVIEW.md)に記録し、利用者の指示でtqueのタイトルへ結論を記載。検討完了としてdone・auto100%を再照会した。実装変更はなく、実装完了を意味しない。

- 583・584は、利用者の「システムが巨大になるなら見送る」という条件に基づき全面対応を見送った。利用者の指示で結論をtqueのタイトルへ記載し、検討完了として両方done・auto100%を再照会。実装完了ではない。VMの例外継続とブロックファイル管理への影響を[対応検討](GFORTH_DEFERRED_WORDS_REVIEW.md)に記録。当初の実装順案を再開指示として扱わない。

- 「すべてのワードの説明をドキュメント化する」（今回照会時753）は完了(auto100%)。[全ワードリファレンス](WORD_REFERENCE.ja.md)と[読み方・使用例](WORD_REFERENCE_GUIDE.ja.md)を英日で作成。全1,503項目に日本語説明・使用例・注意点を収録。全7語彙の実行時辞書1,463項目と構文・ローカル宣言40項目を照合し、記載漏れなし。単独使用例132件と出力確認例28件、標準キー値35件が成功。`zig build test`も成功。翻訳元の変更・説明や使用例の欠落を検出するチェックを追加。実装照合・Claude Codeレビューの指摘を修正し、動作回帰19件と選択・指紋の回帰5件も成功。詳細と検証の限界は[収録・検証記録](WORD_REFERENCE_STATUS.md)と[修正・レビュー記録](WORD_REFERENCE_REVIEW.md)を参照。

- P10の742は作業中。追加確認749〜751はWindows・WSLとも通常37件＋8単独機能除外268件＋構成間イメージ読込7件、各OS312件が成功。通常版最終ビルドとHELP・英日文書整合も完了、文書チェック指摘0件。[P10実施記録](P10_IMPLEMENTATION.md)。macOSの752も今回完了（冒頭参照）。

- Windows確認は完了。通常1058成功・10 skip、最小582成功・457 skip、通常ビルド/freestanding、統合24件、追加境界378件、コンソール36件と既存ブロック/EKEY/ランタイム13件が成功。利用者のIME変換・全角/絵文字編集・表示確認も「ok」の回答で完了。tque537〜540・718・719とWindows専用確認はdone(auto)。[Windows検証記録](WINDOWS_VALIDATION.md)。
- Windows追加修正は既存ファイルのCRT属性保持とSYSTEM後のコンソールモード復元。WSL専用728〜741も今回すべて完了(auto)とし、全子の完了を再照会して607を完了にした。P10・542全体の統合条件は残る。[タスク対応表](PLATFORM_TASK_AUDIT.md)。
- WSL2 Ubuntuは最新ソースで通常1062成功・6 skip、最小586成功・453 skip、境界482件、PTY/FIFO24件、P01〜P03行列15,371件、CLI9件、EKEYのパイプ/PTY、SHOW PTY20件、POSIX統合10件等が成功。行編集18件の前回成功記録も維持。初期スタック1MiBでCLI/ランタイム/保存実行統合が成功。WindowsでLinux用にコンパイルしてWSLで実行した。指定Gforth比較・Linux版Zigのビルドランナーは今回の結果に含めない。[WSL検証記録](WSL_VALIDATION.md)。
- P00・S01・P01〜P09と依頼済みレビューは完了。P09は全50語、tque576・577・578・552・701が完了(auto)。P09レビュー修正は`a76d000`、追加examples・文書は`7ce9a4f`でpush済み。[実装記録](P09_IMPLEMENTATION.md)・[レビュー](P09_REVIEW.md)。
- 698も調査・修正・検証が完了(auto)。明示STDOUT書込みとSYSTEM/SH/エディタ実行後にSHOWが文字を上書きする問題を修正した。修正と本引継ぎは対応するコミットに含む（git履歴参照）。[修正記録](OUTPUT_ACTIVITY_FIX.md)。
- macOSの698修正時の検証は通常1061件通過（6 skip）、最小構成585件通過（453 skip）、freestanding確認、通常ビルド、半ブロック/SixelのmacOS疑似端末20ケース、P09b比較・エディタ・保存復元確認が通過。証跡は`.work/698-*`。Windows/Linux実機確認は含まない。
- tque階層121 → 415 → 542 → 553（P10）→ 742。742・553・542は今回done・auto100%。743〜754もdone（今回再照会）。Windows/Linuxの基礎確認607と引用符付きEDITORの702は完了。
- `docs/NATIVE_WINDOW_STUDY.md`と`examples/graphs.fs`・`graphs-tk.fs`および関連文書はコミット済み。ネイティブウィンドウの実装検討は後回し。

## 次の作業と進め方

- ワード説明の文書化は完了。追加・修正時は日本語説明と使用例も更新し、`python scripts/word-reference.py --check --sigma zig-out/bin/sigma.exe`で全件照合する。翻訳元が変わった場合は日本語説明を確認してから`--record-reviewed-sources`で元ソースの指紋を更新する。使用例の抜粋は、参照先の準備・期待されるエラーを含む文脈と区別して扱う。

1. P10のmacOS検証752と計画542は完了。再確認時は[macOS検証記録](MACOS_P10_VALIDATION.md)と`--platform macos`を使用する。VM速度改善の試作は未着手であり、次の作業は利用者の指示に従う。
2. Windows・WSL追加確認749〜751は完了。追加ケースの全構成再実行、WSL構成間イメージ読込、HELP変更後ビルド・文書整合を再び未実施扱いにしない。検証範囲と証跡は[P10実施記録](P10_IMPLEMENTATION.md)を参照する。
3. 作業が完了した時点で証跡を文書へ記録し、該当するtqueタスクをdoneにする。タスク名は作業内容だけとし、「実施済」「未実施」「残件」などの状態を付けない。状態は完了フラグ、進捗はautoで管理する。今回752・742・553・542は完了条件を確認してdone・auto100%にした。
4. P09追加の組込み語によるABI変更があり、以前のイメージは再作成する。698修正による追加ABI変更はない。HANDOFFは現在状態・次の作業・制約に絞り、詳細は各検証記録へ記載する。

## 再開時の成果物と実行方法

- 今回の測定・計画作成開始時のHEADとorigin/mainは`50e661e`。全ワードリファレンスとHELP修正は`7b9e4dd`、Windows/WSL変更は`eaf0fe1`、582〜584の見送り記録は`50e661e`で公開済み。今回の成果物は冒頭を参照。再開時は`git status --short --branch`とリモートの実際の先端を再照会し、既存変更を保持する。
- P10用スクリプト：`tests/scripts/verify-p10.py`（通常/除外版統合）、`tests/scripts/verify-feature-matrix.py`（8構成のビルド・単体・統合）、`tests/scripts/verify-p10-cross-build.py`（通常版→除外版の保存イメージ読込）。
- 既存除外版実行体：`.work/p10/windows/no-<機能>/bin/sigma.exe`、`.work/p10/linux/no-<機能>/bin/sigma`。機能は`float files help tools image graphics audio debug`。再実行前に対象ソースとビルド時点を照合する。
- 統合検証：`python tests/scripts/verify-p10.py --sigma <実行体> --disabled <除外機能> --output <JSON>`。通常版では`--disabled`を省略。Linux実行体はWSLからLinux側のパスで指定する。
- 構成間読込：`python tests/scripts/verify-p10-cross-build.py --default <通常版実行体> --matrix <.work/p10/windows または linux>`。WSLではWSL側のPythonから実行する。
- 証跡：`.work/p10/windows-default.json`、`linux-default.json`、両OSの`matrix.json`と構成別ログ、Windowsの`cross-build.json`、`.work/p10-docs.log`。`complete: true`と件数、実際のログを照合する。
- 今回は追加の実行検証まで完了。`.work/p10-refresh.log`と更新済みJSONが最新のWindows・WSL追加確認結果。最終ビルドは`.work/p10-windows-final-build.log`・`.work/p10-linux-final-build.log`、最終文書チェックは`.work/p10-docs-final.log`。

## 制約

- コミット・タグ・pushは、その依頼で明示された場合だけ行う。通常の実装継続からは推定しない。
- Windows/Linux確認は607配下で別管理し、パイプ/SH-GETは695、P06cは696。Windowsでの今回の確認範囲は上記記録を参照。freestandingビルド確認は実機実行ではない。
- 仕様や意図に不明点がある場合は実装前に問い合わせる。質問は通常のメッセージで行い、Queued follow-up inputsや専用質問ツールを使わない。比較用Gforth固有の不正アクセスや未定義動作は模倣しない。GPL実装コードを転用しない。
- 標準EKEYS（固定wid3）とGRAPHICSのキー値・検索順を混同しない。端末EKEY/EKEY?/KEY-IORのCtrl+Cは割込み(-28)、ファイル/パイプのバイト3は文字3。EKEY EOFは承認によりK-EOFへ変更済み（KEYは-262、KEY-IORは-512）。
- 辞書イメージはSIGIMG45/46/47。旧形式・不一致ABIは拒否する。アドレスは明示的な型付き登録で再配置し、生セルから推測しない。
- パッケージはスクリプト確認以外で作成しない。版番号を変える場合は[更新チェックリスト](version-update-checklist.md)に従う。
- リポジトリ外・外部データは利用者の許可ルールに従う。以前のセッションでは指定Gforth・tque・Gitリモート・依頼されたClaude Code／agyレビューへのアクセスが許可されていた。今回のセッションではtqueコマンドの使用を明示許可された。他の外部アクセス許可へ拡大解釈しない。
- `.work/`・`.zig-cache/`・`.zig-global-cache/`はGit管理外の検証成果物。clean/resetで破棄したりコミットへ混ぜたりしない。

## 検証と参照先

通常確認は`zig build test`と`zig build`。最小構成や追加検証は変更内容に応じて行う。同じ検証用ファイルを使うテスト同士は同時実行しない。比較前には実行体をビルドする。

指定Gforthはコミット`c479e1eec66dd57a2441c3020177267ba70d3bdc`の`.work/gforth-audit/gforth-build/`（Gforth1.0.1、GCC16再構築）。ローカル成果物がない場合は、過去の実測を実施済みと推測しない。

- [基本仕様・比較方針](GFORTH_P00_SPEC.md)、[フェーズ表](GFORTH_WORD_PHASES.md)、[決定事項](DECISIONS.md)
- [S01レビュー](S01_REVIEW.md)、[P01レビュー](P01_REVIEW.md)、[P02記録](P02_IMPLEMENTATION.md)、[P03記録](P03_IMPLEMENTATION.md)、[P04記録](P04_IMPLEMENTATION.md)
- [P05記録](P05_IMPLEMENTATION.md)・[レビュー](P05_REVIEW.md)、[P06記録](P06_IMPLEMENTATION.md)・[レビュー](P06_REVIEW.md)、[P07記録](P07_IMPLEMENTATION.md)、[イメージ形式](IMAGE_FORMAT45.md)

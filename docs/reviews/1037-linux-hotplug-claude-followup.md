静的レビューの結果です。読んだのは固定スナップショットの2ファイルと、依存先の `linux_x11_test_support.py`、`graphics.fs` の語定義だけです。編集やコマンドの実行はしていません。物理操作の観測と試験の実行は、どちらもまだ一度もありません。

## 前回のM1〜M6の判定

| 項目 | 判定 | 根拠（スナップショットの行） |
|---|---|---|
| M1 | 元の問題は解消（ただし逆向きの誤りが残る。下のR1） | `incomplete` になるのは `AwaitingHardware`、`SystemExit`、`KeyboardInterrupt` だけです（320）。`AwaitingHardware` が出るのは `hardware_only` の待ちだけです（241-243）。Sigmaの無応答で起きる `TimeoutError` や、ソフトの状態が合わない場合は `fail` になります。 |
| M2 | 解消 | 再接続を確認したあと、10秒間すべてのサンプルで `consistent`、`returned_on_primary` であることをassertしています。サンプル数が3以上であることも確かめ、この段階をphaseとして記録しています（300-308）。 |
| M3 | 解消 | `on_monitor` は `0 <= index < len` と画面名の一致で判定します（245-248）。再接続後は、主画面の名前が元と同じであることも確かめています（297）。 |
| M4 | 解消 | 交差面積は `intersections` という別の変数になりました（219-221）。`raw_work_areas` が壊れることはもうありません。 |
| M5 | 解消 | 切断の条件にEDIDの消失が入りました（280）。再接続は、DRMの状態がEDIDのハッシュまで含めて最初と同じことを条件にしています（281）。`physical_evidence_limits` も記録します（170）。申告がない場合は `observed-awaiting-operator-confirmation`、`physical_hotplug_tested=False` になります（312-313）。 |
| M6 | 解消 | `0 ?DO` になりました（185）。 |

前回の軽微な指摘も、次のものは対応済みです：stderrの保存（56-62）、stdoutのEOFの期限（65-75）、中央の位置・大きさ・主画面の一致の確認（250-261, 297）、preflightで両方の画面へ移したあとのclose/reopen（268-276）。追加の検証スクリプトでは、no-operationは `incomplete` と `AwaitingHardware`、frozen-sigmaは `fail` と `TimeoutError` を期待し、止めたSigmaが回収されたことも確かめています（79-91）。

## 残っている中程度の問題

### R1. 操作者の手順違いやHPDの揺れが `fail` に分類される（verify 285-291, 231-243）
- **理由：** 切断を確認したあとの `disconnected-live` と `missing-preference-...` は、ソフトの状態の待ちです。条件には `disconnected(r)` が含まれています。
- 操作者が早めにケーブルを挿し直したり、DPのHPDが一瞬戻ったりすると、時間切れのときには `AssertionError` になり、製品の不具合（`fail`）として記録されます。
- 再接続を待つ間（293）は、こうした誤りを防げています。
- 前回提案した「時間切れのときにハードウェアの条件を確かめてから分類する」は実装されていません。
- **修正案：** `wait_for` が `hardware=` という述語を受け取るようにします。時間切れのとき、待ちの間に一度でもその条件が成り立たなかったら、`AwaitingHardware`（例：`'operator-sequence-violated'`）を出して `incomplete` にします。条件がずっと成り立っていたときだけ `fail` にします。

### R2. 再接続後の10秒間の観察で、一時的な不一致1回だけで `fail` になる（verify 302-305）
- **理由：** `sample` はSigmaのSNAPを読んだあとにX11を読みます。その間にデスクトップが構成を適用し直すと、`consistent` が偽になります。例として、再接続から数秒後に mutter が `_NET_WORKAREA` やパネルの位置を更新する場合があります。
- この時間帯は、M2で見張りたい時間帯そのものです。窓が動いていなくても `fail` になりえます。`reconnected(row)` にEDIDの読み直しの揺れが入った場合も同じです。
- 誤って合格になる方向の問題ではありません。ただし、物理検証をやり直すことになり、手間が大きくなります。
- **修正案：** 窓が副画面にあるかどうかは、Sigmaとは別にX11の位置だけで判定します（`intersections` を常に計算します）。不一致が出たら、すぐにサンプルを取り直します。`fail` にするのは、X11で見て窓が副画面にあった場合と、不一致が続いた場合（例：連続3回）だけにします。

### R3. ケーブルの申告を、操作の前にコマンドライン引数で受け取っている（verify 43-44, 312-313）
- **理由：** `--operator-confirmed-cable` は実行を始める前に指定するフラグです。実際に何をしたかについての事後の申告になっていません。モニターの電源を切った場合でも、フラグがあれば `pass` / `physical_hotplug_tested=True` になります。
- 「エージェントは申告なしにフラグを付けない」という運用の約束を、コードでは守らせていません。
- **修正案：** 記録は常に `observed-awaiting-operator-confirmation` で終えます。そのあと、操作者が別の手順で申告します。例：TTYで入力を求める、または確認用の別コマンドで `report.json` に申告の文と時刻を追記して状態を `pass` にする。

## 軽微な問題（参考）
- **312-317：** 前回の軽微な指摘（行238）がまだ残っています。`physical_hotplug_tested` と `status` を、`finish` / `require_eof` より前に設定しています。そのあとで失敗すると、`fail` と `physical_hotplug_tested=True` が同時に記録されます。修正案：314-317の後ろへ移します。
- **284：** `electrical_disconnection_observed` は初期値（168）にないキーです。`electrical_disconnect_reconnect_observed` と並べて、初期値に `False` を入れます。
- **`centered` の範囲：** 調べているのはbaseline、preflight、再接続後の明示的な選択だけです。切断中の自動の移動、開き直したとき、再接続後の主画面では中央の位置を確かめていません。
- **62：** stderrは、片付け（プロセスグループの終了）より前に取得しています。終了したときのSigmaの出力は記録に入りません。

物理操作の観測はまだ一度もないので、tque 1336/1345 は未完了のままにしておくのが妥当です。

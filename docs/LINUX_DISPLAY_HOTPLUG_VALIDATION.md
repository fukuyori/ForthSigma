# Linuxの物理抜き差し確認（1336・1345）

2026-11-23。対象はGNOME/XWaylandの副画面DP-3（Dell 23インチ）。スクリプトは画面構成を変更せず、利用者による映像ケーブルの切断・再接続を観測する。ソフトウェアで無効にした画面を、物理切断の代用にはしない。

## 実行方法

最初に通常ビルドと事前確認を行う。出力先は毎回新しいディレクトリを指定する。

```sh
zig build
python3 tests/scripts/verify-linux-display-hotplug.py --preflight --output-dir .work/1037/hotplug-preflight-new
python3 tests/scripts/verify-linux-display-hotplug.py --output-dir .work/1037/hotplug-physical-new --timeout 240
```

1. 所有する320×200の窓を副画面へ置き、READYを表示する。
2. 「unplug」の案内後、副画面の映像ケーブルだけを抜き、再接続の案内まで待つ。主画面は接続したままにする。
3. スクリプトが、元の窓の生存と残る画面への移動を記録する。続けて窓を閉じ、取り外された画面への指定を保持したままSHOWし、残る画面へ開くことを確認する。
4. 「reconnect」の案内後、同じ画面のケーブルを接続する。
5. 新しく開いた窓が有効な主画面上に10秒間とどまること、明示的WINDOW-ONで大きさを保ち副画面の作業領域中央へ移せることを確認して終了する。

## 証跡と判定

- `/sys/class/drm/card*-DP-3/status`のconnected→disconnected→connectedを確認する。切断時にはEDIDが消え、再接続後のEDIDのSHA-256は最初と一致する必要がある。対象は接続中の副画面で、主画面を取り外す手順には対応しない。
- 同じSigmaプロセスでDISPLAYS、DISPLAY-RECT/WORK/SCALE/HZ、WINDOW-OPEN?、WINDOW-DISPLAY、WINDOW-CHANGES、WINDOW-PIXELS、FULLSCREEN?を記録する。
- 別のX接続からRandRのモニター名・矩形、WMの作業領域、所有窓の座標とサイズを取得し、Sigmaの値を照合する。対応する画面は最大交差面積で独立に求める。
- DRM・RandR・WMが順次更新する途中は一時的な不一致として採取を続ける。操作によるハードウェアの変化を待つ段階と、変化後のSigmaの状態を待つ段階を分け、各段階は条件が3回続けて成立してから進む。ソフト状態待ちの途中でハードウェアが変わった場合は、手順未成立としてincompleteにする。再接続後の保持では一時的な照合ずれを許容し、連続3回の不一致でfailとする。切断時はWINDOW-CHANGESの増加も確認する。
- `samples.jsonl`は採取のたびにflushする。最終結果は`report.json`へ保存し、物理操作待ちの期限切れと利用者の中断はincompleteとする。SigmaやX11の無応答、切断が観測された後の移動失敗などはfailとし、操作待ちに紛れさせない。SIGTERM/SIGHUPでも所有するSigmaと補助プロセスを回収する。

`--preflight`は、現在の2画面で所有窓の作成・選択・close/reopenと記録処理だけを確認し、`preflight-pass`・`physical_hotplug_tested=false`を記録する。物理操作がなければ1336・1345を完了にしない。

DRMのdisconnectedとEDID消失だけでは、映像ケーブルの切断・モニターの電源断・特権操作による強制切断を完全には区別できない。実際にケーブルを抜き差しする全電気的な遷移とソフトウェアの検証が成功しても、元の記録は常に`observed-awaiting-operator-confirmation`・`physical_hotplug_tested=false`とする。記録終了後、実際にケーブルを抜き差しした操作者から具体的な申告を受けた場合だけ、別の確認ファイルを作る。

```sh
python3 tests/scripts/verify-linux-display-hotplug.py --confirm-report .work/1037/hotplug-physical-new/report.json --operator-statement '副画面DP-3の映像ケーブルを抜き、同じ画面へ挿し直した' --confirmation-output .work/1037/hotplug-physical-new/operator-confirmation.json
```

これは実操作後の申告例であり、操作前に実行するものではない。確認ファイルには元JSONのSHA-256、申告文、確認時刻を記録し、元JSONは一切書き換えない。preflightや未完了の記録への確認は拒否し、確認ファイルも作らない。

## 記録機構の検証

```sh
python3 tests/scripts/test-linux-display-hotplug-recorder.py --output-dir .work/1037/hotplug-recorder-checks-new
```

[6ケースの確認結果](measurements/2026-11-23-linux-hotplug-recorder-checks.json)は全て成功。

- [preflight](measurements/2026-11-23-linux-hotplug-preflight.json)：両画面への選択、中央位置・サイズ、close/reopen、スタックと終了処理を確認。結果はpreflight-pass。
- [操作なし](measurements/2026-11-23-linux-hotplug-no-operation.json)：ハードウェアを変更せず10秒待ち、結果がincomplete・AwaitingHardwareになることを確認。
- [検証用Sigmaの無応答](measurements/2026-11-23-linux-hotplug-frozen-sigma.json)：所有するSigmaだけへSIGSTOPを送り、無応答をfail・TimeoutErrorとして記録し、停止したプロセスも回収することを確認。これは意図的に作った失敗を正しく検出する自己検査であり、製品の不具合を記録したものではない。
- 確認拒否3ケース：preflight、操作なしのincomplete、最適化モード（-O）では申告文を付けても確認ファイルが作られないことを確認。assertが無効な環境で誤合格にしない。

[Claude Code初回レビュー](reviews/1037-linux-hotplug-claude-review.md)のM1〜M6、再確認のR1〜R3を修正した。最終確認は中程度以上の実バグなし。[対応と全レビュー](reviews/1037-linux-hotplug-review-response.md)。

## 現在の状態

事前確認と記録機構の6ケースは成功。

2026-11-23の実機切断試行では、DRM disconnected・EDID消失、DISPLAYSが2→1、窓がDP-3→DP-2へ移動し320×200のまま生存することを観測した。しかしWINDOW-CHANGESが2のままで増えず、試験はfailになった。[失敗記録](measurements/2026-11-23-linux-hotplug-changes-failure.json)。これは意図的な無応答の自己検査とは別の、実機で検出した不具合である。

ConfigureNotifyのあとにRandRの一覧が更新されると、窓の寸法が同じままでは所属画面のキャッシュを更新できなかった。ウィンドウの接続でRandRの画面・CRTC・出力・リソース変更とrootの作業領域・デスクトップ変更を購読し、再照会と変更回数の更新を行う修正を追加した。イベントの判定、サイズも旧所属も変わらない場合の変更回数、関係ないroot属性によるキーリピートへの影響の回帰3件が成功。通常ビルドとzig build testが成功（変更したホストのテスト186成功・17skip、他はキャッシュ）。

先行の修正後試行は300秒内に再切断が観測されずincompleteだった。その後、以下の最終実機確認で全段階が成功し、操作者の事後申告まで記録した。[修正確認とレビュー対応](reviews/1037-linux-randr-changes-review-response.md)。倍率差は[混在倍率検証](LINUX_MIXED_SCALE_VALIDATION.md)、通常の配置は[WINDOW-ON検証](LINUX_WINDOW_ON_VALIDATION.md)を参照する。


## 最終実機確認：完了

利用者がDP-3の映像ケーブルを抜いた後に「nuita」、同じケーブルを挿し直した後に「刺した」と申告した。修正後の同じSigmaプロセスで、独立X11照合を含む全8段階が成功した。

| 段階 | DRM | DISPLAYS | WINDOW-DISPLAY | WINDOW-CHANGES |
|---|---|---:|---:|---:|
| 接続中の副画面 | connected | 2 | 1 | 2 |
| DRM切断を検出（X11は更新途中） | disconnected | 2 | 1 | 2 |
| 窓が主画面へ移り生存 | disconnected | 1 | 0 | 4 |
| 対象画面がないままclose/reopen | disconnected | 1 | 0 | 6 |
| 同じEDIDで再接続を検出 | connected | 2 | 0 | 8 |
| 再接続後の主画面上で安定 | connected | 2 | 0 | 14 |
| 10秒間、主画面上を維持 | connected | 2 | 0 | 19 |
| 明示的WINDOW-ONで副画面へ | connected | 2 | 1 | 20 |

開いている窓の内容サイズは全段階で320×200を維持した。明示的選択の後は副画面の作業領域中央に一致。DRMの接続状態とEDIDは最後に元へ戻り、モニター一覧・配置も最初と一致した。変更回数は構成通知の数であり、1回の再接続中に複数回増える。

- [段階ごとの要約と57個の抜粋サンプル](measurements/2026-11-23-linux-hotplug-physical-summary.json)：原記録とは別の派生要約。段階のsample番号は原記録の添字。
- [不変の原記録（gzip）](measurements/2026-11-23-linux-hotplug-physical.json.gz)：1361サンプル全件と実行ソース、実行体のSHA-256、終了時刻、stderrを保持。
- [操作者の事後確認](measurements/2026-11-23-linux-hotplug-operator-confirmation.json)：原JSONのSHA-256と利用者の実際の申告に結び付けた別ファイル。

元のJSONはスクリプトの直接出力で、observed-awaiting-operator-confirmationのまま保存した。gzipを解凍すると同一バイト列が得られ、そのSHA-256は操作者確認と要約のraw_report_sha256の両方に一致する。これを確認した上で最終合格とした。合成イベントの検査を物理試験の合格に読み替えてはいない。

1336・1345を完了にし、1333〜1336全件の完了を再照会して親1047も完了にした。1037全体は93%で、残る未完了の葉はWindowsの1344・1347（親1342）・1276。

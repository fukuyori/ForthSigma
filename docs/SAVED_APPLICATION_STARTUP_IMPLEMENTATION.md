# 保存アプリ起動基盤：実装と検証

2026-11-20。基点main `d9e88f2`、Zig 0.17.1、未コミットの作業ツリー。仕様1067・実装1068とWindows/Linux受け入れ1123を完了。Mac実機1124は未確認のため、受け入れ1069と親1066は未完了とする。

[採用設計](SAVED_APPLICATION_STARTUP_DESIGN.md)、[設計レビュー評価](reviews/1067-review-response.md)、[実装レビュー評価](reviews/1068-review-response.md)、[数値・構成・実行体とソースのSHA256](measurements/2026-11-20-saved-startup.json)。以前の[サイズ・速度測定](SIZE_SPEED_MEASUREMENT.md)は789420eの結果であり、この起動機能を含む測定ではない。

## 実装した動作

- image語群へ`APP-ENTRY! ( xt -- )`、`APP-ENTRY@ ( -- xt flag )`、`APP-ENTRY-OFF ( -- )`を追加。完成した実行可能なcolonを登録し、削除時に解除する。SAVE・完全復元は登録を保持し、追加読込みは追加先の登録を保持する。
- SAVESYSした実行体は復元後に起動語を一度だけ実行する。SOURCE等は空にし、空文字・空白・日本語・オプション風文字列を現在のargvとして渡す。起動語未登録の保存実行体は従来の起動を保つ。
- 先頭の`--sigma`だけがホスト制御の入口。`--sigma --no-app -- -e ...`で登録を解除せず診断起動できる。認識した埋込み画像の破損を通常起動へ落とさない。
- footerはSIGEND01を維持。新Builtinによって画像ABIは変わるため、以前の辞書画像はソースから保存し直す。実行体自身を読めることが起動条件となる。
- SAVESYSは同じdirectoryの排他tempへ書き、完全なfooter・flush・mode・closeの成功後に原子的に公開する。相対名・hardlinkを含む自己上書き、最終symlink/reparse point、非通常file、readonly既存先を拒否する。

Claude Codeの読み取り専用レビューを設計・実装と並行して依頼した。POSIXのprocess-wide umask変更、Windowsのdrive-relative一時パス、復元前後の診断準備順を見直し、限定再レビューで高・中の具体的欠陥なしとなった。原文・評価・採用設計は別文書として保存している。

## 実行結果

| 対象 | 結果 |
| --- | --- |
| Windows Debug core / host | 1097成功・10除外 / 151成功・12除外、失敗0 |
| Linux musl Debug core / host（WSL） | 1097成功・10除外 / 155成功・15除外、失敗0 |
| Windows `zig build test` | 成功（runtime・freestanding等を含む既存build test） |
| Windows/Linux ReleaseFast | 各11構成、合計22構成のビルドと公開プロセス試験が成功 |
| Mac aarch64 | core-check / host-checkのクロスコンパイル成功。実行していない |
| 全語参照 | 実辞書1805項目、HELP1591項目、文書例28件・個別例401件を照合 |
| 文書 | `python scripts/check-docs.py d9e88f2` 指摘0 |

11構成はgraphics/audio/extensionの8通りに、debug除外・files除外・image除外を加えたもの。image除外は3語不在と通常起動を確認し、別途、登録済み画像を付けたimage除外ホストが実行前に拒否することも確認した。

公開試験は生成実行体の一度だけの起動、空SOURCE、引数・容量エラー、prefixと起動回避、format/log、正常復帰・stack残り・BYE・QUIT・THROW、未登録の従来動作、再保存時のbase重複防止、自己相対名/hardlink/最終symlink拒否、CRC/ABI/root/footer破損拒否、所有temp回収を照合した。通常構成では日本語の保存先と実行体パスも成功。Windows/Linuxのreadonly既存先保持も成功した。権限・ACLの全組合せを実証したとは扱わない。

core試験で登録の失敗原子性・忘却/MARKER・ID再利用・画像往復と追加先保持・破損rootの適用前拒否・空SOURCEを照合した。host試験はbase/image/footer/flush/mode/close/publishの7段階の故障を差し替え、毎回既存出力がOLDのままであることを照合した。追加の実プロセスでは、復元した短い呼出しのtrace/profile/logとCLI StepLimitのstatus1も成功した。

Windows専用の非表示consoleで、NS待機中のCtrl+CはUSER INTERRUPT・status1・console mode復元、無限計算はOS終了3221225786を確認した。Linuxの専用PTYでは対応してstatus1・termios復元とSIGINTによる終了を確認した。暗黙のVM中断ポーリングは追加しておらず、通常の無限計算のOS終了時には後始末を保証しない。

表示・音・ゲームパッドの新しい実機確認は行っていない。既存資源のunit試験と終了経路の確認に留め、将来のPCM/フレーム/タスク資源との結合は1057で確認する。ACL全組合せ・敵対的なdirectory同時変更・電源断を保証せず、fsyncは追加しない。出力権限は新規fileのumask/directory継承規則を使い、旧出力先の独自ACLをコピーしない。

## 起動時間の参考値

ReleaseFast / cpu baseline / strip、1回warmup後15回。アプリ本体は空のMAIN。親Pythonから起動して終了までの全体時間で、2回の画像検査・復元・runtime準備・後始末を含む。旧版比較やinspect単独の費用ではない。LinuxはWSL上で、実行体は`/mnt/d`に置いた。

| 画像 | Windows中央値（範囲）ms | Linux中央値（範囲）ms |
| --- | --- | --- |
| 87,558 B | 6.363（5.971–7.259） | 13.538（13.087–14.361） |
| 8,476,166 B | 36.389（35.604–37.609） | 74.442（72.588–193.131） |

大きい方は8MiBをALLOTし、保存memoryを16Mにした。大量のcode/wordを持つ画像の探索時間までは代表しない。個々の生値と再現用補助ソースをJSONへ保存した。

## 再実行とMac実機1124

リポジトリrootで実行する。Python 3とZigが必要。まず通常構成で実行し、その後graphics/audio/extensionの8通りと`-Ddebug=false`・`-Dfiles=false`・`-Dimage=false`を別prefixへビルドする。

```sh
zig build test
zig build -Doptimize=fast -Dcpu=baseline -Dstrip=true
python3 tests/scripts/verify-saved-application.py zig-out/bin/sigma
python3 scripts/word-reference.py --check --sigma zig-out/bin/sigma
python3 scripts/check-docs.py d9e88f2
```

Windowsでは実行体に`.exe`を付け、別に以下を実行する。

```powershell
python tests/scripts/verify-saved-application-windows.py zig-out/bin/sigma.exe
```

Macでは上の公開試験が生成した実行体を実際に別プロセスで起動し、専用PTYのSIGINTも検査する。termiosは既存の実行制御試験と同様、kernelの入力状態PENDINだけを比較から除く。debug除外版は公開試験へ`--no-debug`、files除外版は`--no-files`を付ける。image除外は通常起動で3語不在を確認し、登録済み画像の自動起動を拒否することを確認する。

さらに実端末で、下の保存実行体を起動しCtrl+Cを押す。USER INTERRUPTとstatus1、次のshell入力・echoが正常であることを確認する。使用端末名・macOS版・機種・Zig版、実行コマンド、出力・終了コード・除外構成を記録する。実機未確認のまま1124・1069を完了にしない。

```sh
mkdir -p .work
zig-out/bin/sigma -e ": MAIN 5000000000. NS ; ' MAIN APP-ENTRY! SAVESYS .work/mac-wait BYE"
.work/mac-wait
echo $?
```

無限計算のOS終了確認は専用PTY試験が担当する。表示/音の物理操作や後続資源の結合を、このCLI受け入れ成功から確認済みと推定しない。

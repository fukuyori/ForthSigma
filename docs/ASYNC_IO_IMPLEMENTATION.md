# 非ブロッキングI/Oの実装・検証（639）

2026-11-19。[採用設計](ASYNC_IO_DESIGN.md)。1078の選択ファイル待機に続き、1091のupdate stream境界、1094の読取り、1095の書込みを実装した。Mac実機は1092（1078）と1096（新4語）に残し、639全体は未完了。

## 振り分けと実装

EXTENSIONにWAIT-FILES、READ-AVAILABLE、WRITE-AVAILABLE、WAIT-WRITABLEを登録。本体コアのwords_async_io.zigはメモリ・全IDの事前検査とoptional FileOps呼出しだけを担当し、StateへOS資源を追加しない。Builtinは末尾追加。hostのmain.zigにFileSlot・Decoder・stream方向・EOF・workerをまとめ、host_file_reader.zigがWindowsの64KiB受信/送信queueを所有する。workerはVMのメモリを参照せず、受付時のコピーとhost_wakeによる通知を使う。

Windowsは移行前のpipeもReadFileで読み、CRTの内部先読みを残さない。reader移行後の旧FILE/EKEYも同じqueueを使う。POSIXのpipeは生fd、通常ファイルはFILE。pollと一時O_NONBLOCKを使い、flags復元失敗時にも取得済みバイトを保持する。非seekableなFILE-POSITION等はESPIPE。1091は通常ファイルの読取り後にseekを入れ、Decoder保留がない場合とEOF probe後の書込みも正しい位置にそろえる。

登録ファイル・stderrの通常書込みは先行queueをdrainして直接書く。stdout移行後は従来出力も共通queueへ入れる。SYSTEM/OPEN-PIPE/Tcl起動前に標準出力・標準エラーをdrainし、stdin workerをpauseする。中断された明示closeは-516でIDを保持し再試行可能。終了時だけ、中断・エラー後の未配送分をキャンセルして回収する。pcloseの子プロセス終了待ち自体は643/1048の範囲。

## Claude Codeレビューの評価と反映

[設計原文](reviews/639-design-claude-review.md)、[実装レビュー原文](reviews/639-implementation-claude-review.md)を保存した。採否・反映は以下。

| 指摘 | 判断・反映 |
| --- | --- |
| 満杯queueでResetEventが停止通知を消す競合 | 採用。stopの設定・再確認・ResetEventを同じlock内で行う。満杯readerの100回pause/resumeと、相手が読まないwriterの停止を試験 |
| READ-FILE/READ-LINEの途中データ消失 | 採用。hostとcoreの両方で件数とiorを保持。prefixだけコピーして失敗した場合は未消費として残す。WindowsのCtrl+Cで2バイトと-516を実測 |
| native pipeで保留prefixをseekする | 採用。pipeのwrite前seekをなくし、位置APIはESPIPE。LinuxのOPEN-FILE R/W pipeでA/B往復を実測 |
| stderrの途中切れ・子プロセスと出力の逆転 | 採用。従来の診断は全量投入とdrain、起動前と従来stderr前のstdout drainを追加 |
| stdin共有object検査が書込み側にない | 採用。stdout/stderrからのworker移行でもstdin aliasを拒否 |
| close中断時にqueueとIDを破棄 | 採用。明示closeはIDを残す。終了時の破棄は例外として設計に明記。実Ctrl+CでIDの継続利用と再FLUSH/CLOSEを確認 |
| pause失敗後に停止threadを再利用 | 採用。次のstartでpauseを再試行。回収不能のstream/queueは解放せず保持 |
| CRの後の読取りエラーが消える | 採用。READ-LINEのiorに反映 |
| 成功0バイトReadFileをEOFと誤認 | Microsoftの一次仕様で確認して修正。pipeは継続し、broken pipe等でEOFとする。匿名pipeへの0バイトwriteの回帰も試験 |
| POSIX共有descriptionへのO_NONBLOCK影響 | 一時flagsの共有という制約を設計に明記。stdinのread-ready後のreadも非ブロッキング化 |
| 致命的終了でstdout queueが残る | defer順を再確認。closeAllFilesがruntime teardownより先に実行されるため、この経路の未回収という指摘は非該当。再レビューでも確認 |

統合再レビューと最終限定レビューのいずれもブロッカーなし。最終限定レビューの軽微な指摘（未移行stdinの0バイトpipe、通常FILEのCR直後エラー、設計段落の位置）も反映した。求められた終了契約とstdoutの扱いを設計へ追記した。その後の小修正は上表のCR・通常FILE部分件数・0バイトpipe・POSIX stdin・標準workerの停止を含む。

## 検証と再現

実機キーボード操作と区別し、Windows console試験は専用の非表示consoleへイベントを注入するfixture。ユーザーのアプリやキーボード状態を操作しない。

- Windows core 1075成功・8除外、host 116成功・11除外。runtimeとfreestandingを含むbuild test成功。
- Linux muslをWSL Ubuntuで実行：core 1075成功・8除外、host 125成功・9除外、runtime 15成功。Windows専用worker試験は除外。
- Windowsのfiles/extension/graphics/audio除外構成：core 702成功・381除外、host 108成功・15除外。Mac arm64はクロスビルド成功、実行は未確認。
- tests/scripts/verify-async-io-read.py：遅延2pipeの順序、EOF-ready、従来読取り→worker移行、不正な後続IDで先行データを消費しない、stdin先読み、到着済みデータの初回0 pollの5ケース。Windows/Linuxで成功。
- tests/scripts/verify-async-io-write.py：満杯時のtimeout→相手の読取りでready、受付後の呼出し元メモリ変更、legacy tailとの順序、別pipeの並行読取り、stdout順序、broken pipe、stderrの受付後の従来書込み（合計196608バイト）、stdout/stderr共有時のOUT→ERR順序。Windows/Linuxで成功。Windowsは非同期エラーをFLUSHと後続write/closeで報告。POSIXはwrite時のEPIPEを返し、空のFLUSH/closeには未配送queueがない。
- tests/scripts/verify-async-io-stdin-spawn.py：親のstdin readerを移行後にSYSTEMで子を起動し、子へ遅延した次のバイトを渡せること、親の再開後のEOFをWindows/Linuxで確認。
- tests/scripts/verify-async-io-console-windows.py：日本語「日」のUTF-8 3バイトと、先に入力したF1のEKEYへの保持。専用consoleで成功。
- tests/scripts/verify-async-io-read-interrupt-windows.py：READ-FILE途中のCtrl+Cで件数2とior=-516を保持。専用consoleで成功。
- tests/scripts/verify-async-io-write-interrupt-windows.py：送信中CLOSEのCtrl+Cで-516、同じIDの継続利用、FLUSH/CLOSE再試行。専用consoleで成功。
- 1078のverify-file-input-wait.py（4ケース）とverify-file-wait-interrupt.pyを新しい実行ファイルで再確認。Windows/Linuxで実行。
- 旧1078画像のロード拒否後に既存語42を保持、新画像のSAVE/LOADで追加語73と新APIを復元。Builtin ABI変更の境界を実行確認。
- 英日HELP/参照は1781語（HELP 1567件）。生成照合と実行辞書の照合を実施。

各Python fixtureは --sigma に対象実行ファイル、--output にJSONの記録先を指定する。.work/639に試験ログ・JSONと固定レビュースナップショットを置く。Mac実機受け入れでは同じ読取り/書込みfixtureを実行し、pipeの中断・close・ID再利用、除外構成を確認する。Windows専用console fixtureはMac受け入れの代用にしない。

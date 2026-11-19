# 643 設計レビューの評価・採否

2026-11-19。[原文](643-design-claude-review.md)、[採用設計](../PROCESS_MANAGEMENT_DESIGN.md)。

| 論点 | 評価と決定 |
| --- | --- |
| TERMとKILLを分ける | 採用。無期限のOS waitや暗黙の猶予を語に隠さず、TERM/WAIT/KILLをアプリが組み合わせる |
| Windows 137/143をsignalへ変換 | 不採用。実際の終了との区別ができないため生の32ビット値を保持。再レビューで合意 |
| FREEで未読/未配送データを破棄 | 採用。実行中はEBUSY、終了済み資源だけ取消しとjoin/close。配送待ちのCLOSE-FILEと区別 |
| waitpidの即reap後にPGIDを保持 | 修正。WNOWAITでleaderを残してPID/PGIDの再利用を防ぐ。FREE/終了で最終reap |
| SIGCHLD自動回収・他のwaitとの競合 | 起動前検査と組込み条件を明記。独自reaperはソース検索で見つからず。動的ライブラリの動作を保証したとはしない。所有喪失時は古いPGIDへ送信しない |
| close_range(3,...)がexec error pipeを閉じる | 初回案の欠陥を指摘し再検討。error fdの上下2区間を閉じ、fallbackでも除外する。stdioの元fdは3以上 |
| 子の環境/cwdによるPATH解決 | 採用。親で合成と絶対パス解決を完了。空PATH要素を飛ばし、シェルを暗黙に起動しない |
| 環境の取得元 | main.zigを確認しGETENVと同じhost.environ_mapに確定。WindowsのUnicode名照合は同梱std実装と実行試験で確認 |
| Mac最低版 | 配布scriptの既定11.0と同梱SDKのaddchdir_np可用性を確認。Mac実機は1101に残す |
| Tclをsingletonのまま残す | 元の643の共通表化に合わないため不採用。段階移行し、公開64件以外の内部1枠、共通backend、継承許可リストを採用。再レビューで合意 |
| 表のallocation rollback | レビューで妥当と評価。全allocation失敗点を試験。PATHの.exe追加時のリークを試験で検出して修正 |

設計上の確認を実装の完了とは扱わない。Linuxの専用helperでWNOWAITの反復取得、leader終了後の子孫へのKILL、両方のreapを確認した。このprobeはSigmaのbackendの実装試験ではない。


## 起動前基盤の実装レビューへの反映

native_owned/nativeAcquired/nativeReleasedで終了後と起動途中の資源解放を保護し、removePublicでTcl内部枠を拒否する。Windowsのbatch別表記・ADS・曖昧なnamespaceを拒否し、.exe優先に変更。POSIXはsymlink/..を壊す字句畳込みを取り除いた。argv[0]、CWD検査順、各上限のior、merge/nonpipe getterを設計へ記載した。これらは基盤の修正で、native接続の完了を意味しない。

再レビューの名前空間混在・PATH内drive相対・START失敗後の状態も反映し、最終のパス/エラー伝搬の限定レビューで基盤ブロッカーなしを確認した。probeの形式不正/I/O失敗は探索を打ち切り、.exeの形式不正時も拡張子なしへ黙って切り替えない。root/UNC文字列解決を追加試験した。

## native/registry/コア実装レビュー

[OS backend原文](643-native-claude-review.md)、[registry/コア原文](643-registry-claude-review.md)を別に保存した。

| 指摘 | 評価・反映 |
| --- | --- |
| 終了状態をcacheした後のPGID所有確認 | 採用。POSIXは毎回WNOWAITで確認し、ECHILDなら古いPGIDへ送信しない |
| 所有喪失時の既知stream回収 | 採用。既知FILEを閉じてから喪失を報告し、保持したtokenで最終解放を再試行 |
| fork中の親signal handler | 採用。親でmaskを設定し、子はdisposition/stdio/cwdを準備してからmaskを解除 |
| Job未割当で既に終了したrootのrollback | 採用。終了済みhandleを確認して回収を続ける |
| SW_HIDEがTclへ影響 | 採用。汎用backendではSW_HIDEを指定しない。Tcl移行自体は1106に残す |
| 終了の共通3秒を起動途中のrollbackが超える | 修正。残り時間をfreeWithin/abortStartへ渡す |
| fclose失敗後のreapが飛ばされる | 修正。FileSlotが残っている失敗と、所有を手放したエラーを区別。後者は回収を続けてエラーを返す |
| 起動rollbackのECHILD retry漏れ | 修正。通常FREEと同じ限定retryを実装 |
| 起動前のsignal EINVAL/時計失敗時の後続回収中止 | 修正。state=0は送信せず、時計失敗時も待たずに後続資源の回収を試す |
| writer.deinitの再試行 | reader/writerは同じWorker実装。解放済みfieldをnullにし、成功後は全体を初期化することをソースで確認 |
| optional hostの戻り方 | ProcessOps未提供はコアで-21 THROW。内部host helperのior形式は公開語から到達しない。設計へ明記 |

再レビューでは修正5件を確認し、registryとwords_processに阻害要因なし。実行による証拠は[実装記録](../PROCESS_MANAGEMENT_IMPLEMENTATION.md)を参照。内部Tclのstop_internal接続を必須として1106へ残す。

## Tcl共通backend移行

[Tclレビュー原文と再レビュー](643-tcl-claude-review.md)。再レビューでShared adapter/main callback/registry shutdownに修正必須の欠陥なし。

- Windows wishの自動探索が見つけたフルパスを使い、探索と起動の食い違いを修正。自動発見は既存のSearchPath/Git fallback、明示TCL-PROGRAM/SIGMA_WISHの名前だけは共通backendのPATH探索とする。自動探索の範囲を今回狭める変更はしない。
- Sigma終了時のTcl専用stop/freeを除去。TclのJob/groupも共通shutdownで最初にKILLし、全体の単一期限内で回収する。Windows/LinuxでTclが作った子孫を含め停止を実行確認した。
- POSIX stderrは継承、Windowsはnullという旧分担を維持。
- close済みのエラーとECHILDは回収後でもTCL-STOPへ-265を報告する。HELPと英日参照の説明を「終了確認または後始末の失敗」に広げた。
- 未回収資源がある間は新しい内部枠を起動しない。失敗でコアのrunningがfalseになった後は、TCL-STOPの反復ではなく次のTCL起動時かSigma終了時にhostが回収を再試行する。ネイティブ所有を放棄して再起動する旧方式は採用しない。
- private FILEをborrowするfd/HANDLEは同期プロトコル処理中だけ使用。watchはwriteのdeferでjoinされ、close前にdetachする。公開FILE IDは作らない。

GUI前面表示そのものはfixtureで確認したとはしない。テストはprivateプロトコルとOS所有、Tcl scriptの寿命、5秒予算と復帰の回帰である。

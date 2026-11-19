# 646 設計レビューの評価・採否

2026-11-20。[原文](646-design-claude-review.md)。読取りだけのレビューで、実行試験は別途行う。

| 指摘 | 評価・採用する対応 |
| --- | --- |
| H1 固定1024バイトと探索への影響 | 公開COMPACTは入力長ぶんの一時heap領域で計算後に反映。固定1024上限を設けない。配列stack不要の共通compactIntoを既存normalizeからも呼ぶ。既存1,010例はGforthと一致。FPATH回帰も実行 |
| H2 read方向の同期 | last_readならseek64(file,0,SEEK_CUR)を成功させてCストリームを同期してからOS同期。input.lengthとslot EOFを維持。write→read→SYNCと保留入力の回帰を追加 |
| H3 拒否順序・種類 | 提案順を採用：standard→invalid/closed→pipe/proc→OS regular判定→readonly。device/directoryもfflushより前に拒否 |
| H4 callbackが直接書く問題 | owned path結果とrelease callbackの対を採用。ホスト専用領域で全結果を生成し、コアでcap判定後にコピー・registry通知。エラー・短bufferは無変更 |
| M1 optional callbackの-21 | 新EXTENSIONのPROC/ASYNC語と同じhost capability不足として意図的に-21。既存directory語の-263は変えない |
| M2 負長とcap0 | 新語は明示的に負長-9。cap0もmemoryAddress(buffer,0)で検査し、範囲末尾は許可、範囲外は-9 |
| M3 readonly | クロスOS契約としてEACCESを維持。native fsyncのerrnoそのものではなくアクセス能力の事前拒否 |
| M4 Windows絶対判定と長さ | WindowsだけUNC/extended prefixをabsoluteとして認識。既存の入力4095バイト制限は出力の再利用にも適用されることを記載 |
| M5 Windows openとpipe名 | access0、share READ/WRITE/DELETE、OPEN_EXISTING/BACKUP_SEMANTICS。明示device namespaceとUNCのpipe shareを拒否してからopen。短bufferは動的再確保。APIエラーをerrno化 |
| M6 時刻 | FILETIMEの秒商からepoch秒を引き、余りをnsとするfloor等価式。0は1601年epoch値として返し、値の未記録との区別は保証しない。Mac st_mtimespec/Linux st_mtimをCで吸収 |
| M7 worker範囲 | 通常ファイルは既存worker対象外。種類を拒否した後に同期し、worker適用範囲変更時はこの前提も見直す |
| M8 SYNC配置とMac | FileSlotを所有するmain.zigへ配置。Mac fsyncはF_FULLFSYNCではなく、媒体書込みの保証はしない |

Gforth1.0.2の1,010入力・実測出力はtests/data/compact-filename.json。GforthのGPLコードは転載せず、独自の既存正規化処理を共通化する。

## 実装レビューの評価

[実装レビュー原文](646-implementation-claude-review.md)は高なし、中3件。

- M1：予約デバイス名のopen前拒否を採用。GetFullPathNameWだけを使うprobeで、このWindows上ではCOM1/NUL/CONIN$がdevice namespaceへ変換されることを確認した（.work/646/windows-device-name-probe.json）。NT形式の接頭辞も明示拒否する。レビュー中の「接続する可能性」は未検証の推測であり、接続した事実とは扱わない。試験用shared libraryだけにopenカウンターを置き、10照会がopen前にEINVALとなることを検査する。
- M2：READ-FILEの値・位置に加え、READ-LINE、KEY-FILE、KEY?-FILEのprobe、CR先読みの保留入力、EOF後の再読を公開語scriptへ追加する。主に同じ症状を再発させない試験。mainの保留入力・EOF単体は初回レビューの固定コピー後に追加済み。
- M3：英日マニュアル・全語参照はレビュー待ち中に更新済み。実辞書1801項目とHELP1587項目、文書例28件・独立例397件を照合した。未実施という評価はレビューが読んだ時点の記録と区別する。
- L1：private heap方式を維持する。採用済みの計算後commit契約と失敗時無変更を優先し、今回in-place算法へ変更しない。
- L2：長過ぎる入力はCのENAMETOOLONGを取得して返し、OSごとのerrno値に合わせる。
- L3：存在しないWindows drive/network path/shareをENOENTへ対応づける。
- L4：write-onlyで失敗した読取りをlast_readとして記録しない。

方向切替の追加修正はH2の当初案だけでは不十分だった実行結果に基づく。WindowsでZZangedがZZ\0ngedとなることを記録し、読取り4経路の開始前flushで再試験を通した。推測を重ねて原因を断定したものではない。

## 限定再レビュー

[再レビュー原文](646-followup-claude-review.md)では読んだ範囲に高・中の残存なし。低い補足に対応して、通常ファイルのrealpathではopen counterが1増える陽性対照を追加した。Windowsのextended pathはdrive/UNC形式だけを扱い、Volume GUID形式は拒否する制約を設計へ追記する。

限定レビュー対象外だった部分はロクがsourceで照合した。KEY?-FILEはFileOps.ready→main.fileReady→filePollByteへ接続され、試験のprobe経路はprepareFileReadを通る。SIGMA_FS_TESTINGは製品のbuild.zigには定義せず、別途zig ccで作る試験shared libraryだけで有効にする。CLIのresult.jsonが実行中は空なのは出力待ちの状態であり、完了後の原文を上記へ保存した。

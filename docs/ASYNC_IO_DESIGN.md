# 非ブロッキングI/Oの詳細設計（639 / 1093）

2026-11-19。1078のslot所有UTF-8保留を共通バイト入力へ拡張する。EXTENSION語群、本体コアにはoptional FileOpsの契約と境界検査だけを置く。ホストがOS資源と受信・送信状態を持つ。State/イメージにネイティブ資源を保存しない。

## 公開API

- WAIT-FILES ( addr n ms -- index ior ): ファイルIDセル配列。0起点の最初のread-readyを返す。データ・観測済みEOF・読取りエラーをreadyとし、エラー時は対象indexとiorを返す。timeoutは-1 0。最初に全IDを検査し、不正な後続IDが早いreadyに隠れないようにする。重複は許可し先頭index。msは0 poll/負数無期限/正数一つの単調期限。nは1..64、範囲外は-24、addr不正は-9。stdinも対象。WRITE専用ID等の方向不一致は対象ior。missing callbackは消費前に-21。
- READ-AVAILABLE ( c-addr u fid -- u2 eof? ior ): いまホストにある分を上限uまで読み、未準備で直ちに戻る。partialとiorが同時ならu2を返す。EOFは観測時のみtrue、保留が残ればfalse。u=0はID/範囲を検査するがOS読取りやEOF観測を進めない。通常のREAD-FILEの要求長まで待つ契約は変更しない。
- WRITE-AVAILABLE ( c-addr u fid -- u2 ior ): 部分書込み。0未準備とiorを区別し、渡された入力メモリを戻った後に借用しない。
- WAIT-WRITABLE ( addr n ms -- index ior ): write-ready/errorを同様に待つ。読取りと対称。SIGPIPEを既存のguardで保護。

名前と戻り値は設計レビューで確定済み。新Builtinは末尾に追加し、既存タグを変更しない。英日HELP/全語参照・除外構成・保存画像のABI確認も対象。

## 入力状態と所有

ファイルslotを共通の状態所有者にする。1078のDecoder.bytesを最優先、次にhost受信queue、最後にOS。通常KEY/READ/READ-LINE/EKEYと新APIが同じ列を消費する。readyは消費しない。EOF/iorはsticky、先行データの後に提示する。open/close/close-pipe/全回収、seek成功、writeへの方向切替の境界を定義する。非seekableにはFILE-POSITION等はESPIPE。

stdinは既存の端末・パイプのbuffer/EOFと統合し、標準Decoderで先読みした生バイトも対象。native mouse/keyなど文字でない通知を捨てない。workerでForth Stateへ触れない。

## OSバックエンド

- POSIX: libc内の先読み/slot queueを先に確認し、それからpollでread/write-readyを待つ。fd flagsは変更したら復旧し、復旧失敗はiorとバイト保持。生fdとFILEの同時読取りはしない。
- Windows: 計画どおりパイプ読取りworkerを使う。定常待機をPeekNamedPipeの短周期pollへ置き換えない。workerはホスト所有queue/eventだけを更新する。timeout・Ctrl+C・失敗・close・ID再利用でworkerの寿命/回収を保証し、同時にFILEを読まない。
- Windows匿名パイプの同期writeを非ブロッキングとして偽装しない。部分書込みの実現方式（backend所有送信queueへの受入れをcountとする明示契約か、pipe生成自体をoverlappedへ変えるか）はレビューで決定する。戻った後に利用者メモリを借用する方式は採らない。

## 実装順

1091の既存update stream境界を先に修正できる。次にread-ready/read-availableの共通契約とPOSIX/Windows入力、続いてwrite-ready/部分書込み。各段階でClaude Codeレビューと実パイプでデータ保存・EOF・中断・close・ID再利用を検証する。Mac実機は別の受け入れ項目へ残す。639全体は残項がある間は完了にしない。

## レビュー後の具体化

- 送信queueへの受入れをWRITE-AVAILABLEのcountとする。コピーは戻る前に完了し、後続エラーはsticky。FLUSH/closeで配送完了を待つ。通常WRITE-FILEは、登録ファイルとstderrでは先行queueをdrainしてから直接書き込み、既存EPIPEを維持する。stdoutがworkerへ移行した後の通常出力は、同じ送信queueへ順に入れる。
- Windows readerへの移行は一方向（direct→reader→closed）。受信queueは64KiB、最初の待機で確保。既存FILE読取りも移行後はqueueから読み、OS handleを並行して読まない。共有host_wakeで状態更新後notify、observe→走査→最大20ms waitで通知競合・Ctrl+Cを扱う。
- 双方向のWindows同期named pipeは、別スレッドのReadFileが保留中だと同じhandleのWriteFileも止まることを実プローブで確認した（.work/639/windows-duplex-result.json）。そこで新しい4語ではこの種類だけEINVALのiorとし、reader/writerへ移行しない。既存1078のEKEY-WAIT/旧FILE語の双方向対応は変更しない。新語の非対応範囲を明示することで既存機能を後退させず、通常の一方向OPEN-PIPEは計画どおりworkerを使う。
- reader経路のKEY-FILEはRuntimeErrorを返せるため中断を-28とする。READ-FILE/READ-LINEは従来のFileOps署名を維持し、中断はEINTRのiorで返す。新しい待機4語の中断は-28。保留prefixは未報告のエラー/中断で失わない。
- 子プロセス起動前にはstdin readerをpause/joinし、queueは保持する。再利用は次の待機でresume。closeはjoin後だけslot再利用可。停止時のみCancelSynchronousIoの再試行を許し、定常の短周期PeekNamedPipeは行わない。


### 判定とエラー値の確定

Windows pipeのGrantedAccessをNtQueryObject(ObjectBasicInformation)で取得し、FILE_READ_DATA/FILE_WRITE_DATAの両方がある同期pipeを新語の対象外とする。stdinも例外にしない。stdinとstdout/stderrがCompareObjectHandlesで同じkernel objectなら、読取りworkerへ移行しない。両APIは動的に解決し、取得不能は安全と推測せずiorを返す。Microsoft公式仕様：[NtQueryObject](https://learn.microsoft.com/en-us/windows/win32/api/winternl/nf-winternl-ntqueryobject)、[CompareObjectHandles](https://learn.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-compareobjecthandles)。新しい静的OS最小要件を作らない。

WAIT-FILES/WAIT-WRITABLEは全IDのopen・方向・双方向/共有制限を待機開始前に検査し、不適合があればそのindexとEINVALを返す。後続IDの不適合を前のreadyで隠さない。旧READ-FILE/READ-LINEと明示closeで返す中断iorは既存errnoIor(4)=-516（OS共通の契約値）。新しいWAIT-FILES/WAIT-WRITABLE/READ-AVAILABLE/WRITE-AVAILABLEのRuntimeError.UserInterruptはTHROW -28。EKEY-WAITは移行済み一方向pipeではDecoder→worker queueを使い、未移行の双方向pipeは1078の既存経路を維持する。


## 実装レビュー後の終了・共有契約

- 明示的なFLUSH-FILEは配送待ち。WindowsのCLOSE-FILE/CLOSE-PIPEで配送待ちが中断された場合は、EINTR=-516を返してIDと未配送queueを保持する。呼出し側は再度FLUSH/CLOSEできる。配送済みでも中断を先に観測した場合は同じ扱いになる。配送エラーはiorで知らせてcloseできる。
- プロセス終了のcloseAllFilesは例外。通常は登録ファイル・stdout・stderrをdrainする。中断や配送エラーで完了できなければ、残りをキャンセルしてjoinし、未配送分を破棄して終了する。配送完了を成功として報告しない。解放に失敗した資源は保持し、他の標準ワーカーの停止も試みる。未停止workerがある間は共有Wakeを解放しない。
- _pclose/pcloseの子プロセス終了待ちは従来どおりで、今回のキュー待機の中断とは別。任意の子プロセスの終了要求・強制終了は643/1048の範囲。
- SYSTEM/OPEN-PIPE/Tclの起動前には標準出力・標準エラーをdrainし、stdin readerをpause/joinする。受信済みstdin queueは親が保持し、子へ移譲しない。従来のstderr診断の前にもstdoutをdrainする。独立したstdout/stderrへのWRITE-AVAILABLE同士の全体順序は保証せず、必要なら呼出し側がFLUSHする。
- Windowsのstdinとstdout/stderrが同じkernel objectを参照する場合、新語は書込み側からの移行も拒否する。双方向同期pipeの除外は新語だけで、旧FILE/EKEY-WAITは維持する。
- CRTの_IONBFだけでは、Windows pipeをgetcで1バイト読んだ後のworker移行時に1バイトが隠れる実例があった。pipeは移行前からReadFile、移行後はqueueを使い、CRTへ読取りを混在させない。POSIXのpipeも最初から生fdで読み書きし、非seekableなupdate streamでのC方向切替を避ける。通常ファイルはFILEの先読みを維持する。
- POSIXの未準備はO_NONBLOCKとpollで扱う。STDINのREAD-AVAILABLEもpoll後のブロッキングreadにはしない。fd flagsは各操作後に復元するが、open file descriptionを外部プロセスと共有する場合は一時変更も共有されるため、同時I/Oを呼出し側で調整する。
- Windowsでは成功した0バイトのpipe ReadFileをEOFにしない。これは相手の長さ0のWriteFileでも発生するという[Microsoftの仕様](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-readfile#pipes)に合わせる。EOFはbroken pipe等で判断する。
- READ-FILE/READ-LINEはhostが部分データとiorを同時に返した場合、その件数も保持する。まだ消費していないDecoder prefixだけをコピーした時点で失敗した場合はprefixを保持し、未報告分を次の読取りで取得できる。
- 送信queueのsticky errorはWindowsの非同期配送エラーに対する契約。POSIXは各writeで直接結果を返し、未配送queueを作らないため、write失敗後に空のFLUSH/CLOSEが成功することがある。

- 初回のWAIT-FILES ms=0は単発の既存probeを使い、既にOSへ到着したデータをworker起動直後の未通知だけでtimeoutにしない。正の待機・無期限待機でreaderへ移行し、移行後の0 pollも同じqueueを使う。継続待機をPeekNamedPipeの周期pollへ戻すものではない。

実装・試験・レビューの記録は[ASYNC_IO_IMPLEMENTATION.md](ASYNC_IO_IMPLEMENTATION.md)。

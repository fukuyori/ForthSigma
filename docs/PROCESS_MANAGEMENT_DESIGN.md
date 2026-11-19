# 子プロセス管理の詳細設計（643 / 1097）

2026-11-19。639のWindows/Linux実装1091・1094・1095を利用して進める。Mac実機1092・1096を待つ依存は開発工程から外し、最終受け入れでは残す。643のMac実機は1101に分離する。Windows/LinuxのOS backendと公開PROC語を実装した。Tclの共通backend移行まで実装した。Windows/Linux全体受け入れは1100、保留するMac実機は1101で管理する。

## 既存実装と振り分け

移行前のhost_process.zigはTclの1プロセスをグローバルに所有していた。現在のadapterは共通registryの内部枠を使い、旧Windows/POSIX起動コードを除去した。Tclの4つのWriter callbackは互換adapterとして保つ。GUIやwishの発見、スクリプト一時ファイル、display budgetはadapterの担当で、汎用PROCに混ぜない。

PROC-*はEXTENSION。本体コアはoptional ProcessOps、論理メモリ・スタック検査、Builtin末尾追加を担当する。hostのregistryが設定文字列・OS process/job/PID・終了結果を所有する。現在のhost_process_table.zigは論理状態とnative_ownedガードを持ち、実際のOS payloadは対応するbackend recordが保持する。FileSlotがpipe・受信/送信workerを所有し、639のFILE/WAIT/AVAILABLEと共有する。VM Stateと保存画像へネイティブ資源を加えない。graphics=falseでもPROCを使用可能、files=falseまたはextension=falseでは-21とする。

## 公開API（レビュー後の確定契約）

| 語 | スタック効果 | 契約 |
| --- | --- | --- |
| PROC-NEW | ( -- proc ior ) | 空の設定を作る。上限64件。失敗は0とior |
| PROC-ARG | ( addr len proc -- ior ) | 引数をコピー。最初が実行ファイルargv[0]、後続は空文字も許す |
| PROC-CWD | ( addr len proc -- ior ) | コピーした作業ディレクトリ。長さ0は親のcwdを継承 |
| PROC-ENV | ( addr len proc -- ior ) | NAME=VALUEを追加/置換。NAMEだけなら継承環境から削除。NAME=は空値 |
| PROC-IO | ( mode which proc -- ior ) | 0/1/2=stdin/stdout/stderr。mode=0 pipe、1 inherit、2 null、3 stderrをstdoutへ統合。既定は独立3pipe |
| PROC-START | ( proc -- ior ) | 引数配列を直接起動。シェルを暗黙に呼ばない |
| PROC-STDIN | ( proc -- fid ior ) | 親が書くFILE ID |
| PROC-STDOUT | ( proc -- fid ior ) | 親が読むFILE ID |
| PROC-STDERR | ( proc -- fid ior ) | 親が読むFILE ID。非pipe/統合は0 0 |
| PROC-STATUS | ( proc -- state code ior ) | 0設定中、1実行中、2通常終了、3signal終了。終了結果を消費せず保持 |
| PROC-WAIT | ( proc ms -- state code ior ) | ms=0 poll、負数無期限、正数単調期限。時間切れはstate=1。Ctrl+Cは-28で、子を暗黙に停止しない |
| PROC-TERM | ( proc -- ior ) | 待たずに終了要求。POSIXはSIGTERM、WindowsはJobの強制終了（終了コード143） |
| PROC-KILL | ( proc -- ior ) | 待たずに強制終了。POSIXはSIGKILL、WindowsはJob終了（終了コード137） |
| PROC-FREE | ( proc -- ior ) | 設定/終了済みの解放。実行中はEBUSY。未読・未配送の内容を破棄して残streamを閉じ、直接の子を回収する |

設定の変更は起動前だけ。argv上限128件、環境の編集ログ上限128件、設定文字列は終端NULを含め合計64KiB。環境編集は順番に適用する。NUL混入・不正UTF-8・空argv[0]・不正な環境名をEINVALとし、失敗時は以前の設定を保つ。環境名は空と=を禁止し、Windowsでは大文字小文字を区別しない。PATHは子へ渡す合成後の環境、相対パスと相対PATH要素は子の実効cwdを基準にし、親で絶対パスへ解決する。PATH未設定は探索せずENOENT。空のPATH要素は飛ばす。WindowsのPATH要素の外側の引用符は取り除き、拡張子なしでは.exeを先に、次に正確な名前を試す。Windowsのnative probeはファイルの存在だけでなく対応する実行形式を調べる。Windowsのdrive相対C:tool、末尾ドット/空白を持つ通常パス要素、ADS、拡張名前空間はEINVAL。解決後のパスも検査し、batch名の別表記で拒否を回避しない。Windowsの引用は空白/引用符/引用直前のbackslash/末尾backslashを含めCRT argv規則に合わせ、.bat/.cmdは明示的なcmd.exe起動を要求する。

## 所有・状態・失敗

- procは0x2000000000000000から単調増加する不透明ID。slot再利用時にも古いIDは再利用しない。容量とID範囲が尽きたらwrapせず失敗。FILE ID/ディレクトリIDとは分ける。
- 起動前に必要なFileSlotとOS資源を予約し、exec/CreateProcess失敗は起動時に返す。OS起動後のファイル登録失敗は子を終了・回収してからエラーを返し、部分IDを公開しない。
- STD* getterは同じIDを繰り返し返す。CLOSE-FILEはpipeだけを閉じ、子の終了を待たない。stdinのcloseで子へEOFを渡せる。旧OPEN-PIPEはCLOSE-PIPEで子も待つ従来契約を保つ。
- process側のstream参照は(proc所有者ID, file ID)で検証する。利用者が閉じた後、同じFILE IDが別のfileへ再利用されても、getter/FREEはそのfileを取得・解放しない。
- プロセスの終了とpipe EOFは独立。STATUSは終了を保持し、stdout/stderrは明示closeまたはFREEまで読み出せる。終了後も勝手にproc slotを再利用しない。
- 起動失敗と終了127を区別する。設定失敗とOS失敗はior、コアの不正メモリ/stackは従来THROW、未提供optional hostは引数を消費せず-21。
- Windowsは同期の独立3pipeを639に渡す。Zig 0.17.1 std.process.spawnの既定stdout/stderr pipeは非同期handleのため、そのまま639のReadFile workerへ渡さない。Windows handle継承は子の3端点だけに制限する。
- POSIXはworkerがある状態のfork後にallocator/文字列処理を行わない。posix_spawnpのchdir actionまたは親で準備したasync-signal-safeなexec経路を比較して採用する。継承不要fdを漏らさない。起動失敗通知で終了127との区別を保証する。
- 保存画像にはOS資源や設定表を復元しない。IDを通常のForth整数として保存した場合、その整数は復元され得るが、資源の復元や別実行での有効性を保証しない。再起動後は必ずPROC-NEW/STARTで作り直す。
- 通常のTHROW/QUITで子は止めない。Sigma終了は全管理対象を停止し、workerをjoinしてFILEを解放し、processをreap/CloseHandleする。終了待ちを妨げるpipe逆圧を先に解除する。回収に失敗した資源は所有を残し、成功として報告しない。

## 所有と終了に関するレビュー決定

TERMとKILLを別語とし、暗黙の1秒猶予は入れない。アプリがTERM→指定時間WAIT→必要ならKILLを選ぶ。Windowsの結果をPOSIX signalへ推測で変換せず、32ビットの生の終了コードをstate2で返す。state3はPOSIXの実際のsignal（1..127）だけ。POSIX通常終了は0..255。

PROC-WAITの対象は直接の子だけ。設定中はstate0で即時復帰する。終了結果は繰り返し読める。正の時間は単調期限、Windowsはprocess handleの最大20ms待ち、POSIXはwaitid(WNOHANG|WNOWAIT)と最大10msの待ち。SIGCHLDハンドラを追加せず、waitpid(-1)も使わない。Ctrl+Cは子を止めず-28。

POSIXは直接の子をFREEまでreapしない。[WNOWAIT](https://man7.org/linux/man-pages/man2/waitid.2.html)で結果だけを観測し、leaderのPID/PGIDを予約したまま保持する。終端後もFREE前ならTERM/KILLは残るprocess groupを対象にできる。SIGCHLD=SIG_IGN/SA_NOCLDWAITや外部の全子回収と共存するという保証はしない。起動前にdispositionを検査し、非対応状態では起動せずiorを返す。waitidがECHILD等で所有喪失を示した場合は古いPGIDへsignalを送らずエラーにする。組込みhost/ライブラリはこの表のPIDを独自に回収しないことが条件。リポジトリの調査対象にはSIGCHLD無視・NOCLDWAIT・waitpid(-1)/wait()の独自呼出しは見つからなかったが、これは動的ライブラリ全体の保証ではない。

FREEはrunningならEBUSY。設定/終了済みではstdin→stdout→stderrの順にworkerを取消し・joinして未読/未配送分を破棄し、FILEを閉じる。通常のCLOSE-FILEは639の配送待ち契約のまま。出力を保存したいアプリはEOFまで読んでからFREEする。FREEはJob/process groupの子孫所有を手放して直接の子をreap/CloseHandleし、最後に表を除去する。途中失敗は所有を残して再試行する。

Sigma終了時はFREEされていない全group/Job（直接の子が既に終わったものも含む）へKILL→streamを破棄してjoin/close→全体3秒を上限に直接の子を回収→旧closeAllFiles。外部資源を含む失敗は診断し、成功と偽らない。自らsetsid等で離脱する子孫の隔離機能ではない。FREE後の子孫は対象外。

## OS起動経路

- 環境の取得元はGETENVと同じhost.environ_map（main.zigで確認）。設定の編集ログを親の複製へ適用し、親を変更しない。Zig 0.17.1 std.process.Environ.MapのWindows Unicode大文字小文字照合も確認した。
- Windowsは同期CreatePipe、STARTUPINFOEXの3端点だけの継承許可リスト、CREATE_SUSPENDEDで生成した子をJobへ割り当ててからResumeする。Job割当失敗は終了/回収して起動失敗。KILL_ON_JOB_CLOSEは使わず、明示TERM/KILLと終了時にJobを止める。通常の子孫はJob内、許可したbreakawayは管理外。CRT引用は[Microsoftの規則](https://learn.microsoft.com/en-us/cpp/c-language/parsing-c-command-line-arguments?view=msvc-170)に従い、argv[0]を別扱いにする。新しいIo runtimeは作らない。
- Linuxは親でargv/envp/絶対パス/cwd/pipeを全準備してfork。子ではsignal設定・setpgid・chdir・dup2・close・execve・失敗通知write・_exitだけを使う。stdioの元fdは親で3以上へ移し、dup2の同一fd/CLOEXECの罠を避ける。execエラーpipeもCLOEXECとし、close_rangeで閉じない。採用案はerror fdを挟む2区間のclose_range、未対応ならそのfdを除くcloseループ。親のerrno handshakeでexec失敗と正常終了127を区別する。
- macOSはposix_spawn、CLOEXEC_DEFAULT/SETPGROUP/SETSIGDEF/SETSIGMASK、dup2/inherit/chdir action。配布scriptの既定最低版は11.0、同梱SDKのaddchdir_npは10.15以降（26.0でdeprecated）であることを確認した。新しいaddchdirだけを必須にして最低版を引き上げない。waitid/WNOWAITとnative起動の実行は1101で受け入れる。
- 起動はVMスレッドで直列化し、Tclを含む全adapterを同じ起動制約に合わせる。Tclは公開64件と別の内部予約1枠を共通表に持つ。wish探索・script一時ファイル・display budgetをadapterに残し、継承許可リストを先に整え、共通backendへ移して旧起動経路を除去する。永久に旧singletonを残す案は採用しない。

## レビューと基盤実装の現在地

[Claude Code設計レビュー原文](reviews/643-design-claude-review.md)と[評価・採否](reviews/643-review-response.md)を分けて保存する。設定/結果表・OS起動・FileSlot所有・PROC語14個を実装し、1098を完了した。1099を1105コア、1106 Tcl移行、1107資料に分割した。Tclの置換1106まで実装した。全体受け入れ1100でWindows/Linuxの実行結果を記録する。実装と試験の範囲は[実装記録](PROCESS_MANAGEMENT_IMPLEMENTATION.md)に記す。

## 工程と検証

1097仕様→1098ホスト/OS→1099コア/Tcl→1100 Windows/Linux→1101 Mac実機。既存Tclの発見・一時ファイル・display budgetを保つ回帰を各接続段階で行う。argvの空文字・空白・quote・末尾backslash・日本語、env追加/削除/空値、cwd、偽プログラムと終了127、同時64件と超過、古いID、終了結果の反復取得を検証する。stdinを送りながら大量stdout/stderrを並行して読み、timeout/中断/close/再利用/全回収を確認する。Windows/Linuxの実行とMacクロスビルドを区別し、Mac実機は1101に残す。


## 基盤実装レビューで具体化した境界

- native資源を作る前にEntry.nativeAcquiredを呼び、rollback失敗時もnative_ownedを保持する。起動とFileSlot公開に成功した後だけstartedでrunningへ移す。回収完了後はnativeReleased、その後にremovePublic。終了状態になっただけではremoveを許さない。Tclの内部IDはgetPublic/removePublicでは拒否する。表のdeinitも未回収をassertする。
- POSIXのパスは絶対パスへ連結しても、symlinkをまたぐ..を字句的に畳まない。カーネルの探索順を保つ。Windowsの通常Win32パスは規則どおり字句解決する。どちらもrealpathでファイルを固定することやTOCTOUの防止は保証しない。
- PROC-CWDの相対指定はSTART時点の親のcwdを基準にする。未指定/空指定ならその親cwdを継承。native backendはcwdの存在・directory/移動可否をprogram探索より先に検査する。exec時のcwd変更が競合等で失敗した場合も起動失敗として通知する。
- argv[0]は利用者がPROC-ARGで渡した元の文字列を保持し、解決後の絶対パスは別の実行先として渡す。WindowsはlpApplicationNameを必ず明示する。Windowsでargv[0]に引用符がある場合はPROC-ARGでEINVAL。cmd.exe等のインタプリタを明示する場合、そのインタプリタ独自の引数規則は利用者が扱う。
- 設定64KiBはOSで必ず起動できる上限という意味ではない。Windowsのcommand lineはNULを含む32767 UTF-16単位をSTART時に検査し、超過はE2BIG。ARG/ENVの件数・文字列量上限もE2BIG、proc/FILE表の容量上限はEMFILE。不正なtext/UTF-8/IO modeはEINVAL、旧/不正proc IDはEBADF、実行中のFREEや未回収資源がある設定変更はEBUSY。メモリ確保はENOMEM。OSの起動エラーは元のerrno相当を返す。
- 設定中/実行中のSTATUS codeは0。STD* getterは設定中なら0 EINVAL、起動後に非pipeなら0 0。stderr mergeはstdoutがpipe/inherit/nullのいずれでも子側の同じ出力先へ接続する。親にはstdoutのpipe IDだけを返し、stderr getterは0 0で二重closeを避ける。
- Windowsの継承環境はWTF-8を保ってUTF-16へ変換し、大文字小文字を区別しないUnicode順の環境blockへする。新しい設定文字列は厳密なUTF-8。継承した=C:等は保存し、明示cwdのdriveについては新cwdに合わせて更新する。終了コード259をrunningと決めつけず、process handleのwait結果で判定する。

START失敗後、rollbackが完了した場合は設定とIDを保持して再設定/再START/FREEできる。rollback未完了ならnative_ownedを保持し、設定変更/再STARTはEBUSY、FREEは残る回収を再試行する。Windowsの名前空間は区切り文字の混在も含め検査し、PATH要素にもdrive相対の禁止を適用する。

probeは不正な実行形式（ENOEXEC）とmetadata取得のI/O失敗（EIO）をNotFoundに混ぜず返す。Windowsのroot相対programは子cwdのdrive/shareを引き継ぎ、UNC cwdも保持することを注入probeによる文字列試験で確認した。これはネットワーク先やOS起動の試験ではない。

PATH途中の形式不正・metadata I/O失敗はその時点で探索を打ち切る。.exeが存在して形式不正なら同じ場所の拡張子なしの名前へフォールバックしない。missing/permission-deniedの探索継続とは区別する。

## 実装レビューで明確化した解放エラー

FileSlotのworkerをjoinできない場合は所有を残す。一方、fcloseは失敗してもFILEの所有を手放すため、そのエラーを保持しつつnative processの回収を続ける。この場合FREEはエラーを返してもproc IDは既に無効になり得る。ECHILDでも古いPGIDへ送らず、既知のstreamとメタデータを回収し、所有喪失をiorで報告する。

起動失敗のrollbackは最大3秒、Sigma終了の待機は全エントリ共通3秒とし、起動途中の残資源にも残り時間だけを渡す。時計取得に失敗しても既知の資源のclose/freeを試み、待機を増やさない。OS操作やworker joinの実行時間そのものを強制的に打ち切る保証ではない。

ProcessOps自体が未提供なら、コアで引数を保持してHostUnavailable（-21）をTHROWする。START前の出力flushやWAITの中断・ホスト待機範囲の失敗も、既存のRuntimeErrorでTHROWする。子の起動失敗・ID/状態のエラーはiorとして返す。

## Tcl adapterの接続

wishの発見・一時script・rawプロトコル・display budgetはhost_process.zigへ残す。内部予約1枠は共通native backendを使い、private FILEはnative recordが所有し、公開FileSlotへ露出しない。close前のstop_internalでraw参照を外し、除去後のreleased_internalでscriptを削除する。通常TCL-STOPのEOF猶予はadapterが扱うが、Sigma終了では先に共通shutdownが全group/JobをKILLする。

TCL-STOPの終了/後始末失敗は-265として報告する。未回収の所有があれば、次のTCL起動かSigma終了で回収を再試行し、放棄して新規起動しない。コアrunning=falseになった後のTCL-STOP反復はhost再試行を行わない。Windows自動wish発見は既存SearchPath/Git fallbackを保ち、明示名の解決は共通PATH規則に従う。stderrはPOSIX継承、Windows null。

WRITE-AVAILABLEの受付完了は配送完了ではない。相手が入力を読む前にstdout/stderrを大量送信する場合、入力のCLOSE-FILEも配送待ちで停止し得るため、出力を並行して取り込んでから半閉じする。公開3streamの試験はこの順序を使う。

# 子プロセス管理の実装記録（643）

2026-11-19。[採用設計](PROCESS_MANAGEMENT_DESIGN.md)、[設計レビュー](reviews/643-design-claude-review.md)、[nativeレビュー原文](reviews/643-native-claude-review.md)、[registry/コアレビュー原文](reviews/643-registry-claude-review.md)、[評価・反映](reviews/643-review-response.md)。

## 現在の範囲

1097仕様・1102起動前基盤・1103 Windows backend・1104 POSIX backendと親1098を完了。1099（1105コア接続・1106 Tcl移行・1107資料）まで完了。公開PROC語とTclは共通OS backendを使う。Windows/Linuxの全体受け入れ1100とMac実機1101を完了。643は完了。

## 振り分けと所有

- 本体コア：optional ProcessOps、PROC語14個のEXTENSION登録、スタックと論理メモリの事前検査、結果の配置。Builtin末尾追加とし、VM Stateや保存画像へOS資源を入れない。files/extension無効またはhost未提供は-21、graphicsには依存しない。
- host_process_table.zig：公開64枠と内部Tcl用1枠、非再利用の単調ID、設定文字列、native_owned/native_lost、終了結果を所有。実際の資源を解放するまで表を除去しない。
- host_process_spec.zig/quote.zig：環境編集・PATH/cwd探索・Windows CRT引用と実行先の準備。子を作る前に必要なZig allocationを終える。
- host_process_native.c/.h/.zig：Windowsの同期3pipe、継承3端点の許可リスト、suspended起動→Job割当→再開、生の32ビット終了値。Linuxはfork/exec error handshakeとCLOEXEC/fd/signal整理。POSIXはWNOWAITでrootを保持し、グループ終了要求と最終reapを分ける。Macは最低11.0を保つposix_spawnのクロスビルド。
- host_process_registry.zig/main.zig：VMスレッドで起動を直列化。公開成功後だけFILE所有をFileSlotへ移し、(proc ID, FILE ID)で再利用を検査。639の待機・通常FILE・AVAILABLEと同じreader/writerを使う。起動失敗、join/close失敗、終了時の回収を扱う。

Tclは共通表の内部予約枠を使用する。host_process.zigの旧Windows/POSIX起動・待機・回収経路を除去し、wish探索・一時script・同期プロトコル・display budgetだけをadapterに残した。private FILEはnative recordが所有し、stop_internalでraw参照を外し、released_internalでscriptを削除する。公開64件とは別枠で、公開FILE IDを消費しない。POSIX stderr継承、Windows nullを保つ。Sigma終了ではTclも共通shutdownの先頭KILLと共通期限へ含める。

[移行レビュー原文](reviews/643-tcl-claude-review.md)と再レビューで、探索先フルパスの保持と終了時の子孫回収を確認した。後始末のエラーは回収後にもTCL-STOPの-265で報告し、未回収の所有がある間は次の起動を待たせる方針を設計と英日HELPへ記した。

## 実行した確認

| 対象 | 結果と範囲 |
| --- | --- |
| Windows通常 | core 1077成功・8除外、host 143成功・12除外、runtime/freestandingと実行試験を含む23/23 step成功。最終sourceでcore/hostを再コンパイル |
| Linux musl/WSL | core 1077成功・8除外、host 148成功・14除外、runtime 15成功。最終sourceで再コンパイルしWSLで実行 |
| files=false/graphics=false/audio=false | Windows core 711成功・374除外、host 133成功・18除外、13/13 step成功。無効機能を成功件数に含めない |
| Mac arm64 | core 1077成功・8除外、host 136成功・15除外、runtime/freestandingを含む23/23 step成功。native・PROC語・Tclの実機受け入れも成功 |
| Native C backend | Windows14ケース、Linux16ケース、Mac16ケース。argv/日本語env/cwd、stdin131072 bytesとstdout/stderr各200000 bytesの並行処理、EOF半閉じ、終了127/259と起動ENOENTの区別、TERM/KILL、多重起動、merge/null |
| 故障注入 | Windows8段階・Linux5段階で起動失敗rollback。24回の起動失敗の前後でWindows handle133→133、Linux fd5→5。Linuxは自動reap disposition拒否と、外部reap後のECHILD/既知stream回収を実行 |
| FileSlot結合 | Windows/Linuxで閉じたFILE IDの再利用を検査し、getter/FREEが別のfileを閉じないことを確認。3箇所の公開失敗でrollback後に同じ設定を再起動。fclose相当の解放済みエラーを注入し、エラーを報告してもroot回収とproc除去を継続 |
| 公開PROC語 | Windows/Linux各4ケース。実際のSigmaでstdin→EOF→stdout/stderr、状態反復と古いID、0/正数timeout、実行中FREE拒否、null出力、KILL→WAIT→FREE、起動失敗後の設定保持、READ/WRITE-AVAILABLEでstdin131072 bytesを送りながらstdout331072・stderr200000 bytesを全バイト照合 |
| 上限と再利用 | Windows/Linuxで実際の64プロセスを同時起動し、全件state=1、65件目EMFILE、全KILL/WAIT/FREE後の枠再利用を確認 |
| 中断 | Windowsの専用hidden consoleとLinux SIGINTで無期限PROC-WAITを中断。-28後の子state=1を確認して明示KILL/WAIT/FREE |
| 継承・子孫 | 親のinheritable Event（Windows）/fd（Linux）が子へ漏れないこと、root終了後のJob/PGIDによる子孫KILLを実行 |
| Tcl | Windows/Linuxで公開64枠を埋めたままprivate枠で3回起動し、TCL-STOP/再起動/BYE後のroot回収とscript削除。Tclが作った子孫もSigma終了時に停止 |
| Tcl表示予算 | Linux x11構成で既存8ケース（無応答、大量書込み停止、SIGSTOP、event/partial trickle、正常、timeout後の明示TCL、検索の再試行）を再実行。失敗した子はSigmaが生きたまま回収。ローカルX11 socket directoryがなくnative socket競合ケースは除外 |
| 追加の除外構成 | graphics=false/audio=falseでも公開PROC語を実行。files=false/graphics=false/audio=falseでPROC-NEWの-21を実行確認。extension=falseの通常試験はcore1063成功・22除外、host143成功・12除外、23/23 step成功 |
| コア境界 | 偽hostで引数順、結果順、範囲外メモリとstack overflow前の副作用防止、START/WAIT中断時のstack保持、host未提供を検証 |
| HELPと全語参照 | 英日1795項目、HELP1581件。実辞書照合、文書例28件と個別使用例391件成功。生成器の回帰5件成功 |

WindowsのZig→native直接driverでも空文字・空白・quote・末尾backslash・日本語・メタ文字、env追加/削除/空値、空白と日本語cwd、stdinを照合した。C backendのctypes試験だけをZig側の引用/準備の証明にはしていない。Linuxの子孫試験では専用Python helperだけを一時subreaperにして自分の子孫をreapし、設定を元に戻した。

cmd.exeはCRTと別の引数解釈を持つ。結合試験ではcmdのコマンド文字列を使わず、Windowsはhostname.exe、Linuxは/bin/echoを直接起動した。シェルを明示する場合は、そのシェル独自の規則を利用者が扱う採用契約を維持する。

## 再現用の主な操作

```powershell
zig build test --summary all
zig build -p .work/643/windows
python tests/scripts/verify-process-words.py --sigma .work/643/windows/bin/sigma.exe
zig cc -shared -DSIGMA_PROC_TESTING src/host_process_native.c -o .work/643/process-native.dll
python tests/scripts/verify-process-native.py --library .work/643/process-native.dll
zig build core-check host-check runtime-check -Dtarget=x86_64-linux-musl -p .work/643/linux
zig build core-check host-check runtime-check -Dtarget=aarch64-macos -p .work/643/macos
```

Linuxのstaged testsはWSL内でそれぞれ実行した。Python ctypes用共有libraryだけはWSLのPythonに合わせLinux GNUとしてビルドし、製品実行体・host testsはmuslを使った。ログとJSONは.work/643、Mac実機の結果は.work/1101/mac。レビュー原文と判断はdocs/reviewsへ保存した。

## Mac実機受け入れ（1101）

2026-11-19、macOS 27.2.1 arm64 / Zig 0.17.1。`.work/1101/mac`へ通常ビルド、`.work/1101/mac-excluded`へgraphics/audio/float除外ビルドを作成。両構成の`zig build test --summary all`、通常ビルドのPROC fixture、およびfiles=false構成でPROC-NEWが-21をthrowする確認が成功。

- `verify-process-native.py`: argv/env/cwdと日本語、3stream各200000 bytesとstdin 131072 bytes、exit 127/259、TERM/KILL、複数起動、merge/null、継承fd防止、root終了後の子孫kill、posix_spawnの4段階rollback、24回の起動失敗後もfd数4の維持、SIGCHLD自動回収拒否と外部reapを確認。結果は`.work/1101/mac/process-native.json`。
- `verify-process-words.py`: 半閉じと状態再読、timeout中の子の存続/KILL、stdin送信中のstdout 331072 bytesとstderr 200000 bytesの同時回収、起動失敗後の設定保持、POSIX終了259の状態/終了コード再読（3）を確認。通常・graphics/audio/float除外で成功。
- `verify-process-capacity.py`: 64プロセス同時起動、65件目のEMFILE、全件kill/wait/free後の再利用を確認。
- `verify-process-interrupt.py`: PROC-WAIT中のSIGINTで-28を返し、子を暗黙停止せず実行状態を保つことを確認。
- `verify-process-tcl.py`: 公開64枠を埋めた状態のTcl内部枠、再起動3回、script削除、終了時の子孫killを確認。制御fixtureによるprotocol・OS所有の試験で、実wish/Tkウィンドウ表示の試験ではない。
- 初回実機実行で、macOSの`waitid(WNOWAIT)`が`si_status=259`を返す差と、process groupへのSIGKILLがEPERMになるrollback経路を検出。POSIX通常終了値を0..255へ正規化し、group signalのEPERM時は所有する子PIDへfallbackするよう修正。両ケースを再実行して成功。
- Linux前提だったTcl/native検証scriptの`/proc`・`prctl`利用をLinux限定にし、Macでは`kill(pid, 0)`と`/dev/fd`で生存・資源数を確認するよう修正。

各構造化結果は`.work/1101/mac/`と`.work/1101/mac-excluded-process-words.json`に保存した。Linuxの既存display budget試験でnative socket directoryがないケースは除外した。

保存画像へprocess tableやnative payloadを追加していない。通常の画像/再配置試験を含むcore試験は通過したが、作動中のPROCを保存して同じOS資源を復元する機能を実装・保証したものではない。設計どおり再起動時にPROC-NEW/STARTで作り直す。

追加の再現用scriptはtests/scripts/verify-process-{words,native,capacity,tcl,interrupt}.py。capacity/tcl用の制御されたfixtureはtests/process_wish_fixture.cをzig ccでビルドする。試験結果とsource fingerprintの一覧は.work/643/final-validation.jsonへ記録する。今回の依頼ではコミット・プッシュしない。

# Windows検証記録

2026-11-14、Windows x86_64、Zig 0.17.0。P10/607のWindows確認として実施。実施内容をtque703と子704〜709に登録し完了へ更新。702・540も完了。版番号変更、パッケージ作成、コミット・pushは行っていない。

## 最終結果

今回のWindows確認は完了。通常1058成功・10 skip（コア999・ホスト59）、最小構成582成功・457 skip、通常ビルド/freestanding、統合24件、追加境界378件、コンソール36件が成功。既存ブロック/EKEY/ランタイム13件も成功した。

利用者へ、実行ファイルを普段のWindows端末で起動し、コメント行でIMEによる「にほんご」→「日本語」の変換/確定、全角・絵文字の挿入/移動/削除、カーソル位置と表示崩れを確認する手順を提示した。利用者の「ok」という回答を受け、問題なしの手動確認結果としてtque718を完了へ更新した。これは自動注入の結果とは別の利用者確認である。

追加検証で次の2件を修正した。

- Windows CRTの`O_CREAT|O_TRUNC`が既存ファイルの読み取り専用属性を作成modeで変更していた。排他的な新規作成を先に試し、既存ファイルは作成modeなしで開くことで属性を保持する。
- SYSTEMの子cmd.exeが共有コンソールモードを変更し、終了後に残していた。SYSTEM前の入力/出力モードを保存し、子終了後に復元する。正常/非0終了、後続キー入力、例外終了時の復元を確認した。

追加境界検証は`python tests/scripts/verify-windows-boundaries.py --minimal .work/windows-minimal/bin/sigma.exe`。minimal実行ファイルは`zig build -Dfloat=false -Dfiles=false -Dhelp=false -Dtools=false -Dimage=false -Dgraphics=false -Daudio=false -Ddebug=false --prefix .work/windows-minimal`で生成する。files無効時はFILENAME-MATCHが除外されることを確認した。

378件には、全256バイトと空ファイルの準備/EOF、Unicodeパス終端容量、ホーム/ドライブ/ソース相対検索、mkdirのWindows方針、列挙上限/解放、FPATHの保存実行と追加、入れ子入力/先読み、broken-pipe、SH-GETのメモリ不足70回後の解放/復帰、時刻/DST/offset/UTF-8名/範囲/失敗保持を含む。Windows broken-pipe書込の実測iorはCRT EINVAL由来の-534であり、定数BROKEN-PIPE-ERRORの-544と同一視しない。

36件にはReadConsoleWの左右/Home/End/Delete/Backspace・履歴上下・日本語/絵文字編集、実コンソールサイズとカーソル移動、Shift/Ctrl/メディアキー、GRAPHICSのINKEYと標準EKEY、同一プロセスのEKEY→KEY→ACCEPT→SYSTEM→INKEY、正常/例外終了時モード復元を含む。NSは通常/raw入力でGenerateConsoleCtrlEventによるOSのCtrl+C通知を受け、2秒と2^64ns超の待機を中断・再待機し、入力Aとコンソールモードを保持することを確認した。CPUTIMEはワーカースレッドのGetThreadTimesと照合するホストテストを追加し、子プロセスCPU除外も確認した。

最終証跡は`.work/windows-complete-{test,build,minimal}.log`、`.work/windows-boundaries/report.json`（complete=true）、`.work/windows-boundaries.log`、`.work/windows-console.json`、`.work/windows-native/report.json`。tqueの現在の対応は[照合記録](PLATFORM_TASK_AUDIT.md)を参照。未実施のWSL専用確認は728〜741へ分離し、Windows完了と混同しない。

## 初回確認の記録

以下の件数は追加検証前の記録。現在状態は上の最終結果を参照。

## 修正

- `host_directories.zig`のWindows型情報参照2か所をZig 0.17.0の`param_types`へ変更。通常ビルドとホストテストのコンパイル失敗を解消。
- `host_timezone.zig`のWindows時刻変換をCRTの実シンボル`_localtime64_s`・`_gmtime64_s`へ変更。`localtime_s`・`gmtime_s`の未解決シンボルを解消。時刻0、2024年初、2038年境界超の結果をPythonのローカル日時と照合。
- 引用符から始まるEDITORコマンドを、cmdが外側の引用符を除去する規則に合わせて囲む。修正前は引用符付き実行パスと、日本語・空白・`&`を含むソース名の組合せでHOST FUNCTION ERRORを再現。修正後はファイル・一時レポート・辞書復元・保存実行ファイル経由で成功。702の再現ケースに対する修正であり、任意のEDITOR構文すべての保証ではない。
- Windows標準入力のサイズ変更レコードを、その後のキーより先に返す。修正前はサイズ変更とAが並ぶとEKEYがAを先に返した。修正後はK-WINCH、Aの順を確認。
- 既存ブロック検証の補助語NEXTをBLOCK-NEXTへ変更。追加済みの組込みNEXTとの再定義警告が期待出力に混入するため。処理系の警告抑制は行っていない。

## 自動検証

PowerShellで次を実行する。検証は同じ作業ファイルを共有するため順番に行う。

```powershell
zig build test --summary all
zig build --summary all
zig build test -Dfloat=false -Dfiles=false -Dhelp=false -Dtools=false -Dimage=false -Dgraphics=false -Daudio=false -Ddebug=false --summary all
python tests/scripts/verify-blocks.py zig-out/bin/sigma.exe
python tests/scripts/verify-ekey.py zig-out/bin/sigma.exe
python tests/scripts/verify-runtime.py --sigma zig-out/bin/sigma.exe --output .work/windows-runtime.json
python tests/scripts/verify-windows.py
python tests/scripts/verify-windows-console.py zig-out/bin/sigma.exe
```

- 通常テスト：コア999成功・5 skip、ホスト58成功・5 skip。freestandingコンパイルとビルド内の実行確認も成功。キャッシュ再利用時の集計は再実行したテストだけを表示する。Windows側のresize通知の実装変更により、WindowsではスキップされるPOSIX用resizeテストの取り込みがなくなり、最終実行のskipは修正途中より1件少ない。
- 最小構成：581成功・457 skip、freestanding確認を含む。
- ブロック：BYE/EOFでの保存、入れ子LOADと入力復元、例外、辞書保存復元、SAVESYS終了時保存。
- EKEY：パイプの非待機確認、不正エスケープのバイト保持、Unicode、文字3。POSIX PTY部分は実行しない。
- ランタイム：再帰上限と復帰、標準出力/標準エラー/SYSTEMの順序、大量出力、flush、KEY入力前のプロンプト表示など13件。
- Windows統合：パイプのバイナリ読込・終了コード・UTF-8書込・不正モード、SH-GETのCRLF保持、空出力、入出力切替のTHROW復元、MARKER/再定義、SAVE/LOAD-DICTIONARY/SAVESYS、Unicodeディレクトリ、時刻変換、EDITORと一時ファイルの失敗時削除など22件。
- コンソールAPI：別の非表示コンソールにWriteConsoleInputWでレコードを注入。Unicode、上矢印、Shift+上、KEY/EKEY併用、ACCEPT、Ctrl+C、サイズ変更通知と後続文字の保持の7件。KEYのケースはWindowsの行入力に合わせEnterも送信する。

追加確認でWindows統合は24件になった。空白入り実行パスへPythonとDLLを複製してEDITORケースを再実行し、パイプ/ファイルからのリダイレクト入力で編集用エスケープ列とUTF-8・CR/LFが保持される2件を追加した。tque702・540を完了に更新した。[タスク別照合](PLATFORM_TASK_AUDIT.md)。

証跡は`.work/windows-final-{test,build,minimal}.log`、`.work/windows-runtime.json`、`.work/windows-native/report.json`、`.work/windows-console.json`。コンソール検証のエラー詳細は`.work/windows-console.log`。

SH-GETのCRLF保持はバイト値で確認した。取得結果をTYPEすると、既存のWindows CRTテキスト出力がLFをCRLFへ変換し、入力に含まれていたCRと合わせCR CR LFになる。今回は標準出力全体の改行方針を変更していない。

## 今回の確認に含めないもの

- 端末ウィンドウをドラッグする操作の目視。サイズ通知と後続入力保持はコンソールAPIで確認した。IME/文字編集/表示の利用者確認、OSのCtrl+C配信は上記のとおり完了。
- 半ブロック/Sixelの実端末描画とSHOWによる上書き防止。既存POSIX PTY用スクリプトをWindows実端末の証跡として流用しない。
- 対話エディタの目視操作。今回のエディタは引数と内容を記録するPython代替プログラム。
- 指定Gforthの比較。指定ビルド成果物はこのチェックアウトに存在せず、比較実施済みとはしない。
- P10の全組合せ、すべての単独機能除外構成、Linuxの未確認項目。P10/542全体を完了とはしない。

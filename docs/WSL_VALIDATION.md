# WSL検証記録

2026-11-14。WSL2 Ubuntu、Linux x86_64、カーネル6.18.33.2-microsoft-standard-WSL2で確認した。Windowsの確認とは別の実行記録であり、独立したLinuxマシンでの受入確認ではない。

## 最終結果

WSL専用タスク728〜741の確認は完了。最新ソースをLinux用にビルドし、通常テスト1062成功・6 skip（コア999・ホスト63）、最小構成586成功・453 skip（コア531・ホスト55）。CPUTIMEにLinuxのワーカースレッドCPUを`CLOCK_THREAD_CPUTIME_ID`と照合するホストテストを追加したため、初回より成功件数が1増えた。処理系の追加修正は不要だった。テストのWindows分も再実行し1058成功・10 skipで回帰なし。

- `verify-posix-boundaries.py`：482件成功。権限9 mode×4 umask、既存属性保持、globの3 locale/無効UTF-8/files無効、cwdのUnicode/終端/ホーム/失敗保持、mkdirのmode/umask/部分作成、列挙の不正UTF-8名/切詰め/失効/64件上限/再利用、FPATHの検索/保存実行/追加/ハンドル解放、全256バイトとEOF、先読み/入れ子/例外復元、CPU単位/子除外、7 zone×13時点の日時/DST/offset/UTF-8名/範囲/失敗保持、SH-GETの借用コピーとメモリ不足70回後のヒープ/パイプ解放・再利用を確認。権限などのfixtureはLinuxの`/tmp`に作り、終了時に削除する。
- `verify-posix-terminal.py`：24件成功。制御端末付きPTYでKEY-FILE/KEY?-FILE/KEY-IORのバイト/Unicode/先読み/Ctrl+C、FORMと相対カーソル、SIGWINCHと後続KEY/ACCEPT、Shift/Ctrl/Alt修飾、GRAPHICS INKEY→標準EKEY、NS中SIGINT（2秒と2^64ns超）・再待機・raw/canonical入力保持・termios復元を確認。named FIFOではライターを開いたままの空準備判定、stdio先読みとEOFを確認。
- P01〜P03の既存スクリプト9本：計15,371ケース成功。P01a/b/cは1177/4060/4553、P02a/b/cは3521/259/119、P03a/b-address/b-dataは1376/18/288。指定Gforthとの新しい比較ではなく、既存の期待値とSigma方針に対するLinux実行結果の照合。
- `verify-build-cli.py`：build.zigの追加CLI9ケースをWSLで別実行して全成功。WindowsのビルドランナーがLinux用バイナリを直接実行できない制約と切り分けた。
- 初期スタック上限1MiB（通常WSLは8MiB）に制限した環境で、CLI9件・ランタイム13件・保存実行ファイル/エディタを含むPOSIX統合10件が成功。記録は`wsl-build-cli.json`のstack_limit_bytes、`wsl-stack-runtime.json`、`wsl-stack-native/report.json`。任意のスレッドスタックサイズすべての保証ではない。
- 既存ブロック/EKEYのパイプ・PTY、ランタイム13件、SHOW PTY20件、POSIX統合10件も最新ビルドで成功。行編集18件は前回の成功記録を維持する。

```sh
python3 tests/scripts/verify-posix-boundaries.py --sigma .work/wsl-build/bin/sigma --minimal .work/wsl-minimal/bin/sigma
python3 tests/scripts/verify-posix-terminal.py --sigma .work/wsl-build/bin/sigma
python3 tests/scripts/verify-build-cli.py --sigma .work/wsl-build/bin/sigma --output .work/wsl-build-cli.json
```

追加の最小構成実行ファイルはWindowsで`zig build -Dtarget=x86_64-linux-musl -Dfloat=false -Dfiles=false -Dhelp=false -Dtools=false -Dimage=false -Dgraphics=false -Daudio=false -Ddebug=false --prefix .work/wsl-minimal`で生成した。

証跡：`.work/wsl-boundaries/report.json`・`wsl-terminal/report.json`（どちらもcomplete=true）、各`.log`、`wsl-final-{core,host}-tests.log`、`wsl-final-minimal-{core,host}.log`、`wsl-final-{build,minimal-build}.log`、`wsl-p01a.json`等9本、`wsl-build-cli.json`。tque728〜741を各実施結果・証跡付きで完了(auto)へ更新した。現在状態は[タスク対応表](PLATFORM_TASK_AUDIT.md)を参照。

## 初回確認の記録

以下の件数は追加検証前。現在状態は上の最終結果を参照。

## ビルドとテスト

WSLのPATHにはZigがなかったため、WindowsのZig 0.17.0で`x86_64-linux-musl`向けに作成し、Linuxの実行ファイルとテストバイナリをWSL内で実行した。Linux版Zigの取得・インストールは行っていない。

```powershell
zig build -Dtarget=x86_64-linux-musl --prefix .work/wsl-build --summary all
zig build test -Dtarget=x86_64-linux-musl --summary all
zig build test -Dtarget=x86_64-linux-musl -Dfloat=false -Dfiles=false -Dhelp=false -Dtools=false -Dimage=false -Dgraphics=false -Daudio=false -Ddebug=false --summary all
```

後ろ2つはテストのコンパイルとfreestanding確認には成功するが、WindowsのビルドランナーがLinuxバイナリを直接実行できず、コマンド全体は失敗する。その出力に記録された`.zig-cache/o/<hash>/test`をWSL内で直接実行した。`--listen=-`は付けない。ハッシュは再ビルドで変わるので固定パスを再利用しない。

- 通常：コア999成功・5 skip、ホスト62成功・1 skip、合計1061成功・6 skip。ホストのskipはSDL3仮想ゲームパッド。通常ビルドも成功。
- 最小構成：コア531成功・447 skip、ホスト54成功・6 skip、合計585成功・453 skip。
- 初回はWindowsビルドランナー内の追加CLI実行ステップを直接実行できなかった。追加検証では同じ9ケースをWSLで実行して成功した（上の最終結果）。

証跡：`.work/wsl-cross-build.log`、`wsl-cross-test.log`、`wsl-core-tests.log`、`wsl-host-tests.log`、`wsl-minimal-build.log`、`wsl-minimal-first.log`、`wsl-minimal-second.log`。

## WSL内での統合確認

リポジトリのルートで実行する。

```sh
python3 tests/scripts/verify-blocks.py .work/wsl-build/bin/sigma
python3 tests/scripts/verify-ekey.py .work/wsl-build/bin/sigma
python3 tests/scripts/verify-runtime.py --sigma .work/wsl-build/bin/sigma --output .work/wsl-runtime.json
python3 tests/scripts/verify-output-activity.py --sigma .work/wsl-build/bin/sigma --output .work/wsl-output-activity.json
python3 tests/scripts/test-line-editor.py --sigma .work/wsl-build/bin/sigma
python3 tests/scripts/verify-posix-native.py --sigma .work/wsl-build/bin/sigma --output .work/wsl-native/report.json
```

すべて成功。

- ブロック：BYE/EOF保存、入れ子LOAD、例外と入力復元、辞書読込、SAVESYS終了時保存。
- EKEY：パイプの非待機・Unicode・不正シーケンス・文字3、POSIX PTYのEscape待ち、Ctrl+C、KEY/ACCEPTとの共存。
- ランタイム13件：再帰上限と回復、出力順、SYSTEM、大量出力、flush、KEY前の表示。
- SHOW 20件：半ブロック/Sixelの疑似端末出力について、直接STDOUT書込やSYSTEM/SH/EDITORの後は旧フレームへ戻らず、連続SHOWや空書込等では再利用することを確認。端末のSixel画面の目視確認ではない。
- 行編集18件：履歴、編集、Unicode、狭い幅、幅未設定、Ctrl+Z/SIGCONT、端末状態復元など。
- POSIX追加10件：パイプ入出力と復元、SH-GETのNUL/改行/終了コード、引用符・日本語・空白・シェル文字を含むソース名、エディタ一時レポートの権限と成功/失敗時削除、辞書/実行イメージを通したエディタ呼出し。

行編集の幅未設定テストは当初失敗した。ログで、バナーが表示された直後、rawモード切替前に入力した文字を端末がエコーしていたことを確認。テストのSessionがICANON/ECHO解除を待つよう変更し、全18件を再実行して成功した。処理系の行編集コードは変更していない。

DrvFs上の作業フォルダーはPOSIXの0600を保持せず、検証時に0777として見えた。一時レポートの権限検証にはLinux側`/tmp`の専用一時フォルダーを使い、0600と終了後の削除を確認した。DrvFs上で0600が保証されたという結果ではない。

## 今回の確認に含めないもの

- 指定コミットのGforth比較。WSLにあるGforthは0.7.9_20260410であり、指定の1.0.1ビルドとは異なるので比較元に代用していない。
- WSL内のLinux版Zigでのビルドランナー全体の完走。
- 物理キー・IME、GUIエディタ、端末画面の目視、独立したLinux実機。
- P10全体の全組合せ・すべての単独機能除外構成。

実施内容はtque710/711〜717と追加728〜741へ記録した。Windows/WSLの607は今回完了。P10/542全体の完了、コミット・push、版番号変更、パッケージ作成は行っていない。

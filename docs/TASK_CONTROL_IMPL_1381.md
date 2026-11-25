# タスク制御06-E：構成試験（1381）

作成日：2026-11-24。作成者：ロク。対象は`D:/tmp/forthz-1381`、開始時HEADは`29f3d03`（detached HEAD）である。

## 1. 対象と仕様

[1378の構成計画](TASK_CONTROL_CONFIG_MATRIX.md)5節のC00〜C16を、[決定済み公開API](TASK_CONTROL_PUBLIC_API_PROPOSAL.md)に照らして検証する。計画当時の「D06待ち」は現在の判断ではない。公開TASK-語58語はEXTENSIONに属し、graphics/audioはextensionを自動有効化しない。652のEXEC-LIMITEDはdebugとextensionの両方が有効な場合だけ公開される。DBGはextensionと独立してdebugに従う。worker内の652は公開API6節により禁止である。

計画C00/C02/C04/C06の「652は残る」と、公開EXEC-LIMITEDの有無は区別する。同語は`words_extension.zig`に属し、`defs.zig`ではextension除外とdebug除外のどちらでも除外される。このためE=0ではdebug=trueでも同語を公開しない。これは本作業での仕様変更ではなく、現行実装の語群境界である。debug基盤の有効性はDBGと既存core試験で別に確認する。

[利用条件](TASK_CONTROL_USAGE_CONDITIONS.md)の時間・容量目標の達成と、[受け入れ表](TASK_CONTROL_ACCEPTANCE.md)全行の完了を、本構成試験の成功と同一視しない。期限の上限を試験内で用いることと、経過時間の測定は区別する。本作業では速度・時間・資源量を測定しない。

## 2. 変更内容

- `tests/scripts/verify-task-public-matrix.py`：既存11構成にC02/C03/C04/C05/C10/C12を加え、全17構成とした。58語の件数・重複、debug語の独立選択、メインの予算、除外時の能力拒否を照合する。runtime試験を直接起動し、buildの実行キャッシュとは別に結果を残す。クロスコンパイル専用引数、実行コマンド記録、作業ツリー内キャッシュを追加した。
- `tests/scripts/check-task-public.fs`：無限ループの取消し、終端回収、両ID解放、その後のメイン計算を追加した。debug=falseでも同じ試験を実行する。取消し要求が実行開始前に成立する場合もあり、このForth試験だけで実行中の確認点を網羅したとはしない。実行中の取消しは既存runtimeの制御された試験と併せて確認する。
- 利用者向け手順は英語を主とする[TASK_CONTROL_CONFIG_TESTING.md](TASK_CONTROL_CONFIG_TESTING.md)と[日本語版](TASK_CONTROL_CONFIG_TESTING.ja.md)である。

処理系の製品ソースと担当外モジュールは変更していない。第三者コード・ライブラリの追加はない。

## 3. Windowsの計画と結果

A/G/Eはaudio/graphics/extensionである。指定しないbool optionは既定値trueである。レビュー前の実行コマンドはPowerShellから`python tests/scripts/verify-task-public-matrix.py`である。下表のbuild/test「成功」はその実行のキャッシュ利用・終了コード0を示す。新規キャッシュによる再検査は4節に分けて記録する。`zig version`の出力は0.17.1であった。スクリプト内部の`zig build test -j2`はPowerShellから起動したPythonの子プロセスとして実行し、Git Bashを使わない。

| 計画ID | A/G/E | debug | 追加false | build/test | 公開語数 | runtime成功/skip/失敗 | DBG/EXEC-LIMITED | 能力拒否 |
|---|---|---|---|---|---|---|---|---|
| C00 | 000 | 1 | なし | 成功 | 0 | 148/25/0 | 有/無 | 対象なし |
| C01 | 001 | 1 | なし | 成功 | 58 | 165/8/0 | 有/有 | graphics |
| C02 | 010 | 1 | なし | 成功 | 0 | 151/24/0 | 有/無 | 対象なし |
| C03 | 011 | 1 | なし | 成功 | 58 | 168/7/0 | 有/有 | 対象なし |
| C04 | 100 | 1 | なし | 成功 | 0 | 148/25/0 | 有/無 | 対象なし |
| C05 | 101 | 1 | なし | 成功 | 58 | 165/8/0 | 有/有 | graphics |
| C06 | 110 | 1 | なし | 成功 | 0 | 151/24/0 | 有/無 | 対象なし |
| C07 | 111 | 1 | なし | 成功 | 58 | 168/7/0 | 有/有 | 対象なし |
| C08 | 001 | 0 | なし | 成功 | 58 | 164/9/0 | 無/無 | graphics |
| C09 | 001 | 1 | files | 成功 | 58 | 164/9/0 | 有/有 | files,graphics |
| C10 | 111 | 0 | files | 成功 | 58 | 166/9/0 | 無/無 | files |
| C11 | 001 | 0 | files,float,image,x11 | 成功 | 58 | 163/10/0 | 無/無 | files,graphics |
| C12 | 000 | 0 | なし | 成功 | 0 | 148/25/0 | 無/無 | 対象なし |
| C13 | 010 | 0 | なし | 成功 | 0 | 151/24/0 | 無/無 | 対象なし |
| C14 | 111 | 0 | help | 成功 | 58 | 167/8/0 | 無/無 | 対象なし |
| C15 | 111 | 0 | tools | 成功 | 58 | 167/8/0 | 無/無 | 対象なし |
| C16 | 011 | 0 | x11 | 成功 | 58 | 167/8/0 | 無/無 | 対象なし |

Windowsで未実行となった構成はない。能力拒否欄は、無効化したfeatureについて期待値-311を実行体で確認したことを示す。全構成で内部Runtimeの指定7試験がOKであることをスクリプトが検査した。表の成功/skipはruntime直接実行の件数であり、core・hostを含む総試験数ではない。

C07のskip 7件は、任意の実窓2件とPOSIX専用5件である。graphics除外・debug除外・files除外・E=0では、さらに該当する公開API・許可語等の試験がskipとなる。全skipの名前は構成別runtimeログに残る。

共通検査はbuild、`zig build test`、58語の有無、DBG/EXEC-LIMITEDの有無、runtime直接実行である。E=1ではさらに公開Forth ABI（投入・成功・結果コピー・SHORT再取得・非消費・失効ID・解放・時計複合待機）と取消しを検査する。debug=trueかつE=1では予算20で無限ループが-280となり、同じプロセスのworker取消しが状態5となり、次の予算0の計算が42とior=0を返すことを確認する。files=falseのkind=2、graphics=falseのkind=5は`-311 0 0`を要求する。

内部Runtimeは`src/runtime_test.zig`から取り込まれるClock/Deadline・Wake・Cancellation・ResourceTable・所有者終了の既存試験を構成ごとに実行する。E=0では公開API試験のskipが正当である一方、`src/tests/runtime_base_test.zig`と`host_runtime.zig`の基盤試験にはEXTENSIONによるskipがないことをソースで照合する。公開語の不在だけから実行体に残る内部コード量を断定しない。

## 4. 証拠と追加検査

構成ごとの標準出力・標準エラーは`.work/task-public-matrix/Cxx-*.log`、完了構成は`results.json`、コマンドは`commands.json`へ保存する。レビュー前のbuild/testログは0バイトであり、当時の「成功」はキャッシュを利用した終了コード0である。新規コンパイル・再実行の証拠とはしない。修正版は`--summary all`を記録する。JSONとプロセス終了コードを併せて確認する。直接実行したruntime試験は`Cxx-runtime.log`で成功・skip・失敗を確認する。

| 検査 | 結果 |
|---|---|
| Windowsレビュー前マトリクス | 全17構成終了コード0。build/testはキャッシュ利用 |
| Python構文検査 | 成功 |
| `python scripts/check-docs.py` | 成功、指摘0件 |
| git diff --check | 成功 |
| macOSクロスコンパイル | aarch64-macos向けC00〜C16全17構成成功、終了コード0。対象OSでは未実行 |

macOSのコマンドは次のとおりである。Windowsの表の全17行と同じfeature指定で実行体・core/host/runtime試験実行体・freestanding境界をコンパイルした。未コンパイルの計画構成はない。記録は`.work/task-public-matrix/aarch64-macos/results.json`と`commands.json`、`Cxx-compile.log`、`Cxx-build.log`である。

```powershell
python tests/scripts/verify-task-public-matrix.py --build-only --target aarch64-macos
```

初回の文書検査では英日手順書の見出し数・コードブロック数の不一致2件を検出した。英語版の例を日本語版と同じ構成へ揃え、再検査で指摘0件となった。製品の不具合は本試験では見つかっていない。


### レビュー対応

6点とも指摘の趣旨を妥当と判断した。E=0の検査拡張は行わず、既定検索順の語の不在だけであることと、HELP・保存イメージ等の未確認範囲を5節および英日手順書へ明記した。

`--fresh-cache`を追加し、呼出しごとに新しい`.work/fresh-*/.zig-global-cache`と`.zig-cache`を指定する。グローバル側は`ZIG_GLOBAL_CACHE_DIR`、ローカル側は`--cache-dir`で指定する。1回の全17構成は初めは空のキャッシュを共有する。同一実行内で共通依存物や同一試験成果物が再利用されることはあるため、全行の全工程をキャッシュなしと表現しない。`--summary all`とコマンドの終了コードを保存し、コンパイル・試験の実行とcachedを区別できるようにした。速度・所要時間の集計や比較は行っていない。

初回の新規キャッシュ実行は、Zig 0.17.1が`--global-cache-dir`を受け付けずC00のbuild入口で終了コード1となった。環境変数による指定へ修正し、別の新規キャッシュで全構成を再実行した。

各results.json行へplatform.platform()、OS、arch、zig version出力、Python版、DISPLAY/WAYLAND_DISPLAY/TERM、親プロセスのstdin/stdout/stderrのisatty()、キャッシュパスを追加した。TTYは子プロセスの実端末試験の成功を意味しない。runtimeログの`N passed; M skipped; K failed`を解析して各件数を保存し、欠落・失敗を拒否する。build-only行はruntime件数をnullとし、未実行と区別する。

有効なfilesのkind=2は既存の`public many wait preserves inputs on Ctrl-C equivalent and combines IO reasons`、有効なgraphicsでネイティブbackendが対応するkind=5は`public paint many validates arguments, backend, lifetime and simultaneous events`のOKを必須にした。前者は注入I/Oによる受理とreadable/writable複合結果、後者は合成した描画状態による受理・待機中・完了を検証している。実ファイルや実窓の結合試験とはしない。後者の受理分岐はgraphicsと`host_window.available`が必要であり、Linux C16はその受理済み件数に含めない。さらにE=1の全構成で窓なしのkind=5が`-311 0 0`を返すことを要求した。これによりLinux C16の未対応描画も同じ検査で拒否を要求するが、Linux実行結果は引継ぎ待ちである。

英日の準備条件・標準エラーと終了コードの保存・results.json全置換の説明を揃えた。`src/tests/runtime_base_test.zig`のパスも修正した。


新規キャッシュ再実行の結果はC00〜C16全17構成成功、スクリプト終了コード0である。コマンドはPowerShellから次のとおり実行した。

```powershell
python tests/scripts/verify-task-public-matrix.py --fresh-cache > .work/task-public-windows-fresh.log 2>&1
$LASTEXITCODE
```

環境はWindows-11-10.0.26300-SP0、AMD64、Zig 0.17.1、Python 3.14.3である。DISPLAY/WAYLAND_DISPLAYは未設定、TERMはdumb、親プロセスのstdin/stdout/stderrのisattyはすべてfalseであった。使用した新規キャッシュは`.work/fresh-3da6b62271094a87aac982aeb779c417/`配下の`.zig-global-cache`と`.zig-cache`である。完了17行と記録された132コマンドの終了コード0を照合した。全行のruntime件数をログと照合し、一致を確認した。C00のtestログではcore・host・runtimeのcompileとrunが成功として記録されており、レビュー前の空ログによる記録とは異なる。Zigが自動出力する所要時間やMaxRSSは評価・集計していない。

| 構成 | runtime成功/skip/失敗（新規キャッシュ再実行） |
|---|---|
| C00 | 148/25/0 |
| C01 | 165/8/0 |
| C02 | 151/24/0 |
| C03 | 168/7/0 |
| C04 | 148/25/0 |
| C05 | 165/8/0 |
| C06 | 151/24/0 |
| C07 | 168/7/0 |
| C08 | 164/9/0 |
| C09 | 164/9/0 |
| C10 | 166/9/0 |
| C11 | 163/10/0 |
| C12 | 148/25/0 |
| C13 | 151/24/0 |
| C14 | 167/8/0 |
| C15 | 167/8/0 |
| C16 | 167/8/0 |

新規キャッシュ試験でもruntime件数は3節のレビュー前の表と一致した。全行のtest/buildログにBuild Summaryを残した。E=1の11構成で窓なしpaint拒否を確認した。有効I/Oの制御試験はC01/C03/C05/C07/C08/C14/C15/C16、描画受理の制御試験はC03/C07/C10/C14/C15/C16で確認した。Windows C16の成功をLinux C16の成功とはしない。macOSクロスコンパイルはレビュー前の結果を維持し、今回の修正版では再実行していない。

Python構文検査、`python scripts/check-docs.py`（指摘0件）、`git diff --check`も成功した。Linux引継ぎコマンドには`--fresh-cache`を追加した。

## 5. 未実施の項目と計画の限界

- Linux上での実行は未実施である。利用者指定により、別機械のClaudeへ引き継ぐ。Windowsでの成功をLinuxの成功とはしない。
- macOS実機は1383の担当であり、ここではクロスコンパイルだけである。
- C03/C07/C10の実入力・I/O・描画との同時結合、C05/C07/C10の実音声と取消し・終了、C02/C06/C13の実画面、C16のLinux X11なしbackendの端末・画面結合は、本マトリクスでは受け入れ未実施である。既存の疑似・制御試験やビルド成功で置き換えない。これらは構成そのものを実行できなかった項目ではなく、計画行に含まれる実機結合の残項目である。
- 実端末のCtrl+C、物理的な描画提示、OS全体の残存スレッド・機器・子プロセスの実機確認は未実施である。任意の実窓試験を有効化していないため、そのskipは成功としない。
- 利用条件の最大滞留、結果公開、取消し、回収等の期限の受け入れ確認は未実施である。手順は同一構成・用途・入力条件を固定し、投入・開始・終端・回収の各時点を記録して利用条件の基準と照合するものである。ただし、本タスクでは時間測定を禁止されているため実行しない。別途許可された受け入れ作業で行う。
- 1381実施時のE=0検査は既定検索順の`[DEFINED]`だけだった。1400で検索順に依存しない辞書表・TASK固有HELP項目・保存イメージの追加builtin／直接Opの除外・拒否時の辞書保持の試験を追加した。構成別の条件は[TASK_CONTROL_CONFIG_MATRIX.md](TASK_CONTROL_CONFIG_MATRIX.md)、実行結果と境界は[1400記録](TASK_CONTROL_IMPL_1400.md)を参照する。全保存イメージ互換の保証ではない。通常ループの生成コード量は1390で確認し、性能・追加128 MiBの実測も本試験の対象外である。

## 6. Linux x86_64への引継ぎ

英日手順書と同じスクリプトを渡す。Zig 0.17.1とPython 3、1381の変更を含むソースを用意し、Linuxのリポジトリルートで実行する。

```sh
zig version
python3 --version
uname -sm
mkdir -p .work
python3 tests/scripts/verify-task-public-matrix.py --fresh-cache > .work/task-public-linux.log 2>&1
printf '%s\n' "$?"
cat .work/task-public-linux.log
cat .work/task-public-matrix/results.json
```

終了コード0、C00〜C16の17行、各行のtest/build成功、公開語の有無、runtimeの基盤試験とskipの内訳を照合する。失敗した場合は該当行と`commands.json`が指すログを報告する。再試行例は`python3 tests/scripts/verify-task-public-matrix.py --configs C08 C11 C12 C16`である。再実行前に全実行のログ・JSONを退避する。毎回results.jsonは空配列に戻り、--configsの再試行後は選択した完了行だけが残る。初回失敗と修正後成功は別に記録する。

C16はx11=falseであって、実画面が必ず使えるという契約ではない。Linuxの実backend・端末結合は利用可能な環境を明記して別途行う。ログ・JSON・実行環境・skipと未実施の理由を回収し、本書のLinux欄を更新する。Linux C16の窓なしkind=5に`-311 0 0`を要求する検査を追加したが、Linux実行は未実施である。Linuxでの時間測定も本タスクの依頼範囲に含めない。

### 6.1 Linux x86_64での実行結果（2026-11-24）

上の手順の `verify-task-public-matrix.py --fresh-cache` を、Linux機（`ssh fuk@192.168.12.12`、リポジトリ `/home/fuk/source/zig/ForthSigma`）で、1380・1381の変更を当てたソースに対して実行した。終了コードは0で、C00〜C16の17構成がすべて成功した。C16の窓なしkind=5の検査も、この実行に含まれる。

| 項目 | 値 |
|---|---|
| platform | Linux-7.0.0-43-generic-x86_64-with-glibc2.43 |
| Zig / Python | 0.17.1 / 3.14.4 |
| DISPLAY・WAYLAND_DISPLAY・TERM | 未設定（ssh越しの非対話実行） |
| キャッシュ | 新規の .zig-global-cache・.zig-cache（fresh_cache=true） |
| results.json | 17行、すべて成功 |

同じ機械で、`zig build runtime-test`・`zig build test`・`zig build test -Ddebug=false`・`zig build`、`tests/scripts/verify-task-examples.py`（15群）、`tests/scripts/check-task-public.fs` も成功した。端末と画面を使う確認は、この実行には含まれない。

## 7. 作業ツリー

コミット・タグ・ブランチ作成・push・tque変更は行っていない。成果物・キャッシュはすべて作業ツリー内である。

最終確認時の`git status --short`は次のとおりである。

```text
 M tests/scripts/check-task-public.fs
 M tests/scripts/verify-task-public-matrix.py
?? docs/TASK_CONTROL_CONFIG_TESTING.ja.md
?? docs/TASK_CONTROL_CONFIG_TESTING.md
?? docs/TASK_CONTROL_IMPL_1381.md
```

HEADは`29f3d03`、detached HEADを維持している。

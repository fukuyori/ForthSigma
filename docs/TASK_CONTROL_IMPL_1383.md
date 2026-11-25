# 1383 タスク制御 06-G macOS 実機受入れの準備

> 現行の固定値・再測定手順は末尾「2026-11-25 決定B」を参照。以下の旧固定値と結果は履歴として保持する。

2026-11-25、ロク。対象はmain、準備開始時HEAD fe2f81206448c8fb62df5c7b86a3bffdc2129b1f。
準備時点ではコードと文書の整備のみを行った。その後Claudeが行ったMac実機での事前確認結果は下記に記録する。本測定と実機受入れ全体の合否判定は未実施である。git commit・branch・push、tque変更は行わない。

## 固定計画

[macOS計画 v1](TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md) の固定SHA-256：

```text
ffb8e936ddda6df8cec2a5b3c789b3664155a365eccb1d9a6e15d715ab44a18b
```

1382の計画は変更していない。固定値は引き続き
`7b341c1b6f6b12eeab2c6aa5bf31f24cde48c4e8bb555a89856744496dfc6032`。
1383の縮小回数（取消し位相ごと100、native5種×3位相、対話10分×1、メモリ3）は初期案である。**1383にも同じ回数を使うかは測定の前に利用者へ確認する。** 確認はClaudeが記録する。変更時は計画を先に改訂してSHAも再固定する。

**回数の確認（2026-11-25）：** レモンが、1382と同じ縮小回数（推奨案）を1383でも使うことを決めた。計画の回数は変わらないので、計画のファイルとSHA-256は変えない。本測定の`--confirmed`には、この確認を示す参照 `lemon-approved-2026-11-25-1383-reduced-counts` を使う。

## 変更内容と根拠

- runnerはDarwin上でmacOS計画を選び、--planで明示もできる。開始前/終了時の同一バイト照合と証拠コピーを維持する。Aのビルド来歴は--baseline-build-manifestで証拠へコピーできる。通常ビルドのstrip=trueも明示した。
- Mach-Oは64-bit arm64のLC_SEGMENT_64/section_64から__TEXT,__textを解析する。fatは明示拒否、CPU/command/section/ファイル範囲を検査する。PE/ELF経路は保持した。
- macOS memoryはlibprocをctypesで呼ぶ。常駐・phys_footprint・仮想サイズを別名で保存し、Windows committedという名前へ詰め替えない。128 MiBと比較するのはphys_footprintの基準/負荷差であり、その選択は計画で「※推測です」と明示した。仮想/常駐は参考。私有予約・コミット上限の合格は未証明とする。
- SDKの根拠はApple公開 [resource.h](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/resource.h) のrusage_info_v4、[proc_info.h](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc_info.h) のproc_taskinfo、[libproc.h](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.h)。宣言/配置を参照して独立にctypesを定義し、実装コードの転載はしていない。Macでは下記のC検査で実際のSDK配置を確認する。
- Zigの内部時計は既存のhost_clock.now→clock_gettime(CLOCK_MONOTONIC)。host_clock.resolutionNsを加え、probe開始時にclock_getresの分解能を記録する（WindowsはQPC frequencyから切上げns）。Pythonは既存perf_counter[_ns]、get_clock_infoを保存し単調性を検査する。親子の値は引き算しない。
- 子はthreadを含む単一プロセスであり、PythonのPopen/kill/wait、背景pipe reader、sampler停止/joinはPOSIX共通経路でmacOSにも適用される。native観測期限のkillと自然終了の競合はProcessLookupErrorを許容する。端末なしの実入力経路はMac smokeに残す。
- host_task_apiのfreshZeroPagesはLinux/Windows限定の最適化で、macOSは従来の明示初期化へ進む。未検証のゼロページ保証をmacOSへ拡張していない。これは対応漏れによる機能不能ではない。

回収の説明はソースを確認してから英語HELP生成元、対訳TSV、examples英日へ追加した。
[src/host_task_api.zig:195](../src/host_task_api.zig#L195) はhandback等を確認して無効IDの資源を回収する。
同 [377行](../src/host_task_api.zig#L377) が通常タスク語の呼出し時、
[668行](../src/host_task_api.zig#L668) がTASK-WAIT-MANYのService.poll呼出し。
MS・EKEY?・描画からこのService.pollは呼ばれない。TASK-RELEASEはその巡の事前poll後に外部IDを無効にするため、後続の巡でのtask語呼出しが必要になる。
`TASK-WAIT-MANY` の時計target・期限0を毎巡呼び続ける例を記した。
`scripts/word-reference.py --record-reviewed-sources` で対訳の原文記録とWORD_REFERENCE英日を再生成した。

## Mac 実機での事前確認（2026-11-25）

以下はレモンから共有されたClaudeの実機確認結果であり、ロクがWindowsで再実行した結果とは区別する。本測定ではない。

- 環境：arm64、macOS 27.2.1、Zig 0.17.1、Python 3.15.2、XcodeのMacOSX.sdk。
- ABIのC検査、`test-acceptance-macos.py`（14件）、`zig fmt --check`、`zig build test`（通常と`-Ddebug=false`）、`runtime-test`、`-Dtask-acceptance=true`のビルド、`verify-task-examples.py`（16グループ）、`check-docs.py`（指摘0）は、すべて終了コード0。
- smoke（workloads・snapshot・response・reclaim・memory）とnativeの事前確認も終了コード0。計画のSHA-256は上記の`ffb8e936…a18b`と一致し、text属性はunsetだった。
- 子の時計は`CLOCK_MONOTONIC`、`resolution_ns=1000`（1µs）。親は`mach_absolute_time()`で約41.7ns。親子の時計値を直接引き算しない。
- 実プロセスの`darwin_memory`では、64MiBを書き込むと`phys_footprint`が11,436,536から78,610,984バイトへ増え、値を取得できた。これだけでメモリ予算全体の合格とはしない。
- nativeではROLLなど5つの位相が「最初の3回とも取り逃し」で打ち切られた。Windowsと同じ傾向であり、終了コード0でも欠測位相の成功や取消し応答の合格を意味しない。

1µsは10msの1/10,000（0.01%）、100msの1/100,000（0.001%）であり、**時計の分解能という点では、10ms・100msの目安を測るのに足りる**。ただし分解能は測定精度や応答時間の保証ではない。実行時のスケジューリング、観測処理の費用、位相の欠測は別に評価する必要があり、今回の事前確認から本測定の合否は判断しない。

## Claudeの実機手順

以下は準備時に記したClaude用の手順。実施済みの範囲は上記の事前確認結果に従う。SSHのリモートコマンドとして各zsh -lcを渡す（ホスト名/接続方法はClaudeの既存環境を使う）。自動検査・smokeはTTYなし、手動は前景の実端末で行う。各コマンドはリポジトリの外への書込みを必要としない。/opt/homebrew/binをPATHの先頭にする。

### 1. 自動の検査

```sh
zsh -lc '
set -eu
export PATH=/opt/homebrew/bin:$PATH
cd ~/source/zig/ForthSigma
mkdir -p .work/1383
export ZIG_GLOBAL_CACHE_DIR=$PWD/.work/1383/global
export ZIG_LOCAL_CACHE_DIR=$PWD/.work/1383/local
{
  git status --short
  git rev-parse HEAD
  uname -a
  uname -m
  sw_vers
  command -v zig python3
  zig version
  python3 --version
  xcrun --show-sdk-path
  shasum -a 256 "$(command -v zig)" "$(command -v python3)"
} > .work/1383/environment.txt
sdk=$(xcrun --show-sdk-path)
shasum -a 256 "$sdk/usr/include/sys/resource.h" "$sdk/usr/include/sys/proc_info.h" "$sdk/usr/include/libproc.h" > .work/1383/sdk-headers.sha256
xcrun clang -std=c11 -Wall -Wextra -Werror tests/scripts/acceptance-macos-abi.c -o .work/1383/macos-abi
.work/1383/macos-abi > .work/1383/macos-abi.log
python3 tests/scripts/test-acceptance-macos.py > .work/1383/python-tests.log 2>&1
zig fmt --check src/host_clock.zig src/core/task_acceptance.zig src/core/help_text.zig
zig build test > .work/1383/test.log 2>&1
zig build test -Ddebug=false > .work/1383/test-plain.log 2>&1
zig build runtime-test > .work/1383/runtime.log 2>&1
zig build -Dtask-acceptance=true > .work/1383/probe-build.log 2>&1
python3 tests/scripts/verify-task-examples.py > .work/1383/examples.log 2>&1
python3 scripts/check-docs.py > .work/1383/docs.log 2>&1
'
```

エラーならそのログを残して停止する。Apple Silicon arm64、Zig/Python等が依頼の確認済み値と違う場合も記録して構成を確認する。実機のABI検査はWindowsの模擬検査やクロスビルドでは代替できない。

### 2. 事前の確認（smoke）

```sh
zsh -lc '
set -eu
export PATH=/opt/homebrew/bin:$PATH
cd ~/source/zig/ForthSigma
expected=ffb8e936ddda6df8cec2a5b3c789b3664155a365eccb1d9a6e15d715ab44a18b
actual=$(shasum -a 256 docs/TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md)
test "${actual%% *}" = "$expected"
git check-attr text -- docs/TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md
python3 tests/scripts/run-acceptance.py --mode smoke --only workloads snapshot response reclaim memory --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md --plan-sha256 "$expected"
python3 tests/scripts/run-acceptance.py --mode smoke --only reclaim --probe-cases native-roll native-fill --repetitions 3 --plan-sha256 "$expected"
'
```

text属性がunset（-text）であることを確認する。results.jsonと各raw.log/JSONを読み、子のCLOCK_MONOTONIC/resolution_ns、親のmonotonic/resolution、q入力終了、BASELINE-READY/ACCEPTANCE-MEMORY-HOLDの採取と応答、OS採取エラーなしを確認する。smokeでは時刻0/null、速度統計なしである。位相欠測を成功にしない。手動確認は計画7節と英日manualに従い別記する。

### 3. 本測定（利用者の確認後にClaudeが実行）

下記の環境変数は、Claudeがレモンの確認内容を識別できる参照として事前設定する。未設定ならコマンドは停止する。変数の存在だけで利用者の確認を得たことにはならない。

```sh
zsh -lc '
set -eu
export PATH=/opt/homebrew/bin:$PATH
cd ~/source/zig/ForthSigma
: "${ACCEPTANCE_1383_CONFIRMATION:?record the user confirmation first}"
python3 tests/scripts/run-acceptance.py --mode measure --only reclaim snapshot memory workloads response --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md --plan-sha256 ffb8e936ddda6df8cec2a5b3c789b3664155a365eccb1d9a6e15d715ab44a18b --confirmed "$ACCEPTANCE_1383_CONFIRMATION"
'
```

80%超の追加は計画3節に従いcase/位相を限定して新runに保存する。取消し/Snapshotは--repetitions 1000、メモリは10。対話は当該caseのみのmeasureを独立2回実行する。--probe-cases、取消し位相は--probe-stagesで指定する。自動合格にせずmissing/extend_requiredを点検する。

### 4. 対照Aのビルド

MacでのAのビルドは未確認。以下のsource/output先は新規のものとし、既存の場合は保存済み証拠を上書きせず停止する。git archiveはbranch/commitを変更しない。参照コミットがローカルにない場合は、その事実を記録してClaude側でソース取得の範囲を確認する。

```sh
zsh -lc '
set -eu
export PATH=/opt/homebrew/bin:$PATH
cd ~/source/zig/ForthSigma
root=$PWD
mkdir -p .work/1383
mkdir .work/1383/control-a-source
mkdir .work/1383/control-a-build
export ZIG_GLOBAL_CACHE_DIR=$root/.work/1383/a-global
export ZIG_LOCAL_CACHE_DIR=$root/.work/1383/a-local
{
  echo 35523f676836134c4fbaed19e3d01d2a23ec2a92
  zig version
  command -v zig
  uname -m
  xcrun --show-sdk-path
  shasum -a 256 "$(command -v zig)"
  echo "zig build -Doptimize=ReleaseFast -Ddebug=false -Dstrip=true --prefix $root/.work/1383/control-a-build -j2"
} > .work/1383/control-a-provenance.txt
git archive --format=tar --output=.work/1383/control-a.tar 35523f676836134c4fbaed19e3d01d2a23ec2a92
shasum -a 256 .work/1383/control-a.tar >> .work/1383/control-a-provenance.txt
tar -xf .work/1383/control-a.tar -C .work/1383/control-a-source
cd .work/1383/control-a-source
if zig build -Doptimize=ReleaseFast -Ddebug=false -Dstrip=true --prefix "$root/.work/1383/control-a-build" -j2 > "$root/.work/1383/control-a-build.log" 2>&1; then
  shasum -a 256 "$root/.work/1383/control-a-build/bin/sigma" >> "$root/.work/1383/control-a-provenance.txt"
else
  echo "A build failed; startup/size comparison unverified" >> "$root/.work/1383/control-a-provenance.txt"
  exit 1
fi
'
```

Aが失敗すれば次の比較は実行せず、startup・sizeのA/Bを未確認とする。Aのpatch・別SHA・別architectureで穴埋めしない。

### 5. startup・size

Aがビルドできた場合は、まず未計時smokeで起動markerとMach-O解析を確認する。Bはrunnerが通常構成で作る。本測定は確認後のみ行う。

```sh
zsh -lc '
set -eu
export PATH=/opt/homebrew/bin:$PATH
cd ~/source/zig/ForthSigma
python3 tests/scripts/run-acceptance.py --mode smoke --only startup size --baseline .work/1383/control-a-build/bin/sigma --baseline-build-manifest .work/1383/control-a-provenance.txt --plan-sha256 ffb8e936ddda6df8cec2a5b3c789b3664155a365eccb1d9a6e15d715ab44a18b
'

zsh -lc '
set -eu
export PATH=/opt/homebrew/bin:$PATH
cd ~/source/zig/ForthSigma
: "${ACCEPTANCE_1383_CONFIRMATION:?record the user confirmation first}"
python3 tests/scripts/run-acceptance.py --mode measure --only startup size --baseline .work/1383/control-a-build/bin/sigma --baseline-build-manifest .work/1383/control-a-provenance.txt --plan-sha256 ffb8e936ddda6df8cec2a5b3c789b3664155a365eccb1d9a6e15d715ab44a18b --confirmed "$ACCEPTANCE_1383_CONFIRMATION"
'
```

A/Bの起動はready marker親受信でありpipe/schedulerの費用を含む。サイズは実行体全体と__TEXT,__textを分ける。A/A′/Bの逆アセンブル・通常単一VM比較はrunner未対応。AC-29全体の合格とはしない。

## 所要時間の初期枠

対話7ケース×600秒=70分、native観測窓最大375秒。※推測です：自動検査・ビルド・smoke20〜60分、短い本測定群とAビルド/比較10〜30分、手動15〜30分を加え、約2〜3.5時間を確保する。Mac実測からの見積りではない。追加規則・失敗調査・異常guardの時間は別枠である。

## Windowsでの検証

Windows PowerShell、Zig 0.17.1、Python 3.14で実行した。キャッシュはリポジトリ内の .work/1383/ に分けた。以下はすべて終了コード0。Mac指定Python 3.15.2の実行とは区別する。

| 検査 | 結果・ログ |
|---|---|
| `zig build test` | 成功、`.work/1383/test.log` |
| `zig build test -Ddebug=false` | 成功、`.work/1383/test-plain.log` |
| `zig build runtime-test` | 成功、`.work/1383/runtime.log` |
| `zig build -Dtask-acceptance=true` | 成功、`.work/1383/probe-build.log` |
| `python tests/scripts/verify-task-examples.py` | 16グループ成功、`.work/1383/examples.log` |
| `python scripts/check-docs.py` | findings: 0、`.work/1383/docs.log` |
| 変更したZig3ファイルの `zig fmt --check` | 成功（host_clock、task_acceptance、help_text） |
| `zig build -Dtarget=aarch64-macos -Dtask-acceptance=true --prefix .work/1383/macos` | 成功、`.work/1383/cross.log`。生成Mach-Oを新parserで読めることも確認 |
| `python tests/scripts/test-acceptance-macos.py` | 14検査成功、`.work/1383/python-tests.log` |
| runnerのWindows未計時smoke（Snapshot・メモリSnapshot） | 成功、`.work/1383/runner-smoke.log`、下記run |

Python検査はthin arm64合成Mach-O、fat4形式拒否、別CPU/section/segment、切れたheader/command/section、範囲外、zero-fill拒否、SDK想定のsizeof/offset、libproc模擬応答の生bytes復号、API失敗/短い読取り、OS別計画/予算の選択を含む。さらに実際のPython子を使い、端末なしpipeの保持点採取→改行応答→終了と、b入力→marker→q終了を確認した。実機libprocは使っていない。

Windows smokeは `--mode smoke --only snapshot memory --probe-cases snapshot --sigma zig-out/bin/sigma.exe --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md --plan-sha256` に上記固定値を渡して実行した。証拠は `.work/acceptance/20261124T200715Z-12003e70/`。固定計画コピー、親時計の単調性、子QPCの分解能、保持点の全応答、OS採取エラーなし、端点0、速度統計空を確認した。これはmacOS計画選択と形式の機能確認であり、Windows値をmacOS受入れ標本にはしない。

1382計画のSHAが元の固定値のままであること、両計画のtext属性がunsetであること、`git diff --check` も確認した。検査成功を各OSの手動項目やskip対象の成功へ拡張しない。

クロスビルドはMac実機の代わりではない。macOSのlibproc実呼出しと実SDK ABIの事前確認は上記の共有結果により確認済み。端末/画面/音/電源下の実動作、Aのビルド、本測定は未確認として残す。本測定、Git commit・branch・push、tque変更は行っていない。

## Claudeレビュー反映後のWindows再検証（2026-11-25）

TASK-RELEASEとTASK-WAIT-MANYのHELPから内部名Service.pollを除き、回収はタスクの語の呼出し中だけ進み、MS・EKEY?・描画では進まない旨を短く記した。日本語対訳とWORD_REFERENCE英日、原文の指紋も更新した。

Windows PowerShellで、`zig build test`、`zig build test -Ddebug=false`、`python scripts/check-docs.py`（指摘0）、`zig fmt --check src/core/help_text.zig src/core/task_acceptance.zig src/host_clock.zig`はすべて終了コード0。`git diff --check`も成功した。macOS計画のSHA-256は上記固定値と一致し、text属性はunsetのままである。計画ファイルの変更、本測定、git commit・branch・push、tque変更は行っていない。

## Mac 実機の本測定の結果（2026-11-25）

ClaudeがMac実機で2026-11-25 05:26〜06:39 JSTに実行した本測定を、ロクがWindows上で保存済み生データから照合した。時間帯・AC電源・`caffeinate -i`はレモンからの共有情報である。今回、新たな測定は行っていない。

証拠は `.work/acceptance-macos/20261124T202712Z-124f2aa8/`（本測定）、`20261124T213907Z-52d883a0/`（startup・size）、同親ディレクトリの `control-a-provenance.txt`。両runの計画はmacOS v1、SHA-256は上記の `ffb8e936…a18b`、確認参照は `lemon-approved-2026-11-25-1383-reduced-counts`。現在の計画原本のSHAも一致した。上の準備段階の「本測定・Aのビルド未確認」は当時の記録であり、現在の結果は本節による。固定計画は変更していない。

実行環境はarm64、macOS 27.2.1、Zig 0.17.1、Python 3.15.2。HEADは `fe2f81206448c8fb62df5c7b86a3bffdc2129b1f` だが未コミットの変更を含むため、HEADだけで測定ソースを識別しない。各runのsource_manifest・fixture_manifest・実行体SHAを識別子とする。本runのprobe実行体SHA-256は `4ec9a048023862f3847a06ade043c04ccab2f90d977f97c11467fe0e911f9fe9`。ReleaseFast/debug=false/strip=true/task-trace=false/task-acceptance=true、response・startup・sizeはtask-acceptance=falseの別実行体である。親はmach_absolute_time、子はCLOCK_MONOTONIC（分解能1µs）。TTYはstdin/stdout/stderrともfalseであり、実端末の確認とは分ける。

保存済みJSONLの全303指標（n、偶数中央平均の中央値、nearest-rank p95、最大、目安超過数、80%該当）を再集計しresults.jsonと一致した。各試行とメモリ基準を含む2,988組のJSON/raw.logを読み、probeのACCEPTANCE行の一致、子の終了コード0、timeoutなし、OS採取エラーなしを確認した。responseは親側の記録でerror=null、raw.logのq後のINPUT-APPLIED=113を確認した。startup.jsonlのwarmup込み210行からA/B各100件も再集計し一致した。照合スクリプトは `.work/report-macos-1383.py`。これらは欠測を埋める検査ではない。runnerのacceptance_verdictもnot-evaluatedであり、**1383全体は未確認**とする。

### ソースの違いとOS間比較

[1382報告書12節](TASK_CONTROL_IMPL_1382.md#12-測定後の改善)の改善後ソースがMac本測定に入っている。題材のATICKはTASK-WAIT-MANYの管理巡を進め、APACEは供給の絶対期限を保ちつつrelease後と待機中にも管理する。T1はSCAN/SKIPで一致区間を数え、複数byte語はSCAN/COMPAREで候補を絞る改善後実装である。総件数・先頭1,000件・重複一致の仕様と64KiB/native上限は維持している。acceptance-fixtures.pyは本runのmanifestとバイト一致、task-search-worker.fsはWindowsのCRLFをLFへ正規化すると本runのSHAと一致した。

Windows・Linuxの1382本測定はこれらの改善前ソースである。MacのT1や公開→回収の数値が小さいことをOSだけの差、同一ソースでの改善率、Windows/Linuxの未達解消の証拠とはしない。ソース、CPU/architecture、OS、時計、メモリ定義、題材の管理巡が異なる。旧runと改善後run、各OSの標本は合算せず、1382で記録済みの超過は残す。

### 指標の全表とD07の照合

以下は各case/位相/metricを省略せず示す。`_ns`指標の表示単位は**ms**（元のns÷1,000,000）、`snapshot_image_bytes`はbytes、`queue_waiting`は件。目安は[D07利用条件](TASK_CONTROL_USAGE_CONDITIONS.md)3〜7節と固定計画による。中央値0や差分0は1µsの同一刻み内の観測であり、費用ゼロの保証ではない。nは要求回数ではなく当該指標の有効標本数で、管理巡は1プロセスから複数採る。

表の「合格（標本）」は観測最大が目安内という限定判定。「未確認・追加」は80%超で規定追加が残るもの。「未確認・欠測」は取消し対象位相の欠測が残るもの。**数値の目安超過（未達）は今回の全有効標本で0件**だが、欠測と未実施項目の合格を意味しない。容量の80%規則も時間と同様に適用する。

#### 対話の最大負荷（各10分×1回）

| case | 位相 | 指標 | n | 中央値 | p95 | 最大 | 目安 | 超過数 | 80%超 | 判定 |
|---|---|---|---|---|---|---|---|---|---|---|
| G1-open | — | management_turn_ns | 396918 | 0 | 0.001 | 0.04 | 1 | 0 | — | 合格（標本） |
| G1-open | — | snapshot_image_bytes | 1 | 2,003,740 | 2,003,740 | 2,003,740 | 4,194,304 | 0 | — | 合格（標本） |
| G1-open | — | snapshot_main_ns | 1 | 7.005 | 7.005 | 7.005 | 50 | 0 | — | 合格（標本） |
| G1-open | — | queue_waiting | 3421 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| G1-open | — | publish_reclaim_ns | 3421 | 1.093 | 1.75 | 44.162 | 100 | 0 | — | 合格（標本） |
| G1-open | — | G1_submit_publish_ns | 3421 | 73.579 | 76.187 | 81.278 | 100 | 0 | 該当 | 未確認・追加 |
| G1-wall | — | management_turn_ns | 396907 | 0 | 0.001 | 0.031 | 1 | 0 | — | 合格（標本） |
| G1-wall | — | snapshot_image_bytes | 1 | 2,004,044 | 2,004,044 | 2,004,044 | 4,194,304 | 0 | — | 合格（標本） |
| G1-wall | — | snapshot_main_ns | 1 | 6.97 | 6.97 | 6.97 | 50 | 0 | — | 合格（標本） |
| G1-wall | — | queue_waiting | 4026 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| G1-wall | — | publish_reclaim_ns | 4026 | 1.205 | 1.736 | 2.058 | 100 | 0 | — | 合格（標本） |
| G1-wall | — | G1_submit_publish_ns | 4026 | 47.067 | 48.748 | 66.008 | 100 | 0 | — | 合格（標本） |
| G1-snake | — | management_turn_ns | 396722 | 0 | 0.001 | 0.033 | 1 | 0 | — | 合格（標本） |
| G1-snake | — | snapshot_image_bytes | 1 | 2,004,556 | 2,004,556 | 2,004,556 | 4,194,304 | 0 | — | 合格（標本） |
| G1-snake | — | snapshot_main_ns | 1 | 6.982 | 6.982 | 6.982 | 50 | 0 | — | 合格（標本） |
| G1-snake | — | queue_waiting | 3863 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| G1-snake | — | publish_reclaim_ns | 3863 | 1.135 | 1.738 | 1.959 | 100 | 0 | — | 合格（標本） |
| G1-snake | — | G1_submit_publish_ns | 3863 | 53.449 | 54.883 | 58.331 | 100 | 0 | — | 合格（標本） |
| G2 | — | management_turn_ns | 445102 | 0 | 0.001 | 0.053 | 1 | 0 | — | 合格（標本） |
| G2 | — | snapshot_image_bytes | 1 | 690,665 | 690,665 | 690,665 | 4,194,304 | 0 | — | 合格（標本） |
| G2 | — | snapshot_main_ns | 1 | 2.42 | 2.42 | 2.42 | 50 | 0 | — | 合格（標本） |
| G2 | — | queue_waiting | 521 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| G2 | — | publish_reclaim_ns | 521 | 1.525 | 2.154 | 2.755 | 100 | 0 | — | 合格（標本） |
| G2 | — | G2_submit_publish_ns | 521 | 152.659 | 155.323 | 158.825 | 500 | 0 | — | 合格（標本） |
| T1 | — | management_turn_ns | 381567 | 0.001 | 0.001 | 0.799 | 1 | 0 | — | 合格（標本） |
| T1 | — | snapshot_image_bytes | 1 | 1,682,558 | 1,682,558 | 1,682,558 | 4,194,304 | 0 | — | 合格（標本） |
| T1 | — | snapshot_main_ns | 1 | 5.828 | 5.828 | 5.828 | 50 | 0 | — | 合格（標本） |
| T1 | — | queue_waiting | 4565 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| T1 | — | publish_reclaim_ns | 4565 | 2.542 | 3.444 | 4.005 | 100 | 0 | — | 合格（標本） |
| T1 | — | T1_submit_publish_ns | 4565 | 29.875 | 31.775 | 33.426 | 200 | 0 | — | 合格（標本） |
| I1 | — | management_turn_ns | 569239 | 0 | 0.007 | 0.064 | 1 | 0 | — | 合格（標本） |
| I1 | — | snapshot_image_bytes | 1 | 690,281 | 690,281 | 690,281 | 4,194,304 | 0 | — | 合格（標本） |
| I1 | — | snapshot_main_ns | 1 | 2.444 | 2.444 | 2.444 | 50 | 0 | — | 合格（標本） |
| I1 | — | queue_waiting | 52706 | 2 | 4 | 4 | 4 | 0 | 該当 | 未確認・追加 |
| I1 | — | publish_reclaim_ns | 52706 | 34.623 | 47.744 | 49.482 | 100 | 0 | — | 合格（標本） |
| I1 | — | I1_submit_publish_ns | 52705 | 22.306 | 35.575 | 40.37 | 250 | 0 | — | 合格（標本） |

#### 入力→状態（10分×1回、pipe注入→marker親受信）

| case | 位相 | 指標 | n | 中央値 | p95 | 最大 | 目安 | 超過数 | 80%超 | 判定 |
|---|---|---|---|---|---|---|---|---|---|---|
| response | — | input_state_ns | 5631 | 0.026584 | 0.039291 | 0.464708 | 16.67 | 0 | — | 合格（標本） |

#### Snapshot（独立100プロセス×3世代）

| case | 位相 | 指標 | n | 中央値 | p95 | 最大 | 目安 | 超過数 | 80%超 | 判定 |
|---|---|---|---|---|---|---|---|---|---|---|
| snapshot | — | management_turn_ns | 600 | 0 | 0.001 | 0.001 | 1 | 0 | — | 合格（標本） |
| snapshot | — | snapshot_image_bytes | 300 | 3,620,337 | 3,620,338 | 3,620,338 | 4,194,304 | 0 | 該当 | 未確認・追加 |
| snapshot | — | snapshot_main_ns | 300 | 12.625 | 12.893 | 13.111 | 50 | 0 | — | 合格（標本） |

#### 取消し・生成/実行・native・待ち

| case | 位相 | 指標 | n | 中央値 | p95 | 最大 | 目安 | 超過数 | 80%超 | 判定 |
|---|---|---|---|---|---|---|---|---|---|---|
| cancel | vm_start | management_turn_ns | 750 | 0 | 0.003 | 0.011 | 1 | 0 | — | 合格（標本） |
| cancel | vm_start | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | vm_start | snapshot_main_ns | 100 | 2.2065 | 2.786 | 6.869 | 50 | 0 | — | 合格（標本） |
| cancel | vm_start | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | vm_start | publish_reclaim_ns | 100 | 0.02 | 0.031 | 0.09 | 100 | 0 | — | 合格（標本） |
| cancel | snapshot_retained | management_turn_ns | 756 | 0 | 0.003 | 0.007 | 1 | 0 | — | 合格（標本） |
| cancel | snapshot_retained | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | snapshot_retained | snapshot_main_ns | 100 | 2.21 | 2.252 | 2.265 | 50 | 0 | — | 合格（標本） |
| cancel | snapshot_retained | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | snapshot_retained | publish_reclaim_ns | 100 | 0.02 | 0.031 | 0.034 | 100 | 0 | — | 合格（標本） |
| cancel | snapshot_retained | request_stop_ns | 21 | 0.001 | 0.002 | 0.002 | 10 | 0 | — | 未確認・欠測 |
| cancel | snapshot_retained | request_reclaim_ns | 21 | 0.021 | 0.023 | 0.024 | 100 | 0 | — | 未確認・欠測 |
| cancel | state_reserved | management_turn_ns | 780 | 0 | 0.003 | 0.006 | 1 | 0 | — | 合格（標本） |
| cancel | state_reserved | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | state_reserved | snapshot_main_ns | 100 | 2.218 | 2.262 | 2.343 | 50 | 0 | — | 合格（標本） |
| cancel | state_reserved | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | state_reserved | publish_reclaim_ns | 100 | 0.02 | 0.03 | 0.034 | 100 | 0 | — | 合格（標本） |
| cancel | state_allocated | management_turn_ns | 774 | 0 | 0.003 | 0.007 | 1 | 0 | — | 合格（標本） |
| cancel | state_allocated | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | state_allocated | snapshot_main_ns | 100 | 2.197 | 2.252 | 2.261 | 50 | 0 | — | 合格（標本） |
| cancel | state_allocated | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | state_allocated | publish_reclaim_ns | 100 | 0.02 | 0.031 | 0.032 | 100 | 0 | — | 合格（標本） |
| cancel | state_allocated | request_stop_ns | 15 | 0 | 0.001 | 0.001 | 10 | 0 | — | 未確認・欠測 |
| cancel | state_allocated | request_reclaim_ns | 15 | 0.021 | 0.026 | 0.026 | 100 | 0 | — | 未確認・欠測 |
| cancel | memory_allocated | management_turn_ns | 796 | 0 | 0.003 | 0.006 | 1 | 0 | — | 合格（標本） |
| cancel | memory_allocated | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | memory_allocated | snapshot_main_ns | 100 | 2.2135 | 2.256 | 2.27 | 50 | 0 | — | 合格（標本） |
| cancel | memory_allocated | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | memory_allocated | publish_reclaim_ns | 100 | 0.019 | 0.03 | 0.033 | 100 | 0 | — | 合格（標本） |
| cancel | memory_allocated | request_stop_ns | 4 | 0.001 | 0.001 | 0.001 | 10 | 0 | — | 未確認・欠測 |
| cancel | memory_allocated | request_reclaim_ns | 4 | 0.021 | 0.021 | 0.021 | 100 | 0 | — | 未確認・欠測 |
| cancel | data_allocated | management_turn_ns | 802 | 0 | 0.003 | 0.004 | 1 | 0 | — | 合格（標本） |
| cancel | data_allocated | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | data_allocated | snapshot_main_ns | 100 | 2.226 | 2.247 | 2.266 | 50 | 0 | — | 合格（標本） |
| cancel | data_allocated | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | data_allocated | publish_reclaim_ns | 100 | 0.019 | 0.031 | 0.032 | 100 | 0 | — | 合格（標本） |
| cancel | data_allocated | request_stop_ns | 3 | 0 | 0.001 | 0.001 | 10 | 0 | — | 未確認・欠測 |
| cancel | data_allocated | request_reclaim_ns | 3 | 0.022 | 0.023 | 0.023 | 100 | 0 | — | 未確認・欠測 |
| cancel | return_allocated | management_turn_ns | 802 | 0 | 0.003 | 0.007 | 1 | 0 | — | 合格（標本） |
| cancel | return_allocated | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | return_allocated | snapshot_main_ns | 100 | 2.2255 | 2.259 | 2.362 | 50 | 0 | — | 合格（標本） |
| cancel | return_allocated | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | return_allocated | publish_reclaim_ns | 100 | 0.019 | 0.031 | 0.032 | 100 | 0 | — | 合格（標本） |
| cancel | return_allocated | request_stop_ns | 1 | 0 | 0 | 0 | 10 | 0 | — | 未確認・欠測 |
| cancel | return_allocated | request_reclaim_ns | 1 | 0.022 | 0.022 | 0.022 | 100 | 0 | — | 未確認・欠測 |
| cancel | float_allocated | management_turn_ns | 783 | 0 | 0.003 | 0.005 | 1 | 0 | — | 合格（標本） |
| cancel | float_allocated | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | float_allocated | snapshot_main_ns | 100 | 2.2335 | 2.314 | 2.535 | 50 | 0 | — | 合格（標本） |
| cancel | float_allocated | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | float_allocated | publish_reclaim_ns | 100 | 0.02 | 0.032 | 0.035 | 100 | 0 | — | 合格（標本） |
| cancel | float_allocated | request_stop_ns | 4 | 0.0005 | 0.001 | 0.001 | 10 | 0 | — | 未確認・欠測 |
| cancel | float_allocated | request_reclaim_ns | 4 | 0.024 | 0.031 | 0.031 | 100 | 0 | — | 未確認・欠測 |
| cancel | loops_allocated | management_turn_ns | 799 | 0 | 0.003 | 0.005 | 1 | 0 | — | 合格（標本） |
| cancel | loops_allocated | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | loops_allocated | snapshot_main_ns | 100 | 2.235 | 2.276 | 2.3 | 50 | 0 | — | 合格（標本） |
| cancel | loops_allocated | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | loops_allocated | publish_reclaim_ns | 100 | 0.019 | 0.032 | 0.035 | 100 | 0 | — | 合格（標本） |
| cancel | frames_allocated | management_turn_ns | 793 | 0 | 0.003 | 0.005 | 1 | 0 | — | 合格（標本） |
| cancel | frames_allocated | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | frames_allocated | snapshot_main_ns | 100 | 2.23 | 2.253 | 2.534 | 50 | 0 | — | 合格（標本） |
| cancel | frames_allocated | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | frames_allocated | publish_reclaim_ns | 100 | 0.019 | 0.031 | 0.032 | 100 | 0 | — | 合格（標本） |
| cancel | catches_allocated | management_turn_ns | 797 | 0 | 0.003 | 0.004 | 1 | 0 | — | 合格（標本） |
| cancel | catches_allocated | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | catches_allocated | snapshot_main_ns | 100 | 2.2295 | 2.253 | 2.346 | 50 | 0 | — | 合格（標本） |
| cancel | catches_allocated | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | catches_allocated | request_stop_ns | 88 | 0.001 | 0.003 | 0.005 | 10 | 0 | — | 未確認・欠測 |
| cancel | catches_allocated | request_reclaim_ns | 88 | 0.021 | 0.034 | 0.037 | 100 | 0 | — | 未確認・欠測 |
| cancel | catches_allocated | publish_reclaim_ns | 100 | 0.019 | 0.031 | 0.034 | 100 | 0 | — | 合格（標本） |
| cancel | storage_zeroed | management_turn_ns | 105084 | 0 | 0.001 | 0.01 | 1 | 0 | — | 合格（標本） |
| cancel | storage_zeroed | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | storage_zeroed | snapshot_main_ns | 100 | 2.235 | 2.256 | 2.268 | 50 | 0 | — | 合格（標本） |
| cancel | storage_zeroed | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | storage_zeroed | publish_reclaim_ns | 100 | 0.273 | 0.301 | 0.344 | 100 | 0 | — | 合格（標本） |
| cancel | storage_allocated | management_turn_ns | 104546 | 0 | 0.001 | 0.001 | 1 | 0 | — | 合格（標本） |
| cancel | storage_allocated | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | storage_allocated | snapshot_main_ns | 100 | 2.2385 | 2.261 | 2.341 | 50 | 0 | — | 合格（標本） |
| cancel | storage_allocated | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | storage_allocated | request_stop_ns | 99 | 0.044 | 0.05 | 0.052 | 10 | 0 | — | 未確認・欠測 |
| cancel | storage_allocated | request_reclaim_ns | 99 | 0.319 | 0.352 | 0.399 | 100 | 0 | — | 未確認・欠測 |
| cancel | storage_allocated | publish_reclaim_ns | 100 | 0.2755 | 0.303 | 0.355 | 100 | 0 | — | 合格（標本） |
| cancel | initialized | management_turn_ns | 135400 | 0 | 0.001 | 0.008 | 1 | 0 | — | 合格（標本） |
| cancel | initialized | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | initialized | snapshot_main_ns | 100 | 2.2395 | 2.261 | 2.266 | 50 | 0 | — | 合格（標本） |
| cancel | initialized | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | initialized | publish_reclaim_ns | 100 | 0.2825 | 0.31 | 1.539 | 100 | 0 | — | 合格（標本） |
| cancel | initialized | request_stop_ns | 16 | 0.002 | 1.104 | 1.104 | 10 | 0 | — | 未確認・欠測 |
| cancel | initialized | request_reclaim_ns | 16 | 0.288 | 1.395 | 1.395 | 100 | 0 | — | 未確認・欠測 |
| cancel | plan_allocated | management_turn_ns | 140372 | 0 | 0.001 | 0.006 | 1 | 0 | — | 合格（標本） |
| cancel | plan_allocated | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | plan_allocated | snapshot_main_ns | 100 | 2.242 | 2.261 | 2.33 | 50 | 0 | — | 合格（標本） |
| cancel | plan_allocated | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | plan_allocated | request_stop_ns | 100 | 1.097 | 1.115 | 1.216 | 10 | 0 | — | 合格（標本） |
| cancel | plan_allocated | request_reclaim_ns | 100 | 1.381 | 1.414 | 1.547 | 100 | 0 | — | 合格（標本） |
| cancel | plan_allocated | publish_reclaim_ns | 100 | 0.282 | 0.309 | 0.332 | 100 | 0 | — | 合格（標本） |
| cancel | restore_validated | management_turn_ns | 141024 | 0 | 0.001 | 0.007 | 1 | 0 | — | 合格（標本） |
| cancel | restore_validated | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | restore_validated | snapshot_main_ns | 100 | 2.241 | 2.256 | 2.271 | 50 | 0 | — | 合格（標本） |
| cancel | restore_validated | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | restore_validated | publish_reclaim_ns | 100 | 0.286 | 0.305 | 0.357 | 100 | 0 | — | 合格（標本） |
| cancel | restore_validated | request_stop_ns | 99 | 0.02 | 0.024 | 0.026 | 10 | 0 | — | 未確認・欠測 |
| cancel | restore_validated | request_reclaim_ns | 99 | 0.306 | 0.333 | 0.38 | 100 | 0 | — | 未確認・欠測 |
| cancel | restore_applied | management_turn_ns | 141496 | 0 | 0.001 | 0.011 | 1 | 0 | — | 合格（標本） |
| cancel | restore_applied | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | restore_applied | snapshot_main_ns | 100 | 2.2405 | 2.259 | 2.323 | 50 | 0 | — | 合格（標本） |
| cancel | restore_applied | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | restore_applied | publish_reclaim_ns | 100 | 0.284 | 0.317 | 0.356 | 100 | 0 | — | 合格（標本） |
| cancel | restored | management_turn_ns | 143730 | 0 | 0.001 | 0.006 | 1 | 0 | — | 合格（標本） |
| cancel | restored | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | restored | snapshot_main_ns | 100 | 2.239 | 2.261 | 2.294 | 50 | 0 | — | 合格（標本） |
| cancel | restored | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | restored | request_stop_ns | 61 | 0.001 | 0.004 | 0.005 | 10 | 0 | — | 未確認・欠測 |
| cancel | restored | request_reclaim_ns | 61 | 0.291 | 0.307 | 0.322 | 100 | 0 | — | 未確認・欠測 |
| cancel | restored | publish_reclaim_ns | 100 | 0.29 | 0.321 | 0.357 | 100 | 0 | — | 合格（標本） |
| cancel | plan_released | management_turn_ns | 142775 | 0 | 0.001 | 0.008 | 1 | 0 | — | 合格（標本） |
| cancel | plan_released | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | plan_released | snapshot_main_ns | 100 | 2.241 | 2.261 | 2.267 | 50 | 0 | — | 合格（標本） |
| cancel | plan_released | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | plan_released | publish_reclaim_ns | 100 | 0.286 | 0.318 | 0.365 | 100 | 0 | — | 合格（標本） |
| cancel | plan_released | request_stop_ns | 3 | 0.001 | 0.004 | 0.004 | 10 | 0 | — | 未確認・欠測 |
| cancel | plan_released | request_reclaim_ns | 3 | 0.283 | 0.296 | 0.296 | 100 | 0 | — | 未確認・欠測 |
| cancel | fresh_checked | management_turn_ns | 142437 | 0 | 0.001 | 0.008 | 1 | 0 | — | 合格（標本） |
| cancel | fresh_checked | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | fresh_checked | snapshot_main_ns | 100 | 2.24 | 2.262 | 2.337 | 50 | 0 | — | 合格（標本） |
| cancel | fresh_checked | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | fresh_checked | publish_reclaim_ns | 100 | 0.2865 | 0.313 | 0.385 | 100 | 0 | — | 合格（標本） |
| cancel | fresh_checked | request_stop_ns | 2 | 0.0025 | 0.003 | 0.003 | 10 | 0 | — | 未確認・欠測 |
| cancel | fresh_checked | request_reclaim_ns | 2 | 0.2985 | 0.3 | 0.3 | 100 | 0 | — | 未確認・欠測 |
| cancel | resolved | management_turn_ns | 143164 | 0 | 0.001 | 0.01 | 1 | 0 | — | 合格（標本） |
| cancel | resolved | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | resolved | snapshot_main_ns | 100 | 2.243 | 2.261 | 2.272 | 50 | 0 | — | 合格（標本） |
| cancel | resolved | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | resolved | request_stop_ns | 35 | 0.002 | 0.005 | 0.005 | 10 | 0 | — | 未確認・欠測 |
| cancel | resolved | request_reclaim_ns | 35 | 0.289 | 0.304 | 0.317 | 100 | 0 | — | 未確認・欠測 |
| cancel | resolved | publish_reclaim_ns | 100 | 0.2865 | 0.315 | 0.346 | 100 | 0 | — | 合格（標本） |
| cancel | grants_ready | management_turn_ns | 144006 | 0 | 0.001 | 0.012 | 1 | 0 | — | 合格（標本） |
| cancel | grants_ready | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | grants_ready | snapshot_main_ns | 100 | 2.243 | 2.266 | 2.363 | 50 | 0 | — | 合格（標本） |
| cancel | grants_ready | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | grants_ready | request_stop_ns | 94 | 0.003 | 0.007 | 0.008 | 10 | 0 | — | 未確認・欠測 |
| cancel | grants_ready | request_reclaim_ns | 94 | 0.291 | 0.318 | 0.34 | 100 | 0 | — | 未確認・欠測 |
| cancel | grants_ready | publish_reclaim_ns | 100 | 0.288 | 0.322 | 0.359 | 100 | 0 | — | 合格（標本） |
| cancel | permissions_checked | management_turn_ns | 143834 | 0 | 0.001 | 0.007 | 1 | 0 | — | 合格（標本） |
| cancel | permissions_checked | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | permissions_checked | snapshot_main_ns | 100 | 2.244 | 2.263 | 2.326 | 50 | 0 | — | 合格（標本） |
| cancel | permissions_checked | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | permissions_checked | request_stop_ns | 4 | 0.0025 | 0.003 | 0.003 | 10 | 0 | — | 未確認・欠測 |
| cancel | permissions_checked | request_reclaim_ns | 4 | 0.288 | 0.289 | 0.289 | 100 | 0 | — | 未確認・欠測 |
| cancel | permissions_checked | publish_reclaim_ns | 100 | 0.2865 | 0.316 | 0.362 | 100 | 0 | — | 合格（標本） |
| cancel | input_ready | management_turn_ns | 142642 | 0 | 0.001 | 0.01 | 1 | 0 | — | 合格（標本） |
| cancel | input_ready | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | input_ready | snapshot_main_ns | 100 | 2.243 | 2.263 | 2.279 | 50 | 0 | — | 合格（標本） |
| cancel | input_ready | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | input_ready | publish_reclaim_ns | 100 | 0.273 | 0.303 | 0.35 | 100 | 0 | — | 合格（標本） |
| cancel | input_ready | request_stop_ns | 32 | 0.002 | 0.004 | 0.004 | 10 | 0 | — | 未確認・欠測 |
| cancel | input_ready | request_reclaim_ns | 32 | 0.276 | 0.308 | 0.337 | 100 | 0 | — | 未確認・欠測 |
| cancel | executing | management_turn_ns | 140003 | 0 | 0.001 | 0.01 | 1 | 0 | — | 合格（標本） |
| cancel | executing | snapshot_image_bytes | 100 | 620,399 | 620,399 | 620,399 | 4,194,304 | 0 | — | 合格（標本） |
| cancel | executing | snapshot_main_ns | 100 | 2.243 | 2.265 | 2.324 | 50 | 0 | — | 合格（標本） |
| cancel | executing | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| cancel | executing | request_stop_ns | 100 | 0.002 | 0.003 | 0.005 | 10 | 0 | — | 合格（標本） |
| cancel | executing | request_reclaim_ns | 100 | 0.258 | 0.288 | 0.339 | 100 | 0 | — | 合格（標本） |
| cancel | executing | publish_reclaim_ns | 100 | 0.256 | 0.286 | 0.336 | 100 | 0 | — | 合格（標本） |
| queued | — | management_turn_ns | 1300 | 0 | 0.005 | 0.011 | 1 | 0 | — | 合格（標本） |
| queued | — | snapshot_image_bytes | 100 | 620,574 | 620,574 | 620,574 | 4,194,304 | 0 | — | 合格（標本） |
| queued | — | snapshot_main_ns | 100 | 2.247 | 2.266 | 2.278 | 50 | 0 | — | 合格（標本） |
| queued | — | queue_waiting | 200 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| queued | — | request_reclaim_ns | 200 | 0.07 | 0.133 | 0.146 | 100 | 0 | — | 合格（標本） |
| queued | — | publish_reclaim_ns | 200 | 0.065 | 0.125 | 0.138 | 100 | 0 | — | 合格（標本） |
| queued | — | queued_cancel_publish_ns | 100 | 0.005 | 0.005 | 0.012 | 10 | 0 | — | 合格（標本） |
| queued | — | request_stop_ns | 100 | 0.007 | 0.011 | 0.013 | 10 | 0 | — | 合格（標本） |
| native-fill | native_before | management_turn_ns | 30 | 0 | 0.005 | 0.01 | 1 | 0 | — | 合格（標本） |
| native-fill | native_before | snapshot_image_bytes | 3 | 685,939 | 685,939 | 685,939 | 4,194,304 | 0 | — | 合格（標本） |
| native-fill | native_before | snapshot_main_ns | 3 | 2.481 | 2.483 | 2.483 | 50 | 0 | — | 合格（標本） |
| native-fill | native_before | queue_waiting | 3 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| native-fill | native_before | publish_reclaim_ns | 3 | 1.535 | 1.588 | 1.588 | 100 | 0 | — | 合格（標本） |
| native-fill | native_running | management_turn_ns | 30 | 0 | 0.009 | 0.011 | 1 | 0 | — | 合格（標本） |
| native-fill | native_running | snapshot_image_bytes | 3 | 685,939 | 685,939 | 685,939 | 4,194,304 | 0 | — | 合格（標本） |
| native-fill | native_running | snapshot_main_ns | 3 | 2.459 | 2.465 | 2.465 | 50 | 0 | — | 合格（標本） |
| native-fill | native_running | queue_waiting | 3 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| native-fill | native_running | publish_reclaim_ns | 3 | 1.579 | 1.585 | 1.585 | 100 | 0 | — | 合格（標本） |
| native-fill | native_after | management_turn_ns | 30 | 0 | 0.012 | 0.013 | 1 | 0 | — | 合格（標本） |
| native-fill | native_after | snapshot_image_bytes | 3 | 685,939 | 685,939 | 685,939 | 4,194,304 | 0 | — | 合格（標本） |
| native-fill | native_after | snapshot_main_ns | 3 | 2.477 | 2.478 | 2.478 | 50 | 0 | — | 合格（標本） |
| native-fill | native_after | queue_waiting | 3 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| native-fill | native_after | publish_reclaim_ns | 3 | 1.588 | 1.591 | 1.591 | 100 | 0 | — | 合格（標本） |
| native-move | native_before | management_turn_ns | 30 | 0 | 0.013 | 0.013 | 1 | 0 | — | 合格（標本） |
| native-move | native_before | snapshot_image_bytes | 3 | 685,971 | 685,971 | 685,971 | 4,194,304 | 0 | — | 合格（標本） |
| native-move | native_before | snapshot_main_ns | 3 | 2.462 | 2.473 | 2.473 | 50 | 0 | — | 合格（標本） |
| native-move | native_before | queue_waiting | 3 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| native-move | native_before | publish_reclaim_ns | 3 | 1.583 | 1.588 | 1.588 | 100 | 0 | — | 合格（標本） |
| native-move | native_running | management_turn_ns | 1000 | 0 | 0.011 | 0.021 | 1 | 0 | — | 合格（標本） |
| native-move | native_running | snapshot_image_bytes | 100 | 685,971 | 685,971 | 685,971 | 4,194,304 | 0 | — | 合格（標本） |
| native-move | native_running | snapshot_main_ns | 100 | 2.4795 | 2.501 | 2.548 | 50 | 0 | — | 合格（標本） |
| native-move | native_running | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| native-move | native_running | request_stop_ns | 92 | 0.006 | 0.009 | 0.01 | 10 | 0 | — | 未確認・欠測 |
| native-move | native_running | request_reclaim_ns | 92 | 1.585 | 1.594 | 1.616 | 100 | 0 | — | 未確認・欠測 |
| native-move | native_running | publish_reclaim_ns | 100 | 1.579 | 1.589 | 1.605 | 100 | 0 | — | 合格（標本） |
| native-move | native_after | management_turn_ns | 30 | 0 | 0.01 | 0.01 | 1 | 0 | — | 合格（標本） |
| native-move | native_after | snapshot_image_bytes | 3 | 685,971 | 685,971 | 685,971 | 4,194,304 | 0 | — | 合格（標本） |
| native-move | native_after | snapshot_main_ns | 3 | 2.412 | 2.493 | 2.493 | 50 | 0 | — | 合格（標本） |
| native-move | native_after | queue_waiting | 3 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| native-move | native_after | publish_reclaim_ns | 3 | 1.579 | 1.579 | 1.579 | 100 | 0 | — | 合格（標本） |
| native-compare | native_before | management_turn_ns | 30 | 0 | 0.011 | 0.012 | 1 | 0 | — | 合格（標本） |
| native-compare | native_before | snapshot_image_bytes | 3 | 686,003 | 686,003 | 686,003 | 4,194,304 | 0 | — | 合格（標本） |
| native-compare | native_before | snapshot_main_ns | 3 | 2.461 | 2.473 | 2.473 | 50 | 0 | — | 合格（標本） |
| native-compare | native_before | queue_waiting | 3 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| native-compare | native_before | publish_reclaim_ns | 3 | 1.578 | 1.584 | 1.584 | 100 | 0 | — | 合格（標本） |
| native-compare | native_running | management_turn_ns | 1000 | 0 | 0.011 | 0.022 | 1 | 0 | — | 合格（標本） |
| native-compare | native_running | snapshot_image_bytes | 100 | 686,003 | 686,003 | 686,003 | 4,194,304 | 0 | — | 合格（標本） |
| native-compare | native_running | snapshot_main_ns | 100 | 2.477 | 2.501 | 2.553 | 50 | 0 | — | 合格（標本） |
| native-compare | native_running | queue_waiting | 100 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| native-compare | native_running | publish_reclaim_ns | 100 | 1.579 | 1.588 | 1.6 | 100 | 0 | — | 合格（標本） |
| native-compare | native_running | request_stop_ns | 92 | 0.006 | 0.011 | 0.013 | 10 | 0 | — | 未確認・欠測 |
| native-compare | native_running | request_reclaim_ns | 92 | 1.585 | 1.594 | 1.602 | 100 | 0 | — | 未確認・欠測 |
| native-compare | native_after | management_turn_ns | 30 | 0 | 0.011 | 0.013 | 1 | 0 | — | 合格（標本） |
| native-compare | native_after | snapshot_image_bytes | 3 | 686,003 | 686,003 | 686,003 | 4,194,304 | 0 | — | 合格（標本） |
| native-compare | native_after | snapshot_main_ns | 3 | 2.466 | 2.498 | 2.498 | 50 | 0 | — | 合格（標本） |
| native-compare | native_after | queue_waiting | 3 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| native-compare | native_after | publish_reclaim_ns | 3 | 1.575 | 1.579 | 1.579 | 100 | 0 | — | 合格（標本） |
| native-search | native_before | management_turn_ns | 30 | 0 | 0.01 | 0.012 | 1 | 0 | — | 合格（標本） |
| native-search | native_before | snapshot_image_bytes | 3 | 686,019 | 686,019 | 686,019 | 4,194,304 | 0 | — | 合格（標本） |
| native-search | native_before | snapshot_main_ns | 3 | 2.473 | 2.481 | 2.481 | 50 | 0 | — | 合格（標本） |
| native-search | native_before | queue_waiting | 3 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| native-search | native_before | publish_reclaim_ns | 3 | 1.583 | 1.585 | 1.585 | 100 | 0 | — | 合格（標本） |
| native-search | native_running | management_turn_ns | 30 | 0 | 0.006 | 0.012 | 1 | 0 | — | 合格（標本） |
| native-search | native_running | snapshot_image_bytes | 3 | 686,019 | 686,019 | 686,019 | 4,194,304 | 0 | — | 合格（標本） |
| native-search | native_running | snapshot_main_ns | 3 | 2.475 | 2.484 | 2.484 | 50 | 0 | — | 合格（標本） |
| native-search | native_running | queue_waiting | 3 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| native-search | native_running | publish_reclaim_ns | 3 | 1.538 | 1.583 | 1.583 | 100 | 0 | — | 合格（標本） |
| native-search | native_after | management_turn_ns | 30 | 0 | 0.011 | 0.012 | 1 | 0 | — | 合格（標本） |
| native-search | native_after | snapshot_image_bytes | 3 | 686,019 | 686,019 | 686,019 | 4,194,304 | 0 | — | 合格（標本） |
| native-search | native_after | snapshot_main_ns | 3 | 2.479 | 2.482 | 2.482 | 50 | 0 | — | 合格（標本） |
| native-search | native_after | queue_waiting | 3 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| native-search | native_after | publish_reclaim_ns | 3 | 1.584 | 1.587 | 1.587 | 100 | 0 | — | 合格（標本） |
| native-roll | native_before | management_turn_ns | 30 | 0.001 | 0.012 | 0.012 | 1 | 0 | — | 合格（標本） |
| native-roll | native_before | snapshot_image_bytes | 3 | 686,195 | 686,195 | 686,195 | 4,194,304 | 0 | — | 合格（標本） |
| native-roll | native_before | snapshot_main_ns | 3 | 2.488 | 2.513 | 2.513 | 50 | 0 | — | 合格（標本） |
| native-roll | native_before | queue_waiting | 3 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| native-roll | native_before | publish_reclaim_ns | 3 | 1.59 | 1.596 | 1.596 | 100 | 0 | — | 合格（標本） |
| native-roll | native_running | management_turn_ns | 30 | 0 | 0.01 | 0.01 | 1 | 0 | — | 合格（標本） |
| native-roll | native_running | snapshot_image_bytes | 3 | 686,195 | 686,195 | 686,195 | 4,194,304 | 0 | — | 合格（標本） |
| native-roll | native_running | snapshot_main_ns | 3 | 2.484 | 2.5 | 2.5 | 50 | 0 | — | 合格（標本） |
| native-roll | native_running | queue_waiting | 3 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| native-roll | native_running | publish_reclaim_ns | 3 | 1.576 | 1.584 | 1.584 | 100 | 0 | — | 合格（標本） |
| native-roll | native_after | management_turn_ns | 30 | 0 | 0.012 | 0.013 | 1 | 0 | — | 合格（標本） |
| native-roll | native_after | snapshot_image_bytes | 3 | 686,195 | 686,195 | 686,195 | 4,194,304 | 0 | — | 合格（標本） |
| native-roll | native_after | snapshot_main_ns | 3 | 2.481 | 2.483 | 2.483 | 50 | 0 | — | 合格（標本） |
| native-roll | native_after | queue_waiting | 3 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| native-roll | native_after | publish_reclaim_ns | 3 | 1.584 | 1.585 | 1.585 | 100 | 0 | — | 合格（標本） |

#### メモリ専用runの容量指標（時間標本には含めない）

| case | 位相 | 指標 | n | 中央値 | p95 | 最大 | 目安 | 超過数 | 80%超 | 判定 |
|---|---|---|---|---|---|---|---|---|---|---|
| G1-open | — | snapshot_image_bytes | 3 | 2,003,596 | 2,003,596 | 2,003,596 | 4,194,304 | 0 | — | 合格（標本） |
| G1-open | — | queue_waiting | 3 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| G1-wall | — | snapshot_image_bytes | 3 | 2,003,900 | 2,003,900 | 2,003,900 | 4,194,304 | 0 | — | 合格（標本） |
| G1-wall | — | queue_waiting | 3 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| G1-snake | — | snapshot_image_bytes | 3 | 2,004,412 | 2,004,412 | 2,004,412 | 4,194,304 | 0 | — | 合格（標本） |
| G1-snake | — | queue_waiting | 3 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| G2 | — | snapshot_image_bytes | 3 | 690,521 | 690,521 | 690,521 | 4,194,304 | 0 | — | 合格（標本） |
| G2 | — | queue_waiting | 3 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| T1 | — | snapshot_image_bytes | 3 | 1,682,414 | 1,682,414 | 1,682,414 | 4,194,304 | 0 | — | 合格（標本） |
| T1 | — | queue_waiting | 3 | 1 | 1 | 1 | 4 | 0 | — | 合格（標本） |
| I1 | — | snapshot_image_bytes | 3 | 689,881 | 689,881 | 689,881 | 4,194,304 | 0 | — | 合格（標本） |
| I1 | — | queue_waiting | 18 | 2.5 | 4 | 4 | 4 | 0 | 該当 | 未確認・追加 |
| snapshot | — | snapshot_image_bytes | 9 | 3,620,424 | 3,620,425 | 3,620,425 | 4,194,304 | 0 | 該当 | 未確認・追加 |

#### メモリ：phys_footprintの負荷ピーク−基準（7題材×3回）

基準は同じmainデータと1世代Snapshot/初期化済serviceの最後のBASELINE-READY。負荷は10ms周期と保持停止点のピーク。下表の差はbytes、括弧はMiB。3回のp95はnearest-rankにより最大と同値。

| 題材 | n | 1回目 | 2回目 | 3回目 | 中央値 bytes | p95 bytes | 最大 bytes | 目安 | 超過数 | 80%超 | 限定判定 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| G1-open | 3 | 67,944,520 (64.797) | 67,944,520 (64.797) | 67,911,704 (64.766) | 67,944,520 | 67944520 | 67944520 | 134,217,728 (128MiB) | 0 | — | 合格（footprint観測差） |
| G1-wall | 3 | 67,928,112 (64.781) | 67,944,520 (64.797) | 67,928,112 (64.781) | 67,928,112 | 67944520 | 67944520 | 134,217,728 (128MiB) | 0 | — | 合格（footprint観測差） |
| G1-snake | 3 | 68,059,208 (64.906) | 68,042,800 (64.891) | 68,059,208 (64.906) | 68,059,208 | 68059208 | 68059208 | 134,217,728 (128MiB) | 0 | — | 合格（footprint観測差） |
| G2 | 3 | 67,928,136 (64.781) | 67,928,136 (64.781) | 67,928,136 (64.781) | 67,928,136 | 67928136 | 67928136 | 134,217,728 (128MiB) | 0 | — | 合格（footprint観測差） |
| T1 | 3 | 68,911,176 (65.719) | 68,911,176 (65.719) | 68,911,176 (65.719) | 68,911,176 | 68911176 | 68911176 | 134,217,728 (128MiB) | 0 | — | 合格（footprint観測差） |
| I1 | 3 | 68,403,296 (65.234) | 68,403,296 (65.234) | 68,403,296 (65.234) | 68,403,296 | 68403296 | 68403296 | 134,217,728 (128MiB) | 0 | — | 合格（footprint観測差） |
| snapshot | 3 | 7,372,824 (7.031) | 7,356,416 (7.016) | 7,372,824 (7.031) | 7,372,824 | 7372824 | 7372824 | 134,217,728 (128MiB) | 0 | — | 合格（footprint観測差） |

全21回でOS採取エラー・保持点欠落はない。footprint差は最大68,911,176 bytes（65.719MiB、128MiBの51.34%）で、この差による80%追加はない。※推測です：footprint差を追加負担の目安とするのは計画5節の選択である。私有予約/コミットの定義とは異なり、**予約・コミット128MiB全体は未確認**。10ms採取と保持点は短命の全確保ピークを証明せず、カテゴリ別予算・全ページ接触・allocator上限の機能確認も別途必要。memory/snapshotのtask row absent 3件は下記のとおり保持する。

#### startup：対照A/B（各5 warmup＋100回、AB/BA交互）

| 対象 | n | 中央値 ms | p95 ms | 最大 ms | 比較目安 | 超過数 |
|---|---|---|---|---|---|---|
| A | 100 | 1.987229 | 2.132375 | 2.183125 | B−Aの中央値≤10ms・p95≤20ms | —（分布差で判定） |
| B | 100 | 1.991542 | 2.129667 | 2.18575 | B−Aの中央値≤10ms・p95≤20ms | —（分布差で判定） |

| 比較 | 増分 ms | 増減率 | 目安 | 判定 |
|---|---|---|---|---|
| median | 0.004313 | +0.2170% | +10ms以内 | 合格（目安内・個別判断待ち） |
| p95 | -0.002708 | -0.1270% | +20ms以内 | 合格（目安内・個別判断待ち） |

AはW1導入前 `35523f676836134c4fbaed19e3d01d2a23ec2a92`。来歴にはZig 0.17.1、arm64、SDK、ReleaseFast/debug=false/strip=trueのコマンド、archive SHA、実行体SHAがあり、Aのビルドは成功した。来歴ファイルSHAはstartup run記録と一致する。A実行体SHAは `b4aaf68bbf3d3616c104179f29388cd9c5944a6b92918996e7318448cd68113e`、Bは `da8c8736921123b4c636f55bd5fa593458a9c0bc8206f6f639fe57f089612ed7`。起動時間はpipe/schedulerを含む親のready受信であり内部ready時刻そのものではない。絶対増分の目安であり、増減率を10%/20%のゲートにしない。

| size | n（各生成物） | A bytes | B bytes | 増分 bytes | 増減率 | 目安 | 超過数 | 判定 |
|---|---|---|---|---|---|---|---|---|
| 実行体全体 | 1 | 2,040,328 | 2,171,784 | +131,456 | +6.4429% | +262,144 bytes かつ+10%以内 | 0 | 合格（目安内・個別判断待ち） |
| __TEXT,__text | 1 | 1,002,396 | 1,091,032 | +88,636 | +8.8424% | +131,072 bytes かつ+10%以内 | 0 | 合格（目安内・個別判断待ち） |

thin Mach-O64 arm64の__TEXT,__textはlogical_bytes=file_bytesで、全体サイズと区別した。sizeは生成物各1件の静的値なので中央値/p95/最大の反復統計は適用しない。startupの増分と実行体全体の増分は各目安の80%以下。一方、__textの相対増加8.8424%は10%目安の88.424%であり、80%を超える（絶対増分88,636 bytesは128KiBの67.624%）。固定計画はsizeについて追加回数を定めていないため、他の群の回数を流用せず、追加の扱いをレモンの判断事項として残す。D07 7節は目安内でも自動承認せず、レモンが生成差分と個別に判断する。A/A′/Bの単一VM実行時間（中央値+1%/p95+2%）、逆アセンブル、配置影響は未確認で、AC-29全体の合格ではない。

### 欠測の内訳と判断が必要な点

1382と同じく、狙った位相以外の要求、同時刻の境界、250ms内の未観測、端点欠落を当該位相の成功標本へ補わない。位相不一致でも公開→回収など別の有効区間は表に残るが、取消し応答の合格へ転用しない。欠測件数は理由やmetricごとに重複するため、下表を単純合算して試行数にしない。

| 区分・理由 | 記録数 | 扱い |
|---|---|---|
| 生成取消しの位相不一致 | 1,719 / 2,500要求 | 有効781要求。停止/回収の2指標それぞれ欠測。位相ごとの内訳は次表 |
| nativeの位相不一致/同時刻・未観測 | 55 / 239実行要求 | MOVE/COMPARE実行区間が各8、13打切り位相が各3。有効184要求 |
| phase mismatch or equal timestamps | 3,548 metric行 | (1,719+55)×停止/回収2指標。phase_missing_count=1,774と重複 |
| phase passed before request or not observed within 250ms | 33試行 | native未観測。上の55件に含む |
| request phase differs from target | 7試行 | native要求位相の不一致。追加の独立試行数とはしない |
| native最初3回に有効要求なしで打切り | 13位相・未実行1,261要求 | 各位相97回を実行せず。取消し不能の証明でも合格でもない |
| task endpoint absent or zero | 100行 | queuedのstopped=0。未実行の待ちtaskを実行停止成功へ読み替えない |
| invalid or missing endpoints: requested=…, stopped=0 | 100行 | 同じqueuedの要求→停止。待ち取消し→公開100件は別途有効 |
| memory/snapshot task row absent | 3試行 | Snapshot保持試験はtaskを投入しない構造。footprint採取21回は存在するがrunner status=incompleteを消さない |
| snapshot群の端点欠落 | 0 | 100プロセス×3取得の容量・占有端点は存在 |
| OS採取エラー・保持点欠落・hang guard・event overflow | 0 | 欠測なしを全確保ピーク/全機能成功へ拡張しない |

| case | 対象位相 | 実行要求 | 有効 | 位相欠測 | 打切り未実行 | 位相の判定 |
|---|---|---|---|---|---|---|
| cancel | vm_start | 100 | 0 | 100 | 0 | 未確認 |
| cancel | snapshot_retained | 100 | 21 | 79 | 0 | 未確認 |
| cancel | state_reserved | 100 | 0 | 100 | 0 | 未確認 |
| cancel | state_allocated | 100 | 15 | 85 | 0 | 未確認 |
| cancel | memory_allocated | 100 | 4 | 96 | 0 | 未確認 |
| cancel | data_allocated | 100 | 3 | 97 | 0 | 未確認 |
| cancel | return_allocated | 100 | 1 | 99 | 0 | 未確認 |
| cancel | float_allocated | 100 | 4 | 96 | 0 | 未確認 |
| cancel | loops_allocated | 100 | 0 | 100 | 0 | 未確認 |
| cancel | frames_allocated | 100 | 0 | 100 | 0 | 未確認 |
| cancel | catches_allocated | 100 | 88 | 12 | 0 | 未確認 |
| cancel | storage_zeroed | 100 | 0 | 100 | 0 | 未確認 |
| cancel | storage_allocated | 100 | 99 | 1 | 0 | 未確認 |
| cancel | initialized | 100 | 16 | 84 | 0 | 未確認 |
| cancel | plan_allocated | 100 | 100 | 0 | 0 | 合格（位相標本） |
| cancel | restore_validated | 100 | 99 | 1 | 0 | 未確認 |
| cancel | restore_applied | 100 | 0 | 100 | 0 | 未確認 |
| cancel | restored | 100 | 61 | 39 | 0 | 未確認 |
| cancel | plan_released | 100 | 3 | 97 | 0 | 未確認 |
| cancel | fresh_checked | 100 | 2 | 98 | 0 | 未確認 |
| cancel | resolved | 100 | 35 | 65 | 0 | 未確認 |
| cancel | grants_ready | 100 | 94 | 6 | 0 | 未確認 |
| cancel | permissions_checked | 100 | 4 | 96 | 0 | 未確認 |
| cancel | input_ready | 100 | 32 | 68 | 0 | 未確認 |
| cancel | executing | 100 | 100 | 0 | 0 | 合格（位相標本） |
| native-fill | native_before | 3 | 0 | 3 | 97 | 未確認 |
| native-fill | native_running | 3 | 0 | 3 | 97 | 未確認 |
| native-fill | native_after | 3 | 0 | 3 | 97 | 未確認 |
| native-move | native_before | 3 | 0 | 3 | 97 | 未確認 |
| native-move | native_running | 100 | 92 | 8 | 0 | 未確認 |
| native-move | native_after | 3 | 0 | 3 | 97 | 未確認 |
| native-compare | native_before | 3 | 0 | 3 | 97 | 未確認 |
| native-compare | native_running | 100 | 92 | 8 | 0 | 未確認 |
| native-compare | native_after | 3 | 0 | 3 | 97 | 未確認 |
| native-search | native_before | 3 | 0 | 3 | 97 | 未確認 |
| native-search | native_running | 3 | 0 | 3 | 97 | 未確認 |
| native-search | native_after | 3 | 0 | 3 | 97 | 未確認 |
| native-roll | native_before | 3 | 0 | 3 | 97 | 未確認 |
| native-roll | native_running | 3 | 0 | 3 | 97 | 未確認 |
| native-roll | native_after | 3 | 0 | 3 | 97 | 未確認 |

FILL・SEARCH・ROLLは直前/実行区間/直後の全3位相、MOVE・COMPAREは直前/直後が打切り。MOVE/COMPAREの実行区間も各92有効/8欠測であり、全native位相合格にはならない。生成取消しは25位相を対象とするが、100件すべて有効なのはplan_allocatedとexecutingだけである。境界の取り逃しを、後からactualの位相へ付け替えて成功回数を稼がない。

queued caseは待ちtaskと、その前で実行中のblockerの両方を記録する。表のqueued/request_stop_nsのn=100はblockerの停止であり、stopped=0の待ちtaskを停止100件成功とした値ではない。queued_cancel_publish_nsのn=100は実際の待ちtaskだけである。request_reclaim_nsやpublish_reclaim_nsもcase内の両taskを含むため、待ちtask単独の件数と区別する。

レモンの判断が必要なのは、欠測位相を未確認として受入れを保留する範囲、観測方法/題材を見直して別計画で再確認する範囲、メモリの予約・コミット確認、未対応の複合fixtureを補う範囲である。計画の回数・位相判別・目安を変える場合は事前に改訂・再固定する。回数を増やすだけで欠測や過去の超過が消えるとは扱わない。欠測の除外、目安緩和、queue_waiting=4やSnapshot容量の80%規則の免除も自動では行わない。今回これらの判断や追加実行は行っていない。

### 80%規則の追加対象と未実行コマンド

| 対象 | 観測最大と目安比 | 計画どおりの追加 |
|---|---|---|
| workloads/G1-open 投入→公開 | 81.278ms / 100ms = 81.278% | 同caseの10分を独立2回 |
| snapshot/snapshot image | 3,620,338 / 4,194,304 bytes = 86.316% | 独立1,000プロセス、各3取得 |
| memory/snapshot image | 3,620,425 / 4,194,304 bytes = 86.318% | 同case追加10回（footprint差の超過ではない） |
| workloads/I1 queue_waiting | 4 / 4 = 100%、超過0 | 同caseの10分を独立2回 |
| memory/I1 queue_waiting | 4 / 4 = 100%、超過0 | 同case追加10回 |
| size/__TEXT,__textの相対増加 | +8.8424% / +10% = 88.424%、目安超過0 | sizeの追加回数は計画に規定なし。追加方法・生成差分の評価をレモンが判断 |

G1-wall/snake・G2・T1・responseと、取消しの有効な時間標本は80%以下である。ただし欠測への対処は別に残る。Snapshot容量と待ち4件は設計上の上限内でも固定規則の例外がない。runnerのextend_requiredは表にある指標別フラグであり、footprint以外の容量も点検した。

以下は**未実行の追加手順**。各回の測定前にレモンへ確認し、確認参照を記録する。元runを保持し、新runへ元run IDと追加理由を残す。下記はMacのzsh -lc内で実行し、AC電源・他アプリ停止条件・caffeinateをそろえる。新しい確認を得る前に既存参照を使って追加測定を始めない。

```sh
zsh -lc '
set -eu
export PATH=/opt/homebrew/bin:$PATH
cd ~/source/zig/ForthSigma
: "${ACCEPTANCE_1383_EXTENSION_CONFIRMATION:?record the new user confirmation first}"
expected=ffb8e936ddda6df8cec2a5b3c789b3664155a365eccb1d9a6e15d715ab44a18b
actual=$(shasum -a 256 docs/TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md)
test "${actual%% *}" = "$expected"
# G1-openは投入→公開81.278%、I1は待ち4/4。各case10分を独立2回。
for repeat in 1 2; do
  caffeinate -i python3 tests/scripts/run-acceptance.py --mode measure --only workloads --probe-cases G1-open I1 --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md --plan-sha256 "$expected" --confirmed "$ACCEPTANCE_1383_EXTENSION_CONFIRMATION"
done
# Snapshot容量86.316%：追加1,000プロセス（各3取得）。
caffeinate -i python3 tests/scripts/run-acceptance.py --mode measure --only snapshot --probe-cases snapshot --repetitions 1000 --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md --plan-sha256 "$expected" --confirmed "$ACCEPTANCE_1383_EXTENSION_CONFIRMATION"
# memoryはSnapshot容量とI1の待ち4件が対象。各追加10回。
caffeinate -i python3 tests/scripts/run-acceptance.py --mode measure --only memory --probe-cases snapshot I1 --repetitions 10 --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md --plan-sha256 "$expected" --confirmed "$ACCEPTANCE_1383_EXTENSION_CONFIRMATION"
'
```

コマンドごとの実行確認を記録し、各新run IDと理由を対応付ける。取消しには今回80%超の有効時間標本がないため、80%規則による取消し追加コマンドはない。欠測位相を再確認する場合は観測方針を先に判断し、`--only reclaim --probe-cases cancel --probe-stages <対象位相>`、nativeは `--probe-cases native-fill` 等と `--probe-stages native_before native_running native_after` で絞る。これは再測定の確定指示ではなく、欠測を1,000回で補充して合格にする手順でもない。追加後も80%超・欠測・超過が残れば原因確認と再計画を要する。

### Macで残る手動確認とD07の未確認項目

固定計画7節と[英語manual](TASK_CONTROL_ACCEPTANCE_MANUAL.md)・[日本語manual](TASK_CONTROL_ACCEPTANCE_MANUAL.ja.md)の残項目を以下に示す。共有された2 runには前景実端末の手動結果がないため、Macではいずれも未確認。自動例やSSH pipeの成功を代用しない。

| 項目 | Macで残る操作・観察 | 残る限界 |
|---|---|---|
| AC-02 | task-path.fsでnと無関係キー、計算中q。入力/frame/generationの進行、旧世代が最新表示を上書きしないこと | 端末例だけでnative画面は合格にしない |
| AC-05 | check-task-console.fsのactiveでr、replacedでc、bye-activeでb。I/O進行、cancelled/released、一時ファイルと所有資源を確認 | 複数task・音・画面同時所有のfixture不足 |
| AC-18 | G1・検索・checksumで入力/終端/I/O/出力の進行、Enter要否、backend能力を記録 | 実I/O可用・paint/close・同時成立を同じ複合待機で扱うfixture不足 |
| 実native paint補助 | 利用可能backendでFORTHZ_PAINT_SMOKE=1のruntime-test。該当試験がskipでなくOK、128×128画面が開閉すること | この補助試験だけで全供給元の複合待機は合格にしない |
| AC-20 | 検索a/b反復と別セッションchecksumの進行・出力停止・世代を観察、q終了 | 別セッションは同一host公平性の証明でなく混在host fixture不足 |
| AC-24 | G1/検索/checksumを処理中qと新規起動Ctrl+Cで終了。psで前後のPID/thread/child、echo/カーソル/入力/新sigma起動を確認 | 短すぎる処理中終了は未確認。子・音・画面・停止不能host結合fixture不足 |
| AC-25 | G1でnnn、T1でba、q。最新世代、G1世代4の95頂点、T1 a=1,048,576一致/1,000保存、b=0、失敗時の従前表示と回収 | G2・最大負荷・混在I/Oでの差替えや失敗を確認するfixture不足 |
| 最大負荷の手動 | G1開放/壁/蛇行、G2、T1、I1で結果件数・main巡・供給継続・q後の資源回収を確認。response.fsでb/qと実端末変化 | 自動runの最大負荷成功から実キー/画面・音へ拡張しない |
| AC-27 | 上記をMacのOS/端末/backend、キー、期待/実際、終了コード、画面/ログ、source/binary SHA付きで記録 | 能力不足は未確認として残す |

D07との照合では、投入→公開（G1 100ms/G2 500ms/T1 200ms/I1 250ms）、公開→回収100ms、管理1ms/巡、Snapshot占有50ms、pipe入力→状態16.67msは有効標本で目安内。待ち取消し→公開10msも100件目安内である。一方、各用途の最大滞留（50/100/100/200ms）はacquired時刻がなく独立に未確認。60Hzの実提示、画面反映33.34ms、端末更新50ms、描画基準からの追加フレーム期限超過、入力欠落、混在I/O排出、公平性はこの計時では未確認。Snapshot取得開始→投入可能100msは投入可能端点を独立に保存しておらず、snapshot_main_nsだけから合格にしない。Snapshotの4MiB上限そのもの、3世代合計12MiBの全作業ピーク、全メモリ内訳、通常単一VM時間と生成差分も未確認として残す。

本節の追記では計画・コード・tqueを変更せず、git commit・branch・pushと新たな測定を行っていない。文書検査の結果は下記に記録する。

Windows PowerShellで `python scripts/check-docs.py` は終了コード0、`findings: 0`。`git diff --check` と固定計画のSHA-256一致も確認した。

## 2026-11-25 決定B：取消し位相を固定して再測定する準備

**ここからの計画が現行。以前の節の固定値とコマンドは当時の測定記録である。** レモンは「B: 段階を確実に狙える測り方に変えて、測り直す」を採用した。3 OSとも生成段階を狙った取消しの約7割を取り逃し、nativeのFILL・SEARCH・ROLLは最初の3回とも取り逃して打ち切ったためである。旧結果の欠測・超過を残し、新方式の標本と混ぜない。

| 現行固定計画 | SHA-256（この文字列を期待値として渡す） |
|---|---|
| [Windows/Linux v4](TASK_CONTROL_ACCEPTANCE_PLAN.md) | `f4994e515253eac7cd10a71906d628a6760a998878b44d619cd80b1be856a36e` |
| [macOS v2](TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md) | `aefdfe0e1e411c4d20eaf5aa520ebb68072a5ac686e38a7dd51f4d68288c0e36` |

両計画の`.gitattributes`の`-text`は維持した。今回変えたのは取消し位相の測り方と、最大量を通すためのnative題材であり、試行回数は変更していない。対象はWindows・Linux・Macのそれぞれ生成25段階、native 5種×3位相、待ち中、計41ケース×各100回（4,100回/OS、合計12,300回）。他群の追加・未確認項目は従前のまま残す。この取消し再測定はWindows queuedの既存追加1,000回等を完了扱いにしない。

### 実装とClaude案に対する選択

`task_acceptance.Storage.hold`が指定段階をatomicで通知し、workerは取消しtokenを確認するまで同じ位置で待つ。ホストTASK-STATEの巡回は通知を確認し、同じtask idで公開語TASK-CANCELのハンドラーを呼ぶ。requestedはその入口なので、holdで到達を待った時間は要求→停止/回収に入らない。stopped/reclaimedの意味と通常の取消し処理は維持した。holdは5秒の実時計guard、時計異常、shutdownのtokenで解除し、時間切れはhold_timeout=trueの理由付き欠測にする。通常ビルドはcomptimeで除去する。

生成・native before/afterは指定位置でholdする。duringについて旧通知方式を残すと取り逃しが続くため、**事前確認後のnative入口でholdし、要求後に最大量のnative全体を実行する保守的な代案**を選んだ。次の通常checkpointでtokenを検出する。method=`guarded-native-entry-full-call`で識別し、実処理中に要求したとは記録しない。nativeの残仕事量全体を要求→停止10msの区間に含めるD07確認であり、特定のOSスケジュールや全入力について最遅時間を証明するものではない。

FILLは64KiB、MOVE/COMPAREは32KiBの2領域。SEARCHは旧256×256の最初の候補一致を避け、65,535 bytesのaから1 byteのbを探す全文不一致（領域合計64KiB）とした。COMPAREは同値の全領域を読む。ROLLは旧4,000 cellsから8,192 cells（64KiB）へ変更し、この子プロセスだけ`--data-stack-size 16384`を付ける。題材と容量差はfixture manifestと子commandで識別する。これは最大量の代表題材であり、全パターンの中で最も遅い入力を選び切った証拠とは区別する。

phase_okは指定段階=hold_stage=request_stage、かつhold_timeout=false。native_runningは上記入口という意味で一致を確認する。待ち中はqueued=trueかつ未実行を確認する。native境界とrequestedが同時刻でもatomicによる位相確認を使い、旧方式の時刻推定とは混ぜない。smokeでもphase_okを保存し、端点0と空の速度統計を維持する。task行欠落・位相不一致・時間切れは欠測とし、最初の3回での打切りを廃止、成功数に達するまで補充もしない。

### Claudeが実行する再測定コマンド（今回は未実行）

各OSのリポジトリルートで実行する。runnerがReleaseFast/debug=false/strip=true/task-trace=false/task-acceptance=trueをビルドする。実行前後に固定計画を照合し、既存runを保持して新しいrunへ保存する。確認参照は今回の決定Bを示す。所要時間は、Windowsの新方式smoke 123試行の全体約10秒を単純換算すると約5分/OS。**※推測です：正常時はビルド・環境確認を除き5〜15分/OS、3 OSで15〜45分。** OS差や負荷で変動する。hold対象4,000件がすべて5秒で時間切れなら約5.6時間/OSに起動・回収費用が加わり、120秒の異常停止guardは別枠になる。

Windows（PowerShell）:

```powershell
python tests/scripts/run-acceptance.py --mode measure --only reclaim --repetitions 100 --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN.md --plan-sha256 f4994e515253eac7cd10a71906d628a6760a998878b44d619cd80b1be856a36e --confirmed lemon-approved-2026-11-25-phase-hold-B
```

Linux（Python 3）:

```sh
python3 tests/scripts/run-acceptance.py --mode measure --only reclaim --repetitions 100 --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN.md --plan-sha256 f4994e515253eac7cd10a71906d628a6760a998878b44d619cd80b1be856a36e --confirmed lemon-approved-2026-11-25-phase-hold-B
```

Mac（SSH先でもzsh -lcを使う）:

```sh
zsh -lc 'cd ~/source/zig/ForthSigma && caffeinate -i python3 tests/scripts/run-acceptance.py --mode measure --only reclaim --repetitions 100 --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md --plan-sha256 aefdfe0e1e411c4d20eaf5aa520ebb68072a5ac686e38a7dd51f4d68288c0e36 --confirmed lemon-approved-2026-11-25-phase-hold-B'
```

### ロクによるWindowsの短い検証

証拠は`.work/phase-hold/`。本測定は実施していない。`zig build test`、`zig build test -Ddebug=false`、`zig build runtime-test`、`zig build -Dtask-acceptance=true`、`python tests/scripts/verify-task-examples.py`（16グループ）、`python tests/scripts/test-acceptance-macos.py`（14件）、`zig build -Dtarget=aarch64-macos -Dtask-acceptance=true`、`zig build -Dtarget=x86_64-linux -Dtask-acceptance=true`は終了コード0。Zigのキャッシュはworktree内を使用した。クロスビルドは実機実行の代わりではない。

最大量題材で`--mode smoke --only reclaim --repetitions 3 --sigma zig-out/bin/sigma.exe`を実行し、`.work/acceptance/20261124T215513Z-149d9962/`で41ケース×3回=123件すべてphase_ok=true、phase_missing_count=0、missingなし、速度統計空を確認した。内部時刻は0なので10ms/100msの合否は判定していない。このrunは計画改訂前に動作確認した記録であり、新しい固定計画の本測定ではない。最終版の再確認は追記する。

`python tests/scripts/test-acceptance-hold.py`は、ホストがTASK-CANCELを呼ばずにBYEへ進む場合と、5秒guard後に取消し・回収する場合を各1回検証した。両方hold_stage=vm_startで到達を確認し、BYEはhold_timeout=false、時間切れはtrue、終了コード0。証拠は`.work/phase-hold/guards/`。

通常ビルドは変更前相当のソースコピーと現ソースを同じReleaseFast/debug=false/task-trace=false/task-acceptance=falseでビルドし、PEの.text全バイトを比較した。両方1,532,928 bytes、SHA-256=`1510320cab491aa5d634347d440bfa6c09c19423fea13e76992e84ea0102f15d`で完全一致した（`normal-control.py`、`compare.py`、`normal-comparison.json`）。比較元は今回変更のなかったHEADのruntime_base/host_task_apiと、作業開始時からあった変更を維持して新holdだけを除いたtask_acceptanceである。A/A′/Bの既存AC-29全体や通常単一VMの速度比較を完了した意味ではない。

今回もgit commit・branch・push、tque変更は行っていない。

最終版の固定計画v4を照合したsmokeは`.work/acceptance/20261124T220109Z-86a87405/`。41ケース×3回=123件すべてphase_ok=true、欠測0、速度統計空、runner終了コード0を再確認した。`python scripts/check-docs.py`（findings: 0）、変更されたZig全5ファイルの`zig fmt --check`、両計画のtext属性unsetを確認した。語リファレンスの日本語説明に通常APIの意味の変更がないことを確認し、出典ハッシュと生成文書を更新した。今回のログは`.work/phase-hold/`に保存した。

## 取消し位相の本測定の結果（2026-11-25）

Macの取消し位相（決定B）は、出力保留の修正後のrun `20261124T222720Z-457847ee`（main `ff7363b`、macOS計画v2 `aefdfe0e…0e36`）で、4,100/4,100 phase_ok、欠測0、要求→停止 最大0.027ms、要求→回収 最大1.60ms、待ち中の取消し 最大0.001ms、管理1巡 最大0.081ms。全指標で超過0件・80%超0件。3 OSの表は [1382報告書](TASK_CONTROL_IMPL_1382.md#出力保留の修正後の取消し位相の本測定2026-11-25) にある。

## 2026-11-25 対話の再測定

macOS v3 の固定SHA-256は `44622846f887091e8a2a3dfcfdda48e149438594678523ae4121eae713b683b8`。改訂理由とClaudeのコマンドは [1382実装報告の「対話の場面の測り直し（2026-11-25）と G1 の遅れ」](TASK_CONTROL_IMPL_1382.md) を参照する。

## Mac実機での構成C00〜C16（2026-11-25）

1381ではMacはクロスビルドだけだった。Claudeが、Mac実機（arm64、macOS 27.2.1、Zig 0.17.1）で `python3 tests/scripts/verify-task-public-matrix.py --fresh-cache` を実行し、C00〜C16の17構成すべてが合格した（main `adcc38b`、終了コード0、ログはMacの `.work/task-public-matrix/`）。これでC00〜C16はWindows・Linux・Macの3実機で合格した。

## 2026-11-25 受入れ全体の判定

最新runによるAC別・OS別の判定、過去runの置換、利用者決定、未確認事項の確認方法と担当は[受入れ総括（日本語）](TASK_CONTROL_ACCEPTANCE_SUMMARY.ja.md)・[Acceptance summary (English)](TASK_CONTROL_ACCEPTANCE_SUMMARY.md)に記録した。本報告の準備時点の「未実施」や旧runは履歴として保持し、現在の全体判定は総括を参照する。

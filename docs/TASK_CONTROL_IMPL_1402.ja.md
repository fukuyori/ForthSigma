# tque 1402：単一VMの配置変種

2026-11-26、Linux x86_64、開始時HEAD `333f8af`、Zig 0.17.1。[1390](TASK_CONTROL_IMPL_1390.ja.md)と[runner](../tests/scripts/single-vm-ab.py)を拡張した。本測定・時間の合否判定は実行していない。製品src/とbuild.zigは変更せず、tque・Gitの変更操作も行っていない。

## 構成

`--layout base|tail64|hot16|hot32` で新規構築を選ぶ（prepare、または--buildsなしのsmoke）。baseは1390と同じくBをリポジトリ直下で構築する。他の構成はA/Aprime/B/B-copyすべてを専用ソース複製で構築する。Aのarchive、Aprimeのworker入口だけの変更は1390と同じ。配置用の変更は複製のbuild.zigだけに行い、`<label>-layout.patch` に保存する。baseは空の配置パッチを記録する。4対照に同じ配置コードを挿入する。

複製buildでは `b.addWriteFiles()` で、16byte整列の小さなC関数 `svab_layout_probe` を生成する。内容はinline NOPとreturnで、測定負荷から呼ばない。`forceUndefinedSymbol` でリンカーGCの保持対象とし、ELF/Mach-Oでは逆アセンブルに存在することを必須とする。Windowsでも1403によりPDBの手続き記号と逆アセンブルした詰め物の検査を必須とした。`used` だけではリンカーGCを防げない。製品設定・ソース関数は変更しない。詰め物はバイト数で指定する。x86_64は1バイトNOP、aarch64/arm64（Apple M5を含む）は4バイトNOPをbytes/4命令使う。未対応アーキテクチャ、命令長で割り切れないバイト数はCプリプロセッサの検査によりprepare中に停止する。return、コンパイラのprologue/epilogue、整列は指定した詰め物に含めない。

- `tail64`：通常の `.text` に64byte NOPを置く。元の案の配置対照。
- `hot16`：ELFの `.text.hot` に16byte NOPを置く。
- `hot32`：ELFの `.text.hot` に32byte NOPを置く。

ELFのリンク順では `.text.hot` が通常のZig関数セクションより前に並ぶため、パディングでZigコードを動かせる。通常のC `.text` は後ろに置かれる場合がある。また64/256byte増加だけではmod 64が変わらないため、16/32byte増加を使う。採用方法の根拠は後述のLinux検証であり、追加バイト数だけから移動を推定しない。今回のLinuxリンクではtail64もZigコードより前に置かれ、他のリンク配置変化も含めBの通常runOperationsが128byte動いたが、mod64は変わらなかった。hot16はmod64を変えたため、優先セクションと64byte未満の増分を有効な変種として採用した。今回はC object追加順の逆転までは必要なかった。Mach-Oでは `__TEXT,__text`、COFFでは `.text$a` を使用する。Windowsでの実際の並びと配置移動は[1403](TASK_CONTROL_IMPL_1403.ja.md)に記録した。Mach-Oではnative検証が引き続き必要で、全OSでの移動は保証しない。

## macOSの配置と代案

macOS arm64（Apple M5）では、**`__TEXT,__text` のC関数がZigコードより前に並ぶかは未確認**。Cオブジェクトのクロスコンパイルで確認できるのはNOPのバイト数だけであり、最終実行ファイルの並びや通常runOperationsの移動ではない。`hot16`/`hot32` はバイト数を表す名前で、Mach-Oでは特別なhot節を選ばない。Macでの最終リンクとsmokeはClaudeが確認する。

追加関数がZigコードより後ろに並ぶ場合、調査した第一候補は `_svab_layout_probe` と詰め物のラベルを対象記号より先に指定する `-order_file`。LLVMには出力節内の記号の優先度と、並べ替えに必要なsubsectionの条件の説明がある（[SectionPriorities.h](https://llvm.googlesource.com/llvm-project.git/+/refs/tags/llvmorg-18.1.1/lld/MachO/SectionPriorities.h)、[Mach-Oのsubsection処理](https://lld.llvm.org/MachO/ld64-vs-lld.html)）。Zig 0.17.1からの指定方法、詰め物区間の保持、実際の移動は未確認。Cオブジェクト・リンク入力順の変更も未確認の候補。Mach-Oで先に並ぶ別の節も調査候補だが、確立した方法ではない。現在の[LLDの節順序](https://raw.githubusercontent.com/llvm/llvm-project/main/lld/MachO/OutputSegment.cpp)は他のコード節より `__text` を優先するため、節名を変えるだけでは先行配置を保証できない。ZigのMach-Oリンカーで利用可能な先行節や節順序の上書き方法は確認できていない。いずれも複製ビルドで試す代案であり、今回は実装していない。

## コマンド

Python 3.12以降、Zig 0.17.1、objdumpが必要。Mach-Oではnmも使用する。macOSではMach-O対応llvm-objdumpを指定する。以下のmeasureコマンドは提案であり、実行前に利用者が反復数・標本数・独立run数・延長規則を決定する。各配置・独立runについて新しい出力先で実行し、prepare元も保持する。配置を合算しない。測定区間・比較・不確かさの扱いは1390を参照する。

```sh
export ZIG_GLOBAL_CACHE_DIR=$PWD/.work/codex-cache/global ZIG_LOCAL_CACHE_DIR=$PWD/.work/codex-cache/local
# macOS: add --objdump llvm-objdump to every invocation below.
for layout in base tail64 hot16 hot32; do
  python3 tests/scripts/single-vm-ab.py --mode prepare --layout "$layout" --out ".work/1402-r2/$layout"
  python3 tests/scripts/single-vm-ab.py --mode smoke --builds ".work/1402-r2/$layout/builds.json" --out ".work/1402-r2/$layout-smoke"
done
# Only after the operator fixes the plan and environment; use fresh run directories.
python3 tests/scripts/single-vm-ab.py --mode measure --builds .work/1402-r2/hot16/builds.json --out .work/1402-r2/hot16-run1 --rounds 100 --warmup 5 --iterations 10000000 --confirmed USER-DECISION-REF --environment 'CPU, power, background load, terminal: fill before run'
```

```powershell
$env:ZIG_GLOBAL_CACHE_DIR="$PWD/.work/codex-cache/global"
$env:ZIG_LOCAL_CACHE_DIR="$PWD/.work/codex-cache/local"
foreach ($layout in 'base','tail64','hot16','hot32') {
  python tests/scripts/single-vm-ab.py --mode prepare --layout $layout --out ".work/1402-r2/$layout"
  if ($LASTEXITCODE) { throw "prepare $layout failed" }
  python tests/scripts/single-vm-ab.py --mode smoke --builds ".work/1402-r2/$layout/builds.json" --out ".work/1402-r2/$layout-smoke"
  if ($LASTEXITCODE) { throw "smoke $layout failed" }
}
# Only after the operator fixes the plan and environment; use fresh run directories.
python tests/scripts/single-vm-ab.py --mode measure --builds .work/1402-r2/hot16/builds.json --out .work/1402-r2/hot16-run1 --rounds 100 --warmup 5 --iterations 10000000 --confirmed USER-DECISION-REF --environment 'CPU, power, background load, terminal: fill before run'
if ($LASTEXITCODE) { throw 'measure failed' }
```

## 配置記録の読み方

`layout.json` はA/Aprime/B/B-copy別に `layout`、`symbols_status`、対象全実体の `functions`（runOperations、runOperationsLoop、executeWordMode、executeBuiltin）、追加関数の保持状況・番地、`probe_bytes`（期待する詰め物のバイト数）、`probe_actual_bytes`（逆アセンブルした詰め物のバイト数、baseはnull）を記録する。関数ごとに完全な記号名、整数・16進番地、byteサイズ、mod64、サイズの出典を残す。ELFはobjdump記号表を使う。Mach-Oでサイズが得られなければnmの番地順の記号と逆アセンブル範囲へフォールバックする。この範囲は整列パディングを含み得るため、厳密なソース関数サイズとして比較しない。独立した関数がない場合はインライン化の可能性があり、削除の証明にはならない。完全な記号表・逆アセンブルもJSONとともに保存する。

今回のLinuxビルドでは、`executeWordMode__func_183` がソース1956行の通常（counted=false、worker=false）分岐から `runOperations__func_186` を呼ぶ。行情報付きの証拠はhot16準備先の `B-normal-callsite.txt` に保存した。通常runOperationsは、worker=falseのexecuteWordMode / executeOperationsModeからの呼出しを追って同定する。匿名番号だけに依存しない。worker=trueは別ループへ入りキャンセル確認を行う。全実体を記録に残す。番地はリンク時仮想番地で、ASLR後の実行時番地ではない。`mod64` は番地を64で割った余り。配置実験として扱う前に、構築した変種間でBの通常runOperationsが複数のmod64値をとることを確認する。

Windowsではllvm-pdbutilとPEヘッダーからPDB記号を解決する。native検証と配置結果は[1403](TASK_CONTROL_IMPL_1403.ja.md)を参照。対象記号欠落、非base追加関数欠落、詰め物のバイト数が取得できない場合や期待値と一致しない場合は、WindowsでもELF/Mach-Oと同じくprepare・smokeを停止する。記号の取得だけでは実際の配置移動を確認したことにはならない。開始・終了ラベルも関数とともに保持対象とし、その番地区間が連続したNOP命令で埋まり、逆アセンブルした各命令のバイト数の合計が期待値と一致することを検査する。同じ番地の別名が省略された場合は記号表で解決する。各配置で従来どおりB/B-copyの.text全体一致を必須とする。一致は再現性の検査であり速度不変の証明ではない。--builds再利用は保存済み配置を引き継ぎ、非baseの--layoutとの併用は拒否する。

後日の承認済み本測定では、負荷ごとのB/A、B/Aprimeを中央値+1%・p95+2%の目安と個別に比較する。配置や独立runで符号・目安の内外が変われば判定不能とする。smokeはチェックサム確認のみで、この問いへの結論は出せない。

## 所要時間

※推測です：キャッシュ・機械により、4ビルドのprepareは配置ごと約2〜15分、4配置で約8〜60分を見込む。smokeは配置ごと45短時間プロセス（計180）で、追加で全体1〜5分程度を仮定する。性能測定結果ではない。1390の本測定案は独立runごと1,575プロセス。1プロセス0.1〜2秒なら約3〜53分/run、4配置×独立2runは約24〜424分にprepareを加える。Linux/macOS/Windowsのnative費用は測っていないため同じ仮定の範囲を置いている。INTERPRETや機械負荷により超過し得る。

## Linux検証

R2での再実行結果（前回の記録は `.work/1402/` に保持）：

| 配置 | B 通常runOperations | 関数サイズ | mod 64 | B/B-copy .textサイズ | NOPバイト数 期待値/実際 |
|---|---|---:|---:|---:|---:|
| base | `0x1141d90` | 11014 | 16 | 1387299 | — |
| tail64 | `0x1141e10` | 11014 | 16 | 1387379 | 64/64 |
| hot16 | `0x1141de0` | 11014 | 32 | 1387331 | 16/16 |
| hot32 | `0x1141df0` | 11014 | 48 | 1387347 | 32/32 |

全4配置のprepareと最終smokeが成功した。最終smokeは各45プロセス、計180プロセスのチェックサムが一致し、各配置のB/B-copy .textも全バイト一致した。非baseの追加関数は全12実体がGCで落ちず、逆アセンブルした詰め物は期待値64/16/32バイトと一致した（x86_64では64/16/32個のNOP）。Bの通常runOperationsはmod64が16・32・48の3値をとる。表は生成物の証拠であり時間測定結果ではない。準備記録は `.work/1402-r2/{base,tail64,hot16,hot32}/`、smokeは対応する `*-smoke/` に保存した。前回の `.work/1402/` の記録は保持する。配置間の検査済み一覧は `.work/1402-r2/layout-comparison.json` に保存した。

Python構文コンパイル、`python3 scripts/check-docs.py`（findings: 0）、`git diff --check` は成功した。詰め物パーサーはNOP以外・バイト列の欠落を拒否し、同じ番地の別名を処理できることを確認した。結果は `.work/1402-r2/parser-checks.json`。Linux tail64のBに対して期待値を意図的に60バイトとする異常系も実行し、実際の64バイトとの不一致で停止し、両方の値が `.work/1402-r2/mismatch-check/layout.json` に残ることを確認した。これらはnative Mach-O/PE実行ではない。製品src/とbuild.zigの差分はない。

## aarch64オブジェクト検証

Linux上で、実際に生成するC片を `zig cc -target aarch64-macos -c` でコンパイルし、`llvm-objdump-21 -d` で逆アセンブルした。オブジェクトはMach-O arm64、節は `__TEXT,__text`。`tail64` は16 NOP＝64バイト、`hot16` は4 NOP＝16バイト、`hot32` は8 NOP＝32バイト。番地区間と命令のバイト列が期待値と一致した。18バイトを指定する異常系では4で割り切れずコンパイルが失敗した。C片、オブジェクト、逆アセンブル、異常系の診断、`aarch64-check.json` は `.work/1402-r2/` に保存した。

Windowsのnative実行とPDB抽出は[1403](TASK_CONTROL_IMPL_1403.ja.md)に記録した。macOSのnative実行、最終Mach-Oでの追加関数の並びと通常runOperationsの移動、代案のリンク順指定の適用可否、時間の目安の配置感度は未確認。Macでの確認はClaudeが行う。--mode measureは一度も実行していない。[英語版](TASK_CONTROL_IMPL_1402.md)も参照。

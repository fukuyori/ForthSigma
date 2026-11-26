# tque 1403：Windows PDBによる単一VM配置検査

2026-11-26、Windows x86_64、Zig 0.17.1。[1402](TASK_CONTROL_IMPL_1402.ja.md)の配置変種にWindowsの記号解決を追加した。[英語版](TASK_CONTROL_IMPL_1403.md)も参照。

## 実装

[runner](../tests/scripts/single-vm-ab.py)はWindowsで実行体の隣のsigma.pdbを読む。`--pdbutil`でllvm-pdbutilを指定できる。省略時はPATHを探し、見つからなければ `C:\Program Files\LLVM\bin\llvm-pdbutil.exe` を使う。欠落・実行失敗は停止する。`dump --symbols --publics` の完全な出力を `*-pdb-symbols.txt` に残す。

S_LPROC32/S_GPROC32（_ID形式も含む）のセクション番号、10進オフセット、code sizeを解析する。PE32+ヘッダーのImageBaseとセクション表を読み、仮想番地をImageBase + セクションVirtualAddress + オフセットで求める。mod64はこのリンク時仮想番地から計算する。ASLR後の番地ではない。layout.jsonにはPDBのパス・SHA-256、ツール・バージョン、ImageBaseとそのmod64、SectionAlignmentとそのmod64、全セクションのVirtualAddressとそのmod64を記録する。

runOperations、runOperationsLoop、executeWordMode、executeBuiltin、executeWord、executeCompiledの全実体を記録する。インライン化されて独立記号のない関数を新しく作ることはしない。PDBの番地・code sizeでobjdumpの逆アセンブルを切り出し、関数名の見出し付きで `*-normal-functions.txt` に保存する。サイズの出典はPDB code sizeであり、次の記号までの推定範囲ではない。対象記号が一つもない場合、逆アセンブル範囲が空の場合は停止する。

非baseではsvab_layout_probeの手続き記号を必須とする。S_PUB32からsvab_padding_begin/endを解決し、既存の検査で連続したNOP命令のバイト数を合計する。欠落・不一致・NOP以外・番地の欠落で停止する。追加関数の入力節.text$a、対象関数群より前か、sigma_zcu.objに属する最初のZig手続きより前かを番地で記録する。入力節名は生成したCの属性による。ELF/Mach-Oの記号解決経路は変更していない。

## 実行と結果

| 配置 | B 通常runOperations 仮想番地 | サイズ | mod 64 | probe仮想番地 | NOPバイト数 |
|---|---|---:|---:|---|---:|
| base | `0x140041190` | 9979 | 16 | — | — |
| tail64 | `0x140041190` | 9979 | 16 | 0x140193450 | 64 |
| hot16 | `0x140041190` | 9979 | 16 | 0x140193450 | 16 |
| hot32 | `0x140041190` | 9979 | 16 | 0x140193450 | 32 |

全4配置のprepareとsmokeが成功した。各smokeは45プロセス（計180）、既存ビルドの再利用smokeも45プロセスで、すべてチェックサムが一致した。各配置のB/B-copyの.textは全バイト一致。非base全12実体のNOPは64/16/32バイトと一致した。ImageBaseは0x140000000、SectionAlignmentは4096で、ともに64の倍数。全セクションのVirtualAddressも64の倍数だった。追加関数は全対照でZigコードより後ろにあり、Bでは最初のZig手続き0x14001e0f0に対しprobeは0x140193450だった。Bの通常runOperationsは4配置すべてで番地・mod64が同じ。比較一覧は `.work/1403/layout-comparison.json`。baseとreuseの記号成果物は最終パーサーで再抽出し、manifestにartifact_refresh_script_sha256を記録した。

既存 `.work/1391-prepared/builds.json` の再利用smokeでも、BのrunOperations__func_144はセクション0001・オフセット262544・9979バイトで手作業の値と一致した。仮想番地は0x140041190、mod64は16。通常実体の同定は番号だけに依存せず、executeWordModeからの呼出しとsrc/forth.zigのworker=false経路を照合する。executeWordのコンテキストなし分岐はexecuteWordMode__func_141（0x140040240）へ進み、その0x14004059fのcallがrunOperations__func_144を呼ぶ。逆アセンブルをreuse/B-normal-callsite.txtに保持した。今回objdumpではPDBのソース行注釈は得られない。

PowerShellでZIG_GLOBAL_CACHE_DIRを `$PWD/.work/codex-cache/global`、ZIG_LOCAL_CACHE_DIRを `$PWD/.work/codex-cache/local` に設定した。各配置について `--mode prepare --layout <layout> --out .work/1403/<layout>`、続いて `--mode smoke --builds .work/1403/<layout>/builds.json --out .work/1403/<layout>-smoke` を実行した。既存ビルドのsmokeは `.work/1403/reuse` に保存した。完全なコマンドはmanifest.jsonとbuilds.jsonに残る。

## 制約と代案

今回の.text$aの追加関数はZigコードより後ろに置かれ、この詰め物では対象関数の配置を変えられていない。mod64が同じ結果を速度不変の証拠として扱わず、配置実験としては不十分とする。※推測です：複製ビルドで通常の.textのprobeオブジェクトをsigma_zcu.objより前に明示的にリンクする方法、または関数単位の節生成とCOFFの記号順指定を組み合わせる方法が次の調査候補になる。Zig 0.17.1での指定方法、リンカーへの適用可否、保持、64バイト未満の実際の移動はいずれも未確認で、今回は実装していない。本測定の前に最終番地を確認する必要がある。

本測定（--mode measure）は実行していない。性能差・時間の合否は未確認。native ELF/Mach-Oの再実行はしていない。製品src/・build.zigは変更せず、tque操作・Git変更操作は行っていない。複製build.zigの変更だけを配置実験に使う。

## 検査

`python -m py_compile tests/scripts/single-vm-ab.py`、`python scripts/check-docs.py`（findings: 0）、`git diff --check` が成功した。全対照の切り出し範囲の先頭と末尾がPDBの番地・code sizeに一致することも `.work/1403/verify.py` で確認した。

補助検査はS_LPROC32/S_GPROC32、10進オフセット、PE番地計算、公開ラベルの別名、欠落ラベル、NOP以外、命令列の欠落を確認し、結果を `.work/1403/parser-checks/results.json` に保存した。実物のtail64 Bで期待値を60にすると実際の64との不一致で停止した。PDB手続き記号を欠落扱いにする異常系でも停止した。診断は `.work/1403/negative-checks.json`、停止時のlayout.jsonはnegative-mismatch / negative-missing-probeに保持した。

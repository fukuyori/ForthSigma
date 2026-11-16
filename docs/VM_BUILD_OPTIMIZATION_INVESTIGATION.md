# ビルド最適化の調査（#793）

2026-11-16。ローカルZig 0.17.0、x86_64-windows-gnuとx86_64-linux-muslで確認した。**Linux musl・fast・WSL実行の範囲でfull LTOのサイズ縮小と回帰結果を確認。整数演算の2系列は約2.58%/2.68%短縮だったが既存10%目標未達で、今回の標準候補としては不採用。本体・配布設定は未変更。Windows GNUはリンク失敗。smallの独立比較も速度目標未達で初回調査を完了した。詳細は[small比較](VM_OPTIMIZE_SMALL_EXPERIMENT.md)へ記録。**

## 設定と対応の確認（#839）

build.zigはstandardTargetOptions/standardOptimizeOptionでtarget・CPU・最適化を受ける。配布スクリプトbuild-release.ps1/shは、target未指定なら-Dcpu=baselineを付ける。今回もtarget/CPUを明示し、fast・floatを含む通常機能・strip=trueを固定した。追加CPU命令を使うnative指定への変更は試していない。対象CPUの互換性や配布方針を変更する提案ではない。

ローカルcompiler helpの-flto/-fno-ltoとBuild.Step.Compile.lto、std.zig.LtoMode {none,full,thin}を確認した。プロジェクトにLTOの公開optionはないため、作業用コピーだけにtrial-lto=default/none/full/thinを追加した。共通buildファイルは変更していない。

| 対象 | default | none | full | thin |
| --- | --- | --- | --- | --- |
| Windows GNU | 1,809,408 bytes | defaultとSHA一致 | link失敗 | link失敗 |
| Linux musl | 1,891,456 bytes | defaultとSHA一致 | 1,829,296 bytes（−3.286%） | 1,912,976 bytes（＋1.138%） |

Windows default/noneは採用済み実行体379d…、Linux default/noneは基準bdb6…ともSHA一致。この2target・toolchain・入力での同一性であり、Zigの全環境の既定動作を一般化しない。thinのLinuxサイズは既定の1%増加上限を超える。fullはLinux側のサイズ条件だけ充足し、Windowsには生成物がないため評価不能である。両OSのサイズ基準を満たしたとは扱わない。

## Windowsでの失敗の切り分け

full/thinともfrexpf、frexpl、wmemchr等の未解決シンボルが出た。float=falseでも同じ種類のリンク失敗が再現し、浮動小数点を外す対策は成立しなかった。機能無効版の性能改善を候補へ数えていない。

putsを呼ぶ最小Zig＋libc、およびヘッダーを使わない小さなCプログラムでも、LTOなしは実行exit0、full/thinは同じ種類の未解決シンボルで失敗した。Forth固有のソースがなくても再現することは分かったが、リンク失敗の原因は未特定。Windows全般や別toolchainもLTO非対応と断定しない。未解決関数を空実装してリンクを通すことは行っていない。

## PGO

zig cc helpには-fprofile-instr-generate/-use等があるが、補助Cプローブはx86_64-windows-gnuだけで実行し、__llvm_profile_runtimeの未解決シンボルでリンクできなかった。Linux musl側のC PGOは未試行。最初の-march=x86-64はこのzig ccでunknown CPUになったため、baselineへ訂正した最終ログと分けて保存した。PGOによる実行データ生成や使用段階には進めていない。

最小Zigプローブを渡したbuild-exe CLIでは同じ-fprofile-instr-generateがunrecognized parameterだった。target/cpu未指定・-fno-emit-bin付きで引数解析が拒否した確認であり、VMソースやbuild API経由のPGOを試した結果ではない。この通常のフラグと今回のリンク構成で成立しなかった結果であり、LLVM IR・追加runtime・別構成を使う全てのPGO手法が不可能という意味ではない。C部分だけのPGOをZig VM全体の対応と数えない。

## Linux full LTOの実行・同一環境での再ビルド一致

通常と異なるlocal cacheパスを指定して再ビルドし、fullのSHA f149…・1,829,296 bytesが初回と一致した。同じマシン/ソース/toolchainで、global toolchain cacheは共有している。そのパスの実行前の空状態は記録していない。ソース絶対パス・cwdも同じで、global cacheにはmusl CRT/compiler-rt等が含まれ得る。別環境や全cache削除後の再現性は未確認。

通常8カーネル×default/full/thinの24実行で、出力・DEPTH=0・stderrが一致した。これは短いsmokeで、時間測定や全意味論の検証ではない。

core/hostテストartifactにもfull LTOを設定してfast試験を実施し、ZCUオブジェクトのbitcode化を確認した。Windowsからのクロス親コマンドはELFを直接起動できずexit1だが、生成されたテスト2本をWSLで実行し、core 1,011成功/5skip、host 63成功/1skip、両exit0。test_zcu.oの先頭4243c0deも記録した。CLI9項目も同じfull版SHA f149…の実行体で成功。unit/hostへの設定追加前後のbuild差分を保存した。Cオブジェクトや最終リンクのフラグそのものは直接記録していないため、全コンパイル単位へのLTO適用まで証明したとは扱わない。full/thinの区別はbuild API設定に基づき、本体はSHA・サイズの変化も確認した。

保存画像の双方向互換、他の機能無効構成、他target、標準34条件全体の時間評価は未実施。

## 速度の予備比較（#840）

Linux full LTOだけを予備候補として、整数演算1条件のCPU時間を比較する計画を事前固定した。基準100M pilotから約6秒の反復数を固定し、A/Aは5標本×2群、候補比較は7標本×2群。各実行体warmup1回を除外し順序を交互にする。全標本を残し、最小中央値5秒/差2%の校正未達なら候補を測らず停止する。

整数演算の既存Linux目標10%以上短縮かつ2δ超を予備判定に使い、新たな部分採用率は作らない。この1条件が通っても共通採用・Linux限定採用の根拠には足りない。2群は連続した別標本群で、独立環境を保証しない。候補の時間比較中はbuild/回帰/profileと重ねない。結果は以下のとおり。

[コマンド・全buildログ・最小再現例・差分・smoke・回帰](measurements/2026-11-16-build-optimization-capability.json)、[CLI9件](measurements/2026-11-16-build-lto-linux-cli.json)。installer/package/sign/tag/commit/pushは行っていない。


## 整数演算の予備結果

baseline-only pilotから774,406,557反復を固定。A/Aの最小中央値は5,740.364 ms、最大δは0.094018%で事前条件を満たした。候補比較は各7標本×2群、各warmup1回を除外。中央値比の変化は系列1 −2.579574%、系列2 −2.684161%。両系列で短縮した点推定だが、既存の10%目標には届かなかった。

この予備判定は未達とし、LOOP・残る通常項目・CATCHの時間比較へ進んでいない。全48測定標本・8warmup・pilotを保存し、再試行なし。今回の2実行体・1条件での結果であり、LTOの最適化機序とコード配置差は分離できていない。一般的な短縮率や統計的な保証として扱わない。[プロトコル・全標本・スクリプト](measurements/2026-11-16-build-lto-linux-screen.json)。

群内は奇数標本数のため先行順がA/A 3:2、比較4:3となり、群2で反転する。全体では均衡するが群ごとの偏りは残る。CPU0はLinux側affinityであり、Windowsホスト側負荷やスケジューリングは未記録。build/回帰/profileと重ねない運用をしたが、スクリプトによる強制や外乱全体の記録ではない。A/A差は信頼区間・変動の上限ではない。

[静的レビュー原文](VM_BUILD_OPTIMIZATION_CLAUDE_REVIEW.md)は計時未完了時点のbuild結果・方法を確認したもので、上記速度結果はレビュー後に確定し集計した。[対応記録](VM_BUILD_OPTIMIZATION_REVIEW_RESPONSE.md)。Windows MSVCやlld以外のリンカ、他toolchain/targetは未試行。

通常機能・baseline CPUを維持したsmall最適化は[独立比較](VM_OPTIMIZE_SMALL_EXPERIMENT.md)を実施し、両OSビルド/通常回帰は通過したが、Linux整数のCPU時間が約2.38倍となり予備判定で不採用とした。Windowsや他項目の時間は事前の打切り条件に従い未測定。PGO・native CPU追加命令・Linux full LTOの用途限定採用も今回決定していない。

#839の対応・サイズ・再ビルド/回帰確認、#840のLinux整数LTO予備比較、#841〜843のsmall独立評価を記録して、#793の初回調査を完了。PGO/追加CPU機能や他targetの効果を調べ尽くしたとは扱わず、今回の互換条件で小規模に適用する候補は採用しない。

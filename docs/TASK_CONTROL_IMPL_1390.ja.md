# tque 1390：単一VM A/A'/B 比較の準備

2026-11-25、Linux、開始時 main `8ad71bb`、Zig 0.17.1。本測定・時間の合否判定は実施していない。変更は作業ツリーに残す。tque・commit・branch・pushの操作は行わない。

## 対照と除去対象

根拠は[利用条件](TASK_CONTROL_USAGE_CONDITIONS.md)7節と122行の方針、[縮小計画](TASK_CONTROL_ACCEPTANCE_PLAN.md)3・6・9節、[1382報告](TASK_CONTROL_IMPL_1382.md)「コードの大きさの増加の内訳」。既存計画のハッシュ・内容は変更しない。本手順は未対応だった単一VM時間の追加手順であり、既存runnerの完遂やAC-29全体の合格を意味しない。

- A：W1前 `35523f676836134c4fbaed19e3d01d2a23ec2a92` を `git archive` し、専用ディレクトリへ展開する。
- B：作業ツリーの通常ビルド。ReleaseFast、debug=false、task-trace=false、task-acceptance=false、既定語群・VM容量、native target。逆アセンブルのためstrip=falseを全対照に統一する。配布用strip=trueの時間と混ぜない。
- A'：Bの追跡済み＋非ignore新規ファイルを複製し、`src/forth.zig` の `executeWord` にある `if (self.workerCancellation() != null)` を `if (comptime false)` に置換する。差分は `Aprime.patch` に保存する。アンカーが一意でなければ停止する。

実際の置換は次のとおりである。

```diff
-        if (self.workerCancellation() != null) return self.executeWordMode(true, id);
+        if (comptime false) return self.executeWordMode(true, id);
```

除くのはnative再入を含む公開内部入口のworker context判定と、その入口からのworker側分岐である。`runAsWorkerWithMemory` → `executeWordMode(true)`、worker用 `runOperations` / `runOperationsLoop` の2つ目の実体、task service、State配置、回復処理は残す。このためA'はworker製品動作の対照ではなく、**workerを使わない単一VM専用の対照**である。workerのnative再入に使ってはならない。製品src/build.zigは変更しない。新しい製品ビルド設定も追加しない。

A/B差にはW1以後の他の変更も含む。A'/B差にも最適化・インライン化・配置の波及が含まれ、すべてを入口の費用と断定しない。A/A'差もそのまま測定ノイズとは解釈できない。1382で大きかったworkerループの2つ目の実体は意図的に残し、構造の差を小さくする。

## 測定器

[新しいrunner](../tests/scripts/single-vm-ab.py)はA/A'/Bを構築し、未変更のB複製も別配置でビルドする。BとB複製の.text（Macは__text）のバイト数・SHA-256が一致しなければ停止する。製品の既定構成に変更がないことの確認であり、A'の機械語一致や速度不変の証明ではない。

負荷は個別に集計する。CALCは既存 `scripts/benchmark-runtime.py` の算術題材、XTは実行トークンのEXECUTE、DEFERREDはDEFER/ISによる呼出し、INTERPRETはEVALUATEによる文字列の通常解釈、byte-scanは4KiBバッファのバイト集計である。最後はI/O塊の集計に近い小さな合成例であり、実アプリ全体の代替ではない。入力ファイルI/O・描画・workerは含めない。全負荷が独立に整数チェックサムを検証する。

各標本は独立プロセス。定義・初期化・コンパイル後のREADYで待機し、親の1byte解放からDONE行の親受信までを `monotonic_ns` で測る。起動時間は除くが、pipe・親の実行待ち・完了出力を含む壁時間であり、純VM CPU時間ではない。Linux/Windows/macOSで同じ区間を使う。別にプロセス全体の壁時間も費用見積り用に保存する。短すぎる負荷では1%の差を論じられない。反復数は結果を見る前に、十分長い区間を得られる設定に固定する。

A,A',B の全6順列を順に巡回し、各負荷でwarmupと本標本を分離する。中央値は中央2値の平均、p95はnearest rank。B/A、B/A'、A'/Aの増加率と中央値1%・p95 2%の目安との照合を出す。主判断は負荷ごとのB/A、他2比較は切分け材料であり、負荷間の相殺平均はない。数値内でも自動承認しない。smokeは各対照1回warmup＋2回のチェックサム確認のみ、時間統計・合否は出さない。

提案は縮小案Aの起動比較等と同じ考え方で **各負荷・各対照5 warmup＋100標本、独立2run**。100標本のp95は95番目であり尾部の情報は少ない。回数・反復数・run数の固定は利用者の判断事項で、まだ採用された計画ではない。measureは明示的な `--rounds`・`--confirmed`・`--environment` がないと開始しない。試行数、除外なし、中断・異常はrun全体を未完了とする方針を事前に固定する。遅い標本は捨てず、再測定は旧runを残した新runで行う。既存計画の80%規則をこの相対比へ自動転用しない。追加回数と発動条件は実行前に別途決定する。

ソースmanifest、archive、パッチ、HEAD/status、Zig版・実体ハッシュ、ビルドコマンド・ログ、実行体ハッシュ、fixtureとハッシュ、warmup込みJSONL、summary、objdumpの全逆アセンブル・関数抜粋・section表を保存する。`--builds`で既存構築物を再利用できる（その元ディレクトリも保持する）。再利用時も実行体ハッシュと.textを再採取する。中断時にはJSONLが残り、summaryのないrunを合格にしてはならない。

## 配置と不確かさ

B複製の一致は再現性確認だけで、配置感度を解消しない。Claudeは本測定前に、同じA/A'/B一組についてリンク順・textパディングを変えた複数の構築物を準備し、変更パッチ・ビルドコマンド・各関数アドレスを保存する。具体案は別コピーのbuild.zigで、測定対象から参照されない小さなC関数（リンカーGCで落ちないことを逆アセンブルで確認）を追加し、0/64/256byteのNOPを含む構成と、C object追加順を逆にした構成を同じ対照三つへ適用する。これは未実装・未実行の追加実験案で、ファイル末尾のゼロ埋めや単なるASLRの繰返しを関数配置変更の代用にしない。

各構成は別runとして本runnerの `--builds` にA/Aprime/B/B-copyの実行体を指定したJSONを渡せる。形式は生成したbuilds.jsonを参照する。各配置でもB-copyは同じ配置設定のBの複製とする。配置ごとの値を混ぜず、差の符号・目安の内外が配置や独立runで変わるなら判定不能として追加調査する。信頼区間を自動計算する機能はない。変動が1%判断に対して大きい場合も判定不能。配置の追加実験を行うまでは配置影響の不確かさが残る。

`*-normal-functions.txt` はrunOperations/Loop、executeWord/Mode、executeBuiltin、executeCompiledに一致する全実体の抜粋。匿名番号・アドレス・呼出先再配置を区別し、通常（worker=false）とworkerの実体をソース・呼出しから同定して比較する。単純なテキストdiffだけで命令差を断定しない。インライン化された入口は全disassemblyでも確認する。

## Claudeの本測定コマンド

リポジトリルートで実行。Python 3.12以降、Zig 0.17.1、git、GNU objdumpまたは互換llvm-objdumpが必要。Macは `--objdump llvm-objdump` 等、__textとMach-Oを読めるものを指定する。Windows/macOSでの実行は未確認。以下の100回・反復10,000,000・独立2runは**提案**であり、採用する値と環境メモ・確認参照を利用者が実行前に確定する。異なる環境・設定を合算しない。出力先は毎回未使用の名前とする。

Linux/macOS（Macではobjdump引数を対応ツールに変更）：

```sh
export ZIG_GLOBAL_CACHE_DIR=$PWD/.work/codex-cache/global ZIG_LOCAL_CACHE_DIR=$PWD/.work/codex-cache/local
python3 tests/scripts/single-vm-ab.py --mode prepare --out .work/1390-prepared
python3 tests/scripts/single-vm-ab.py --mode measure --builds .work/1390-prepared/builds.json --out .work/1390-run1 --rounds 100 --warmup 5 --iterations 10000000 --confirmed USER-DECISION-REF --environment 'CPU, power, background load, terminal: fill before run'
python3 tests/scripts/single-vm-ab.py --mode measure --builds .work/1390-prepared/builds.json --out .work/1390-run2 --rounds 100 --warmup 5 --iterations 10000000 --confirmed USER-DECISION-REF --environment 'CPU, power, background load, terminal: fill before run'
```

Windows PowerShell：

```powershell
$env:ZIG_GLOBAL_CACHE_DIR="$PWD/.work/codex-cache/global"
$env:ZIG_LOCAL_CACHE_DIR="$PWD/.work/codex-cache/local"
python tests/scripts/single-vm-ab.py --mode prepare --out .work/1390-prepared
if ($LASTEXITCODE) { throw 'prepare failed' }
foreach ($n in 1,2) {
  python tests/scripts/single-vm-ab.py --mode measure --builds .work/1390-prepared/builds.json --out ".work/1390-run$n" --rounds 100 --warmup 5 --iterations 10000000 --confirmed USER-DECISION-REF --environment 'CPU, power, background load, terminal: fill before run'
  if ($LASTEXITCODE) { throw "run $n failed" }
}
```

所要時間の式は1runあたり `3 × (100+5) × 各5負荷の平均プロセス時間の和`、計1,575プロセス。※推測です：各プロセス平均0.1〜2秒なら約3〜53分/run、独立2runは約6〜106分/OS。INTERPRETが他の負荷より長くなる可能性があり、この範囲は保証しない。※推測です：4ビルド・逆アセンブルに別途2〜15分/OS、配置追加構成ごとに同程度のビルドと2run分を加える。Windows/Linux/Macそれぞれの速度は本測定しておらず同じ仮定を置いた見積りである。smokeの短い反復を線形に外挿した本測定性能値ではない。

## Linuxの検証

最終結果は以下に追記する。既知のサンドボックスX11 `send=-1` は実装の修正対象にしない。

- `zig build test`：1,662 pass、48 skip、2 fail。失敗はmain/runtime双方の同じX11 `send=-1` のみ。記録は `.work/1390/test.log`。
- `zig build test -Ddebug=false`：1,587 pass、123 skip、2 fail。同じX11試験のみ。
- `zig build runtime-test`：182 pass、17 skip、1 fail。同じX11試験のみ。上記3コマンドを完全成功とは報告しない。
- smoke：`.work/1390/smoke-verified/`。5負荷×3対照×（warmup 1＋確認2）＝45プロセス、チェックサム成功、時間の合否なし。最初の `.work/1390/smoke/` は題材名の既存語衝突で停止し、専用接頭辞 `SVAB-` を付けて修正した。最初の記録も保持する。
- `python3 -m py_compile tests/scripts/single-vm-ab.py`、`git diff --check`：成功。
- `python3 scripts/check-docs.py`：英日コードブロック数の不一致を直した後、findings: 0。

逆アセンブルでは実行ループの一部がrunOperationsへインライン化されるため、runOperationsLoopという名前のシンボル数だけでworker実体の有無を判断しない。A'のソース上のworker入口と両コンパイル時モードは残っている。

リポジトリ直下からも通常Bを再ビルドして最終smokeを再実行した。BとB複製の.textはともに1,387,299 bytes、SHA-256 `afd2fc65b2f1ab91f0797e2f4d49ac606e9270611a6b92e5bff6c64a293971e1`、全バイト一致。Aは1,279,875 bytes、A'は1,385,571 bytes。サイズは生成物確認の記録であり時間の判定ではない。`zig build test` の再実行は成功済みの検査がキャッシュされ、367 pass・36 skip・同じX11 2 failだった。上の1,662 passは初回全体の結果である。最終チェックのログは `.work/1390/` に残す。

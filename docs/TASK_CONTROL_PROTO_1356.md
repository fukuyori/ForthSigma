# タスク1356：タスク制御01-C5 時間の測定

作成日：2026-11-23（測定日・終了時刻は生データのorder.csvによる）。本書は1357への測定資料である。方式の採用、利用条件、合格閾値、取消しの保証上限は定めない。

## 1. 対象と条件

利用者から他アプリケーションを止めた状態での測定許可を受け、ビルド・実行をすべて逐次に行った。並行ビルド・WSLビルド・並行ベンチマークは起動していない。OSのバックグラウンド処理を排除した保証はない。

- W1：`D:/tmp/forthz-1352`。開始時から存在した未コミットのW1試作を測る。HEADだけではソースを識別できないため、全src/includeと根のbuild.zig・LICENSE・VERSION・THIRD_PARTY_NOTICES.mdの内容ハッシュを保存する。
- base：`D:/tmp/forthz-base`、HEAD `35523f676836134c4fbaed19e3d01d2a23ec2a92`。ソースは変更していない。baseをimportする測定用実行体もW1側のbench-1356内へ出力する。
- 参照：詳細計画14節、PROTO_1352、1353側のPROTO_1353、1354側のPROTO_1354。Snapshotの非保存状態や許可集合の制約を解消したとは扱わない。
- 実行環境：Windows 11 Pro x86_64、10.0.26300/build 26300。AMD Ryzen 7 7700、8物理コア・16論理コア。電源プランは「バランス」である。CPU/OS/電源の取得結果はbench-1356直下に保存する。
- Zig 0.17.1、ReleaseFast（Zig 0.17.1の`.fast`）、debug=false、strip=true、native targetである。語群float/files/help/tools/image/graphics/x11/audio/extensionはすべてtrueである。memory_mib=32、locals_kib=64、stack_cells=4096、max_words=65535、names_kib=1024である。
- 測定用ホストのメインスレッドのスタック予約は16 MiB、allocatorは`std.heap.page_allocator`である。affinity・優先度・電源設定は変更していない。CPUの実動作周波数・温度・boost状態は取得していない。
- 既存のmain.zigから作るsigma.exeではなく、同じVMソースをimportする専用ホストを使う。Dのbase/W1は同一のホスト・ビルド設定・Forth入力であり、import先のVMツリーだけを変える。CLI起動・端末処理・ファイル読込み時間を含めない。

## 2. 方法と再実行

新規ファイル[build.zig](../bench-1356/build.zig)、[main.zig](../bench-1356/main.zig)、[run.ps1](../bench-1356/run.ps1)を用いる。既存のVMソース・build.zig・試験ルートの挙動を変更していない。CORE-MATH/FMAは既存build.zigと同じCソース・フラグでリンクする。ライセンスと第三者通知の既存文書を維持する。

```powershell
Set-Location D:/tmp/forthz-1352
# キャッシュ・出力はこの作業ツリー内。run.ps1内は同期呼出し、-j1である。
./bench-1356/run.ps1
python bench-1356/analyze.py
```

個別のビルド例は以下である。最適化・debug・語群は専用build.zigで上記の値に固定している。

```powershell
$env:ZIG_GLOBAL_CACHE_DIR = "$PWD/.zig-global-cache"
zig build --build-file bench-1356/build.zig '-Dsource=D:/tmp/forthz-1352/src' '-Dsuite=a_true' --prefix "$PWD/bench-1356/bin/a_true" -j1
zig build --build-file bench-1356/build.zig '-Dsource=D:/tmp/forthz-base/src' '-Dsuite=d' --prefix "$PWD/bench-1356/bin/base" -j1
& ./bench-1356/bin/a_true/bin/bench.exe 2> ./bench-1356/raw/a_true-0.csv
```

時計はQueryPerformanceCounterであり、QueryPerformanceFrequencyをプロセス開始時に取得し、整数演算でnsに換算する。今回のQPCは10 MHz、1目盛り100 nsである。raw/の正式44ファイルのns列は全2,015行で100の倍数である（補助情報行の0を含む）。サブµsの値も100 nsの目盛りで量子化されており、例えばAのtrueのstate_alloc中央値600 nsは6目盛りである。中央2値の平均では50 ns刻みの中央値も生じるが、時計の分解能が向上したことを意味しない。表の小数桁は時計精度の保証ではない。空の計時区間のオーバーヘッドは別測定しておらず、時計呼出しの境界費用を差し引いていない。CSV出力と結果検算は計時区間外である。

A〜Cは各条件につき105回である。iteration=0を初回として分け、1〜4を追加ウォームアップ、5〜104の100回を集計する。初回もOS起動直後・CPUキャッシュ無効・ページキャッシュ無効を意味せず、そのプロセス内の当該操作の初回である。Bは先にイメージを一度作るため、encodeのiteration=0もAPIの絶対的な初呼出しではない。CのNATIVEはPUREの測定後である。いずれも条件間の完全な冷時比較ではない。

Dは20組である。偶数組はbase→W1、奇数組はW1→baseとし、各実行体を交互に40プロセス実行する。各プロセス内ではCALC→XT→DEFERRED→INTERPRETの順に、それぞれ3回ウォームアップ後1回測る。同一組内の比も保存する。集計対象は負荷・実行体ごとに20回である。A→B→C→Dを含むプロセス実行順・開始/終了・終了コードはorder.csv、内部順はmain.zigとCSVの行順で追跡できる。

中央値は中央2値の平均、p95は昇順の`ceil(0.95*n)`番目、最大は当該標本の観測最大値である。観測最大値は保証上限ではない。[analyze.py](../bench-1356/analyze.py)は44プロセスの成功・順序・非重複・集計件数も検査する。

### A：VM作成

既定SizesでStorage.allocateを実行し、State用領域を別途確保してState.initを呼ぶ。already_zero=trueにはOSから新規ゼロページを返すpage_allocatorを使う。falseではStorage.allocate自身によるmemory/data/return/floatのゼロ化も含む。どちらもStorageを毎回解放して新規確保する。ウォームアップ後も同じStorageの再利用ではない。

allocate、State確保、initを個別に計時する。「allocate+init」は個別区間の和であり、State確保を除く。「total」はState確保を含む連続区間である。init後の語検索で初期化を確認する。State/Storageの論理的な確保量と、初回init後のプロセスWorkingSet/PrivateUsageも記録する。後者はプロセス全体の値であり、VMだけの常駐量・仮想予約量とは一致しない。OSページ丸め、allocator管理費、スレッドスタック等を論理量へ含めない。

### B：Snapshot

入力は算術定義100語・変数100語・入口ENTRY・64 KiBのPAYLOADである。[inputs.md](../bench-1356/inputs.md)とmain.zigに入力を保存する。各変数へ番号の値を入れ、PAYLOADを0x5aで埋める。ENTRYの結果146を復元後に検算する。

encodeImageは事前確保した出力バッファへの符号化だけを測る。encodedSize・バッファ確保は含めない。対象は毎反復で新規Storageを確保してinitし、restoreFreshImageを呼ぶ。Storage確保・initを計時に含めない。その反復内の同じ対象へPAYLOADの上書きとEXTRA語の追加を行ってからrestoreImageを呼び、EXTRAが消えたことも確認し、対象を解放する。反復をまたいでVMを再利用していない。対象の約64 MiBのmemoryの大部分は未使用であり、restoreImageの全域消去（block buffer領域を除くmemset）は未接触ページの初回ページフォールト費用を含む。restore系の内部preflight、コピー、再配置、specialize/inline復元は含むが、1353/1360の許可検査・タスク投入・転送は含めない。任意のヒープ・資源・全種類の再配置を代表する入力ではない。

### C：取消し

専用VMを呼出し元スレッドでrunAsWorkerにより実行する。別の要求スレッドが開始callbackのatomic到達印を待ち、Sleep(2)後にQPCを読み、Cancellation.requestを1回呼ぶ。runAsWorkerがTaskCancelledで戻った直後のQPCとの差を測る。要求前のSleep、スレッド起動・join・VM確保/解放は含まない。request直前の時計から測るため、requestのatomic store自体とその直前の境界費用も含む。

PUREは`BEGIN AGAIN`、NATIVEは確保済みの専用1 MiBへFILLするループである。先頭の`1 .`は開始通知だけに使い、計時開始前に通過する。FILLは監査表上の条件付き許可語であり、ここでは専用データ領域に限定した信頼する入力である。一般の領域保護を検証したものではない。

現在の`State.worker_poll_interval`は1024である。workerループ入口および1024 Opごとにatomic印を確認し、個々のFILL内部には確認を追加していない。要求位相を個々のFILLの開始/終了に同期させていない。確認時刻・停止内部時刻・回収時間は分離測定していない。戻り値・文脈復元を検査し、要求スレッドをjoinしてからトークンを破棄する。要求スレッドは30秒のハング検出監視を持つが、これは合格閾値・本番期限ではない。監視スレッドも測定中のCPUを使用する。

### D：通常入口の費用

CALCは500万回のBEGIN/WHILEによる整数計算である。XTは定数語ONEのxtをコンパイル済みEXECUTEで200万回実行する。builtinのxtはwordInLoopからbuiltinInLoopへ短絡するため、非builtinの定数語を選びexecuteWordへの経路を通す。XTに.executeが残り、ONEが.constantであることを実行前に検査する。DEFERREDはbuiltin 1+を設定したDEFER語を200万回呼び、INCが.deferredであることを確認する。INTERPRETは行`SHORT 40 2 + DROP`を10万回解釈する。測定区間内の入口は次のとおりである（main.zig、forth.zigのhandleWord・executeWord・executeColon・wordInLoopとOpディスパッチによる）。

| 負荷 | executeWord入口 | executeOperations入口 |
|---|---|---|
| CALC | ホストからCALCへ1回 | CALCのコロン定義へ1回。内部の整数計算・ループでは入口を反復しない |
| XT | ホストからXTへ1回、EXECUTEから定数ONEへ200万回 | 外側のXTへ1回。ONEの実行では入らない |
| DEFERRED | ホストからDEFERREDへ1回、INCへ200万回、その参照先のbuiltin 1+へ200万回 | 外側のDEFERREDへ1回。INCと1+の実行では入らない |
| INTERPRET | 各行のSHORT・+・DROPが通る。40と2は数値の解釈である | 各行のSHORTだけが入る（10万回）。解釈した算術`40 2 + DROP`は入らない |

これらはworker経路の費用ではなくworker_cancellation=nullの通常経路の比較である。結果の数値・最終スタックを毎回検算する。測定差はW1試作全体の実行差であり、追加分岐1個だけの単価や命令列の同一性を示さない。State配置・コード配置・最適化判断の影響も分離していない。

## 3. 結果

正式測定は2026-11-23 22:58:04.992〜22:58:37.164（JST）である。44プロセスすべて終了コード0であり、順序と非重複の検査を通過した。以下の時間表はµs単位である。初回値はn=1の観測値であり、分布を表さない。

### A：作成時間

| already_zero | 区間 | 初回 | ウォーム中央値 | p95 | 観測最大 |
|---|---|---:|---:|---:|---:|
| true | allocate | 7.800 | 4.100 | 5.500 | 9.000 |
| true | state_alloc | 0.800 | 0.600 | 0.800 | 1.000 |
| true | init | 250.400 | 89.900 | 115.600 | 131.500 |
| true | allocate_plus_init | 258.200 | 94.000 | 121.300 | 140.500 |
| true | total | 259.000 | 94.600 | 122.000 | 141.500 |
| false | allocate | 7,596.400 | 7,989.450 | 8,723.700 | 15,674.400 |
| false | state_alloc | 3.200 | 2.500 | 4.900 | 22.100 |
| false | init | 179.800 | 90.850 | 163.600 | 261.000 |
| false | allocate_plus_init | 7,776.200 | 8,089.550 | 8,813.300 | 15,838.600 |
| false | total | 7,779.400 | 8,091.400 | 8,816.200 | 15,843.900 |

State本体は6,777,936 bytes、Storageの記述子は152 bytesである。Storageが別途確保する領域は次のとおりである。

| 領域 | bytes |
|---|---:|
| State | 6,777,936 |
| memory | 67,174,400 |
| data_stack | 32,768 |
| return_stack | 32,768 |
| float_stack | 32,768 |
| loop_stack | 131,072 |
| frames | 65,536 |
| catches | 1,540,096 |
| Storage別確保合計 | 69,009,408 |
| State + Storage別確保の論理合計 | 75,787,344 |

この論理合計にはState内のslice/サイズ情報（Storage記述子と重なる情報）を二重加算しない。OSのVirtualQueryを用いた別の非計時プロファイルでも、各割当のallocation_baseが8件すべて異なることを確認した。true/false双方で領域合計は予約75,788,288 bytes、コミット75,788,288 bytesであった（ページ単位の丸めを含む、VMの8割当のみ）。仮想アドレス割当間の空隙、実行体、スレッドスタック、イメージ等は含まない。

初回init前後のプロセス全体のメモリ量は以下である。WorkingSetは常駐ページ、PrivateUsageはプロセスのプライベートなコミット量の指標であり、同じ値ではない。

| already_zero | WorkingSet 前→後 (bytes) | PrivateUsage 前→後 (bytes) |
|---|---:|---:|
| true | 3,964,928 → 4,403,200 | 622,592 → 76,558,336 |
| false | 3,964,928 → 71,671,808 | 630,784 → 76,570,624 |

予約/コミットの補足は正式な時間測定の完了後に[memory.zig](../bench-1356/memory.zig)からVirtualQueryで取得した値である。再実行は`./bench-1356/memory-run.ps1`で行う。trueでは未接触ページの常駐を抑えても、同量の予約/コミットがある。already_zero=trueはページフォールト費用をなくすのではなく、そのページを最初に使うときへ先送りする。trueの確保・初回init前後のWorkingSet増加は438,272 bytes（約0.4 MB）にとどまる。初期化直後のWorkingSetだけをworkerのメモリ予算に使わない。

### B：Snapshot

イメージ長は全反復で176,831 bytesであった。出力バッファとSnapshotの別途所有メモリはAの値に含めない。

| 操作 | 初回 | ウォーム中央値 | p95 | 観測最大 |
|---|---:|---:|---:|---:|
| encode | 548.700 | 559.400 | 681.300 | 913.900 |
| restoreFresh | 333.200 | 317.700 | 403.200 | 473.500 |
| restore | 8,220.300 | 8,295.950 | 9,052.600 | 15,841.600 |

### C：取消し要求からrunAsWorkerの帰還

| 負荷 | 初回 | ウォーム中央値 | p95 | 観測最大 |
|---|---:|---:|---:|---:|
| PURE | 28.800 | 4.650 | 54.900 | 91.600 |
| NATIVE | 1,420.300 | 919.500 | 1,722.100 | 2,031.400 |

### D：通常経路の実行時間

| 負荷 | 実行体 | 中央値 | p95 | 観測最大 |
|---|---|---:|---:|---:|
| CALC | base | 72,175.800 | 74,211.600 | 74,551.000 |
| CALC | W1 | 70,093.150 | 71,926.200 | 72,522.200 |
| XT | base | 30,932.200 | 31,795.200 | 31,883.600 |
| XT | W1 | 31,796.200 | 33,305.500 | 33,473.400 |
| DEFERRED | base | 36,735.400 | 37,865.100 | 40,534.000 |
| DEFERRED | W1 | 37,920.600 | 39,949.700 | 41,332.100 |
| INTERPRET | base | 22,518.400 | 23,243.800 | 23,642.200 |
| INTERPRET | W1 | 22,241.750 | 23,207.400 | 23,569.300 |

| 負荷 | 中央値同士のW1/base差 | 同一組の比の中央値 | W1>base | 両側符号検定 p | 比の母中央値の95%区間 |
|---|---:|---:|---:|---:|---:|
| CALC | -2.89% | 0.97017 | 3/20 | 0.002577 | 0.962398〜0.984859 |
| XT | +2.79% | 1.02505 | 16/20 | 0.011818 | 1.010363〜1.044294 |
| DEFERRED | +3.23% | 1.03261 | 19/20 | 0.0000401 | 1.019028〜1.043417 |
| INTERPRET | -1.23% | 0.98957 | 5/20 | 0.041389 | 0.972823〜0.997821 |

raw/base-0〜19.csvとraw/d-0〜19.csvのiteration=3を組ごとに対応させて算出した。同値の組はない。符号検定は帰無仮説をW1>baseの確率1/2とし、二項分布の小さい側の裾確率を2倍した正確両側検定である。p値は負荷ごとの値であり、多重比較補正は行っていない。区間は比を昇順にした第6・第15順序統計量であり、独立な組と連続分布を前提とする母中央値の分布によらない区間である。離散的な標本数のため実際の被覆率は約95.86%である。4負荷ともこの区間は1を含まない。最小値〜最大値が1をまたぐことを有意差の判定基準にはしない。

負の差はW1側の時間が短いことを表す。XTはconstant種別のONEを指すコンパイル済みEXECUTE Opの存在を検査する。builtin xtの場合にexecuteWord入口を通らない経路と区別した。DEFERREDはINCのdeferred種別を確認する。INTERPRETのSHORTはexecuteWordからexecuteColon経由でexecuteOperationsへ入り、解釈した算術の+・DROPはexecuteWordからbuiltinを実行する。返るスタック値/深さを各回検算した。

詳細計画14節の「既存への影響」のうち、保存済みartifact-sha256.csvによる専用ホストの実行体サイズ比較は次のとおりである。現在のbin/の再ハッシュは行っていない。

| 対象 | base | W1 | 差（W1−base） |
|---|---:|---:|---:|
| 実行体サイズ（bytes） | 2,369,024 | 2,381,312 | +12,288 |
| 起動時間 | 未測定 | 未測定 | 未測定 |

サイズはbin/base/bin/bench.exeとbin/d/bin/bench.exeの比較であり、製品CLIやインストーラーのサイズではない。

### 保存データと識別

- [raw/](../bench-1356/raw/)：各プロセスの全観測（ns、iteration、補助バイト数等）。正式44ファイルのみを集計する。
- [summary.csv](../bench-1356/summary.csv)：初回とウォーム値のn/中央値/p95/max/min。
- [paired.csv](../bench-1356/paired.csv)：Dの20組×4負荷のbase/W1時間、比、差、順序。
- [order.csv](../bench-1356/order.csv)：正式プロセス実行順、JST時刻、終了コード。
- [memory-regions.csv](../bench-1356/memory-regions.csv)：補足のOS予約/コミット。
- w1-source-sha256.csv / base-source-sha256.csv：パス別ソースSHA-256。source-verification.txtに測定後の再照合結果がある。
- artifact-sha256.csv：実行体と測定ソース/スクリプトのSHA-256。zig-sha256.jsonはコンパイラのハッシュである。

ソース一覧CSV自体のSHA-256（保存した一覧ファイルそのものを識別する）は以下である。

| ツリー | 一覧件数 | 一覧のSHA-256 |
|---|---:|---|
| w1 | 402 | `b4b327d47e4c0bcf60fcd1a8505ccc384f7ea7deefe5ff7b3d1a58814e323705` |
| base | 401 | `908b66426c553f03a6fb9fd870f64c62c188741f06930ddddc065ca6c57de048` |

| 実行体 | bytes | SHA-256 |
|---|---:|---|
| bin/a_false/bin/bench.exe | 1,252,352 | `c892656b5515a58ad3b9fd80342023c5f8069b386287dba332778fdd9339b2a6` |
| bin/a_true/bin/bench.exe | 1,252,352 | `742ecba35ac6e5db2018acf8661c40b0417f3fdcd10ed9f59c7c1aa6ae37434f` |
| bin/b/bin/bench.exe | 2,440,192 | `9b7f0d58bb9b189204e8c9c1e1aca4c5ee59cc2b65de139543777343e3b80e11` |
| bin/base/bin/bench.exe | 2,369,024 | `c7711adf68ebf3501679a13d5dea1b35900dc1fc9ea348ec2e9c454a13fd167e` |
| bin/c/bin/bench.exe | 2,381,312 | `42246936d399f46c567be3278062198d534554599af558c0a08f1b88ebc9db1c` |
| bin/d/bin/bench.exe | 2,381,312 | `a5e8d25e4ff7d087c3c72b88454a9f528ab5b69bb83143945c86dcfe1698c014` |
| bin/memory/bin/bench.exe | 1,250,304 | `f94314471ce1b3421436201507daf81aac2d376af1f73aa385fdd33f0310b363` |

## 4. 保存物と検証

生データは[bench-1356/raw](../bench-1356/raw/)の44個のCSVである。nsが計時値、auxはバイト数または確認間隔である。ウォームアップを含む全行を残す。集計は[summary.csv](../bench-1356/summary.csv)、Dの組ごとの比較は[paired.csv](../bench-1356/paired.csv)、実行順は[order.csv](../bench-1356/order.csv)である。実行体と測定用ソースのSHA-256は[artifact-sha256.csv](../bench-1356/artifact-sha256.csv)、VMソースの各ファイルのSHA-256はw1-source-sha256.csv/base-source-sha256.csvである。後者はsrc/includeの全ファイルを含む保守的な識別であり、リンクされたファイルだけの一覧ではない。

準備中にはPowerShellの-D引数の渡し方、Writer.context、埋込licenseのimport、CORE-MATHリンク、Zig 0.17.1の型情報APIに起因するビルド失敗があった。測定用コード・専用buildだけを直した。予備実行のDを中断して、builtin xtを非builtin定数xtに変更し、解釈行へSHORTを加えた。中断時のデータはexcluded-preflightに保存し、正式集計へ混ぜていない。

正式run.ps1、analyze.py、verify_sources.py、verify_data.pyは終了コード0であった。VMソースの再照合はW1の402ファイル・baseの401ファイルすべて一致した。baseのgit status --shortは出力なしであり、HEADは上記のままである。新規Zig 4ファイルのzig fmt --check、git diff --checkは終了コード0であった。後者は既存の追跡変更に対するCRLF変換予告を出したが、空白エラーはなかった。新規ファイルは別途末尾空白・残存プレースホルダー・データ整合性を確認した。

新規成果物はbench-1356配下と本報告書だけである。開始時から存在した追跡変更・試作ファイルへ編集を加えていない。git commit・branch・tag・pushおよびtqueの参照/変更は行っていない。

## 5. 解釈・未確認事項・1357への判断材料

取消しはPUREの中央値4.650 µsに対してp95 54.900 µs、観測最大91.600 µsであり、上側のばらつきが大きい。NATIVEは中央値919.500 µs、p95 1,722.100 µs、観測最大2,031.400 µsであった。1024 Opは時間の上限ではなく、FILLの入力サイズを増やしても同じ時間内に戻るとはいえない。※推測です：要求スレッド/VMスレッドのスケジューリング、割込み、要求が置かれたpoll周期内の位相、native処理量がばらつきの候補である。ETW等のスケジューラログは採取しておらず、原因を特定していない。

VM作成のゼロ化省略ありとなしではallocate+init中央値が94.000 µsと8,089.550 µsであったが、OS領域の予約/コミット総量は同じであった。already_zero=trueは未接触ページの初回ページフォールトを最初の使用時へ先送りする。初期化直後のWorkingSetだけをworkerのメモリ予算に使わない。Snapshotもfresh復元317.700 µsと通常restore 8,295.950 µsを区別する必要がある。後者は毎反復で新規作成し、イメージ復元と一部の書換えだけを行った対象の値であり、memoryの大部分の初回ページフォールト費用を含む。※推測です：全memory消去とページの初回書込みが、通常restoreとfalse確保の共通する主な費用である。内部処理ごとの時間とページフォールト数は分離測定していないため、寄与率は断定しない。※推測です：その場で継続して再利用するVMでは、ページの接触・常駐状態によってrestore費用が異なる可能性がある。1357の追加測定候補として、対象memoryを事前に温めた復元と、新規対象の復元の比較を挙げる。

false確保と通常restoreにも中央値の約1.9倍の観測最大値があった。※推測です：ページフォールト、OSのメモリ管理、割込みや周波数変動が候補である。原因を裏付けるトレースはない。今回の標本から保証上限を導かない。

Dの中央値同士の差はCALC -2.89%、XT +2.79%、DEFERRED +3.23%、INTERPRET -1.23%であった。今回の固定した実行体の組合せでは差の向きが負荷ごとに一貫しており、負荷ごとの両側符号検定ではいずれも5%水準で、偶然のばらつきだけでは説明しにくい差である。ただし、入口を1呼出しに各1回しか通らないCALCでも約−2.9%と同程度に動いている。このため、差を入口の判定に帰することはできず、コード・Stateの配置の違いと区別できていない。この結果を「ゼロ費用」とも「退行」とも呼ばない。※推測です：配置・最適化の変化、スケジューリング・boost等も差に寄与し得る。1355の命令列比較と実利用負荷に加え、配置の影響の下限を見積もる対照実験を1357の判断事項・追加測定候補とする。具体的には、入口の判定をコンパイル時に除いたW1とのA/A'比較、およびリンク順・パディングを変えた複数の実行体の比較である。これらは候補であり、今回実行していない。

本測定は単一VMの逐次操作と、1件の取消しを要求する補助スレッドの範囲である。TaskManager・投入キュー・入力/結果コピー・通知/回収・並行worker数・メイン入力/描画の応答は未測定である。1353/1354が指摘した全State再利用・共有状態・ホスト資源の隔離を証明していない。Linux/WSL/macOS、別CPU・電源条件、長時間連続運転、実アプリケーション負荷も未確認である。

1357では利用例ごとに起動頻度・Snapshotの取得頻度と再利用・許容する取消し時間・nativeの最大処理量・worker数/メモリ上限を先に定める必要がある。今回の中央値・p95・観測最大値を閾値として逆採用しない。1024 Opのままにするか、nativeの処理量制限や内部取消し点を設けるか、VMを毎回作るか、監査済みの再利用へ進めるかを比較する資料とする。Dの差は1355の生成コード比較と併せて評価する。

# タスク1384：W1の通常経路への影響を減らす改良

作成日：2026-11-24。W1からの改良内容と静的生成コードの比較報告である。

## 1. 結論と境界

通常経路へ命令ごとの定期取消し確認を追加していない。workerのOp確認と1024 Opごとのatomic読取りは、引き続きworker=trueの実体だけに置いた。

executeOperationsの実行時worker判定を除去し、runAsWorkerから語実行・再帰・compiled loopへcomptimeのworker引数を渡す構造とした。Stateに追加していたworker_cancellationフィールドを除き、実行スレッドのスタック上のコンテキストへ退避した。通常の数値THROWの表から内部取消しをコンパイル時に除き、実行時の除外分岐を削除した。

**executeWordの再入用判定と、通常CATCHの取消し非捕捉判定は残る。** 通常VMのCATCH内のcallbackがrunAsWorkerを呼び、戻った内部取消しを同じRuntimeErrorで伝える既存契約を維持するためである。すべての通常経路の追加判定を除去したとの結論ではない。機械語の完全一致や、時間費用の合格も主張しない。

基準はD:/tmp/forthz-base、実装はD:/tmp/forthz-1352であり、HEADはいずれも35523f676836134c4fbaed19e3d01d2a23ec2a92である。既存の未コミットW1を開始点とした。他タスクの変更は保持した。baseのソースは変更していない。bench-1356/とzig-out/1355/は読み取りだけである。コミット・タグ・ブランチ作成・push・tque変更は行っていない。

根拠はCORE_EXTENSION_DESIGN_DECISIONS.mdの利用者決定、TASK_CONTROL_METHOD_DECISION.md 8節、TASK_CONTROL_DETAILED_PLAN.md 4.1・9節、TASK_CONTROL_AUDIT_REENTRY.md、TASK_CONTROL_AUDIT_ALLOWED_SET.md、およびPROTO_1352〜1356である。TASK_CONTROL_STATE_MACHINE.mdは確認時点で存在しなかった。Snapshot・TaskManager・投入検査・回収機構は本タスクで実装していない。公開Forth語と公開エラー値は追加・確定していない。

## 2. 変更ファイルと既存ファイルを変えた理由

以下は開始時のW1から今回追加した変更である。git diff全体には開始時からの他タスクの変更も含まれる。

| ファイル | 内容・理由 |
|---|---|
| src/core/task_context.zig（新規） | threadlocalの現在スコープと、VM識別・トークン・親スコープを持つスタック上のContextを実装した。Stateのフィールドを増やさず、再入・別VMの入れ子・復元を扱うためである。 |
| src/core/task_policy.zig（新規） | W1のworker境界拒否を移し、決定済みのDO系拒否を加えた。数値THROW用の表をコンパイル時に生成する。完全な許可集合の実装ではない。 |
| src/tests/task_control_1384_test.zig（新規） | 直接executeWordするnative再入、wordInLoopのfallbackと別名、スコープの入れ子・スレッド分離、DO系拒否と、レビュー修正で追加した取消し済みの非colon入口を検査する計5試験を追加した。 |
| src/forth.zig | runAsWorker、executeWord、executeColon、executeOperationsMode、wordInLoopとその呼出し箇所へcomptimeの実行モードを通した。既存の実行器本体を二重に手書きせず、通常処理との意味のずれを避けるためである。Stateの追加フィールドを除去し、workerCancellation()へ置換した。 |
| src/core/exception_registry.zig | 診断callbackをworkerで禁止する既存判定をworkerCancellation()へ置換した。取消しを握り潰すcallbackを再び有効にしないためである。 |
| src/core/words_system.zig | 数値THROWの参照表をnumeric_throw_codesへ変更し、ループ内のTaskCancelled除外を削除した。CatchContextの非捕捉条件は維持した。 |
| src/tests/task_control_w1_test.zig | 12件の既存W1試験のフィールド参照をworkerCancellation()へ変更した。試験の要求とwatchdogは維持した。 |
| src/forth_test.zig | 新規試験を1行で登録した。 |
| 本報告書（新規） | 改良内容、静的比較、試験、残る判断事項を記録した。 |

defs.zig、error_reporting.zigにあるW1の内部TaskCancelledと暫定診断値-282は今回変更していない。数値-282からTaskCancelledを生成しないことは維持した。新しい第三者コード・依存ライブラリは取り込んでいない。

## 3. 設計上の選択

### 3.1 専用入口と再入

runAsWorkerはContextを設定し、取消し要求を入口で確認してからexecuteWordMode(true)へ直接入る。要求済みならnative（builtin）やデータ語も実行せずTaskCancelledを返す。worker専用入口だけの確認であり、通常経路には加えない。deferにより正常終了・拒否・取消し・他エラーのすべてで親コンテキストへ戻す。forward・synonym・colonの実行も同じcomptimeモードを引き継ぐ。wordInLoopの一般語fallbackはworkerならexecuteWordMode(true)を直接呼ぶ。executeOperationsModeの選択もcomptimeであり、通常入口でトークンを調べない。workerはcountedを選ばない。

native callbackが既存のexecuteWordを呼ぶ経路だけは、実行時に当該VMのworkerコンテキストを検索する。ここを無条件にplainへ固定するとnative再入が通常経路へ抜けるため、判定を残した。レビュー修正後は通常側のwordInLoopもexecuteWordMode(false)を直接呼ぶ。TLSでモードを分配する処理はnative callbackが使う公開内部入口executeWordに残す。Forthへの公開語を作ったという意味ではない。

コンテキストの検索は現在スコープから親へたどり、VMのアドレスで照合する。異なるVMを入れ子にしても外側VMの印を失わず、同じVMの入れ子では最も内側のトークンを選ぶ。スコープの設定と復元は所有スレッドだけで行う。別スレッドの要求側はCancellation.request()だけを呼び、ContextとStateへ触れない。スコープを別スレッドへ移送するAPIではなく、同じStateの同時実行を許可するものでもない。トークンとVMは同期呼出しが戻るまで呼出し元が保持する。

Context.leave()はstd.debug.assert(current == self)で入れ子を検査する。ReleaseFastではassertが消え、入れ子が崩れても検出せずself.previousをcurrentへ代入する。所有スレッドでenterの逆順に一度だけleaveすることが必須契約であり、違反時のContext連鎖の有効性や安全な回復は保証しない。今回の試験は正しい入れ子の復元を対象とする。

### 3.2 Stateの配置

Zig 0.17.1に同梱された公式言語リファレンスdoc/langref.htmlのstruct節（4124〜4125行）は、通常structのフィールド順序とサイズを保証せず、フィールドのABI alignmentを保証すると説明する。extern structはC ABIの配置を保証する別の型である。確認したローカル資料はC:/Users/n_fuk/AppData/Local/Microsoft/WinGet/Packages/zig.zig_Microsoft.Winget.Source_8wekyb3d8bbwe/zig-x86_64-windows-0.17.1/doc/langref.htmlである。

このため、フィールドを宣言の末尾へ移すだけでは既存フィールドのオフセット維持を保証できない。State全体のextern化も、内部型全体のABI変更を伴う範囲拡大となるため採らなかった。既存Writer等の別の値へポインタを埋め込む案も、その値の配置と契約を変更するため採らなかった。Stateからフィールドを完全に除き、threadlocalには現在Contextへのポインタ1本、各同期呼出しのスタックにはContextを置く方法を採った。通常structであるContext自身の配置には固定ABIを要求しない。

Windows fast/smallのPDB型情報では、baseと改良後のStateは双方6,777,936 byteであり、PDBで取得した173フィールドの名前とオフセットが一致した。ソース上のStateはbase・現在とも176フィールドであり、名前と宣言順も一致する。-Ddebug=falseで大きさ0となるcode_lines・code_columns・executionの3フィールドは、このPDBには現れない。旧W1はサイズこそ同じであったが、内部オフセットが変わっていた。これは確認した構成の観測結果であり、将来のZig版や他構成での固定配置を仕様化するものではない。

| Stateフィールド | base | 旧W1 | 改良後（CLI・補助比較） |
|---|---:|---:|---:|
| words | 0x163dd8 | 0xfd0 | 0x163dd8 |
| code | 0x16e8 | 0x301aa8 | 0x16e8 |
| data_depth | 0x1031b0 | 0x4033c0 | 0x1031b0 |
| backtrace_suppression | 0x1484b0 | 0x4486a0 | 0x1484b0 |
| frame_depth | 0x163b40 | 0x463d58 | 0x163b40 |
| catch_depth | 0x163b58 | 0x463d70 | 0x163b58 |
| halted | 0x550b44 | 0x550b4c | 0x550b44 |
| worker_cancellation | なし | 0x463d80 | なし |


### 3.3 CATCH・THROWと削除しなかった判定

worker内のCATCH/THROWは従来どおり拒否する。ただし、通常VMの解釈CATCHやcompiled CATCHの内側でnative callbackがrunAsWorkerを呼ぶW1の経路は維持する。runAsWorkerが戻った時点ではコンテキストは復元済みであり、外側のplain回復器にもTaskCancelledが届く。

plainの非捕捉判定だけをcomptime(worker)で除くと、この経路で取消しを通常例外として捕捉する。判定をCatchContextだけへ移す案では、その前にresumeCatchがフレーム・locals等を書き換え、従来の非捕捉時の巻戻し・診断契約を変える。既存のQuit/StepLimitを搬送値へ流用する案では、外側まで伝わった時の取消しと本来のQuit/StepLimitを区別し直す新しい契約が必要となる。これらは採らなかった。

そのためrunOperationsとCatchContext.handleErrorのTaskCancelled非捕捉判定は保持した。通常の回復処理からこの差分を完全に除く改良は実施していない。worker専用の回復器を作るだけでは外側plain CATCHの問題は解消しない。削除には外側callbackとエラー伝播の契約変更が必要であり、本タスクで推測に基づいて変更しない。

一方、数値THROWで必要だったTaskCancelled除外は、task_policy.numeric_throw_codesを生成するコンパイル時処理へ移した。実行時には取消しを含まない表だけを走査する。-282は通常のThrownとして従来どおり捕捉できる。TaskCancelledの診断に用いるW1の暫定値を公開仕様として承認したものではない。

## 4. 静的生成コードの比較

4.2・4.3の表と数値はレビュー修正前の保存結果である。レビュー修正後の再比較は4.4節に記す。

### 4.1 条件と手順

Zig 0.17.1、LLVM objdump/pdbutil 22.1.8を用いた。1355と同じx86_64-windows / x86_64-linux、ReleaseFast / ReleaseSmall、-Ddebug=false -Dstrip=false、全語群と容量の既定値である。LinuxもWindowsの同じZigでクロスビルドした。-j2はビルドの同時ジョブ数だけを制限する。WSL UbuntuのGNU objdump 2.46でも両ツリー・両最適化の4 ELFを-h -d -Mintelで出力した。fileは4件ともELF64 x86-64、statically linked、with debug_info、not strippedと判定した。実行体は起動していない。

```powershell
# 各ツリーをカレントにしてtarget/optimizeの4組を実行する。
$env:ZIG_GLOBAL_CACHE_DIR = "$PWD/.zig-cache/1355-global"
$env:ZIG_LOCAL_CACHE_DIR = "$PWD/.zig-cache/1355-local"
zig build -Dtarget=x86_64-windows -Doptimize=fast -Ddebug=false -Dstrip=false --prefix zig-out/1384/windows-fast -j2 --summary failures
# windows-small、linux-fast、linux-smallも同じ指定である。
```

対象関数をWindowsはPDBのS_LPROC32、LinuxはELF symbol tableから抽出し、関数範囲をLLVMで逆アセンブルした。--source --line-numbersを指定した出力も保存した。Windowsの実体・型はPDB、Linuxの実体はELFのsymbol tableから特定した。PDBのsection 0001のoffsetへ0x140001000を足してPEの開始位置を求める。runOperationsLoopは独立シンボルとして残らず、runOperations内のインライン本体として比較する。

正規化では命令先頭のアドレス・表示シンボルを除き、直接呼出し先を名前、関数内分岐先をLOCAL+offset、RIP相対データ変位をDATAとした。State・スタックの変位、レジスタ、通常の即値は残した。大きなbitset即値も残した。補助的なshape比較ではLOCAL位置だけを隠したが、これによって分岐先の意味的同一性を証明したとは扱わない。rawとソース対応を判断根拠とする。

旧W1は変更禁止のzig-out/1355/analysis/results.jsonと生の出力を使用した。今回再ビルドしたbaseの4実行体は、1355のbaseとSHA-256まで一致した。開始時に保存したW1のforth.zig、words_system.zig、exception_registry.zigのSHA-256も1355の保存値と一致した。旧W1と改良後では到達する関数集合も変わるため、以下のCLI比較と両入口を残した補助比較を分ける。

### 4.2 指定されたCLIビルドの比較

今回のCLIではrunAsWorkerの呼出し元がない。threadlocalの現在スコープへ書き込む経路も到達しない構成で、worker入口とexecuteWordの実行時検索は最適化後の実体に残らなかった。executeWordModeのplain本体が残る。**この除去結果を、workerが組み込まれた場合にも判定がゼロになる証拠にはしない。**

| 構成 | 対象 | base byte / 命令行 | 旧W1 byte / 命令行 | 改良後CLI byte / 命令行 |
|---|---|---:|---:|---:|
| windows-fast | executeWord | 2,515 / 549 | 2,729 / 591 | 2,515 / 549 |
| windows-fast | executeOperations | inline / 除去 | inline / 除去 | inline / 除去 |
| windows-fast | runOperations | 11,295 / 2,157 | 10,051 / 1,906 | 11,308 / 2,159 |
| windows-fast | executeBuiltin | 21,033 / 4,433 | 21,033 / 4,433 | 21,033 / 4,433 |
| windows-small | executeWord | 1,323 / 329 | 1,510 / 357 | 1,323 / 329 |
| windows-small | executeOperations | 86 / 25 | 116 / 33 | 86 / 25 |
| windows-small | runOperations | 8,675 / 1,768 | 7,995 / 1,604 | 8,690 / 1,770 |
| windows-small | executeBuiltin | 119,323 / 24,425 | 119,331 / 24,427 | 119,323 / 24,425 |
| linux-fast | executeWord | 2,474 / 538 | 2,596 / 565 | 2,474 / 538 |
| linux-fast | executeOperations | inline / 除去 | inline / 除去 | inline / 除去 |
| linux-fast | runOperations | 10,865 / 2,177 | 11,051 / 2,202 | 10,868 / 2,178 |
| linux-fast | executeBuiltin | 21,157 / 4,429 | 21,157 / 4,429 | 21,157 / 4,429 |
| linux-small | executeWord | 1,280 / 313 | 1,437 / 348 | 1,280 / 313 |
| linux-small | executeOperations | 86 / 25 | 115 / 33 | 86 / 25 |
| linux-small | runOperations | 8,172 / 1,728 | 8,032 / 1,693 | 8,165 / 1,729 |
| linux-small | executeBuiltin | 118,434 / 24,741 | 118,434 / 24,742 | 118,434 / 24,741 |


単位はbyte / 静的命令行数であり、動的実行回数や速度ではない。executeWord欄は改良後のexecuteWordMode(false)本体、executeOperations欄はexecuteOperationsMode(false)である。FastのexecuteOperationsはexecuteWord内へインライン化される。

| 構成 | base全体 | 旧W1全体 | 改良後CLI全体 | base .text | 旧W1 .text | 改良後CLI .text |
|---|---:|---:|---:|---:|---:|---:|
| windows-fast | 2447360 | 2461184 | 2448384 | 1429334 | 1442502 | 1429398 |
| windows-small | 1908224 | 1918464 | 1909760 | 912358 | 921830 | 912390 |
| linux-fast | 10330664 | 10408264 | 10338168 | 1282131 | 1295187 | 1282195 |
| linux-small | 7133424 | 7195096 | 7141488 | 818069 | 827765 | 818101 |


全体サイズはPDBを除く実行体のファイル長、.textはsectionの内容長である。デバッグ情報・他の共有関数・データ・alignmentも全体差へ含まれる。plain関数単独の費用と混同しない。

CLIではexecuteWordのplain本体は4組とも正規化後にbaseと一致し、SmallのexecuteOperationsも一致した。FastのexecuteOperationsはインライン化され、その部分を含むexecuteWordが一致した。executeBuiltinはFastの2組で一致し、Smallの2組では内部エラー番号を返す即値が2箇所変わった。Windows Smallは0x4c→0x4dと0x36→0x37、Linux Smallは0x6e→0x6fと0x50→0x51である。数値THROWの取消し除外ループは残っていない。ここでいう一致は、上記のアドレス正規化を行った命令列の一致に限る。

plain runOperationsは4組とも不変ではない。baseとの差はWindows Fast +13 byte / +2命令行、Windows Small +15 / +2、Linux Fast +3 / +1、Linux Small -7 / +1である。Windows Fastには次の回復条件の変更がある。

```asm
; base: Quit / StepLimitの2値判定
mov eax, r14d
and eax, 0xffdf
cmp ax, 0x15
je NON_CATCHABLE
; 改良後CLI: TaskCancelledを含めた3値のbitset判定
cmp r14w, 0x36
ja CHECK_CATCH_DEPTH
movzx eax, r14w
movabs rcx, 0x60000000200000
bt rcx, rax
jb NON_CATCHABLE
```

これはOpごとの取消し要求の読取りではなく、失敗後の回復経路の判定である。さらにLinux Fastでは保存するentry_frames・entry_catches・suppressionのスタック位置と命令順、Smallではレジスタ・スタック局所値・分岐位置に差がある。命令の配置が変わったことでLOCAL分岐先にも差が広がるため、diffの行数を追加処理の件数とみなさない。旧W1からState変位と二つの実行時入口判定を除いたCLIではあるが、plain回復器をbaseと同一にしたものではない。

### 4.3 両入口を到達可能にした補助比較

CLIの最適化除去だけを成果としないため、ビルド出力配下にbaseと改良後のソースコピーを置き、同じ設定で追加の静的比較を行った。baseのソース自体には変更していない。コピーのmainだけを、plainEntryとworkerEntryのアドレスをdoNotOptimizeAwayへ渡すハーネスへ置き換えた。plainEntryはexecuteWord、改良後のworkerEntryはrunAsWorkerを呼ぶ。base側のworkerEntryはexecuteWordを呼ぶ対照である。ハーネスは実行していない。

これは1355と同じCLIの比較に追加した確認であり、CLIの数値と混ぜない。初回の補助ハーネスはexport宣言だけを用い、Linuxの最適化後に両入口が残らなかったため、最終版では両方のアドレスを保持した。最終表は保持後に再ビルドした結果だけである。

| 構成 | base executeWord | 改良後の分配器 / plain本体 | base / 改良後 executeOperations | base / 改良後 plain runOperations | 改良後 worker runOperations | base / 改良後 executeBuiltin |
|---|---:|---:|---:|---:|---:|---:|
| windows-fast | 2,515 | 81 / 1,914 | 両方inline | 11,295 / 10,051 | 12,049 | 21,081 / 21,081 |
| windows-small | 1,323 | 56 / 940 | 86 / 86 | 8,675 / 7,995 | 8,483 | 119,846 / 119,846 |
| linux-fast | 2,474 | 65 / 1,908 | 両方inline | 10,865 / 11,051 | 11,666 | 21,205 / 21,205 |
| linux-small | 1,280 | 45 / 935 | 86 / 86 | 8,172 / 8,032 | 8,461 | 118,917 / 118,917 |


上表はそれぞれの関数のbyte数であり、分配器とplain本体を足した値を1回の呼出し費用へ換算しない。SmallではworkerCancellationが別関数としてWindows 57 byte、Linux 47 byte残る。FastではplainEntryにも検索処理がインライン化されるため、executeWordのサイズだけで通常入口全体のサイズを表したものでもない。

workerEntryから呼ぶ語実体と、executeWordのnull側から呼ぶ実体を追い、さらにexecuteOperationsからrunOperationsへのcallを追ってモードを識別した。関数番号の大小を根拠にしていない。対応は以下のとおりである。

| 構成 | plain mode / worker mode | plain loop / worker loop |
|---|---|---|
| windows-fast | executeWordMode__func_10 / executeWordMode__func_9 | runOperations__func_13 / runOperations__func_1466 |
| windows-small | executeWordMode__func_10 / executeWordMode__func_9 | runOperations__func_13 / runOperations__func_1466 |
| linux-fast | executeWordMode__func_29 / executeWordMode__func_28 | runOperations__func_36 / runOperations__func_35 |
| linux-small | executeWordMode__func_29 / executeWordMode__func_28 | runOperations__func_36 / runOperations__func_35 |

補助比較でもSmallのplain executeOperationsはbaseとアドレス正規化後に一致し、worker判定はない。executeWordのplain本体は再帰先・関数境界・インライン化が変わり、4組ともbaseと異なる。分配器には当該VMのコンテキストを探すTLS読取り、比較・分岐、親リンク走査が残る。

plain runOperationsは4組ともbaseと異なる。レジスタ・スタック・ブロック配置に加え、取消しを含む回復条件が残る。サイズは1355の旧W1 plain実体と4組とも一致したが、Stateの参照変位はbaseへ戻っているため、旧W1の命令列と同じという意味ではない。

executeBuiltinはFastの2組で正規化後に一致した。Smallでは同じサイズ・命令行数であるが、エラー番号の即値2箇所とexecuteWordを呼ぶ14箇所の行先が異なる。後者は従来の語本体から今回の分配器へ進む変更であり、単にシンボル名を同一視して隠していない。下位関数まで含む通常経路全体が不変であるという証拠ではない。

4組すべてでplain runOperationsにTLSセグメント参照と0x400のpoll再設定はなかった。workerの4実体には1024 Opの再設定とトークンのbyte読取りがあった。FastはTLS検索をインライン化し、SmallはworkerCancellationをcallした後でトークンを読む。Windows Fastのworkerには次の列がある。

```asm
; workerだけのpoll部分（周囲に残カウンター判定とContext検索がある）
mov rax, qword ptr [rcx + 0x8] ; Context.token
movzx eax, byte ptr [rax]     ; Cancellation.requestedのacquire load
mov r14d, 0x400
test al, 0x1
jne CANCELLED
```

x86_64ではacquire loadが通常のloadになるため、lock命令がないことだけを非混入の根拠にはしていない。ソースのcomptime条件、呼出しによる実体識別、ループ先頭のraw命令列を合わせた確認である。native callbackから公開executeWordへ再入する際の検索と、Opごとの定期確認は別である。通常ループのfallbackでの検索はレビュー修正で除いた。

### 4.4 通常経路の残る差分一覧

1. workerを組み込む構成のexecuteWordにはthreadlocalから当該VMのスコープを検索する入口が残る。旧W1のStateフィールドのloadとは異なり、入れ子では親リンクの検索も行う。時間費用の優劣は測定していない。
2. executeWordMode(false)を別実体としたため、再帰先・呼出し境界・インライン化の選択が変わる。executeOperationsの実行時worker判定は除去したが、両入口が残る構成の語実行全体がbaseと同じ命令列になるとはしない。
3. Stateの追加フィールドによる参照変位の差は、確認したWindowsの配置では解消した。TLSの存在とその参照は新しい差分である。
4. runOperationsとCatchContextのTaskCancelled非捕捉判定が残る。回復条件のbitset化、分岐位置・レジスタ・スタック局所値の割当ての変化も静的に観測した。回復時だけの判定とOpごとの定期確認を区別する。
5. 数値THROWの実行時TaskCancelled除外分岐は削除した。通常エラー表・内部エラー番号の割当てや共有関数の配置の影響までゼロになるとはしない。
6. executeBuiltinにworker印の入口判定は追加していない。下位関数のインライン化、エラー番号、呼出し先、データ位置による生成コード差は別に残り得る。命令列の一致と参照データ全体の一致は区別する。
7. exception_registry.zigのwriteMessageは診断レジストリをたどるエラーを報告するたびにworkerCancellation()でTLSを検索する。エラー報告経路だけの追加である。
8. error_reporting.zigのメッセージ選択にはerror.TaskCancelledとの比較が1つ増えている。これもエラー報告経路だけの追加である。
9. workerの確認カウンター、atomic読取り、checkOpはworker=trueのcomptimeブロックだけにある。通常実体へ命令ごとの定期確認を追加する変更はない。workerを残す補助比較でもplain/workerを区別して確認した。

レビュー修正後、1355と同じtarget・最適化・debug/strip条件でCLIを4組再ビルドし、保存済みbaseを再解析した。4.2節の関数byte数・命令行数と正規化比較結果は今回も同じである。executeWordのplain本体は4組で一致し、SmallのexecuteOperationsも一致した。runOperationsは4組とも一致せず、通常回復条件・レジスタ・スタック割当て・分岐配置の差が残る。FastのexecuteBuiltinは一致し、Smallは4.2節に記した内部エラー番号の2即値が異なる。

両入口を保持する補助構成もbaseコピー・現在コピーを各4組ビルドし直した。下表はbase / 現在のbyte数である。通常入口の分配器はWindows Fast 81、Small 56、Linux Fast 65、Small 45 byteであり、4.3節のサイズと同じである。plain本体・runOperationsはbaseと正規化後も一致せず、サイズが同じことから命令列の一致を導かない。

| 構成 | executeWordのplain本体（base / 現在） | plain runOperations（base / 現在） |
|---|---:|---:|
| windows-fast | 2515 / 1914 | 11295 / 10051 |
| windows-small | 1323 / 940 | 8675 / 7995 |
| linux-fast | 2474 / 1908 | 10865 / 11051 |
| linux-small | 1280 / 935 | 8172 / 8032 |

plain runOperationsから呼ばれるwordInLoopを呼出し先アドレスで追跡したところ、4組すべてでfallbackはexecuteWordMode(false)を直接呼び、そのwordInLoopにfs:/gs:のTLS参照もworkerCancellationへの呼出しもなかった。WindowsではwordInLoop__func_20、Linuxではforth.State.wordInLoop__func_39である。公開executeWordへの分配器を経由しないことを確認した（review-fallback-evidence.txt）。workerのpollは別実体に残り、通常ループへ定期取消し確認を加えていない。StateのPDBサイズ6,777,936 byteと取得173フィールドのオフセット一致も全Windows CLI・補助構成で再確認した。ソースの176フィールドの名前・順序一致はreview-state-source.jsonに保存した。

### 4.5 レビュー指摘の照合

指摘1〜5はいずれもソースと整合しており、誤りとして退けた指摘はない。今回のソース変更はsrc/forth.zigの2行と、src/tests/task_control_1384_test.zigの試験修正・追加だけである。既存ファイルの2行は、通常ループの不要なTLS検索を除くためと、非colon入口の実行前取消しを成立させるために変更した。診断経路とContext.leave()のコードは変更していない。

## 5. 試験と実行結果

PowerShellから最終ソースで次を実行し、すべて終了コード0となった。3試験構成はいずれも失敗診断を出さなかった。試験は1352の全12件と1384の全5件を含む。試験キャッシュは作業ツリー内の.zig-cache/1384-globalと1384-localを使用した。

| コマンド・確認 | 結果 |
|---|---|
| zig build test -j2 --summary failures | exit 0 |
| zig build test -Ddebug=false -j2 --summary failures | exit 0 |
| zig build test -Ddebug=false -Dfloat=false -Dgraphics=false -Daudio=false -Dimage=false -Dextension=false -j2 --summary failures | exit 0 |
| 指定条件のCLI再ビルド（改良後 × 4組） | 4件すべてexit 0。baseは保存済み出力を再解析した。 |
| 両入口を保持した補助ビルド（base・改良後 × 4組） | 8件すべてexit 0 |
| 1384で対象としたZigファイル8件のzig fmt --check | exit 0 |
| 追加確認：zig fmt --check build.zig src | exit 1。対象外の285ファイルを列挙した。範囲外の一括整形は行っていない。 |
| git diff --check | exit 0。既存ファイルのLF/CRLF変換予告だけが出た。 |


全体fmtの追加確認はreview-fmt.logに保存した。列挙されたファイルを作業ツリー内の別コピーでLFへ統一して確認しても23ファイルが残り、改行だけが理由であるとは扱わない。全体整形を行うかは、本タスクの小さな差分という制約とは別の判断が必要である。対象8件のfmt合格とリポジトリ全体のfmt合格を区別する。

既存W1の12試験を維持し、新規5試験を登録した。debug=falseでは既存のdebug専用counted試験がSkipZigTestとなる。その他の既存OS・語群別skipも、実行済みの合格へ数え直していない。--summary failuresは成功時に件数を出さないため、終了コードと失敗診断の有無を結果とする。

W1はBEGIN AGAIN、入れ子colon、inline/specialize、既存worker内の再入、解釈・compiledの外側CATCH、保留済み取消し、動的実行・例外・PAD拒否、診断callback遮断、数値-282 THROW/FAST-THROW、正常帰還・失敗後のコンテキスト復元を検査する。既存watchdogはハング時に失敗させる用途として維持し、速度や取消し時間の標本は収集していない。

レビュー修正後のsynonym試験は、.call ALIASからコロン定義BADへ進み、その中のPADがworkerで拒否されること、および同じSLOTがplainで実行されスタックへ1値を積むことを検査する。別コピーでexecuteLoopWord(true)をplainへ退行させる変異試験を実行すると、この試験だけが期待エラー不成立で失敗した（review-mutation.log）。入口の取消し確認を削除する別の変異では、追加の取消し済み入口試験が失敗した（review-mutation-entry.log）。どちらも意図した検出結果であり、本体ソースには変異を適用していない。取消し済み入口試験はDUPとCONSTANTを使い、スタックが変わらずContextが復元されることを確認する。

追加試験はnative callbackからrunAsWorkerを呼び直さずにexecuteWordへ再入した際の取消しを確認する。スコープ試験は別VMキー・同一VMの別トークンの入れ子と、親スレッドの印が子スレッドへ引き継がれないことを確認する。後者はContextの試験であり、複数の本番VMが同時に動作する隔離試験ではない。DO系は16種類のOpと基本10種類のBuiltinを、引数を消費する前に拒否する試験を行う。完全な許可表と全operand検査は後続1360の範囲である。

## 6. 未確認事項と利用者が判断する事項

- State配置を維持するために採ったthreadlocalとスタックContextを受け入れるか。通常入口に残る検索、入れ子時の親検索、所有スレッドで実行する契約、両経路を残した際のコードサイズを判断材料とする。
- executeWordの再入用判定とTaskCancelledの通常CATCH非捕捉判定を残した改良を受け入れるか。完全削除が必要なら、外側callbackからのworker起動と取消し伝播を別契約として再設計する必要がある。
- CLIだけではworker経路が除去されるため、補助比較の差分も含めて判断する。サイズの増減から速度改善・退行・費用ゼロを推定しない。追加の速度・時間測定は行っていない。
- Linuxはクロスビルドと静的生成コードの確認までである。Linuxでの実行試験、macOS、ReleaseSafe、strip=true、他CPU・他Zig版は未確認である。
- 新規VM＋Storage.allocate/State.initを基準とする決定を変更していない。全State再利用、Snapshot失効・寿命、複数workerとメインUIの並行隔離、native内部の停止上限、終端競合、回収の実装・受け入れは本タスクの証拠に含まれない。
- bench-1356/main.zigは旧フィールドworker_cancellationの型・値を直接参照するため、改良後のAPIとは互換でない。指定どおり変更も実行もしていない。将来この旧ハーネスを使う場合の更新は別作業である。

方式の確定・公開、-282の公開採用、取消し間隔やメモリ・時間の合格閾値は決定していない。必須条件を維持したことと、上記の残る差分を利用者が受け入れることは別の判断である。

## 7. 証拠と最終Git状態

主要な証拠はzig-out/1384/以下に置いた。static-build.ps1、prepare-reachable.py、reachable-build.ps1がビルド手順、analyze.py、analyze-reachable.py、compare.py、compare-reachable.py、layout.pyが静的解析の補助である。analysis/に生のasm・ソース行付きasm・symbol・型情報・正規化差分・関数集計を保存する。baseの既存ビルド出力だけはbase/zig-out/1384/にある。今回のレビュー修正ではbaseを再ビルドせず、その保存済み出力を読み取った。補助比較用のbaseコピーは本worktree内にある。analysis-initial/は数値THROW表をさらに改良する前の中間結果であり、最終結果とは区別する。

開始時の差分と状態はzig-out/1384/start.patch、start.status、W1のforth.zigはforth-before.zigに保存した。試験ログ、ビルド結果、最終ハッシュ、最終状態も同ディレクトリに保存する。レビュー修正のログはreview-接頭辞で区別する。旧final-hashes.jsonはレビュー前の記録である。1384-from-W1.patchは開始時のW1から今回の変更だけを取り出した差分である。W1未反映の作業ツリーへ単独で適用する差分ではない。現在の作業ツリーに対するgit apply --check --reverseで内容を照合した。ソースコピーもmain.zig以外の全srcファイルについて元ツリーとSHA-256で一致することを確認した。baseの全srcは1355の保存ハッシュとも一致した。

最終のgit status --shortは以下である。開始時からの変更・未追跡ファイルを含む。今回の編集対象は2節の表で区別した。baseのgit status --shortは最終確認でも空であった。

```text
 M docs/CORE_EXTENSION_DESIGN_DECISIONS.md
 M docs/CORE_EXTENSION_DETAILED_DESIGN.md
 M docs/CORE_EXTENSION_PLAN.md
 M docs/README.ja.md
 M docs/README.md
 M docs/TASK_CONTROL_PLAN.md
 M docs/WINDOWS_NATIVE_DISPLAY_VALIDATION.md
 M src/core/defs.zig
 M src/core/error_reporting.zig
 M src/core/exception_registry.zig
 M src/core/words_system.zig
 M src/forth.zig
 M src/forth_test.zig
?? bench-1356/
?? docs/TASK_CONTROL_ACCEPTANCE.md
?? docs/TASK_CONTROL_AUDIT_ALLOWED_SET.md
?? docs/TASK_CONTROL_AUDIT_REENTRY.md
?? docs/TASK_CONTROL_AUDIT_SHARED_STATE.md
?? docs/TASK_CONTROL_CONFIG_MATRIX.md
?? docs/TASK_CONTROL_DETAILED_PLAN.md
?? docs/TASK_CONTROL_IMPL_1384.md
?? docs/TASK_CONTROL_METHOD_COMPARISON.md
?? docs/TASK_CONTROL_METHOD_DECISION.md
?? docs/TASK_CONTROL_PROTO_1352.md
?? docs/TASK_CONTROL_PROTO_1353.md
?? docs/TASK_CONTROL_PROTO_1354.md
?? docs/TASK_CONTROL_PROTO_1355.md
?? docs/TASK_CONTROL_PROTO_1356.md
?? docs/TASK_CONTROL_USAGE_CONDITIONS.md
?? src/core/task_context.zig
?? src/core/task_policy.zig
?? src/tests/task_control_1384_test.zig
?? src/tests/task_control_w1_test.zig
```


# Gforth対応の引き継ぎ

更新日：2026-11-13。P00・S01・P01・P02とP03の65語（P03a/b/c）まで実装・検証完了。P04の33語まで実装・検証完了。現在は **P05a ファイル補助とパス検索（565）**。EMIT-FILE/SLURP-FID（653）を実装・検証済み、未コミット。次は残り14語（654〜656）。Windows/Linux確認はここでは行わず607に残す。

P03c was committed and pushed as `98be4f8`. P03 and task 562 are complete. Claude Code review fixes and the first 21 P04a words were committed/pushed as a6ab243. Task 631 is complete (auto), with no new concrete defect found in the final review. See [P03 review](P03_REVIEW.md). The six additional P04a edit/owned-string words were committed/pushed as 5b2c8a4. XC@+? was committed/pushed as fa2afe9 and P04a is complete. P04b $VALUE/MACRO: were committed/pushed as 33bb55a (634); the macro vocabulary/callback words (635) were committed/pushed as 6a9c4e3. Check git status and git log before resuming.

## P05a file-stream helpers (uncommitted)

Task653 implements EMIT-FILE and SLURP-FID (2/16 words in565). Seven regressions, normal/minimal tests, normal build and 29 designated-Gforth comparisons pass, including binary data, EOF/current position, Japanese filenames, nonseekable short-read stubs and cleanup on failure. See [P05 record](P05_IMPLEMENTATION.md). Source changes are uncommitted; next are654 (input/EOF3),655 (mode/listing/source-end3),656 (paths8). Keep565/548/542 incomplete; native Windows/Linux remain607.

## P04a completion

All 28 P04a words are implemented. Normal/minimal tests, 18 regressions, 672 Gforth comparisons and three Sigma-specific empty cases pass. P04a tasks 632/633/563 are complete (auto). P04b 564 and P04 547 are complete; 542 remains incomplete. See [P04 record](P04_IMPLEMENTATION.md).

## P04 review

P04 is committed/pushed through 6a9c4e3. Claude Code review task636 is complete (auto). Initial findings and an independently reproduced APPEND failure are fixed: +TO metadata preflight, allocation fallback/shrink, HERE overlap, owner commit and macro lint. Nine review regressions, normal/minimal suites, 125 affected Gforth comparisons and CLI persistence pass. Follow-up found no blocking defect. Fixes are included with the review record; check git log for their commit id. See [P04 review](P04_REVIEW.md).

## P04b macros complete

635 implements MACROS-WORDLIST, REPLACER: and .SUBSTITUTE, integrating REPLACES/SUBSTITUTE/$SUBSTITUTE with the case-sensitive dictionary. User approved recommended exception propagation and hard-coded update retention. Each occurrence executes once, including callback emissions captured by the owned/bounded APIs; nested TMP captures restore their output targets. Twelve regressions, 50 designated-Gforth comparisons (48 initial plus two review boundary cases), normal/minimal tests, normal build and CLI SAVE/two LOAD-DICTIONARY calls pass. See [P04 record](P04_IMPLEMENTATION.md), `macro_substitute.zig`, `p04b_macros_test.zig`, `.work/p04b-macros-check/`. 635/564/547 are complete (auto). Macro changes were committed/pushed as 6a9c4e3. P04 review task636 is complete; next is P05a/565. Keep 542 incomplete and native Windows/Linux checks in 607.

## P04b string values

$VALUE/MACRO: (634) now support borrowed execution, interpreted/compiled TO/+TO, typed ownership, rollback, images and repeated append. Nine regressions, normal/minimal tests, normal build, 27 Gforth comparisons and CLI save/load pass. Sources: string_values.zig and shared dynamic_strings.storeString. Image validation checks required owner metadata and length headers. Committed/pushed as 33bb55a. 635/564/547 are now complete; keep 542 incomplete. See [P04 details](P04_IMPLEMENTATION.md).

## 最初に読む資料

- [実装フェーズ](GFORTH_WORD_PHASES.md)：対象語・依存・完了条件・tque ID。
- [P00仕様](GFORTH_P00_SPEC.md)：確定した互換方針、再配置設計、比較元との差。
- [ワード分類](gforth-word-plan.tsv)：931語のA〜E分類と380語の実装先。
- [仕様索引](gforth-p00-spec-cases.tsv)：未対応380語＋既存構文4語のスタック効果と参照元。
- [実測結果](gforth-p00-runtime-cases.tsv)：比較元の470ケース。Sigmaの実装済み一覧ではない。改行を含むCSVレコードなので物理行数で数えない。
- [比較手順](../scripts/gforth-p00/README.md)、[キー定数](gforth-p00-key-constants.tsv)。
- [S01レビュー記録](S01_REVIEW.md)、[P01レビュー記録](P01_REVIEW.md)、[P02実装・検証記録](P02_IMPLEMENTATION.md)、[P02レビュー記録](P02_REVIEW.md)、[P03実装・検証記録](P03_IMPLEMENTATION.md)。

## タスク管理と次の作業

tqueで管理し、進捗モードは**auto**とする。階層はForthSigma 121 → 次のフェーズ415 → 実装計画542。542全体は未完了。

|タスク|確認した状態・次の扱い|
|---|---|
|543 P00|完了。384語・470ケースの仕様確認とレビュー済み|
|579 S01|完了。580 S01a、581 S01b、子608/609/610も完了|
|611 S01レビュー|完了。修正`2f5dad8`までpush済み|
|544 P01|完了。554 P01a、555 P01b、556 P01cの全25語が完了|
|612 P01レビュー|完了。修正`a8f06e9`までpush済み、指摘解消|
|545 P02|完了。557/558/559の全65語と検証が完了。進捗auto|
|614 P02レビュー|初回P2 1件・P3 8件と要確認事項を解消。再レビューで新たな具体的問題なし。進捗auto|
|546 P03|完了。560 P03a 44語、561 P03b 15語と永続化、562 P03c 6語が完了|
|563 P04a|完了。28語の文字列操作/Unicode|
|564 P04b / 547 P04|完了。文字列値・マクロ5語、合計33語。635は6a9c4e3でpush済み|
|548 P05 / 565 P05a|進行中。653の2語を実装・検証、未コミット。残り14語は654〜656|
|561 P03b|完了。15語の実行・型/寿命追跡と新形式保存/復元/追加を統合|
|550 P07|未着手。P01依存は解消。457を先行させる|
|457 P07先行|550配下。IS/ACTION-OF/TO/+TOの辞書登録。既存IDを使う|
|570 P07a|457と544に依存。457を飛ばさない|
|553 P10|未完了。P03〜P09の依存が残る|
|607 Windows/Linux別環境確認|未実施。553配下、544/545/560/580/581依存は解消。ここでは実施しない。既存537〜540と連携|

440は削除済みで再作成しない。完了済み417を再開しない。582はアセンブラー方針の別途検討、583はTRY系の保留D、584はGforth固有ブロック拡張9語の保留D。これらを自動的に今回の実装対象へ加えない。

P03bは15語の実行・型/寿命追跡と、617〜630の新形式保存/復元/追加まで完了。後続では生セルの数値をアドレスとして推測せず、既存の型/寿命追跡を維持する。不明な仕様は実装前に確認する。

非同期・TUI実行基盤とエディタ拡張の企画は別タスク613（121直下）。利用者提示の16項目を子637〜652へ登録（全て未着手、進捗auto）し、[企画・API案](ASYNC_OVERVIEW.md)へ反映した。優先度・モジュール構成・6段階の順序は提案として保持し、実装開始・API確定・Gforth計画との実施順は未定。独立ワーカーVMとネイティブジョブの段階、EVENT-WAIT等のAPI差は調整事項。

## 完了した実装と注意点

### P03c (562, 98be4f8 pushed)

words_buffers.zigでSAVE-MEM/EXTEND-MEM/FREE-MEM-VAR/BUFFER%/INIT-BUFFER/ADJUST-BUFFERを末尾登録し、既存IDを維持。BUFFER%は長さ・番地・容量の24バイト。伸長は内容を保ち、縮小は容量を保持。番地セルを明示登録して保存復元に対応。NULLのFREE-MEM-VARは長さも変更しない。バッファー解放後はINIT-BUFFERで再初期化してから再使用する。

6回帰、通常/全機能群無効のzig build test、通常ビルドが成功。verify-p03c.pyは指定Gforthとの60ケースが一致。ログは.zig-cache/p03c-test.log、p03c-minimal.log、p03c-build.log。JSONは.work/p03c-check/results.json。562と546は完了（auto）。Windows/Linuxは未実施のまま607へ残す。


### P03b公開経路統合（630、bcf625fをpush済み）

SAVE/SAVESYSは新形式を出力し、復元・LOAD-DICTIONARY・State.appendImageは明示登録と到達可能ヒープを再配置する。旧SIGIMG44以前は拒否。型情報を持たない生セルや数値LITERALは再配置しない。固定システム格納セルの登録が追加先と重なる場合は変更前にInvalidImage（利用者確認済み）。入力/ローカル/Tcl所有バッファーへの参照は保存対象外として検査する。

ホストの保存先openより前に出力確保とエンコードを終える。保存前のTcl未完メッセージ破棄・キー解放は従来どおり。Tcl所有バッファーへの型付き参照はその破棄前に拒否する。fresh復元は未使用ページのゼロ化を省き、通常復元はブロックバッファーを保持する。

通常／全機能群無効のテストと通常ビルド、CLI新形式保存/2回追加/旧形式拒否/既存ファイル保持、指定GforthとのP03a 1,376・データ配置288・アドレス18ケースが成功。ログは.zig-cache/p03b-public-*.log、CLIと比較結果は.work/p03b-public-check/。630/628/626/624/620/617/561は完了（auto）。

[P03記録](P03_IMPLEMENTATION.md)と[形式](IMAGE_FORMAT45.md)を参照。P03cも完了し、次は563。P03全体546は完了。

### P03a：固定幅メモリー44語（737b660をpush済み）

words_width.zigを追加し、既存組込タグを保って44語を末尾登録。HELP・英日マニュアル・互換性・フェーズを更新。通常／全機能群無効テスト成功、verify-p03a.pyは基本44＋境界/コンパイル等1,332＝1,376ケースでSigma・指定Gforthとも一致。

利用者の選択でXD>Sは1セル入力→2セルの符号拡張（64ビットGforthのS>D相当）。XD@/XD!のメモリー幅は8バイトで、スタックは2セル。論理バイト順は常にLE。未整列を許し、全幅検査後に格納。!@/+!@は原子操作ではない。明示整列は非0の2累乗、最大整列8。詳細は[P03記録](P03_IMPLEMENTATION.md)。

Historical P03a verification: 737b660 was pushed. P03b/c and typed image persistence were completed subsequently. P03 review is tracked by 631; see [review record](P03_REVIEW.md).

### P02：数値演算・数値入出力65語（初回c3cde8aをpush済み）

整数32語、浮動小数点16語、変換・表示・乱数17語を実装し、辞書・HELP・英日マニュアル・互換性一覧へ反映。通常／全機能群無効テストが成功。比較スクリプトはP02a 3,521、P02b 259、P02c 119、計3,899ケースが成功した。Gforthとの差を意図して検査する635ケースを含むため、全件がGforthとの一致という意味ではない。詳細・コマンドは[P02記録](P02_IMPLEMENTATION.md)。

利用者の「おすすめで」により、幅以上の論理シフトは0、算術シフトは符号埋め、回転数は幅で剰余を取り、16/32ビット回転は上位を0にする。DEC.Rは文書上の符号なし10進契約を採用。指定Gforthの境界実装・負の生セル表示との差は記録済み。

Historical P02 record (typed persistence was subsequently implemented in P03): F*+は融合丸め、E.EXACTは完全な十進値を保持し、最小サブノーマル値まで往復確認。DPLは0x0d50。乱数はVMごとの64ビット状態で同じ種から再現し、Gforth列との一致は要求しない。初期種はP00どおりホストepochマイクロ秒（取得口なし／失敗時0）。RNDの生LCG状態は下位ビットが弱いので範囲選択にはRANDOMを使う。新組込語のタグは既存の末尾に追加。復元・追加イメージで新語の呼出しを検証した。新再配置形式は未実装のまま。

ログは`.zig-cache/p02-test.log`、`p02-minimal.log`。JSONは`.work/p02a-check/`、`p02b-check/`、`p02c-check/`。Windows/Linux確認は607へP02を追加し、ここでは未実施。Claude Code初回はP0/P1なし、P2 1件・P3 8件。時刻種、長い処理のステップ制限、非有限FP.空白、HELPを修正し、Gforth比較とテストを補強。再レビューも全件解消・新たな具体的問題なし。レビュー後のログは`.zig-cache/p02-review-test.log`、`p02-review-minimal.log`、原文と追加実測は`.work/p02-review/`。

### S01：入力・標準ブロック

初回`fac0e8f`、レビュー修正`2f5dad8`をpush済み。レビューと再確認の詳細は[S01レビュー記録](S01_REVIEW.md)。

- EKEYはUTF-8コードポイントと特殊キーを扱う。EKEY>CHARは0〜255、EKEY>XCHARはUnicodeスカラー値を判定する。EKEY?は非ブロック。単独Escは単調時計で合計50 ms判定し、不明・未完入力を保持する。
- 標準キー定数は固定語彙EKEYS（ID 3）。初期検索順はForth Forth EKEYS Root。RootにもEKEYSがあり、ONLY ALSO EKEYSで復帰できる。GRAPHICSのキー値は維持し、ALSO GRAPHICSではそちらが優先される。
- **利用者の選択により端末EKEY/EKEY?のCtrl+CはUserInterrupt（THROW -28）**。pipe/fileのバイト3は文字3。GRAPHICS INKEYは変更していない。割込み時にも未完入力を保持する。
- KEY/EKEY/ACCEPTは先読みを共有する。POSIXではstdio先読みによる停止を避けるためdescriptor読込を使う。Writerにevent_key_fn、buffered_key_fn、monotonic_ms_fnを追加。
- 標準LOAD/THRU/LISTとBLK/SCRを実装。**辞書イメージ読込はLOAD-DICTIONARY**。GRAPHICS LOAD-IMAGEは従来どおり。
- blocks.fbを遅延open/createし、1024バイト×32バッファーを使う。EOF不足分は空白。既存疎ファイルの穴はGforth実測同様NUL。読み取り専用fallbackは権限／読取専用エラーに限定する。
- UPDATEは現在バッファーを変更済みにする。SAVE-BUFFERSは保存、FLUSHは保存して割当解除、EMPTY-BUFFERSは破棄。保存失敗時はdirtyを保持し、読込失敗時は旧バッファーを保持する。
- BYE・通常EOF・SAVESYS実行体の通常終了で書き戻す。バッチ保存失敗は終了コード1。異常終了・シグナル時の保存保証はない。
- LOADは8段の入力スナップショットでキャッシュ衝突を防ぐ。SOURCE-ID=2、SOURCE長1024、REFILLは次ブロック、SAVE-INPUTはblk/cursor/2。コメントは64文字境界まで。THROW/EVALUATE後にBLKと入力を復元する。
- BLOCK/BUFFERは0〜0x1fffff、初回LOADは1〜0x1fffff（範囲外-35）。0 BLK !でブロック0を選べるが、0 LOADは無効。
- BLK=0x0d40、SCR=0x0d48、データ開始位置=0x1e000。ブロックキャッシュ32 KiBと入力スナップショット8 KiBはイメージ対象外。既存プロセスで辞書復元しても未保存バッファーを維持し、BLKは0へ戻す。

### P01：基本25語

|範囲|コミット|追加語|
|---|---|---|
|P01a|cd715dc|0<=、D0<=、D0<>、D0>、D0>=、D<=、D<>、D>、D>=、DU<=、DU>、DU>=、U<=、U>=、UMAX、UMIN|
|P01b|c8fedf1|2NIP、2RDROP、2TUCK、FOURTH、RDROP、THIRD|
|P01c|4021a83|2,、ROL、ROR|
|レビュー修正|a8f06e9|文書誤記・リターンスタック互換性説明・追加回帰|

既存組込enumタグを維持して末尾へ追加。Cell/UCellは64ビット、Double/UDoubleは128ビット、真=-1・偽=0。二倍長数は下位セルの上に上位セルを置く。2@/2!のメモリー順は低いアドレスに上位セル。

2,はHEREに16バイトを確保し、上位／上側セルx2、続いてx1を格納する。自動整列しない。容量不足時はHERE・データ・入力スタックを変更しない。生セルはアドレスに見えても自動再配置しない。

ROL/RORはu64ビット列を回転し、回転数の下位6ビットを使う。0/64/128は恒等、負の生セルも下位6ビットで扱う。2TUCKは入力4セルと空き2セルを事前確認する。

**利用者リターンスタックは呼出しフレーム・DOループスタックと別**。釣り合ったRDROP/2RDROPはGforthと一致するが、Gforthの`2RDROP EXIT`でループ制御情報を直接捨てる用法は非対応（利用者スタックが空なら-6）。ループからは`UNLOOP EXIT`を使う。比較実測とCATCH時のループ復元回帰を追加済み。

Claude Codeの初回レビューはP0/P1/P2・実装論理バグなし。P3文書誤記3件とリターンスタック互換性の確認事項を処理し、再レビューは全件解消・新たな具体的問題なし。[P01レビュー記録](P01_REVIEW.md)を参照。

旧S01ビルドで40利用者定義を保存したSIGIMG42を-264で拒否し、既存KEEP=77を保持することも確認した。検証時の旧イメージ語数667は当時の組込652以上であり、単純な語数不足だけによる拒否試験ではない。

## 検証済み範囲と再実行

通常構成と全機能群無効構成のテスト成功。Zig実行環境は0.17.1。次の形式を使う（--global-cache-dirではなく環境変数）。

```sh
ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-global-cache" zig build test --cache-dir .zig-cache
ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-global-cache" zig build test \
  -Dfloat=false -Dgraphics=false -Daudio=false -Dfiles=false \
  -Dimage=false -Dhelp=false -Dtools=false -Ddebug=false \
  --cache-dir .zig-cache
```

zig build testにはfreestanding objectの確認も含むが、実機実行ではない。実行体を使う比較前にはzig buildを行う。

```sh
python3 scripts/verify-p01a.py zig-out/bin/sigma --gforth-build .work/gforth-audit/gforth-build --report .work/p01a-check/results.json
python3 scripts/verify-p01b.py zig-out/bin/sigma --gforth-build .work/gforth-audit/gforth-build --report .work/p01b-check/results.json
python3 scripts/verify-p01c.py zig-out/bin/sigma --gforth-build .work/gforth-audit/gforth-build --report .work/p01c-check/results.json
python3 scripts/verify-ekey.py zig-out/bin/sigma
python3 scripts/verify-blocks.py zig-out/bin/sigma
```

P01a 1,177、P01b 4,060、P01c 4,553、計9,790ケースがSigma・指定Gforthとも一致。リターンスタックの意図した差は別途実測した。--gforth-buildを省略するとSigmaの期待値検証のみ。EKEYはpipe/PTY/端末行編集/Ctrl+C、ブロックは実ファイル・入力復元・BYE/EOF・SAVESYS終了を確認済み。

比較元は指定Gforthコミット`c479e1eec66dd57a2441c3020177267ba70d3bdc`。元リポジトリではなく`.work/gforth-audit/gforth-build/`のコピーをGCC 16で再構築したGforth 1.0.1 arm64を使う。当初の生成済み0.7.9_20260610は一部の語が未登録だった。

原文・実測は`.work/s01-review/`、`.work/p01-review/`、`.work/p01*-check/`、`.work/gforth-audit/`。最終テストログは`.zig-cache/p01-review-test.log`と`p01-review-minimal.log`。これらはGit管理外で、新しいチェックアウトに存在する保証はない。確定事項はdocsとscriptsを参照する。

**Windows/Linuxの確認はここでは行わない**。607で入力切替・特殊キー・Ctrl+C、ブロック終了保存/SAVESYS、64/128ビット比較・リターンスタック/DO・2,/ROL/ROR・P02の数値演算/変換/表示/乱数を確認する。S01初期のクロスビルド成功は実機確認でも、後続変更の検証でもない。

## 確定方針と後続要件

- Forth 2012標準語を優先する。仕様未確定のまま実装・完了扱いにしない。
- 旧辞書イメージ互換は要求しない。安全に拒否する。**現形式はSIGIMG45/46/47。型付き再配置と到達可能ヒープを保存し、旧形式は拒否**。P03/P08/P10等の後続要件はP00仕様に従う。
- A,/ACONSTANT/AVARIABLE/AVALUE等のアドレス専用機構による追加読込時の自動再配置は後続作業。通常のカンマや2,の生数値を推測で再配置しない。
- F*+は融合したf64演算。乱数は同じ種でSigma内の同じ列を再現し、Gforthとの列一致は要求しない。
- Gforthのゼロ除算やWHEREGの不正アクセス等、比較元固有の不正動作を取り込まない。GPLコードの転用はしていない。今後もライセンスを確認する。

## 作業上の制約

- Planモードは使わない。質問にはまず回答し、修正依頼のない質問だけでコードを変更しない。
- コミット・タグ・pushは、その依頼で明示された場合だけ行う。版番号・リリース用パッケージは今回変更／作成していない。
- パッケージ作成はスクリプト動作確認以外では行わない。版番号変更時は[チェックリスト](version-update-checklist.md)に従う。
- リポジトリ外・外部データへのアクセスは利用者の許可ルールに従う。当セッションでは指定Gforth・tque・Gitリモート・Claude Codeレビューへのアクセスが認められていた。
- tqueは既存CLIを使い、tque ls --all --jsonで確認する。変更後は再読込で保存結果を確認する。rmには確認・Undoがないため注意する。進捗はautoを維持する。
- 未追跡の成果物をgit clean/resetで破棄しない。.workのコピー・バイナリ・ログ、キャッシュをコミットへ混ぜない。
- cargo testが必要な場合は利用者指定どおりPowerShellから実行する。Git Bash経由では実行しない。

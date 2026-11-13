# Gforth対応の引き継ぎ

更新日：2026-11-13。P00・S01・P01とClaude Codeレビュー対応、P02の実装・検証とP03aの実装・検証は完了。次の推奨作業は **P03bの到達可能ヒープ収集・内部ポインター登録（子619、親617/561）**。P02初回コミットc3cde8aをpushし、Claude Codeレビュー指摘への対応と再レビューも完了。

P02レビュー修正`1c39b75`、P03a`737b660`、P03bデータ配置12語`ad34fef`をpush済み。型付きアドレス登録・寿命追跡（616）は`16862f1`でコミット・push済み。続けて新形式コーデック・構造検証（618）を実装・検証した。618と今回のドキュメント変更は未コミット。再開時はgit statusとgit logで最新状態を確認する。

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
|546 P03|未完了。560 P03aの44語は完了、561 P03bは15語の実行・追跡まで実装、562 P03cは未着手|
|561 P03b|未完了。子615のデータ配置12語は完了。子616の型付きアドレス追跡も完了。617は構造コーデック618が完了。収集619と保存復元統合620が残る|
|550 P07|未着手。P01依存は解消。457を先行させる|
|457 P07先行|550配下。IS/ACTION-OF/TO/+TOの辞書登録。既存IDを使う|
|570 P07a|457と544に依存。457を飛ばさない|
|553 P10|未完了。P03〜P09の依存が残る|
|607 Windows/Linux別環境確認|未実施。553配下、544/545/560/580/581依存は解消。ここでは実施しない。既存537〜540と連携|

440は削除済みで再作成しない。完了済み417を再開しない。582はアセンブラー方針の別途検討、583はTRY系の保留D、584はGforth固有ブロック拡張9語の保留D。これらを自動的に今回の実装対象へ加えない。

P03bは15語の実行と型付き登録・寿命追跡まで完了（615/616）。617の新形式・再配置が残る。P00確定の型付きアドレス登録、到達可能ヒープ、SIGIMG45/46/47、部分書込み/MOVE/FREE/FORGET/MARKERと破損表検証を満たす。writeCellだけでなくwords_width.zigとwords_data.zigの直接書込みも追跡へ接続する。アドレスらしい生数値を推測で再配置しない。不明な仕様は実装前に確認する。

非同期タスク・イベントキューの企画は別タスク613（121直下）。[概要](ASYNC_OVERVIEW.md)のみ作成済みで、詳細・子タスク・Gforth計画との実施順は未定。今回のP02には含めない。

## 完了した実装と注意点

### P03b新形式コーデック（子618完了、未コミット）

SIGIMG45/46/47のヘッダー・再配置・ヒープ節と読取専用構造検証を実装。[形式](IMAGE_FORMAT45.md)。10テストに128件のビット変異を含み、通常／全機能群無効のzig build testが成功。ログは.zig-cache/p03b-format-test.logとp03b-format-minimal.log。Stateの保存・復元にはまだ接続していない。

次は619の到達可能ヒープ収集と内部ポインター明示登録。その後620で組込語照合・事前容量確保・失敗時の状態維持・保存復元追加を統合する。型付き登録の暫定保存拒否は維持し、親617/561/546を完了にしない。Windows/Linuxはここでは確認しない。


### P03b型付き登録・寿命追跡（子616完了、16862f1をpush済み）

A,/ACONSTANT/AVARIABLEを既存定義処理へ接続し、メモリー／定数値の登録、全セル更新・部分破損・修復・MOVE前スナップショット、FREE/RESIZE/巻戻し/失敗定義の寿命追跡を実装。最大2,048件で、容量不足はデータ変更前に検査する。通常／全機能群無効テスト、11回帰、実行動作の18ケースが成功。P03a 1,376とデータ配置288も現在の実行体で再確認した。

**新形式の保存・復元への統合前のため、型付き登録がある辞書の保存・復元・追加は暫定拒否**（有効でも-264、部分破損/無効参照は-9）。SAVE/SAVESYSはホスト処理前に拒否し、既存ファイル保持をCLIで確認。旧形式へ型情報を落として保存しない。新形式617でrequireLegacyImageを置き換え、内部文字列等のポインター登録・ホスト資源等の除外・保存/読込の事前検証まで統合する。

ログは`.zig-cache/p03b-address-test.log`、`p03b-address-minimal.log`、比較とCLI結果は`.work/p03b-address-check/`。親561とP03全体546は未完了。詳細は[P03記録](P03_IMPLEMENTATION.md)。

### P03bデータ配置12語（子615完了、ad34fefをpush済み）

->HERE、2FIELD:、W,/L,/X,/XD,、WFIELD:/LFIELD:/XFIELD:、MAXALIGN、MEM,、SAVE-MEM-DICTをwords_data.zigへ実装。288ケースで指定Gforthと一致し、通常／全機能群無効テストが成功。失敗時のHERE・入力・格納内容の保持、重複コピー、フィールドの復元追加、生セルの非再配置を回帰した。

親561は未完了。A,等の登録・追跡は上記616で完了。新形式617はコーデック618まで実装し、619/620が残る。将来の書込み追跡は今回の直接書込みにも接続する。ログは`.zig-cache/p03b-data-test.log`と`p03b-data-minimal.log`、比較JSONは`.work/p03b-data-check/results.json`。詳細は[P03記録](P03_IMPLEMENTATION.md)。

### P03a：固定幅メモリー44語（737b660をpush済み）

words_width.zigを追加し、既存組込タグを保って44語を末尾登録。HELP・英日マニュアル・互換性・フェーズを更新。通常／全機能群無効テスト成功、verify-p03a.pyは基本44＋境界/コンパイル等1,332＝1,376ケースでSigma・指定Gforthとも一致。

利用者の選択でXD>Sは1セル入力→2セルの符号拡張（64ビットGforthのS>D相当）。XD@/XD!のメモリー幅は8バイトで、スタックは2セル。論理バイト順は常にLE。未整列を許し、全幅検査後に格納。!@/+!@は原子操作ではない。明示整列は非0の2累乗、最大整列8。詳細は[P03記録](P03_IMPLEMENTATION.md)。

P03bの新形式・再配置、P03cは未実装。P03全体546は完了にしない。Windows/Linux確認は607へ追加しここでは未実施。ログは`.zig-cache/p03a-test.log`、`p03a-minimal.log`、JSONは`.work/p03a-check/results.json`。P03aは737b660でコミット・push済み。Claude Codeレビューは未依頼で行っていない。

### P02：数値演算・数値入出力65語（初回c3cde8aをpush済み）

整数32語、浮動小数点16語、変換・表示・乱数17語を実装し、辞書・HELP・英日マニュアル・互換性一覧へ反映。通常／全機能群無効テストが成功。比較スクリプトはP02a 3,521、P02b 259、P02c 119、計3,899ケースが成功した。Gforthとの差を意図して検査する635ケースを含むため、全件がGforthとの一致という意味ではない。詳細・コマンドは[P02記録](P02_IMPLEMENTATION.md)。

利用者の「おすすめで」により、幅以上の論理シフトは0、算術シフトは符号埋め、回転数は幅で剰余を取り、16/32ビット回転は上位を0にする。DEC.Rは文書上の符号なし10進契約を採用。指定Gforthの境界実装・負の生セル表示との差は記録済み。

F*+は融合丸め、E.EXACTは完全な十進値を保持し、最小サブノーマル値まで往復確認。DPLは0x0d50。乱数はVMごとの64ビット状態で同じ種から再現し、Gforth列との一致は要求しない。初期種はP00どおりホストepochマイクロ秒（取得口なし／失敗時0）。RNDの生LCG状態は下位ビットが弱いので範囲選択にはRANDOMを使う。新組込語のタグは既存の末尾に追加。復元・追加イメージで新語の呼出しを検証した。新再配置形式は未実装のまま。

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
- 旧辞書イメージ互換は要求しない。安全に拒否する。**現形式はSIGIMG42/43/44で、新形式SIGIMG45/46/47と再配置表は未実装**。P03/P08/P10等の後続要件はP00仕様に従う。
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

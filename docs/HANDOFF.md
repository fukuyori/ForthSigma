## 現在地：P01a完了（未コミット）

P01a 554の比較・最小最大16語を実装。追加語は0<=、D0<=、D0<>、D0>、D0>=、D<=、D<>、D>、D>=、DU<=、DU>、DU>=、U<=、U>=、UMAX、UMIN。既存組込タグをずらさず末尾へ追加し、整数演算モジュールと辞書・HELPに登録した。英日マニュアル・互換性一覧・フェーズ資料を更新。

`src/tests/p01a_test.zig`で64/128ビットの符号境界・最小最大・低位セルと高位セルの順序・真=-1・解釈/コンパイル・スタック不足・イメージ復元/追加後の実行を確認。通常のzig build testと、float/graphics/audio/files/image/help/tools/debugをすべて無効にした構成が成功。ログは`.zig-cache/p01a-test.log`、`.zig-cache/p01a-minimal.log`。

`python3 scripts/verify-p01a.py zig-out/bin/sigma --gforth-build .work/gforth-audit/gforth-build --report .work/p01a-check/results.json`で、P00の33ケースと境界/コンパイル済み1,144ケース（計1,177）がSigma・指定Gforthとも期待値に一致。比較元は既存P00の作業用Gforthコピーで、GPLコードの転用はしていない。Windows/Linux確認はここでは行っていない。

tque 554を完了にした。親544 P01は未完了で、次は555 P01b（基本スタック6語）、その後556 P01c（2,と回転）。進捗はauto。今回のP01aについてコミット・push・版番号変更・パッケージ作成は依頼されておらず、行っていない。

以下はS01以前の記録。現在の実装地点はこの節を優先する。

---

## 現在地：S01コミット・Claude Codeレビュー対応済み

S01初回コミット`fac0e8f`をorigin/mainへpushした後、Claude Code Sonnetへ読取専用レビューを依頼。P0/P1なし、P2 1件・P3 7件に対応し、再レビューと追加4点の最終確認はいずれも新たな具体的バグなし。修正内容・比較根拠・検証は[レビュー記録](S01_REVIEW.md)を参照。レビュー修正もmainへ追加する。最終コミットIDはgit logで確認する。

主な修正：Root EKEYS、未読文字と特殊キーの順序、KEY→EKEYの先読み停止、初回EKEY?、Windows既読UTF-8保持、読み取り専用ブロック読込、BLKによるブロック0選択。利用者の明示選択により端末EKEY/EKEY?のCtrl+Cを割込み（-28）とし、pipeのバイト3は文字のまま維持。割込み時は未完入力列を保持する。Gforthも疎ファイルの穴をNULとするため、その動作は変更せず文書化・回帰確認した。

通常・機能削減のzig build test、verify-ekey.py、verify-blocks.pyが成功。旧13eddbaで実際に作ったイメージの拒否と既存辞書維持も確認。原文と比較ログは`.work/s01-review/`、成果はdocs/S01_REVIEW.md。Windows/Linux実機確認607はここでは未実施、Windowsでの新しい入力経路のコンパイル・errno対応・未読順序も607で確認する。アドレス再配置形式は後続フェーズのまま。次の実装はP01a 554。レビュー管理はtque 611（auto）。

以下は完了までの途中記録。状態が異なる記述はこの現在地を優先する。

---

## 現在地：2026-11-13 S01完了（未コミット）

S01a 580、S01b 581、親S01 579をtqueで完了にした。S01bの子608/609/610も完了。進捗モードはauto。Windows/Linux実機確認は利用者の指示でここでは実施せず、P10配下607（依存580/581）へ分離した。

610ではBYEと通常EOF終了の変更済みブロック書戻しを接続。SAVESYS実行体も共通の終了処理を使う。書戻し失敗は報告し、バッチ終了コードは1。BYEの保存失敗はCATCH可能で、成功前にhaltしない。辞書読込はLOAD-DICTIONARY。英日README/マニュアル/互換性、HELP、実装ノートを更新し、サンプル・スクリプトの旧辞書LOADが残っていないことを確認した（Gforth比較元の標準LOADと誌面仕様の歴史的LOADは維持）。

検証：通常のzig build test、files/image無効構成、graphics/audio/float/image無効構成が成功。`python3 scripts/verify-blocks.py zig-out/bin/sigma`でBYE/EOFの実ファイル保存、ブロック入力、LOAD-DICTIONARY、SAVESYS実行体のEOF保存が成功。ログは`.zig-cache/s01b-test.log`、`.zig-cache/s01b-disabled.log`、`.zig-cache/s01b-minimal.log`。

次はP01 544（S01依存は解消）、最初の作業P01a 554（比較・最小最大16語）。P01aは未着手。新形式SIGIMG45/46/47とアドレス再配置は未実装で、後続フェーズの要件として残る。現在のイメージは追加済み組込語と新しいデータ開始位置を前提とし、S01前のイメージとの互換はない。版番号変更、リリース用パッケージ作成、コミット、タグ、pushはしていない。

以下は今回の途中記録と前回のP00引き継ぎ。

---

## 2026-11-13 S01b入力統合完了（未コミット）

tque 609完了。BLK/SCR、標準LOAD、THRU/LISTを登録。辞書読込の登録名はLOAD-DICTIONARYへ変更し、ホストの辞書読込テストとHELPも追従済み。LOADは固定論理メモリー内の入れ子用入力スナップショットを使い、衝突するBLOCKや内側のLOADによる入力破壊を防ぐ。BLK変数は0x0d40、SCRは0x0d48。SourceKind.blockを追加。ブロックのSOURCE-IDは2、SOURCE長は1024、SAVE-INPUTはblk/cursor/2、REFILLは次ブロック。EVALUATE/ファイル/端末の解釈中はBLK=0とし、終了/THROW後に呼出元へ戻す。バックスラッシュコメントは64文字境界まで。

通常テスト、`-Dfiles=false -Dimage=false`、macOS実ファイルのLOAD/入れ子/コメント/THROW/REFILLを確認済み。未保存バッファーは引き続き辞書復元時に保持する。

次は610：BYE/通常バッチ終了/SAVESYS実行体終了時の書戻しと失敗扱い、LOAD-DICTIONARY改名に伴う残りの文書/サンプル/メッセージ更新、ブロック語のマニュアル/互換性一覧、統合回帰。581全体は未完了。Windows/Linux実機確認はここでは行わない。

---

## 2026-11-13 S01b保存基盤完了（未コミット）

tque 608完了。BLOCK/BUFFER/UPDATE/SAVE-BUFFERS/EMPTY-BUFFERS/FLUSHを実装。`src/core/blocks.zig`と`src/tests/blocks_test.zig`。32×1024バイトを入力領域直後の固定論理領域に予約し、辞書データ開始位置を移動。バッファー内容はイメージへ含めず、既存プロセスで辞書復元する場合は未保存内容とファイル識別子を維持する。errno=2の場合だけblocks.fbを作成し、読込不足分は空白で埋める。書込・flush失敗時は変更フラグを残し、読込失敗時は旧内容を維持する。

通常の`zig build test`、`-Dfiles=false`、macOS実ファイルでの作成/保存/再読込が成功。ログは`.zig-cache/s01b-test.log`と`.zig-cache/s01b-nofiles.log`。追加テストはルートから取り込み済み。

次はtque 609（入力統合、依存543/608）、続いて610（改名・終了保存・文書・統合、依存543/609）。BLK/SCR/LOAD/THRU/LISTはまだ未実装。BYE/バッチ終了時保存と辞書LOADの改名も未実装。S01b 581全体は未完了。進捗管理はauto。

---

## 2026-11-13 S01a作業中（未コミット）

標準キー定数のEKEYS語彙、EKEYのUTF-8/端末エスケープ列解釈、EKEY>FKEYと修飾マスク、EKEY>XCHARのコードポイント判定を追加中。GRAPHICSライブラリーの読込中はEKEYSを検索順から外し、終了後に元へ戻す。固定語彙ID 3を追加読込時の再配置対象から除外した。回帰テストを追加し、既存ORDERテストを新しい初期検索順へ更新した。

EKEY?のパイプ非ブロック性、単調時計によるEscの合計50 ms、EKEYからKEY/ACCEPTへの未読バイト保持を修正。macOSのパイプ・PTY試験は `python3 scripts/verify-ekey.py zig-out/bin/sigma` で成功。Windows x86_64・Linux x86_64のクロスビルド成功（実機確認ではない）。英日マニュアルと互換性一覧を更新。GRAPHICSなし構成でも標準キー定数のHELPを残す。

利用者の指示により、tque 580（S01a）は完了。Windows/Linuxの実端末確認は、ここでは実行せず、P10配下の別タスク607（依存580）へ分離した。Windowsのキー修飾、UTF-16入力、KEY/ACCEPT/行編集との切替、Linuxの実端末確認は607で行う。新イメージ形式45/46/47と再配置表の実装はまだ行っていない。S01bは保存基盤608まで完了。入力統合609と改名・終了処理610が残る。

テストログは `.zig-cache/s01-test.log`。`.zig-global-cache/`は検証用キャッシュで成果物へ含めない。コミット・pushは未実行。

---

# Gforth対応の引き継ぎ

2026-11-12時点。P00の仕様確定とClaude Codeレビューは完了。次はS01の実装から再開する。今回の作業ではSigmaのワード本体は変更していない。

## 最初に読む資料

- [実装フェーズ](GFORTH_WORD_PHASES.md)：フェーズ・対象語・依存・完了条件・tque ID。
- [P00仕様](GFORTH_P00_SPEC.md)：確定した互換方針、再配置設計、比較元との差。
- [ワード分類](gforth-word-plan.tsv)：931語のA〜E分類、380語の実装先、Forth 2012の語群・節番号。
- [仕様索引](gforth-p00-spec-cases.tsv)：未対応380語＋既存構文4語のスタック効果と参照元。
- [実測結果](gforth-p00-runtime-cases.tsv)：470ケース。Sigmaの実装済み一覧ではない。
- [比較スクリプトの手順](../scripts/gforth-p00/README.md)。

## 利用者が確定した方針

1. Forth 2012の標準語を優先する。標準キー4語・標準ブロック10語をAに上げ、S01で先行実装する。
2. 辞書イメージ読込の現行LOADはLOAD-DICTIONARYへ改名する。LOADは標準ブロック実行にする。途中案のLOAD-IMAGEは、既存のGRAPHICSの画像読込語と衝突するため撤回した。GRAPHICS LOAD-IMAGEは維持する。
3. 旧辞書イメージとの互換は考慮しない。新形式へ更新し、旧形式は安全に拒否する。
4. GRAPHICSのキー値は維持する。標準用定数は別語彙EKEYSへ置く。起動時は標準定数を使える検索順にし、ALSO GRAPHICS時は既存GRAPHICS定数を優先する。
5. 乱数は同じ種でSigma内の同じ列を再現する。Gforthとの列一致は要求しない。
6. A,やアドレス専用の定義語で保存した値は追加読込時に自動再配置する。普通のカンマで保存した数値は再配置しない。
7. アセンブラーは今回に含めず、対応方針を別途検討する。
8. 確認が必要な仕様を推測で決めたり、未決のまま完了扱いにしない。

EKEYのコードポイント化、Escの50 ms判定、F*+の融合、ブロックの32バッファー、再配置表の構造と検証等の技術設計はP00仕様に記載済み。設計と実装結果を区別する。

## 次の作業 S01

tqueの階層はForthSigma 121 → 次のフェーズ415 → 実装計画542。

|タスク|状態と扱い|
|---|---|
|543 P00|完了。384語・470ケースの比較とレビュー済み|
|579 S01|完了。Windows/Linux実機確認は607へ分離|
|580 S01a|完了。実装・macOS検証済み。Windows/Linux実端末確認はP10配下607へ分離|
|581 S01b|完了。子608/609/610も完了|
|544 P01|基本語25語。579完了により着手可能。最初は554 P01a|
|457 P07先行|550配下。IS/ACTION-OF/TO/+TOの辞書化。544の後|
|570 P07a|457と544の後|
|582|アセンブラーの別途方針検討。542の完了条件には含めない|
|583|TRY系の保留D。542の実装対象には含めない|
|584|Gforth固有ブロック拡張9語の保留D。581の後に必要性を再検討|

440は削除済み。内容は実装フェーズと583・584へ移管した。440を再作成したり、完了済み417を再開したりしない。457も別IDで重複登録しない。

S01では新しい名前の追加だけでなく、既存語への影響も実装する。EKEY/EKEY>CHAR/EKEY>XCHAR、標準K-*定数、LOADの改名、ブロック中のSOURCE/SOURCE-ID/REFILL/SAVE-INPUT/RESTORE-INPUT/EVALUATE、コメント境界、THROW時の入力復元が対象。既存同名語があることを意味互換の根拠にしない。

## P00の検証とレビュー

- 指定された比較元は`/Users/fuk/source/forth/gforth/`、コミット`c479e1eec66dd57a2441c3020177267ba70d3bdc`。
- 当初の生成済み実行版は0.7.9_20260610で、一部のソース上の語が未登録だった。元リポジトリをビルド場所にせず、`.work/gforth-audit/gforth-build/`のコピーでGCC 16を使って再構築した。新しい実行版はソースのconfigure.acに従い1.0.1 arm64。
- macOS arm64の比較環境で470ケースが成功し、仕様索引の384語全てをカバー。新しいSigma機能が成功したという意味ではない。
- Claude Code Sonnetの初回レビューでは未完了と判定。RANDOM等の参照誤り、改名の衝突、キーの語彙、ブロック入力、再配置設計、具体的な比較ケースを修正した。
- 再レビューでは「P00は完了にできる」「完了を妨げる具体的な不備なし」。軽微な文書指摘も処理した。
- ケース数はCSVとして470レコード。引用された入力に改行があるため、物理行数で数えない。run.pyが件数・失敗・網羅・重複IDを検査する。
- BUFFERはGforth同様に既存内容を取得する。標準が初期内容を要求しないこととは区別する。
- Gforthの0除算の動作とWHEREGの-e入力からの不正メモリーアクセスには比較元固有の差がある。Sigmaへ不正動作を移さず、P00仕様に従う。
- EDITOR=true等は検証プロセス限定。実エディターは起動していない。

セッション内のレビュー原文とビルドログは`.work/p00-review/`、`.work/gforth-audit/`。これらはGit管理外なので、新しいチェックアウトに存在するとは限らない。確定事項と再実行手順はdocsとscriptsへ保存済み。

## 作業ツリーとGit

基点HEADは`f1140c76814fb31b71c91743ca6cb7d99ad05054`。このコミットは以前の依頼でpush済み。この引き継ぎ作成後、利用者から計画・P00資料・比較スクリプト・引き継ぎのコミットとpushが指示された。後続コミットのIDと作業ツリーの状態はgit logとgit statusで確認する。

変更済みの既存ファイルはCOMPATIBILITY英日版、DECISIONS、docs/README英日版。新規ファイルはGFORTH_WORD_PHASES.md、GFORTH_P00_SPEC.md、分類・仕様・実測・キー定数のTSV、scripts/gforth-p00配下、およびこの引き継ぎ。

未追跡の資料も成果物なので、git cleanやresetで破棄しない。`.work`のGforthコピー、Git情報、バイナリ、既存パッケージのコピー、ログ等をコミット対象へ混ぜない。

## 作業上の制約

- Planモードは使わない。仕様の不明点は実装前に確認する。
- 質問にはまず回答し、修正・実装の依頼がない質問だけでコードを変更しない。
- コミット・タグ・pushは、その依頼で明示された場合だけ行う。
- パッケージ作成はスクリプト動作確認以外では行わない。版番号を変える場合は[チェックリスト](version-update-checklist.md)に従う。
- リポジトリ外・外部データへのアクセスは利用者のアクセス許可ルールに従う。当セッションでは指定Gforth/tque等へのアクセス許可があった。
- tqueは既存CLIを使う。`tque ls --all --json`で状態を確認し、保存結果が不明な変更は再読込してから判断する。`rm`は確認なし・Undoなし。
- GforthのGPLコードは参照元として扱い、実装コードの転用はライセンスを確認する。
- 実装後のWindows・Linux・macOS確認は別途必要。クロスビルドを実機検証として扱わない。Windowsの既存確認537〜540も維持する。

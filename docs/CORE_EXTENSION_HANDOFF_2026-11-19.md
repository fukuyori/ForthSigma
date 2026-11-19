# 613 本体機能拡張の引継ぎ（2026-11-19）

## 最新追記：638イベントキュー（2026-11-19）

現在の基点は`e66c701`、main。637はMac実機1073を含め完了済み。以下の637の残作業の記述は履歴。638のコード・設計・試験・レビュー資料は、この追記と同じコミットに含む。2026-11-19、利用者からコミット・プッシュの指示を受けた。

638を1074仕様→1075実装→1076 Windows/Linux→1077 Mac実機へ分割した。13:02 JST確認。1074〜1076は完了、638はauto75%、1077は未着手。最終12構成の成功とsource_sha256の一致も確認済み。[設計](EVENT_QUEUE_DESIGN.md)、[実装記録](CORE_EXTENSION_IMPLEMENTATION.md)、[レビュー採否](reviews/638-review-response.md)を先に読むこと。

EKEY-WAITの固定3セル、mouse付随情報、paste境界、部分入力と全体期限、peek/byte/GRAPHICSの切替、stdin入れ子、checked押戻しとEOFの順序を実装した。Windows独立console/pipeと既存回帰、LinuxのReleaseFast・PTY/pipe・NS、Mac向けコンパイルが成功。クロスコンパイルをMac実行の証拠とは扱わない。

EKEY-WAITはstdin専用。選択ファイルの期限待機は639配下1078へ追加した。1067保存アプリ起動設計は独立して着手可能だが、起動機能の実装は未着手。LOGO本体は外部Forthアプリの方針を維持する。


## 最新追記：637端末制御（2026-11-19）

以下の旧09:32時点の記録は履歴。現在の基点は`b4af2fb`で、共通基盤・語群のMac実機1065と900・1055は完了済み。今回の637の実装・設計・試験・レビュー資料は、この追記と同じコミットに含む。2026-11-19、利用者からコミット・プッシュの指示を受けた。

637を1070仕様→1071実装→1072 Windows/Linux→1073 Mac実機へ分割して進めた。[端末制御設計](TERMINAL_CONTROL_DESIGN.md)、[実装記録](CORE_EXTENSION_IMPLEMENTATION.md)、[レビュー評価](reviews/637-review-response.md)を先に読むこと。TERM-MODE!/@、COLS/ROWS、4定数、表示管理と入力境界の処理を実装。Windows cooked Ctrl+C後の入力再開は専用CONIN$ハンドルで修正し、外部生成イベントとConPTYで確認した。Mac向けコンパイルは成功したが、637のMac実行は1073に残る。

11:29 JST確認。最終の12構成マトリクスと追加レビュー・再試験が完了し、tqueの1070〜1072を完了にした。637はauto75%、1073は未着手0%。マトリクスのsource_sha256は現在のbuild.zig/srcと一致する。次は638で、先行条件1056・1064は完了している。1067保存アプリ起動の設計は別途着手可能だが、まだ実装していない。LOGOは外部Forthアプリに置く。


確認日時：2026-11-19 09:32 JST。作業場所：`D:\home\source\zig\forthz`、PowerShell、ブランチ`main`、HEADは`935b4e7 docs: detail core extension design and review findings`。

この引継ぎ作成時にGit・tque・実装記録・保存ログを再確認した。下記の試験結果は直前の開発で実施した記録であり、引継ぎ作成のための再実行ではない。タスク番号は振り直されることがあるため、再開時はタイトルと親子関係も照合する。

## 引継ぎ作成後の追記：保存アプリ起動基盤

2026-11-19、利用者の追加指示により1003配下へ1066「保存アプリの起動基盤」を追加した。仕様設計1067→コア実装1068→受け入れ1069。実装は1067・1056・1064に依存する。LOGOの言語処理・タートル・UIをSigmaへ組み込まず、本体は汎用のSAVESYS起動基盤を担当する。[追加計画](SAVED_APPLICATION_STARTUP_PLAN.md)。計画・tqueへの登録のみで、新しい起動機能は未実装。既存の次工程637・638も引き続き着手可能。以下の確認日時時点の記録とは区別する。

## 利用者の指示と現在の到達点

- 利用者はレモン、担当の呼称はロク。
- 「claude codeのレビューを依頼しながら、できるだけ止めないで進めて」を受け、読み取り専用レビューと実装・検証を並行して進めた。
- 「mac部分は残して、次に進めて」を受け、Mac実機確認1065を残したまま1056「語群基盤」と1036「OS判別」を完了した。
- 共通基盤の実装を利用する後続タスクは、900全体ではなく完了済み1064を先行条件に変更した。900の契約担当は維持する。最終受け入れ1057は1055を通して900とMac確認も待つ。
- 現在のコード・実装記録・レビュー記録は未コミット・未プッシュ。今回の引継ぎ依頼にはコミット・プッシュの指示はない。

## tqueの確認結果

| 番号 | タイトルの要点 | 状態 |
|---|---|---|
| 613 | 本体の機能拡張 | 未完了、auto16% |
| 1055 | 共通基盤 | 未完了、auto97% |
| 900 | 共通契約と内部最小基盤 | 未完了、auto91% |
| 1058〜1062 | 共通部品・ホスト統合・信号所有 | 完了 |
| 1063 | 統合後の受け入れ | 未完了、auto50% |
| 1064 | Windows/Linux自動受け入れ・Macコンパイル | 完了 |
| 1065 | Mac実機受け入れ | 未着手、0%。語群構成とHOST-OSもここに残す |
| 1056 | 語群のビルド・読込み基盤 | 完了。依存1064 |
| 1036 | OS判別 | 完了。依存1056 |
| 637 | ターミナル制御 | 未着手、着手可能。依存1056・1064 |
| 638 | イベントキュー | 未着手、着手可能。依存1056・1064 |
| 1049 | タスク実行方式の比較 | 未着手、依存なし。設計を並行して進められる |

自動進捗はタスク構造からの値であり、工数の消化率ではない。637・638を開始した扱いにはしていない。タスク制御1048の実装も未着手。

## 実装済みの内容と重要な契約

### 900 共通内部基盤

- `src/core/runtime_base.zig`：差替え時計、期限、取消し印、型付き台帳、信号所有スコープ。OSサービスを使わない。
- `src/host_clock.zig`、`host_wake.zig`：Windows QPC/Event、POSIX単調時計/pipe。通知の集約、早着通知、取消し、期限、継承属性を試験。
- `src/host_runtime.zig`：共通所有者、時計・Wake・取消し・Broker、台帳の寿命と終了順。ownerと台帳epochはプロセス内で再利用しない。
- `src/host_signal_broker.zig`、`host_wait.zig`：NSと音待機の信号所有を仲介。復元失敗は保持して再試行し、古い端末モードの保存値を再適用しない。
- `main.zig`、`host_input.zig`、`host_audio.zig`：ホスト文脈への接続、端末変更前の復元フック、shutdown/deinit順。音待機のホスト障害は既存-265へ伝える。

Runtime/Wakeは共有後にコピー・移動しない。OwnedTableは`initTable(out)`で安定アドレスへ束縛し、操作・解放は所有スレッドに限る。解放前に利用者を停止・joinする。台帳のgetが返すポインターはremove/deinitまでの借用。起動をまたぐハンドルの一意性や公開Forthハンドル形式は未実装。

### 1056・1036 語群基盤とOS判別

- `-Dextension`は既定true。audio/graphicsから独立し、除外しても共有の内部Runtime・時計・Wakeを使える。
- `REQUIRE-EXTENSION`がEXTENSION語彙を初回だけ登録する。利用例：

```forth
REQUIRE-EXTENSION ALSO EXTENSION HOST-OS TYPE PREVIOUS
```

- `HOST-OS ( -- c-addr u )`はコンパイル対象のOS系列を`windows`、`linux`（WSL/Androidを含む）、`macos`、その他は`unknown`で返す。Wine上のWindows版もwindows。未知の文字列はunknownと同様に扱う。
- 借用文字列を呼ぶたびに論理領域へ書き直す。次のHOST-OSかイメージ復元まで有効、書換え禁止。保存された別OSの値をそのまま返さない。
- extension除外時は通常の未定義語-13。読込みはparserの入口なので`[DEFINED] REQUIRE-EXTENSION`では機能検出できない。
- 記録セルは`0x0dc0`、文字列は`0x0dc8`から8バイト。領域の重複をcomptimeで検査する。
- `src/core/library_groups.zig`で語群一覧を共通化し、State追加とバイト列追加の両方で読込み済み認識を更新する。
- 新BuiltinによりイメージABI署名が変わる。新magicは増やさない。旧版互換は追加要件にしていない。
- 復元・追加のpreflightは、除外された追加builtin語と直接builtin OpをInvalidImageで拒否する。以前読めたaudio/graphicsイメージを一部拒否する変更。wire codecとSAVEは構造検査を維持する。
- 予約された基本辞書欄への普通の呼出しは従来どおり読込み可能で、除外語の実行時に-261となる。生xtデータの実行時防御も残す。
- `State.extension_library`が増え、直下フィールドは168項目。ワーカー隔離監査表と1053へ反映済み。再帰的な隔離監査は未完了。

## 検証の記録

Zig 0.17.1。詳細は[実装・検証記録](CORE_EXTENSION_IMPLEMENTATION.md)。

| 対象 | 確認済みの結果 |
|---|---|
| Windows通常構成 | 23/23ステップ成功。core1027成功・8skip、host87成功・10skip。runtimeは先行成功のキャッシュ |
| Windows構成マトリクス | audio/graphics/extensionの8通り＋代表除外4構成、計12構成成功。異なるextension構成間のイメージ拒否も成功 |
| Windows結合試験 | 通常・extension除外それぞれ38件成功 |
| WSL/Linux通常構成 | core1027成功・8skip、host98成功・5skip、runtime15/15成功。HOST-OS実出力はlinux |
| WSL/Linux extension除外 | core1023成功・12skip、host98成功・5skip、runtime15/15、結合38件成功 |
| Mac向け | aarch64-macos、graphics/audio/float除外、extension有効でcore/host/runtimeの14/14ステップがコンパイル成功。実行は未確認 |
| OS非依存性 | Cortex-M0+ freestandingのコンパイル成功 |
| 全語リファレンス | 1536項目、HELP1322項目を照合。文書例28件、独立例136件、選択器5試験、動作回帰19件が成功 |
| 共通基盤の先行検証 | Windows独立コンソール36ケース、Linux NSの期限・信号復帰・PTY5ケースも実施済み。物理キーボード操作の確認とは別 |

主な保存先（`.work`はローカル成果物。別環境には自動で引き継がれない）：

- `.work/extension-matrix/matrix.json`：12構成のcomplete=trueとイメージ拒否。source_sha256は実行開始時の参照値で、GitコミットIDではない。実行途中に行った追加整形はlibrary_loadingのコメントのみ。
- `.work/1056-review/matrix-final.log`、`linux-*-final.log`、`macos-compile-final.log`、`reference-*-final.log`。
- `.work/p10/linux/`：extension除外の明示配置した試験と結合試験。
- `.work/900-review/`、`.work/p05b-ns-check/sigma-only.json`：共通基盤・NSの先行検証。
- `.work/1056-windows/bin/sigma.exe`、`.work/1056-linux/bin/sigma`：検証用実行体。インストール済みアプリやリリース版の更新ではない。

## Claude Codeレビューと未確認事項

900では4回、1056・1036では3回の読み取り専用レビューを実施した。原文・依頼・評価・採用判断を別々に保存した。

- [900の指摘対応](reviews/900-runtime-response.md)
- [1056・1036の指摘対応](reviews/1056-response.md)
- [詳細設計の判断記録](CORE_EXTENSION_DESIGN_DECISIONS.md)

追加確認の評価は「読んだ範囲で新たな高・中の問題なし」。実OS・全機能の承認ではない。低い指摘への試験・HELP等の補強は、その後の回帰試験で検証した。

残る制約：POSIXでSIGINTハンドラーそのものの復元に失敗している間、待機外SIGINTが既定動作へ戻ることは保証しない。失敗を報告して次の待機・モード変更・終了で回復を試みる。実OSの復元失敗の注入は未実施。Mac実機、通常VMループの速度比較、リリース用パッケージ作成も未実施。ライブラリ失敗の巻戻しは辞書・検索設定が対象で、任意のForthのスタック・メモリー副作用を取り消すものではない。

## 再開する順序

1. Git状態とtqueを再取得し、未コミットの900・1056・1036の差分を保持する。番号だけでタスクを特定しない。
2. [全体計画](CORE_EXTENSION_PLAN.md)、[詳細設計](CORE_EXTENSION_DETAILED_DESIGN.md)、[語群の採用設計](EXTENSION_GROUP_DESIGN.md)を確認する。
3. 次の候補は637「ターミナル制御」と638「イベントキュー」。[TUI・非同期計画](ASYNC_CORE_PLAN.md)から担当する仕様を詰める。637では端末の表示設定をraw modeから分け、既存の信号復元フックと終了順を維持する。638では期限・時計・取消しを共通基盤から再利用し、既存のWindows入力レコードと保留入力を保持する。
4. 未決API・具体値は既存決定と照合し、Claude Codeに具体案をレビュー依頼しながら進める。レビューには固定コピーを渡し、原文と対応を保存する。レビュー待ちの間は独立した検証・文書作業を進める。
5. 1049の方式比較は並行可能。独立Forth VM採用、通常ループの変更、デバッグ必須のタスク取消しを既決事項として扱わない。[タスク制御計画](TASK_CONTROL_PLAN.md)と[State監査表](CORE_EXTENSION_WORKER_STATE_AUDIT.md)を使う。
6. Mac確認は[1065の実機手順](CORE_EXTENSION_MAC_ACCEPTANCE.md)へ残す。クロスコンパイルで完了にせず、900・1063・1055・1057の最終完了条件も維持する。

再開時の確認コマンド：

```powershell
git status --short
git log -1 --oneline
tque ls --root 613 --all --json
zig version
```

変更内容に応じて選ぶ検証コマンド（この引継ぎ作成時には再実行していない）：

```powershell
zig build test --summary all
python tests/scripts/verify-extension-matrix.py
python tests/scripts/verify-feature-matrix.py --platform linux --groups extension
python scripts/word-reference.py --check --sigma .work/1056-windows/bin/sigma.exe
```

最後のコマンドで使う実行体は検証対象のソースから作り直す。日本語リファレンスのsource fingerprint更新は、日本語説明と実装の対応を確認した後に行う。

Claude Codeへ読み取り専用レビューを依頼したときのCLI設定：

```powershell
Get-Content -Raw .work/<review>/request.txt | claude -p --tools 'Read,Glob,Grep' --allowedTools 'Read,Glob,Grep' --permission-mode dontAsk --strict-mcp-config --disable-slash-commands --no-session-persistence --output-format json
```

## Gitと作業範囲

HEADは上記の設計文書コミット。実装には追跡済みファイルの変更と未追跡の新ファイルが混在する。`src/core/runtime_base.zig`、host側のRuntime/時計/Wake/Broker、`words_extension.zig`、`image_features.zig`、`library_groups.zig`、追加試験・Forthソース・レビュー原文・実装記録を含めて差分を確認する。

現在は`docs/LOGO_TURTLE_STUDY.md`も未追跡として存在し、文書索引にリンクがある。その内容は今回の613の引継ぎでは確認対象にしていない。コミット対象は再開時にGit状態と差分を照合して選ぶ。

コミット・タグ・プッシュは、その依頼で明示された場合に行う。リポジトリ外と外部データへのアクセスは利用者のアクセス規則に従う。今回の引継ぎではソース修正・tque更新・ビルド・リリースは行っていない。

# 1057：613全体の統合受け入れ計画

[English](INTEGRATION_ACCEPTANCE_PLAN_1057.md)

作成日：2026-11-26。作成者：ロク。第1段階の計画であり、受け入れ結果ではない。対象は ForthSigma、Zig 0.17.1、Windows x86_64を起点とするWindows・Linux・macOS。実装、題材・道具の作成、ビルド、性能測定、実機操作は今回行わない。

## 1. 範囲と既存の合格

出典：[全体計画](CORE_EXTENSION_PLAN.md)「進める順序」のE段階1057行、同節末の999・1001の判断記録、[詳細設計](CORE_EXTENSION_DETAILED_DESIGN.md)§14。1055・1002・1003・1037・1048・999・1001の完了は今回の利用者提示を前提とする。`tque show 1057` と `tque ls --root 613 --tree --all` は保存先ロックへのアクセス拒否で取得できなかった。実行段階で同じ読取りを再試行し、題名・親子・依存を照合する。tqueは変更しない。

以下は既存の記録への参照であり、今回の再実行ではない。古い「未完了」記述より、日付の新しい完了追記・利用者決定を優先する。相違は根拠を併記して残す。

| 記録ID | 既存の受け入れと参照する節 | 1057で追加する境界 |
|---|---|---|
| R1 | [共通基盤](CORE_EXTENSION_IMPLEMENTATION.md)「2026-11-19：1065 Mac実機受け入れ」「最終の検証結果」 | 保存アプリから各資源を同時に使う |
| R2 | [端末・イベント](CORE_EXTENSION_IMPLEMENTATION.md)「2026-11-19：637 ターミナル制御（1070〜1073）」「2026-11-19：638 イベントキュー（1074〜1077）」、[I/O](ASYNC_IO_IMPLEMENTATION.md)「検証と再現」「Mac実機受け入れ（1092/1096）」、[子プロセス](PROCESS_MANAGEMENT_IMPLEMENTATION.md)「実行した確認」「Mac実機受け入れ（1101）」 | 保存起動した同一プロセスで入力・I/O・タスク完了・描画待ちを結合 |
| R3 | [Unicode](GRAPHEME_IMPLEMENTATION.md)「確認結果」「Mac実機受け入れ（1111）」、[ファイル](FILESYSTEM_IMPLEMENTATION.md)「確認結果」「Mac実機受け入れ（1116）」、[実行制御](EXECUTION_CONTROL_IMPLEMENTATION.md)「最終集計」「Mac実機受け入れ（1122）」 | 結合題材の日本語・ファイル・中断経路に限定 |
| R4 | [保存アプリ](SAVED_APPLICATION_STARTUP_IMPLEMENTATION.md)「実行結果」「Mac実機受け入れ（1124）」、[1069条件](SAVED_APPLICATION_STARTUP_ACCEPTANCE.md)「1069での受け入れ表（設計レビュー後に固定）」最終段落 | 後続のPCM・フレーム提示・タスク資源（明示された1057残件） |
| R5 | [PCM資源寿命](PCM_HOST_LIFETIME_IMPLEMENTATION.md)「実行結果」、[PCM公開実装](PCM_PUBLIC_IMPLEMENTATION.md)、[音源最終採否](AUDIO_TARGET_AUDIT.md)「最終採否（1140、2026-11-22、利用者の決定）」 | 保存起動時のPCM併用と終了時の停止。音源別全試験は再実行しない |
| R6 | [詳細設計](CORE_EXTENSION_DETAILED_DESIGN.md)§10.4「受け入れの状況（2026-11-23更新）」、[Windows表示](WINDOWS_DISPLAY_CONTRACT_VALIDATION.md)「実行方法と結果」、[Linux物理確認](LINUX_DISPLAY_HOTPLUG_VALIDATION.md)「最終実機確認：完了」、[Windows最終判断](WINDOWS_NATIVE_DISPLAY_VALIDATION.md)「1276・1037の完了判定」 | 保存起動とタスク・PCM・I/O併用。1047の画面配置・抜き差し等を繰り返さない |
| R7 | [タスク制御合格記録](TASK_CONTROL_ACCEPTANCE_SUMMARY.md)§2・§3a（2026-11-26合格、AC-01〜29）、§5の利用者決定 | SAVESYS入口を経由する場合の起動・取消し・終了・復元。既存ACや単一VM比較を再実行しない |

## 2. 受け入れ条件

18条件。起動3、待機・応答4、回収・復元4、構成2、文書2、採否2、証跡1。各行の「出典」は契約、「既存」は合格の参照先。「案」は後続実装が必要な方法であり、既存ツールが既に対応するという意味ではない。

全条件をWindows・Linux・macOSで照合する。M0等は§4の構成。文書・採否・証跡は全OS共通の静的照合とする。非対応能力は仕様どおりの拒否を確かめる条件であり、能力の提供を要求しない。

| ID / 区分 | 結合で新たに確かめる条件・出典・既存 | 方法と合否基準 | OS / 構成 |
|---|---|---|---|
| IA-01 起動 | 保存した入口から後続資源を起動。[保存設計](SAVED_APPLICATION_STARTUP_DESIGN.md)「起動順と終了（全体レビューを反映）」、既存R1・R4・R7 | 保存実行体を別プロセスで起動する案。入口1回、復元後の新規入力・PCM・窓・Snapshot・タスクの初期化成功。保存元の実行時IDを使わない | 3OS / M0 |
| IA-02 起動 | 結合題材の引数・診断経路。同設計「アプリ引数とホストオプション」、既存R3・R4 | 空・空白・日本語・`-e`を題材引数に渡し内容を自動照合。`--sigma --no-app --`経由は資源を起動しない。汎用引数試験は再実行しない | 3OS / M0・M9 |
| IA-03 起動 | 部分初期化失敗後の回収。同設計「起動順と終了（全体レビューを反映）」、[共通規則](ASYNC_COMMON_RULES.md)§6、既存R4・R5・R7 | 入力→窓→PCM→Snapshot/タスク→子/pipeの各取得直後に題材側で故障を起こす案。取得済み資源のみ回収、失敗を成功に隠さず、次の別起動が成功 | 3OS / M0・M1・M2・M9 |
| IA-04 待機 | 同一保存アプリで実入力・I/O・完了・paint/close・期限を一緒に待つ。[詳細設計](CORE_EXTENSION_DETAILED_DESIGN.md)§11.3、既存R2・R7 AC-18/20 | 既存mixed題材の提供元を再利用する案。各提供元に一意連番を付け、処理・保留・破棄の理由と数を照合。入力だけ／完了だけで進行を占有せず、pipeを排出しcloseで待ちを解除。別セッションの成功を合算しない | 3OS / M0・M1・M2・M9（ない提供元は除く） |
| IA-05 応答 | 保存起動経由で要求世代と結果世代を照合。[詳細設計](CORE_EXTENSION_DETAILED_DESIGN.md)§11.2、既存R7 AC-25 | task-native-path/searchの描画とログを流用する案。n・a/b連続要求後、古い結果を採用しない。fによるworker失敗後も直前の正常画像を維持し、次の要求が成功。自動照合とMNL-01 | 3OS / M0 |
| IA-06 応答 | PCM供給中の入力・画面応答。[詳細設計](CORE_EXTENSION_DETAILED_DESIGN.md)§8・§9.4、既存R5・R7 AC-02 | §8の固定測定。画面入力→描画完了33.34ms以内、端末出力排出50ms以内、各フレーム要求→完了16,666,667ns以内の超過数を記録。タスクなし同負荷の基準との差（追加超過）が0、PCM underrun増分0。物理提示を保証しない。数値合否とMNL-02の聴取は別記 | 3OS / M0 |
| IA-07 待機 | 表示能力がない経路でも結合が進む。[詳細設計](CORE_EXTENSION_DETAILED_DESIGN.md)§10.4「能力の取得とエラー」、既存R6・R7 | native/Tk/端末を分け、実装済み能力表と照合する案。非対応フレーム待ちを成功に偽装しない。期限・入力・取消しによる代替で永久待ちせず終了。Tkにnativeの完了番号を流用しない | 3OS / M0（backend別）・M1 |
| IA-08 回収 | 捕捉した失敗と取消しの所有範囲。[共通規則](ASYNC_COMMON_RULES.md)§3・§6、[詳細設計](CORE_EXTENSION_DETAILED_DESIGN.md)§12、既存R5・R7 AC-01/05/24 | 実行中・待機中のtaskを取消す案。取消し要求と終端・回収を別に観測。CATCHはアプリ全資源の自動解放と扱わず、失敗taskを回収し窓/PCMを継続、再投入成功。MNL-03 | 3OS / M0・M1・M2・M9 |
| IA-09 回収 | 正常復帰・BYE・QUIT・未捕捉THROWの共通終了。[保存設計](SAVED_APPLICATION_STARTUP_DESIGN.md)「起動順と終了（全体レビューを反映）」、既存R4・R7 AC-24 | 各経路を独立起動し、正常/BYE=0、QUIT/未捕捉THROW=1。task-native-byeをPCM用に適合する案。音・窓・task・Snapshot・所有子/pipeを残して終了し、生存一覧と終了証跡を照合。失敗時も残資源を記録。MNL-04/05 | 3OS / M0・M9 |
| IA-10 復元 | 保存イメージに実行時状態を持ち込まない。[共通規則](ASYNC_COMMON_RULES.md)§7、[保存設計](SAVED_APPLICATION_STARTUP_DESIGN.md)「保存・完全復元・追加読込み」、既存R4〜R7 | 混在資源の使用後、適法な停止・保存・新規プロセス起動を通す案。入口登録・永続データは保持、古いPCM/窓/task/pipe/入力キューは復活しない。新規資源取得が成功 | 3OS / M0・M9 |
| IA-11 復元 | 完全復元と辞書追加を分ける。[詳細設計](CORE_EXTENSION_DETAILED_DESIGN.md)§12、[保存設計](SAVED_APPLICATION_STARTUP_DESIGN.md)「保存・完全復元・追加読込み」、既存R4・R7 AC-22 | 混在資源の停止前/後に復元preflightと追加を確認する案。実施前に現行の資源別busy/停止契約をソース・最終設計と照合し期待値を固定。拒否は辞書/APP登録/活動資源を変更しない。停止後の完全復元成功、追加はtarget登録を保持し勝手に入口を呼ばない | 3OS / M0・M9 |
| IA-12 構成 | 除外語群を保存入口が暗黙に要求しない。[共通規則](ASYNC_COMMON_RULES.md)§8、[保存設計](SAVED_APPLICATION_STARTUP_DESIGN.md)「機能除外と予約引数」、既存R1・R4・R7 AC-26〜28 | 構成別の保存題材を自動起動する案。§4で残る資源が結合動作し、除外APIの呼出しは既存仕様どおり拒否。全機能版イメージを別ABI構成へ移す方法にしない | 3OS / M0〜M9 |
| IA-13 構成 | image/debug等を除く境界。[タスク構成表](TASK_CONTROL_CONFIG_MATRIX.md)§2・§5・「AC-28：構成別の検査（1400）」、既存R7 | M9でdebug専用EXEC-LIMITEDを使わずtask取消し。M10はSAVESYS/APP語がなく保存題材を生成しない。既存image拒否・58語検査は記録を参照し、新たな汎用行列は回さない。M11でX11なしの能力表示を照合 | 3OS / M9・M10、Linux / M11 |
| IA-14 文書 | 英日利用者向け契約を照合。[全体計画](CORE_EXTENSION_PLAN.md)「項目ごとの着手条件と完了確認」、既存R1〜R7 | §5の項目対応表を埋め、語・引数・能力・中断・終了・復元・除外条件の意味に食い違いなし。機械チェック合格のみで意味一致としない | 全OS共通 / 全構成 |
| IA-15 文書 | 計画と結果・旧履歴の区別。[詳細設計](CORE_EXTENSION_DETAILED_DESIGN.md)§14・§15、既存R6・R7 | 本書英日IA番号/構成/閾値/手順/未確認が一致。後続結果は実行版・記録版・生ログを分けて英日化し、旧未完了文と新完了追記を混同しない。check-docs.pyと参照実在確認が成功 | 全OS共通 / 全構成 |
| IA-16 採否 | 999の採否の最終転記。[全体計画](CORE_EXTENSION_PLAN.md)「進める順序」、[詳細設計](CORE_EXTENSION_DETAILED_DESIGN.md)§8、既存R5 | §6の8対象・モデル・採用版・測定範囲・保留理由・SNES例外が1140の利用者決定と一致。旧進捗値を現在判断に使わず、再測定しない | 全OS共通 / audio有効・無効の説明 |
| IA-17 採否 | 1001の追加なしの根拠。[エミュレータ計画](EMULATOR_CORE_PLAN.md)「背景1画面の試作と測定（1001、2026-11-22）」 | §6の測定入力・7回中央値・SHOWなし・Forth維持・未測定範囲・再検討条件が決定と一致。計画に汎用描画補助の実装を追加しない | 全OS共通 / graphics有効・無効の説明 |
| IA-18 証跡 | 3OS・実機未確認を欠かさず集約。[詳細設計](CORE_EXTENSION_DETAILED_DESIGN.md)§14、既存R7 §1〜3a | §7の結果台帳で全IA×対象OS/構成を合格/不合格/未確認/適用外に分類し、根拠・理由・次の確認方法あり。cross/WSL/差替え/人の観察を分離。不足をexit 0で埋めない | 全OS共通 / 全構成 |

## 3. 結合題材と道具の設計案

1411で題材とadapterを実装した。[道具の使い方と制限](INTEGRATION_ACCEPTANCE_1057_TOOLS.ja.md)を参照。以下の案は計画の履歴であり、実行結果ではない。

後続実装の案であり、この段階では作らない。保存用の定義読込みと実行開始を分離し、入口colonを`APP-ENTRY!`へ登録して`SAVESYS`する。既存の`examples/task-native-path.fs`・`task-native-search.fs`・`task-native-bye.fs`は末尾で実行を始めるため、そのままINCLUDEDして保存する方法は使わない。定義部を再利用する最小の題材を後続で作る。`task-native-common.fs`の描画番号と世代表示、`task-console.fs`のtask/Snapshot処理、`task-path-worker.fs`のworkerを優先して使う。

既存bye題材の音は`VOICE-HOLD`であり、PCMの結合証拠ではない。新題材では既存PCM公開例の形式・APIに従ったPCM供給を接続する。音源8モデルやエミュレータCPUの結合は要求しない。描画は経路/検索結果と世代を表示し、クリップ・座標変換・回転・アルファはR6の期待画像検証を再実行せず、初期状態が復元後に正しいことだけ照合する。

流れは、(1)副作用のない定義・永続データを保存、(2)新規実行体が現在の引数を受領、(3)入力/端末・窓・PCM・Snapshot/task・所有子/pipeを段階取得、(4)同一プロセスの複合待機で入力・I/O・描画・task結果を処理、(5)要求差替え・故障・取消し、(6)通常復帰/BYE/QUIT/THROWをそれぞれ別起動、(7)別起動で完全復元・追加・再保存を検証する。ファイル/Unicodeは日本語の題材引数と一時ファイル名、実行制御は対応構成での協調的中断だけに絞る。

復元と回収はForthで架空の台帳APIを作らず、既存公開語・ホスト試験口を確認して観測する。詳細設計§12には「案」が残るので、IA-11のbusy/停止期待値や資源上限は実装前の契約照合ゲートで最終実装と突き合わせる。相違は根拠と選択肢をClaudeへ示し、勝手に新仕様にしない。解除不能worker・強制終了・既定SIGINTは通常の回収成功に含めず、R7の既存保証と制約を引き継ぐ。

| 既存の道具 | 再利用する点 | 1057で必要となる差分案・制約 |
|---|---|---|
| `tests/scripts/verify-saved-application.py`、`verify-saved-application-windows.py` | 所有一時領域でのSAVESYS・別プロセス起動・status/argv照合 | 結合題材と段階故障の選択、構成別生成物manifest。既存1069全試験は再実行しない |
| `tests/scripts/manual-acceptance-tty.py` | Windows ConPTY/Job、POSIX PTY/supervisor、所有子回収、端末前後比較、nativeの基準入力再生 | 現行は通常sigmaへ題材を送る方式。保存アプリ入口を起動するadapterが必要。既存`--cases native/mixed`が保存アプリ対応済みとはしない |
| `tests/scripts/run-acceptance.py`、`acceptance-probes.py`、`acceptance-fixtures.py` | `--plan`・SHA-256・確認参照、計測/非計測分離、paintログと基準ログの集計 | 全体AC再実行ではなく保存起動分を別runにする。runnerのpaintはログ取込みであり窓を起動しない。1057のログに必要な端点を残すadapterの検討 |
| `tests/scripts/verify-task-public-matrix.py`、`verify-feature-matrix.py`、`verify-extension-matrix.py` | 構成定義・除外語・ビルド出所の記録方法 | C番号と§4を照合。合格済み一般行列は参照し、保存入口からの差分だけ実行 |
| `tests/scripts/verify-async-io-read.py`、`verify-async-io-write.py`、`verify-async-io-stdin-spawn.py` | pipe提供元、連番データ、排出/EOFの期待値 | 保存アプリの複合待機へ提供元だけを接続。独立実行の合格をIA-04に流用しない |
| `tests/scripts/verify-windows-display-contract.py`、`verify-linux-display-contract.py`、`verify-macos-display-contract.py` | backend選択・能力・辞書初期状態の観測方法 | 全表示行列の再実行はしない。OS別方法を保存起動に適合。物理抜き差しは既存R6を参照 |

証跡は後続でリポジトリ内の新しいrunディレクトリへ保存する案。対象実行体とSHA-256、HEADとdirty差分、Zig/Python版、ビルドコマンド、語群、OS/CPU/端末/表示backend/音経路、題材と道具のハッシュ、argv、stdout/stderr、status、取得/終端/回収記録、観察の回答を残す。人の返答はrun ID・原結果ハッシュと関連付ける。第三者コード・ROM・音源データは追加せず、既存題材のライセンス表示を維持する。

## 4. 語群の代表構成

A=audio、G=graphics、E=extension。表の0だけを`-D<name>=false`で除き、指定のないfiles/image/debugは既定値。各構成自身の実行体から保存アプリを作る。すべて3OSのネイティブ実行対象（M11のみLinux）。既存C00〜C17の合格を基盤とし、同じ汎用テストは繰り返さない。

| 構成 | A/G/E・追加の除外 | 既存C対応 | 保存起動からの結合差分 |
|---|---|---|---|
| M0 | 1/1/1 | C07 | 全資源、全終了経路、復元、基準/負荷の応答 |
| M1 | 1/0/1 | C05 | PCM＋端末＋task＋I/O。窓・物理キー・paintを要求しない |
| M2 | 0/1/1 | C03 | 入力＋窓＋task＋I/O。PCMの取得をしない |
| M3 | 1/1/0 | C06 | PCM＋描画の内部待機と保存起動。EXTENSION/task/TUI公開語を要求しない |
| M4 | 0/0/1 | C01 | 端末＋task＋I/O、終了・復元 |
| M5 | 0/1/0 | C02 | 描画＋入力の保存起動と終了、内部待機。公開taskなし |
| M6 | 1/0/0 | C04 | PCMのみの保存起動・停止・復元。公開taskなし |
| M7 | 0/0/0 | C00 | 保存入口と永続データ、後続資源を要求しないこと |
| M8 | 1/1/1、files=0 | C10からdebugを既定へ戻す構成 | SAVESYSと窓/PCM/task。ファイル公開語・ファイル依存pipe試験を呼ばない |
| M9 | 1/1/1、files=0・debug=0 | C10 | M8に通常task取消し・回収。EXEC-LIMITED/traceなし。filesありのM0と併記 |
| M10 | 0/0/1、files=0・debug=0・float=0・image=0・x11=0 | C11 | image除外境界の静的照合。保存アプリは適用外。非保存の最小起動・taskの動作は既存C11の証跡を参照 |
| M11 | 0/1/1、debug=0・x11=0 | C16 | Linuxで保存起動しTk/端末の能力を照合。X11専用能力を要求しない |

M3/M5/M6の時計・起床は内部共通基盤であり、Eを暗黙に有効化しない。M8/M9でもimageは有効なのでSAVESYSを除外しない。image除外時の内部復元能力と公開語の有無を区別する。各構成の省略枝は適用外理由を残し、題材全体をskipして合格にしない。

## 5. 英日の文書照合

| 文書・ソース | 照合する項目 |
|---|---|
| `docs/USER_MANUAL.md` / `.ja.md` | APP-ENTRY・SAVESYS・`--sigma`/`--no-app`、引数、TUI/I/O、PCM、描画能力・完了と実提示、TASK取消し・待機・回収、保存/復元、除外構成 |
| `docs/COMPATIBILITY.md` / `.ja.md` | 語群・OS差・非対応値・debug/files/image等の条件が上のマニュアルと一致 |
| `docs/WORD_REFERENCE.md` / `.ja.md`、`src/core/help_text.zig` | 対象語の綴り・スタック効果・ior/THROW・所有・寿命。新語だけでなく結合題材が使う既存語も照合 |
| 本書英日、`docs/TASK_CONTROL_ACCEPTANCE_SUMMARY.md` / `.ja.md` | IA番号、構成、数値、合格の範囲と未確認、2026-11-26の採否が一致 |
| R1〜R7、`CORE_EXTENSION_PLAN.md`、`CORE_EXTENSION_DETAILED_DESIGN.md`、保存設計 | 単一言語の履歴資料は対応節・日付を根拠欄に記し、英日結果から同じ判断を参照する。履歴全体の翻訳は作業範囲外 |

`python scripts/check-docs.py`は、対訳文書の見出しレベル列・表行数・コードフェンスの対応、追加語のHELP/互換表、CLI項目、版数、全登録語と全ワードリファレンス、grapheme生成表を検査する。見出し本文の翻訳・文章の意味・節リンクの実在・OS実機の合否・数値の正しさは検査しない。対応表で原文節と対訳節を1行ずつ照合し、source登録/HELPと最終設計の語契約に戻って確認する。差異は文書名・節・英日引用・根拠・判断を記録し、無断で契約を変えない。

## 6. 999・1001の採否の確定方法

999は[AUDIO_TARGET_AUDIT.md](AUDIO_TARGET_AUDIT.md)「最終採否（1140、2026-11-22、利用者の決定）」の§1対象・§2保留にした変種・§3本体の部品を最終根拠とする。CHIP-8、ZX Spectrum、NES、Commodore 64、Apple II、Amiga、Atari STは宣言モデルをForthで維持。SNESは`SNES-FRAMES`を本体に残す1188の例外を維持し、参照Forthも残す。機種共通の本体部品は追加しない。8対象の個別文書・測定記録へのリンク、採用版、最重負荷、OS/機器、実聴/停止/再再生の範囲、保留変種を結果へ転記して一致を確定すれば足りる。

NES/SID/Paula/STは他アプリを止めていない既存測定を測り直さないという決定を守る。Linuxの多くはWSLでApple IIは実機という違い、SIDのWindows 1.03倍が機種全体の余裕ではないこと、SNESのForthだけでは不足した根拠を落とさない。保留変種は「調べて不要」ではなく、必要なCPU側エミュレータがまだないため必要時に追加する扱いである。

1001は[EMULATOR_CORE_PLAN.md](EMULATOR_CORE_PLAN.md)「背景1画面の試作と測定（1001、2026-11-22）」と同節の利用者決定を最終根拠にする。Windowsの背景256×240・2ビットプレーン・属性パレット・各負荷7回中央値、`SHOW`を含まない条件と、[Windows測定記録](measurements/2026-11-22-background-prototype-windows.json)を照合する。Forthで8画素をまとめて復号し既存GFX-INDEXED等で転送でき、この範囲で本体追加なしと決定済み。後続のMac測定が存在してもWindows決定と実行環境を混同しない。スプライト/優先順位/4枚以上のビットプレーンは未測定で、必要が出た時に機種共通入力と別タスクを検討する。再測定・採否のやり直しは1057の条件にしない。

## 7. 手作業と未確認の扱い

手作業はOSごとに1手順ずつ利用者へ依頼し、回答を記録してから次へ進む。依頼時は実行体の絶対パス、OS/backend/音経路、起動コマンド、対象窓、操作、期待する結果、止め方を示す。下表は依頼の単位であり、一括実施の依頼ではない。MNL-01aと01b、03aと03bも個別に依頼する。

| 単位 | 操作と観察 | 結び付けるIA |
|---|---|---|
| MNL-01a | 保存したpath題材でnを押す。要求/採用世代と画面が対応し、古い結果に戻らないことを目視 | IA-05 |
| MNL-01b | 保存したsearch題材でa/bを切り替え、次に別依頼でfを押す。失敗中も直前の正常画像が残ることを目視（切替えとfも別の依頼に分ける） | IA-05 |
| MNL-02 | 保存題材のPCM再生中に指定のキーを1回押す。短い既知音と画面反応を確認。音切れ/異音は聴取、時間の数値は計測ログで判定 | IA-06 |
| MNL-03a | 待機可能な区間の予告後、対象端末でCtrl+Cを1回。捕捉結果・入力/カーソル回復・音の停止または設計した継続を確認 | IA-08 |
| MNL-03b | task取消し後に指定キーで再投入。画面・音・入力の継続と新しい結果を確認 | IA-08 |
| MNL-04 | 保存bye題材でqを1回。窓の消滅と音の停止を観察。親子/スレッド回収の自動証跡とは別に記録 | IA-09 |
| MNL-05 | 別起動した保存題材の窓を閉じる。close待機解除と端末の入力・表示回復を確認 | IA-04・09 |

各IA×OS×構成×backendに、判定（合格/不合格/未確認/適用外）、run ID、試験版/記録版、原ログ/ハッシュ、機器、方法、自動結果、人の回答、制約、再確認手順を持つ結果台帳を作る案。必要な端点や所有子の終了証拠がない場合は未確認。未確認は合格数に含めず、理由と使用可能な実機での同じ手順を添える。適用外は設計上の除外だけに用い、機器不足を適用外としない。

クロスビルドは実行未確認、WSL/PulseAudio/RDPSinkはその経路だけ、Xvfbは期待画素の自動検証だけ、関数差替えは差替え契約だけの証拠とする。物理キー、聴取、DPI/複数画面、実提示を推定で埋めない。DwmFlush非対応実環境はR6の利用者決定で完了条件から除外済みで、未実施の記載を維持し再要求しない。現在の計画段階ではすべての新IA実行は未実施であり、Linux/macOSの利用可能な端末・表示・音経路も未確認である。

## 8. 時間条件と計画の固定

IA-06は保存起動により新しく生じる結合経路だけを測定する提案。[TASK_CONTROL_ACCEPTANCE_PLAN.md](TASK_CONTROL_ACCEPTANCE_PLAN.md)「1394：ネイティブ窓の描画と終了（本版で追加）」「60Hz期限の判定の改訂（2026-11-26、利用者の決定 案1、tque 1405・1406）」と同じ端点・基準再生を使う。既存の全負荷70分/OSや取消し4,100件は再実行しない。

測定前に英日計画、構成、題材、道具、標本数・入力列・閾値・除外条件を確定してSHA-256 manifestに固定する。日本語版を正本とし、そのバイト列のSHA-256を`--plan-sha256`へ渡す。英語版とmanifestのハッシュも外部のrun記録へ保存し、文書自身に自己ハッシュを埋め込まない。既存runnerの`--plan`へ本書を渡しても、1057題材を自動選択する機能にはならない。後続adapterが実測の計画一致を検証する。

本測定はレモンの明示確認参照を`--confirmed`に記録してからClaudeが実行する。今回の計画作成依頼を測定承認とは扱わない。準備用smokeは非計測であり閾値合格の標本にしない。IA-06の案は3OSのM0でpath/search各1,200フレーム、独立2組の負荷→基準。負荷側の入力順・フレーム番号を基準へ再生し、描画負荷・PCM標本/供給・窓サイズ/backend・実行体・構成を揃え、task投入だけを止める。双方の最初のフレームを生ログに残し、期限集計から除く。基準不足・欠測・描画負荷差・PCM供給差は未確認とし、成功標本で置換しない。

入力始点はホストの最初のキー取得、画面終点は対応フレームのbackend描画完了、端末終点はwriter排出。OS入力待ち・物理押下・パネル発光は含まない。request/completeを個別に保存し、後のpainted-throughで欠けた完了を補わない。PCMは開始前後のunderrun差とaccepted frame数を残す。33.34/50msは当該区間の最大値で照合し、全生値・超過数・分布を保存する。基準側の入力端点は入力列一致用で、応答判定は負荷側だけ。定常周期の積み上げ超過は診断に残すが合否に用いない。

既存計画の80%追加規則を本条件にも使う案：最大値が限度の80%以上、または追加超過/underrunが発生した場合、該当OS/題材を独立2組追加し、初回結果を残して原因と全組を判定する。規則と回数は測定前レビューで固定し、良い組だけ採用しない。機能失敗・欠測は測定を続ける根拠にせず原因を調べる。ハング防止timeoutは安全用であり応答の閾値ではない。

### 固定した条件（1410、2026-11-26）

以下は上の提案を具体化した測定契約であり、測定結果ではない。回数と80%規則は本節で固定する。計画のハッシュはレモンの確認後にClaudeが外部manifestへ固定し、本書には埋め込まない。

| 項目 | 固定した条件 |
|---|---|
| 対象と回数 | 3 OSのM0。path/searchそれぞれ1,200フレームを、独立2組の負荷→基準で測る。各runは新規プロセス・新規PCM session。組間で状態を引き継がない。追加前は8 run/OS |
| 比較 | 同一実行体・構成・backend・窓サイズ・描画内容・PCM標本列と供給方式。負荷側のキー順序とフレーム番号を基準に再生し、task投入のみ止める。accepted frame数と供給時刻・partial/zero write・waitを双方で記録し、欠落や供給方式の差は未確認 |
| PCM形式 | `examples/pcm-synth.fs:6`のPS-RATE=48,000 Hz、mono signed16 little-endian。`examples/pcm-synth-play.fs:6,18–36`と同じ512 frame/1,024 byteのブロック、capacity=4,096 frame。PS-DEMO-SETUPの同一標本列を使い、無音化の有無も負荷/基準で一致させる。MNL-02は可聴にする |
| PCM供給間隔 | 公開例PS-SEND/PS-RUNと同じ空き容量に従う連続供給とする。固定sleepは挿入せず、512 frameを生成・PCM-WRITEし、accepted分だけ進める。partial/0なら未送信分を保持し、PCM-WAITのneed=1、timeout=1,000 msで再試行する方式を使う。満杯までの先行供給を許す。512/48,000秒=約10.667 msは消費時間であり、固定の呼出し周期ではない。供給待ちで入力/paint処理を独占しないadapterは後続実装の対象 |
| underrun | PCM-OPEN後の同一handleで計測区間直前/直後のPCM-UNDERRUNSを取得し差を取る。新世代attach ack前の0を始点にせず、供給が実際に消費され始めたことを確認してから開始する。初回供給前の無音と意図的drain tailはAPIどおり非計数。連続した欠乏無音はcallback/frame数でなく1 episode、再供給後の再欠乏は別件。終点はSTOP/drain前。各負荷・基準runの差=0を要求し、基準との差で相殺しない。accepted frame数と生counterも保存 |
| 応答と期限 | 負荷側のinput→対応paint最大33.34 ms以下、input→writer排出最大50 ms以下。各frameのrequest→completeが16,666,667 nsを超えた数を負荷/基準で別々に数え、追加超過=max(0,負荷超過数−基準超過数)=0。後続完了で欠測を補わない |
| 80%追加規則 | 該当OS/題材でpaint最大26.672 ms以上またはwriter最大40 ms以上、追加超過>0、またはいずれかのrunでunderrun差>0なら独立2組を一度追加し計4組とする。初回を含む全組を残す。追加で元の失敗を取り消さず、なお閾値失敗なら不合格。機能失敗/欠測は原因調査へ回し、成功runへの差替えや無制限な再試行をしない |
| 除外 | 各runの最初の1 frameのみ期限集計から除外し、生ログには保持（期限の標本は1,199/run）。smokeは全数除外。underrun/応答を最初のframeという理由で事後除外しない。OS入力待ち・物理押下・実提示は測定端点外。欠測・不一致・機能失敗・安全timeoutは合格標本から捨てず未確認/不合格として記録。通常のOS scheduling遅延を外れ値として除外しない |

underrunの根拠：`src/core/sound_stream.zig:74–106` Stream.sample、`src/core/words_pcm.zig:74–80` execute、`docs/PCM_STREAM_DESIGN.md`「SPSCと再標本化」。対応試験は`src/tests/pcm_stream_test.zig`の「PCM hold, held frame accounting, silence episodes and restart」「PCM initial silence is not an underrun episode」「PCM intentional drain suppresses only its empty tail」、`src/tests/pcm_words_test.zig`の「PCM copied stereo input can be reused immediately and silent tails count once」「PCM query before attach acknowledges no previous underrun count」。今回は読み合わせのみで再実行していない。

## 9. 作業順序と所要時間

すべて今後の案。見積りは今回実測していない。利用者の応答待ち・別OSへの受渡し・環境復旧・不具合修正は含めない。

| 段階 | 成果物・終了条件 | 時間 |
|---|---|---|
| 1 計画照合（今回） | 英日計画、IA/出典、check-docs.py、diff/参照実在確認 | ※推測です：1〜2時間 |
| 2 契約ゲートとClaudeレビュー | IA-11の現行契約、IA-06の回数/閾値、構成縮約の採否を確定。レビューと判断は別記録 | ※推測です：1〜2時間 |
| 3 題材・adapter（別途実装依頼後） | 保存定義と入口の分離、PCM/pipe、故障・復元モード、証跡。smokeは計測と分離 | ※推測です：4〜8時間 |
| 4 OS別の自動結合差分 | M0〜M9の保存入口と各終了/復元。M10静的境界、Linux M11。失敗/欠測を記録 | ※推測です：1〜3時間/OS、ビルド込み。初回は試行で再見積り |
| 5 OS別の手作業 | §7を1件ずつ依頼して記録 | ※推測です：20〜40分/OS、回答待ちは別 |
| 6 承認後の時間測定 | §8の2題材×2組×負荷/基準。承認前は実施しない | 理論上のフレーム枠は2×2×2×1,200/60=160秒/OS。※推測です：準備/照合込み20〜40分/OS、追加2組は別枠 |
| 7 文書・採否・最終集約 | IA-14〜18、英日結果、未確認と再確認手順、全体判断 | ※推測です：2〜4時間 |

後続段階2〜7の合計は、3OSで※推測です：約12〜27時間＋待ち/修正/追加測定。実機未確認が残る場合、計画作成完了と1057受け入れ完了を分けて報告する。コミット・タグ・プッシュ・tque更新はこの計画の作業に含まない。

## 10. Claudeに判断を求める点と今回の検証

採否999/1001の再決定は不要。レビュー候補は次の3点。いずれも今回実装しない。

| 論点 | 選択肢 | 推奨と理由 |
|---|---|---|
| 復元期待値の最終化 | A：初期案のbusyをそのまま仕様扱い / B：資源別の最終設計・実装とR7を照合して固定 | B。詳細設計§12は案なので、停止/拒否の相違を契約違反と誤判定しない |
| 保存経由の応答測定 | A：既存R7だけ参照 / B：§8の小さい差分測定 / C：全AC測定を再実行 | B。既存合格を重複させず保存経由PCM併用を確かめる。回数と80%規則はレビュー後固定 |
| 構成の実行範囲 | A：M0だけ実行 / B：M0〜M9とLinux M11の差分、M10の境界照合 / C：既存18構成を全再実行 | B。独立語群の8通りとfiles/debug/image/X11境界を覆い、一般行列は再実行しない |

今回の検証対象は`python scripts/check-docs.py`、`git diff --check`、本書で参照したファイルと節の実在、英日IA/構成/表構造の一致、LFである。実行結果は最終報告に記す。新しい受け入れ試験や実機確認の合格をこの計画書では主張しない。

### 利用者の決定（2026-11-26）

| 論点 | 決定 |
|---|---|
| 構成の実行範囲 | B：M0〜M9とLinux M11の差分を実行し、M10は境界の静的照合 |
| 保存経由の応答測定 | B：§8の差分測定（3 OSのM0、path/search各1,200フレーム、負荷→基準の独立2組、PCM underrun増分0）。回数と80%規則は測定前のレビューで固定する |
| 復元期待値の最終化 | B：題材の作成前に、資源別の最終設計・実装とR7を照合して期待値を固定する。食い違いは根拠と選択肢を付けてレモンに確認する |

## 11. 契約ゲートの結果（1410）

2026-11-26、ロク。指定のef8e481の計画を作業ツリーの英日計画で読み、末尾の3点ともBという決定を基準とした。以下は現行ソースと最終設計・既存試験の静的照合であり、新しい受入れ合格ではない。食い違いD1〜D5は未決のままClaudeが根拠と選択肢をレモンに確認する。題材・道具の実装、測定、Gitの変更操作、tqueの変更は行わない。

### IA-10・IA-11の資源別期待値

全行で、ABI/layout/容量/rootが正しいイメージ、単一の復元操作、他のbusy原因なしを前提とする。「停止後成功」はそれらの検査成功を条件とし、壊れた画像まで成功を保証しない。拒否時は辞書・APP登録・資源所有を変えず、取消し/閉鎖/再起動を行わない。ただしタスク静止検査のhost.pollによる自然な完了観測まで凍結する意味ではない。完全復元成功時のAPP登録は画像の登録、追加ではtargetの登録（未登録を含む）を保持し自動起動しない。

| 資源 | 活動中の完全復元/preflight | 明示停止・解放後の完全復元 | 辞書追加 | 保存イメージに入らないもの | 設計・関数と行・既存試験 |
|---|---|---|---|---|---|
| 入力/端末 | 専用busyなし。検査成功後decoder/保留入力と物理キー状態をreset。端末設定の送信はしない。拒否を要求しない | 成功。入力状態は空。端末要求を画像から再適用しない | 現在の入力/端末要求を保持 | decoder、保留イベント、物理キー、OSモード/端末要求/時計 | `EVENT_QUEUE_DESIGN.md`「既存入力・復元との境界」、`TERMINAL_CONTROL_DESIGN.md`の保存境界段落。`image_restore.zig` restore:12、apply:33–39,112–115、`host_terminal.zig` Manager.set:61/finish:104。T1/T2。端末の復元専用試験は未確認 |
| 窓/画像/表示保留 | 一律busyなし。窓・fit/smooth/keep-open・表示一覧/ホスト回数を保持し、画面/画像プール/clipを解放。表示保留中はD1 | 成功。新規Stateへの復元では窓・一覧・runtime設定は既定値。既存Stateへの復元はState全体の初期化ではない | targetの窓/画像/設定を保持、sourceのOS窓を作らない | 窓、画像画素/プール/clip、display一覧、ホスト回数/設定。辞書変数のIMAGE-*値は保存される | 詳細設計§10.4「状態の持ち主と辞書イメージ」。`image_restore.zig` apply:112–115、`words_graphics.zig` clearImage:587、`graphics_images.zig` releaseAll:329。T3/T4 |
| PCM | current Stateのhandle≠0なら検査適用前にerror.Thrown、throw_code=-528。停止済みでもhandle所有中は拒否（STOPだけでは不足） | PCM-CLOSE成功でhandle=0にしてから成功。新しいPCMは明示OPEN | targetのPCM所有を保持し自動再開しない | live handle、ring、再生位置、ack/underrun/OS音声資源 | `PCM_STREAM_DESIGN.md`「所有と保存」。`image_restore.zig` restore:12–15/restoreFresh:20–23、`words_pcm.zig` execute:37。T5 |
| Snapshot/タスク | Snapshotの外部保持だけは拒否しない。bound hostで非終端・execution_ref・internal_refs・cleanup中ならerror.Busy（数値iorではない）。host受付/IDを維持、取消しなし。core直呼びの境界はD4 | 静止検査を満たせば成功。終端記録/idle workerの存在だけでは拒否しない。成功でepoch更新、旧Snapshot新規admitはStaleSnapshot、保有参照は解放まで存続 | 成功で旧Snapshot新規admitを無効化。既にadmitされた版の寿命を保持し、taskを取消さない | Snapshot manager/版/参照、task ID/queue/結果/worker/WAIT登録。明示捕捉した辞書データとは別 | `TASK_CONTROL_IMPL_1375.md`「回収と復元」、詳細設計§11.3、R7 AC-07/08/22。`host_task_reap.zig` restore:39–42、`task_reap.zig` requireRestoreIdle:52–58、`task_snapshot.zig` canSubmit:163/admit:169、`image_restore.zig` apply:34、`image_append.zig` apply:59–60。T6–T9 |
| 子プロセス/pipe | 専用busy/停止処理は復元経路にない。hostのProcessOps/FileOpsは保持されるが、活動中に残す最終契約と直接試験はD2 | 所有子の終了・出力排出・FREE/pipe閉鎖の成功後、他の前提を満たせば成功。復元は子の停止の代用ではない | 復元経路上はtargetのhost参照を保持。活動中の保証はD2 | registry、設定表、PID/Job、pipe/worker/未読・未配送バイト | `PROCESS_MANAGEMENT_DESIGN.md`「所有・状態・失敗」（保存境界の段落）、`ASYNC_IO_DESIGN.md`冒頭。`host_interface.zig` Writer.process_ops:192/file_ops:246、`image_restore.zig` apply:33–120、`image_append.zig` apply:59。直接復元試験なし。T10はdispatch試験であり代用不可 |
| ファイル/ブロック | 専用busyなし。hostファイル状態と同一processのruntime block bufferを保持。自動closeしない | 明示close後も成功。ファイルを画像から再openしない | targetのhostファイル状態を保持 | OS fid/stream/位置/worker、runtime block buffer。辞書中の整数fidは保存され得る | `ASYNC_COMMON_RULES.md`§7の既存ファイル契約、詳細設計§12の例外。`image_restore.zig` apply:59–63、`host_interface.zig` FileOps:48付近/Writer.file_ops:246。T11/T12 |
| 実行制御 | 専用busyなし、State.executionはapplyの代入対象でなく保持。active予算中の完全復元を最終期待値として採るにはD3の確認が必要 | active EXEC入口/scope終了後は成功。新規Stateは予算/owner/poll状態を引き継がない | active予算depth/remainingを保持、制限回避しない | budget stack/owner/poll counter、割込みscope/ホスト参照 | `EXECUTION_CONTROL_DESIGN.md`「State・画像・検証」の予算段落（74–75行）。`forth.zig` execution:336、`image_restore.zig` apply:33–120、`execution_control.zig` run:58。T13はappend/非保存のみ、full restoreは未試験 |

ソースのパスは上表では`src/core/`を省略（`host_*`は`src/`、`forth.zig`は`src/`）。保存範囲の共通根拠は`src/core/image_encoder.zig` encode:24–70（辞書・保存範囲memory・型付きheapのみ）、`src/core/image_graph.zig` collect:20/collectForAppend:24。普通のセルのhandle値を消去する契約ではない。別起動で番号が一致する可能性があるため「古い整数は必ず無効」と判定しない（共通規則§7、PCM/Process設計）。APPの根拠は`SAVED_APPLICATION_STARTUP_DESIGN.md`「保存・完全復元・追加読込み」、T14。

### 読み合わせた試験名と受入れ記録

以下は実在するtest宣言。今回再実行していない。「直接試験なし」は一般試験の合格で補わない。

| ID | ファイル（src/tests/） | 試験名 |
|---|---|---|
| T1 | event_queue_test.zig:162 | image restoration clears standard decoder state without serializing native events |
| T2 | physical_key_test.zig:124 | physical restore resets only after successful image preflight |
| T3 | graphics_test.zig:3369 | display support runtime state survives in-place restore but is absent in a new machine |
| T4 | graphics_test.zig:985 | restoring an image into a used machine drops its graphics image, and a failed restore keeps it |
| T5 | pcm_words_test.zig:227 | PCM full restore is busy before mutation while save and typed append retain ownership |
| T6 | task_snapshot_test.zig:135 | snapshot complete restore invalidates only after successful preflight |
| T7 | task_snapshot_test.zig:167 | snapshot typed and State append invalidate old versions |
| T8 | task_reap_test.zig:85 | restore busy is nonmutating and retained references block collection |
| T9 | task_reap_test.zig:170 | idle complete restore keeps host and worker open |
| T10 | process_test.zig:44 | process words dispatch arguments and retain stack on interruption or invalid memory |
| T11 | blocks_test.zig:137 | dictionary restore preserves this process's unsaved runtime block buffer |
| T12 | filesystem_test.zig:125 | filesystem compiled words survive image restore without OS resources |
| T13 | execution_control_test.zig:112 | runtime execution budgets survive image append and are not encoded |
| T14 | app_entry_test.zig:55 | app root roundtrip append policy and corrupt image fail before mutation |

R7の`TASK_CONTROL_ACCEPTANCE_SUMMARY.md`§2（AC-07/08/22の3 OS合格）と§3aの追加測定の範囲を照合した。Snapshotデータと寿命、復元時busy/静止後成功はT6–T9の契約と一致する。N2は§3の2026-11-25追記で、accounting allocatorによる上限強制を根拠に「不要」と判断済みである。その下に残る旧「別途提案」と混同せず再要求しない。この契約ゲートで容量・時間・保存起動の新規合格へ拡張しない。T8は内部参照を保持する終端taskも対象とし、単にTASK状態が終端になっただけでは静止成功としない。

### 食い違いとClaudeからの確認事項

| ID | 食い違い・根拠 | 選択肢 | 推奨（未決） |
|---|---|---|---|
| D1 | 詳細設計§12は「表示保留…活動中busy」の初期案。最終§10.4とT3ではホストframes_shown=4/painted=3でも成功し窓保持。native実paint処理と復元の競合はT3の差替えでは未確認 | A：最終§10.4の窓保持/画像解放を採用し、実paint競合を後続で検証 / B：表示保留中busyを新たに設計・実装 | A。既存の最終契約を維持し、初期案を一律の拒否期待値にしない |
| D2 | 共通規則§7は新しい子/readerの復元時保持/閉鎖を未決とする。Process設計の保存対象外だけでは実行中復元の挙動は決まらず、applyに停止もbusyもなく、活動中の直接試験もない | A：targetのhost資源保持を明文化し専用試験 / B：活動中busy / C：復元前に終了・排出を自動実行 | A。既存host所有とファイル境界に沿う。確認までは活動中のIA-11判定を固定しない |
| D3 | EXEC設計74–75行はrestore/appendでactive予算を無効化しないと要求。T13はappendとencodeのみ。applyはexecutionを保持するが実行stack深さをresetするため、active入口からのfull restore安全性は未立証 | A：full restoreはEXEC入口終了後に限定 / B：active full restoreも保証し専用試験/必要な設計修正 | A。既存保証を広げず、停止後の試験を採る。active時の拒否値は未定であり新しい値を作らない |
| D4 | R7 AC-22のBusyは`host_task_reap.restore`のbound host検査。`dictionary_image.restoreImage:88`/restoreFreshImage:92のcore経路にはtask検査がなく、PCMだけを検査する。T9とtask_reap_test:277のunbound試験でも境界が異なる | A：IA-11のtask preflightはbound host hookを使い、core直呼びをbusy保証に含めない / B：全復元経路へtask guardを追加する設計変更 | A。既存ホスト契約を正確に試す。架空のForth復元語やbusy数値を追加しない |
| D5 | 共通規則§7のPCM/端末未決と詳細§12の一律busy案は、PCM最終「所有と保存」、端末最終の表示送信なし、§10.4の保持契約より古い。IA-10の「保存しない」を「同一process復元で全資源を閉じる」と読むと矛盾 | A：資源別の最終契約を優先し、古い未決表は履歴として扱う / B：全資源停止へ統一する新仕様 | A。IA-10は別processでruntime資源を復活させないこと、IA-11は表の資源別挙動を判定する |

### 今回確定した範囲と未確認

確定したのは既存契約を根拠にした表の確定部分と§8の測定条件である。D1〜D5の採否はClaudeがレモンに確認し、回答を記録してから題材実装の前提を固定する。特に子/pipe活動中、active EXEC full restore、native paint競合、各拒否での辞書・APP・全活動資源を同時観測する結合試験は未実施。既存試験名の列挙をその合格証拠にしない。タスクerror.Busyの数値ior変換はこのホストAPIにはなく、Forth公開語としての新しい拒否値は確定していない。3 OSの保存起動測定・実機観察・計画ハッシュ固定も未実施。

### 食い違いD1〜D5の利用者の決定（2026-11-26）

| ID | 決定 |
|---|---|
| D1 | A：最終§10.4（窓を保持し画像を解放）を期待値にする。実paintとの競合は1057の結合試験で確かめる |
| D2 | A：復元しても子プロセス・pipeはtargetのホスト資源として残ることを明文化し、専用の試験を加える |
| D3 | A：完全復元はEXEC入口の終了後に限る。入口の途中での拒否値は新しく作らない |
| D4 | A：IA-11のタスクのBusyはbound hostの経路で確かめる。coreの関数を直接呼ぶ経路はBusyの保証の範囲外と記録する。題材の作成時に、公開語がbound hostの経路を通ることを確かめる |
| D5 | A：資源別の最終契約を優先し、古い未決の表と一律busyの案は履歴として扱う。IA-10は別processでruntime資源が復活しないこと、IA-11は資源別の期待値の表どおりに動くことで判定する |
### IA-11の確かめ方の利用者の決定（2026-11-26、1411で発見）

保存アプリが資源を取得した後に、活動中のtargetを完全復元する公開の入口はない（bound hostの完全復元は保存アプリの起動時だけ、`LOAD-DICTIONARY`は一時VMへの復元と辞書の追加）。決定B：保存アプリでは利用者が通れる経路（起動時の復元、資源を持ったままの`LOAD-DICTIONARY`）を確かめる。活動中の完全復元は、PCM・タスク・窓を同時に持った状態のZigの試験を1つ加えて確かめる。試験用の入口は製品に加えない。
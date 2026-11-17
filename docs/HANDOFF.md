# ForthSigma 作業引き継ぎ

更新日：2026-11-15。現在状態はこの文書、実装経緯は各フェーズ記録とgit履歴を参照する。tqueの表示番号は振り直されるため、再開時はタスク名と親子関係で照合する。

## GitHub ActionsのEKEY最適化失敗の修正（2026-11-15）

`v0.11.0`の[Release実行](https://github.com/fukuyori/ForthSigma/actions/runs/43675216095)で、Windows・Ubuntuの`-Dcpu=baseline -Doptimize=fast`におけるP06a入力切替とEKEY UTF-8の2件が失敗。テストスクリプト移動前のコミット`4802167`で発生した。

公式配布のZig 0.17.0を`.work/ekey-ci/`へ取得し、公式indexのSHA256と照合。macOS arm64でも同じ2件を再現した。診断ログでは`{195,169}`等の入力バイトが正しいのに、デコード結果が233ではなく195となる。最小再現でも符号付きi64からu8への直接`@intCast`を含むUTF-8デコードが失敗し、0.17.1では成功した。0.17.0のLinux x86_64向けLLVM IRでは当該変換に`trunc nuw nsw`が付き、符号なしセルを経由する修正後は`trunc nuw`となることを確認した。

`src/core/event_input.zig`のイベント→バイト変換を符号なしセル経由の共通ヘルパーへ変更。Checkedビルドの範囲検査は維持する。EKEY?経由の1〜4バイト境界、不正・不完全UTF-8、後続KEYバイト保持の回帰を追加した。語義・仕様の変更はない。生成リファレンスのEKEY?使用例は新しい回帰テストの抜粋へ更新され、英日で参照先を確認してソース指紋も更新した。

Zig 0.17.0の修正後fastテストは1063成功・7 skip（コア1001成功・5 skip、ホスト62成功・2 skip）。Linux x86_64向けEKEYテストのクロスコンパイルも成功。Zig 0.17.0の通常テストも1063成功・7 skip、fast実行体のビルド、EKEYパイプ・POSIX PTY、P10統合37件が成功。文書チェック指摘0件。クロスコンパイルをWindows/Linux実機の実行結果と混同しない。証跡は`.work/ekey-ci/`の`before-0170-fast.log`・`diagnostic.log`・`cast-{before,after}.log`・`cast-0171.log`・`after-0170-fast.log`・`ir-cast-comparison.txt`と生成IR。利用者から既存`v0.11.0`タグの削除、修正のコミット、同名タグの再作成とpushを明示指示された。EKEY修正はCHANGELOGの0.11.0へ含める。公開コミットとタグの実際の状態はGit履歴・リモートを照合する。Actionsの修正後結果は別途確認する。

## テストスクリプトの配置変更（2026-11-15）

`test-*`・`verify-*`・`probe-*`と`gforth-p00/`の99ファイルを`tests/scripts/`へ移動した。実行は引き続きリポジトリルートから行う。呼出し元・文書のパスとテストのルート解決・importを更新。生成・ビルド・配布・ベンチマーク本体と文書チェックは`scripts/`に保持する。[実行例と区分](../tests/scripts/README.md)を参照。測定JSONのハッシュ対象パスと外部レビュー原文は当時の記録として保持する。

移動後にPython97ファイルの構文、リファレンス回帰5件＋動作19件、署名スクリプトのモック9件、行編集18件、P10統合37件、ランタイム13件、debug除外マトリックスの単体・ビルド・統合36件を確認して成功。文書チェック指摘0件。Linux専用ベンチマークテストはimportのみ確認し、Gforth比較・Windows専用試験は再実行していない。証跡は`.work/script-move/`。

## バージョン更新（2026-11-15）

利用者指定で製品バージョンを0.11.0へ更新し、チェックリストの表示例・ログ例・変更履歴・開発記録を更新した。過去の測定記録は変更しない。パッケージ・タグは作成していない。

## macOS P10検証と計画542の完了（2026-11-15）

macOS 27.2 arm64・Zig 0.17.1で、`16945a5`を対象に通常版・8単独機能除外版のビルド・単体・P10統合・構成間保存読込を実行し、計312件が成功した。通常単体は1062成功・7 skip。ランタイム13件、文書チェック指摘0件、実行時辞書照合・標準キー35件・出力例28件・使用例132件も成功。[macOS P10検証](MACOS_P10_VALIDATION.md)に環境・件数・実行方法を記録。証跡は`.work/p10/macos/`。

`verify-feature-matrix.py`に`--platform macos`を追加した。アプリケーション実装・版番号の変更なし。tqueをコマンドで照会し、752 → 742 → 553 → 542の順に全子の完了を照合してdoneにした。最後に542配下すべてがdone・auto100%であることを再照会した（`tasks-before.json`・`tasks-after.json`）。コミット・タグ・pushは行っていない。

今回のP10残作業は完了。VM速度改善は計画・レビューのみで試作未実施のまま。次の実装に自動着手せず、利用者の指示に従う。以下の過去の未完了記述は当時の記録であり、現在状態はこの節を優先する。

## Linuxネイティブ追加確認と元作業ツリーへの統合（2026-11-15）

利用者の#553のLinux確認依頼により、`9d26340`を基準とする別作業ツリーで実施。通常版・8単独機能除外版のLinux版Zigビルドランナー、P10計312件、境界482件、PTY/FIFO24件、POSIX統合10件、ランタイム13件、文書チェックが成功。詳細・証跡は[Linux P10検証](LINUX_P10_VALIDATION.md)。tque #754はdone・auto100%。macOS実機の#752は未実施のまま残し、#742・#553・#542を完了にはしない。

その後の利用者の統合指示により、元の`/home/fuk/source/zig/ForthSigma`を`9d26340`へfast-forwardし、Linux検証の修正・文書・`.work/p10`の成果物を反映した。元の未コミットCATCH変更はstash「Preserve pre-integration CATCH changes 2026-11-15」と`/tmp/ForthSigma-catch-before-integration.patch`に退避。最新mainに別実装のCATCH再帰対策があるため古い本体差分は重ねず、元の深い再帰・SYNONYM/EXECUTE/DEFER・上限捕捉・ローカル復元の回帰テストを追加保持した。

`verify-feature-matrix.py`へLinux直接実行を追加し、glibcで不定となるシグナルマスク予約領域の比較をテストから除いた。日本語説明への影響なしと確認しソース指紋を更新。今回の変更には検証基盤・回帰テスト・記録を含む。統合後は1063件成功・6 skip、通常ビルド・P10統合37件・文書チェック指摘0件。参照行番号も更新した。別worktreeの全変更と検証成果物を元フォルダーに保持し、別worktreeは削除済み。詳細はLinux P10検証記録を参照。

## VM速度改善の計画・レビュー

利用者の依頼で[速度改善計画](VM_PERFORMANCE_PLAN.md)を作成した後、Claude Codeへレビューを依頼し、指摘をソースと照合して改訂、限定的な再確認まで完了した。[採否と結果](VM_PERFORMANCE_REVIEW.md)、[初回原文](VM_PERFORMANCE_CLAUDE_REVIEW.md)、[再確認原文](VM_PERFORMANCE_CLAUDE_FOLLOWUP.md)を別々に保存。モデル表示claude-sonnet-5-5、実際のツールは初回Read/Grep計10回・再確認計5回で、コマンド・編集はない。再確認は「重大な残存問題なし、条件付きで安全な実験計画」との結果で、改善を保証するものではない。

計画は、同一バイナリーA/Aと生成コードを確認した後、Runningを値で渡して局所保持する小規模案を最初に検証する。無条件の外側書戻しを削除し、エラー時PC・全ヘルパーの状態更新・CATCH復帰を維持する。停止検査の移動は全副作用境界を示せる場合だけ。境界退出方式へ自動的に拡大せず、VM複製・機能削除・JIT・アセンブラーは見送る。CATCH専用測定、サイズ各1%以内、メモリー容量を増やさないことも基準にした。

続いて利用者の指示でagy CLI 1.5.9にもレビューを依頼し、Gforth固定版c479e1eのengine・threaded・prim・exceptを[参照調査](GFORTH_VM_REFERENCE.md)へ整理した。[agy報告](VM_PERFORMANCE_AGY_REVIEW.md)と[採否](VM_PERFORMANCE_REVIEW.md)を保存。実際の履歴はread_file 14回・13ファイル、SUCCESS。モデル名は結果に明示なし。コマンド・編集のツール呼出しはなく、ソースハッシュも照合した。CLIのplan指定はslash禁止との併用で無効警告があり、実際はrequest-reviewだったため、plan強制とは扱わない。

agy指摘は、CATCH成功用0の容量不足＋外側CATCHなしでの失敗PC／バックトレース、BYE時の全継続解除、外側・内側resumeCatchの状態引渡し、δ_iの分母固定などを反映した。生成コードで過剰な展開が確認できた場合だけ、例外ヘルパーの非インライン化・cold配置を試すA2も追加。Gforthの局所状態・例外境界の考え方を参考にするが、GPLコード転用・生スタック混在・computed goto・TOS全面キャッシュは行わない。改善率の保証はなく、指摘反映後の追記全体を再レビュー済みとも扱わない。

原因調査の[根拠データ](measurements/2026-11-15-vm-diagnosis.json)も共有用に保存。f1140c7全体の変更で整数演算+59.0%、LOOP+37.9%を再現したが、個別の生成命令の原因は未特定。改善案の試作・A/A校正・新たな生成コード調査はまだ行っていない。本改善計画のtque登録・完了操作も未実施。測定・計画・レビューの文書と根拠データは、測定器テストの修正とまとめて記録する。

## 最新の測定結果

2026-11-17、利用者の指示で[サイズ測定・速度比較](SIZE_SPEED_MEASUREMENT.md)を同じ条件で取り直し、[生データ](measurements/2026-11-17-size-speed.json)を保存した。対象はSigma 0.11.0、`f1d641c`のアプリケーション実装。12構成のビルドと起動確認・機能除外の確認が両OSで成功した。通常版はWindows 1,809,408バイト、Linux musl 1,891,456バイト（前回比+2,560、+3,456バイト）。グラフィックス・浮動小数点なしはWindows 1,110,528バイト、Linux 1,139,040バイト。速度はWSL2のCPU0で8カーネルを各1億反復・7回測定し、全チェックサムが一致した。CPU時間の中央値比の幾何平均は、SigmaがGforth 1.0.2通常版の2.59倍、fast版の7.46倍。Sigmaの所要時間は前回比で8項目すべて短くなり、15.8〜34.9%、幾何平均25.7%の短縮だった。2時点の実行体全体の比較であり、個々の変更の寄与は分離していない。実表示・音声再生、Windows版の速度は未確認。以下は前回の記録である。

2026-11-15、利用者の指示で[サイズ測定・速度比較](SIZE_SPEED_MEASUREMENT.md)を実施し、[生データ](measurements/2026-11-15-size-speed.json)を保存した。対象は`50e661e`のアプリケーション実装。Zig 0.17.0、fast・baseline CPU・stripでWindows/Linuxの通常・浮動小数点なし・グラフィックスと浮動小数点なし・グラフィックス単独除外・サウンド単独除外・最小の12構成をビルドし、各起動確認が成功した。通常版はWindows 1,806,848バイト、Linux musl 1,888,000バイト。利用者指定のグラフィックスなしはgraphics=falseとfloat=falseを同時指定し、Windows 1,107,968バイト、Linux 1,135,488バイト。追加構成の起動と機能除外も確認済み。 グラフィックス単独除外はWindows 1,554,944バイト、Linux 1,646,240バイト。サウンド単独除外はWindows 1,724,416バイト、Linux 1,791,576バイト。両単独除外で浮動小数点の動作を確認。サウンド単独除外では画像生成も成功した。浮動小数点だけを外した構成の整数描画・画素読戻しも両OS計4ケース成功。実表示・音声再生は未確認。

速度はWSL2のCPU0で8カーネルを各1億反復、ウォームアップ1回を除外して7回測定し、全チェックサムが一致した。起動・コンパイルを除いたCPU時間の中央値比の幾何平均は、SigmaがGforth 1.0.2通常版の3.50倍、fast版の10.06倍。実用全般の速度ではなく、旧表からの性能退行とも断定しない。旧Gforth 0.7.9はlibgfdisasm2.la欠落で起動失敗し除外。環境やインストールは修復していない。

測定器のテストがPythonへ非対応の-eを渡していたため、`tests/scripts/test-benchmark-runtime.py`のテスト用起動方法を修正し3件成功。測定本体・アプリケーション実装は変更していない。記録対象は測定レポート・生JSON・改善計画・レビューと採否・索引・実装ノート・本引継ぎ・上記テスト。実行体・ビルドログ・事前試行は`.work/measure-20261115/`。

## 直前の見送り検討と公開記録

利用者の最終方針は「システムが巨大になるなら見送る」。582（アセンブラー8語）、583（TRY系5語）、584（Gforth固有ブロック拡張9語）は、この方針に基づき対応を見送った。各タスクは「対応要否の検討」を完了したもので、機能を実装したという意味ではない。利用者の指示で結論をタイトルへ記載し、3件ともdone・auto100%を今回再照会した。当初の584→583という実装案は採用しない。具体的な用途と新たな指示がない限り実装を再開しない。

ワードリファレンスの作成・実装照合・Claude Codeレビュー修正は`7b9e4dd`へ、582〜584の見送り記録は`50e661e`へコミット・push済み。今回の測定後にもorigin/mainの実際の先端が`50e661e9758cf41234da84946204930bb09a09af`であることを照合した。次の4文書はその公開記録であり、未追跡ファイルではない。

| ファイル | 公開時の変更 | 内容 |
| --- | --- | --- |
| `docs/GFORTH_ASSEMBLER_REVIEW.md` | 新規追加 | 582の8語を見送る理由、VM・ABI・保存・寿命管理への影響 |
| `docs/GFORTH_DEFERRED_WORDS_REVIEW.md` | 新規追加 | 583・584の検討、最終の見送り判断、検討完了の記録 |
| `docs/GFORTH_WORD_PHASES.md` | 更新 | 582〜584の結論と検討書への参照 |
| `docs/HANDOFF.md` | 更新 | 本引継ぎ |

検討書2件も含めて公開済み。

次に残る実装計画側の確認はmacOS実機のP10検証（今回752）。今回の再照会では742がtodo・auto90%、親553がtodo・auto95%、計画542がtodo・auto99%、752がtodo・auto0%。753「すべてのワードの説明をドキュメント化する」はdone・auto100%。582〜584は542の外にある検討項目であり、完了にしてもP10・542の完了にはならない。

見送り検討時の作業は静的調査、文書編集、tqueの更新・再照会で、その段階ではビルド・実行試験は再実施していない。その後に行ったサイズ・速度測定は冒頭のとおり。以下のOS別件数や全ワードの実行確認は、前の実装・検証で得た記録であり、今回すべてを再実行したという意味ではない。

## 現在状態

- 582は機械語実行・CPU/OS別ABI・保存と寿命管理への影響から、規模を抑える方針に基づき8語とも対応を見送ると決定。[アセンブラー対応検討](GFORTH_ASSEMBLER_REVIEW.md)に記録し、利用者の指示でtqueのタイトルへ結論を記載。検討完了としてdone・auto100%を再照会した。実装変更はなく、実装完了を意味しない。

- 583・584は、利用者の「システムが巨大になるなら見送る」という条件に基づき全面対応を見送った。利用者の指示で結論をtqueのタイトルへ記載し、検討完了として両方done・auto100%を再照会。実装完了ではない。VMの例外継続とブロックファイル管理への影響を[対応検討](GFORTH_DEFERRED_WORDS_REVIEW.md)に記録。当初の実装順案を再開指示として扱わない。

- 「すべてのワードの説明をドキュメント化する」（今回照会時753）は完了(auto100%)。[全ワードリファレンス](WORD_REFERENCE.ja.md)と[読み方・使用例](WORD_REFERENCE_GUIDE.ja.md)を英日で作成。全1,503項目に日本語説明・使用例・注意点を収録。全7語彙の実行時辞書1,463項目と構文・ローカル宣言40項目を照合し、記載漏れなし。単独使用例132件と出力確認例28件、標準キー値35件が成功。`zig build test`も成功。翻訳元の変更・説明や使用例の欠落を検出するチェックを追加。実装照合・Claude Codeレビューの指摘を修正し、動作回帰19件と選択・指紋の回帰5件も成功。詳細と検証の限界は[収録・検証記録](WORD_REFERENCE_STATUS.md)と[修正・レビュー記録](WORD_REFERENCE_REVIEW.md)を参照。

- P10の742は作業中。追加確認749〜751はWindows・WSLとも通常37件＋8単独機能除外268件＋構成間イメージ読込7件、各OS312件が成功。通常版最終ビルドとHELP・英日文書整合も完了、文書チェック指摘0件。[P10実施記録](P10_IMPLEMENTATION.md)。macOSの752も今回完了（冒頭参照）。

- Windows確認は完了。通常1058成功・10 skip、最小582成功・457 skip、通常ビルド/freestanding、統合24件、追加境界378件、コンソール36件と既存ブロック/EKEY/ランタイム13件が成功。利用者のIME変換・全角/絵文字編集・表示確認も「ok」の回答で完了。tque537〜540・718・719とWindows専用確認はdone(auto)。[Windows検証記録](WINDOWS_VALIDATION.md)。
- Windows追加修正は既存ファイルのCRT属性保持とSYSTEM後のコンソールモード復元。WSL専用728〜741も今回すべて完了(auto)とし、全子の完了を再照会して607を完了にした。P10・542全体の統合条件は残る。[タスク対応表](PLATFORM_TASK_AUDIT.md)。
- WSL2 Ubuntuは最新ソースで通常1062成功・6 skip、最小586成功・453 skip、境界482件、PTY/FIFO24件、P01〜P03行列15,371件、CLI9件、EKEYのパイプ/PTY、SHOW PTY20件、POSIX統合10件等が成功。行編集18件の前回成功記録も維持。初期スタック1MiBでCLI/ランタイム/保存実行統合が成功。WindowsでLinux用にコンパイルしてWSLで実行した。指定Gforth比較・Linux版Zigのビルドランナーは今回の結果に含めない。[WSL検証記録](WSL_VALIDATION.md)。
- P00・S01・P01〜P09と依頼済みレビューは完了。P09は全50語、tque576・577・578・552・701が完了(auto)。P09レビュー修正は`a76d000`、追加examples・文書は`7ce9a4f`でpush済み。[実装記録](P09_IMPLEMENTATION.md)・[レビュー](P09_REVIEW.md)。
- 698も調査・修正・検証が完了(auto)。明示STDOUT書込みとSYSTEM/SH/エディタ実行後にSHOWが文字を上書きする問題を修正した。修正と本引継ぎは対応するコミットに含む（git履歴参照）。[修正記録](OUTPUT_ACTIVITY_FIX.md)。
- macOSの698修正時の検証は通常1061件通過（6 skip）、最小構成585件通過（453 skip）、freestanding確認、通常ビルド、半ブロック/SixelのmacOS疑似端末20ケース、P09b比較・エディタ・保存復元確認が通過。証跡は`.work/698-*`。Windows/Linux実機確認は含まない。
- tque階層121 → 415 → 542 → 553（P10）→ 742。742・553・542は今回done・auto100%。743〜754もdone（今回再照会）。Windows/Linuxの基礎確認607と引用符付きEDITORの702は完了。
- `docs/NATIVE_WINDOW_STUDY.md`と`examples/graphs.fs`・`graphs-tk.fs`および関連文書はコミット済み。ネイティブウィンドウの実装検討は後回し。

## 次の作業と進め方

- ワード説明の文書化は完了。追加・修正時は日本語説明と使用例も更新し、`python scripts/word-reference.py --check --sigma zig-out/bin/sigma.exe`で全件照合する。翻訳元が変わった場合は日本語説明を確認してから`--record-reviewed-sources`で元ソースの指紋を更新する。使用例の抜粋は、参照先の準備・期待されるエラーを含む文脈と区別して扱う。

1. P10のmacOS検証752と計画542は完了。再確認時は[macOS検証記録](MACOS_P10_VALIDATION.md)と`--platform macos`を使用する。VM速度改善の試作は未着手であり、次の作業は利用者の指示に従う。
2. Windows・WSL追加確認749〜751は完了。追加ケースの全構成再実行、WSL構成間イメージ読込、HELP変更後ビルド・文書整合を再び未実施扱いにしない。検証範囲と証跡は[P10実施記録](P10_IMPLEMENTATION.md)を参照する。
3. 作業が完了した時点で証跡を文書へ記録し、該当するtqueタスクをdoneにする。タスク名は作業内容だけとし、「実施済」「未実施」「残件」などの状態を付けない。状態は完了フラグ、進捗はautoで管理する。今回752・742・553・542は完了条件を確認してdone・auto100%にした。
4. P09追加の組込み語によるABI変更があり、以前のイメージは再作成する。698修正による追加ABI変更はない。HANDOFFは現在状態・次の作業・制約に絞り、詳細は各検証記録へ記載する。

## 再開時の成果物と実行方法

- 今回の測定・計画作成開始時のHEADとorigin/mainは`50e661e`。全ワードリファレンスとHELP修正は`7b9e4dd`、Windows/WSL変更は`eaf0fe1`、582〜584の見送り記録は`50e661e`で公開済み。今回の成果物は冒頭を参照。再開時は`git status --short --branch`とリモートの実際の先端を再照会し、既存変更を保持する。
- P10用スクリプト：`tests/scripts/verify-p10.py`（通常/除外版統合）、`tests/scripts/verify-feature-matrix.py`（8構成のビルド・単体・統合）、`tests/scripts/verify-p10-cross-build.py`（通常版→除外版の保存イメージ読込）。
- 既存除外版実行体：`.work/p10/windows/no-<機能>/bin/sigma.exe`、`.work/p10/linux/no-<機能>/bin/sigma`。機能は`float files help tools image graphics audio debug`。再実行前に対象ソースとビルド時点を照合する。
- 統合検証：`python tests/scripts/verify-p10.py --sigma <実行体> --disabled <除外機能> --output <JSON>`。通常版では`--disabled`を省略。Linux実行体はWSLからLinux側のパスで指定する。
- 構成間読込：`python tests/scripts/verify-p10-cross-build.py --default <通常版実行体> --matrix <.work/p10/windows または linux>`。WSLではWSL側のPythonから実行する。
- 証跡：`.work/p10/windows-default.json`、`linux-default.json`、両OSの`matrix.json`と構成別ログ、Windowsの`cross-build.json`、`.work/p10-docs.log`。`complete: true`と件数、実際のログを照合する。
- 今回は追加の実行検証まで完了。`.work/p10-refresh.log`と更新済みJSONが最新のWindows・WSL追加確認結果。最終ビルドは`.work/p10-windows-final-build.log`・`.work/p10-linux-final-build.log`、最終文書チェックは`.work/p10-docs-final.log`。

## 制約

- コミット・タグ・pushは、その依頼で明示された場合だけ行う。通常の実装継続からは推定しない。
- Windows/Linux確認は607配下で別管理し、パイプ/SH-GETは695、P06cは696。Windowsでの今回の確認範囲は上記記録を参照。freestandingビルド確認は実機実行ではない。
- 仕様や意図に不明点がある場合は実装前に問い合わせる。質問は通常のメッセージで行い、Queued follow-up inputsや専用質問ツールを使わない。比較用Gforth固有の不正アクセスや未定義動作は模倣しない。GPL実装コードを転用しない。
- 標準EKEYS（固定wid3）とGRAPHICSのキー値・検索順を混同しない。端末EKEY/EKEY?/KEY-IORのCtrl+Cは割込み(-28)、ファイル/パイプのバイト3は文字3。EKEY EOFは承認によりK-EOFへ変更済み（KEYは-262、KEY-IORは-512）。
- 辞書イメージはSIGIMG45/46/47。旧形式・不一致ABIは拒否する。アドレスは明示的な型付き登録で再配置し、生セルから推測しない。
- パッケージはスクリプト確認以外で作成しない。版番号を変える場合は[更新チェックリスト](version-update-checklist.md)に従う。
- リポジトリ外・外部データは利用者の許可ルールに従う。以前のセッションでは指定Gforth・tque・Gitリモート・依頼されたClaude Code／agyレビューへのアクセスが許可されていた。今回のセッションではtqueコマンドの使用を明示許可された。他の外部アクセス許可へ拡大解釈しない。
- `.work/`・`.zig-cache/`・`.zig-global-cache/`はGit管理外の検証成果物。clean/resetで破棄したりコミットへ混ぜたりしない。

## 検証と参照先

通常確認は`zig build test`と`zig build`。最小構成や追加検証は変更内容に応じて行う。同じ検証用ファイルを使うテスト同士は同時実行しない。比較前には実行体をビルドする。

指定Gforthはコミット`c479e1eec66dd57a2441c3020177267ba70d3bdc`の`.work/gforth-audit/gforth-build/`（Gforth1.0.1、GCC16再構築）。ローカル成果物がない場合は、過去の実測を実施済みと推測しない。

- [基本仕様・比較方針](GFORTH_P00_SPEC.md)、[フェーズ表](GFORTH_WORD_PHASES.md)、[決定事項](DECISIONS.md)
- [S01レビュー](S01_REVIEW.md)、[P01レビュー](P01_REVIEW.md)、[P02記録](P02_IMPLEMENTATION.md)、[P03記録](P03_IMPLEMENTATION.md)、[P04記録](P04_IMPLEMENTATION.md)
- [P05記録](P05_IMPLEMENTATION.md)・[レビュー](P05_REVIEW.md)、[P06記録](P06_IMPLEMENTATION.md)・[レビュー](P06_REVIEW.md)、[P07記録](P07_IMPLEMENTATION.md)、[イメージ形式](IMAGE_FORMAT45.md)

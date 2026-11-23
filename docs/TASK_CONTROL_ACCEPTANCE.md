# タスク制御の受け入れ条件

作成日：2026-11-23。対象：1048配下の1377（06-A、親1054）。
状態：受け入れ計画であり、全試験は未実施である。方式・API・上限値の採用を確定する文書ではない。

## 1. 根拠と適用範囲

主たる根拠は `docs/TASK_CONTROL_DETAILED_PLAN.md:419`〜443の必須検証項目である。設計・実装・試作の役割は同文書の2節・5〜12節、完了判定は `docs/TASK_CONTROL_DETAILED_PLAN.md:310`〜326・483以降に従う。補完計画の「完了確認」（`docs/TASK_CONTROL_PLAN.md:49`〜55）とも照合する。

関連する根拠は以下のとおりである。

- `docs/CORE_EXTENSION_DETAILED_DESIGN.md:769`〜826：方式比較、状態、隔離、複合待機、通常ビルドの取消しの設計案である。
- `docs/CORE_EXTENSION_WORKER_STATE_AUDIT.md:10`・234・331・436〜438：直下フィールドの列挙だけでは完了せず、Writer・内部参照・共有状態まで再帰監査する方針である。
- `docs/CORE_EXTENSION_REVIEW_RESPONSE.md:14`〜16・49〜54：R01〜R03、F01〜F06を追跡する。文書への反映を実装の成立や再承認とは扱わない（同文書:56）。
- `docs/CORE_EXTENSION_DESIGN_DECISIONS.md:9`・22〜27：既存の通常ループ方針と、方式・取消し・Snapshot・許可検査の確定ゲートである。

現在の実装を直接確認した範囲では、数える実行経路の選択はdebug条件に依存し（`src/forth.zig:1877`〜1878）、CATCHからの伝播例外はQuit/StepLimitである（`src/forth.zig:1898`、`src/core/words_system.zig:124`）。これを新しい取消しの合格証拠とはしない。その他の実装全体の成立、StateやWriterの最新件数は本作業では未確認である。

1348〜1383のタイトル・親・備考・直接依存は2026-11-23に `tque show` で確認した。内訳は1049配下1348〜1357、1053配下1358〜1362、1050配下1363〜1367、1051配下1368〜1372、1052配下1373〜1376、1054配下1377〜1383である。以下の完了判定はその作業内容を受け入れ条件へ展開したものであり、tqueの変更や完了登録ではない。

## 2. 表の読み方と共通完了条件

「再現」は偽時計・偽起床・キュー操作・停止位置の制御・割当失敗注入等による再現試験である。実際の経過時間を測らず、イベント順序・状態・参照・処理回数を検査する。「実機」は実OS資源・画面・端末での試験である。構成検査ではビルド・語登録・文書照合も併記する。静的照合だけでは実機の合格にならない。

担当タスクと機械は各行に組で明示する。1382・1383以外のタスクはWindows機（WSLのLinuxを含む）で実施する。Windows・WSLのLinuxの実機受け入れは1382、macOSの再現試験・実機受け入れはすべて1383がMac実機で担当する（詳細計画の機械別分割は `docs/TASK_CONTROL_DETAILED_PLAN.md:413`・417、本書の再現試験への適用は今回の利用者指示による）。WSLの結果をその他のLinux環境の実機結果へ拡張しない。再現試験も実行したOSを分けて記録する。クロスコンパイルは実機合格に含めない（`docs/TASK_CONTROL_DETAILED_PLAN.md:441`〜442）。

- 全行の状態は「未実施」である。各機械の実行証拠が揃うまで、他OSの合格を転記しない。
- 実施時にはAC-ID、OS・Zig版、ソース識別子、実行体、構成、コマンド、入力、順序、期待値、実際の状態・診断、証拠の保存先を残す。資源・画面・端末の試験はbackendと能力も残す。
- 設計判断に依存する行は、採用した契約と判断記録を先に参照する。未決の契約に独自の期待値を置かない。対象外となる方式固有条件は理由と範囲変更の判断を残し、合格に数えない。
- 再現試験は通知だけでなく台帳・結果・参照を検査する。実機試験は操作に対する入力・描画・I/Oの進行と回収結果を記録し、応答時間の保証へ置き換えない。
- 成功・失敗・取消し・復元拒否・停止不能を区別する。停止不能を通常回収成功に数えない。
- 速度・時間の測定は本作業に含めない。1356は別作業であり、事前の利用者確認が必要である（`docs/TASK_CONTROL_DETAILED_PLAN.md:447`）。
- 1037で利用者が不要としたDwmFlush非対応実環境テストは受け入れ項目に含めない（`docs/TASK_CONTROL_DETAILED_PLAN.md:443`）。能力を偽装した未対応経路の再現試験とは区別する。

## 3. 受け入れ表

各行の末尾の根拠は詳細計画の該当行である。担当欄には実装・試作・検証に対応するタスクと、その実施機械を併記する。Windows側の実装・試作内検証と1382の実機受け入れは別に証拠を残す。macOS側は再現試験を含め1383が実施する。

| ID | 分類 | ケース | 合格条件 | 試験の種類 | 実施する機械 | 担当タスク・機械 | 状態 | 根拠 |
|---|---|---|---|---|---|---|---|---|
| AC-01 | 通常ビルド | debug=falseで有限計算・無限ループを取消す | debug予算に依存せず停止し、取消し要求と停止完了を区別する。タスク固有の取消しが他タスクやRuntime全体を取り消さない | 再現：確認地点・要求順序を制御 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1352：Windows機（WSLのLinuxを含む）；1373：Windows機（WSLのLinuxを含む）；1376：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:425・174・238〜248 |
| AC-02 | 通常ビルド | 通常構成の実タスクを取消し、メインを操作する | 停止と回収を確認し、メインが入力と描画を処理し続ける | 実機：OSスレッド・端末・画面 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1373：Windows機（WSLのLinuxを含む）；1380：Windows機（WSLのLinuxを含む）；1382：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:425 |
| AC-03 | 実行文脈 | 入れ子、EXECUTE、CATCH、THROW、ネイティブ再入、specialize/inline後のOp | 許可時はワーカー文脈・取消し・権限検査を保持し、取消しをForthエラーやiorへ変換して握り潰さない。拒否時は入口または実行境界で拒否する | 再現：再入先・取消し位置を制御 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1349：Windows機（WSLのLinuxを含む）；1351：Windows機（WSLのLinuxを含む）；1352：Windows機（WSLのLinuxを含む）；1360：Windows機（WSLのLinuxを含む）；1373：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:426・263〜268 |
| AC-04 | 隔離 | ワーカーの変数・ヒープ・出力変更、出力満杯 | メインと他タスクの値・出力を変更しない。専用Writerの出力上限超過を診断し、メインへ逃がさない | 再現：専用バッファ・callback到達検査 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1350：Windows機（WSLのLinuxを含む）；1353：Windows機（WSLのLinuxを含む）；1358：Windows機（WSLのLinuxを含む）；1361：Windows機（WSLのLinuxを含む）；1362：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:427・168〜178 |
| AC-05 | 隔離 | 実スレッドで複数タスクとメインを実行する | メインの端末・ファイル・表示・音の所有を侵害せず、共有状態への不許可到達がない | 実機：OSスレッド・資源・出力先 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1353：Windows機（WSLのLinuxを含む）；1358：Windows機（WSLのLinuxを含む）；1380：Windows機（WSLのLinuxを含む）；1382：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:427・74〜91 |
| AC-06 | 禁止語 | 入口内部・直接builtin・インライン・動的行先の入力/UI/SYSTEM/MS/辞書変更/タスク投入・待機 | 許可集合外を実行前または境界で拒否する。null callback時の既定動作も迂回経路にならない | 再現：静的走査・実行境界・callback追跡 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1350：Windows機（WSLのLinuxを含む）；1351：Windows機（WSLのLinuxを含む）；1360：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:428・194〜200・135〜142 |
| AC-07 | Snapshot | 取得後の変数変更とタスクの書込み | 指定版の保存対象と投入データだけを利用し、後のメイン変更を自動反映せず、結果コピー以外はメインへ戻さない | 再現：取得・変更・投入の順序を固定 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1354：Windows機（WSLのLinuxを含む）；1359：Windows機（WSLのLinuxを含む）；1361：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:429・182〜191 |
| AC-08 | Snapshot | FORGET/MARKER/完全復元、古い入口、実行中の版保持 | D03で決めた失効・入口解決に従い、実行中の版を早期解放しない。復元時の形状・builtin・ヒープ・再配置・最適化後コードを検査する | 再現：辞書変更・復元失敗・参照解放を制御 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1354：Windows機（WSLのLinuxを含む）；1359：Windows機（WSLのLinuxを含む）；1362：Windows機（WSLのLinuxを含む）；1374：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:429・190〜211 |
| AC-09 | 結果 | 0バイト、採用上限ちょうど、上限超過、負の長さ、不正範囲、スタック深さ違反 | 長さ・範囲・深さ・上限をコピー前に検査し、規約違反は失敗として安全に回収する。入力領域・静的領域を指す有効な結果もコピー完了まで保持する | 再現：ABI境界・割当失敗を注入 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1361：Windows機（WSLのLinuxを含む）；1365：Windows機（WSLのLinuxを含む）；1367：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:430・144〜148 |
| AC-10 | 結果 | 容量不足後の再取得、反復照会、失敗・取消しの診断 | 非消費の照会・必要量の返却・結果保持が採用契約どおりであり、失敗/取消し時の取得と診断上限も契約に一致する | 再現：取得順序・容量を制御 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1363：Windows機（WSLのLinuxを含む）；1365：Windows機（WSLのLinuxを含む）；1367：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:430・219〜225 |
| AC-11 | 状態競合 | 完了・失敗・取消し・RELEASEの各順序と同時成立 | D04/D05どおりに終端が一度だけ確定する。確定後に状態を変えず、二重の終端通知・二重解放がなく、実行側参照を保持する | 再現：終端化・解放の順序を制御 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1363：Windows機（WSLのLinuxを含む）；1364：Windows機（WSLのLinuxを含む）；1366：Windows機（WSLのLinuxを含む）；1367：Windows機（WSLのLinuxを含む）；1373：Windows機（WSLのLinuxを含む）；1376：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:431・215〜230 |
| AC-12 | 台帳 | 台帳満杯、世代枯渇、別種・別owner・古いID | 別タスクに操作が届かず、無効理由を診断する。ID再利用後も旧IDを拒否する | 再現：台帳状態・世代を注入 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1364：Windows機（WSLのLinuxを含む）；1367：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:432・224〜225 |
| AC-13 | 台帳・逆圧 | 入力確保失敗、キュー満杯、バッファ満杯、登録失敗 | 成功前にハンドルを公開しない。失敗時は呼出し側入力の所有を奪わず、部分確保を回収し、原因を区別する | 再現：割当・登録・キュー操作を制御 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1361：Windows機（WSLのLinuxを含む）；1364：Windows機（WSLのLinuxを含む）；1366：Windows機（WSLのLinuxを含む）；1367：Windows機（WSLのLinuxを含む）；1371：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:432・219〜225 |
| AC-14 | 通知 | 通知併合・通知失敗・通知だけの取りこぼし | 完了状態と結果の公開順序を守り、再照会で回復する。通知回数を結果件数の唯一の根拠にしない | 再現：偽起床・完了領域公開順を制御 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1366：Windows機（WSLのLinuxを含む）；1367：Windows機（WSLのLinuxを含む）；1368：Windows機（WSLのLinuxを含む）；1372：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:433・176〜178・223 |
| AC-15 | 複合待機 | 既成立、登録前・登録直後・解除中の成立 | 世代観測→登録→再確認→待機→再取得で取りこぼさず、解除・解放後に対象を参照しない | 再現：偽起床・登録位置を制御 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1368：Windows機（WSLのLinuxを含む）；1369：Windows機（WSLのLinuxを含む）；1372：Windows機（WSLのLinuxを含む）；1374：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:434・283〜285 |
| AC-16 | 複合待機 | 入力・I/O・終端・期限・取消しの同時成立、偽起床の反復 | 単一の単調時計期限を維持し、採用した優先規則と返却契約に一致する。偽起床で期限を延長しない | 再現：偽時計・偽起床 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1368：Windows機（WSLのLinuxを含む）；1369：Windows機（WSLのLinuxを含む）；1372：Windows機（WSLのLinuxを含む）；1373：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:434・279〜285 |
| AC-17 | 複合待機・描画 | 描画対象番号、不明/未対応能力、close、描画完了と物理提示 | 登録時に対象・能力・終端を検査し永久待機を作らない。描画完了・次時刻・物理提示を区別する | 再現：偽backend・偽完了通知 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1368：Windows機（WSLのLinuxを含む）；1370：Windows機（WSLのLinuxを含む）；1372：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:434・287〜290 |
| AC-18 | 複合待機 | 実入力・I/O可用・タスク終端・期限・利用可能な描画完了の接続 | 一つの待機が他の供給元の進行を止めず、closeを含む実backendの能力に従って返る | 実機：OS資源・端末・対応画面 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1369：Windows機（WSLのLinuxを含む）；1370：Windows機（WSLのLinuxを含む）；1380：Windows機（WSLのLinuxを含む）；1382：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:434・279〜290 |
| AC-19 | 公平性 | 入力・I/O・完了通知の連続供給、満杯時の再投入 | 一巡ごとの上限と採用した投入順に従って他の供給元も進み、無期限占有を生じない。初期版のワーカー間待ちを拒否し、全ワーカー待ちによる後続仕事の停止を作らない | 再現：供給キュー・巡回順・処理回数を制御 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1371：Windows機（WSLのLinuxを含む）；1372：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:435・275〜277 |
| AC-20 | 公平性 | 実入力・I/O・完了が続く状態で操作する | 入力・出力排出・描画・結果回収がそれぞれ進む | 実機：端末・画面・I/O | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1371：Windows機（WSLのLinuxを含む）；1380：Windows機（WSLのLinuxを含む）；1382：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:435・438 |
| AC-21 | 回収 | 成功・失敗・取消し後のVM連続再利用 | State・Writer・入力・結果・Snapshot参照が前タスクから残らず、他タスクの参照を壊さない。本実装の取消し経路でも再検証する | 再現：資源台帳・参照・初期状態を照合 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1358：Windows機（WSLのLinuxを含む）；1362：Windows機（WSLのLinuxを含む）；1376：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:436・207〜211 |
| AC-22 | 終了 | 例外・QUIT/BYE・所有者終了・完全復元 | D05の所有範囲と採用順序で停止・待機解除・回収する。活動中の完全復元を安全に拒否し、二重解放・解放後参照を生じない | 再現：終了位置・復元・エラーを注入 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1363：Windows機（WSLのLinuxを含む）；1374：Windows機（WSLのLinuxを含む）；1376：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:437・238〜248 |
| AC-23 | 終了・停止不能 | 確認地点のないネイティブ処理・同期OS待機を模擬する | 強制スレッド終了で成功扱いせず、参照対象を保持し未回収を診断する。独立した子終了要求・音停止・端末復元の試行と失敗を区別する | 再現：偽時計・停止不能・後始末失敗を注入 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1375：Windows機（WSLのLinuxを含む）；1376：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:246〜248、docs/CORE_EXTENSION_REVIEW_RESPONSE.md:52 |
| AC-24 | 終了・回収 | 実タスク・I/O・子プロセス・音・表示と終了する | タスク終端、子終了、出力終端、表示完了を混同せず、定義した所有資源を回収し端末を復元する。通常回収で残存タスク/スレッド/子を生じない。停止不能経路は未回収と保持対象を記録する | 実機：OS資源・画面・端末。停止不能ケースは隔離したホストで実行 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1374：Windows機（WSLのLinuxを含む）；1375：Windows機（WSLのLinuxを含む）；1376：Windows機（WSLのLinuxを含む）；1382：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:436〜437、docs/TASK_CONTROL_PLAN.md:49〜55 |
| AC-25 | 結合 | 経路探索・マップ生成・TUI検索中の要求差替えとI/O | 入力・描画・I/O・結果回収を続け、版/要求の古い計算結果を新しい画面へ適用しない。失敗・取消しも表示契約に従う | 実機：利用例・端末・画面・OS資源 | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1380：Windows機（WSLのLinuxを含む）；1382：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:438・18〜22 |
| AC-26 | 構成 | debugなし、extensionなし、graphics/audio/files等の代表構成 | 1378で確定するマトリクスに従って語の有無・内部依存を検査し、独立選択と単一VMの既存動作を壊さない | 再現：構成別ビルド・語登録・既存回帰試験 | Windows機（Windows・WSLのLinux） | 1378：Windows機（WSLのLinuxを含む）；1381：Windows機（WSLのLinuxを含む） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:439 |
| AC-27 | 構成 | macOSでの代表構成と通常ビルド | 採用した構成で実行し、利用できる語と依存が契約に一致する。構成ごとの実行範囲・未確認範囲を記録する | 実機：構成別の実行体・端末・対応画面 | Mac実機（macOS）。1378の計画作成はWindows機（WSLのLinuxを含む） | 1378：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:439・442 |
| AC-28 | 公開語・文書 | 確定した公開語、スタック効果、状態・エラー・寿命・構成 | 実装・英日HELP・全語リファレンス・英日READMEが一致し、停止不能・未対応・未確認を説明する | 再現：語登録/HELPの照合と文書検査（偽時計は不要） | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1379：Windows機（WSLのLinuxを含む）；1381：Windows機（WSLのLinuxを含む）；1382：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:292〜308・323、docs/TASK_CONTROL_PLAN.md:49〜55 |
| AC-29 | 通常経路への影響 | debug=falseの通常ループの生成コードとサイズ | 変更前後の逆アセンブルを比較し、通常ループ方針との整合をD01で判断する。サイズ一致だけを不変の証明としない | 再現：同一構成の静的生成物比較（時間測定なし） | Windows機（Windows・WSLのLinux）、Mac実機（macOS） | 1355：Windows機（WSLのLinuxを含む）；1357：Windows機（WSLのLinuxを含む）；1383：Mac実機（macOS） | 未実施 | docs/TASK_CONTROL_DETAILED_PLAN.md:257・270〜271 |

13節の分類との対応は、通常ビルド=AC-01/02、実行文脈=AC-03、隔離=AC-04/05、禁止語=AC-06、Snapshot=AC-07/08、結果=AC-09/10、状態競合=AC-11、台帳=AC-12/13、通知=AC-14、複合待機=AC-15〜18、公平性=AC-19/20、回収=AC-21/24、終了=AC-22〜24、結合=AC-25、構成=AC-26/27である。AC-28/29は公開・既存方針との整合を補完する。

## 4. 子タスクの完了判定と対応

計画・監査・仕様タスクの完了は、対応ACの試験合格そのものではない。実装担当は対応ACの検証手順と証拠を引き継ぎ、再現試験担当・実機担当は実施範囲を明記する。以下は完了判定用の対応表であり、依存関係の新設ではない。

| tque（確認した親） | 作業 | 完了判定 | 対応AC |
|---|---|---|---|
| 1348（1049） | 01-A 方式比較 | 利用例・非目標・5方式・R01〜R03/F01〜F03・採用基準・未決事項を対応付け、選択前提を残す | AC-01〜08、AC-29の採用前提 |
| 1349（1049） | 01-B1 再入監査 | 各再入先と捕捉除外、失敗値変換を列挙し、許可/拒否と試験への引継ぎを示す | AC-03 |
| 1350（1049） | 01-B2 共有監査 | Writer・共有変数・復元処理の到達先とnull時の動作を分類し、未監査経路へ進まない | AC-04〜06、AC-08 |
| 1351（1049） | 01-B3 最小許可集合 | builtinからState/callback/共有変数と最適化後Opまで追跡し、許可根拠を残す | AC-03、AC-06 |
| 1352（1049） | 01-C1 W1試作 | 通常ビルドで専用取消し・再入・inline・捕捉除外を確認し、debug機能との併用規則を示す | AC-01、AC-03 |
| 1353（1049） | 01-C2 最小隔離 | 別State/Storage/Writerで実スレッド隔離を確認し、大きさを記録する。件数や大きさは実測記録を別途付ける | AC-04/05 |
| 1354（1049） | 01-C3 Snapshot試作 | 新規/再利用復元、最適化後コード、取得後変更と保存範囲を検証する | AC-07/08 |
| 1355（1049） | 01-C4 生成物比較 | debug=falseの逆アセンブル差分とサイズを変更前後で提示する | AC-29 |
| 1356（1049） | 01-C5 時間測定 | 別途利用者確認後に14節の条件・生データ・閾値を記録する。本作業では未実施であり、ACの機能試験で代替しない | AC-01/02/07/08/29の方式判断資料。測定自体は本表の試験対象外 |
| 1357（1049） | 01-D 方式判断 | D01/D02の採用/保留/不採用、通常ループ方針、レビュー対応、代替案と利用者判断を記録する | AC-01〜08、AC-29の適用範囲確定 |
| 1358（1053） | 05-A 再帰監査 | 最新フィールド・内部ポインター・Writer・ホスト共有参照を分類し、列挙件数だけで完了としない | AC-04/05/21 |
| 1359（1053） | 05-B Snapshot | D03と実装が一致し、版・入口・辞書破壊後の失効と実行中保持を検証する | AC-07/08 |
| 1360（1053） | 05-C 許可検査 | 静的・直接builtin・inline・動的先の検査が迂回できない | AC-03/06 |
| 1361（1053） | 05-D 転送 | 入力/結果コピー、深さ・範囲・長さ・上限、違反時の失敗回収を検証する | AC-04/07/09/13 |
| 1362（1053） | 05-E 再利用 | 成功・失敗・取消し後の連続実行で状態と参照が残らない。試作取消し経路の結果と本実装での再検証を区別する | AC-08/21 |
| 1363（1050） | 02-A 状態仕様 | 内部/公開状態・D04/D05・エラーと各操作の許否を明文化する | AC-10/11/22の期待値確定 |
| 1364（1050） | 02-B 台帳 | 種別・世代・owner・満杯・枯渇・旧IDと解放時の参照保持を検証する | AC-11〜13 |
| 1365（1050） | 02-C 結果 | 上限付き保持・非消費照会・必要量返却・失敗/取消しの診断を検証する | AC-09/10 |
| 1366（1050） | 02-D キュー | 上限・完了公開・メモリ順序・起床失敗時の回復と所有権を説明し検証する | AC-11/13/14 |
| 1367（1050） | 02-E 状態再現試験 | 状態競合、結果境界、満杯、世代/旧ID、通知異常を再現して証拠を残す | AC-09〜14 |
| 1368（1051） | 03-A 待機設計 | 世代観測・登録・再確認・単一期限・再取得とD08、解除時の所有を明記する | AC-14〜18の手順確定 |
| 1369（1051） | 03-B 入力等接続 | 入力・I/O可用・期限・終端を共通登録へ接続し、個別同期待機の直列化を避ける | AC-15/16/18 |
| 1370（1051） | 03-C 描画接続 | 対象番号・backend能力・close時の終端を検査し、未対応待機を作らない | AC-17/18 |
| 1371（1051） | 03-D スケジューリング | 一巡上限・投入順・逆圧・公平性・ワーカー間待ち禁止を実装し検証する | AC-13/19/20 |
| 1372（1051） | 03-E 待機再現試験 | 登録前後/解除中/同時成立、取消し対期限、通知併合、飢餓を制御して確認する | AC-14〜17、AC-19 |
| 1373（1052） | 04-A 取消し | 要求をラッチし安全境界で停止する。CATCH非捕捉とD04の終端確定を確認する | AC-01〜03、AC-11/16 |
| 1374（1052） | 04-B 終了回収 | 所有者終了・例外・QUIT/BYE・完全復元と関連資源の順序/拒否を確認する | AC-08/15/22/24 |
| 1375（1052） | 04-C 停止不能 | 参照保持・診断・独立資源の後始末・ホスト最終終了の経路を区別して検証する | AC-23/24 |
| 1376（1052） | 04-D 回収再現試験 | 二重解放・残存・解放後参照を検査し、停止不能を成功扱いしない。本実装取消し後の再利用も確認する | AC-01/11/21〜24 |
| 1377（1054） | 06-A 受け入れ表 | 13節の全分類、試験種別、機械、子タスク、未実施状態、共通完了条件と未決事項を整理する | 全ACの計画。本書の作成は試験合格ではない |
| 1378（1054） | 06-B 構成計画 | D06と代表構成ごとの語の有無・内部依存・コマンド・期待値を計画する | AC-26/27 |
| 1379（1054） | 06-C 公開語・文書 | 語名・スタック効果・エラーを確定し、英日HELP/リファレンス/READMEを実装と一致させる | AC-28 |
| 1380（1054） | 06-D 利用例・結合 | 経路探索/TUI検索等で計算・I/O中の入力/描画と古い結果の排除を検証する | AC-02/05/18/20/25 |
| 1381（1054） | 06-E 構成実行 | 1378のマトリクスをWindows・WSLのLinuxでビルド/試験し、独立選択を確認する | AC-26/28 |
| 1382（1054） | 06-F Windows・WSL実機 | Windows機の当該2環境で実機行を実行し、環境・証拠・未確認範囲を別々に残す | AC-02/05/18/20/24/25、AC-28 |
| 1383（1054） | 06-G macOS実機 | Macで再現試験と実機行を実行し、構成・公開語・通常経路の確認範囲と未確認範囲を残す。クロスコンパイルで代替しない | AC-01〜25、AC-27〜29 |

1048全体は方式判断だけで完了せず、1050〜1053の実装、1054の結合・構成・OS確認、文書/HELPと全子の完了が必要である（`docs/TASK_CONTROL_DETAILED_PLAN.md:490`〜493）。1377の文書完成と、この全体完了を区別する。

## 5. 未確認事項と判断待ち

- 全ACの実装適合性・実行結果は未確認である。ビルド・実行・速度/時間測定は行っていない。各OSの実際のbackend・利用可能な画面/音/I/O資源も未確認である。
以下の子タスクへの対応は、15節の確定先（親タスク）を12.3の作業分担へ展開したものである。tqueの依存や備考の追加ではない（`docs/TASK_CONTROL_DETAILED_PLAN.md:403`〜413・470〜477）。

- D01：確定先は1049・利用者判断であり、子タスクは1357（試作・比較資料は1352〜1356）である。通常ループ方針の解釈も判断記録へ残す（同計画:470・404〜406）。
- D02：確定先は1049、子タスクは1357（方式比較資料は1348）である。独立VMを不採用とする場合は方式固有ACの置換・対象外理由を記録する（同計画:471・403・406）。
- D03：確定先は1049・1053、子タスクは1357・1359（試作資料は1354）である。Snapshotの保存範囲・辞書破壊後の新規投入・旧版と入口の失効を照合し、既存詳細設計との相違を独自に解消しない（同計画:472・404・406〜407）。
- D04：確定先は1050・1052、子タスクは1363・1373である。完了対取消しの優先規則を仕様と実装で一致させる（同計画:473・407・409）。
- D05：確定先は1050・1052、子タスクは1363・1373・1374である。実行中RELEASE、所有者終了/QUITの範囲、取消しと回収を一致させる（同計画:474・407・409〜410）。
- D06：確定先は1049・1050・1054、子タスクは1357・1363〜1365・1378・1379である。方式判断、状態・ハンドル・結果/診断、所属語群・公開表現・エラーの整合を確認する。構成の具体的コマンドは1378の成果を待つ（同計画:475・403・406〜408・412）。
- D07：確定先は1049・1050・1052、子タスクは1357（試作・比較・測定資料は1352〜1356）・1363〜1366・1373〜1375である。ワーカー数・キュー/台帳・入出力/診断/Snapshotの有限上限、期限・合格閾値は未確定である。上限境界試験に任意の数値を置かない。偽時計による期限検証は実時間の停止保証ではない。1356の測定は本作業では行わない（同計画:476・404〜410）。
- D08：確定先は1051、子タスクは1368〜1370である。待機対象と描画能力別の扱い、同時成立時の返却規則を確定する（同計画:477・408〜409）。

判断項目の出典は `docs/TASK_CONTROL_DETAILED_PLAN.md:466`〜481（15節）である。13節の機能受け入れと14節の測定条件は別であり、測定未実施を機能合格で埋めない。

## 付録A. 件数の確認コマンド

以下はPowerShellから実行した読み取り専用コマンドである。件数は文書の構造とタスク範囲の件数であり、実装のフィールド数やテスト合格数ではない。

```powershell
# 詳細計画13節の分類行
$p = Get-Content docs/TASK_CONTROL_DETAILED_PLAN.md
$a = [Array]::IndexOf($p, '## 13. 必須の検証項目')
$b = [Array]::IndexOf($p, '## 14. 測定計画と上限値')
@($p[($a+1)..($b-1)] | Where-Object { $_ -match '^\| ' -and $_ -notmatch '^\| 分類 ' }).Count
# 結果: 15

# 各タスクの情報を実際に取得し、親ごとの件数を確認
$tasks = @(1348..1383 | ForEach-Object {
    $detail = @(tque show $_)
    if ($LASTEXITCODE -ne 0) { throw "tque show failed: $_" }
    [pscustomobject]@{ Id = $_; Parent = ($detail | Where-Object { $_ -match '^親:' }) }
})
$tasks.Count
$tasks | Group-Object Parent | Select-Object Name, Count
# 結果: 36。親1049=10、1050=5、1051=5、1052=4、1053=5、1054=7

# AC行の一意性、状態、子タスク対応表の範囲
$text = Get-Content docs/TASK_CONTROL_ACCEPTANCE.md
$ac = @($text | Where-Object { $_ -match '^\| AC-\d{2} \|' })
$ac.Count
@($ac | ForEach-Object { ($_ -split '\|')[1].Trim() } | Sort-Object -Unique).Count
@($ac | Where-Object { $_ -notmatch '\| 未実施 \|' }).Count
$mapped = @($text | Where-Object { $_ -match '^\| (13\d{2})（' } | ForEach-Object {
    [int]([regex]::Match($_, '^\| (\d+)').Groups[1].Value)
})
$mapped.Count
Compare-Object @(1348..1383) @($mapped | Sort-Object -Unique)
# 結果: AC行29、一意ID29、未実施以外0、対応表36、差分なし
```


## 付録B. 修正時の機械割当て確認

今回の修正では、付録Aの件数確認コマンドも再実行し、同じ結果であることを確認した。次の追加確認をPowerShellで実行した。

```powershell
$text = Get-Content docs/TASK_CONTROL_ACCEPTANCE.md
$ac = @($text | Where-Object { $_ -match '^\| AC-\d{2} \|' })
@($ac | Where-Object { $_ -match '全機' }).Count
@($ac | Where-Object { $_ -match '1383：Mac実機（macOS）' }).Count
@($ac | Where-Object { ($_ -split '\|')[7] -match '13(?!83)\d{2}：Mac' }).Count
# 結果: 「全機」の行0、1383のMac実機割当て28行、1383以外のMac担当割当て0行
```

AC-26はWindows・WSLの構成試験であり、macOSの構成試験はAC-27に分けている。1383の割当てはAC-26以外の全行を対象とする。試験はすべて未実施のままであり、この件数は合格数ではない。

指摘4については、修正時点の詳細計画で完了条件が490〜493行にあることを確認した。開始行490は有効であり、従来の終端494のみが範囲外であったため、引用を490〜493へ修正した（`docs/TASK_CONTROL_DETAILED_PLAN.md:490`〜493）。

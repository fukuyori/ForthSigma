# 637 ターミナル制御の設計と実装

2026-11-19。637は設計1070、実装1071、Windows/Linux受け入れ1072、Mac実機1073へ分割する。1070〜1072は仕様・実装・Windows/Linux受け入れまで完了。637は75%、Mac実機1073だけを残す。Mac実機での新機能の動作は未確認。

## 公開する語と配置

新しい語はEXTENSIONに登録する。既存FORMとGRAPHICSのMOUSE-ON/OFFは所属を変えない。音・描画の語群やdebug/filesは新しい語の前提ではない。

| 語 | スタック | 動作 |
|---|---|---|
| TERM-MODE! | `( mask -- ior )` | 要求全体を置換する。0成功、-24不正mask、-21ホスト/端末非対応、-265ホスト操作失敗 |
| TERM-MODE@ | `( -- mask )` | 受理済み要求を返す。非対応ビットと復元保留中で不確かなビットは除く。raw状態や一時退避では値を変えない。ホストの取得口がなければ-21のTHROW |
| COLS / ROWS | 各`( -- u )` | FORMと同じ出力先・capture・既定値の規則で列数/行数を返す |
| TERM-ALT-SCREEN | `( -- mask )` | 1、代替画面 |
| TERM-PASTE | `( -- mask )` | 2、raw時のbracketed paste要求 |
| TERM-HIDE-CURSOR | `( -- mask )` | 4、カーソル非表示 |
| TERM-MOUSE | `( -- mask )` | 8、raw時のマウス報告 |

負値と15を超えるmaskはホストを呼ぶ前に-24とする。MOUSEの指定は既存MOUSE-ON/OFFと同じ要求を更新する。TERM-MODE!で8を含まないmaskを成功させると、MOUSE-ONの要求も解除する。成功時にVMのgfx_input.mouse_onも更新する。

COLS/ROWSはFORMの寸法計算を共用する。通常は実端末サイズ、取得できなければ24行80列、出力がファイルなら同じ既定値、capture中はROWS=1・COLS=最大正セル値となる。[Gforthの一次ソースkernel/termsize.fs](https://github.com/forthy42/gforth/blob/master/kernel/termsize.fs)のスタック効果と、ROWSがFORMの行、COLSが列を返す関係を照合した。外部Gforth実行体による比較は今回行っていない。GPLの実装を転記せず、既存のSigma FORMの処理を共用した。

## 受理・実適用・復元保留

`host_terminal.Manager`はwanted（受理した要求）、applied（送信/設定できた値）、dirty（成否不明のビット）、raw、退避の深さを持つ。ホストスレッドから操作し、共有中に値コピーしない。

altとカーソルはrawを使う前から設定できる。pasteとmouseは要求を保持するが、実際の報告はraw時だけ有効にする。getterは受理済み要求を返すので、KEY/INKEY/DSR等でrawが変わっても値は揺れない。端末からの肯定応答や機能の実在を確認するAPIではない。

設定変更は成功してから要求を確定する。途中の書込みが失敗すると旧要求へbest-effortで戻し、成否不明のビットを残す。復元ではdirtyビットへも明示的な解除を送り、失敗を成功扱いにしない。解除は何度呼んでもよく、複数項目の後始末は一項目が失敗しても残りを試す。

TERM-MODE!は標準出力そのものが端末の場合にホストから直接制御列を送る。VMのcaptureやOUTFILEへ制御列を混ぜない。出力順を保つため通常出力をflushし、カーソル位置のキャッシュを無効化する。

## 対応条件とWindows

通常の設定口はstdin/stdoutが端末であることを要求する。POSIXはTERMが未設定・空・dumbなら-21とする。WindowsはコンソールとVT processingの有効化成功を条件にする。端末が制御列を無視するかを能動照会しない。0の設定と未適用状態の取得は、非端末でも後始末のため使える。

WindowsはReadConsoleInputWを維持し、VT入力へ切り替えない。PASTEだけは要求を無視して成功とし、getterに2を立てない（既存の利用者決定）。mouseはrawのコンソール入力モードへ設定し、成否を確認する。既存MOUSE-ONの、入力コンソールだけが端末で出力がリダイレクトされている場合の動作は維持する。

POSIXのTERM-PASTEは端末へ2004の要求を送るだけで、638の貼り付けイベント実装は含まない。この時点でEKEY/INKEYが貼り付け境界をイベントとして解釈できるとは扱わない。cooked入力には報告の印を混ぜない。

## 入出力と終了の境界

| 経路 | 処理 |
|---|---|
| EKEY/INKEY等のraw入力 | paste/mouseを要求に合わせて適用。既存の保留バイトとWindows入力レコードを保持 |
| KEY/KEY?/ACCEPT | alt/cursorを維持し、cookedへの変更でpaste/mouseを止める。表示要求がある間の入力には既存信号仲介のinterrupt-onlyスコープを使う |
| stdinのKEY-FILE等 | 既存のraw byte経路を維持する。語名だけでcookedの退避を追加しない |
| REPL | 入力とプロンプトは通常画面。一行を実行する間だけ要求へ復帰 |
| SYSTEM/エディター | 外部処理の全体で表示を一時解除し、終了後に受理済み要求へ戻す。入れ子の退避に対応 |
| CATCHしたTHROW | 設定を維持する |
| 未捕捉エラー | 信号回復→表示の解除→raw解除の後、通常画面へ診断を出す。要求は0に戻す |
| BYE・EOF・通常終了 | raw未使用でも表示を解除する。profile等の終了時出力より先に復元する |

KEY/ACCEPT中のSIGINTを捕捉するスコープは、host_waitのプロセス所有ゲートと既存の安定したNativeScopeを使う。入れ子の入力は一つのticketを共有し、最外側で解除する。EINTRを無条件で再試行せず割込みを確認する。POSIXのcooked読み取りはスコープ中に20msのpollで割込みを再確認し、read直前の信号を取り逃がして無期限に待たない。nullableな従来の入力コールバックで起きたエラーはWriter.input_error_fnからcoreへ伝え、EOFと誤認しない。

Windowsのcooked読み取りは専用CONIN$ハンドルを保持し、通常の長い行では読み取り間も閉じない。入力スコープ中のCtrl+Cは登録済み読み取りスレッドだけをCancelSynchronousIoで中断する。中断後は登録を先に外してから専用ハンドルを閉じ、conhost側に残った読み取りが次の一行を消費する回帰を防ぐ。標準入力のハンドルは閉じない。ReadConsoleWの0文字・失敗ではハンドラーの先行/後行を考慮して約100ms待ち、説明できない0文字はHostFailedとする。入力スコープ内ではCtrl+Z以外を永続EOFにせず、保留中の割込み・ホスト失敗をstdin_eofへ反映しない。ハンドラースレッドが約100msを超えて遅れる状況は未確認であり、その場合の完全な復元は検証できていない。ハンドルと世代番号をロックで守り、古いハンドラーが次の読み取りを取り消さないようにする。閉じる処理の失敗時は所有を保持し、再試行まで同じハンドルで読み取らない。

通常VMループやMS中など、既存の入力・待機スコープ外のSIGINT、Ctrl+Break、SIGTERM/SIGHUPは本機能で捕捉しない。既定の終了処理では表示復元を保証しない。これはKEY/ACCEPTやNSのUserInterrupt経路で確認する復元とは別の制約であり、全シグナル対応を完了扱いにしない。

host_input.before_mode_changeを先に通し、NSが保留した端末復元と競合しない。native rawの復元が失敗したときは所有を保持して再試行し、古いrawマウス設定を、復元済みのcookedコンソールへ再適用しない。

表示の要求とOS資源を辞書イメージへ保存しない。新プロセスでは要求0から始める。同一プロセスで辞書を復元・追加するだけでは新たな表示設定を送らない。今回の語の追加でBuiltinのABI署名は更新され、古いイメージは作り直す。OSによる強制終了と、実OS APIが復元不能な状態での完全回収は保証しない。

## 検証と残作業

- 差替えBackendで、raw前の表示、raw限定報告、入れ子、途中失敗と巻戻し、復旧失敗のdirty保持、冪等解除を確認する。
- core試験でmask検査・ホスト不在・スタック境界・MOUSE共有・FORMとの一致・入力エラー伝達を確認する。
- `verify-terminal-modes.py`はPOSIX PTYで、KEY/ACCEPT/SYSTEM・捕捉/未捕捉の例外・raw/cooked SIGINT・profileと終了復元を確認する。
- `verify-terminal-modes-windows.py`は独立した非表示コンソールで、Windows貼り付け除外・rawマウス・入力モードとカーソルの復元等を確認する。物理キーによる実機受け入れとは区別する。
- `verify-terminal-modes-conpty.py`は独立ConPTYの入力パイプからCtrl+Cを送り、cooked入力の中断と次のKEYを確認する。物理キーボード操作とは区別する。
- 通常構成・extension除外・audio/graphics/debug/files除外、既存WindowsコンソールとLinux NS/PTY回帰、Cortex-M0+、Mac向けコンパイルを確認し、結果を[実装記録](CORE_EXTENSION_IMPLEMENTATION.md)へ残す。
- 1073のMac実機では同一コードの全体・除外試験とPOSIX PTYを実行し、OS/Zig版と結果を記録する。旧1065の完了は637のMac実行確認を意味しない。

実装は`host_terminal.zig`、`host_input.zig`、`host_wait.zig`、`main.zig`とcoreのWriter/extension/input処理にある。coreにOSサービスは追加しない。Writerへ追加したホスト操作口は将来のワーカーへそのまま渡さず、1053の再帰監査に含める。

## Mac実機1073の再開手順

同一コードをMacへ渡し、`zig version`、`sw_vers`、対象コミットと作業差分を記録する。`zig build test --summary all`、`zig build --prefix .work/637-native --summary all`、`python3 tests/scripts/verify-terminal-modes.py --sigma .work/637-native/bin/sigma`、`python3 tests/scripts/verify-p05b-ns.py --sigma .work/637-native/bin/sigma --sigma-only`、`python3 tests/scripts/verify-extension-matrix.py`を実行する。全体構成の実行体で`python3 scripts/word-reference.py --check --sigma .work/637-native/bin/sigma`と`python3 scripts/check-docs.py`も確認する。ログの場所と成功・スキップ数を実装記録へ追記し、成功した範囲に応じて1073と637を完了する。署名・パッケージ作成は不要。

## レビュー資料

- [設計レビュー原文](reviews/637-design-claude-review.md)
- [実装レビュー原文](reviews/637-implementation-claude-review.md)
- [Windows入力再開の調査レビュー](reviews/637-windows-investigation-claude-review.md)
- [最終レビュー原文](reviews/637-final-claude-review.md)
- [追加修正の再レビュー原文](reviews/637-followup-claude-review.md)
- [指摘の評価と反映判断](reviews/637-review-response.md)

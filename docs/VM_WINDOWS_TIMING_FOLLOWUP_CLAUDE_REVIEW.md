# Windows計時診断 Claude Codeレビュー

初回レビュー（修正前）。以下の指摘を受けて集計・手順を補正した。

# Windows計時追加診断レビュー(#858、読取り専用)

## 総合判定

- **Critical/Highの指摘なし。** 現行結論(原因未特定・候補比較未再開・採用保留)を覆す誤りは見つかりませんでした。
- **Mediumは4件。** M1〜M3は管理者実行前に直すべき項目、M4は記録の注記修正です。
- 確認範囲はRead/Grep/Globのみで、実行はしていません。
- `samples.json`/`native-samples.json`の原記録は直接開かず、`summary.json`/`native-summary.json`と`native-config.json`で照合しました。

照合できた数値は次のとおりです。

| 文書の記載 | 根拠 | 結果 |
| --- | --- | --- |
| 結果表のSigma 4セル(CPU中央値・CPU/wall/cycles範囲比) | `summary.json:5016-5201` | 一致 |
| 結果表のnative 4セル | `native-summary.json:4945-5129` | 一致 |
| Sigma長条件 2.379%/3.626%、screen不合格 | `summary.json:5237-5242` | 一致 |
| 観測最大 42.189/41.675ms、thread一覧 34.979ms、context 10.038ms、CPU照会 0.163ms | `summary.json:2518-2530`、`native-summary.json:2812,4643` | 一致 |
| DONE後CPU増分 0〜15.625ms | `summary.json:627,2814`、`native-summary.json:923` | 一致 |
| process−主thread差が32実行で0 | 両summaryに非0の行なし | 一致 |

## 問1 計装の整合性:概ね整合

- **端点の非同時性は実害が小さい。** 主指標の`GetProcessTimes`を最初に読み(`observer.py:34`)、約40msの補助観測はその後です。子はREADY/DONEとも`KEY`待ちなので、CPU主指標への混入は構造上小さいです。
- **wallへの混入は文書どおり。** `wall_start`はREADY側の`read_cpu()`の後で取られます(`scripts/benchmark-runtime.py:156-161`)。DONE側の読取り全体がwallに入り、文書75行の記述と整合します。
- **主threadの特定は妥当。** `CreateProcess`の戻り値からTIDを取り(`observer.py:5-7`)、`OpenThread(0x0840)`で開いています。
- **原因断定はしていない。** 文書12、24、69、77行はいずれも相関からOS/周波数/schedulerの不具合を特定していません。

### M4(Medium・記録修正)psutilの`voluntary`は自発切替数ではない

- psutilのWindows実装は、全threadのContextSwitches合計を`voluntary`に入れ、`involuntary`を0で返します。これは私の知識に基づくもので、今回psutilのソースは開いていません。
- データもこれと整合します。CPU専有ループで554回/6.5秒、2224回/26秒と時間に比例しています(`summary.json:86-89,398-401`)。
- 文書22行は「involuntary 0は証拠にしない」と書いていますが、`voluntary`が総数であることは未記載です。
- 予定しているETWのCSwitch照合では比較対象を取り違える恐れがあるため、文書とJSONの`limits`に追記してください。

### L1(Low)host counterの合計が二重計上

- CPU0の`counter_total_seconds`は7.078秒で、wallの6.492秒を超えています(`summary.json:93-100`)。
- interruptとdpcを引くと6.5秒になり、他CPUの合計(6.48〜6.5秒)と揃います。systemにinterrupt/dpcが含まれていると読めます。
- CPU0の`busy_fraction`はidle=0なので1.0のままですが、他CPUの比率と`counter_total_seconds`は過大です。文書77行に一言追記を勧めます。

### L2(Low)他threadの増分0は「両端に存在したthread」だけ

- 解析は両端の共通threadだけを差分しています(`analyze.py:15`)。
- 実際にはDONEで新規thread(`summary.json:388-390`)やREADY後の消滅thread(`native-summary.json:381-383`)があります。
- 文書73行は「境界間だけ生存するthread」しか除外を明記していません。
- 補強材料として、process cyclesと主thread cyclesの差は約7万cycles(`summary.json:14-15`)と極小です。これを併記すると主張が正確になります。

### L3(Low)用語と未検査の戻り値

- JSONキー`primary_within_one_quantum`の「quantum」は、実際には会計の刻み15.625msです。文書本文の「刻み」が正しい表現です。
- `GetPriorityClass`と`GetThreadPriority`は失敗値を検査していません(`observer.py:46`)。今回の値32/0は正常値なので実害はありません。

## 問2 記述的範囲とA/A校正の区別:適切

- 文書56行が「A1/A2校正のδではなく、信頼区間でもない」と明示しています。
- `summary.json`の`limits`にも「Diagnostic 3 samples is not AA calibration」があります。
- 事前条件は`run.py:8`の`continuation`に固定されており、解析も同じ2%閾値です(`analyze.py:25-26`)。条件の緩和はありません。
- nativeについて、文書42行と69行は共通原因の証明としていません。`native-summary.json`から`fresh_calibration_ground`も除かれています(`analyze-native.py:27`)。

### L4(Low)nativeに未宣言のscreen結果が残っている

- `native-summary.json:5179`に`long_range_screen_passed: false`があります。
- nativeには2% screenを事前宣言していないため、合否と読まれないようキー削除か注記を勧めます。

### L5(Low・任意)

- 元の継続条件は「all queries pass」(`run.py:8`)でしたが、解析は`required_live_fields_complete`で判定しています(`analyze.py:25`)。
- 文書40行と79行が曖昧さを開示しており、範囲比未達で結論は不変です。追加対応は不要です。

## 問3 native pilotと固定N:記載は正確

- pilotはCPU 15.625ms(1刻み)、wall 58msです(`native-config.json:5-7`)。
- Nは`ceil(1e8×6e6/15625)`=38,400,000,000、長は153,600,000,000です(`native-config.json:522-523`、`run-native.py:10`)。結果を見た調整はありません。
- 1刻みだけのpilotは真値の不確かさが大きく、狙いの6/24秒から外れたことは文書71行に記載済みです。
- volatileループは残っています。`native-disassembly.txt:74-87`(0x1400010ef〜0x140001123)に4回展開の読込み・加算・格納があり、端数ループは90-94行、ソースは`native-control.c:18-20`です。
- nativeとSigmaの速度比は文書・JSONのどこにも出ていません。

## 問4 WPRと管理者wrapper:骨格は妥当、実行前に3点修正

確認できた点は次のとおりです。

- **profileは最小構成。** 7 keywordのみで、stack/File/Network/Registryはありません(`schedule.wprp:10-16`)。
- **拒否記録は一致。** exit 2147942405=0x80070005で、その後の自instance照会は「not recording」です(`capture.json:38-50`)。`privilege.json`とも整合します。
- **出力とsessionは新規。** `admin-<UTC>-<uuid6>`を`mkdir()`で作り、既存なら失敗します(`capture-admin.py:3`)。instance名は別の一意名です(同4行)。
- **停止対象は自instanceのみ。** stop、cancel、statusのすべてに`-instancename`が付いています(同33-35行)。
- **自動昇格なし。** ps1は`IsInRole`で確認して例外を出すだけです(`capture-admin.ps1:17-21`)。py側も`IsUserAnAdmin`で止まります(`capture-admin.py:10`)。
- **未実行の表記は正直。** 文書87行「ETW取得自体はまだ未検証」と、公開JSON 29235行「syntax/WhatIf checked only」が一致しています。

### M1(Medium・実行前に修正)`wpr`が相対名で、昇格下の探索順に依存

- `call(['wpr',...])`は`cwd=r`で相対名を起動します(`capture-admin.py:8,18,21,33-35`)。
- Windowsのプロセス生成は、python.exeのディレクトリやカレント(プロジェクト直下)をSystem32より先に探します。
- どちらも利用者が書き込める場所なので、管理者権限で意図しない`wpr.exe`が動く余地があります。
- `%SystemRoot%\System32\wpr.exe`の絶対パス指定と、存在確認を入れてください。

### M2(Medium・実行前に修正)安全確認が`assert`頼み

- ハッシュ照合と範囲確認はすべて`assert`です(`capture-admin.py:3-4,11-17,26,30`)。
- `PYTHONOPTIMIZE`や`-O`が有効だと、警告なしで全部が無効になります。wrapperは`-X utf8`だけを渡しています(`capture-admin.ps1:24`)。
- 明示的な`raise`に置き換えるか、冒頭で`__debug__`を確認してください。
- 併せて、psutil 7.2.2の実行時照合がありません。`import`のみです(`capture-admin.py:9`)。

### M3(Medium・実行前に修正)cleanup成否が機械的に判定されない

- cancelの終了コードと最終statusの出力を検査していません(`capture-admin.py:34-35`)。
- session残存時も「Capture incomplete」としか出ません(同38行)。
- 最終statusが「not recording」かを`cleanup_confirmed`として記録してください。
- 未確認なら、instance名と手動の`wpr -cancel -instancename <名前>`を表示するのが必要です。
- 文書89〜95行にも、窓を閉じた場合などの復旧手順を1行追記してください。instance名は開始前に`capture.json`へ保存されるので復旧は可能です。

### L6(Low)事前確認の失敗が記録に残らない

- `mkdir`は管理者確認とハッシュ確認より前です(`capture-admin.py:3`と10-17行)。
- 失敗すると空の`admin-*`だけが残り、`capture.json`はできません。
- workload中の例外も`status`やエラー文として保存されません(同24-35行)。

### L7(Low)`-WhatIf`の検証範囲を明記する

- `-WhatIf`ではPythonとdriverの存在確認と表示だけが動きます(`capture-admin.ps1:9-16`)。
- 管理者確認、ハッシュ照合、WPR状態確認、stop経路は一度も実行されていません。
- 文書87行の「依存関係と凍結実行体を開始前に確認する」は設計の説明です。WhatIfで確認済みと読まれないよう一言足してください。

### L8(Low)入力検証の残り

- `-PythonExecutable`は任意パスを受け、`Test-Path`はディレクトリでも通ります(`capture-admin.ps1:8-9`)。
- `capture-admin.py`自体はハッシュ検証の対象外です。
- 照合元の`protocol.json`も同じ書込み可能領域にあるため、自己参照的な検証にとどまります。

### L9(Low)追跡予定JSONにユーザー名入りパス

- `docs/measurements/2026-11-16-windows-timing-followup.json:29188`に`C:\Users\n_fuk\...`があります。
- 絶対パス、PID、commandも計134箇所に含まれます。
- commit前に伏せるかどうかの判断をお願いします。`.work/`は`.gitignore:4`で除外されており、ETLの非公開方針とは整合しています。

### L10(Low)ps1の実行ポリシー

- 管理者PowerShellの実行ポリシーで`.ps1`が拒否される可能性があります。
- その場合は永続設定を変えず、プロセス範囲の指定で対処する旨を手順に書くと、方針(永続設定不変)と整合します。

## 対応の区分

**管理者実行(#861)の前に必要**

1. M1:`wpr`を絶対パスにする。
2. M2:`assert`を明示的な検査に置き換える。
3. M3:cleanup確認の記録と復旧手順を追加する。
4. M4:`voluntary`=総切替数の注記を追加する(ETW照合の前提)。

**文書とJSONの修正(結論は不変)**

- L1、L2、L4、L7、L9。

**任意の将来観測(今回の判断には不要)**

- CPU0のinterrupt/dpc増分の記述的な併記。値は記録済みですが、原因の断定には使えません。
- ETL取得後のschema、欠落、時間境界の確認。これは文書95行で計画済みです。
- stop/cancel経路の実機確認。初回の管理者実行が実質的な初検証になります。

再試行の追加や主CPU指標の変更は推奨しません。


## 再レビュー（最終補正前）

初回の行番号は修正前を指す。補正前summary/driverは.workのetw/before-reviewへ保存した。再レビュー指摘への最終対応は対応文書を参照。最初の再レビュー試行はサービス混雑529で失敗し、再実行はexit0で完了した。

# フォローアップレビュー結果(読取り専用)

**総合判定:** M1〜M4とL1〜L8の補正は内容として反映済みで、結論(原因未特定・候補比較未再開・採用保留)と「管理者取得は未実行」の記載は正直です。ただし、管理者手順が開始前に止まる可能性が高い問題が1件残っています。

確認はRead/Grep/Globのみで、ハッシュ計算と実行はしていません。

## 残る指摘

### H1(High・管理者実行前に要確認)driverハッシュが実ファイルと不一致の可能性
- `fix-review.py:45-47`は、driverを`write_text(s)`で書き、ハッシュを`s.encode()`から計算しています。
- Windowsの`write_text`は改行をCRLFに変換し、実際に`capture-admin.py`は全135行がCRLFです。記録された`driver_sha256`はLF版の値と読めます。
- この場合、`capture-admin.ps1:12`の`Get-FileHash`照合が不一致になり、`-WhatIf`でも本実行でも「Driver changed」で止まります。危険側ではなく停止側の失敗です。
- 文書108行は`-WhatIf`がdriverハッシュまで確認すると書いていますが、補正後に`-WhatIf`を再実行した記録は見当たりません(`admin-validation.json`は`--preflight`のみ)。
- 対応:実バイトから`driver_sha256`を再計算し、公開JSONの同値(29369行)も更新したうえで、非管理者の`-WhatIf`が通ることを確認して文書に明記してください。

### M5(Medium)開始失敗が`workload_failed`に上書きされる
- `capture-admin.py:82-84`で`start_failed`を設定して例外を出しますが、直後の`except`(110-112行)が`workload_failed`に書き換えます。
- 今回と同じ0x80070005が再発した場合、記録上はworkload失敗と区別できず、手がかりは`error`文字列だけになります。
- 開始していないinstanceにも`-stop`と`-cancel`が走ります。自instance限定なので実害はありませんが、`stop_exit`と`cancel_exit`が非0で残ります。
- 対応:開始失敗時は`status`を保持し、stopを省いてstatus確認だけにしてください。

### L11(Low)cleanup検証の未カバー経路
- `validate-admin.py`の4ケースは`finally`本体だけを模擬しています。
- 未検証なのは、`call()`の例外経路(60-66行)、開始失敗経路、既存記録検出での終了(76-79行)です。
- stop呼出し自体が例外になると、cancelとstatusは実行されず`cleanup_confirmed`も未設定のままです。手動cancelの表示は出ます。

### L12(Low)昇格下の実行環境は依然として利用者書込み領域
- Python実行体はユーザープロファイル配下で、`-X utf8`のみで起動します(`capture-admin.ps1:26`)。
- スクリプトのディレクトリが`sys.path`先頭に入るため、`etw/`に置かれた同名モジュールが優先されます。
- `-PythonExecutable`は任意の実行体を受け付け、`python-environment.json`の`version`とは照合しません。
- 入力ハッシュの確認後に`benchmark-runtime.py`と`observer.py`を再読込みして実行します(85-90行)。
- 文書106行の「変更検出用で信頼の証明ではない」で開示済みです。可能なら`-P`と`-E`の追加を勧めます。

### L13(Low)初回L9・L10が未対応
- L9:公開JSON 29366行にユーザー名入りのPythonパスが1箇所残っています。PIDや絶対パスの扱いと合わせて、commit前に判断が必要です。
- L10:実行ポリシーで`.ps1`が拒否された場合の対処が、文書89〜95行にありません。プロセス範囲の指定で対処し、永続設定は変えない旨の追記を勧めます。

### L14(Low)記録の整理
- レビュー文書の行番号は修正前のファイルを指しています(例:`capture-admin.py:3`、`native-summary.json:5179`)。対象が`etw/before-review/`である旨を冒頭に一言足してください。
- 各指摘の対応状況(対応済み/対応不要/保留)の一覧がありません。L5は対応不要、L9とL10は保留と明記すると追跡できます。
- `scripts/__pycache__/`が未追跡で、`.gitignore`にもありません。commitに含めないでください。

## 補正の確認結果

| 指摘 | 状態 | 根拠 |
| --- | --- | --- |
| M1 WPR絶対パス | 済 | `GetSystemDirectoryW`で取得し存在確認、全呼出しを置換(`capture-admin.py:28-37,59`) |
| M2 `assert`排除 | 済 | 明示的な`raise`に置換、psutil版の照合を追加(同9-27行)。`-O`でのpreflight成功が`admin-validation.json`に記録 |
| M3 cleanup判定 | 済(M5とL11を除く) | `stop_exit`、`cancel_exit`、`cleanup_confirmed`、`manual_cancel`を保存し、未確認なら失敗終了(同115-135行)。復旧手順は文書106行 |
| M4 `voluntary`の意味 | 済 | 文書102行と、両summaryの各行の`context_counter_semantics` |
| L1 二重計上 | 済 | `analyze.py:12`がuser+system+idle。CPU0合計は6.5秒(`summary.json:101`)、文書77行 |
| L2 共通threadのみ | 済 | 文書73行と`limits` |
| L3 用語・戻り値 | 済 | キーを`primary_within_observed_15_625ms_increment`に変更、文書102行 |
| L4 nativeの合否field | 済 | `native-summary.json:5187-5194`から削除、文書104行 |
| L5 | 対応不要 | 文書40行と79行で開示済み |
| L6 失敗の記録 | 済 | `mkdir`を事前確認の後へ移動、workload例外を保存 |
| L7 `-WhatIf`の範囲 | 済(H1の再確認が前提) | 文書108行 |
| L8 入力検証 | 部分的 | Leaf確認とdriverハッシュを追加。自己参照性は開示済み(L12) |

- 結果表の8セルの範囲比は、現行の`summary.json`と`native-summary.json`に一致しました。Sigma長条件は2.379%/3.626%で不合格のままです。
- 公開JSONに旧集計の値は残っていません。旧キー名は`fix-review.py`の埋込みソース内だけです。
- 未実行の表記は、文書83行・87行・108行、`review-corrections.json`の`actual_elevated_capture_tested: false`、公開JSON 29414行で一致しています。

## 対応の区分

**管理者実行(#861)の前に必要**
1. H1:driverハッシュの再計算と`-WhatIf`の再確認。
2. M5:開始失敗時の`status`保持。driverを直すのでH1のハッシュ更新と同時に行ってください。

**文書の修正(結論は不変)**
- L13、L14。

**任意**
- L11、L12。

再試行の追加や主CPU指標の変更は推奨しません。

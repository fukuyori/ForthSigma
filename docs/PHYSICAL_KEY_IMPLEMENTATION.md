# 997 物理キーの実装・受け入れ記録

2026-11-19。1084（native接続）・1085（公開語）・1086（統合レビュー）と1081（Windows/Linux自動受け入れ）を完了。**997全体は未完了。1087（Windows US実機）と1089（Windows JIS追加確認）は完了。1082（Mac実機）・1090（Linux JIS実機）もリモートの確認記録を取り込んだ。Linux USの状態はtqueの現行構成を参照する。**

## 実装したもの

- `src/core/physical_keys.zig`：256ビットの状態、256件のedge、先行履歴を残すoverflow、stickyな再同期、stale snapshot待ち、Host/Ops。文字入力・既存KEY-HELD?の16キー状態とは独立。
- `src/physical_key_map.zig`：Windows Set1/E0、Darwin keyCode、XKB位置名→HID。SDL表はzlib表示を保持し改変版と明記。新しいSDLライブラリ依存はない。
- `src/physical_key_protocol.zig`：Mac Sender/Receiver。u64連番、dirty状態の最新snapshot、欠落・不正行の検出、閉鎖後の読捨て、追加edgeのない最後の解放の復旧。
- Windows：4種のKEY/SYSKEYを文字変換前に取り込み、既存SRW lockで保護。PauseとPrintScreenは未対応。両Shiftの解放欠落をUIタイマーとGetKeyStateで補完する。タイマー失敗時は左右Shiftも未対応。
- Linux：XKB GetNames/NamesNotifyの位置名を使い、keycode-8やkeysym文字から推定しない。repeat対の解放は確定してから反映する。unsupported/XErrorと通信断を区別。_NET_WM_PIDを公開して、試験時の送信先を所有プロセスのウィンドウに限定できるようにした。
- Mac：NSApplication.sendEvent:で観測して親へ委譲。状態lockとstdoutのtry-lockを分け、非blockingでdirty snapshotへ集約。既存の命令読取りスレッドが16ms周期で再送する。親のSCANSYNCはwrite成功後に重複送信しない。
- GRAPHICS：SCAN-INPUT?、SCAN-SUPPORTED?、SCAN-HELD?、KEY-EVENT、KEY-RESYNCと218個のSC定数（215 usage＋3 kind）。下位組込み5語は既存enum／登録順の末尾へ追加。範囲外-24、無効アドレス-9。イベントを消費する前に3セル分を確保し、snapshotは検査→作業領域→論理メモリ→writtenの順で更新する。
- イメージ：状態・履歴・ホスト参照は保存しない。復元成功時だけ非失敗の境界reset。OS／Mac pipeで未読だった通知は復元後に届いたものとして扱う。Builtin追加でイメージABI署名が変わるため、以前の実行体の保存イメージは作り直しが必要。

## 実行した最終検証

Zig 0.17.1、Windowsから実行。LinuxはWSLのX11/XWayland環境を使用。コンパイル・合成入力・実キーボードを区別する。

| 検証 | 結果・範囲 |
|---|---|
| `zig build install test --prefix .work/997-review/windows-final --summary all` | 27/27工程成功。core1071成功・8skip、host106成功・11skip。runtimeは既存キャッシュ再利用 |
| `python tests/scripts/verify-physical-keys.py --sigma .work/997-review/windows-final/bin/sigma.exe` | Windows実ウィンドウ、7段階成功。A等はSendMessage、ShiftはSendInputで注入 |
| `zig build install core-check host-check runtime-check -Dtarget=x86_64-linux-musl -Doptimize=ReleaseFast --prefix .work/997-review/linux-final --summary all` | 21/21工程成功。その生成バイナリをWSLで実行：core1071成功・8skip、host119成功・5skip、runtime15成功 |
| WSLで同じ`verify-physical-keys.py --sigma .../linux-final/bin/sigma` | XKB GetNamesで実際のkeycodeを照会し、所有PIDのX11ウィンドウへSendEvent。7段階成功 |
| `zig build core-check host-check runtime-check -Dtarget=aarch64-macos` | Mac向け全体構成、14/14工程成功。実行はしていない |
| 上と同じコマンドに`-Dgraphics=false -Daudio=false -Dfloat=false` | Mac向け除外構成、14/14工程成功。実行はしていない |
| `python tests/scripts/verify-extension-matrix.py` | 12構成すべてのtest/build成功。8通りのaudio/graphics/extension、files/debug除外等。除外ビルドのextension image原子的拒否も成功 |
| GRAPHICS image往復と除外時拒否 | graphicsのみ有効の010で物理語を含む辞書を保存・復元。SC-A=4、SCAN-INPUT?=false、復元直後の再同期要求を確認。000ではロードを拒否し既存語・辞書を保持 |
| `verify-event-queue-windows.py`／Linuxの`verify-event-queue.py` | 既存638のWindows5件、Linux PTY/pipe15件成功 |
| `word-reference.py --check --sigma .../windows-final/bin/sigma.exe` | 全8語彙の実辞書照合に欠落なし。EKEYS35値一致、文書例28件、個別例377件成功。HELP1563／全語1777項目を英日更新 |
| `python scripts/check-docs.py`／`git diff --check` | findings0／差分エラーなし |
| 手動チェッカーの定義部分 | Windows最終実行体でコンパイル成功。対話の実キーボード手順は実行していない |

構成試験の最終product source SHA-256：`83aede903ea916ecda7996933c83f82c7849c581878cb39381a3db6297de80a2`（build.zigとsrc全ファイル）。最終コードとmatrix.jsonのhash一致を確認した。ログとJSONは`.work/997-review/`、`.work/extension-matrix/`。配布パッケージは作成していない。

### native自動受け入れの7段階

1. 短押し・重複press（repeat）の抑止、左右Shiftの独立、supported/held/available。
2. stdinのEKEYとウィンドウのINKEYを先に読んでも、4件の物理edgeが順番どおり残る。
3. 両Shiftから左だけを離すと、左false・右trueになる。
4. フォーカス喪失で残りの右Shiftが解放される。
5. WindowsのSYSKEYDOWN/UP（LinuxはRightCtrl）で228のpress/releaseを取得。
6. 256件を超えると先行256件→sticky再同期。heldを更新し続け、32バイトsnapshot採取後は空になる。
7. ウィンドウ閉鎖後も解放edgeを読め、available/heldはfalse。

これは実際のOSウィンドウ経路の試験だが、物理キーボードのJIS/US配列・IME・ハードウェア固有の欠落を検証した結果ではない。SendInputもWindows固有のShift keyup欠落を再現したとは主張しない。

### 内部の試験範囲

pure Tracker9件、IPC Sender/Receiver4件、変換表1件、公開語7件。短押し、全252非予約usage、左右修飾、exact capacity、リング折返し、focus中のoverflow、世代境界、stale中のack、最終releaseの周期flush復旧、閉鎖後の行、連番wrap、不正payload、全SC定数の一意性とホスト表の網羅、無効アドレスでackしないこと、非整列copy、writtenによる再配置記録のdamaged化、スタック不足でイベントを奪わないこと、復元preflight失敗時の無変更を確認した。

折返し途中のoverflow、特殊Macキーボードのdevice-dependent mask欠落、X11 GetNames待ち中の別要求の非同期エラーは専用の実行試験をしていない。X11の別要求のエラーで応答列を継続できない場合は切断される。未知のキーを無理に対応済みとして補完しない。

## Claude Codeレビュー

[設計・Trackerの採否](reviews/997-review-response.md)、[1084ホスト接続原文](reviews/1084-native-claude-review.md)、[1085公開語原文](reviews/1085-public-claude-review.md)、[修正の採否](reviews/1084-1085-review-response.md)、[1086最終統合原文](reviews/1086-integration-claude-review.md)を保存した。

初回指摘を修正し、最終レビューは統合を止める欠陥なし。実行試験をしていない独立レビューと、上の実測結果を混同しない。存在しないワーカー実行ガードを追加済みとは扱わず、Writerのoptional opsと将来1049〜1053の禁止語検査への引継ぎを記録した。

## 残りの作業と次の順序

- 1082：Mac実機。sendEvent/super、左右修飾、Command併用、Fn/電源/音量の除外、通信詰まりから最後の解放の復旧、全体／除外構成を同じコードで実行する。
- 1087：Windows US実機（完了）。1088：Linux US実機（未完了）。1089：Windows JIS追加確認（完了、53/136は対象外）。1090：Linux JIS実機（未着手）。各OSの確認結果を独立して管理する。
- タスク制御の本物のワーカー実行検査は1049〜1053へ引継ぎ。入力資源を借用せず、worker Writerのphysical_key_opsはnullにする。
- 次の開発項目は予定どおり639・1078（非ブロッキングI/O／ファイル入力待機）。実機確認を完了済みとはせず、依存のない後続を進められる。

## 1087 Windows実キーボード確認の着手

2026-11-19T14:39:36.883729+09:00、コミット`ca82413`のクリーンな作業ツリーから`zig build --prefix .work/1087/windows --summary all`を実行し、10/10工程成功（コンパイルはキャッシュ再利用）。その実行体で手動チェッカーを起動し、所有するnativeウィンドウが表示され、初期ログのCapsLock/Pause/PrintScreen対応値が1/0/0であることを確認した。

実行体：`.work/1087/windows/bin/sigma.exe`。実行体・チェッカーのSHA-256、OS、開始時のGit状態、PIDは`.work/1087/windows-session.json`、出力は`windows-keyboard.log`と`windows-keyboard-error.log`に記録する。対象ウィンドウのレイアウトハンドルはWindows APIで`0x4110411`を取得したが、これを実キーボードの機種／JIS配列の確認結果とは扱わない。

利用者が実キーボードでAの短押し・約1秒の長押し、左右Shiftの同時保持→左だけ解放→右解放を操作し、「操作した」と報告。記録した8イベントを確認した。合成入力はこのセッションでは送っていない。

| Windows実キーの第1段階 | 観測結果 |
|---|---|
| Aの短押しと長押し | usage4のpress/releaseが各1組、合計4件。長押しで余計なpress edgeは増えていない。保持時間自体はログで測定していない |
| 左右Shiftの同時保持 | 229 press→225 pressの順で到着し、held L/R=1/1 |
| 左だけ解放 | 225 release、held L/R=0/1 |
| 右も解放 | 229 release、held L/R=0/0 |
| エラー | stderrは空 |

観測の構造化記録は`.work/1087/windows-observations-01.json`。Windowsのkeyupとタイマー補完のどちらから解放を得たかは、このログでは識別していない。確認したのは実キー操作に対する外部の状態とedgeである。

利用者から物理配列はUSとの回答を得た。Windows APIの入力レイアウトハンドルと、実際のキーの物理配列は別に記録する。回答は`.work/1087/windows-user-report.json`に保存した。

第2段階の操作報告を受け、左右Ctrl（224/228）、左Alt（226）、矢印4方向（82/81/80/79）、通常Enter（40）とテンキーEnter（88）のpress/releaseを確認した。各キーの押下数と解放数は一致し、stderrは空。右矢印は複数回記録されたが、操作回数の追加かどうかは未確認なので、指示した順序と完全一致したとは記載しない。

右Alt（230）はこの範囲のログにない。キーの有無、OS／メニュー等による配送、入力側のどこに原因があるかはまだ特定していない。まず右Altだけを再操作してもらい確認する。記録は`.work/1087/windows-observations-02.json`。なお、行末のmodifier表示はイベント発生時のsnapshotではなく読取り時の最新状態なので、短い押下のpress行に0が表示されたことだけでは失敗と判断しない。

右Altだけの再操作で、230 press（Alt L/R=0/1）→230 release（0/0）を確認した。stderrは空。第2段階で欠けていた理由は未特定だが、単独の右Alt操作が取得できることは確認できた。記録は`.work/1087/windows-observations-03.json`。

第4段階でUS記号キー`[ ] \ ; ' /`をそれぞれ47/48/49/51/52/56として確認した。左Windows227、メニュー101、左Shift225のpress/releaseも取得した。利用者がShiftを押したまま枠外へ移動して離す操作を実施し、held L/R=1/0→0/0を確認した。右Windows231はログにないが、利用者から「右ウインドウズキーはない」と回答されたため、現在のキーボードでは装備なしと記録する。取得失敗とはしない。記録は`.work/1087/windows-observations-04.json`、stderrは空。

IME確認用に`tests/scripts/check-physical-ime.fs`を追加した。既存`check-ime.fs`のGUI-FIELD／UTF-8確定ログを使い、各フレームに上限32件の独立物理イベント読取りを加えた。定義のコンパイルを検証した後、所有PIDを確認して旧チェッカーをWM_CLOSEで正常終了（exit0）し、新しいGUI入力欄を起動した。キー入力の自動注入はしていない。ログは`.work/1087/windows-ime.log`、stderrは`windows-ime-error.log`、実行体・スクリプトのhashとPIDは`windows-ime-session.json`へ記録する。

IME確認は利用者の操作後にログで検証した。IMEオフの確定文字は`a`（1バイト、61）、オンは「あ」（3バイト、E3 81 82）で、GUI-FIELDが2行を報告した。物理Aは編集・切替途中の操作も含め3組あり、いずれもusage4のpress/release。Alt、Backspace、Ctrl+Space、Enter等も含む全イベントは押下／解放が対応し、終了時の保持は空、stderrは空、Quitによるexit0を確認した。記録は`.work/1087/windows-observations-05.json`。

Windowsの手元US配列では、短押し／長押し、左右修飾、矢印、通常／テンキーEnter、US記号、左Windows／メニュー、フォーカス喪失、IMEの文字確定と独立した物理通知を確認した。右Windowsは装備なし、機種名は不明として記録した。分割後の1087はこのUS実機の範囲で完了。JIS配列は1089、Linux USは1088で管理する。

## 1088 Linux実キーボード確認（分割前1087）の着手

`zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseFast --prefix .work/1087/linux --summary all`は12/12工程成功（コンパイルはキャッシュ再利用）。実行体hashは最終自動受け入れで使ったLinux実行体と一致した。WSLのX11/XWaylandで手動チェッカーを起動し、CapsLock/Pause/PrintScreen対応値1/0/1の初期ログを確認した。入力は利用者がWindowsと同じUSキーボードから行う。合成入力は送っていない。

OSは`Linux-6.18.33.2-microsoft-standard-WSL2-x86_64-with-glibc2.43`、DISPLAYは`:0`。セッション・実行体／チェッカーhashとPIDは`.work/1087/linux-session.json`、出力は`linux-keyboard.log`／`linux-keyboard-error.log`に記録する。

このX11セッションの`_XIM_SERVERS`には登録がなかった。Linuxのnative XIMによるIME併用は、この環境の実キー試験では確認済みとせず、XIM対応環境での確認を残す。IMEオフの実キー操作後、A短押し／長押し（各1組）、左右Shift／Ctrl／Alt、矢印4方向、通常／テンキーEnter、US記号6個、メニュー、枠外移動に伴うShift解放を確認した。押下数と解放数は各キーで一致した（終了キーQはpressで終了する仕様のためreleaseはログ対象外）。stderrは空、Qでexit0。記録は`.work/1087/linux-observations-01.json`。

ただし、左右Shiftの初期保持は1/1だが、左release行では既に0/0であり、右だけ保持された中間状態は今回の読取りタイミングでは確認できなかった。最新状態はedge時点のsnapshotではないため、これだけで不具合とは断定しない。左だけを離した後1秒待つ操作で再確認する。また左Windows227の通知はない。XKB GetNamesではLWIN133/RWIN134/COMP135があることを別途確認したが、通知がどこで届かなくなったかは未特定。左Windowsも単独で再確認する。

再確認画面について利用者から「開いていない」と報告があった。Linuxプロセスは継続しており、Windows側のWSLg RAILウィンドウ`[WARN:COPY MODE] FORTH/Sigma graphics (Ubuntu)`も存在・可視・非最小化だったが、矩形は別モニターの(11,46)-(567,303)だった。利用者が使っていた前景モニターの作業領域(-1920,55)-(0,1135)へ移動し、(-1238,466)-(-682,723)で前景ウィンドウになったことをAPIで確認した。記録は`.work/1087/linux-recheck-window-visibility.json`。キー入力は注入していない。

利用者の「開き直して」を受け、先の再確認プロセスがexit0で終了済みであることを確認してから、新しいプロセスを起動した。ログは`.work/1087/linux-reopen.log`等。Windows側のWSLg RAILウィンドウを現在のモニターで前景にしたが、利用者から「正常な状態のアプリでない」と報告された。この再起動後の画面は正常と判定せず、キー試験を保留する。

画面の直接取得をComputer Useで試みたが、`Computer Use was not approved to use msrdc`で拒否された。アシスタントによる目視確認はできていない。初期ログやvisible/foregroundフラグだけでは、描画や応答が正常とは判断しない。原因未特定のため、利用者の表示状況を確認してから対応する。記録は`.work/1087/linux-reopen-display-issue.json`。先行して確認した実キーの記録は保持し、再起動後の未確認状態と混同しない。

利用者の画像では、タスクバーのプレビューは灰色のプレースホルダーだけで、黄色い枠が表示されていなかった。所有PIDのX11 drawableをGetGeometry/GetImageで読み取り、480×160・depth24、黒75524画素／黄1276画素（枠の周長と一致）を確認した。画像は`.work/1087/linux-owned-x11-drawable.png`、計数は同名json。これはLinux側の描画を取得したもので、アクセス拒否されたWindowsのmsrdc画面取得とは別である。

`wsl --version`はWSL2.7.11.0、WSLg1.0.73.2、MSRDC1.2.7214。Microsoftの[openvmm#4274](https://github.com/microsoft/openvmm/issues/4274)には同じWSL/WSLg版でWARN:COPY MODE、タスクバーだけ現れる、ウィンドウが空になる症状が報告されている。Westonのrdprail.cでも、共有メモリー描画のuse_gfxredirがfalseの場合にこの警告タイトルを付けることを確認した。ただし、この環境で共有メモリーがEIOになっているかは未確認。原因をWSLgと断定せず、表示経路の問題を疑っている。

リポジトリ外の`/mnt/wslg/weston.log`等は未読。利用者提示のAGENTS.mdはリポジトリ外のファイル読取りに事前許可を要求するため、ログ読取りを確認してから継続する。WSL全体の停止・更新・マウント変更は行っていない。診断記録は`.work/1087/wslg-display-diagnosis.json`。

利用者からリポジトリ外の読取り許可を得て、WSLgログと共有メモリー状態を確認した。Westonの15:21:13の起動ログに、`rdp_allocate_shared_memory: Failed to open ... with error: Input/output error`、`use_gfxredir = 0`、`enable_copy_warning_title = 1`がある。したがって、このセッションの共有メモリー描画の初期化失敗はログで確認できた。下位のvirtiofsがどの契機で失敗したかまでは未特定。

system distroの`/mnt/shared_memory`はwslgをソースとするvirtiofsとしてmount済みで、rootのstat自体は成功した。これは起動時の共有メモリー割当失敗を否定しない。ログのコピーは`.work/1087/weston-readonly.log`、該当行の抜粋は`weston-display-failure-extract.txt`。現行WSL2.7.11.0と、調査時の上流最新安定版[3.0.5](https://github.com/microsoft/WSL/releases/tag/3.0.5)を照合したが、更新は実行していない。

復旧の候補はWSL VM全体の再起動。稼働中のディストリビューションはUbuntuで、確認用Sigma以外にも複数のzshが存在するため、それらを終了させる操作は利用者の承認待ちとする。現時点で`wsl --shutdown`や設定・mountの変更は行っていない。

WSL再起動について、Ubuntuのzsh等を含む全プロセスが終了する影響を説明し、利用者から「許可」を得て`wsl --shutdown`を実行した。停止後のrunning distro一覧は空。その後の起動ログで`use_gfxredir = 1`を確認し、新しいSigmaのWindows側タイトルも`FORTH/Sigma graphics (Ubuntu)`となりCOPY MODE警告が消えた。その後、利用者から「表示されている」と回答があり、Windows側でも実際に黒地に黄色い枠が表示されたことを確認した。復旧後の画面でShift中間状態と左Windowsを再試験する。

新しいチェッカーの記録は`.work/1087/linux-recovery-session.json`、出力は`linux-recovery.log`等。以前のPIDは再起動で無効になったため使い回さない。受け入れ中にWSLが休止しないよう、所有する時間制限付きセッション（最大1800秒）も起動した。PIDと目的は`linux-acceptance-lease.json`に記録し、試験終了時にこのセッションだけを終了させる。WSLの更新・永続設定変更は実行していない。

## 実キーボードの共通手順（1082・1087〜1090）

1. OS・Zig版・Git HEADと未コミット差分、キーボード機種・接続方法・配列を記録する。未コミット差分がある場合は、HEADだけで同一コードとは判定しない。
2. 対象OSで`zig build test --summary all`、`zig build test -Dgraphics=false -Daudio=false -Dfloat=false --summary all`を実行する。その後`zig build`で全体構成の実行体を作る。
3. `zig-out/bin/sigma tests/scripts/check-physical-keys.fs`（Windowsはsigma.exe）を実行する。黄色い枠のnativeウィンドウをクリックし、キーを押す。結果は端末へusageとkind、左右modifierの状態として出る。Qまたはウィンドウ閉鎖で終了する。
4. Aの短押し／長押し、左右Shiftを両方押して片方だけ離す、左右Ctrl/Alt/GUI単独、矢印、通常Enter／テンキーEnter、JISの国際キーを確認する。IMEのon/offで物理番号が変わらず、文字確定の経路は別に動くことを確認する。Ctrl+Cは既存の割込みとして扱う。
5. Alt+Tab／Command+Tabのフォーカス喪失でheldがすべてfalseになること、閉鎖で全解放して終了すること、対応外の問い合わせがfalseになることを確認する。
6. MacはCommand併用のkeyUp、FlagsChangedの左右区別を確認する。device-dependent maskを出さない対象キーボードも、使う場合は左右同時押下を確認し、必要なら対応可否と復旧を修正する。
7. Macのpipe詰まり確認は、このチェッカーの親Sigmaだけを一時停止して行う。`ps -ax -o pid,ppid,command`でチェッカー親PIDを確認し、別端末から`kill -STOP 親PID`。`--sigma-internal-window-child-v1`の子は止めない。ウィンドウで十分な数のキーを押し離してから、すべて離し、`kill -CONT 親PID`で必ず再開する。ウィンドウが応答を続け、復帰後に再同期要求／snapshot採取を経てheldが0へ戻ることを記録する。この手順はまだ実行していない。
8. 実行ログと未確認を本記録へ追記し、該当するOS・配列のタスクだけを完了にする。クロスコンパイルや合成入力だけで閉じない。

### 復旧後の実キー再確認

利用者の操作後、チェッカーはQでexit0。左右Shiftのpress/releaseは各1組あったが、左解放時の保持値は左右とも0だった。独立した20ms間隔のX11 QueryKeymap観測でも、15:47:39に右、続いて左右の押下を捉えた後、15:47:42.995には左右とも解放となり、右だけ保持する中間状態は記録されなかった。実際の解放間隔の確認が必要であり、Sigma固有の不具合とはまだ判定しない。

左WindowsはSigmaにもX11のQueryKeymapにも押下が記録されなかった。同時間帯にフォーカスが外れて戻った記録はあるが、キーが届かなかった原因は未特定。右Windowsは実機にないため対象外。記録は`linux-recovery.log`、`linux-recovery-session.json`、`linux-modifier-server-observations-recovery.json`（いずれも`.work/1087/`）。分割後のLinux USタスク1088は未完了を維持する。

利用者に「左Shift解放後も右Shiftだけを1秒以上保持したか」を確認し、「ok」と回答を得た。この確認と20ms間隔のQueryKeymap記録の不一致を未解決事項として残す。ソース確認ではLinuxホストはキー通知に従って状態を更新し、FocusOut時には全保持を解放する。今回のShift解放時点は観測上フォーカス内だった。受信イベント自体の時刻・keycodeを独立取得する追加診断が必要であり、製品コードの変更は行わない。

Claude Codeの読み取り専用レビューでは、QueryKeymap・GetInputFocus・XKBキー名の解析に誤りは指摘されなかった。一方、旧観測は状態変化のみを保存し、サンプル最大間隔を記録していないため、20ms周期の連続性はログだけでは証明できないとの指摘があった。この制限を踏まえ、右Shift保持がX11に存在しなかったと断定しない。別のX11接続で同じ対象ウィンドウのKeyPress/KeyRelease/Focusイベントを購読する追加診断を準備・起動した。観測接続だけにイベント選択を設定し、入力注入や製品コード変更は行わない。受信イベントはキーを左右Shift/Windowsに限定し、server timeと受信時刻を記録する。新しい記録は`.work/1087/linux-events-session.json`、`linux-events.log`、`linux-modifier-events.json`。

### 追加イベント観測の結果

利用者が左Shiftを離して右Shiftを2秒保持する手順を実施した後、独立したX11接続でkeycode50（左Shift）と62（右Shift）のKeyReleaseを確認した。両方のserver timeは536531msで一致し、受信時刻も15:51:19.182853／19.182909だった。この時点でフォーカスは対象内にあり、次のFocusOutは15:51:25.452915。従って、今回の解放間隔の消失はSigmaのログ出力だけの現象ではなく、独立した接続に届いたX11イベント自体で確認された。Windowsホスト・RDP・Weston・XWaylandのどの段階に原因があるかは未特定。製品コードの変更で補正しない。

左Windowsのkeycode133はイベントにもQueryKeymapにも記録されなかった。フォーカスが外れて戻ったことは確認したが、キーが届かなかった原因は未確定。右Windowsは装備なし。チェッカーはQでexit0、stderrは空。これまでの同一操作の再試験はここで終了し、Linux USの1088にはWSLg経路での左右Shift個別解放／左Windowsの制約とLinux XIM併用を残す。JIS実機はWindowsの1089とLinuxの1090に分離する。ネイティブLinux環境での確認と今回のWSLg環境の結果を区別する。証拠は`.work/1087/linux-modifier-events.json`、`linux-events.log`、`linux-events-session.json`。

## OS・配列ごとのタスク分割

2026-11-19、利用者の指示でWindowsとLinuxを分離した。各タスクは997直下、依存先1081で独立して管理する。既存の証拠ファイルは追跡できるよう`.work/1087/`から移動しない。

| タスク | 対象 | 状態・残件 |
| --- | --- | --- |
| 1087 | Windows US実機 | 完了。上記の実操作とIME確定を確認。右Windows装備なし、機種名不明を記録 |
| 1088 | Linux US実機 | 未完了。WSLg入力経路の制約の切り分けとXIM併用を残す |
| 1089 | Windows JIS追加確認 | 完了。53/136を対象外として保持残留を解消。他4キーの押下解放とIME確定を修正後実機で確認 |
| 1090 | Linux JIS実機 | 未着手。国際キー・左右修飾・片方解放・XIMを確認 |

Mac実機1082は従来のまま未完了。旧1087のWindows/Linux共通範囲を完了扱いにはせず、確認済みのWindows USのみを完了にした。

### 1089 Windows JIS固有キーの実操作

利用者が指定順に実キーを操作した。ろ135・円137・無変換139・変換138は各press/releaseを1組取得。カタカナ／ひらがな136はpressのみ。半角／全角53はpress10回・release9回で最後のreleaseなし。Qでexit0、stderrは空。キー解放が記録されなかった原因は未特定のため1089は未完了。Windows APIのkeyboard type/subtypeは7/2（先行US時4/0）、機種名は未確認。実行体hashは先行Windows USと一致。記録は`.work/1089/windows-session.json`、`windows-keyboard.log`、`windows-jis-observations-01.json`。

### 1089 JIS解放の再確認結果

カタカナ／ひらがな、半角／全角を各1回押して離し2秒待つ手順を依頼し、利用者が操作した後のログを確認した。136はpressのみ、53は複数press/releaseと最後のpressが記録され、Q press時点でもSCAN-HELD?は136/53ともtrueだった。単にイベント行を読み出した時点の状態が先に進んだだけではなく、操作終了時にも保持が残ることを確認した。Qでexit0、stderrは空。イベントが複数になった理由、解放が欠けた経路はまだ未特定。Windowsのキー通知とIME処理の境界を診断する必要がある。

記録は`.work/1089/windows-jis-release.log`、`windows-jis-release-session.json`、`windows-jis-observations-02.json`。Windows US1087の既存証拠は保持し、Windows JIS1089は完了にしない。共通機能の全面再試験は行わず、JIS固有キーの解放残留を対象にする。

### 1089 Windows受信メッセージの診断準備

製品ソースは変更せず、`.work/1089/diagnostic-source/`にソースをコピーし、windowProc先頭でWM_KEY/WM_SYSKEY・WM_IME・FocusOutのmessage、wParam、lParam、scan、extended、transitionをstderrへ記録する診断処理だけを追加した。通常の処理順とDefWindowProcへの転送は維持する。ビルドは10/10工程成功。診断実行体は`.work/1089/diagnostic-bin/bin/sigma.exe`、セッションは`windows-jis-messages-session.json`、受信メッセージは`windows-jis-messages-error.log`。実行体は先行製品バイナリーとは別物としてhashを記録する。

MicrosoftのWM_IME_KEYUP仕様ではDefWindowProcが対応するWM_KEYUPを生成する。既存実装のWM_IME_KEYUPはdefault分岐からDefWindowProcへ渡るため、コードを見ただけではIME解放の取りこぼしは断定できない。実際のwParamと押下／解放のscan・transitionの照合を残す。参考：https://learn.microsoft.com/en-us/windows/win32/intl/wm-ime-keyup 。Claude Codeにも読み取り専用レビューを依頼中。

### 1089 通知列を照合した調査結果

診断用実行体のwindowProc入口ログで、解放通知自体が存在することを確認した。かなはscan0x70のWM_KEYUP（VK0xF0）が先に入り、その後WM_KEYDOWN（VK_PROCESSKEY=0xE5、scan0x70）とrepeatが入る。半角／全角もscan0x29のWM_KEYUP（VK0xF3/0xF4）の後にVK_PROCESSKEYのWM_KEYDOWNが続き、Q直前はdownで終わる。両方とも拡張bitはfalseで、押下と解放のscanは同じ。従って今回の記録では、別scanへの変換や解放通知の全欠落は直接の説明にならない。

現在の実装はWM_KEYDOWN/UPとWM_SYSKEYDOWN/UPをscanに変換してそのまま物理状態へ反映する。取得した通知列を同じ規則で再生すると、Q時点でusage136と53がともにtrueになる。解析は`.work/1089/windows-jis-message-analysis.json`。物理状態の残留を生む直接の処理は、IME処理を経た通常通知を物理押下・解放として扱っている点まで絞れた。なぜこの順序の通知が生成されたか（IME内部、TranslateMessage中の再入など）は、今回のwindowProc入口ログだけでは未特定。物理操作時刻の逆転と断定しない。

Microsoftの[ImmGetVirtualKey仕様](https://learn.microsoft.com/en-us/windows/win32/api/imm/nf-imm-immgetvirtualkey)でも、IME処理後にVK_PROCESSKEYへ変化することと、元VKの取得がTranslateMessage前に必要なことが説明されている。元VKを直すだけでは今回のscanは同じなので通知順の問題を解決できる根拠はない。[Raw Input](https://learn.microsoft.com/en-us/windows/win32/inputdev/about-raw-input)の低水準キーボード通知と既存文字入力を分ける方法を修正候補として検討する。Raw Inputのこの実機でのmake/breakはまだ採取していないため、解決済みとはしない。製品ソースの修正は未実施。

Claude Codeの先行ログレビューは、受信・マッピング・IME合成通知を候補として挙げ、通知の絞り込み前のscan/ext/transition記録を推奨した。今回の追加記録により、同一scanでのup→VK_PROCESSKEY downを確認できた。1089は未完了。

### 1089 対応範囲の決定と修正

利用者の指示により、Raw Input移行は行わずWindowsのusage53と136を物理入力の対象外にする方針とした。53はUSのgrave/tilde位置も同じ番号なのでUSでも対象外。supported bitmapへの登録から除外し、既存Hostのhas検査によってheld・edge・snapshotへ入らないようにした。通常文字入力・IME処理、Linux/Macの対応表は変更しない。設計と英日グラフィック説明に制約を記載。

Windowsの`zig build test --summary all`は23/23工程成功（実行分106pass/11skip、他キャッシュ）。修正実行体のビルド10/10成功。native合成通知の既存7段階受け入れも成功し、追加したup→VK_PROCESSKEY downの再現入力で53/136のsupported/heldは全て0、後続の物理イベント列に混入がないことを確認した。これは自動試験であり、修正後のJIS実キー確認は別に行う。記録：`.work/1089/windows-exclusion-acceptance.json`。

Claude Codeの修正レビューはブロッカーなし。Host.hasによる除外、held/edge/snapshotへの不混入、既存文字・IME経路とLinux/Macの維持を確認した。自動試験はIME本体を通らないこと、snapshot不在は今回の追加assertでは直接検証していないことを制限として記録する。ろ/円/変換/無変換は先行実キーの成功記録を参照し、修正後の実操作をこれから確認する。

### 1089 修正後のJIS実操作

修正実行体hash `3908bda2bc60b1b9974f76911f6a179f69b2e9f9f20b9b3deb1e0e82f1b0104d`で利用者がかな・半角全角、ろ・円・無変換・変換を操作した。53/136のsupportedは0/0、各イベント行とQ終了時点のheldも0/0。53/136のedgeはなく、135/137/139/138は各press/releaseを1組取得。Qでexit0、stderrは空。記録は`.work/1089/windows-jis-excluded.log`と同セッションjson。IMEの確定文字は次のGUI-FIELD確認で別途検証する。

### 1089 最終IME実操作と完了

修正後の同一実行体で、IMEオフの`a`（UTF-8:61）とIMEオンの「あ」（E3 81 82）の2行確定を確認した。物理Aは各入力でusage4のpress/releaseとなり計2組、無変換139・変換138・Enter40も全て押下と解放が対応。対象外53/136の物理イベントはなし。Quitでexit0、stderrは空。記録は`.work/1089/windows-jis-ime.log`、`windows-jis-ime-session.json`、`windows-jis-final-acceptance.json`。

1089はWindows JIS固有キーとIME追加確認の範囲で完了。共通の同時押下・左右修飾・focus等はWindows US1087の証拠を参照する。手元機種名不明、53（US grave/JIS半角全角）と136（かな）はWindows物理入力の対象外という制約を維持する。Linux1088/1090とMac1082は未完了。コミット・プッシュは未実施。

## リモートから取り込んだ実機確認記録（81294af）

以下は別環境で実施されたMac・Linux JISの確認記録。WSLgによる先行確認とは環境・実行体を区別する。過去の未確認・未完了の記述は各試験時点の履歴として保持する。

### 1082 Mac実機の受け入れ（2026-11-19）

対象は`ca82413b26d8616df2092340d04c605813514b0d`、開始時の作業ツリーはクリーン。macOS 27.2.1 Build 26B131（Darwin 27.2.0、arm64）、Mac model identifier `Mac17,3`、Zig 0.17.1、Python 3.15.2。内蔵キーボードを使用。ユーザー申告では左Controlキーとテンキーなし。配列名は未採取。

| 確認 | 結果 |
|---|---|
| `zig build test --summary all` | 23/23工程成功、1178成功・14スキップ。core1071成功・8スキップ、host107成功・6スキップ。 |
| `zig build test -Dgraphics=false -Daudio=false -Dfloat=false --summary all` | 22/22工程成功、958成功・205スキップ。 |
| `zig build --summary all` | 通常構成10/10工程成功。 |
| `verify-extension-matrix.py` | 12構成成功、extension除外イメージ拒否成功。 |
| HELP・語参照、文書 | 語参照check成功。HELP1563、全語彙1777。check-docs findings=0。 |
| 実キーボード | `zig-out/bin/sigma tests/scripts/check-physical-keys.fs`を実行しQで正常終了。A (usage 4)、左右Shift (225/229)、左Option (226)、左右Command (227/231)、矢印 (79〜82)、Enter (40) の押下・解放を取得。長押し中の重複pressはなく、左右Shiftの片側解放後も他方はheld。左Controlとテンキーは機器にない。 |
| 入力経路の独立 | 物理Aのpress/release (usage 4) とGRAPHICS `INKEY` の`a` (97) を別々に取得。 |
| Command併用・フォーカス | Command併用中のキーpress/releaseを取得。ShiftとCommandを保持してアプリを切り替え、フォーカス復帰後に両方のrelease edgeを取得。その後のAイベントで修飾状態はすべて0。Command+Tab自体はOSが処理するためTab edgeはアプリへ届かない。 |
| Fn・電源・音量 | native窓を開いた状態でHID usage 0、POWER、MUTE、VOLUMEUP、VOLUMEDOWNの`SCAN-SUPPORTED?`はいずれもfalse。起動表示のCapsLock/Pause/PrintScreenは0/1/1。 |
| overflow・通信復旧 | 親Sigma PID 67494を1分26秒SIGSTOPし、AppKit子PID 67500が動作を続けることを確認。再開後、物理入力overflowの`KEY-RESYNC`とsnapshot読取りを確認。 |

997の設計・native接続・公開語レビュー回答をコードと照合した。既存レビューで挙がった修正事項は反映済みで、今回新たなブロッキング欠陥は見つからなかった。Mac実機のキー通知、左右modifier、Command併用、フォーカス解放、overflow後のsnapshot復旧を確認した。

## 1090 Linux JIS実キーボード確認（2026-11-19）

環境：Ubuntu 26.04.1、kernel 7.0.0-43、GNOME Waylandセッション（SigmaのウィンドウはXWayland経由）、IMEはfcitx5のXIM。Zig 0.17.1。HEAD `ca82413`。キーボードはCompx 2.4G Receiver（USB 25a7:fa61）経由の無線JIS配列で、機種名は不明、テンキーなし。XKBはevdev／pc105、jp,us。同じマシンにARCHISS M04US（US）も接続しているが、試験ではJISの方だけを使った。左右Altを単押しでIME切替にする常駐ツール（alt-henkan、仮想キーボード）は、試験中だけ止めて終了後に再開した。

手順：`zig build`、`tests/scripts/check-physical-keys-ime.fs`（物理edgeの記録と、IMEを使うGUI-FIELDを同時に動かすチェッカー。今回追加）。ログは`.work/1090/session1.log`、xevによる切り分けは`.work/1090/xev-super.log`。

| 確認 | 結果 |
|---|---|
| 国際キー | ろ135、¥137、無変換139、変換138、カタカナ/ひらがな136、半角/全角53。いずれも押下と解放が1対ずつ届き、supportedは1。Windowsで53/136を対象外にした決定（1089）とはOSで扱いが違う |
| A短押し／長押し | どちらもedgeは1対だけ。長押しでは文字側に`a`が19個入り、repeatは物理edgeにならない |
| 左右Shift同時押下と片方の解放 | 左を先に離すと`shift=01`、右を先に離すと`shift=10` |
| 左右Ctrl・左右Alt・メニュー(101)・矢印・Enter | 正常 |
| IME併用 | 半角/全角でオンにして`a`→Enterで`あ`（E3 81 82）が確定。物理番号はIMEの状態で変わらない |
| フォーカス喪失 | Alt+Tabで、押されたままのキーがまとめて解放された |
| 左右Windowsキー(227/231) | 押下は届くが、解放は届かない。xevでもKeyPressのみで、KeyReleaseは0件。GNOME（overlay-key=Super）がXへ届く前に解放を横取りしているため。**利用者の決定でWindowsキーは使わない**ことにし、XKBのLWIN/RWINを未対応（supported=false、edgeなし）に変更した。修正後に同じ実機で、LGUI/RGUI=false、左Alt・ろ=trueを確認した。Windows版とMacのCommandは変更していない |
| CapsLock/Pause/PrintScreen | X11では1/0/1。PrintScreenの実押下（GNOMEのスクリーンショットに取られる可能性）は未確認 |

未確認：テンキーEnter（キーなし）。IMEをオフにする経路は、IMEの状態変化を明示的に観測していない（確定3の`a`）。

ネイティブglibcビルドの`zig build test`では、997と関係のない`host_resize`のSIGWINCH試験が1件失敗する（sigactionのmask 128バイト全体を比べるため、glibcが書かない末尾の部分で食い違う）。`-Dtarget=x86_64-linux-musl`では全工程が成功する。別タスクで直す。

## 997 Claude Codeレビュー（1090時点）

- 1082の記録（`18800bf`）で、残りの作業はtqueの1088／1090に合わせて書き直された。ただし、冒頭の状況説明と[詳細設計](PHYSICAL_KEY_DESIGN.md)は、まだ「1087＝Windows/Linux実キーボード」のまま。1087（Windows US）と1089（Windows JIS）の実機結果と、1089のタイトルにある「ろ/円/無変換/変換・IME a/あの修正」のコードも、このリポジトリにない。1090はその修正を含まない`ca82413`で実施した。
- Linuxの経路では、XIMへ転送する前に押下を記録すること、保留した解放を毎周期確定すること、IMEから戻ってきたキーが物理状態を変えないことを、コードで確認した。ブロッカーはない。

### 取り込み後の統合状態

リモート81294afをfast-forwardで取り込み、手元Windowsの修正・記録を復元した。英日説明のLinux左右GUI除外とWindows53/136除外を両方保持した。上記1090時点レビューの「Windows修正コードと記録がない」はレビュー当時の状態であり、この作業ツリーでは統合済み。Mac1082とLinux JIS1090は現行tqueで完了。コミット・プッシュは行っていない。

取り込み時に` tque ls --root 1088 --all --json `はNotFoundとなった。削除・移動の経緯はこの操作では確認できないため、1088の完了／未完了を推測しない。先行WSLgの試験結果は履歴として残す。退避stashは安全のため保持している。

# 997 物理キーの実装・受け入れ記録

2026-11-19。1084（native接続）・1085（公開語）・1086（統合レビュー）と1081（Windows/Linux自動受け入れ）を完了。**997全体は未完了。1082（Mac実機）と1087（Windows/Linux実キーボード）を残す。**

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

- 1088：Linux US実機。キー位置、左右修飾と片方解放、IME併用、フォーカス切替を確認し、機種・OS・配列・未対応を記録する。Windows US 1087、Windows JIS 1089、Linux JIS 1090（下記）は完了。
- タスク制御の本物のワーカー実行検査は1049〜1053へ引継ぎ。入力資源を借用せず、worker Writerのphysical_key_opsはnullにする。
- 次の開発項目は予定どおり639・1078（非ブロッキングI/O／ファイル入力待機）。実機確認を完了済みとはせず、依存のない後続を進められる。

## Linux実キーボード確認手順（1088・1090）

1. OS・Zig版・Git HEADと未コミット差分、キーボード機種・接続方法・配列を記録する。未コミット差分がある場合は、HEADだけで同一コードとは判定しない。
2. 対象OSで`zig build test --summary all`、`zig build test -Dgraphics=false -Daudio=false -Dfloat=false --summary all`を実行する。その後`zig build`で全体構成の実行体を作る。
3. `zig-out/bin/sigma tests/scripts/check-physical-keys.fs`（Windowsはsigma.exe）を実行する。黄色い枠のnativeウィンドウをクリックし、キーを押す。結果は端末へusageとkind、左右modifierの状態として出る。Qまたはウィンドウ閉鎖で終了する。
4. Aの短押し／長押し、左右Shiftを両方押して片方だけ離す、左右Ctrl/Alt/GUI単独、矢印、通常Enter／テンキーEnter、JISの国際キーを確認する。IMEのon/offで物理番号が変わらず、文字確定の経路は別に動くことを確認する。Ctrl+Cは既存の割込みとして扱う。
5. Alt+Tab／Command+Tabのフォーカス喪失でheldがすべてfalseになること、閉鎖で全解放して終了すること、対応外の問い合わせがfalseになることを確認する。
6. LinuxではJIS配列の国際キーと左右修飾、XIMのIME on/offを確認する。USの基本キー確認とは別に、1089・1090で対象とするキーの位置・押下解放を記録する。
7. 実行ログと未確認を本記録へ追記し、該当する1088／1090だけを完了にする。クロスコンパイルや合成通知だけで閉じない。

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

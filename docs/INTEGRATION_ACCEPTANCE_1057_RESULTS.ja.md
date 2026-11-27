# 1057：統合受け入れ結果台帳（1415、追記用）

[English](INTEGRATION_ACCEPTANCE_1057_RESULTS.md)

## 1. 記録の範囲と判定

2026-11-26、ロク。記録基点 `99afe6d`。1057全体は未確認で、IA-18は集約の準備段階。今回は既存ログの読取りと静的照合だけで、ビルド・実機実行・時間測定を行っていない。[計画](INTEGRATION_ACCEPTANCE_PLAN_1057.ja.md)§2/4/7/8/11と末尾の決定、[道具](INTEGRATION_ACCEPTANCE_1057_TOOLS.ja.md)、[文書・採否照合](INTEGRATION_ACCEPTANCE_1057_REVIEW.ja.md)を参照。

P=自動機能判定の合格、F=不合格、U=未確認、N=適用外、D=未実施（分類は未確認）。P/Uは自動合格だが手作業等を含むIA全体は未確認。Pは実提示・聴取・時間・完全復元競合の合格を意味しない。Nは語群除外や計画対象外であり、機器不足には使わない。静的なIA-14〜18は全OS・全構成に共通で§4を参照する。

## 2. 出典・実行版・原記録

| 出典 / Source | run ID | 実行時HEAD / Tested HEAD | 方法 / Method | ledger SHA-256 |
|---|---|---|---|---|
| W | 20261126-193555-1be64edd | 92617e7c6b8ca97079f074adce11d0710c37594c | tests/scripts/integration-acceptance.py --functional --configs M0 M1 M2 M3 M4 M5 M6 M7 M8 M9 M10 | 49c8cecbaf81f057fc1df57f1aef4ffdde2e4ad820c937ef0b450ce9482af5c8 |
| W1 | 20261126-201122-54d17ba8 | 92617e7c6b8ca97079f074adce11d0710c37594c | tests/scripts/integration-acceptance.py --functional --configs M1 | 33fd1c0bb941fd67757fbe747d262b98c7d669a09ad835db1dd6517ec46d7215 |
| WT | 20261126-192325-012b4581 | 92617e7c6b8ca97079f074adce11d0710c37594c | tests/scripts/integration-acceptance.py --functional --configs M0 --backend tk --frames 240 | ada16933277ed86814d64f6b2695fb97f74ad411070aa0d19fba4e00663de626 |
| WC | 20261126-192425-c5f0d86e | 92617e7c6b8ca97079f074adce11d0710c37594c | tests/scripts/integration-acceptance.py --functional --configs M0 --backend terminal --frames 240 | 35bf40136528507ab09b09d02a5630e869b80a95e623574ba930720df4d49c4b |
| L | 20261126-193548-e41e290a | 未確認 / unknown | Claude確認済み要約 / supplied Claude-checked summary | 未取得 / unavailable |
| A | 20261126-193548-73ed9e3e | 未確認 / unknown | macOS: descendant lifetime tracking absent | 未取得 / unavailable |
| A6 | 1425、path/search各4組 | 765b6cca36e05edb0c3a60d65fe8571901ecae5f | M0 native、1,200フレームの正式測定 | `.work/1425-summary.json`（各output.binのSHA-256を収録） |
| A7 | 1425の測り直し、path/search各2組 | 6b6a7ac＋1440の作業ツリー | M0 native、1,200フレームの正式測定 | Mac機の `.work/1425b-runs.txt` |

WのM1をW1で置き換える。旧WのM1 IA-03未確認を消さず、最新W1の合格を採用する。WT/WCは[1412報告](../.work/integration-acceptance/1412-diagnosis/REPORT.ja.md)にあるTk/terminalの240枠runで、1,200枠のWと同じ実行としない。Windowsの元記録版はmanifest/ledgerの92617e7、今回の集約版は99afe6d基点の作業ツリー。元のdirty差分・plan/fixture/binary hashを各runのmanifest.json、working-tree.stdout、M*/binary.jsonで追える。実行時HEADが同じでもバイナリ同一とは断定しない。

Windowsのrunはリポジトリ内`.work/integration-acceptance/<run ID>/`に実在し、ledgerのevidence先も確認した。機器・音経路はledgerのsystem default (unverified)のままで、人の回答は未取得。Linux/macOSのファイルにはアクセスせず、今回提示された要約を転記した。Lの「全構成合格」は適用可能な自動機能枝に限り、M10の保存起動やM0以外のIA-05へ拡張しない。L/Aの実行版・機器・backend・ハッシュ・原ログはClaudeが追記する。

## 3. IA×OS×構成・backend

計画§2より広い構成でadapterが実行した合格は補足証拠として残す。各セルの原判定・理由・場面別証拠は、出典runのledger.jsonの同一ia/configuration/backend行を参照する。手作業を要するIAは下記の総合判定を優先する。M11はLinux専用でWindows/macOSでは全IA-01〜13がN。

### Windows

| 構成 / Config | backend | 出典 / Source | IA-01 | IA-02 | IA-03 | IA-04 | IA-05 | IA-06 | IA-07 | IA-08 | IA-09 | IA-10 | IA-11 | IA-12 | IA-13 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| M0 | native | W | P | P | P | D | P/U | D | U | P/U | P/U | P | P/U | P | N |
| M1 | native | W1 | P | P | P | D | N | N | P | P/U | P | P | P | P | N |
| M2 | native | W | P | P | P | D | N | N | U | P/U | P | P | P | P | N |
| M3 | native | W | P | P | P | N | N | N | U | N | P | P | P | P | N |
| M4 | native | W | P | P | P | D | N | N | P | P | P | P | P | P | N |
| M5 | native | W | P | P | P | N | N | N | U | N | P | P | P | P | N |
| M6 | native | W | P | P | P | N | N | N | P | N | P | P | P | P | N |
| M7 | native | W | P | P | N | N | N | N | P | N | P | P | P | P | N |
| M8 | native | W | P | P | P | D | N | N | U | P | P | P | P | P | N |
| M9 | native | W | P | P | P | D | N | N | U | P/U | P/U | P | P/U | P | P |
| M10 | native | W | N | N | N | N | N | N | N | N | N | N | N | N | P |
| M0 | tk | WT | P | P | P | D | P/U | D | P | P/U | P/U | P | P/U | P | N |
| M0 | terminal | WC | P | P | P | D | P/U | D | P | P/U | P/U | P | P/U | P | N |

### Linux

| 構成 / Config | backend | 出典 / Source | IA-01 | IA-02 | IA-03 | IA-04 | IA-05 | IA-06 | IA-07 | IA-08 | IA-09 | IA-10 | IA-11 | IA-12 | IA-13 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| M0 | 未取得 / unknown | L | P | P | P | D | P/U | D | U | P/U | P/U | P | P/U | P | N |
| M1 | 未取得 / unknown | L | P | P | P | D | N | N | U | P/U | P | P | P | P | N |
| M2 | 未取得 / unknown | L | P | P | P | D | N | N | U | P/U | P | P | P | P | N |
| M3 | 未取得 / unknown | L | P | P | P | N | N | N | U | N | P | P | P | P | N |
| M4 | 未取得 / unknown | L | P | P | P | D | N | N | U | P | P | P | P | P | N |
| M5 | 未取得 / unknown | L | P | P | P | N | N | N | U | N | P | P | P | P | N |
| M6 | 未取得 / unknown | L | P | P | P | N | N | N | U | N | P | P | P | P | N |
| M7 | 未取得 / unknown | L | P | P | N | N | N | N | U | N | P | P | P | P | N |
| M8 | 未取得 / unknown | L | P | P | P | D | N | N | U | P | P | P | P | P | N |
| M9 | 未取得 / unknown | L | P | P | P | D | N | N | U | P/U | P/U | P | P/U | P | P |
| M10 | 未取得 / unknown | L | N | N | N | N | N | N | N | N | N | N | N | N | U |
| M11 | 未取得 / unknown | L | P | P | P | D | N | N | U | P | P | P | P | P | U |

### macOS

| 構成 / Config | backend | 出典 / Source | IA-01 | IA-02 | IA-03 | IA-04 | IA-05 | IA-06 | IA-07 | IA-08 | IA-09 | IA-10 | IA-11 | IA-12 | IA-13 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| M0 | native | A/A7 | U | U | U | D | U | P | U | U | U | U | U | U | N |
| M1 | 未取得 / unknown | A | U | U | U | D | N | N | U | U | U | U | U | U | N |
| M2 | 未取得 / unknown | A | U | U | U | D | N | N | U | U | U | U | U | U | N |
| M3 | 未取得 / unknown | A | U | U | U | N | N | N | U | N | U | U | U | U | N |
| M4 | 未取得 / unknown | A | U | U | U | D | N | N | U | U | U | U | U | U | N |
| M5 | 未取得 / unknown | A | U | U | U | N | N | N | U | N | U | U | U | U | N |
| M6 | 未取得 / unknown | A | U | U | U | N | N | N | U | N | U | U | U | U | N |
| M7 | 未取得 / unknown | A | U | U | N | N | N | N | U | N | U | U | U | U | N |
| M8 | 未取得 / unknown | A | U | U | U | D | N | N | U | U | U | U | U | U | N |
| M9 | 未取得 / unknown | A | U | U | U | D | N | N | U | U | U | U | U | U | U |
| M10 | 未取得 / unknown | A | N | N | N | N | N | N | N | N | N | N | N | N | U |

IA-11のP/Uは保存起動・appendの自動成功まで。計画末尾Bが要求する活動中の完全復元は道具§4のZig試験で別記し、窓差替えの試験を実paint競合の証拠にはしない。LのIA-13 M10は要約に結果がなく未確認。Aは短命・逸脱した子孫の寿命証拠がなく、適用可能な全場面を未確認とし、exit 0や他OSの合格で埋めない。

## 4. 全OS・全構成に共通の静的判定

| IA | 判定 / Verdict | 根拠・残件 / Evidence and remaining work |
|---|---|---|
| IA-14 | P | Review §1–2; F1–F4 corrected; N1–N3 recorded |
| IA-15 | P | Review §3 and validation §6; original plan/decisions unchanged |
| IA-16 | P | Review §4; 1140 §1–3 and plan §6 agree; no remeasurement |
| IA-17 | P | Review §5; six stored medians agree; no native additions |
| IA-18 | U | This ledger prepared; native/manual/timing and L/A provenance remain open |

## 5. 未実施・未確認と追記手順

| 対象 / Item | 状態 / State | 次の確認方法 / Next procedure |
|---|---|---|
| IA-04 / MNL-05 | 未実施 | OSごとに保存アプリの窓を手で閉じ、同じプロセスの待機解除・端末回復を観察。連番/処理/保留/破棄とpipe/taskの自動照合を分けて記録。 |
| IA-06 / MNL-02 | macOS数値測定は合格（A7）、MNL-02は未実施 | 1425の初回（A6、未確認）は保持。1440の修正後の測り直し（A7）で合格。MNL-02の聴取は1426で別に依頼。 |
| IA-07のnative能力 / 非EXTENSION描画 | 未実施 | OS/backendごとに能力表示と非対応待機拒否、期限/入力/取消しによる終了を同一runで照合。WT/WCのPをnativeへ流用しない。 |
| MNL-01a / 01b / 01b-f | 未実施 | M0のpathでn、searchでa/b、別起動でfを個別依頼。世代と画像保持を目視しIA-05へ結び付ける。 |
| MNL-03a / 03b | 未実施 | 待機中の物理Ctrl+Cと、task取消し後の再投入を別依頼。入力/カーソル・音/窓の継続と回復を観察しIA-08へ結び付ける。 |
| MNL-04 | 未実施 | 保存bye題材でq、窓消滅と音停止を観察。IA-09のプロセス回収自動ログと分離する。 |
| IA-11 / real paint | 未確認 | 計画末尾Bの同時PCM/task/window Zig試験とD2子/pipe試験の実行記録をOS別に関連付ける。実paintとの競合の観察・試験は差替えと分離する。 |
| macOS 全場面 | 未確認 | 起動前からesloggerのfork/exec/exitを採取し全所有子孫の寿命と端末・場面結果を関連付ける。欠測・権限失敗も保存し、間欠pollのみで回収合格としない。 |
| Linux M11 / IA-13; M10 | 未確認 | Linux原ledger/manifestを取り込み、M11のX11除外能力、M10 image境界の証拠と理由を追記。 |
| L/A の出所 | 未確認 | Claudeが原ledger/manifest、実行版/dirty diff、記録版、OS/機器/backend/音経路、SHA-256、原ログを添付。 |

各手作業は計画§7どおり一度に1件。依頼時に実行体の絶対パス、OS/backend/音経路、対象窓、コマンド、操作・期待結果・止め方を示す。DwmFlush非対応実環境はR6決定の除外を維持し、再要求しない。

### Claudeの追記欄

| 日付 / Date | IA / OS / Config / backend | run / tested / recorded | 自動 / 総合判定 Auto / Overall | 原ログ・SHA-256 / Raw logs | 機器・音経路 / Devices | 人の回答 / Human reply | 制約・次の方法 / Limits, next method |
|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — |

新しいrunを別行で追加し、旧失敗・未確認と置換理由を残す。raw hashとhuman-reply.jsonを結び付け、要約の出典と直接ログを区別する。英日同じキーの行を同時に更新し、自動判定だけでMNLや測定を合格へ変更しない。

## 6. 今回の文書検証

2026-11-26：`python scripts/check-docs.py`は指摘0、`git diff --check`は成功。新規4文書のローカルリンク106件と引用した節の実在、Windows ledgerのevidence先、1001の保存7値の中央値6件、英日構成とLFを確認した。計画の英日ファイルはHEADと同一で、決定表も変更していない。

## 計画の固定（IA-06の測定の前、2026-11-26）

日本語版の計画を正本とし、そのSHA-256を `--plan-sha256` に渡す。計画の英日は `.gitattributes` で `-text` にし、3 OSの取り出しで同じバイト列になるようにした。

| 文書 | SHA-256 |
|---|---|
| INTEGRATION_ACCEPTANCE_PLAN_1057.ja.md（正本） | `bab8017fa35c6448d4d0cdbe8ebf2b2040d907fff420489a873cf95d9a8f08d2` |
| INTEGRATION_ACCEPTANCE_PLAN_1057.md | `da20c53d90710e430b77534a5ce299194e499da7adb99b712c63e3633c41020e` |
## macOSの子孫の寿命の追跡（1423、2026-11-26）

macOSの自動の実行（`.work/integration-acceptance/20261126-204614-acd76ed6`、M0〜M9、HEAD `99afe6d`）は、174場面すべてが「macOSの子プロセスの間欠的な調査を超える寿命の追跡が必要」という理由だけで未確認だった（それ以外の理由で合格しなかった場面は0件）。レモンが `sudo eslogger fork exec exit` で記録し（`.work/1414-eslogger.jsonl`、28,711件、11:45:13〜12:21:44 UTC）、実行の期間（11:46:14〜12:20:51 UTC）を含むことを確かめた。`tests/scripts/eslogger-process-tree.py` で集計すると、run の保存アプリなど204個とその子孫238個がすべて終了し、終了していないものは0個だった。これにより、macOSのIA-01〜03・05・08〜12・13（M9）は、Windows・Linuxと同じく自動の判定で合格とする。IA-04・06・07の一部・手作業は、他のOSと同じく別のタスクで確かめる。
## LinuxのM11（X11なし）のIA-07・IA-13（1420、2026-11-26）

adapterはM11のIA-13を自動では判定せず、常に未確認とする（`tests/scripts/integration-acceptance.py:347`）。Linux機で、M11をTk（`.work/integration-acceptance/20261126-212518-c4bf82b5`）と端末（`20261126-193339-3d89dcf4`）のbackendで実行し、どちらもIA-01〜03・07〜12が合格し、`normal` の場面で `IA-FRAME-WAIT rejected no-capability; deadline/input fallback` と `IA-BUDGET deadline reached` が出た。X11なしの構成で、ネイティブのフレーム完了の待ちを能力がないとして拒否し、期限と入力で進んで終わることを示す。Claudeはこれを根拠に、IA-13（M11）を合格と判断した。
## macOSのM0のTk・terminal backend（1424、2026-11-26）

Tk（`.work/integration-acceptance/20261126-212155-d3dee35b`）とterminal（`20261126-212545-283a799a`）で、各23場面とも未確認の理由は「子孫の寿命の追跡が必要」だけだった。同じeslogger記録（`.work/1414-eslogger.jsonl`、12:30:08 UTCまで）で集計し、Tkはrunのプロセス26個と子孫99個、terminalは26個と子孫36個がすべて終了した。IA-07を含め、Windows・Linuxと同じく合格とする。
## WindowsのIA-06（1417、2026-11-26）

計画（日本語版 SHA-256 `bab8017f…`）で固定した条件で、M0の保存アプリの入口からPCMを再生しながら測った。利用者の指示（「いつでも進めて」）で開始し、他のアプリの停止は求めていない。最初の3回は道具の不具合で判定に至らず（ConPTYが記録の途中に制御列を入れた、同じく端末の行が分かれた、複合待機の入力の時刻を記録していなかった）、adapterと計測用ビルドの記録を直して4回目で判定した。失敗したrunも `.work/1417-runs*.txt` に残す。

| 組 | 入力→画面の最大 | 入力→端末の最大 | 各フレームの期限超過（負荷／基準） | 追加の超過 | PCM underrunの増分 |
|---|---:|---:|---:|---:|---:|
| path 1 | 26.77 ms | 28.12 ms | 0／0 | 0 | 0 |
| path 2 | 10.97 ms | 12.14 ms | 0／0 | 0 | 0 |
| path 3（80%規則の追加） | 10.54 ms | 11.90 ms | 0／0 | 0 | 0 |
| path 4（80%規則の追加） | 11.74 ms | 13.01 ms | 0／0 | 0 | 0 |
| search 1 | 13.15 ms | 14.65 ms | 0／0 | 0 | 0 |
| search 2 | 26.30 ms | 27.50 ms | 0／0 | 0 | 0 |

全組で、基準とフレーム数1,200・入力数6が一致した。path 1の26.77 msが目安33.34 msの80%（26.67 ms）を超えたため、計画どおり独立2組を追加し、元の組を含めて残した。判定：WindowsのIA-06は合格。run IDは `.work/1417-runs4.txt` と `.work/1417-runs4-extra.txt`。
## Windowsの手作業 MNL-01a〜05（1418、2026-11-26〜27）

M0のnative。利用者が自分のPowerShellで `--manual <単位>` を実行し、`キー>` に端末キーを打ち、`観察結果>` に答えた。道具の不具合（qの後に入力を待つ、Ctrl+Cが中断として届かない、音を鳴らさない、保存アプリの表示が利用者に見えない）を直して進めた。答えの欄が空や `done` だった単位は、チャットでの利用者の回答をClaudeが書き写し、その旨を `human-reply.json` に記録した。

| 単位 | 観察 | run |
|---|---|---|
| MNL-01a | 問題なし（nでRequestedが増えGenerationが追いつき、古い値に戻らない） | `20261126-214314-22fdffeb` |
| MNL-01b | 問題なし（a・bで同様） | `20261126-214846-207f770a` |
| MNL-01b-f | 問題なし（fの後もGenerationと表示が残る） | `20261126-214957-ffbb5770` |
| MNL-02 | 問題なし（合成音に乱れなし、キーに画面が反応） | `20261126-215101-ce76c751` |
| MNL-03a | ok（Ctrl+CでIA-CAUGHT、窓と音が続く） | `20261127-175012-bce2d422` |
| MNL-03b | OK（cで取消しと投げ直し、nで新しい結果） | `20261127-175137-3a541c85` |
| MNL-04 | ok（qでIA-EXIT live BYE、窓が消え音が止まる） | `20261127-175338-a70ec686` |
| MNL-05 | ok（閉じるボタンでIA-WINDOW-CLOSED、IA-CLEAN error=0） | `20261127-175430-85f15024` |

判定：WindowsのMNL-01a〜05はすべて合格。IA-04（closeの待ち解除）・IA-05・IA-08・IA-09の人の観察の部分を満たす。
## LinuxのIA-06（1421、2026-11-27）

最初の試しのrunで、POSIXの端末入力の経路でinputの時刻が0になった（`.work/integration-acceptance/20261127-180335-e2f5d3ff`）。Windowsと同じく、計測用ビルドだけで、POSIXの1バイトの読み取り（`src/host_input.zig` の `posix.readByte`）で最初の取得時刻を記録するように直し、試験を加えた（通常ビルドの動作は同じ）。そのうえで、Linux機の実際の画面（GNOME/Mutter＋XWayland）で測った。run IDはLinux機の `.work/1421-runs.txt`。

| 組 | 入力→画面の最大 | 入力→端末の最大 | 各フレームの期限超過（負荷／基準） | 追加の超過 | PCM underrunの増分 |
|---|---:|---:|---:|---:|---:|
| path 1 | 12.95 ms | 12.06 ms | 0／0 | 0 | 0 |
| path 2 | 16.27 ms | 15.50 ms | 0／0 | 0 | 0 |
| search 1 | 21.51 ms | 20.95 ms | 0／0 | 0 | 0 |
| search 2 | 19.85 ms | 18.83 ms | 0／0 | 0 | 0 |

全組で基準とフレーム数1,200・入力数6が一致した。最大21.51 msは目安33.34 msの80%未満で、追加の組は不要。判定：LinuxのIA-06は合格。

## macOS IA-06（1425、2026-11-27）

計画SHA-256 `bab8017fa35c6448d4d0cdbe8ebf2b2040d907fff420489a873cf95d9a8f08d2`、HEAD `765b6cca36e05edb0c3a60d65fe8571901ecae5f`、M0/nativeでpath/search各1,200フレームを独立2組測定した。入力→画面の最大が各題材で33.34 msの80%以上となったため、計画§8どおり追加2組ずつ実施した。

| 題材・組 | 入力→画面 最大 | 入力→端末 最大 | 要求→完了 超過数（負荷／基準） | 追加超過 | PCM underrun増分（負荷／基準） | accepted frames（負荷／基準） | 欠測端点数（負荷／基準） |
|---|---:|---:|---:|---:|---:|---:|---:|
| path 1 | 41.221 ms | 23.864 ms | 398／9 | 389 | 0／0 | 958,336／958,336 | 506／41 |
| path 2 | 33.925 ms | 20.020 ms | 123／664 | 0 | 0／0 | 958,816／958,816 | 139／763 |
| path 3（追加） | 32.076 ms | 23.352 ms | 166／154 | 12 | 0／0 | 958,816／958,816 | 182／166 |
| path 4（追加） | 32.467 ms | 23.368 ms | 663／194 | 469 | 0／0 | 958,336／958,816 | 754／207 |
| search 1 | 30.132 ms | 22.312 ms | 177／172 | 5 | 0／0 | 958,336／958,816 | 262／185 |
| search 2 | 31.966 ms | 21.478 ms | 111／534 | 0 | 0／0 | 958,336／958,816 | 125／650 |
| search 3（追加） | 32.069 ms | 20.938 ms | 160／364 | 0 | 0／0 | 958,336／958,816 | 174／483 |
| search 4（追加） | 29.286 ms | 19.906 ms | 162／91 | 71 | 0／0 | 958,816／958,336 | 176／108 |

8組すべてで負荷・基準の描画列は一致し、各runのPCM underrun増分は0だった。一方、全組で個別paint/wait端点が欠け、path 4とsearch全組でaccepted framesが負荷・基準間で480異なる。観測できた追加超過もpath 1/3/4とsearch 1/4に残る。よってmacOS IA-06は未確認とし、成功とは判定しない。音声経路はsystem default（未確認）。MNL-02の人による聴取は別途未実施。run ID、実行体・raw outputのSHA-256は `.work/1425-summary.json` にある。先行の不正な計測試行も各 `.work/1425-*/` 下に保持した。

## Linuxの手作業 MNL-01a〜05（1422、2026-11-27）

Linux機のデスクトップ（GNOME/Mutter＋XWayland）の端末で、利用者がtque 1422の備考の手順に従って実行した。8単位とも自動の判定は合格、強制的な後始末なし、観察の答えはOKまたはok（Linux機の各runの `M0/human-reply.json`）。

| 単位 | 確かめた表示 | run |
|---|---|---|
| MNL-01a | IA-CLEAN error=0 | `20261127-185201-963d2260` |
| MNL-01b | IA-CLEAN error=0 | `20261127-185310-fa4b1253` |
| MNL-01b-f | IA-CLEAN error=0 | `20261127-185337-88b5e1b8` |
| MNL-02 | IA-CLEAN error=0 | `20261127-185404-9764766d` |
| MNL-03a | IA-CAUGHT、IA-CLEAN error=0 | `20261127-185435-4d79b310` |
| MNL-03b | IA-CANCEL resubmitted、IA-CLEAN error=0 | `20261127-185510-ca063f21` |
| MNL-04 | IA-EXIT live BYE | `20261127-185645-1f34064b` |
| MNL-05 | IA-WINDOW-CLOSED、IA-CLEAN error=0 | `20261127-185701-8febe452` |

判定：LinuxのMNL-01a〜05はすべて合格。Claudeが道具の確認のために動かしたMNL-03a（`20261127-180115-cf93845f`（Xvfb）、`20261127-180218-f7df2c56`（入力を流し込んだもの））は、受入れの証拠に使わない。

## macOS IA-06の測り直し（1425・1440、2026-11-27）

A6の未確認の原因を1440で調べた。親から子への画像の送信は最大約1 ms、子の描画は最大12.3 msで、遅れは子の「描いた」の通知を親が読むまでの区間（最大34.8 ms）にあった。親は決まった処理の途中でしかpipeを読まず、子は画面の更新ごとにまとめて描くので間のフレームが描かれないことがあった。1440で、親に子のpipeの読取りスレッドを設けて到着時刻で端点を記録し、子は各FRAMEを受け取った直後に描くようにした。

| 題材・組 | 入力→画面 最大 | 入力→端末 最大 | 期限超過（負荷／基準） | 追加超過 | 欠測端点 | PCM underrun増分（負荷／基準） | accepted frames（負荷／基準） |
|---|---:|---:|---:|---:|---:|---:|---:|
| path 1 | 14.83 ms | 14.66 ms | 0／0 | 0 | 0 | 0／0 | 958,816／959,776 |
| path 2 | 19.87 ms | 19.71 ms | 0／0 | 0 | 0 | 0／0 | 958,816／959,776 |
| search 1 | 14.84 ms | 14.66 ms | 0／0 | 0 | 0 | 0／0 | 958,816／959,776 |
| search 2 | 19.46 ms | 19.32 ms | 0／0 | 0 | 0 | 0／0 | 958,816／960,256 |

全組で、基準とフレーム数1,200・入力数6・描画列が一致した。最大が33.34 msの80%（26.67 ms）未満なので追加組はない。

accepted framesの扱い（2026-11-27、レモンの決定A）：accepted framesは測定区間の長さで変わる量で、負荷側と基準側の差を不合格の理由にしない。計画§8の「欠落」は記録の欠落、「供給方式の差」は供給の仕方の違いと読み、音の欠けはunderrun増分（全run 0）で判定する。Windows（1417、差は約1万〜5万frames）とLinux（1421、差0）の合格もこの扱いと一致する。

判定：macOSのIA-06は合格。run IDはMac機の `.work/1425b-runs.txt`。

## macOSの手作業 MNL-01a〜05（1426・1442、2026-11-27）

Macのターミナルで、利用者がtque 1426の備考の手順に従って実行した。観察の答えはすべてOKまたはok（Mac機の各runの `M0/human-reply.json`）。8単位とも強制的な後始末はなく、IA-CLEAN error=0（MNL-04はIA-EXIT live BYE）。

| 単位 | 確かめた表示 | run | 実行体 |
|---|---|---|---|
| MNL-01a | IA-CLEAN error=0 | `20261127-201016-b147caed` | 58fa00a |
| MNL-01b | IA-CLEAN error=0 | `20261127-201058-f7055782` | 58fa00a |
| MNL-01b-f | IA-CLEAN error=0 | `20261127-201124-7f6a1b70` | 58fa00a |
| MNL-02 | IA-CLEAN error=0 | `20261127-201146-6bbc52bc` | 58fa00a |
| MNL-03a | IA-CAUGHT、IA-CLEAN error=0 | `20261127-202404-f2115c56` | 58fa00a＋1442 |
| MNL-03b | IA-CANCEL resubmitted、IA-CLEAN error=0 | `20261127-201333-dd3efd39` | 58fa00a |
| MNL-04 | IA-EXIT live BYE | `20261127-201426-1ab471ed` | 58fa00a |
| MNL-05 | IA-WINDOW-CLOSED、IA-CLEAN error=0 | `20261127-201441-43f14454` | 58fa00a |

最初のMNL-03a（`20261127-201210-0d1b9296`）は不合格だった。IA-CAUGHTの直後に保存アプリがHOST FUNCTION ERRORで終わり、音が止まった。物理Ctrl+CのSIGINTは前面のプロセスグループ全体に届き、AppKitの窓の子プロセスも終わっていた。Claudeが入力を流し込んだrunで再現し（`20261127-201804-29170cda`）、1442で窓の子プロセスがSIGINTを無視するよう直した。修正後の流し込みの確認（`20261127-201924-f3eb73f7`）と、利用者のやり直し（`20261127-202404-f2115c56`）で合格。1442の修正は窓の子プロセスのSIGINTの扱いだけで、ほかの7単位の観察には関わらない。

自動の判定は、8単位とも「native lifetime tracing required beyond macOS child polling」で未確認。esloggerなしで実行したためで、ほかの理由の未確認・不合格はない。

判定：macOSのMNL-01a〜05の人の観察はすべて合格。子孫プロセスの後始末の判定は未確認。

## macOSのeslogger記録下の再実行（1443、2026-11-27）

1440・1442の修正後の実行体（HEAD `73b782c`）で、M0〜M9の自動の判定を1423と同じ引数で実行した（`.work/integration-acceptance/20261127-210221-a3d08a10`、21:02:21〜21:40:41 JST）。164場面すべてが「macOSの子プロセスの間欠的な調査を超える寿命の追跡が必要」という理由だけで未確認で、ほかの理由の未確認・不合格は0（1423の実行と同じ形）。

レモンが `sudo eslogger fork exec exit` で記録し（`.work/1443-eslogger.jsonl`、9,439件、12:02:10〜12:57:05 UTC）、runの期間を含むことを確かめた。`tests/scripts/eslogger-process-tree.py` で集計すると、runの保存アプリなど204個とその子孫238個がすべて終了し、終了していないものは0だった（`.work/1443-process-tree.txt`）。

判定：修正後の実行体でも、macOSのM0〜M9の自動の判定は合格。レモンの決定A（2026-11-27）により、手作業MNL-01a〜05の子孫プロセスの後始末も、この記録で確かめたとみなす。手作業の終わり方（q、BYE、窓を閉じる、Ctrl+C）は、自動の判定のexit-quit・exit-bye・fault-window・中断の場面と同じ経路である。よってmacOSのMNL-01a〜05は合格。

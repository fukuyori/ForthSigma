# 1084・1085 実装レビューの評価と反映

2026-11-19。[ホスト接続原文](1084-native-claude-review.md)、[公開語原文](1085-public-claude-review.md)。以下はソースとの照合後の判断。実行結果とは区別する。

## ホスト接続

| 指摘 | 採否・対応 |
|---|---|
| H1 MacのSCANSYNC重複送信 | 採用。非blockingの9バイトwrite成功時に再送待ちを消す。失敗時だけ次回へ残す。Unix pipeの正常なwrite済み命令をポーリングごとに再送しない。子はatomicな要求印へまとめ、次の周期で最新snapshotを送る |
| H2 Pause/PrintScreen | 採用。SDL_windowsevents.cで非拡張0x45のPause特例とPrintScreenの押下合成を確認。実際の両edgeを保証しないのでWindowsで未対応。NumLockは拡張0x45を使う |
| M1 閉鎖後のSCANによるstale残留 | 採用。unavailable中の物理行は読み捨てる。新しい子の受信状態は初期化し、既存Trackerがstaleならsync要求を引き継ぐ。回帰テスト追加 |
| M2 両Shift時のkeyup欠落 | 採用。SDLの実装コメントとGetKeyState照合処理を確認。UIタイマー16msで左右Shiftの解放だけを補う。タイマー生成失敗時は両Shiftを未対応とする。受け入れスクリプトはSendInputで所有ウィンドウへShiftを送り、片方だけを離した状態を検査 |
| M3 XKB取得失敗の握りつぶし | 採用。消費済みのX11 error packetをXErrorとして区別。Unavailable/XErrorだけを物理機能なしへ変換し、期限切れ・途中読取り等は伝播させて既存の切断処理へ渡す |
| M4 Macのstdout lock待ち | 採用。短い状態用physical_guardとstdout用try-lockを分離。命令スレッドは状態lockもtry-lock。物理edgeの出力は待たず、失敗をdirtyへ集約。SenderをOS非依存モジュールへ分け、最後の解放を落として追加edgeなしで周期flushから復旧するテストを追加 |
| L1 Fn | 採用。Darwin keyCode63のSDL互換fallbackを0へ変更し、Fnを右GUIと混同しない |
| L2 device-dependent bitのないMacキーボード | 実機確認へ引継ぎ。標準maskとaggregateの整合を使うが、特殊なキーボードで左右の両方の変化を保証できるとは記載しない。1082で純正／対象キーボードの左右同時押下を確認し、必要なら対応可否と復旧を修正する |
| L3 電源・音量 | 採用。Windows/MacのPower102、Mute/Volume127〜129は未対応にし、Mac子も生成しない。HID keyboard page上の定数は残し、SCAN-SUPPORTED?で確認する |
| L4 X11のPAUS | 採用。実際の解放を保証しないので未対応 |
| L5 Menu正式名 | 採用。libxkbcommonのxkeyboard-config fixtureでCOMPとMENU aliasを確認し、COMPを受理 |
| L6 表の長さ | 採用。Windows256、Darwin128を型で固定 |
| L7 SelectEventsコメント | 採用。NamesNotifyも購読する旨へ修正 |

レビュー後の確認で、XKBのAB11/AE13が一般行の範囲判定で先に0になっていた点も修正し、国際キーとCOMPの回帰検査を追加した。

## 公開語

| 指摘 | 採否・対応 |
|---|---|
| SC-FRONT165 | 削除。SDL独自のSun Front項目であり、今回のホスト表にも現れない。未確認のHID予約範囲を事実とは断定せず、公開対象から外す。定数は218個（215 usage＋3 kind） |
| 定数値とホスト表の対応試験 | 採用。全SC usageの4〜255範囲・重複なし・Windows/Darwin表の全非0値を網羅する試験を追加。XKB代表名も確認 |
| writtenの再配置記録 | 採用。32バイトcopyで重なる登録セルがdamagedになる試験を追加 |
| HELP | First256の空白と、予約0〜3の扱いを補足 |

機能除外構成では公開語の直接実行テストをcomptimeで除外する。実装で存在しないgraphics用voidフィールドの解析をテストから誘発しない。製品側の語の除外を解除して回避しない。

## 一次実装の照合

GitHub APIでSDLのSDL_windowsevents.c（Pause特例、PrintScreen合成、両Shiftのkeyup欠落対策）、SDL_cocoaevents.m（sendEventでKeyDown/Up/FlagsChangedを親へ渡す前に処理）、Apple objc4/runtime/message.h（objc_superとobjc_msgSendSuper）、Apple IOHIDFamilyのIOLLEvent.h（左右modifier mask）、libxkbcommon/test/data/keycodes/evdev（COMP/MENU）を確認した。コード・型・数値の根拠と、Macでの実際の効果の確認を区別する。

最終の統合レビューと実行記録は別途保存する。Mac実機1082はこのレビューだけでは閉じない。

## 最終判断

[1086最終統合レビュー](1086-integration-claude-review.md)に統合を止める欠陥の指摘はなく、最終コードのWindows/Linux自動検証、Mac全体／除外コンパイル、12構成試験、語参照の実辞書と使用例の検証が成功した。1084・1085・1086と親実装1080、1081自動受け入れを完了した。

実キーボードの確認を完了と混同しないため、Windows/LinuxのJIS/US・国際キー・左右同時押下等は1087へ分け、1082 Mac実機とともに未完了とした。最終レビューの非同期XErrorの切断条件、Macの特殊modifier maskの制約も実装記録へ残した。997全体は閉じていない。

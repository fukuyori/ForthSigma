# Linuxの構成変更通知：レビューと修正確認

2026-11-23。実機の切断でWINDOW-CHANGESが増えない不具合を検出した。[失敗記録](../measurements/2026-11-23-linux-hotplug-changes-failure.json)では、DRMがdisconnected・EDIDが消失し、DISPLAYSは2→1、窓はDP-3からDP-2へ移動して生存したが、変更回数は2のままだった。

従来はConfigureNotifyのあとにだけ所属画面を再照会していた。Mutterの移動通知がRandRの一覧更新より先に来ると、寸法が同じままの窓について、後から変わった画面構成を再照会できなかった。

ウィンドウのX接続でRRSelectInputのScreen/CRTC/Output/Resource変更を購読し、first_eventとfirst_event+1で構成と位置のキャッシュを無効化する。rootの_NET_WORKAREAと_NET_CURRENT_DESKTOPも購読し、サイズや旧キャッシュの所属が同じでも変更回数を更新する。閉じた窓の回数は増やさない。

[Claude Code静的レビュー](1037-linux-randr-changes-claude-review.md)は中以上のバグなし。Read/Grep/Globだけを許可し、実行や編集はしていない。[メタデータ](../measurements/2026-11-23-linux-randr-review-metadata.json)。

低指摘にも対応した。

- 関係ないrootのPropertyNotifyを、保留中のKeyReleaseを処理する前に捨てる。detectable repeatがない環境でrelease/pressの組を壊さない回帰テストを追加。
- 構成通知は複数のイベントとして届くため、1回の変化で複数回増えうることを文書化。回数をイベント件数と同一視しない。
- Linuxでは画面構成を数えないとしていた互換性表・グラフィックスガイド・詳細設計を更新。

通常ビルドとzig build testが成功。ホスト186成功・17skip（追加回帰3件を含む）、他はキャッシュ。通常の[表示先選択38段階](../measurements/2026-11-23-linux-randr-window-regression.json)も成功した。

`python3 tests/scripts/verify-linux-display-change-events.py --output docs/measurements/2026-11-23-linux-randr-event-routing.json`で、所有する窓に合成RandRリソース通知を送り、画面数・所属・窓の大きさが変わらないまま、変更回数が1→2となった。[記録](../measurements/2026-11-23-linux-randr-event-routing.json)。画面構成そのものは変えない、イベント処理の回帰検査である。物理抜き差しの合格には使わない。

先行する修正後試行は300秒内に再切断が観測されずincompleteだった。その後の[最終実機確認](../LINUX_DISPLAY_HOTPLUG_VALIDATION.md#最終実機確認完了)で、切断・不在画面の指定での再起動・再接続・10秒保持・明示的選択を確認し、利用者の事後申告も記録した。1336・1345と共通受け入れ1047は完了。1037全体はWindowsの葉3件を残して93%。

# LinuxのWINDOW-ON実機確認（1345）

2026-11-23、Linux x86_64 / GNOME WaylandのXWayland、Zig 0.17.1。HEAD `e7514502c1a8d667037cc5557013ee37d4377ee8`に未コミットの表示支援修正を加えた通常ビルド。実行体と検証対象ソースのSHA-256は[結果JSON](measurements/2026-11-23-linux-window-on.json)に記録する。

## 手順と結果

`python3 tests/scripts/verify-linux-window-on.py --output docs/measurements/2026-11-23-linux-window-on.json`

現在の2画面で38段階が成功。Sigmaの所有ウィンドウだけを操作し、このスクリプト自体は画面の配置・倍率・接続構成を変更しない。各段階をKEYで区切り、専用のプロセスグループでSigmaと補助プロセスを管理する。長い検証ソースは一時ファイルからINCLUDEし、`-e`の入力長制限に依存しない。

- 両画面それぞれへの起動前指定。指定だけでは窓を開かず、SHOWで指定画面に開く。
- 表示中の移動は作業領域の中央で、64×40の大きさを保つ。
- 全画面中の移動と通常表示への復帰。全画面を始めた画面と最後の移動先を変え、位置の更新漏れを検出する。
- -1は現在位置を変えない。DISPLAYS以上と-2は-24を返し、現在位置を変えない。
- 通常の全画面往復、大きい通常窓（2200×1200）を小さい画面へ移してから戻す場合の縮小（1920×1011）、大きいままの3ms間隔の連続指定。
- FALSE FULLSCREENとWINDOW-ONの同時操作、WMの移動要求で通常窓を動かした後の全画面往復、SHOWより前のTRUE FULLSCREEN、全画面への遷移とWINDOW-ONの同時操作、3ms間隔の連続移動、移動中のWINDOW-SIZEとSHOW。

WINDOW-DISPLAY・WINDOW-PIXELS・FULLSCREEN?に加え、独立のX11接続でRandRの画面矩形、GetGeometry、TranslateCoordinates、_NET_FRAME_EXTENTS、_NET_WORKAREA、_NET_WM_STATEを取得して照合する。通常表示は枠を含む中央位置、全画面表示は画面の左上と幅・高さを確認する。通常倍率では座標の完全一致を求める。混在倍率での丸めと座標の単位は[別の検証記録](LINUX_MIXED_SCALE_VALIDATION.md)を参照する。

## 修正とレビュー

初回の13段階では、全画面から通常表示へ戻した窓が副画面の左上（内容領域原点0,69）に寄ることを発見した。全画面中の寸法ではなく、通常時のサイズと枠の厚みを使って中央を計算するよう修正した。

Claude Codeに[初回レビュー](reviews/1037-linux-window-on-claude-review.md)と[再レビュー](reviews/1037-linux-window-on-claude-followup.md)、[最終レビュー](reviews/1037-linux-window-on-claude-final.md)を依頼し、指摘と追加の実行検証に基づいて次を補強した。各レビューは固定スナップショットへの静的レビューであり、Claudeはテストを実行していない。

- WMの状態通知だけで復帰済みとせず、GetGeometryで元の通常サイズへの復帰を確認してから、必要なときだけ縮小・移動する。サイズ指定を早く送ると、復帰中の枠の再作成と競合し高さが3になることを試作で確認した。
- 移動先のサイズ・位置の反映を確認してから全画面へ入り直す。未確定の移動先に合わせて計算したサイズを、次の指定で「元のサイズ」として使わない。
- 普通の全画面解除とWINDOW-ONによる復帰を区別し、前者ではWMの復帰位置を上書きしない。キャンセル後は古い通常矩形を捨てる。
- WMへの全画面要求、元のサイズへの復帰待ち、移動後の確認にはそれぞれ1000msの期限を設ける。要求の無視で以後のWINDOW-ONを永久に保留しない。
- 新規起動では通常窓を指定先へ置いてから全画面へ入る。遷移中もAlt+Enterで解除できる。

普通の全画面解除でWMが別画面へ復帰させる経路は、強制移動しないコードを静的に確認した。WMの外部ショートカットによる全画面窓の移動はこの自動検証には含めない。最大化した窓は別途確認が必要である。

## WMが要求を無視する場合

`python3 tests/scripts/verify-linux-fullscreen-rejection.py --output docs/measurements/2026-11-23-linux-fullscreen-rejection.json`

[結果](measurements/2026-11-23-linux-fullscreen-rejection.json)。所有する窓だけを一時的にoverride-redirectにしてWMの管理対象から外した。全画面要求が保留中であることを100ms後に確認してからWINDOW-ONを加え、全画面要求が反映されないこと、期限後にFULLSCREEN?が偽へ戻ることを確認した。再びWMの管理に戻すとWINDOW-ONで副画面へ移動できた。非EWMHのWMそのものを導入して試した記録ではない。デスクトップ全体のWMや設定は変更しない。

通常ビルド・zig build test・文書照合が成功。詳細は[レビュー対応](reviews/1037-linux-window-on-review-response.md)を参照。

## 残る確認

1345は未完了。物理的に画面を外した場合と再接続が残る。Windows1344の実機確認も残る。ソフトウェアによる画面の無効化を物理切断の代用にはしていない。

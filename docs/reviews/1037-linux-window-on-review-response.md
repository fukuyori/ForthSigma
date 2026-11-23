# 1037 Linux表示支援：Claude Codeレビューへの対応

2026-11-23。利用者の指示でClaude Code CLIへ3回、固定スナップショットを渡して静的レビューを依頼した。許可したツールはRead/Grep/Globだけで、編集・コマンド・ビルド・ネットワーク利用を依頼していない。全回正常終了、permission_denialsは空。[実行メタデータとスナップショットの指紋](../measurements/2026-11-23-linux-display-review-metadata.json)を参照。モデル表示はclaude-opus-5-5。

| 指摘 | 対応・確認 |
|---|---|
| キャンセル後の古いnormal_rect | 復元の実状態を確認し、再入場しない場合は破棄。FALSE FULLSCREENとWINDOW-ONの同時操作、移動後のユーザー位置での全画面往復を追加 |
| 大きい通常サイズが移動先に入らない | 復帰前の通常サイズを記録し、元のサイズへの復帰を確認してから縮小・移動。2200×1200から1920×1011への縮小を実機確認 |
| 全画面での新規起動、遷移中の連続指定 | 最初の配置を確認してから全画面へ。state_asked中は移動先を保留し、未確定サイズで取り直さない。3ms間隔の小さい窓・大きい窓の連続指定を追加 |
| WMが要求を無視すると永久保留 | state_askedに1000ms期限と実状態の再照会。所有窓のoverride-redirectによる拒否と、WM管理へ戻した後の復旧を確認 |
| 普通の全画面解除で強制的に元の場所へ戻す | normal_placedで明示的な配置とWMの通常復帰を区別。後者へ移動・resizeを送らない。配置後の全画面再入場ではnormal_placedも消す |
| XWaylandの座標丸め | 1倍＋2倍で1 Xピクセルの丸めを実測し、復元完了の確認は±1を許容。通常倍率の外部検証は完全一致、混在倍率は明示した2ピクセル刻みで確認 |
| watchdogと親の時間・終了処理 | 親全体75秒・watchdog150秒、SIGTERM/SIGHUPの後始末、子の専用セッション、設定維持とwatchdog生存の合格前確認、復元後のstatus設定 |
| 元設定の保持・復元 | 元と候補の両方をverify。色モード・RGBレンジ・underscanningを保持。未知のモニター属性があれば適用前に止める。watchdogの復元を再試行し、45秒の回収期限を超えた場合もreport.jsonを残す |
| テストの根拠と記録 | 全画面前後で最後の画面を変え、WMから矩形・枠・状態を独立取得。Tk closeの広域steps依存を除き、framesへ--outputを追加。最終実行体でJSONを直接出力し、コマンドとリンク先を一致させる |

[初回原文](1037-linux-window-on-claude-review.md)、[再レビュー原文](1037-linux-window-on-claude-followup.md)、[最終レビュー原文](1037-linux-window-on-claude-final.md)。最終レビューは「前回中のA・B・Cは解消、新たな中以上なし」。残るR1〜R5は低〜中または低という判定だった。

最終レビューの後にも低指摘を反映した。再入場後・期限切れ後のnormal_placedを消し、同じtickの新しいFULLSCREEN要求を期限切れ処理で上書きしない。復元・入場中のSHOWで新しいウィンドウサイズを送らず、復帰条件を壊さない。検証にそのSHOWとの組合せを追加した。

拒否テストも、全画面要求が保留中にWINDOW-ONを受ける経路へ強化した。その実行で、place_firstが保留中にも内部の再要求フラグを立て続け、期限切れ処理を遅らせるケースを発見した。place_firstはstate_askedとrestore_pendingが空の場合だけとし、再検証が成功した。この最後の条件と、作業領域の反映待ちは、Claudeの最終スナップショットより後の変更である。

混在倍率ではRandRの矩形が先に変わり、_NET_WORKAREAの更新が遅れる実測も得た。矩形だけの反映待ちでは作業領域が旧構成のままのプローブを採取できたため、両方が期待値になるまで待つようにした。Mutterの色モード・RGBレンジ・実験的機能も記録する。設定適用後に親へSIGTERMを送り、元の設定への復元とwatchdog終了を確認した。これらは[混在倍率検証](../LINUX_MIXED_SCALE_VALIDATION.md)へ記録する。

最終の実行結果・ソース指紋は[WINDOW-ON検証](../LINUX_WINDOW_ON_VALIDATION.md)、[混在倍率検証](../LINUX_MIXED_SCALE_VALIDATION.md)、[Tk検証](../LINUX_TK_DISPLAY_VALIDATION.md)を参照。レビューを実機確認の代用にはしていない。

固定1秒後に各段階を照合する検証のため、遅いWMの一般的な受け入れ試験にはしない。現在のGNOME/XWaylandでの確認である。WMの外部ショートカットによる全画面窓の移動・最大化状態・物理切断は残る範囲として扱う。

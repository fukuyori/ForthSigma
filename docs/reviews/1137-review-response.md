# 1137 Paula：レビュー評価と採否

2026-11-20。[設計原文](1137-design-claude-review.md)を保持し、評価・採否を分ける。ClaudeはRead/Glob/Grepだけを許可し、コマンド・試験・ネットワーク・Git操作を依頼していない。[モデルの契約](../PAULA_FORTH.md)と実行結果はロクが別に検証する。Mac1147が終わるまで親1137を完了にしない。

## 設計レビュー

| 指摘 | 判断と反映 |
| --- | --- |
| H1 PAL最小123と既存124の違い | 一律124の提案は不採用。ClaudeはHRM未読と記憶による推測と明記している。ロクがHRM第5章のPAL123/NTSC124を確認し、付録Aの124と既存MML124との差も記録。既存MMLを変更しない |
| H2 IRQの回数 | 採用。DMA有効化後の初回とlast-word fetch。各blockのfirstで重ねない。LEN1の初回/末尾はpending1bitに合流する独自規則と明記 |
| H3 同tickのwriteと遷移 | 採用。期限tick以下の遷移→同時刻queue→即write。enableを時刻tで書くとfetchはt+1 |
| H4 実効DMA enable | 採用。DMAEN AND AUDxENの立上り/立下りで起動/停止。masterだけの切替も扱い、pendingは消さない |
| H5 stereo wrapper | 採用。別の2048byte buffer、4byte/frame offset、2ch OPEN。monoのPS-SENDを流用しない。PSのcleanup/error優先/close失敗時ID保持は共用 |
| M1/M2 512KiBと折返し | 採用。OCS想定の宣言とし、LCH&7/LCL&FFFE。pointerは19bitで折り返す。メモリ全byteを保持・比較 |
| M3 PER0拒否案 | 不採用。LEN0/PER0=65536はモデルの宣言値として統一し、実機保証とはしない。外部PER1..122は-21、attachなら123へ丸めて回数を記録。一般のsilicon互換を主張しない |
| M4 manual latch | 1word保持案を採用。途中のDATで現在wordを切らず、pendingの最後のwordを使う。IRQをword開始へ変更する案は不採用。HRM第5章のdirect出力のword完了の説明を参照し、pipeline/ack分岐は省略したモデルとする |
| M5 attach境界 | 採用。block先頭はvolume、CPU/attachは後の書込みが有効、解除後もeffective値保持、attach元はmuteでもDMA/IRQ継続。same-tickの期限は先にsnapshot、voice0→3順 |
| M6 write errors | 範囲外・奇数・readonlyへのwriteはAPIの-24へ統一し、許可mask外は-21。bit15のみは変更なしとして受理。値は16bit |
| M7 RESET | 採用。queue/regs/state/pending/mask/端数/統計/slowを初期化し、samplememoryだけ保持 |

## 独立性と完了条件

Forthの基準/まとめ処理はヘルパーを共有する。Pythonは1tickごとの別実装で、手計算したhigh/low・manual latch・IRQ・wrap・buffer保持・period遅延・変調時の丸めも補う。両者共通の仕様の読み違いは残るため、実機検証と扱わない。固定PCMのSHAと全512KiBのmemory照合を保持する。

1145（実装）と1146（Windows/Linux・測定）を1147（Mac）から分け、すべて1137配下へ登録。実装部分を完了しても親は未完了のまま残す。PCM実聴のWindows1148/Linux1149はPCM998→1133配下で別に管理する。

## 実装レビュー

[実装原文](1137-implementation-claude-review.md)はHigh/Mediumなし。読取りだけのレビューで、実行結果とは区別する。

Low1は追加fixtureで対応し、非ゼロのstereoデータを5frame受理→0→残り507受理として、再開offset20byteと全2048byteコピーを検証する。2byte/frameへ戻すと検出する。timeout/close再試行・本体とcleanupエラー優先・ID保持・open/drain失敗も含む。Low2はboth attachのword列64/123/32/124とblock再開の5境界を手計算で補う。Low3はread範囲/奇数の-24、VOL bit6の優先を明記した。基準/まとめ版のヘルパー共有や仕様の共通読み違いの限界は引き続き残る。

## 追加レビュー

[追加原文](1137-followup-claude-review.md)でMedium1件。LEN4は偶数なので、reload時の交互位相resetが無くても次blockがvolumeになり、resetの独立した検証にならない点を採用した。元の交互列検査は残し、LEN3の奇数blockを追加。tick493でvolume32/period123/位相0、739でvolume64/period123/位相1、985でvolume64/period123/位相0、PER丸め0を手計算値として検査する。reloadのresetを除くと739で64がperiodに入り、丸め回数と値が異なる。

[最終原文](1137-final-claude-review.md)はHigh/Mediumなし。奇数LEN3では493の位相、739のvolume、丸め回数の3点でreset漏れを検出できる。さらにリポジトリ本体は変更せず、専用tempコピーでreloadのresetをDROPへ置き換えてstack効果を維持した負の対照を実行した。process正常終了/stack0のまま期待値と不一致となり、数値の差として検出した。レビューの手計算評価と、ロクの実行結果を分ける。

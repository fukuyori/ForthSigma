# 1138 YM2149/ST：レビュー評価と採否

2026-11-20。[設計原文](1138-design-claude-review.md)と[実装原文](1138-implementation-claude-review.md)を保持し、原文・評価・採否を分ける。ClaudeはRead/Glob/Grepのみでコマンド・試験・ネットワーク・Git操作を実行していない。メーカーPDFの図表とAtariの原資料はロクが照合し、[現行契約](../YM2149_FORTH.md)へ出典と宣言を分けて記録する。

## 設計採否

| 指摘 | 評価と対応 |
| --- | --- |
| native固定0のindex1 | 修正を採用。MMLの休符・停止が音量0を使う内部契約と、AY経路とを揃える。メーカー図だけから実機の精密な0電圧を断定しない。修正前probe0.0056234132→修正後0、envelope1を維持する回帰を実行 |
| High：3声の合成式 | 採用。floor((A+B+C)/3)で0..32767。表は独自の理想1.5dB整数化で実測DACではない |
| tick/標本の順序 | 採用。master8kにstep、期限step→queue→即時write/read。標本は現在clockから端数を持ち越して相対的に進める。RESETからレンダーだけならfloor(n*clock/rate) |
| raw読戻しとI/O例外 | 採用。R0..13はraw8bit、R14/15はinput pins/output latch AND pins。未使用bit/electrical挙動は宣言値 |
| fast境界 | 採用。count>=newperiodなら次step、noise奇数step位相、保持中env除外を含める。queue/標本のmasterclock境界を越えない |
| bus選択の簡素化 | 採用。raw8bit一つでselect0..15/非選択を決め、不要なlastvalid状態を持たない。dataはevent適用時のselectへ書く |
| PORT/PIN query | PORTはCPU latchと駆動mask、PINはモデルのpin値を返すよう分離。未適用queueをqueryで勝手に消費しない |
| 未確認だった資料 | YM2149 PDFのtap/seed・period0・未使用bit等はnative由来/モデル宣言として記録。2MHzはAtari Corporation §4.1、メーカーp7/8のclock/32levels/portsを原典確認。FF8800/02は原著register listingの値を照合し、鏡像/waitを含む実機保証としない |

独立Forthの不足補完と、既存native SOUNDの互換維持を分けた。SOUNDは0..13の非同期writeのままで、I/O実周辺機器を操作するnative語を足していない。Forthは点標本、nativeはstep平均なので、両者のPCM一致を採否条件にしない。Pythonの1masterclock実装とForth両経路/手計算/固定PCMを照合し、共通仕様誤りと実機未検証を残す。

## 実装指摘

実装レビューはHighなし、Medium1件。M1を採用し、標本時刻の文書を現行の相対レンダー契約へ合わせた。即時writeで1000clockまで進めた後の1frameは1041clock、さらにTO2000後の次frameは2042clock、次は2084clockになる手計算を補助fixtureへ追加した。連続音声はEVENT!とRENDERで進め、直接TO/readの隙間はPCMを作らない。

Low1は純粋queryが適用済み状態だけを見ると明記し、INPUT-EVENTの同tick未適用255→RUN0後0を検査。Low2は停止直後のfilter tailが非0であることをnative回帰へ追加し、filterをresetする退行も検出する。Low3はRESETでreg13=0でも内部envelope31/holdingという宣言を明確化し、native Psg型の直接resetとEngine初期化を区別した。Low4は計時7回すべての最後に37項目のsemantic stateもPythonと照合・記録し、warmup後のRESET漏れを検出する。Low5はBUS経由の両port input/output readを追加し、未使用localを削除した。

native全体試験はWindows/Linuxで実施し、計測はその終了後に行う。Mac1154は1138の子に残し、親1138を完了にしない。[最終原文](1138-final-claude-review.md)はHigh/Mediumなし。M1は相対レンダーの契約と追加検査で解決済み。最終Lowは補助スクリプト単独時のdirectory作成、時刻とbyte一致の説明、計時終了state照合の記載であり、いずれも反映した。レビューは読取りだけで、実行結果はロクが別に確認する。

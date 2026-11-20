# 1169 ZX Spectrumレビューへの対応

設計・実装・最終の原文を別ファイルで保持する。Claudeは読み取りのみであり、テスト実行/実機検証をしたレビューではない。

## 設計

H1はCPU tickで有理比を保持、H2はRESET後16k境界、H3は未対応portの-21と対応port上の無効selectのFFを区別して反映した。M1は単一の全API優先順には揃えず、各APIの検査順を明記し複数不正の検査を追加した。M2は1queue entryでULA→AYを処理、M3は登録済み予定を即時操作前にflushし、即時操作後の同tick予定は次flushで適用する。M4は128bitの正確なframe上限、M5は不正bufferの-9後に時刻が進む宣言と実検査を採用した。

## 実装

Highなし、Medium4件。レビュー開始時点のスナップショットと途中で追加した検査には時間差がある。

- M1: MAX直前の失敗-24・41項目の前後状態・buffer両端保持に加え、1frameの上限内成功とclock/fractionを検査した。
- M2: APIごとのerror優先順位を仕様に追記。過去tick/未対応R15/48K、満杯と逆順が重なるケースを追加した。
- M3: select15..255のdata無視とreadFFを全件確認。48KのIN/INPUTの-21と原子性を追加した。
- M4: tone/noiseのperiod0、noise/tone/envelope短縮、envelope EP0、R12高位byte、R13と共有divider境界を直接検査した。
- L1: 別のstream検査で11RAM callbackケースを音声有効6構成に実行。L2/L3: RESET時SLOW=FALSE、R13未書込み時のlevel15保持を仕様に明記した。

原典について、ロクが128K PDF20/21頁とGI PDF1/2/4/5頁を確認した。Claudeが原典を確認したものとは扱わない。アナログ音量、仮想portA、R15、未対応readはモデル宣言として残し、全機種/実基板の互換性を主張しない。

## 最終評価

最終レビューはHigh/Mediumなし。原文は[最終レビュー](1169-final-claude-review.md)。stream上限ちょうど成功の追加検査などのLowは未実施として残す。8構成の独立検査と音声有効6構成のRAM送出検査はロクが実行し成功した。実聴/速度は未実施で、1170/1171/1172に残す。

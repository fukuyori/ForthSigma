# 1067 保存アプリ起動：レビュー評価と採否

2026-11-20。[全体レビュー原文](1067-design-claude-review.md)、[比較レビュー原文](1067-metadata-claude-review.md)、[原案](1067-design-proposal.md)、[採用設計](../SAVED_APPLICATION_STARTUP_DESIGN.md)。Claudeは読み取り専用で、実行確認はロクが担当。

| 指摘 | 評価・採否 |
| --- | --- |
| H1 復元前のdebug/cleanup | 採用。plain_calls等は復元前、既存deferも復元前。formatではlog/lint/profileを生成しない |
| H2 formatと検査順 | 採用。Absentだけ従来早期処理。PresentはStateを初期化して完全復元を検査した後に整形し、APPや-eを実行しない |
| H3 旧footer/新ABI | A案自体を比較レビューのB案へ置換したため、SIGEND02とbitは不採用。SIGEND01を維持し、検証済み画像のrootだけから判定。旧ABIを許可するわけではない。SAVESYS切り離し時の長さ一致検査は採用 |
| M4 QUIT | 採用。既存-eと同じ表示なし/status1/finishBlocksなし。deferは共通経路 |
| M5 正常復帰のstack検査 | 採用。新しいdata/float/return深さの契約エラーを足さず、finishBlocksへ合わせる |
| M6 root範囲と再検査 | 採用。encoded rootの非zero範囲はbuiltin_count+1..word_count。query/保存/restore/起動前で属性変化も検査 |
| M7 削除hook | 採用。dropWordsFromへ一元化。HERE変更だけでwordが消えるという記述を修正。MARKERへ設定snapshotは追加しない |
| M8 registry | overlap拒否とsetter/clearの旧slot記録除去を採用。ただしregistry.writtenは削除関数ではないため、それだけで古いrecordを捨てられるとの説明は修正し、明示的にslot記録を除く |
| M9 Ctrl+C | 採用。既存待機/明示EXEC-LIMITEDによる協調的中断と、checkpointのない計算中のOS終了を区別。通常VMへ暗黙pollは足さない |
| M10 debug除外 | 採用。format/lintもdebug依存であることを明記し、strict prefixで不明optionとして拒否 |
| M11 引数 | 採用。現在のargv0、argv0込み256件、文字列領域と空文字の保持。host prefix除去後の新しいvectorを構築 |
| M12 診断先 | 採用。既存stdout/reportDiagnosticに合わせ、readerから直接UIを出さない |
| L13 files/image除外 | files=falseの引数利用は維持。image=falseで非zero APP rootを許すという比較レビュー案は不採用。APIだけ除外して隠れた自動起動を許すことはせず、root!=0をInvalidImageとする |
| L14 Mac child予約 | 採用。既存の私有child判定は最優先で、単一の予約引数はAPP引数として使えない制限を記録 |
| L15 SAVESYS失敗途中の出力 | 「範囲外」とする案は不採用。生成物の不完全さが通常版へのfallbackを起こすため起動契約と関係する。同directoryの排他的temp→完全write/flush/close/権限→atomic replaceを1068の範囲に含める。故障時は既存出力先保持とtemp回収を検証 |

## メタデータ比較レビューの補正

B案を採用し、画像情報の二重保持と新footer移行をなくす。A案が必ず不正実行するとは断定しないが、B案の方が整合性条件が少ない。比較レビューの「末尾8byteがmagic」は正確ではない。SIGEND01は末尾20byteの先頭8byte（end-20..end-12）にあるので採用設計で補正した。

feature検査はStateなしでも既存image_featuresを使えるのでinspectにも実施する。builtin table一致・容量はStateのprepareで確認し、Presentのformatもその完全な検査の後だけ行う。Workspaceはheap上、Viewを外へ返さず値だけコピーして解放。二度parseする費用は1069で測る。

## 確認済みと未実施

Windows/Linuxの現行SAVESYS（入口なし）、空/空白/日本語引数、saved layout拒否、SIGEND01とCRC/system領域を独立probeで確認した。[照合・試験表](../SAVED_APPLICATION_STARTUP_ACCEPTANCE.md)。これは新APIや新起動動作の合格ではない。

1067は仕様・レビュー・採否の完了。1068の実装、1069の生成実行体受け入れは別に記録する。測定文書の既存未コミット差分を保持し、コミット・タグ・pushは行っていない。

## 限定再レビュー（実装着手時）

[原文](1067-followup-claude-review.md)の高1/中4/低1へ対応。SAVESYSの最終置換前にfile IDで自己上書きを再検査し、相対path/hardlinkも拒否する。最終symlink/Windows reparse pointは拒否する方針に確定。実行体の読取り権限と出力先directoryの書込み権限を要件とし、root=0のsaved formatterはno-app不要という区別を明記した。

APPは空のterminal sourceを用意するState.runEntryから呼ぶ。SOURCE/>IN/BLK/SOURCE-ID/PARSE-NAMEは空行相当で、元のsource contextへ戻す。format以外のlog/lint/profileは既存どおり復元前に準備して復元失敗を診断し、formatでは作らない。registry slot除去は専用のcompact処理とし、セルを指す他のaddress rootを無効化しない。

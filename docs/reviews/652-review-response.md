# 652 設計レビューの評価・採否

2026-11-20。[設計原文](652-design-claude-review.md)。read-only、実行試験はロクが行う。

| 指摘 | 評価・対応 |
| --- | --- |
| H1 デコード済み保持案 | 採用。main.deferred_packetsへ新しい背景入力を積む案を取り下げ、POSIXはhost_input.queued、Windowsは未デコードINPUT_RECORD ringへ保持する。enterやstandard mode切替をpollから呼ばない |
| H2 中断印の再発 | 採用。takeInterruptを追加し、Forthへ渡すときに1回消費。新EXECのpollとborrowした待機にも適用 |
| H3 NS/audioとの競合 | 採用。外側EXECがinterrupt-only scopeを持ち、内側待機はnative handlerを新設しない。EXEC外の既存拒否規則は維持 |
| H4 -280 THROWとowner | 採用。内部reasonをnone/CLI/入口indexへ分け、明示THROW -280・reset/reportでは理由を整理する。自分の入口だけior化し直後に理由を消す |
| M1 byte位置の算式 | 指摘された非byte・reset・partial input・元bufferの3について、既存parserを用いた独立試験でbyte数の算式が成立することを確認した（execution_replay_test）。算式自体が常に誤るとの評価には同意しない。ただし実装は層/indexのタグを持つsourceを優先し、host側の記録を正確に除く |
| M2 EINTR | 採用。EXECが最初のsignal所有者のときはSA_RESTARTを使う。すべてのOS呼出しを中断可能とは扱わない |
| M3 解釈loop | 採用。有効EXEC内のtoken dispatchを追加単位としてchargeする。CLIの従来計上範囲とは分ける |
| M4 順序・優先度 | begin前の検査、xt/uのpop前のhost begin、予算pop後のhost endを採用。endの復元失敗を最優先とし、その後はcallee例外、pending割込み、正常/入口iorの順。CATCH復元を共通化する |
| M5 O(depth) | 初期実装は最大16段の明示的な検査/消費を維持し実測する。飽和絶対期限ではu64全域と長時間u=0実行の境界が曖昧になるため、測定前に単調counter方式へ置換しない。通常loop(false)へ処理を足さない |
| M6 cookedへの移行 | raw入力保持と既存mode変更の境界を試験する。背景で読んだ文字は保持し、KEY/FILE/GRAPHICSの順序・Backspace・UTF-8を確認 |
| M7 cooked Ctrl+C | EXEC内ではguardを持ち-28として返す。独立console/PTYで確認する |
| 画像・native | budgetは保存/append対象外。LOAD後も制限が有効なこと、既存native hookのエラー後始末を確認する |

入口iorの-280は、既存THROWへ渡すとStepLimitとして通常CATCHを通り抜ける。仕様として明記し、入口で処理する用途では数値を比較して扱う。CLIや明示THROWの従来挙動を変更しない。

## 実装レビューの採否

[実装レビュー原文](652-implementation-claude-review.md)を保存した。

| 指摘 | 評価・対応 |
| --- | --- |
| H1 未完成ESC/UTF-8直後の3 | 採用。sourceが3を返した直後の中断では、その3はdecoderに入らない。従来式で残buffer長を引くのは誤り。last_threeでsource直後とbuffer先頭の中断を区別し、元のsourceタグから3だけを除く。先の独立試験はこの経路を含まず、一般的な成立の証明には不足していた。ESC+3、ESC[+3、aESC+3z、部分UTF-8+3を追加し、Windows/PTYでもESC保持を確認する |
| M2 入れ子endの印消費 | 入れ子での消費を除く部分を採用。inner endは印を保持し、outer input ownerのendか次pollで消費する。外側予算切れと同時ならouter endの-28が入口iorに優先する。通常THROWより-28を優先する提案は不採用。採用済み設計は復元失敗→callee例外（CLI/Quit含む）→pending割込み→正常/自分のiorであり、通常THROWと同時の中断はcallee例外を報告する。fake endでこの順を固定する |
| L3 大きいreplay領域 | 採用。入力UTF-8保留は実際に4096byteあるため400要素への縮小はできない。5120要素の領域をprocess-owned static workspaceに置き、使用した項目だけ上書きする。decoderはcopy、clock callbackはVMへ再入しない。modern処理中のprobeはskipする |

除外検証ではdebugなしのEXTENSIONがEXEC-LIMITEDを登録する問題も見つかり、full definitions（HELP/参照用）とenabled_definitions（group登録用）を分けた。debugなしでHELP・画像復元も再試験する。

[限定再レビュー](652-followup-claude-review.md)では修正範囲に高・中の具体的欠陥なし。低指摘を受け、EXEC-LIMITED末尾前提にcomptime assertを追加し、実際のhost_wait endInputとコアを組み合わせて、外側の予算切れ＋inner endでの保留割込みがouter endで-28となる試験を追加した。内側自身の予算切れ時は印を保持し、外側の次poll/endまで通知が遅れる点も仕様に記録する。

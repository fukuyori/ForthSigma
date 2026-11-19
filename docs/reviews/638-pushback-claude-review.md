# 638 押し戻しと入れ子の再レビュー原文

2026-11-19、読み取り専用。レビュー時点の指摘であり、現状の未解決一覧ではない。実行結果と採否は638-review-response.mdおよび実装記録を参照。

## 依頼

```text
Narrow post-fix review, read-only. Review only current core/event_input.zig beforeBytes/beforeStdinBytes/beforeFileRead, core/input_redirect.zig run/capturePending/applyPending and line fallback, host_interface unread_byte_fn contract, main terminalUnreadChecked/terminalUnread, and corresponding last3tests in event_queue_test.zig. Last followup four findings fixed: new checked pushback is atomic refusal (error=>byte notaccepted); void legacy callback impliesaccept, core removesbeforecheckinglatched-error. Global stdin legacy pending cache moves key/bytes/event across nested file bindings, tests preserveX Y Z WINCH A. line fallback entry includespending_key/eventbytes; nonLF afterCR isreadnextACCEPT. nextStandardPacket and nextByte bothoutercap32calls, each Win.next filters32native records. Also explicitSTDIN KEY-FILE/READ-FILE/READ-LINE/slurp/include forward decoder bytes via beforeFileRead even while another file selected; query-file returnsready/!eof ifdecoder bytesqueued. Old hosts withoutstandard_event_fn unaffected; new typed hosts mixing legacybyte-cache withSTDIN filecallbacks need atomic pushback or get-21beforeloss. ReaderState image reset clearsoldpending too. Check concrete acceptance/order/dataloss defects only in those changes, no file edits/commands. Native tests passing before latestSTDIN bridge, nowrerunning. Japanese concise.
```

## 原文

レモン、指定の範囲を読みました。ファイルの編集とコマンドの実行はしていません。テストは今回走らせていないので、結果は未確認です。

## 指摘

### 1. 【中】EKEY? の peek 後に KEY を読むと順序が入れ替わる
- **原因**: `sourceRead`（`src/core/event_input.zig:136`）は、`pending_key` と `pending_event_bytes` を1バイトずつデコーダへ移します。このため、デコーダにあるバイトは、残っている pending より先に読まれるべきものです。
- **`beforeBytes`/`beforeStdinBytes` の問題**（`event_input.zig:165`）: デコーダのバイトだけをホストへ押し戻し、pending はコアに残します。その後 `nextKey`（`words_xchar.zig:122`）は pending を先に返します。
- **再現例**: 3本目のテストと同じ状態（`pending_key='X'`、pending バイト Y Z）で `EKEY? DROP KEY KEY KEY` を実行します。
  - EKEY? の peek で X がデコーダに残ります。
  - その後の KEY は Y Z X の順になります。期待値は X Y Z です。
- **影響する範囲**: `unread_byte_fn` のあるホストでも、押し戻し手段のないホストでも起きます。
- **`beforeFileRead` との違い**: `beforeFileRead`（`event_input.zig:189`）は、pending を先に押し戻してからデコーダを押し戻します。このため順序は正しく、`beforeBytes` だけが逆になっています。
- **main で起きるか**: ※推測です。main の typed host では pending に入るのは line fallback の `pending_key` の1バイトだけで、`sourceRead` が先にそれを取り出します。このため main では起きないと考えます。
- **修正の方向**:
  - 押し戻し手段のあるホスト: `beforeBytes` でも pending をデコーダより先に押し戻します。
  - 押し戻し手段のないホスト: line fallback の CR 後（`input_redirect.zig:91`）と xkey（`words_xchar.zig:163`）が、デコーダから取ったバイトを `pending_key` に置きます。ここでは順序が逆向きの依存になります。修正の前に、「デコーダが常に pending より先」という不変条件にそろえるかどうかを決める必要があります。

### 2. 【低】押し戻しが失敗したとき、またはできないときに paste 状態が消える
- `beforeStdinBytes` は、最初に `paste = false` にします（`event_input.zig:166`）。
- `unread_byte_fn` が拒否した場合や、押し戻し手段がない場合でも、デコーダにはバイトが残ります。しかし paste 状態は消えます。
- その結果、貼り付け中の ESC などが通常のキー列として解釈される可能性があります。`\x1b[201~` は paste 状態がなくても `paste_end` に解釈されます（`standard_event.zig:102`）。

## 問題がないと確認した点
- **`terminalUnreadChecked`**: 溢れたときは、状態を変える前にエラーを返します。拒否は原子的です。容量は lookahead 1 + 64 = 65 です。
- **`beforeStdinBytes`**:
  - checked の経路: 失敗したバイトの length は減らしません。
  - void の経路: 受理したものとして length を減らしてから、エラーを確認します。どちらも重複も消失もありません。
- **`beforeFileRead`**:
  - 押し戻す順序は、旧バイト列 `bytes[0]`（最後に読まれる）から始めて、`key`、デコーダの順です。読む順序は正しくなります。
  - 途中で失敗しても、`count` を減らすのは成功後だけで、`defer` で legacy を書き戻します。データは失われません。
  - 最大で 32+1+32 = 65 バイトになり、すでに lookahead がある場合は `HostFailed` になります。これは仕様どおりの拒否で、データの消失はありません。
- **`input_redirect.run`**: stdin → file → stdin の入れ子、file → file の切り替え、エラー時の `defer` で、退避と復元の対応が取れています。
- **line fallback**: CR の後の LF でないバイトは `pending_key` に残ります。`pending_key` は取り出し済みで空なので、上書きによる消失はありません。

## テストについて
- 3本とも、主張している挙動の検証として妥当です。
- 指摘1の EKEY? peek → KEY の組み合わせと、`beforeFileRead` の経路（STDIN READ-FILE / READ-LINE）は、この3本では検証していません。

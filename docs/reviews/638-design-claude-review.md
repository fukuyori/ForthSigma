# 638 Claude Code設計レビュー原文

2026-11-19、読み取り専用。採否・実行結果とは区別する。

## 依頼

```text
Read-only design review for task638. Read docs/EVENT_QUEUE_DESIGN.md, docs/ASYNC_CORE_PLAN.md section2, ASYNC_COMMON_RULES sections2-4, src/core/event_input.zig, standard_keys.zig, input_redirect.zig, words_xchar.zig, graphics_input.zig readInput, host_interface.zig, src/host_input.zig nextStandard, src/main.zig terminalEventKey, relevant src/tests/xchar_test.zig and p06c_test.zig. Need concrete decisions on proposed API fixed event flag ior, bounded partial buffer and lookahead, whole deadline, mouse metadata, paste, KEY/INKEY switching, legacy callbacks and images. Identify flaws and recommend exact resolution instead of asking user spec questions. Do not modify files or execute commands. Return concise Japanese ranked issues and recommended accepted design. User authorized development while asking you to review.
```

## 原文

レビューを書き上げています。キュー・Ctrl+C・切替の各点について、どう直すかの具体案まで含めてまとめます。

# task638 設計レビュー（読取りのみ。ファイルの変更とコマンドの実行はしていません）

最初に結論です。現状の案では、そのままだと壊れるか実装が決まらない点が5つあります（1〜5）。各項目に直し方を付けたので、その形で採用してよいと考えます。

## 問題点（重大な順）

**1. ホストが値3を先に例外へ変えるので、貼り付け中の値3を文字にできない**
- 現状、ホストは値3を受けた時点で `UserInterrupt` にしています（`src/main.zig:1973`、`1963`、`2008`）。このためコアには届かず、案の「paste中は値3を割込みにしない」が実現できません。
- **直し方:** 新しいホスト口は、値3をただのbyteとしてコアへ渡します。値3が貼り付けの外なら、コアはその3を消費して -28 をTHROWします。それより前に読んだ途中のバイトは保留に残します（今のテスト `xchar_test.zig:221` と同じ考え方です）。貼り付けの内側なら、文字3として返します。

**2. 保留したバイトがACCEPT・KEY?・INKEYから見えない**
- 今のEKEYは、読み残しを `unread_fn` でホストの `lookahead` へ戻しています（`main.zig:1994`）。この仕組みでACCEPTやREFILLとの順序を守っています。案のように保留をコアだけに持たせると、`read_fn`（ACCEPTなど）がその保留を読みません。
- INKEYは `host_input.next()` が持つ `queued` だけを読み、`main.zig` の `lookahead` を読みません。経路ごとに保管場所が違います。
- **直し方:** EKEY系以外の読取り（KEY、XKEY、KEY?、KEY-IOR、ACCEPT、標準入力のREFILL、INKEY、MOUSE-EVENT、KEY-HELD?）の入口で、コアの生バイトを吐き出す処理を1つ呼びます。
  - 端末系の語では、`unread_fn` で逆順にホストへ戻します。
  - GRAPHICS系の語では、`gfx_input.pending` へ順に入れます。
  - ホストの `unread_bytes` は、今は assert で31バイトを前提にしています。32バイトのバッファと既存の先読み1バイトを足すと33バイトなので、容量を64バイトにし、assert をやめて -265 にします。

**3. 期限が過ぎた後に届いた完成イベントを「保留してtimeout」とするのは不合理**
- ホストがデータを返した時点で、そのデータはもう手元にあります。それを今回は timeout と報告すると、ポーリングするたびに1回分遅れます。共通の取り決めで未決だった「複数の結果が重なったときの優先の順」も、この点と一緒に決める必要があります。
- **直し方（優先の順）:**
  1. 保留中の完成イベント（期限が0でも返す）
  2. 今回読んだバイトで完成したイベント（時計が期限を過ぎていても返す）
  3. 中断（-28）
  4. 対象のior（途中のバイトは保留に残し `0 false ior`）
  5. 期限（`0 false 0`）

  期限の判定は、ホストを次に呼ぶ前だけに行います。ホストへ渡す待ち時間は、残り時間をミリ秒に切り上げた値にします。

**4. 貼り付けの途中でGRAPHICSへ切り替えたら -21、は不適切**
- これだと、利用者が貼り付けをしただけで、別のAPI（INKEY）が例外を出してアプリが落ちます。
- **直し方:** -21 は出しません。問題点2の吐き出しで生バイトをGRAPHICS側へ渡し、貼り付けの状態は解除します。INKEYが貼り付けの印をどう扱うかは、GRAPHICSの既存の解釈に任せます。

**5. EKEY? の先読みとKEYの互換を両立するデータの持ち方が決まっていない**
- **直し方:** byteから作るイベントは、デコードした結果を保存しません。その都度、生バイト、ESCの開始時刻、貼り付けの状態、マウスのボタン状態から作り直します。状態の確定（貼り付けの開始・終了、マウス情報の更新）は、EKEYかEKEY-WAITがイベントを消費したときだけ行います。
  - EKEY? は「今のバイトで完成するか」だけを調べ、状態を変えません。
  - KEYは生バイトの先頭から取るので、互換が自然に守られます。
  - ESCの開始時刻はStateに持ちます。こうすると、ポーリングを繰り返しても、最初のESCから50ms後に単独のESCを返せます。

**6. マウスの意味が足りない**
- SGRの `b` は「変化したボタン」を表し、押している状態そのものではありません。一方、Windowsの `dwButtonState` は押している状態です。
- **直し方:**
  - `buttons` は、イベントの後に押しているボタンの集まりとします。SGRでは、デコーダの中で押している状態を追います（GRAPHICSの `terminal_buttons` とは別に持ちます）。
  - 修飾キーは、イベント値に `K-MOUSE OR K-SHIFT-MASK…` の形で載せます（`isFunction` が修飾キーの部分を除いて判定するので、EKEY>FKEYはそのまま動きます）。
  - 横ホイール（SGRの66/67）は、消費して捨てます。
  - 637はマウスを1003（すべての移動を報告）で有効にしているので（`host_input.zig:105`）、移動もK-MOUSEとして出します。Windowsの `MOUSE_MOVED` も同じ扱いです。
  - 旧来のX10形式（`ESC[M`）はデコードしません。旧来の MOUSE-ON が1006を必ず送るかどうかは未確認です。

**7. 既存EKEYで対象のiorをTHROWする値を明記する**
- 共通の取り決め3節で「既存の語の戻り方は変えない」と決まっています。
- **直し方:** EKEYとEKEY?は、今までどおり -265 をTHROWします。iorを返すのは EKEY-WAIT だけです。

**8. INFILE-EXECUTEで選んだファイルの経路**
- `input_redirect.byte` は、iorを自分でTHROWします（`input_redirect.zig:44`）。
- **直し方:** EKEY-WAIT用に、iorをTHROWせずに返す版を作ります。
  - ESCの列、マウス、貼り付けは、ファイルからはデコードしません（今の `selected == null` の条件を引き継ぎます）。
  - 期限が0以上のときは `ready` で判定し、読めなければtimeoutにします。

**9. 貼り付けを打ち切る条件が足りない**
- **直し方:** END、EOFに加えて、次の場合も貼り付けを解除します。
  - Raw modeに入り直したとき（`restarted`）
  - TERM-MODE! で貼り付けの報告を止めたとき
  - 問題点4の切替のとき
  - INFILE-EXECUTEで入力源が変わったとき

  貼り付けの外で来た `201~` も K-PASTE-END として返します（害はありません）。何も来ない時間で打ち切る方法は採りません。

**10. 細かい点**
- EOFが来たら、ESCの列は50msを待たずにすぐ確定します。
- 時計が失敗したら -265 にします。新しい経路では、今の `monotonicMilliseconds` のように0を返す時計は使いません。
- 名前の表に3つ足すと、`key_name_base` の範囲を確認するコンパイル時のチェック（`memory_map.zig:171`）と、`p06c_test` のイメージの往復テストに影響します。実際に収まるか、テストが通るかは未確認です。
- 900の `Deadline` APIの具体的な形と、637の文書は読んでいないので未確認です。

## 採用を勧める設計

- **ホスト口:**
  - 新しく `standard_input_fn(ctx, timeout_ms: i32) RuntimeError!StandardInput` を作ります。
  - 戻り値は `union{ byte:u8, key:Cell, mouse:{column,row,buttons,wheel,mods}, timeout, eof, ior:Cell }` です。
  - THROWするのは -265（失敗）だけにします。値3はbyteとして返します。
  - 既存の `event_key_fn` などは、古い埋込み用にそのまま残します。新しい口があれば、そちらを優先します。新しい口がないとき、EKEY-WAITは -21 です（`event_key_fn` はtimeoutとEOFをどちらもnullで返すので、区別できません）。
- **Stateに持つもの:** 生バイト32個、ネイティブのイベント1個、ESCの開始時刻、貼り付けの状態、SGRで押しているボタン、最後のマウス情報。これをまとめて1つの構造体にし、今の `pending_event_bytes` と `pending_standard_event` もこの中へ移します（`pending_key` は今のまま別に持ちます）。
  - INFILE-EXECUTEでは、この構造体を値として退避し、元に戻します。
  - State.init、イメージの復元、ワーカーStateの作成のときに初期化します。SAVEには含めません。
- **EKEY-WAIT ( ms -- event flag ior ):** 案のとおり固定の3セルです。
  - 入口で、深さが1以上あること、引数を取った後に2セルの空きがあることを確かめてから、入力を消費します。
  - EOFは `K-EOF true 0` です。
  - 優先の順は問題点3のとおりです。
- **EKEY-MOUSE、定数3つ、EKEY>FKEY、名前の表示:** 案のとおりです。マウスの意味は問題点6のとおりにします。
- **貼り付け:** 案のとおりです。ただし、値3と打切りの条件は問題点1と問題点9に、GRAPHICSとの切替は問題点4に従います。
- **ほかの読取りとの切替:** 問題点2の吐き出しを1か所にまとめます。INKEY側からEKEY側へは保留を渡しません（既存のまま）。ネイティブの非文字イベントは、標準側に残します。
- **検証:** 案の項目に、次の点を足します。
  - 値3が貼り付けの内と外でどうなるか
  - 吐き出した後にACCEPT、KEY?、INKEYで順序が保たれるか
  - 期限ちょうどに完成したイベントが返るか
  - ホストのunreadが33バイト入るか
  - SGRで押している状態をたどれるか

この方針で設計書へ反映し、採否を記録してよければ、1074（仕様）へ進みます。

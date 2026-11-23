確認は終わりました。結論として、**中以上の具体的なバグは見つかりませんでした**。低めの指摘が3点あります。

## 実行していないこと
Read/Grep/Globによる静的な読解だけです。編集、コマンド、ビルド、テストの実行、実機での確認はしていません。`zig build test` 成功の報告も、こちらでは再現していません。物理切断の再試行も未実施なので、合格扱いにはしていません。

## 問題がないと確認した点
- **プロトコル形式**
  - QueryExtension：応答の `[9]`=opcode、`[10]`=first_event で合っています。
  - RRSelectInput（minor 4）：本体8バイトに、`request` が付けるヘッダー4バイトを足して長さは3単位です。window、enable、padの並びで合っています。
  - マスク：`1|2|4|64` は `randr.h:117-125` の ScreenChange/CrtcChange/OutputChange/ResourceChange と一致しています。ResourceChange が使えるのは1.4以降ですが、`randrVersion` で1.5を交渉してから購読しているので問題ありません。
  - イベント番号：RRScreenChangeNotify=base+0、RRNotify=base+1 で正しいです。合成ビットも `&127` で外しています。
- **root の ChangeWindowAttributes**
  - 同じ接続で root にイベントマスクを付けている箇所はほかにありません（`host_window_linux.zig:1196` は自分の窓のカーソルです）。そのため、ほかの購読を上書きすることはありません。
  - 窓を作り直すと再送されますが、同じ内容なので無害です。
  - `changes_selected` は接続の寿命（`run()` の中）と一致しています。
- **publish**
  - 閉じた窓（`id == 0`）では、`display_dirty` を消すだけで回数を増やしません。
  - `geometry_dirty` も立てているので、`locate` と `monitorOn` を取り直します。Mutter の順序がどちらになっても、後から来た側で所属画面を更新できます。
- **回帰テスト**：`.conn = undefined` のままでも、`geometry_dirty=false` なので conn には触れず、成り立っています。

## 低めの指摘（中未満）
1. **root の関係ない PropertyNotify が `pending_release` を出してしまう**（`host_window_linux.zig:902-911`）
   - 新しいフィルターを通らなかった root の PropertyNotify（`_NET_ACTIVE_WINDOW`、`_NET_CLIENT_LIST_STACKING` など）は、`switch` の 28 番で id によって捨てられます。ただしその手前の907行で、保留中の KeyRelease を出してしまいます。
   - そのため、オートリピートの release/press の組を見分ける処理が崩れることがあります。影響するのは detectable repeat が効かないサーバーだけなので、低めとしました。
   - 修正案：902行のフィルターに `(kind == 28 and x.get32(bytes, 4) != self.id)` を加えて、先に return してください。
2. **余計な回数が増える**
   - 切り替え後の作業領域の値が同じでも、ワークスペースを切り替えるたびに WINDOW-CHANGES が増えます。`_NET_WORKAREA` が同じ値で書き直された場合も同じです。
   - 抜き差し1回で RandR のイベントが複数のループ周回に分かれて届くと、1回の変化で何度も増えます。
   - 仕様は「変わるたびに増える数」なので、取りこぼしよりは安全側です。
   - 抑えたい場合は、モニター一覧と作業領域の指紋（数、name、矩形、作業領域）を持っておき、違ったときだけ `display_dirty` にしてください。
3. **文書が古くなっている**：`docs/COMPATIBILITY.ja.md:116`（英語版の116行目も）に「Xの下のLinuxのウィンドウ（ディスプレイの構成そのものの変化は数えない）」とあります。この修正で Linux でも構成の変化を数えるようになったので、記述と食い違います。

## 補足（バグではありません）
- `watchChanges(...) catch null` で失敗すると、RandR の購読は窓を作り直すまで再試行されません。その間はプロパティ側の通知と ConfigureNotify だけが頼りです。
- 実機で再試行するときは、DP-3 を抜いたときと戻したときの両方で、WINDOW-CHANGES が増えた読取りの中で DISPLAYS と WINDOW-DISPLAY が揃っているかを見ると確実です。

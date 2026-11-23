# 1303・1336 設計レビュー

モデル: `claude-opus-5-5`（modelUsageで確認）。Read/Grep/Globのみ。実装完了や実機受け入れの承認ではない。以下はレビュー原文。

# 1303 と 1336 の読み取りレビュー（Read/Grep/Globのみ使用。コマンド実行・編集はしていません）

## 1303: Tk のフレーム提示（未完了のまま）

### いまの状態
- `WINDOW-FRAMES` と `WINDOW-PAINT-WAIT` は、DISPLAY-TK を選んでいてもネイティブのまま動きます（`src/graphics/graphics.fs:436-437`）。`(TK-SHOWN?)` で振り分けていません。実際に読んでいるのはネイティブの `shared` で（`src/core/words_graphics.zig:424-439`、`src/host_window_linux.zig:166-178`）、Tk だけで表示した場合は `0 0` と偽になります。表示内容と一致しないので、間違いではありませんが、何も伝えていない値です。
- `sigma_show`（`src/graphics/sigma_tk.tcl:144-194`）は、photo を差し替えて `sigma_fit` を呼び、そのまま R を返します。ラベルの再描画は Tk の idle 処理に回るので、R を受け取った時点では描画は終わっていません。
- `tcl.request` には期限がありません（`src/core/tcl.zig:384-391`）。R が届くまでブロックするので、`ms` の上限を守れません。R には要求 ID もないため、遅れて届いた R を次のスクリプトの結果と取り違えます。
- 状態取得の `windowMinimized` は別の X 接続を使い、2秒の固定期限です（`src/host_display_linux.zig:42-44`）。状態を知るには使えますが、描画の順序を保証するものではありません。

### 安全な実装に必要な条件
1. **番号は core が振る**
   - `sigma_show <serial> …` で通し番号 N を渡し、R が code 0 で返ったときだけ `tk_shown = N` にします。
   - 番号は State 単位で単調増加させ、wish の停止・再起動をまたいで続けます。
   - painted-through は最大値だけを持ちます。N より小さい値や重複した P は無視し、`tk_shown` を超える P はプロトコル違反として `lost` 扱いにします。
2. **完了は wish から非同期で通知する**
   - 新しい制御種別 `P <serial>` を作ります。W と同じく固定バッファで受け、ヒープを使わず、`sigma_pending_limit` でも捨てません。
   - PAINT-WAIT は `poll()` と短い sleep で、残り時間の範囲内で待ちます。ブロックする request は使いません。
   - WINDOW-FRAMES は `poll()` してから値を読むだけにし、wish が動いていなければ起動しません。
3. **完了の判定は wish 自身の X 接続で行う**
   - `after idle` も `update idletasks` も、それだけでは完了と見なしません。
   - `update idletasks` を流した後に、Tk 自身の Display で応答が返る要求を出します。候補は `winfo pointerxy`（XQueryPointer）です。その応答が届いた時点を「サーバーが処理した」とみなします。
   - ただし、使う Tk の版のソースで、キャッシュせず同じ Display に対して XQueryPointer を出していることを確認するまでは採用しません。ここが最大の未確認点です。
   - 別接続の round trip（Python のプローブや core の X 接続）は、wish 側の要求の順序を何も保証しません。
4. **idle の合体と、描いたのがどのフレームかを確かめる**
   - Tcl からはラベルの DisplayLabel が実際に走ったか、未 map のため飛ばされたかが見えません。そこで次の記録を持ちます。
     - `sigma_copy` のときの view の serial
     - fit を計算したときの `winfo width/height`
     - `<Expose>` の回数
   - P を送る条件は、view の serial が N、サイズが変わっていない、確認の前後で map 済み・viewable・Expose の回数が同じ、のすべてです。どれかが崩れたら、再描画させてもう一度確認します。
   - 速い SHOW が続いた場合は、その時点の最新の番号だけを通知します。ネイティブと同じ意味になります。
5. **最小化と復帰**
   - XWayland では Tk の `wm state` が更新されません（Mutter は map したまま最小化できるため）。PAINT-WAIT 側で WM_STATE を確認し、iconic なら確定しません。
   - iconic から normal に戻ったのを core が検知したら、`sigma_repaint N` で view を作り直させて、確認をやり直します。ネイティブ側の deferred paint（1332）と同じ考え方です。
   - そのためには `windowMinimized` に期限を引数で渡せるようにし、残り `ms` に合わせて短くする必要があります。2秒固定のままでは、短い PAINT-WAIT の上限を破ります。
6. **停止・再起動と SAVE**
   - `stop()` の上限付きの読み出しで、W と同じように P も取り込みます。`halt` しても painted-through は保持し、ウィンドウがなくなれば PAINT-WAIT はすぐ偽を返します。
   - 新しく作った State と保存したアプリでは 0 0 から始め、実行中の復元では値を保持します。`releaseHeap`、`forgetHeap`、部分的に読んだ P の扱いは、W と同じ固定バッファの規則にします。
7. **ネイティブとの共存**
   - 返す値は、選択中のバックエンドのものにします。ネイティブ側のカウンタには手を付けません。
   - VSYNC-WAIT は Tk では偽のままにします。
   - 1326（Tk の close 制御）に依存します。withdraw すると viewable でなくなり、確定しません。

### 具体的な阻害要因
- `winfo pointerxy` などが、同じ接続で round trip することを Tk のソースでまだ確認していません。
- Tcl から DisplayLabel の実行を直接観測する手段がありません。上の間接的な条件で代用するしかありません。
- `tcl.request` に期限がなく、P のプロトコルを追加する必要があります。
- `windowMinimized` の期限が固定です。
- 「サーバーが処理した」ことは、画面に合成されたことと同じではありません。ネイティブと同じ限界です。

### 検証案
- 偽ホストのテスト: P の重複・逆順・`tk_shown` 超過、SAVE をまたぐ部分 P、stop 中に届く P、合体。
- 実機: SHOW を連打したときの合体、PAINT-WAIT 中のリサイズ、最小化中は偽で復帰後に真、wish を kill した後に番号が続くこと、フルスクリーンの切り替え。
- wish を SIGSTOP して、`50 WINDOW-PAINT-WAIT` が上限時間内に偽を返すこと（上限が守られるかの対照）。

## 1336: Mutter による論理構成の変更（ソフトウェアによる再構成。物理的なケーブルの抜き差しではありません）

### 前提の確認（`.work/1336/DisplayConfig.xml`）
- `ApplyMonitorsConfigAllowed` が真であることを確認します。
- `properties` の `global-scale-required` が真なら、副画面だけの倍率2は API 上できません。X11 の GNOME セッションがこれに当たります。その場合は理由を記録してその手順を飛ばし、失敗とも成功とも扱いません。
- `XDG_SESSION_TYPE` と、experimental-features の `xwayland-native-scaling` を記録します。Xwayland の RandR に見える寸法（論理か物理か）は、これで決まります。
- D-Bus のセッションが正しいかを確かめます。GetCurrentState のモニター数と、RandR（`tests/scripts/verify-linux-monitor-moves.py:49-63`）の数が一致しなければ中止します。

### 手順
1. GetCurrentState で次を一覧にします。
   - 各モニター: connector、vendor/product/serial、`is-current` のモード ID、`is-underscanning`、`color-mode`、`rgb-range`、`is-for-lease`
   - 各論理モニター: x、y、scale（double をそのまま）、transform、primary、所属するモニター
   - `layout-mode`
   - clone（1つの論理モニターに複数のモニター）があれば中止します。
2. 復元用の設定を、元の状態から組み立てます。
   - mode ID は元の文字列のまま使います（VRR 用の ID も含む）。
   - `underscanning` は対応している場合だけ、`color-mode` は報告されている場合だけ渡します。
   - `layout-mode` は `supports-changing-layout-mode` のときだけ渡し、for-lease のモニターは `monitors-for-lease` に入れます。
   - `rgb-range` はこの API では設定できないので、変化していないことを確認するだけにします。
3. method 0（検証のみ）で、(a) 復元設定、(b) 副画面の倍率2、(c) 副画面を無効化、の3つを先にすべて通します。1つでも拒否されたら、何も変えずに終了します。
4. method 1（TEMPORARY）だけを使います。method 2 は使いません。API の記述上、temporary には自動で元に戻る仕組みがありません。

### 落とし穴
- **layout-mode 1 は論理座標です。** 倍率2にすると、副画面は 1920×1080 から論理 960×540 になります。今の配置は副画面が左（原点差 x=1920）なので、x=1920 のままだと主画面との間に隙間ができて拒否されます。
  - 位置は計算し直します。副画面 (0, y)、主画面 (960, 0) とし、y は主画面の縦の範囲と辺を共有する値にします。
  - 最小の x と y は 0 に正規化します。Mutter はずれた原点を拒否するはずですが、method 0 で確認してください。
  - 倍率は、そのモードの supported scales に含まれる値でなければならず、論理サイズは整数でなければなりません。
- **主画面はそのまま保ちますが、Xルート座標上の原点は動きます**（1920 から 960 へ、無効化時は 0 へ）。主画面基準の DISPLAY-RECT と、RandR の原点差は、毎回読み直して照合します。
- **競合**
  - serial は apply（検証と復元を含む）の直前に毎回取り直します。
  - AccessDenied（serial が古い）なら、状態が想定どおりかを確かめ直してから、上限付きで再試行します。想定と違っていれば、他者が変更したとみなして中止します。
  - 反映の順は、MonitorsChanged、GetCurrentState の一致、Xwayland の RandR 更新です。それぞれ期限付きでポーリングし、固定の sleep で済ませません。
  - Sigma の DISPLAYS はキャッシュされるので、手順ごとに DISPLAYS を呼び直します。
- **ID が変わる可能性があります。** DISPLAYS の ID は RandR モニター名の atom + 1 です（`src/display_randr.zig:145`）。Xwayland の出力名（`XWAYLANDn` など）は、無効化と再有効化で変わることがあり得ます。同じとは決めつけず、観測した結果を記録します。
- **倍率は X からは見えません。** XWayland で native scaling がなければ、Sigma のウィンドウは論理座標のまま合成時に拡大され、`WINDOW-PIXELS` は X のピクセルを返します。「物理倍率差」として何を測ったのかを限定して書き、倍率の報告を確認したとは書きません。
- **出力に対する確認**
  - 無効化の前に、所有ウィンドウを副画面へ移します。
  - 無効化後: DISPLAYS の数が減ること、WINDOW-DISPLAY が主画面の ID になること、WINDOW-CHANGES が増えること、ウィンドウが開いたままで 64×40 を保つこと、その後 PAINT-WAIT が真になること。
  - 最後に、GetCurrentState を serial を除いて正規化した値が元と一致すること、RandR の矩形が元と一致すること。
  - 終了時に stdout と stderr が空であること。

### 元に戻す仕組み
- テスト側は `finally` で復元します。apply の直前に serial を取り直し、現在の状態が元と同じなら何もしない（冪等）ようにします。
- これとは別に、独立した監視プロセスを置きます。
  - 最初の apply より前に起動し、準備完了の返事を受け取ってから先へ進みます。
  - `start_new_session=True` で起動し、SigmaSession がプロセスグループを kill しても巻き込まれないようにします。
  - 元の構成は、権限 0600 の専用一時ディレクトリに置きます。
  - 親とはパイプでつなぎます。読み口が EOF になったら親が死んだとみなします（SIGKILL でも検知できます）。PDEATHSIG だけには頼りません。
  - 上限時間（例: 120秒）が過ぎたら、無条件に復元します。
  - 親と監視プロセスが同時に復元しないよう、ロックファイルで排他します。正常終了したときは「完了」の印を送ってから閉じます。

## 次の手順の提案
1. 1303: インストールされている Tk のソースで、`winfo pointerxy` が同じ Display で round trip するか確かめます。その結果で同じ接続での確認方式を決め、P プロトコル、期限付きの PAINT-WAIT、期限を渡せる `windowMinimized` を、まず偽ホストのテストで固めます。
2. 1336: まず読み取りだけのスクリプトを作り、構成の一覧、セッションの種類、`global-scale-required` と method 0 の結果だけを記録します。監視プロセスの単体試験（親の kill、上限時間、二重復元の排他）が通ってから、method 1 の手順を追加します。
3. 記録には「ソフトウェアによる論理再構成。物理的な抜き差しは未確認」と明記します。1303、1336、1047 は完了扱いにしません。

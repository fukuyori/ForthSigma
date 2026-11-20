## 結論：B を採用します

B（SIGEND01 の 20 byte footer を維持し、CLI 解析の前に `image_format.parse` で検証した画像の system cell 0x0dd0 から判定する方式）のほうが、変更が小さく、安全で、具体的です。

- **A の問題（high）**：footer の APP bit と image 内の root が、同じ事実を二重に持つことになります。その結果、SIGEND01＋root あり、bit あり＋root 0、bit 0＋root ありという不一致状態が生まれ、それぞれに検査・エラー・テストが必要です。さらに、未検証の bit で CLI 文法を選んでから復元で失敗する、という順序の曖昧さが残ります。
- **B の利点**：検証済みの画像データだけを根拠に文法を選ぶので、上記の不一致状態そのものが存在しません。footer の版、flags、SAVESYS 再保存時の二重 footer 切り離しも、現在のコード（`src/main.zig:2825-2831`）のままで足ります。

裏付けとして確認した事実：
- encoder は system 領域 `0..system_end` をそのまま保存します（`src/core/image_encoder.zig:53`）。restore も同じ範囲をそのまま書き戻します（`src/core/image_restore.zig:54-55`）。そのため 0x0dd0 は保存・復元で値が保たれます。
- 0x0dd0 の手前にある `host_os_buffer_address` は 0x0dc8 で 8 byte です（`src/core/memory_map.zig:291-300`）。0x0dd0 から 0x0e00 の間に定義済みのアドレスはありません。
- Builtin enum は機能（feature）の構成にかかわらず共通で、除外される語は `image_features` が拒否します。このため ABI 署名は feature の違いでは変わりません。

## モジュールと関数の責務（案）

- **`core/app_entry.zig`（新規、共通の検査関数）**
  - `checkRoot(raw: Cell, word_count, builtin_count, wordAt) RuntimeError!?u16` を置きます。0 なら未登録です。それ以外は、範囲が builtin_count..word_count-1 にあること、kind が colon であること、compile_only=false であること、code 範囲が有効であることを検査し、満たさなければ InvalidImage にします。
  - `overlapsRoot(record)` は、0x0dd0 に重なる relocation record を拒否します。
  - 呼び出し元は inspect、`image_restore_plan.prepare`、`image_graph.collect`、append preflight の 4 か所です。全員が同じ関数を使うことで、「inspect では APP と判定したのに prepare では不正」という食い違いを防ぎます。
- **`core/image_format.zig`**：変更しません（必要なら `wordAt` を pub にするだけです）。
- **`host_saved_image.zig`（新規）**
  - `read(path, allocator) → Absent | Present{bytes} | Failed` を置きます。
    - 実行体を open・seek・ftell できない場合は Failed です。
    - 末尾の 8 byte が SIGEND01 でなければ Absent です。
    - marker が見つかった後に起きた失敗（u64 加算の overflow、`base+len+20 != end`、メモリ確保、読み取り）はすべて Failed です。現在の実装はこれらを null（埋込みなしと同じ扱い）にしていますが、これは high の欠陥です。null になると、APP 用の引数が Forth ソースのファイルとして INCLUDE される危険があります。
  - `inspect(bytes, allocator) !Saved{ m, l, entry: ?u16 }` を置きます。
    - 処理は、Workspace（約 74KB）を heap に確保 → `format.parse` → root cell の検査と、root 位置への relocation 重なりの検査 → Workspace を解放、の順です。
    - View は block の外へ持ち出さず、値だけを返します。
    - 結果の m/l は、現在の `imageLayout` の代わりに使います。
- **`main.run`**：上記の関数を呼び出す順番と、status の決定だけを担当します。

## エラーの順序

0. Mac の内部 child 判定（現行どおり）
1. argv を収集
2. `read` が Failed → stderr に固定の診断を出して status1
3. Present なら `inspect`。失敗したら status1。`--no-app` や `--format` でもこれは迂回できません。
4. entry があれば APP 文法（`--sigma` prefix）、なければ従来の `parseStartOptions` → option エラーなら status1。従来の `--format` の早期終了は、この後に置きます。Absent の場合は現行と同じ挙動です。
5. Present で `-m`/`-l` が指定されていれば拒否 → `startSizes` → Storage/State/host の準備
6. `restoreFreshImage`（prepare：feature 検査、builtin 表の一致、サイズ、`checkRoot`）が失敗したら status1。現在は「INVALID IMAGE !」を出して REPL へ進んでいますが、これは high の欠陥なので廃止します。
7. 復元後の root と inspect の entry が一致することを確認し、不一致なら status1（安価な防御です）。
8. `setArguments` → APP を実行、または従来の loop/REPL

## B で詰める点（medium）

- **二重 parse**：起動時に、CRC と構造検証が画像サイズに比例してもう 1 回実行されます。restore plan は自分の Workspace で再 parse する前提（`src/core/image_restore_plan.zig:22-25`）なので、View は共有せずに再 parse します。時間は測定していません（未確認）。
- **Workspace の生存期間**：約 74KB なので、`run` の stack に置かずに heap へ置きます。Storage を確保する前に解放します。
- **inspect では State がないため確認できない項目**：builtin 表の一致と feature の除外は、手順 6 で初めて検出されます。このため、option エラーが画像エラーより先に報告される場合があります。どちらの順でも引数は実行されないので、fail closed は保たれます。この順序は設計文書に明記します。
- **root cell の値**：負の値や u16 を超える値は InvalidImage にします。0 だけを「未登録」とします。
- **旧 ABI の画像**：parse の段階で status1 になります。現在の「INVALID IMAGE ! を出して REPL へ進む」からの意図的な挙動変更として記録します。
- **image=false**：この構成のビルドには SAVESYS がないので、画像の存在は外部で連結されたことを意味します。判定はビルド構成に依存させず、同じ規則で検証して実行します。flags は不要です。
- **legacy の no-entry**（root=0 の画像）：現行の文法のままで、`--sigma` を明示した場合だけ認識します。

## 設計文書への反映箇所

`.work/1067/design-review/design.md:29-33` の「SIGEND02」「APP bit」「SIGEND01 を旧版として扱う」という記述を、上記の reader の 3 状態、inspect、エラー順序の記述に置き換えます。19 行の preflight 記述と 23 行の共通 root 検査の記述は、`app_entry.checkRoot` を参照する形にそろえます。
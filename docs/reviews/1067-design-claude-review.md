# task1067 設計レビュー：保存アプリの起動基盤

`.work/1067/design-review/design.md` を、計画書と現行ソースに照らしてレビューしました。読み取り専用の Read/Glob/Grep だけを使い、コマンドの実行やファイルの編集はしていません。`docs/SAVED_APPLICATION_STARTUP_DESIGN.md` は凍結版と同じ内容でした。`result.json` は空です。

結論として、そのまま採用できない重大な欠陥が3件あります。起動順、`--format` と画像検査の順序、旧形式 footer の扱いです。中程度の欠陥は9件で、いずれもソースを根拠に解決策を決めました。利用者への追加の質問は不要と判断しています。

以下は、依頼どおり「レビュー原文」「判断」「採用仕様」を分けて記載します。

---

## 1. レビュー原文

### H1（高）起動順：デバッグ設定と後始末の位置がソースと逆
- **設計の記述**：「4 復元 → 6 debug/profile/log 設定と既存 cleanup を有効化」。
- **根拠**：
  - `src/main.zig:3633-3637` は、`plain_calls` などを画像の復元より前に設定しています。コメントは「Before the image: with the trace, its short definitions stay calls」です。これを復元の後に回すと、短い定義が呼び出し形式のまま残らず、`--trace` や `--profile` で数えられなくなります。
  - 後始末の defer は `main.zig:3592-3632` で、復元より前に登録済みです。設計どおり 6 で有効化すると、4 で失敗したときに後始末が走らない書き方になってしまいます。
- **解決**：採用仕様の「起動順」に現行の順序を明記します。

### H2（高）`--format` と画像検査の順序が決まっていない
- **設計の記述**：「少なくとも footer と画像の preflight を先に通す」。
- **問題**：
  - preflight の `image_restore_plan.prepare(state, …)` は、初期化済みの State（sizes・builtin・names）を必要とします（`image_restore_plan.zig:24-48`）。そのため、Storage 確保と `machine.init` より前の現在の早期 return 位置（`main.zig:3569`）では実行できません。
  - 「少なくとも」という書き方では、実装する範囲が決まりません。
- **解決**：
  - footer がない実行体（Absent）は、現在の早期 return のままにします。
  - footer がある実行体（Present）は、`machine.init` と下の a の後で、b の完全復元と root/flag 照合を済ませてから `formatFiles` で return します。
  - format 中は debug log・lint・profile を作りません。現在も作っていないためです。

### H3（高）SIGEND01 の扱いが実際には起こらない場合を前提にしている
- **根拠**：
  - ABI 署名は Builtin 列挙の名前をハッシュしています（`image_format.zig:436-441`）。新しい語を3つ追加すると、旧画像はすべて parse 段階で拒否されます（`image_format.zig:173`）。
  - 新しい実行体が読むのは自分自身のファイルだけです（`main.zig:3570`）。そのファイルを書くのは新しい SAVESYS なので、SIGEND01 が付くことはありません。
- **結論**：「SIGEND01 で root が登録された新 ABI 画像」は、手で連結しない限り生じません。
- **解決**：読み取り側は SIGEND01 を Failed（status1）とし、引数の文法選択も行いません。SAVESYS 側の切り離しは両方の footer を対象として残しますが、検査を厳密にします（H3 の補足）。
- **補足**：現在の SAVESYS の切り離しは magic と `prior_base <= base_len` しか見ていません（`main.zig:2827-2829`）。`base + image_len + footer == end` が完全に一致することを必須にします。

### M4（中）QUIT を status0 にすると、既存の引数処理と食い違う
- **根拠**：
  - QUIT は `error.Quit` を返します（`words_system.zig:158`）。
  - `-e` やファイル引数の中の QUIT は、`reportDiagnostic` の後に status1 になります（`main.zig:3723-3726`）。このとき表示はなく（`error_reporting.zig:74`）、`finishBlocks` も実行しません。
- **解決**：APP でも同じ扱いにします。表示なし、status1、`finishBlocks` なしです。

### M5（中）正常復帰時のスタック検査が BYE や `-e` と一貫しない
- **問題**：
  - 設計では、BYE は残りのスタックを検査しないのに、正常復帰だけ検査します。
  - `-e` も残りのスタックを検査しません。
  - 「DEFINITION ERROR !」という表示は、スタックの不整合を表す文としても不正確です。
- **根拠**：`finishBlocks`（`main.zig:3807-3817`）は defining・quote・postponing だけを検査します。
- **解決**：正常復帰は `finishBlocks` だけを通し、data・float・return スタックは検査しません。

### M6（中）root の範囲と再検査の時点
- **範囲の誤り**：登録できるのは colon 定義だけなので、セルの値の範囲は「1..word_count」ではなく「builtin_count+1..word_count」です。
- **登録後の変化**：`COMPILE-ONLY`（`defs.zig:990`）は最新の語に印を付けます。そのため、登録した直後に compile_only へ変わることがあります。
- **解決**：次の4か所すべてで同じ検査関数を使います。
  - `APP-ENTRY@`
  - `collectInternal`（SAVE/SAVESYS と、LOAD の読込み元）
  - `prepare`（画像のバイト列）
  - 起動直前

### M7（中）語を削除する経路の特定
- **問題**：「HERE巻戻し」で語を削除する経路はありません。
- **解決**：フックを `State.dropWordsFrom`（`forth.zig:1139`）に1か所だけ置きます。ここを経由する経路は次のとおりです。
  - FORGET（`definers.zig:109`）
  - MARKER（`forth.zig:1538`）
  - 語群のロールバック（`library_loading.zig:139`）
  - 定義中断（`error_reporting.zig:59,299`）
  - quotation（`quotations.zig:35`）
- **安全な例外**：`string_values.zig:37` はこの経路を通りません。ただし、直前に作った string_value の語を消すだけなので、登録済みの語に影響しません。
- **MARKER の扱い**：MARKER は登録状態の snapshot を持ちません。`marker_snapshot_size` は変えません。

### M8（中）アドレス registry との関係
- **書込み側**：`APP-ENTRY!` と `APP-ENTRY-OFF` で値を書くときは、`setArguments` と同じ方法でそのセルの古い記録を捨てます（`words_system.zig:53` の前例）。
- **画像側**：`image_restore_plan.prepare` の relocation のループ（`:57-83`）で、system 領域の slot が 0x0dd0..0x0dd8 に重なる記録を InvalidImage にします。
  - バイト列からの追加も `full.prepare` を経由するので（`image_append_plan.zig:27`）、同じ検査が働きます。

### M9（中）Ctrl+C の受入れケースが区別されていない
- **根拠**：
  - 割込みハンドラは、待機中のスコープでだけ導入されます（`host_wait.zig:86-106,116-122`）。
  - 計算中の Ctrl+C は、Windows では `restoreOnSignal` が 0 を返し（`main.zig:2232-2237`）、OS の既定処理で終了します。POSIX でも SIGINT の既定処理で終了します。
- **解決**：受入れケースを2つに分けます。
  - 待機中：USER INTERRUPT、status1、共通の後始末。
  - 計算中：OS による終了。終了コードは OS が決め、後始末は保証しません。

### M10（中）debug=false で使えるオプションの誤り
- **問題**：`--lint`・`--format`・`--format-check`・`--format-indent` も debug 専用です（`main.zig:2634-2695`）。
- **解決**：debug=false の `--sigma` で受け付けるのは、次の3種類だけです。
  - `-d`・`-r`・`-f`。`-m` と `-l` は、保存実行体では拒否、通常版では許可します。
  - `--no-app`
  - `--`

### M11（中）引数の詳細が決まっていない
- **argv[0]**：既存の `argument_list.items[0]` を使います（`main.zig:3694`）。`executable_path` ではありません。
- **上限**：引数は argv[0] を含めて 256 個まで（`max_arguments`）です。文字列領域は 0x11850 から 0x14000 までの 10160 byte で、各引数の長さ＋1の合計がこれに収まる必要があります。超えた場合は `StringTooLong`、status1 で、入口の語は呼びません。
- **空文字の引数**：`ARG` は、空文字の引数に対して「0 でないアドレスと長さ 0」を返します。範囲外の番号には `0 0` を返します（`words_system.zig:62-69`）。

### M12（中）診断表示の出力先
- **問題**：設計は stderr に出すとしていますが、既存の仕組みと異なります。
- **根拠**：既存の起動オプションの誤りは `terminalWrite`（stdout）に出ます（`main.zig:3560`）。復元失敗の表示は「INVALID IMAGE !」です（`main.zig:3688`）。
- **解決**：既存の仕組みに合わせます。

### 低優先度
- **L13**：image=false と files=false の扱いを明記します。`ARGC`〜`SHIFT-ARGS` は file 語群に含まれていないので（`defs.zig:60`）、files=false でも APP 引数を使えます。
- **L14**：macOS では、内部 child 用の引数 1 個だけを渡して APP を起動できません（`main.zig:3509`）。制限として記録します。
- **L15**：SAVESYS は出力先へ直接書きます（`main.zig:2836-2852`）。途中で失敗して footer のないファイルが残ると、通常の Sigma として起動します。1067 の範囲外です。今回は読み取り専用のため、tque には未登録です。

---

## 2. 判断

| 項目 | 判断 |
|---|---|
| xt 0 との衝突 | 「word-id＋1、0 は未登録」を維持します。`APP-ENTRY@` は `0 0` または `xt -1` を返します |
| 登録できる語・ID の寿命 | colon 定義だけ。範囲を builtin_count+1..word_count に修正し、4か所で再検査します（M6）。削除時の解除は `dropWordsFrom` で行います（M7） |
| エラーの種類 | 実行中の状態の検査は -261、画像バイト列の検査は InvalidImage にします |
| 追加読込み | 読込み元の登録は無視し、読込み先のセルは書き換えません。`appendImage` は system 領域をコピーしないため、構造上そうなります（`dictionary_image.zig:229`） |
| SIGEND01 | 読み取り側は Failed にします。SAVESYS 側の切り離しは厳密な一致検査で残します（H3） |
| QUIT | `-e` と同じく、表示なし・status1 にします（M4） |
| 正常復帰 | `finishBlocks` だけを通します（M5） |
| `--no-app` | APP 文法でだけ意味を持ちます。それ以外の文法では受け付けますが、何もしません |
| 画像の破損 | `--no-app` を付けても復元しません。登録を解除する手段は、APP-ENTRY-OFF の後に SAVESYS で保存し直すことです |

---

## 3. 採用仕様

### API（image 語群。image=false では除外）

- **`APP-ENTRY!` `( xt -- )`**
  - 検査の順序：
    1. スタックの深さを検査します。不足なら StackUnderflow。
    2. defining なら -259。
    3. xt を検査します。colon 定義であること、compile_only でないこと、code 範囲が `code_count` 以内であることを確認し、満たさなければ -261。
  - すべて合格してから pop し、セル 0x0dd0 に id+1 を書いて、そのセルの古い registry 記録を捨てます。
- **`APP-ENTRY@` `( -- xt flag )`**：未登録なら `0 0`、登録済みなら `xt -1` を返します。セルの値が破損していれば -261 とし、値は返しません。
- **`APP-ENTRY-OFF` `( -- )`**：0 を書き、registry 記録を捨てます。
- **コンパイル時の検査**：
  - `host_os_buffer_address + 8 <= 0x0dd0`
  - `0x0dd8 <= timezone_buffer_address`

### 削除・保存・追加読込み

- **削除**：`dropWordsFrom(id)` の中で、`root - 1 >= id` ならセルを 0 にします。
- **保存（SAVE/SAVESYS）**：`collectInternal` で root を検査し、0x0dd0 に重なる記録を拒否します。
- **画像の検査**：`image_restore_plan.prepare` で、view の system 領域から root を取り出し、view 内の語と照合します。0x0dd0 に重なる relocation は InvalidImage です。
- **追加読込み**：State 経由・バイト列経由のどちらでも 0x0dd0 を書きません。これを試験で確認します。

### footer

- **SIGEND02 の形式**：24 byte。オフセット 0 から magic、8 から `image_len`（u32）、12 から `base_len`（u64）、20 から `flags`（u32）です。bit0 が APP 登録の有無で、それ以外のビットは 0 でなければ Failed です。
- **読み取りの判定**：
  - 末尾 24 byte の先頭が `SIGEND02` か、末尾 20 byte の先頭が `SIGEND01` かを確認します。
  - SIGEND01 なら Failed です。
  - どちらの magic もなければ Absent です。
  - 自分のファイルを開けない・読めない、加算のオーバーフロー、長さの不一致、確保の失敗は Failed です。
- **失敗時の表示**：
  - machine の初期化前：`terminalWrite("INVALID IMAGE !\n")`、status1。
  - 初期化後：`reportDiagnostic(error.InvalidImage)`、status1。
- **flag と root の照合**：flags の bit0 と「root ≠ 0」が一致しなければ InvalidImage です。
- **SAVESYS の flags**：`prepareSave` で検査済みの同じ root から作ります。

### 引数の文法

- **`--sigma` なしの APP 実行体**：argv[1..] をすべてアプリへ渡します。
- **argv[1] が `--sigma` の場合**：厳密な解析を行います。`--` で終わるか、引数の最後で終わります。それ以外の語（空文字を含む）は `<arg>: UNKNOWN OPTION !`、status1 です。
- **`--` の後**：
  - APP 文法では、すべてアプリの引数です。
  - `--no-app` を付けた場合と通常の文法では、既存のファイル・`-e` の処理へ渡します。ホストのオプションとしては解析し直しません。
- **APP 文法で `--no-app` が必須のもの**：`--format`・`--format-check`・`--lint`。
- **argv**：argv[0] は既存の値です。上限は M11 のとおりです。

### 起動順

1. Mac の内部 child 用プロトコル。
2. 実行体のパスを取得し、footer を読みます。
3. 文法を選び、オプションを解析し、`startSizes` でサイズを決め、保存されたレイアウトを適用します。
4. Absent で format 指定なら、現在どおり早期 return します。
5. Storage・Runtime・`machine.init` と、既存の defer を登録します。
6. a：`step_limit`・`tracing`・`trace_limit`・`plain_calls`・`cover_blocks` を設定します。
7. b：Present なら `restoreFreshImage` を行い、root と flag を照合します。
8. c：format 指定なら return します。
9. d：debug log・lint・profile を作ります。
10. `setArguments` を行います。
11. APP 文法で `--no-app` がなければ、`resetSteps` の後、root を再検査して `executeWord` を1回だけ呼びます。

### 終了

| 終わり方 | 扱い |
|---|---|
| 正常復帰 | `finishBlocks` |
| BYE（halted） | `finishBlocks` |
| QUIT | 表示なし、status1 |
| THROW、UserInterrupt、StepLimit | `reportDiagnostic` の後、status1 |
| 計算中の Ctrl+C | OS が終了させます。後始末は保証しません |

暗黙のポーリングは追加しません。EXEC-LIMITED は debug=true かつ extension=true の構成でだけ使えます。

### ビルド構成による除外

- 画像の root 検査と `--sigma` の文法は、すべての構成で同じコードを使います。
- debug=false の `--sigma` は、M10 の3種類だけを受け付けます。

---

**未確認**：今回は読み取り専用のため、ビルド・テスト・実際の起動は一切行っていません。`git status` も確認していません。
# 1067 採用設計 フォローアップレビュー（読み取りのみ）

レモン、まとめると、高 1 件・中 4 件・低 1 件の欠陥が残っています。ご指定の論点のうち、ここに挙げていないものはソースと整合していました。footer02 案と暗黙 polling 案は扱っていません。

## 修正が必要な点

**H1 SAVESYS を一時ファイル＋原子的置換にすると、自分自身の実行体を上書きできてしまう**
- 根拠：
  - 現在の自己上書き防止は、文字列比較 `eqlIgnoreCase(output_path, executable_path)`（`main.zig:2817`）だけです。
  - Linux の `executable_path` は `/proc/self/exe` を readlink した実パスです（`main.zig:2915-2919`）。そのため `SAVESYS ./sigma` や symlink 経由の指定は、この比較をすり抜けます。
  - 現行の `fopen("wb")` は、実行中ファイルなら ETXTBSY で失敗するので、結果的に上書きを防いでいます（※推測です。OS の挙動は未確認）。
  - rename は実行中でも成功するため、本体の Sigma が保存アプリに置き換わります。
- 修正案：
  - 公開の直前に、保存先と現在の実行体が同じファイルかどうかを ID で比較し、同じなら `FileUnavailable` にします。POSIX は `st_dev`/`st_ino`、Windows は volume serial と file index を使います。
  - 保存先が symlink の場合も扱いが変わります。現行はリンク先へ書き込みますが、rename はリンク自体を置き換えます。「リンク先へ書く／リンクを置換する／拒否する」のどれにするかを仕様に明記してください。

**M1 実行体を開けない場合を Failed にすると、通常の Sigma も起動できなくなる**
- 根拠：現行では `fopen` が失敗すると null を返し、通常起動します（`main.zig:2448`）。設計では open/seek/ftell の失敗が Failed → status1 になり、保存アプリでない Sigma にも適用されます。そのため、実行専用権限（例：0711）の実行体ではすべての起動が失敗します。
- 修正案：fail closed の方針は維持し、「実行体が読み取り可能であること」を起動要件として設計文書に明記します。あわせて 1069 の試験表に「読み取り不可の実行体 → status1」を加えます。

**M2 `--format` に `--no-app` を必須とする範囲があいまい**
- 根拠：設計文書の 49 行目は「saved実行体では」と書いています。登録なし（root=0）の旧来の保存実行体は従来 grammar（`parseStartOptions`）で `--format` を直接受け付けるので、これを必須にすると互換性が壊れます。
- 修正案：「root≠0 の APP 実行体だけ `--sigma ... --no-app` が必須。root=0 の保存実行体は従来 grammar のまま、完全復元の後に整形する」と明記します。

**M3 APP 入口を呼ぶときの入力ソースが決まっていない**
- 根拠：
  - 設計では host から `executeWord`（`forth.zig:1490`）を直接呼びます。
  - この場合、`interpretSource` が行う準備（`forth.zig:603-619`）を通りません。具体的には `blk=0`、`source_kind`/`source_line`/カーソルの設定、`last_created_word=null` などです。
  - このため SOURCE、>IN、PARSE-NAME、EVALUATE の起動時の状態が仕様にありません。実際に誤動作するかは未確認です。
- 修正案：core に `runEntry(id)` を置きます。空行の terminal source（`-e ""` と同じ文脈）を用意してから `executeWord` を呼び、終わったら元に戻します。

**M4 debug-log の生成を復元後へ移すと、復元失敗が log に残らない**
- 根拠：現行では log/lint/profile を復元前に生成しています（`main.zig:3639-3686`、復元は 3688）。log への記録は、log が有効なときだけ行われます（`error_reporting.zig:35`）。そのため設計の手順 8 へ移すと、復元失敗の `InvalidImage` が log に入りません。
- 修正案：
  - format 以外では debug-log を手順 5（復元前）で開き、lint/profile は手順 8 のままにします。
  - `--format` と `--debug-log`/`--lint`/`--profile` を同時に指定した場合の扱いを、現行どおり無視するか拒否するかを明記します。

**L1 slot 記録の除去関数の副作用**
- `discardRange` で `0x0dd0` を除去すると、そのセルを指している他の record も invalid になります（`address_registry.zig:150-151`）。害は小さいと考えますが、slot だけを取り除く専用関数の方が意図がはっきりします。

## 整合を確認した点
- **QUIT**：`-e` の経路と同じく `reportDiagnostic` を通り、表示なしで戻ります（`error_reporting.zig:74`）。その後 status1 になり、finishBlocks は通りません（`main.zig:3723-3726`）。
- **BYE**：`saveAll` の後に `halted` を立て（`words_system.zig:154`）、`executeWord` から正常に戻ります（`forth.zig:1892`）。
- **スタックの残り**：finishBlocks はスタック深さを検査しません（`main.zig:3807-3817`）。
- **State なしの feature 検査**：`image_features` と `format.parse` は State を必要としません（`image_features.zig:3-11`、`image_format.zig:170`）。
- **完全復元**：system 領域 `0..system_end` をコピーするので、`0x0dd0` も含まれます（`image_restore.zig:55`）。
- **追加読込み（append）**：
  - system セルを一括コピーはしません。
  - ただし、残した relocation record は system slot にも適用されます（`image_append.zig:108-113`）。このため設計にある「`0x0dd0` に重なる record の拒否」は必要です。
- **image=false**：
  - ABI 署名は Builtin enum 全体をハッシュします（`image_format.zig:436`）。そのため image=true で作った画像も parse を通り、非zero root の拒否は防御として意味があります。
  - 3 語はすでに除外リストに入っています（`defs.zig:63`）。
- **削除フック**：FORGET/MARKER/library の rollback/定義の中断は、`forgetFrom` → `dropWordsFrom` に集まっています（`forth.zig:1122-1142`、`error_reporting.zig:59,299`、`quotations.zig:35`）。`string_values.zig:38` は `dropWordsFrom` を通りませんが、対象は新しい string_value 語だけなので、colon の登録には影響しません。
- **SAVESYS の古い画像の切り離し**：現行は `prior_base` だけを信用しています（`main.zig:2827-2830`）。長さを照合する設計の修正は妥当です。
- **実装の進行状況**：`app_entry_address=0x0dd0`、そのコンパイル時の重なり検査、`app_entry.forget` の `dropWordsFrom` への組込みは、すでに作業ツリーに入っています。

## 未確認
- H1 の ETXTBSY と rename の OS 挙動（推測のみ）
- M3 で実際に誤動作が起きるか
- ビルドとテストは実行していません
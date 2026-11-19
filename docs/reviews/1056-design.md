# Claude Code設計レビュー原文

2026-11-19。セッション`4c61ae7d-299a-4da2-b4ea-4a23b263181d`。読み取り専用。

# 1056 語群基盤・1036 OS判別 設計レビュー

レモン、レビュー結果です。提案の大筋（extensionを独立した語群にする、第三のmagicを作らない、内部runtimeは除外構成でも残す）は妥当です。ただし、イメージの扱いと文字列の置き場所には、そのままでは不具合になる点があります。

## 指摘（重大度順、8件）

### 1. 【高】除外構成でイメージを拒否すると、既存のaudio/graphicsと挙動が変わる
- **現状:**
  - `image_format.parse` はmagicからkindを判別しますが、`header.kind` を拒否には使っていません。kindを参照しているのはテストだけです。
  - 復元時の照合（`image_restore_plan.zig:28-32`）は起動時の組込み語（`builtin_count` 未満）だけが対象です。
  - このため `-Daudio=false` のビルドでも SIGIMG47 を読み込めます。読み込んだSND語を実行すると、`executeBuiltin` が `InvalidExecutionToken`（-261）を返します（`forth.zig:2244`）。
- **ABI署名で区別できない理由:** `abi_signature` は `Builtin` enumの全名前から計算します。enumはビルド構成によらず同じなので、`-Dextension=true/false` は同じ署名になります。HOST-OSの追加で旧版を拒否できるのは提案どおりですが、除外構成とは区別できません。
- **推奨:**
  - `image_restore_plan` と `image_append_plan` に共通の検査を設けます。`builtin_count` 以降の `.builtin` 語と、`.builtin` Opについて `defs.isExcludedBuiltin` を確認し、該当すれば `InvalidImage`（-264）にします。
  - 起動時の組込み語の欄（名前なし）は検査から外します。
  - データに保存したxtは静的には検出できないため、実行時の-261の防御は残します。
- **ご判断が必要な点:** この検査をextensionだけに適用するか、全語群に適用するか。私の推奨は全語群です。ただし、audio/graphicsを除いたビルドで今まで読めたイメージが読めなくなるという挙動変更になります。

### 2. 【高】HOST-OSの文字列を起動時に1回書くと、別のOSで復元したときに古い値が返る
- `c-addr` は論理メモリ上のアドレスです。システム領域（`system_end` まで）はイメージに保存・復元されます（`memoryLength`）。
- 起動時に1回だけ書く方式では、Windowsで保存したイメージをLinuxで復元すると "windows" が返ります。データ空間に置いても同じ問題が起きます。
- **推奨:**
  - HOST-OSを呼ぶたびに、固定8バイトの欄へ書き直します。文字列の最長は7文字です（windows/unknown）。
  - 欄の候補は `0x0dc0` です。16進リテラルの検索では未使用でしたが、計算されたオフセットで使われていないかは未確認です。
  - 文書には「次のHOST-OSの呼出しかイメージ復元までは有効。書き換え禁止」と記載します。

### 3. 【中】語群を記録するセルの空きが既存の範囲にない
- `0x02d0`〜`0x02f8` はgraphics/audio/gui/gameで使用済みで、`0x0300` は `tmp_string_base` です。
- **推奨:**
  - `extension_vocabulary_address = 0x0dc8` を新設します（2と同じ空き帯の候補で、未確認）。
  - magicを変えないため `image_address = null` とします。
  - `library_loading.Group.image_address` のコメントは「組込み語のない語群」を前提に書かれており意味がずれるので、合わせて更新します。

### 4. 【中】イメージ追加（append）後の認識が二重の経路と固定長配列に残っている
- `image_append.zig:15` の `groups_loaded: [4]bool` が固定長です。
- 語群の一覧が `:22` と `:124` に、さらに `dictionary_image.appendImage` の `:128-131` と `:268-271` にもあります。
- **推奨:** 語群の表を1か所（例: `library_groups`）にまとめ、両方の経路で使います。設計3節の「同じ機能表」に当たります。
- **確認するテスト:** append後に `isLoaded` が真になること、再度 REQUIRE-EXTENSION しても語数が変わらないこと、FORGET/MARKER の後に再読込みできること。

### 5. 【中】除外時の REQUIRE-EXTENSION を -13 にすると、他の語群と異なる
- 既存では、除外構成の REQUIRE-GRAPHICS は -270、REQUIRE-AUDIO は -275 です（`words_audio.zig:66`）。-13 にするとこれと揃いません。
- **推奨:** 新しいエラー番号を設けないというご指示に従います。実装は「無効時は `forth.zig:1265` 付近のparser分岐そのものを外し、通常の未定義語の経路へ流す」形にします。エラー表示に語名が出て、処理も最も単純です。
- **副作用（文書に記載）:**
  - 有効構成ではparserが先に処理するため、利用者が定義した同名の語は呼べません。除外構成では見つかります。
  - REQUIRE-AUDIOなどと同じく `[DEFINED]` では検出できません。有無の判定は、`EVALUATE` を `CATCH` して -13 を見る方法になります。

### 6. 【中】コールバックか comptime target か → comptime（`builtin.os.tag`）を推奨
- coreにはすでに `paths.zig:197` で `@import("builtin").os.tag` を使っている前例があります。`freestanding_check.zig` が保証しているのは「OSのサービスに到達しないこと」で、コンパイル時の定数は抵触しません。
- freestandingでビルドすると `.freestanding` になり、自動的に unknown になります。
- 返す値は4種類に限られるため、コールバックの柔軟性は使いません。逆にコールバックだと、`Writer` への追加、main.zig・テスト用ホスト・将来のホストすべてへの接続、返り値の検査が必要です。接続を忘れると、実際のOS上で黙って unknown になります。
- **対応:**
  - `.windows` は windows、`.linux` は linux（WSL・Androidも含む）、`.macos` は macos、それ以外は unknown。
  - 実行中のホストを個別に区別する必要が出た場合は、設計どおり別の語にします。

### 7. 【低】既存の設計文書との差分と、依存関係の切替え
- 詳細設計3節（100-102行）は `HOST-OS ( -- os )` と `OS-UNKNOWN=0` などの数値定数です。今回の文字列案はこれと異なります。R06の条件（extensionに所属させる）は満たしています。
- 更新が必要な箇所:
  - 詳細設計 3節
  - DESIGN_DECISIONS 16行
  - PLAN 4・59・176・220行
  - tque の依存（1056の先行条件を900から1064へ）
- Gforthに同等の語や環境問い合わせがあるかは未確認です。名前を確定する前に、WSLのgforthで確認することを推奨します。

### 8. 【低】HELP・ライブラリ・ビルド構成の取りこぼし
- `defs.zig` に `extension_builtins` を追加し、`excluded_builtins` に含めます。
- `words_help.isExcludedName` に REQUIRE-EXTENSION と extension の `definitions` を追加します。
- `host_os` は `Builtin` enumの末尾に追加します。
- `require` は埋め込みライブラリを前提にしています。最小限の `src/extension/extension.fs` を置くことを推奨します。ソースファイル表の枠を1つ使うかどうかは未確認です。
- freestanding は既定のオプションでビルドされるため、extensionを含むコンパイル確認になります。
- `-Dextension=false` のテストを追加します（`audio_test.zig:53` と同じ形）。

## 採用を推奨する仕様

| 項目 | 推奨値 |
|---|---|
| ビルド | `-Dextension`（既定true）、`defs.extension_enabled` |
| 読込み | REQUIRE-EXTENSION はparserで処理（REQUIRE-AUDIOと同じ位置）。有効時のみ分岐。定義中は -259 |
| 除外時 | 分岐なし。通常の未定義語として -13。新しいエラー番号なし |
| 語群 | vocabulary `EXTENSION`、記録セル候補 `0x0dc8`、`image_address=null`、`definitions` は HOST-OS から開始 |
| HOST-OS | `( -- c-addr u )`、ASCII小文字で windows/linux/macos/unknown。comptime の `builtin.os.tag` から決定。呼ぶたびに固定8バイト欄（候補 `0x0dc0`）へ書く |
| イメージ | magicはSIGIMG45/46/47のまま。ABI署名はHOST-OS追加で自然に更新。除外語の内容検査で -264（全語群に適用するかはご判断） |
| append | 語群の表を1か所にまとめ、両方の経路で使う |
| HELP | 未読込みでも説明する。除外構成では一覧から外す |
| 既存語 | 移動しない。内部runtimeは常に含める。files/debug の条件は該当する機能の担当で適用する |

## 読んだ範囲と実施しなかったこと
- **読んだもの:**
  - PLAN（4-139行、145-221行の該当箇所）
  - DETAILED_DESIGN 1〜3節
  - DESIGN_DECISIONS 全文
  - library_loading.zig、dictionary_image.zig、image_format.zig、image_append.zig は全文
  - defs.zig（20-64行、590-690行、1150-1167行）
  - words_help.zig 90-170行
  - words_audio.zig 1-90行
  - forth.zig（905-944行、1245-1289行、2240-2252行）
  - memory_map.zig の該当箇所、freestanding_check.zig、audio_test.zig 50-134行
  - build.zig・host_interface.zig・レビュー文書はGrepで該当箇所のみ
- **読んでいないもの:** image_restore.zig の本体、main.zig、help_text の表示処理、CLAUDE_REVIEW の全文、gforth。
- **実施しなかったこと:** 編集、Git操作、ビルド、テスト、外部アクセスはいずれも行っていません。

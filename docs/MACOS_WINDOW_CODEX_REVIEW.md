# macOSネイティブウィンドウ（#975・#922）のCodexレビュー原文

2026-11-17。Codex CLI 0.169.0（表示モデルgpt-6-luna、読み取り専用サンドボックス）による静的レビュー。未コミットの作業ツリーが対象で、ビルド・テスト・ウィンドウの表示は行っていない。以下は受領原文（ファイルへのリンクだけ相対パスに直した）で、[対応](MACOS_WINDOW_REVIEW_RESPONSE.md)による修正前の指摘を含む。行番号は依頼時点のもの。

## 指摘

1. **[高] キュー満杯時にキー解放イベントを捨て、押下状態が残る可能性があります** — [src/host_window_macos.zig](../src/host_window_macos.zig:335)

   `input_queue` が満杯だと、イベント種別を判定する前に入力行を破棄します。`KEYUP` も対象なので、キーを押した後、親が入力を読まない状態でキューが満杯になると、解放が親へ届かず `held_keys` に押下状態が残りえます。結果として `KEY-HELD?` が真のままになる可能性があり、G3の「キュー満杯でもキー解放を失わない」という契約と食い違います。記録にも、キューあふれは未確認とあります。

2. **[中] 子から親への入力通知が部分書き込みされると、プロトコル行が欠けます** — [src/host_window_macos.zig](../src/host_window_macos.zig:1009)

   `outputInput` はstdoutを一時的に非ブロッキングにし、`write`を1回だけ呼びます。戻り値を確認・再送しないため、書き込みが部分成功または`EAGAIN`になると、`INPUT`行が途中で切れ、親の行パーサーはイベントを認識できません。特に、親が入力を読まずパイプが混雑している状況でキー解放通知が欠けると、上記の押下状態残留につながります。G3の文書は「入力通知でイベントループを止めない」としていますが、通知の欠落も防ぐ必要があります。

3. **[中] `SHOW` の競合修正を「合成試験で確認」と明記すべきです** — [docs/NATIVE_WINDOW_STUDY.md](../docs/NATIVE_WINDOW_STUDY.md:622)、[docs/HANDOFF.md](../docs/HANDOFF.md:5)

   検討書には、競合修正は合成クリック試験で再試験し、利用者操作での再現・解消は確認できていない、と正確に書かれています。一方、HANDOFF冒頭は「#922の確認で…不具合を3件直した」とまとめており、その制限が冒頭の要約からは読み取れません。文書全体としては留保がありますが、要約だけを読むと実操作でも解消を確認したように受け取られる余地があります。

4. **[低] 旧辞書のABI変更理由は説明がやや粗いです** — [src/core/words_graphics.zig](../src/core/words_graphics.zig:34)、[src/core/defs.zig](../src/core/defs.zig:1111)

   新しい4語は`definitions`の末尾に追加されており、既存の組込み語の追加位置を保つ意図は確認できました。ただし、記録は旧`SIGIMG46`が拒否される理由を「組込み語が4つ増えてABIが変わった」と一括して説明しています。読み取れる実装上の変更は、グラフィックス辞書に4語を追加したことと、旧辞書をソースから再構築する必要があることです。どのABI検査が拒否を決めたかまでは、記録から特定できません。なお、辞書ロードや保存の動作確認は依頼に従い実行していません。

## ほかの観点

- **親子プロセスの基本的な通信・後始末:** `HELLO/READY`、`FRAME/FRAME-READY/FRAME-ACCEPTED`、`QUIT/CLOSED/EXIT`、期限、再試行、子の回収、close-on-exec設定、親のパイプ終端時に子を終了させる経路をコードで確認しました。コード上で明確な追加不具合は見つけませんでした。実機での成否を独立に確認したものではありません。
- **ウィンドウ閉鎖と`SHOW`、IME表示経路:** 閉鎖後の再生成、キー・マウス解放、変換中文字列と確定文字の経路を読みました。上記のキュー飽和時の解放欠落以外に、コードから確実に指摘できる問題は見つけませんでした。
- **G3との食い違い:** macOS初回表示が前面になる挙動は、決定G3の追記と実装に一致します。内蔵Retinaでの受け入れ記録と、外部画面・SSH経由を未確認とする記述も区別されています。8項目表は性能について合格を主張していません。
- **テストの抜け:** 追加されたテストは自動表示の基本経路と手動確認スクリプトが中心です。親子プロトコルの異常・満杯キューでの解放保持・部分書き込みを自動で検査するテストは、今回読んだ差分範囲では見当たりません。ビルドやテストは実行していません。

## 読んだファイル

`src/host_window_macos.zig`、`src/host_window.zig`、`src/main.zig`、`src/core/words_graphics.zig`、`src/core/graphics_input.zig`、`src/core/host_interface.zig`、`src/forth.zig`、`src/core/defs.zig`、`src/graphics/graphics.fs`、`src/graphics/gui.fs`、`src/tests/graphics_test.zig`、`tests/scripts/check-ime.fs`、`tests/scripts/check-window.fs`、`docs/NATIVE_WINDOW_STUDY.md`、`docs/DECISIONS.md`、`docs/HANDOFF.md`、`CHANGELOG.md`。

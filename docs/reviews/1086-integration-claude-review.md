# 1086 Claude Code最終統合レビュー原文

2026-11-19。読み取り専用。実行試験は行っていない。テスト実績・採否と区別する。

## 依頼

```text
Final read-only integration review for task1086 after1084/1085 review fixes. Read docs/reviews/1084-1085-review-response.md and verify high/medium corrections in src/host_window_macos.zig physical/polling locks/Sender, src/physical_key_protocol.zig Sender/Receiver and tests, src/host_window.zig SetTimer/GetKeyState/native hooks/support, src/physical_key_map.zig special codes and XKB, src/host_x11.zig XError differentiation, src/host_window_linux.zig physicalNames/error/repeat/close, src/core/words_graphics.zig physical words, src/tests/physical_key_test.zig. Earlier reviews in1084-native-claude-review.md and1085-public-claude-review.md. Do not edit or run commands. Product source is now frozen while Windows final build/native7-stage acceptance, Linux final build/core-host-runtime/native7 stages, Mac full/reduced cross compile and12-config matrix run. Earlier Windows/Linux native5-stage acceptance and Windows7-stage refined acceptance passed; Mac runtime and physical keyboards unverified. Focus on remaining blocking bugs only, not style or speculative new features. Check single SCANSYNC request after successful write, command state locks never wait on blocking stdout, latest final key-up recovered with pure Sender test, unavailable lines ignored, Shift release polling, Pause/Print unsupported, unaligned snapshot/written/stack atomicity, optional-group exclusion and image reset boundaries. State whether1084/1085/1086 can close after tests pass while1082 Mac runtime stays open. Separate genuinely blocking implementation defects from Mac runtime acceptance obligations. Be concise Japanese.

```

## 原文

## 結論

レビュー指摘への修正を読んだ範囲では、統合を止める実装上の欠陥は見つかりませんでした。今回は読んだだけで、コマンドとテストは実行していません。

- **1084・1085**：実行中のテストとビルドがすべて通れば閉じられます。
- **1086**：統合として閉じてよいと判断します。ただし、実機キーボードでの確認が1086の完了条件に入っているかは未確認です。入っていれば、その確認が残ります。
- **1082（Macの実機確認）**：閉じられません。

## 確認した項目（すべて問題なし）

| 項目 | 根拠 |
|---|---|
| SCANSYNC要求は書込み成功時の1回だけ | `src/host_window_macos.zig:20`。9バイトすべてを書けたときだけ再送待ちを消します。親はシングルスレッドで、`sendFrame` は最後まで書くか失敗するかのどちらかです。そのためFRAMEの途中に要求が混ざることはありません |
| 状態lockがstdoutの空きを待たない | `:1367-1388`。stdoutはtry-lockで取ります。命令スレッドは `physical_guard` もtry-lockで取ります。キー入力スレッドが待つのは `physical_guard` だけで、これを持つ側は書き込みで待ちません |
| 最後のキー離しの回復 | `src/physical_key_protocol.zig:84-150`。dirtyにしておき、16msの周期でSCANSNAPを送ります。追加のキー操作がなくても回復することを、OSに依存しないSenderのテストで確認しています。SNAP行は約100バイトで、受信バッファ（640バイト）とPIPE_BUFに収まります |
| ウィンドウを閉じた後の行を捨てる | `Receiver.accept:9`、テスト `:70`。新しい子プロセスでは受信状態を初期化します（`:654`）。`readFrameStatus` もINPUT行をここに渡します |
| Shift離しの補完 | `src/host_window.zig:1024,1055-1065`。補うのは離しだけです。タイマーの作成に失敗したときは、`supported[28]&~0x22` で左右のShift（225と229）を未対応にします |
| Pause/PrintScreenを未対応にする | Windowsでは `windowsScan` が0を返し、対応表からも70と72を除いています。X11ではPAUSを0にしています |
| XKB | AB11とAE13は行の範囲を超えるので、個別の名前の表で引かれます。COMPも同様です（テストは `physical_key_map.zig:82-84`） |
| X11のXErrorを区別する | `src/host_x11.zig:298`。物理キー機能をなしにするのはUnavailableとXErrorのときだけです（`host_window_linux.zig:346`）。それ以外のエラーは従来どおり `.failed` へ渡ります |
| Linuxのキーリピートとウィンドウを閉じる処理 | ペアになった離しはループの1周期分遅らせて扱います（`:1168`）。閉じたとき・終了時は `close()` を呼び、ロック内でまとめて処理します |
| アドレス検査とスタックの一貫性 | アドレスは `memoryAddress` で検査し、通ってからresyncします。KEY-EVENTはスタック3セル分の空きを先に確かめてから `next` を呼びます。境界をずらしたコピーと、再配置記録の `written` はテストで確認しています |
| image復元の境界 | `image_restore.zig:102` は復元の確定段階にあります。復元に失敗したときにresetされないこともテストしています |
| 機能を外した構成 | テストは `build_options.graphics` をcomptimeで判定して外しています |

## 統合を止めない残存点（参考）

- **X11**：`physicalNames` を待つ間に、それより前の別の要求に対する非同期XErrorが届くと、GetNamesの応答が後から届いて系列番号が合わず切断されます。修正前もXErrorは切断扱いだったので、悪化ではありません。
- **Mac**：SCANSYNCの再送は `physical()` が呼ばれたときだけ行われます。物理キーの状態を問い合わせない間はstaleのまま残りますが、次に問い合わせた時点で回復するので仕様上は問題ありません。

## Macの実機確認（1082）で確認が必要なこと

ここに挙げるのは実装の欠陥ではなく、実機でしか確かめられない受け入れ確認の項目です。

1. `sendEvent:` のサブクラス化と `objc_msgSendSuper` が実際に動くこと（KeyDown/KeyUp/FlagsChanged）。
2. FlagsChangedで左右のmodifierが正しく判定されること。デバイスごとのビットがないキーボードでの確認も含みます（L2）。
3. Fn、電源、音量のキーが入力として報告されないこと。
4. pipeが詰まった状態で、SCANSYNCからSCANSNAPへの回復が実際に起きること。
5. 純正キーボードと対象キーボードで左右のキーを同時に押したとき。

このほか、Windows・Linuxの実機キーボードでの確認も未確認です。特に両Shiftのkeyup欠落は、SendInputによる受け入れ試験では再現していません。

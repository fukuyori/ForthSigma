ファイルを読み終えたので、結果をまとめます。

# 1170/1171 ZX OS受け入れの最終レビュー（読み取りのみ。編集・実行・ネットワーク接続はしていません）

## High
なし。

## Medium

**1. `docs/ZX_SPECTRUM_AUDIO_FORTH.md` が Linux 再試験の成功を反映しておらず、JSON と食い違っています**
- 100行目は「物理再試験待ち」のままです。一方、`linux_interrupt_retry`（9639–9650行）と `.work/1170-1171/linux-r2-interrupt.json` には、exit 0、`CATCH=-28 handle=0`、`REPLAY-OK handle=0 underruns=0`、`DEPTH=0` と、レモンの確認ＯＫが記録されています。JSON 冒頭の status（8行目）と listening_acceptance の status（8396行目）も、再試験成功を前提に書かれています。
- 87行目「原因特定・修正と再確認は未実施。人の実聴結果も返答待ち」は、92–98行目の修正・Windows 完了の記述と矛盾します。85行目の「物理Ctrl+C後の停止/再再生…は未確認」も Windows 完了後としては古い記述です。
- 1171 を完了にする前に、古い文を書き換えるか削除して、記述を JSON に合わせる必要があります。

**2. `docs/reviews/1170-1171-review-response.md` の最終節が再試験前の状態で止まっています**
- 35行目の「レモンの再開了承までは追加生成音を鳴らさない」で終わっており、次の記録がありません。
  - 再開了承を得たこと
  - r2 の結果（stdout / exit 0 / 実聴ＯＫ）
  - 「物理試行2回のうち成功1回（初回 exit=-2 は保持）」
- このままでは、1171 完了の根拠を説明する記録が残りません。

**3. 完了記録で、Linux の成功が試験用の設定変更の上で得られたことを明示する必要があります**
- r2 は、聞こえない B/C チャネルとノイズの設定（R2–R6）を変えて、待機区間の外での計算時間を減らしています。可聴 PCM が同一であることは独立モデルとの照合（49152frame、hash 一致）で確認されていますが、元の source で観測された物理結果はプロセス終了（exit=-2）だけです。
- `src/host_wait.zig:121/159/167` を見ると、SIGINT handler は NativeScope の開始〜終了の間だけ設定されます。待機の外で Ctrl+C を押すと既定処理で終了する、という説明はコードと一致しています。
- review-response 33行目の「常に捕捉されるとは主張しない」は記載済みです。ただし ZX 文書の完了記述と JSON の status にも、次の3点を書く必要があります。
  - Linux の Ctrl+C 捕捉は押すタイミング次第であること
  - 成功例は試験用の非可聴設定でのものであること
  - 初回失敗時の資源回収はプロセス終了によるもので、cleanup は確認していないこと

## 確認して問題がなかった点
- 初回失敗は `linux-interrupt-first-failed.json` と JSON の `linux_interrupt_first_failed` に別名で保存され、上書きされていません（binary hash は r2 と同じ `28b12e5b…`）。
- `linux-signal-diagnostic.json` は scope に「not physical acceptance」と明記され、JSON の `linux-interrupt-revised-preflight.json` 相当部分にも `physical_acceptance:false` があります。プログラムから注入した診断を物理受け入れの代わりにしている記述はありません。
- r2 の source は preflight の source_setup と一致し、Linux だけで置換していることが supervisor_source に残っています。
- 速度表、7回の測定、native 変更なし、build 来歴（再ビルドなし）、純粋合成コアの計時であって再生を含まないこと、という主張の範囲は一貫しています。
- tasks_snapshot は 1168/1171/1172 とも todo、1168 は effective 50 で、文書の「auto50%」と一致します。Mac 1172 と親 1168 を未完了とする記述もそろっています。

## Low
- `same_pcm_hash_as_previous_audition` の「previous」がどの実聴（Linux 128K の3段階か、元の interrupt 試験か）を指すのか、キー名だけでは分かりません。
- r2 の JSON には実施時刻がなく、stderr は stdout に合流しています（Windows 側の記録も同じ形式）。

## 残る制約（指摘ではありません）
- Linux は WSL2（WSLg/RDPSink）上での確認で、物理 Linux や ALSA 直結は確認していません。
- 物理 Ctrl+C が待機区間の外に当たるとプロセスが終了し、`-28` の CATCH にはなりません。native 側は変更していないので、この制約はそのまま残ります。tque に登録済みかどうかは未確認です。
- 中断されたストリーム側の underrun は close 後なので調べていません。
- 初期送出の修正で解消したのは、今回再現した起動時の供給不足です。任意のホスト負荷で欠落しないことは保証しません。
- Mac 1172 と親 1168 は未完了です。

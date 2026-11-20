レモン、追加レビューの結果です。**範囲を限った 1176 の完了処理を止める High・Medium は、もう残っていません。** ただし M2 は、完了処理のときに実際に直すまでは解消扱いにしません。今回は読むだけで、実行・編集・測定・tque の操作はしていません。ハッシュも計算し直していないので、記録されたハッシュが実ファイルと一致するかは未確認です。

読んだもの：
- `linux-final-claude-review.md`
- `linux-followup-review-input.json`（全体）
- `probe-linux-zero.py`
- `linux-device-checked-zero.json`（新しいゼロ出力の stdout 全体）
- `docs/AUDIO_TARGET_AUDIT.md` と `linux-*.txt`（どちらも grep のみ）

## 前回の指摘ごとの判定

**H1（解消）**
- 新しい stdout は次の 7 行で、ソースの出力文と順番も中身も一致しています。
  `AUDIO?=-1` / `LEFT LOW: about3seconds` / `handle=0 underruns=0 frames=98304` / `RIGHT HIGH: about3seconds` / `handle=0 …98304` / `AUDIO?=-1` / `DEPTH=0`
- 合否判定（`probe-linux-zero.py:43`）は、両方のラベルが 1 回ずつ、`AUDIO?=-1` が 2 回、`frames=98304` が 2 回出ることを条件にしています。stderr が空、exit 0、pactl の成功、pacat の親が sigma であることも条件です。
- 子プロセスの出力は 1 つの一時ファイルに書かせ、終了後にまとめて読んでいます（30・42 行）。前回 1 行欠けた原因の「readline と communicate の混用」は、もう使っていません。
- 欠けた原因の説明は、Linux で切り出して再現した結果（`LEFT_LOW_missing: true`）と、Windows では欠けない結果の両方が記録されていて、筋が通っています。
- 元の記録（`superseded_zero_log.original`、`*-before-logfix.json`）も残っています。
- pacat とのつながりも確認できました。pacat（PID 460）の親 PID は 459 で、テスト用に起動した sigma の PID 459 と一致します。コマンドライン（`pacat --raw … --channels=2 --latency-msec=40`）も記録されています。
- json の `helper_source` と現在の `probe-linux-zero.py` は、目で見比べた範囲では同じ内容です。`helper_sha256_lf`（`4f9b690b…`）は計算し直していないので未確認です。

**M1（解消）**
- `launcher_provenance` では、起動前のハッシュ、実行後のハッシュ、ソースのスナップショットのハッシュが、3 つとも `86e1cb7e…` で一致しています。
- スナップショットの中身は `wsl.exe --exec python3 … interrupt.py linux --play` を起動し、`linux-interrupt-window.pid` を書き出すものです。1176 の記録と矛盾しません。
- 元の欄に Windows 用スクリプトのハッシュが入っている件は、注記で説明されています。

**M2（未解消・完了処理で直す予定）**
- 計画は妥当です。ただし、入力 JSON の中にも食い違いが 1 つあります。`process_check` は「Owned sleep1800 still running pending cleanup」のままですが、`cleanup_verified` は「止めた」と記録しています。完了時にまとめて更新する対象に、これも入れてください。

**M3（解消）**
- 対象範囲を WSL/PulseAudio とする根拠が、記録に明記されています。`AUDIO_TARGET_AUDIT.md:18` の「LinuxはWSL/pacat/PulseAudio/RDPSinkで、Linux実機ALSAの受け入れとは区別する」と、同じ形で完了した 1171 です。
- 確認していないものも `not_claimed` に列挙されているので、範囲は十分に限定されています。

## 新しく見つけた点（Low のみ・完了の妨げにはならない）

- **シンクが RDPSink だという対応付けが間接的です。** 今回のゼロ出力の実行は、最初の 2 回の確認でソケットがなく接続を拒否された後に始まっています。それ以前とは別の WSLg セッションだった可能性があります（※推測です）。このセッションの記録は `シンク: 1` だけで、`pactl list sinks` の結果は取っていません。番号 1 が RDPSink だという記録は、`linux-pulse-ready-session.txt:16` にある以前のセッションのものです。気になる場合は、そのことを注記するだけで足ります。
- **起動の証拠は、作業した側の記述が中心です。** `invocation_evidence` は自己申告で、裏付けになる生成物は `linux-interrupt-window.pid` くらいです。範囲を限った完了処理なら、このままで構いません。
- **interrupt.py のハッシュの扱い。** その後 `interrupt.py` は、OS に応じて起動スクリプトを選ぶように直されています。そのため、現在のファイルのハッシュは、記録された `26441e99…` とは違うはずです（※推測です。未確認）。正式記録の `hash_verification_scope` には、照合する相手は今のファイルではなく、残しておいた元のスナップショットだ、とはっきり書いておくとよいです。

## まとめ

1176 を完了とする前に残っている作業は、M2 の状態の記述を一括で更新することだけです。`process_check` の食い違いも、その中に含めてください。Mac 1177 と親タスク 1173 は todo のまま残す方針で、問題ありません。

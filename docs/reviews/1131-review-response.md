# 1131 Forth音源試作：レビュー評価と採否

2026-11-20。Claude Codeに読み取り専用で依頼した。[初期提案レビュー](1131-design-claude-review.md)、[実装レビュー](1131-final-claude-review.md)、[試験補強後の再レビュー](1131-followup-claude-review.md)を原文で保存し、この文書に判断を分ける。Claude自身は実行・ビルド・測定をしていない。

再レビューはM1/M2とも解決済み、新しいHigh/Mediumなし。以下の実行確認は別途こちらで行った。

## 実装レビューの2件

- M1採用。不正なレジスタを拒否した後の1標本だけでは、誤書込みを見逃す。6配列×4cellの全状態と、各配列の前後1cellずつを、拒否前後で比較する試験へ置換した。12種の不正引数すべてで36cellが一致し、THROW -24とスタック深さ0も確認する。
- M2採用。mockのPCM-WRITEがアドレスを捨てていたため、部分書込み後のポインタ更新を検査できなかった。3回のアドレス差0/10/10byteと、partial/full/write/wait/frameカウンタ1/1/3/2/512を照合する。cleanup自体のTHROWでも一次エラーを保つ/本体成功ならcleanupエラーを返す2試験も追加した。

L1のヘッダ例はPS-DEMO-SETUPを含めた。L2のtimeoutとOPEN busyの-528共用は小さい例の明記された契約として維持し、製品のエラー体系は変えない。L3は倍率のJSON名をmedian_realtime_ratio_at_48000へ改め、余裕率1−t/Tも別に記録する。

実装レビューが「手計算値の試験なし」とした箇所は、レビュー進行中に追加した現在のquarter-turn pulse/triangle/noiseとs16LE端点試験で補った。原文は書き換えず、時点の違いをここに記録する。最終バッファのbyte和は並び替えを検知できないため、checksumの限界を維持する。別の完全byte列比較は順序も含めて照合する。

## 初期レビューの採否

- 採用：NTIMEとCPUTIMEを分け、非正のwall差/負のCPU差を除外。音声を起動しない合成専用processと、無音の実PCM送出を分ける。送出側のpartial/full/wait/underrunとAUDIO?を記録する。時間を測ったprocessでも最終バッファを照合する。
- 状態と計算順は既に実装した独自仕様に固定した。Hz整数からQ24増分へ床除算し、advance-before-output、16bit LFSRを採る。初期レビューのadvance-after-output/15bit LFSR/別レジスタ表は代替案であり、元の仕様の欠陥ではない。[仕様](../PCM_SYNTH_PROTOTYPE.md)と独立Python・手計算値を基準とする。
- 「OPEN直後の実WRITEは必ずcapacity分」という案は採用しない。consumerは同時に進められるため、一般にはその値を保証できない。部分・満杯・期限切れは決定的なmockで強制し、実hostでは受理総数と終了を検査する。
- WAITは最小の空き1frameを待ち、capacity超過を要求しない。CLOSE自体がdiscard/detachを行うため、例外時の冗長なSTOPは追加しない。失敗IDを保持して明示的なPS-CLEANUP再試行を可能にする。3回で必ず回収できる保証は加えない。
- 今回は汎用の合成負荷の最初の子タスク。機種別のイベント表・実機音源・CPUとの同時負荷は1132へ分ける。この結果だけで本体移行を決めない。
- 初期レビューの「時間測定は利用者確認後」「他アプリを止める」は現在の依頼・セッションの測定許可から新たな承認条件を導くものではなく、採用しない。他のアプリは停止していない。
- 初期原文の1124未完了という記述も現状と異なる。保存アプリMac1124はc822e53で完了済み。未完了のPCM Macは1130。

Windows/Linuxの通常/除外構成の実行結果と測定生データは[JSON](../measurements/2026-11-20-pcm-synth.json)。可聴音・Mac実機・機種別の正しさは未確認として残す。

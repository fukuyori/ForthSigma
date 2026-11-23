# Windows表示支援 Claude Codeレビュー対応

2026-11-23。Claude CodeへRead/Glob/Grepのみを許可して依頼。
[初回原文](2026-11-23-windows-display-claude-review.md)、[作業中の追加原文](2026-11-23-windows-display-claude-followup.md)。
どちらも読み取り専用。実行・ビルド・測定はロクが行った。
初回の応答のmodel_usage_since_last_resultはclaude-opus-5-5。

| 指摘 | 対応 |
| --- | --- |
| 初回M1・追加M1：同じサイズではTk切替えの誤りを見逃す | native160×100に対しTk200×120、画像200×100とnativeとのサイズ差をassert。 |
| 初回M2・追加M2：画面倍率と小窓の根拠不足 | DISPLAY-SCALEの分子・分母を記録し、このfixtureのTk倍率1をassert。指定64×40と実サイズの独立caseを追加。最終9項目。 |
| 追加H1：作業中の1326と旧1334 JSONの動作が不一致 | 同じ最終通常実行体で全Windows表示試験を実行し直してJSONを置換。1334の明示的native closeはGFX-WINDOW-CLOSEへ変更し、公開WINDOW-CLOSEのTk選択は17段階で別途検証。文書も現在動作へ統一。 |
| 成功時にwish終了漏れを見逃す | jobのActiveProcessesが0になることを期限付きでassertしてからfinallyの回収。 |
| Python強制終了時の子の残存 | KILL_ON_JOB_CLOSEを設定。 |
| 非公開process._handleへの依存 | OpenProcessでSET_QUOTAとTERMINATEのhandleを取得し、割当後に閉じる。 |
| 保存アプリのSTATE行数 | 保存前・新規起動後とも1行とassert。 |
| VSYNCの可否 | Windowsホストの0/-1を環境依存の記録値とし、特定周期や成功を保証しない。Tkは1300で明示的に偽。 |
| 固定300msの待ち | 合成操作の固定待ちは記録上の制限として保持。遅い環境での偽陰性はあり得る。期限付きプロセス制御はある。 |
| HEADだけではソースを特定できない | working_tree、実行体SHA-256を記録。速度測定は測定時の別実行体を明記。 |
| 古い設計の1334残件表記 | 現在の状況を更新し、1298時点のnative専用表記は過去の記録と明記。 |

Tk close制御1326・未対応フレーム1300・補間未対応1318・状態1295は[追加検証](../WINDOWS_TK_DISPLAY_VALIDATION.md)。
[速度測定](../DRAWING_SPEED_VALIDATION.md)はCPUTIMEの粒度と対象範囲を明示。

## 最終の実装レビューと再確認

[実装レビュー](2026-11-23-windows-display-final-claude-review.md)はHighなし、Medium2件。
M1のclose/closes部分一致は17/19/18バイトのメッセージ長を含む照合へ修正。
M2のkeep=false時の動作は既存Windows・Linux nativeと同じであることをソースで照合し、
保留だけを捨てて窓を閉じない意味をHELP・Forth説明・英日文書へ記載した。
L1の設定通信失敗時にwishを終了する動作も英日文書へ追記した。

[再確認](2026-11-23-windows-display-final-followup.md)ではM1修正とM2の説明・テストの一致を確認。
残存Highなし。残った文書のMedium2件は、速度JSONが先行ビルドのhashで最終実行体と異なることを明示し、
HELP明確化後の5本再実行で全て成功した事実を過去形で記録して対応した。
通常1371成功・25skip、graphics除外1201成功・191skip。文書チェック指摘0、実辞書・EKEYS35値・文書例28件・単独例424件が成功。
この検証はロクが実行し、Claude自身の実行確認ではない。



[画像と文書残件の限定レビュー](2026-11-23-windows-alpha-visual-claude-review.md)はHigh/Mediumなし。
アルファ画像の全画素照合に偽陽性となる欠陥を見つけず、前回の文書Medium2件も指定範囲で解消を確認。
Claudeの読了範囲は各原文の末尾に明記されている。全ファイルを一度に再レビューしたという意味ではない。
最終通常実行体の現物hashを、表示支援5本と1310のJSON6本で再照合し、すべて同一だった。

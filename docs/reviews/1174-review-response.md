# 1174 S-DSPレビュー対応

設計・実装・最終の原文と本評価を分けて保存する。Claudeは読み取りのみで、実行/実機確認をしたレビューではない。

## 設計

[設計レビュー原文](1174-design-claude-review.md)はHighなし、Medium9件。M1のGauss係数対応と遅れ、M2の16個目消費内でのEND/loop/header latch、M3のKON pollを含む5frame delay、M4の更新前ENVで出力/publish→ENV更新→pitch消費を採用した。M5のnoise bit0 XOR bit1を明記しvoice前に更新。M6のMVOL/EVOL/EFB積は全てfloor後s16 wrap。M7の即時/read全引数先行検査、M8の負数/overflow/未処理件数と優先順、M9のflush時点を定めた。

容量と逆順が重なる場合は既存queue方式に合わせ-528を先とし、RENDER0/SAMPLEはflushしない。いずれも仕様と実検査を揃えた。frame countはCYCLE/32以下で、公開APIのMAX制約内ではoverflowしないため、別のmod30720 counterは追加しなかった。BRR wrap、PMON上限、rate offset、GAIN隠れ値、ESA/ENDX slot等の宣言差分は明記し、実機の確認済み事項とは扱わない。

## 実装

[実装レビュー原文](1174-implementation-claude-review.md)はHighなし、Medium2件。レビュー開始後に検査を追加しており、原文の読取snapshotと現在の検査に時間差がある。

M1: Gaussは独立したtoken抽出で保存HTMLから再取得し、source HTML hash・全512値・pinned little-endian numeric hashを照合する `--reference-doc` を追加した。8構成の本実行でこのoptionを用いる。defaultでもpin/単調性/4係数和と全256位相・正負極値・known overflowを検査する。外部数値という共有dataと、独立したBRR rational predictor/heap queue/Python modelを区別する。

M2: 全PCM/266semantic state/全64KiB ARAMの一括/分割照合へ、nonloop end（noise中も進行）、pitch>=4096/上位mask/PMON clamp、FIR負値/先頭7項wrap、echoの16bit wrapとBRR/DIR alias、ADSR/GAIN mode、DIV17の相対RENDERを追加した。oracleの必要分岐を実際に通ることもassertする。状態並びの共通化は照合のserialize形式であり、算術はBRRの分数係数など別表現を使う。

手計算vectorはBRR +7FFF→-1/-8000→0、MVOL/EVOL/EFB=-128、8tapの単発応答、EDL latch境界、noise最初20値、KON delay、header latch/loop/16bit wordに追加した。全128register×256byte、全65536ARAM、全32rate、317ENV case、error時の全state/ARAM/queue不変、容量/回収/優先順、MAX成功/失敗、-9途中進行も検査する。streamはstereo4byte offset/prime/継続/zero/cleanup等19RAM caseで、生成音は装置へ送らない。

## 制限と残る作業

宣言したsample境界モデルの検証であり、実機の微細DSP slot/ROM互換性を完了した主張ではない。1175/1176/1177の速度・採否・生成音の実聴は未実施。自動nativeテストはFALSEのゼロ送出だけで、最初にLinux AUDIO?=0だった回を参考に残し、接続保持後AUDIO?=-1の実経路を再確認した。速度測定は開始確認後だけ行う。Mac1177が終わるまで親1173を未完了に維持する。

## 最終評価

[最終レビュー原文](1174-final-claude-review.md)はHigh/Mediumなし。M1の条件である `--reference-doc` は8構成の本実行ですべて使用し、各reportの先頭caseに同じ保存HTML hashがあることをロクが確認した。Reviewerは実行していない。

Lowも対応し、HTML hashの対象を.htmにも拡張、同tick予定→即時→後から予定の順と未来tick不正writeの原子性を追加、統合demo caseはForthのSD-DEMO-SETUP自体を独立Pythonと直接照合するよう変更した。原文レビューは変更していない。追加後に8構成×19モデル群、音声有効6構成×19RAM caseを再実行し成功、結果/現行ソース指紋を保存した。

1174を完了、1175/1176/1177は未完了。親1173はMac1177も含め未完了・auto25%。

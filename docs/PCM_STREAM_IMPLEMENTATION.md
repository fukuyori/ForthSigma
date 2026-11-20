# PCMストリーム：内部実装と検証（998 / 1125・1126）

2026-11-20、基点main `6512916`、Zig 0.17.1。1125の設計と1126の内部コンポーネントを実装した記録。**PCMの公開語・ホストの停止回収はまだ実装しておらず、アプリからPCMを使える状態ではない。** 全体998は未完了。

[採用設計](PCM_STREAM_DESIGN.md)、[初期提案](PCM_STREAM_DESIGN_PROPOSAL.md)、[ソース/API照合](PCM_STREAM_SOURCE_AUDIT.md)、[レビュー評価](reviews/998-review-response.md)、[原データ・コマンド・ソース指紋](measurements/2026-11-20-pcm-internal.json)。

## 実装した範囲

- `src/core/sound_stream.zig`：storageを借りるSPSC ring、complete-frame copy、partial/full、u32添字wrap、符号付き非整列s16LEのmono/stereo入力。
- 整数位相によるsample/holdと未着のskip保持。WRITEの区切りだけでdownsample位置が変わらず、実際にemptyを出したら位相を再開する。anti-alias filterは付けていない。
- held frameを含むQUEUED、最初の入力前を除くunderrun episode、意図的drainの抑制、再生再開時のconsumer状態初期化。
- 32bit atomicのControl mailbox、遅れたack、古い完了の保持、最終serialのdetach予約と枯渇拒否。render境界で旧参照を終えてからackする。
- `sound_engine.Engine.render`へ任意のPCM接続を追加。従来filter/gain後にs16 PCMを飽和加算する。既存のPLAY/MOD等のresetはPCMを暗黙に停止しない。
- 容量の公開検査helper：40ms..1s、2の冪、256..65536frames。内部の小さいringを使う試験と公開の容量制限を区別する。

Stream/Frameの実storageはcallerが保持する。今回hostはまだ確保/公開しておらず、通常の実行体からPCMへ接続する入口もない。既存sound_pcmのappend-only poolには書き込まない。ForthのBuiltin・画像ABI・公開語一覧は変更していない。

## レビューと修正

Claude Codeへ設計・内部リング・限定再レビュー2回をRead/Glob/Grepのみで依頼し、原文を別保存した。設計ではhost所有と非永続資源、ms/THROW、容量と画像復元busyを確定。完全復元applyでの自動abandon案は採用せず、明示CLOSE後に復元する設計とした。hostのtimeoutを回収成功として扱わない。

リングの指摘は、未着入力を越えたdownsampleのskip消失、後続ackで古いcompletedがfalseになる点、drain尾部のunderrun誤計上を修正した。最終限定レビューは対象に高・中の具体的欠陥なし。レビューは実機音声やテスト実行の証拠ではない。

## 検証結果

| 対象 | 結果 |
| --- | --- |
| Windows ReleaseFast core | 1113成功・10除外、失敗0 |
| Windows Debug core / host | 1113成功・10除外 / 151成功・12除外、失敗0 |
| Linux musl Debug core / host（WSL） | 1113成功・10除外 / 155成功・15除外、失敗0 |
| Windows graphics/audio/extensionを全部除外 | core933成功・190除外 / host149成功・12除外、失敗0 |
| Windows `zig build test` | 成功。thumb-freestanding-eabi/Cortex-M0+のcompileとruntime確認を含む |
| Mac aarch64 core-check / host-check | クロスコンパイル成功。実行していない |

追加16件は、full/partial/overflow/u32 wrap、8k..192kの比、非整列stereo、44100→48000の整数境界、producer/consumer実2thread（unity10万frameと非unity44100入力/48000出力）、mailbox未ack/古い完了/枯渇/detach後再利用、drain抑制解除、engine混合を確認する。並行試験は実時間の音切れや装置latencyの測定ではない。

最初の全体テストでは64bit atomicがCortex-M0+でcompileできなかった。counter/制御serialをu32にし、飽和/枯渇を明示して再実行し成功した。修正前の失敗ログと修正後の成功ログを`.work/998`へ保持した。

実辞書1805項目・HELP1591項目・文書例28件・個別例401件も照合し、check-docsは指摘0。通常ReleaseFast実行体で既存の保存アプリ公開試験を再実行し、引数・破損画像・再保存・自己別名・readonly・日本語path等の回帰がないことを確認した。実機音声の確認ではない。

## 再実行

```powershell
zig build test
zig build core-check host-check --prefix .work/998/windows-final
.work/998/windows-final/core-tests/x86_64-windows/test.exe
.work/998/windows-final/host-tests/x86_64-windows/test.exe
```

Linuxは`-Dtarget=x86_64-linux-musl`でcore-check/host-checkを作り、WSL上で生成したtestを実際に実行した。Macは`-Dtarget=aarch64-macos`によるcompileのみ。元の保存アプリ1124のMac実機は未確認のまま保持する。

## 続く作業

1. **1127 host寿命**：join可能な音thread、装置待ちの終了、初期化失敗rollback、Pulse阻害時の失敗/領域保持、pipe子回収。現行host_audioはdetach/無限消費のままで、この内部実装だけでは解決していない。
2. **1128 公開語・所有・画像**：hostに256KiB以下の再利用storageを持ち、AUDIO語を登録。ms期限、中断、closing再試行、明示close、完全restore busyとappend保持、英日HELPを実装する。
3. **1129 Windows/Linux、1130 Mac実機**：生成アプリ、音のcapture/実聴、停止/異常/中断、fd/handle/thread、語群除外と文書。Mac実機は別項目のまま残す。

999の音源合成はPCM公開基盤が使えるようになってから実測する。今回のring試験をもって音源合成の速度や3OS音声受け入れまで完了とはしない。

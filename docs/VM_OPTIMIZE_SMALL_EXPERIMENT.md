# small最適化の独立比較（#841）

2026-11-16。Zig 0.17.0、x86_64-windows-gnu / x86_64-linux-muslでfastとsmallを比較した。CPU baseline、全通常機能、strip=trueを固定し、LTOは追加していない。rootのbuild.zig・VMソース・配布設定は変更していない。**サイズは約25〜26%縮小したが、確認したLinux整数演算のCPU時間は約2.38倍へ増加した。既存速度目標未達のため、速度改善策としては不採用。本体はfastの採用済み版を維持する。**

## ビルド・サイズ（#842）

| 対象 | fast | small | 増減 |
| --- | --- | --- | --- |
| Windows GNU | 1,809,408 bytes | 1,333,248 bytes | −26.316% |
| Linux musl | 1,891,456 bytes | 1,418,496 bytes | −25.005% |

fastはそれぞれ採用済み379d… / bdb6…とSHA一致。build設定・forth.zig・defs・image_format・VERSIONもrootとのSHA一致を記録した。これは5ファイルの照合であり、全入力の同一性の主根拠はfast実行体が従来の採用済みSHAを再現したことである。機能無効化で縮めたものではない。追加CPU命令の指定や容量の削減はしていない。サイズの減少は速度改善を意味しない。

## 検証

smallのWindows通常構成でbuild testは21/21ステップ成功、core 1,011成功/5skip、host 59成功/5skip（計1,070成功/10skip）。Linux smallはWindowsからのクロス親コマンドexit1を保持し、生成ELF2本をWSLで実行。core 1,011/5skip、host 63/1skip、各exit0。build.zigのCLI9条件もsmall実行体で成功した。Fastのunit testは今回再実行していない。

各OSで通常8カーネル×fast/smallの32実行を行い、stdout・stderr・DEPTH=0が一致。short smokeであり時間比較ではない。

各OS・各modeで同じSMALL-IMAGE-CHECK定義をSAVEし、同じOSのfast/small双方でLOAD-DICTIONARYして7/DEPTH0を確認。計4SAVE・8LOAD、SEE出力も各OS内で一致した。画像SHAはmode間で異なり、その原因は未調査。byte同一とは要求していない。画像サイズと生byte差分位置を測定JSONへ追加したが、差分の意味の解読までは行っていない。1定義のプローブで、全画像型や別OS間の互換性を保証しない。SAVESYSやinstallerは作っていない。

初回の画像ハーネスはSAVEをS-string引数と誤解し、SAVEが後続BYEをfilenameとして読んだため期待ファイルがなかった。既存check-images.pyの構文を確認し、SAVE filename / LOAD-DICTIONARY filenameへ訂正。生成されたrootのBYEファイルは今回作成されたもので、workspace内の.work証拠へ移動しSHAを記録した。正しい構文で全実行を確認した。初回スクリプトを保存し、アプリの互換性失敗として扱わない。

他の機能無効構成・他target・表示付き操作・実デバイス受入は未実行。[ビルド/テスト/出力/画像の全記録](measurements/2026-11-16-optimize-small-validation.json)、[Linux CLI9件](measurements/2026-11-16-small-linux-cli.json)。

## 速度の事前計画（#843）

Linux整数演算1条件を先に評価する。baseline-only 100M pilotから約6秒のNを固定し、A/Aは各5標本×2群、各実行体warmup1回を除外。最小中央値5秒・最大δ2%以内なら、候補比較各7標本×2群へ進む。先行順を交互にし群2で反転、全標本を保存する。校正未達では候補を測らず、再試行しない。

既存のLinux整数演算10%以上短縮かつ2δ超を両群で満たすかを予備判定とする。満たさなければ他の時間比較は打切り、通っても1項目だけで採用しない。Windowsの時間、LOOP・他normal/CATCHの時間、追加構成の回帰は残件。2群は同じセッションで連続する別標本群で、独立環境や信頼区間ではない。build/回帰/profileの実行と計時を重ねない運用とし、外乱全般を強制排除したとは扱わない。

root実行体は維持し、凍結済みprotocol/run.pyを変更せずに実行した。結果は以下に記録する。


## Linux整数演算の結果と採否

baseline-only pilot（100M、約0.776秒）から773,361,863反復を固定した。A/Aの最小中央値5,716.365 ms、最大δ0.231535%で事前校正条件を通過。候補比較は各7標本×2群で、warmup各1回を除外した。

| 系列 | CPU時間の変化 | small/fastの時間比 |
| --- | --- | --- |
| 1 | ＋138.383% | 2.38383倍 |
| 2 | ＋137.329% | 2.37329倍 |

両群でCPU時間が増えた観測結果であり、10%短縮目標に届かない。凍結済みscriptのpassed=falseと、上記正の変化率を区別して保存し、速度改善策として不採用と判断した。結果を見て新たな合格/悪化率を設定していない。既存計画の他normal項目のmax(3%,2δ)は、この主目標の判定に置き換えていない。サイズ目的で採用する判断も今回行わない。

予定どおり他の時間比較を打切った。Windowsの時間、LOOP、他normal/CATCHの時間は未測定。機能無効構成等の追加回帰も未実施。Smallが全用途で遅いとは結論しない。遅くなった機序・コード配置差等も今回特定していない。[全標本・凍結入力・集計](measurements/2026-11-16-optimize-small-performance.json)。

2δは約0.463%で、今回10%目標より十分小さい。δはA/A段階の中央値差であり、A/B中のドリフトの上限ではなく、事後A/Aによる再確認もしていない。先行順は群内3:2/4:3、群2で反転して全体では均衡するが、群内の偏りは残る。Linux論理CPU0の指定で、ホスト負荷は記録していない。

48測定標本・8warmup・pilotを保存し、再試行なし。これは実行記録に基づく報告で、上書き可能な成果物だけから独立に検証できるものではない。計数結果は2実行体・1条件に限定する。

## レビューへの対応

[レビュー原文](VM_OPTIMIZE_SMALL_CLAUDE_REVIEW.md)は計時未完了時点の方法・ビルド・回帰を確認したもので、速度数値はレビュー後に確定・再集計した。凍結protocol/scriptは変更していない。未達が常に同等/悪化を意味するとは扱わず、今回は正の変化率による観測上の悪化と目標未達を分けて記録した。

初回画像スクリプトはwindows-fast（379d…）の1回目で停止しており、そのsourceから作成元を特定できる。移動先に保持されたcreation時刻もJSONへ追加した。移動前の未追跡確認や初回コマンドのstdout/stderrを独立したファイルには保存していなかったことを明記する。現在rootにBYEはない。

Linux CLI9件は配置済みsmallと同じSHA6bd1…で実行した。ELFの直接実行は引数なしで、build runnerのseedは引き継いでいない。smallはCソース最適化にも影響し得るため、浮動小数の意味確認はsmoke1件ではなくcore unit testの範囲で扱う。freestanding objectは元から固定smallで、今回のfast/small比較対象ではない。[対応記録](VM_OPTIMIZE_SMALL_REVIEW_RESPONSE.md)。

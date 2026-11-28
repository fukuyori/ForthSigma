# Forth音源の試作と測定（999 / 1131）

2026-11-20、基点main `9d1c528`、Zig 0.17.1。Mac1130を残して進める指示に従い、999の最初の子1131として、独自のForth合成例とPCM送出例を作った。特定機種の音源を再現したものではなく、999全体と機種別の実測・採否1132は未完了。今回の差分は未コミット。

## 配置と実行

- [pcm-synth.fs](../tests/audio/pcm-synth.fs)：AUDIOにもhostにも依存しない合成。読み込むだけでは音声を起動しない。
- [pcm-synth-play.fs](../tests/audio/pcm-synth-play.fs)：明示的にPCMで送る。読み込むだけでは再生しない。
- [verify-pcm-synth.py](../tests/scripts/verify-pcm-synth.py)：独立したPython照合、境界・送出例の失敗回復、任意の測定。

リポジトリ直下から、約1秒分を合成して無音を送る例：

```powershell
zig-out/bin/sigma tests/audio/pcm-synth-play.fs -e "PS-DEMO-SETUP 96 FALSE PS-STREAM BYE"
python tests/scripts/verify-pcm-synth.py zig-out/bin/sigma --benchmark
```

Windowsではsigma.exeも使用可。TRUEを明示した場合だけ合成波形を送る。自動試験はすべてFALSEで、合成後のバッファを0で埋めてからPCM-WRITEへ渡した。生成波形の可聴確認はしていない。

## 試作の仕様

48kHz、mono s16LE、64bit cell。4声を整数で合成し、各声のピークを8191以下に制限するため、和は-32764..32764でs16に収まる。全声の位相はQ24、増分はfloor(hz×2^24/48000)。毎標本、位相を先に進め、2^24で剰余を取り、その位相から出力する。無音・gain0でも内部の位相とnoise状態は進む。

`PS-REG! ( value voice register -- )`はvoice 0..3を指定する。全引数を検査してから1項目だけを書き換え、位相やnoiseをリセットしない。不正値は-24をTHROWする。

| register | 内容 | 範囲 |
| --- | --- | --- |
| 0 | kind：0無音、1pulse、2triangle、3noise | 0..3 |
| 1 | 整数Hz | 0..23999 |
| 2 | ピークgain | 0..8191 |
| 3 | pulseのduty（256分率） | 1..255 |

PS-RESETはkind/Hz/gain/位相を0、dutyを128、noiseを1にする。pulseはphase < duty×65536で+gain、それ以外で-gain。triangleはphase>>14をxとし、x<512なら128x−32768、それ以外は98304−128xをgain倍して32768で床除算する。noiseは位相の周回ごとに16bit状態nを`(n>>1) OR (((n XOR (n>>1)) AND 1)<<15)`へ更新し、下位bitの1/0で+gain/−gainを選ぶ。実チップの周期・特性やアンチエイリアス性能を保証しない。

`PS-RENDER ( addr frames -- )`は連続したframes×2byteへs16LEを書き、負のframesを-24で拒否する。0ならメモリへ触れない。呼出し側は有効な出力領域を確保する。低水準のPS-VOICE等はこの例の内部処理で、再入や複数の同時合成は扱わない。

PS-STREAMは512frameずつ合成し、capacity4096のPCMへ送る。部分書込み後はwritten×2byteだけアドレスを進め、未送出分を再試行する。満杯時は空き1frameを最大1000ms待つ。期限切れは-528で打ち切る。全体をCATCHで囲み、成功・失敗ともCLOSEを試す。CLOSEは既にdiscard/detachを含む。失敗時はIDをPS-HANDLEに残し、`PS-CLEANUP ( -- ior )`で明示的に再試行できる。cleanup自体がTHROWしても、bodyの一次エラーがあればそちらを保持する。

## 確認結果

通常版とdebug/graphics/extension除外版をWindows/Linux各々で実行し、各18検査群、失敗0。純粋な合成例はaudio/graphics/extension除外版でも実行できた。実行体は1129で使ったReleaseFast/cpu=baseline/strip=trueのWindows GNU/Linux musl版を再利用し、本体ソースのLF正規化SHA256が基点9d1c528と一致することを確認した。OS/バイナリ/ソース指紋と全結果は[JSON](measurements/2026-11-20-pcm-synth.json)。

- 手計算した1/4周のpulse・triangle・noise標本、およびs16LEの-32768/32767を照合。
- 独立したPythonの計算と3設定×8193framesを照合。1回での合成と1/511/7681frameへの分割が同じ。途中の周波数・gain・kind変更でも出力が一致。
- 12種の不正レジスタ引数、負のframes、0frames、スタック深さ、拒否前後の全24状態cellと配列の前後12cellが変化しないことを確認。
- 専用processのmockで部分書込み→満杯→残り、待機timeout、close失敗後の再試行、一次エラー優先、OPEN busy時に他所有者をcloseしないことを確認。部分書込みのアドレス差0/10/10byteと各カウンタも直接照合した。実hostではconsumerが並行するため、最初のWRITEが必ずcapacityだけを返すとは仮定しない。
- 実PCMへ無音を32block、0blockと再open、別途96blockを渡し、受理総数と終了を照合。

## 合成だけの速度

各processで1000blockのwarm-upを1回行い、次の1000block（512000frames）を7個の新しいprocessで測った。合成・Forth dispatch/loop・s16LE格納を含み、音声host、PCM-WRITE/WAIT、起動と終了は含まない。NTIMEの差とCPUTIMEのprocess全体のCPU差を記録し、最後の512frameのbyte和140426をPythonと照合した。非正の経過時間・負のCPU差は不採用にする規則で、今回の除外は0回。時計の正方向の跳躍はこの検査だけでは検出できない。

| 対象 | 中央値 ns/frame | 48kHzに対する倍率 | 7回の経過時間範囲 |
| --- | --- | --- | --- |
| windows | 615.96 | 33.82倍 | 311.458..393.040 ms |
| linux | 496.73 | 41.94倍 | 252.234..265.727 ms |

倍率は「この単純な4声の合成」についての値。レジスタ書込みの時刻管理、CPUエミュレーション、実機固有のenvelope/sweep/DMC/DMA/filter/割込み等の負荷は含まない。NES/SID/Paulaの実時間動作や、本体への移行が不要という判断には使わない。

## エンジン消費に合わせた無音送出

96block、49152frames（入力換算1.024秒分）を送った各1回の値。外側の単調時計で新規process全体を測り、起動、合成後の無音化、host開始、書込み・待機・engine drain・close・終了を含む。装置の再生完了や可聴遅延ではない。fullは受理0、partialは0より大きく要求未満を返した回数。

| 対象 | 全体 秒 | WRITE | partial | full | WAIT | underrun | AUDIO? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| windows | 1.141 | 173 | 75 | 2 | 77 | 2 | -1 |
| linux | 1.660 | 282 | 185 | 1 | 186 | 0 | 0 |
| windows-no-debug | 1.127 | 152 | 54 | 2 | 56 | 1 | -1 |
| linux-no-debug | 1.663 | 281 | 184 | 1 | 185 | 0 | 0 |

Windows通常版はunderrunを2回、除外版は1回記録した。隠さず原データに残すが、装置で音切れを聞いた意味ではない。LinuxはAUDIO?=0の無音消費で、装置動作を確認したことにはならない。backend固有名は測っていない。この送出例はWAIT前に必要な空きがあればポーリングで戻るため、待機回数そのものを睡眠回数とは扱わない。

## レビューと残件

[初期レビュー原文](reviews/1131-design-claude-review.md)と[採否](reviews/1131-review-response.md)を分ける。実装レビューのMedium試験不足2件を補強し、[再レビュー](reviews/1131-followup-claude-review.md)で解決・新しいHigh/Mediumなしを確認した。1131完了、999は50%。

999の直接依存は1064と1129とし、Mac1130の未完了で先行試作を止めない。1132では対象機種・再現範囲を定めたForth音源の負荷を測り、その結果から本体移行の採否を決める。今回の試作だけでは999を完了にしない。Mac実機、生成波形の可聴確認、機種別の正確さは未確認。コミット・プッシュは今回行っていない。

## 合成中のCtrl+C（2026-11-20追記）

[pcm-synth-play.fs](../tests/audio/pcm-synth-play.fs)とNES/SID/Paulaの再生例は、512frameの合成とPCM-WAITを交互に行う。PCM-WAIT中のCtrl+Cは-28で捕捉され、例のCATCHと後始末でストリームを閉じる。合成中に届いた場合は、確認点のない計算として既存の中断規則（[利用者マニュアル](USER_MANUAL.ja.md)）どおりOSがプロセスを終了させ、後始末は保証しない。MacのNES例では300blockの3.18秒中1.02秒が合成で、無作為な時刻のSIGINT20回のうち7回が終了となった。全機能版（extensionとdebugを含む）では、合成の呼出しをEXEC-LIMITED（予算0）で包めば合成中のCtrl+Cも-28で捕捉できる。ただし実行制御の記録どおり包んだ中の計算は約2.8倍遅くなり、Macでの試算ではSIDデモが約1.3倍、Windowsでは約0.9倍と実時間を下回るため、例には組み込まない（2026-11-20に試作し、全機能版で20回中20回-28を確認した後に取り消した）。

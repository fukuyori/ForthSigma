# レトロPCエミュレータ向け拡張の対応方法

## SNES Windows/Linux完了・Mac1177残し、次はApple IIの範囲確認（2026-11-20）

Linux1176は左低音→右高音と物理Ctrl+C停止/低音再再生をレモンが確認。CATCH=-28/handle0/accepted155136、replay98304/underrun0/stack0/code0/timeoutなし。Linux4構成・通常6負荷の速度/サイズも記録済み。従来同様のUbuntu26.04.1/WSL2→pacat/PulseAudio/WSLg範囲で1176完了。physical Linux/direct ALSAの合格ではない。[仕様/結果](SNES_DSP_AUDIO_FORTH.md)、[全結果](measurements/2026-11-20-snes-dsp-os-acceptance.json)、[追レビュー](reviews/1176-linux-followup-claude-review.md)。

最初の無音補助ログのLEFT行欠落は、POSIXでreadlineとcommunicateを混ぜた取り込みの欠落を再現し、元ログを残した。全量ファイル回収の無音機能再試験で両ラベル/前後AUDIO?=-1/全統計を確認し、pacatの親がSigmaであることも記録。音源本体/実行体を直したのではなく記録補助だけを修正。Linuxlauncher実行前後とsnapshotのhashを補い、latest statusも統一した。追レビューはこれらを踏まえblocking High/Mediumなし（状態更新条件を実施済み）。

Sigma/pacat残留なし、owned WSL sleep1800はPID310とcmdline照合後にSIGTERMし、Windows controller29088退出を確認。追加のpersistent保持用processは起動していない。旧actual-run helper snapshotと後のmetadata修正版を区別する。

1174/1183/1175/1176完了、Mac1177と親1173は未完了auto80%。Windows初回連続試験の未合格・仮想既定出力/物理機器未同定の制限も保持する。次の1179は対象モデル/追加音源を先に利用者と確定する。提案は初代Apple II（NTSC）の内蔵speakerを先行し、MockingboardとIIgs DOCを別扱いとすること。現時点でApple II実装には未着手、承認済み仕様ではない。cached RedbookのC030/PEEK toggle資料と現task1178/1179を確認した。検証記録作成時点では未コミットだった。利用者からコミット/プッシュの指示を受領し、公開結果はGitのHEAD/originで確認する。一時helperは.work。以下は各時点の履歴。


## SNES Linuxの左右音確認ＯＫ・物理Ctrl+C開始確認待ち（2026-11-20）

Linux/WSLの左低音→右高音は各98304frame/handle0/underrun0/stack0/code0で完了し、レモンからＯＫ。人の確認として記録した。次は了承後.work/1175-1176/launch-linux-interrupt.ps1で新しいSNES Linux Ctrl+C test窓を開く。高音を約1秒聴いて、その窓でCtrl+Cを1回。500ms後の低音約3秒、CATCH=-28/handle0・replay98304/underrun0/stack0/code0を確認する。

Linux固有の両tone全PCM/state/ARAM、両OS RAM模擬control、全source/silent gateと--check-readyは成功。実際のWSL物理信号は未検証。共有supervisorはレビュー済み、Win actual-run snapshotと、後のLinux tone-proof選択対応版を区別して保存した。[全記録](measurements/2026-11-20-snes-dsp-os-acceptance.json)。Windows1175完了、Linux1176/Mac1177と親1173（auto60%）は未完了。owned WSL sleep1800はLinux後に本人確認して回収する。追加速度測定/コミット/プッシュなし。以下は各時点の履歴。


## SNES Windows1175完了・Linux1176の実聴開始確認待ち（2026-11-20）

Windows物理Ctrl+CはCATCH=-28/handle0/accepted81856、500ms後の低音98304frameはhandle0/underrun0/stack0/code0、レモンからＯＫ。終了後Sigma残留なし。最終ClaudeはHigh0/Medium3で、状態表記を修正し、次の制限を明記して宣言Windows範囲を閉じる評価に従い1175完了。[結果と範囲](SNES_DSP_AUDIO_FORTH.md)、[レビュー](reviews/1175-windows-final-claude-review.md)、[全記録](measurements/2026-11-20-snes-dsp-os-acceptance.json)。

確認は物理WindowsホストのwaveOut既定経路。試験後defaultはCABLE Input (VB-Audio Virtual Cable)、後段物理機器と再生時open handleのendpointは未同定。初回連続ステレオの未合格は保存し、連続試験が再合格したとは言わない。右初回/元の左単独再試験・raw参照・物理停止/再再生はそれぞれ確認済み。原因特定や本体/設定修正による恒久解決の主張はしない。

Linuxは初回Pulse接続拒否とsocketなしを記録。owned WSL接続保持中にsocket生成とRDPSink接続成功を確認し、追加の同一process無音送出は前後AUDIO?=-1/2段階98304frame/underrun0/handle0/stack0/code0。実pacat sink inputを記録し、Ubuntu26.04.1/WSL2→PulseAudio17/RDPSinkと識別。generated Linux音と物理Ctrl+Cは未実施。了承後 `wsl --exec python3 .work/1175-1176/acceptance.py linux --play` で左低音→右高音各約3秒を確認する。両gateは成功。owned sleep1800はPID記録済みで、Linux完了後に本人確認して回収。1176/1177と親1173（auto60%）は未完了。追加速度測定/コミット/プッシュなし。一時helperは.work。以下は各時点の履歴。


## SNES左低音の再確認ＯＫ・Windows物理Ctrl+C準備（2026-11-20）

元と同じSNES左低音の単独再試験はtechnical checks成功後にレモンからＯＫ。初回「右しか聞こえなかった」の失敗を保持し、原因特定やcode/設定修正による解決とは主張しない。右音は初回、左音は単独再試験で確認された記録として扱う。

次は了承後.work/1175-1176/launch-windows-interrupt.ps1で可視SNES Ctrl+C test窓を開く。高音を約1秒聴いてCtrl+Cを1回。CATCH=-28/handle0、500ms後に低音約3秒、再生handle0/underrun0/98304frame/stack0/code0を確認する。高音は最長30秒（1875block）で終了。全ソース/無音試験gate、両音の全PCM/state/ARAMとRAM模擬中断/replayを検証済みだが、実際の物理試験は未実施。[全準備](measurements/2026-11-20-snes-dsp-os-acceptance.json)のlistening_preparation.physical_interrupt_preparation。ClaudeレビューはHighなし・Medium1件を反映済み。両toneとRAM検証の一致を起動条件にし、--check-ready成功。親deadline45秒、accepted-frame表示、実Python.exe解決、PowerShell parser確認も追加した。1175/1176/1177と親1173は未完了。以下は各時点の履歴。


## SNES raw左右確認ＯＫ・元の左低音を単独再確認待ち（2026-11-20）

raw440Hzの左→右→両側（各2秒）はtechnical checks全成功後にレモンからＯＫ。試聴確認返答として記録した。元のSNES左低音が聞こえなかった報告は消さず、原因は未特定のまま。

次は元と同じ451/16/0・192block/98304frame・同音量の左低音のみを、1秒の予告後に約3秒出す。元の全PCM/state/ARAM proofと送出RAM captureのhashを照合し、無音実装置ではhandle0/underrun0/98304frame・stack0/code0。新helperは.work/1175-1176/left-recheck.pyで、了承後だけ--play実行する。[全記録](measurements/2026-11-20-snes-dsp-os-acceptance.json)のwindows_left_channel_investigation。生成音の再確認は未実施、設定/本体/実行体の変更なし。1175/1176/1177と親1173は未完了。以下は各時点の履歴。


## SNES Windows左側の実聴未合格・同一周波数で切り分け（2026-11-20）

レモンから「右しか聞こえなかった」と報告。Windows1175を完了にせず、左右実聴は未合格で保存した。技術上のhandle0/underrun0/code0を、人の確認成功として扱わない。

SD-SENDがPCM-WRITEへ渡す全98304frameをRAM callbackで捕捉し、独立PythonのPCMと全byte一致。左音は左98231非ゼロ/peak849・右全ゼロ、右音は左全ゼロ・右98245非ゼロ/peak849。ただし実装置出力の録音ではなく、原因は未特定。音の高さとchannelを分けるため、S-DSPの合成を通さない同じ440Hz/peak849のraw PCMを左→右→両側各2秒で出すテストを準備。全入力byteの照合、S-DSP frame0、実装置のゼロ送出3段階handle0/underrun0/64000frame・stack0/code0、--check-ready成功。[全記録](measurements/2026-11-20-snes-dsp-os-acceptance.json)のwindows_left_channel_investigation。

了承後だけ `python .work/1175-1176/channel-check.py --play` を実行する。切り分け音はまだ再生していない。prodコード/設定/実行体を変更せず、追加の速度測定もしていない。Claudeへ狭い範囲の確認を依頼済み。1175/1176/1177と親1173は未完了。以下は各時点の履歴。


## SNES Windows実聴準備済み（2026-11-20）

次は左だけの低音→500ms間隔→右だけの高音を各98304frame（約3.072秒）確認する。共通setupとnative PCM/266state/queue2/fullARAMを独立Pythonで両OS照合し、反対側channel全ゼロも確認。両OSは同じfixtureのFALSE送出のみ実装置で実行し、各handle0/underrun0/98304frame、DEPTH0/code0。生成音の実聴はまだ行っていない。[準備ソース/全記録](measurements/2026-11-20-snes-dsp-os-acceptance.json)のlistening_preparation。

一時helperは.work/1175-1176。了承後の実行は `python .work/1175-1176/acceptance.py windows --play`。物理Ctrl+C試験は準備のみで、RAM内模擬THROWによるcleanup/replayの両OS検査は物理合格に数えない。実際には別の可視テスト窓で約1秒後Ctrl+Cを1回押して低音再生を確認する予定。1175/1176/1177と親1173は未完了。追加の速度測定・コミット/プッシュはしていない。以下は各時点の履歴。


Claude準備レビューのMedium3件（全ソースの固定、無音実行の前提化、逐次表示）を反映し、両OSの--check-readyも成功。peak<=2048。レビュー原文とこちらの修正検証を区別して記録した。

## SNES native速度測定済み・次はOS実聴/物理中断（2026-11-20）

レモンの新たなＯＫ後、検証済みの通常版をWindows→WSL/Linuxで6負荷各16384frame×7回測定。全回の全PCM/266state/queue2/fullARAM、初期ARAM reset/前状態/A5とForth版との一致を確認し、7値の中央値も再計算した。[全値と採否](measurements/2026-11-20-snes-dsp-os-acceptance.json)のnative_candidate_timings、[結果表](SNES_DSP_AUDIO_FORTH.md)。

全6負荷で実時間を満たし、最小余裕はWindows28.69倍/Linux30.34倍（dense8kHz）。従来不足したBRR/filter3/maxpitchは36.21/36.94倍で、ARSHIFT Forth比72.96/66.41倍。次の再生受け入れにはnative候補を採用し、参照Forthは既定として保持する。SPC700/ROM/実装置込みの結果ではない。

1183完了、1175/1176は速度/サイズを記録済みだが実聴・物理Ctrl+C停止/再再生が残る。Mac1177と親1173（auto40%）も未完了。今回生成音の装置再生・コミット/プッシュ・追加ビルドはしていない。一時スクリプトは.workへ置く。以下は各時点の履歴。



## SNES native1183完了・速度測定の開始確認待ち（2026-11-20）

mainを0f33455へff-onlyでプルし、YM2149/CHIP-8/ZX SpectrumのMac受け入れ完了記録を取り込んだ。EMULATOR_CORE_PLANの競合は両側を保持して解消し、作業中のSNES変更も保持した。コミット/プッシュは行っていない。一時スクリプトは.work/1183へ置いた。

ARSHIFT後も最重BRRはWindows0.496倍/Linux0.556倍で実時間不足だったため、既定方針に従い同期・借用bufferのnative frame kernel1183を実装。[新測定と採否](measurements/2026-11-20-snes-dsp-os-acceptance.json)、[native全36report/全ソース・指紋・実行体](measurements/2026-11-20-snes-dsp-native.json)、[設計](SNES_DSP_NATIVE_DESIGN.md)、[レビュー評価](reviews/1183-review-response.md)。最終ClaudeはHigh/Mediumなし。

8構成で参照Forth19モデル群、音声有効6構成でnative23群・両backend各19RAM群を照合。nativeはBRR256×16×3、317ENV、Gauss256×4、FIR8tapと非自明なfeedback/MVOL境界も通す。6構成で一括frame/DIV/切替え/reset/SAVESYS、通常2構成でEXEC-LIMITED中断後k-frameとPythonの全state/ARAM・queue/retryを確認。両OS各6負荷は両backendで計時なしの全PCM/266state/queue2/fullARAM照合が成功。no-audioでは語が未定義で、旧ABI/native依存画像の拒否も両OS成功。core1130/host162成功（skip10/15）、全reportの現物binary/source hashを照合した。

通常版サイズはWindows2161664（旧比+15872）/Linux2371680（+15328）byte。HEREは両OS122880→218640（増分95760、logical領域のみ）。Forthのキューと所有ARAMを保持し、参照版を既定、nativeは明示adapter。新実行体へ読ませる旧画像はABI署名不一致なので再作成が必要。

1183完了、1175/1176/1177と親1173は未完了auto40%。次は新たな開始確認への返答後だけ、通常版の `measure-snes-dsp-audio.py PATH --native --measure` をWindows→WSL/Linuxで順に実行する。nativeの速度は未測定で、実時間採用・実聴/物理中断再再生・Mac受け入れを完了としない。以下は各時点の履歴。


## CHIP-8/ZX SpectrumのMac受け入れ1167/1172完了（2026-11-20）

Mac1167/1172が合格し、CHIP-8の親1163とZX Spectrumの親1168を完了にした。YM2149の1138もMac1154で完了済み。結果は[CHIP-8](CHIP8_AUDIO_FORTH.md)、[ZX Spectrum](ZX_SPECTRUM_AUDIO_FORTH.md)。次の音源はSNES1174。以下の「Mac1172未完了」等は当時の記録。

## SNES初回速度測定で実時間未達・ARSHIFT候補検証済み（2026-11-20）

レモンの開始確認へのＯＫ後、Windows→WSL/Linuxで6負荷各16384frame×7processを測定し、全回のPCM/266state/queue2/fullARAMと前状態/ARAM reset/A5を照合した。最重filter3/maxpitchは実時間比Windows0.425倍/Linux0.503倍、Windows echoも0.983倍。初回版で宣言全負荷の実時間採用には不足する。[全7値・旧source・候補検証](measurements/2026-11-20-snes-dsp-os-acceptance.json)、[結果と採否](SNES_DSP_AUDIO_FORTH.md)。

まずForthのSD-ASRをFM/MODによるfloorから既存ARSHIFTへのaliasへ変更した候補を作成。native/ABI/API/harnessは不変。使用shift1/4/5/6/7/10/11の旧helper/候補/独立Pythonの境界115vectorを両OSで直接比較し、8構成×20モデル群（新helperの1344vector含む）・6構成×19RAM群が成功した。6負荷の計時なし検証でも全PCM/ARAM hash・state/queueが初回版と完全一致、oracle brr/Model/demo AST不変を確認。HERE95752byte増分のまま、native332source/8binary現物hashも不変。[候補レビュー](reviews/1175-1176-arshift-claude-review.md)は使用範囲で同値として評価を推奨しているが、改善幅は未測定。

次は新たな計時開始確認への返答後、同じmeasureスクリプトをWindows→Linuxで--measure実行し、候補の7値と旧版の比を別に記録する。旧値は上書きしない。なお不足すれば本体移行判断を具体化する。生成音の実聴は未実施。1174完了、1175/1176/1177と親1173は未完了。Mac1177は対応機能の子に残す。今回コミット/プッシュは行っていない。以下は各作業時点の記録。


## SNES1174完了・Windows/Linux測定の開始確認待ち（2026-11-20）

承認された標準S-DSPの8声/BRR/Gauss/ADSR/GAIN/noise/PMON/stereo/echoFIRをForthで実装し1174完了。[仕様・制限・結果](SNES_DSP_AUDIO_FORTH.md)、[14report/全ソース・指紋・来歴](measurements/2026-11-20-snes-dsp-audio.json)、[レビュー原文と評価](reviews/1174-review-response.md)。8構成×19モデル群、音声有効6構成×19stereo RAM caseが成功。10統合caseの全PCM/266state/全ARAM、一括/分割、BRR/Gauss/rate/317ENV/全reg/ARAM/手計算/error境界を検査。8構成すべて保存HTMLからGaussを別抽出して照合した。最終ClaudeはHigh/Mediumなし、Lowも検査追加後に全構成成功。

両OSの実PCM経路で各8192frameをFALSEのゼロのみ送出しAUDIO?=-1/handle0/underrun0/stack0/code0。Linux最初のAUDIO?=0回は参考に保存し、接続保持後の実経路を確認した。残留Sigma/pacatなし、保持用owned sleep120も終了済み。HEREはWindows122880→218632（logical増分95752byte、RSSではない）、再生bufferは別。native332ソース不変で既検証8binaryを再利用。CPU/ROM/実機微細slot互換の完了とは主張せず、宣言差分を仕様に明記。

親1173は未完了auto25%、Windows1175/Linux1176/Mac1177も未完了。999は未完了auto75%。次の1175/1176用6負荷各16384frameのハーネスは両OSで計時せず、全PCM/266state/queue2/fullARAMと前状態/全ARAM resetを照合した。[準備記録](measurements/2026-11-20-snes-dsp-os-preparation.json)、[計画レビュー](reviews/1175-1176-review-response.md)はHigh/Mediumなし。-Oは入口で拒否、未計時roundを明示。速度/採否/実聴は未実施。

次はレモンの計時開始への返答後、Windows→WSL/Linuxを順に `python tests/scripts/measure-snes-dsp-audio.py PATH_TO_SIGMA --measure` で7回ずつ測定する。開始確認は必須で、タイムアウトや機能検査は測定の代用ではない。Mac1177は残し、完了まで親1173を未完了に維持。今回コミット/プッシュは行っていない。以下は各作業時点の記録。


## ZX Windows1170/Linux1171完了・次はSNES1174の範囲確認（2026-11-20）

レモンがLinux物理再試験の停止→低音再生を確認し、最終追レビューHigh/Mediumなしで1171を完了。Windows1170も完了。[仕様・結果](ZX_SPECTRUM_AUDIO_FORTH.md)、[全値/ログ/ソース](measurements/2026-11-20-zx-spectrum-os-acceptance.json)、[最終レビュー評価](reviews/1170-1171-review-response.md)。

Linux物理は2回中、試験用の非可聴B/C/noise周期を変えた2回目で成功。初回exit=-2とcleanup未確認を保存。プログラムSIGINT診断は物理受け入れに数えず、NativeScope外のCtrl+Cは終了し得る制約を維持した。Linuxの残留Sigma/pacatなし、owned keepaliveはcmdline確認後停止済み。再生wrapperの初回最大4096frame供給修正は6構成×19RAM検査成功、純粋core/native不変・速度再測定なし。

1169/1170/1171完了、Mac1172未完了のため親1168は未完了auto75%、999は未完了auto68%。次はSNES1174。標準S-DSPの8声/BRR、envelope/noise、pitch modulation、echo/8tap FIRを対象とし、SPC700 CPUは別扱いとする案をレモンが承認済み。既存資料 `.work/1139/snes.pdf/.txt` のDSP register表とBRR章を確認したが、SDK/ROM/他実装コードはコピーせず、補間/境界/時刻とモデル範囲は資料とClaudeレビューで設計する。SNES実装には未着手。この範囲のコミット・プッシュ依頼を受領した。公開結果はGitの状態で確認する。以下は各作業時点の記録。


## Linux物理Ctrl+C初回失敗・診断と再試験準備（2026-11-20）

初回はREADY後SIGINT exit=-2、CATCH/再再生なしで1171未完了。失敗source/JSONを保存。[全記録](measurements/2026-11-20-zx-spectrum-os-acceptance.json)、[診断レビュー/評価](reviews/1170-1171-review-response.md)。無音の制御診断はSigCgtを確認してSIGSTOPで固定後にSIGINT/SIGCONTを注入し、捕捉なしはexit-2、捕捉ありはCATCH=-28/handle0→replay underrun0/DEPTH0/code0。物理受け入れの代替にはしない。元の失敗時の命令位置は特定できない。

再試験用Linux helperのみ非可聴B/C period4095、noise31へ変更。AY高/低音各49152frameの全PCM/39状態を独立Pythonと照合し、元の実聴PCMともhash一致。192/288block無音送出もunderrun0/handle0。native/core/wrapper不変、追加速度測定なし。物理捕捉が必ず成功するとは保証しない。

次は了承後 `.work/1170-1171/launch-linux-interrupt.ps1` を開く（引数linux linux-r2）。新しい結果はlinux-r2-interruptへ分ける。まだ生成音を再生していない。Windows1170完了、Linux1171/Mac1172と親1168は未完了。WSL保持用owned sleep1800はLinux完了後に本人確認して停止。コミット/プッシュは行っていない。以下は各作業時点の記録。


## Linux128K実聴済み・物理Ctrl+C準備（2026-11-20）

レモンがLinux128Kの高音→低音→低音+断続beeperを確認した。全段階underrun0/handle0/49152frame/stack0/code0。Linux48Kも実聴済み。[全記録](measurements/2026-11-20-zx-spectrum-os-acceptance.json)。

次は了承後、`.work/1170-1171/launch-linux-interrupt.ps1` で可視PowerShellからWSL/python3のinterrupt.py linuxを実行する。連続約440Hzを1秒ほど聴いたら、そのテスト窓でCtrl+Cを1回。停止後500msの間を置いて低い約220Hzが約3秒再生される。CATCH=-28/handle0、replay handle0/underrun0、DEPTH0/code0を確認する。まだ起動していない。タイトルはEncodedCommand方式でWindowsの引用符問題を避ける。

Windows1170完了、Linux1171/Mac1172と親1168は未完了。WSL保持用owned sleep1800はLinux完了後に本人確認して停止する。コミット/プッシュは行っていない。以下は各作業時点の記録。


## Linux48K実聴済み・128K準備完了（2026-11-20）

レモンがLinux48Kのブザー約1秒→無音約1秒を確認。underrun0/handle0/98304frame/stack0/code0。[全記録](measurements/2026-11-20-zx-spectrum-os-acceptance.json)。Linux128Kの3段階（AY約440Hz→約220Hz→低音+断続beeper、各1.024秒）は全段階の無音実PCMがunderrun0/handle0で、各全PCM/状態も独立期待値とLinux上で一致した。生成音はまだ鳴らしていない。

次は了承後、`.work/1170-1171/linux-128k.fs` をWSL/Linux通常binaryで実行する。その後物理Ctrl+C。Windows1170完了、Linux1171/Mac1172と親1168は未完了。WSL保持用sleep1800はownedで、Linux完了後にkeepalive.pidとcmdlineを確認して停止する。コミット/プッシュは行っていない。以下は各作業時点の記録。


## Windows1170完了・Linux48K実聴準備（2026-11-20）

レモンが物理Ctrl+Cで停止後の低音再生も確認し、Windows1170を完了にした。48K/128K実聴とCATCH=-28/handle0、再生underrun0/DEPTH0/code0が揃った。[全記録](measurements/2026-11-20-zx-spectrum-os-acceptance.json)。親1168は未完了auto50%、Linux1171/Mac1172は未完了。

WSLg Pulseは初回connection refused、ownedWSL sleep1800で保持後pactl infoとAUDIO?=-1を確認した。RDPSink/44100Hz stereo、model入力48000Hz mono。Linux48Kの約440Hzブザー→無音の無音版はunderrun0/handle0/98304frame/code0。生成音はまだ鳴らしていない。次は了承後、`.work/1170-1171/linux-48k.fs` をWSLの通常Linux binaryで実行する。保持用のowned processはkeepalive.pidで識別し、Linux受け入れ後に本人確認して停止する。Windowsテスト窓は終了したSigmaの後にPowerShellが残るだけで、勝手に閉じない。コミット/プッシュは行っていない。以下は各作業時点の記録。


## Windows物理Ctrl+C/再生ログ成功・実聴詳細待ち（2026-11-20）

可視テストでCATCH=-28/handle0、REPLAY-OK handle0/underrun0、DEPTH0/code0を確認した。レモンは「音は鳴った」とログを提示。停止後に低い音が約3秒鳴る順序の実聴確認はまだ明示されていないため1170は未完了。Sigma processは終了済み。[全記録](measurements/2026-11-20-zx-spectrum-os-acceptance.json)。

冒頭のZX command-not-foundはStart-Process -Commandのタイトル設定で引用符が失われたもの。無音のlabel代入だけで同じエラーを再現し、EncodedCommand方式で文字列全体の出力/stderr0を確認した。次回用 `.work/1170-1171/launch-windows-interrupt.ps1` は修正済みだが、音声テストは再実行していない。1170/1171/1172と親1168は未完了。コミット/プッシュは行っていない。以下は各作業時点の記録。


## Windows128K実聴確認済み・物理Ctrl+C準備（2026-11-20）

レモンがAY高音→低音→低音+断続beeperの3段階を確認した。全段階underrun0/handle0/49152frame/stack0/code0。[記録](measurements/2026-11-20-zx-spectrum-os-acceptance.json)に保存した。Windows48K修正版も実聴済み。

次はWindowsの物理Ctrl+C。`.work/1170-1171/interrupt.py windows` を可視PowerShellから実行し、約440Hzの連続音を1秒ほど聴いたらCtrl+Cを1回。CATCH=-28/handle0で停止し、500ms後、約220Hzを3.072秒再生する。replay handle0/underrun0、DEPTH0、code0を確認する。監督PythonだけSIGINTを捕捉し、Sigmaへ物理入力が届く構成。まだ起動していない。割込み前streamのunderrunはclose後に照会できないため0とは記録しない。

1170/1171/1172と親1168は未完了。コミット/プッシュは行っていない。以下は各作業時点の記録。


## Windows48K修正版の実聴確認済み・128K準備完了（2026-11-20）

レモンが修正版の約440Hzブザー約1秒→無音約1秒を確認した。underrun0/handle0/98304frame/stack0/code0。[記録](measurements/2026-11-20-zx-spectrum-os-acceptance.json)に保存した。

次のWindows128KはAY高音約440Hz→低音約220Hz→低音に断続的なbeeperが重なる3段階（各96block=1.024秒）。無音の実PCMは全段階underrun0/handle0/49152frame/code0。各段階の全PCM/39状態/queueを独立Pythonと照合済み。生成音はまだ鳴らしていない。1170/1171/1172と親1168は未完了。次は128K実聴への了承後に `.work/1170-1171/windows-128k.fs` を通常Windows binaryで実行する。コミット/プッシュは行っていない。以下は各作業時点の記録。


## ZX初期供給不足を修正・無音検証完了（2026-11-20）

レモンが最初のWindows48Kブザー→無音を実聴確認した。underrunはWindowsの初期8×480frame連続renderに対して初回512frameしか渡さない経路で再現し、ZX wrapperの初回だけ最大4096frameをまとめて公開するよう修正。1block/8blockだけを変える比較で対照1/1/1、修正48K0/0/0・128K0/0/0。6構成×19RAM検査とClaudeレビュー（High/Mediumなし）も成功した。[結果/ログ/ソース](measurements/2026-11-20-zx-spectrum-os-acceptance.json)、[評価](reviews/1170-1171-review-response.md)。native/coreと測定source不変、速度再測定なし。

追加の生成音は鳴らしていない。次は修正版で同じWindows48Kブザー→無音を再確認し、その後128K・物理Ctrl+Cへ進む。Windows1170/Linux1171/Mac1172と親1168は未完了。今回コミット/プッシュは行っていない。以下は各作業時点の記録。


## ZX Spectrum Windows実聴でunderrun検出（2026-11-20）

レモンのＯＫ後、約440Hz/約1秒→無音約1秒をWindowsで1回再生した。code0/handle0/98304frame/ULA0/stack0だがunderrun2で、実聴の返答も未受領のため受け入れは保留。追加の生成音は鳴らしていない。無音3回はunderrun0/1/1、事前に2048frame合成する無音3回も2/1/2で解消せず、原因未特定。最初の影響例はblock4/5で増加している。[全ログ/実行source](measurements/2026-11-20-zx-spectrum-os-acceptance.json)に保存。1170/1171/1172と親1168は未完了。次は実聴の返答を受け、初期送出とconsumerのログを調査する。速度測定は再実行していない。以下は各作業時点の記録。


## ZX Spectrum Windows/Linuxの速度・サイズ記録（2026-11-20）

レモンの開始確認へのＯＫ後、通常構成の6負荷32768frame×7processをWindows→WSL/Linuxの順に測定し、全回のPCM/状態/queueとRESET/A5を照合した。実時間比の中央値は48K beeperが78.81倍/91.59倍、最小の128K period0が3.59倍/4.14倍。[全値・指紋](measurements/2026-11-20-zx-spectrum-os-acceptance.json)、[結果と採否](ZX_SPECTRUM_AUDIO_FORTH.md)。測定範囲の音源はForthを維持するが、CPU/ROM全体・任意trace・実装置再生の保証ではない。

サイズはnative不変でWindows2145792byte/Linux2356352byte、logical辞書増分25160byte。Windows1170/Linux1171は生成音の実聴・物理Ctrl+C後の停止/再再生待ち、Mac1172も未完了。親1168は未完了auto25%、999は未完了auto61%。次はWindowsの48K beeper約1秒→無音約1秒の実聴から行う。コミット/プッシュは行っていない。以下は各作業時点の記録。


## ZX Spectrum実装1169完了（2026-11-20）

レモンが48K beeper/128K beeper+AYを承認した。[仕様・結果](ZX_SPECTRUM_AUDIO_FORTH.md)、[全検査データ/ソース指紋](measurements/2026-11-20-zx-spectrum-audio.json)、[レビュー対応](reviews/1169-review-response.md)を保存した。全port/register byte、16envelope手書き列、独立CPU tick/全PCM/状態、queue/error/time上限を8構成で照合。音声有効6構成の11RAM送出検査、両OSの各8192frame無音実PCMも成功。最終ClaudeはHigh/Mediumなし。native332ソース不変、HERE増分25160byte（RSSではない）。

1169完了、親1168は未完了・auto25%。999は未完了・auto61%。Windows1170/Linux1171/Mac1172のサイズ/速度・採否・生成音の実聴は未完了。速度測定は準備を済ませ、開始確認への返答後に実行する。Macの確認は対応featureの子タスクに残す。今回の差分は未コミットで、コミット/プッシュは行っていない。1170/1171用の6負荷32768frame測定ハーネスは両OSで計時なしの全PCM/状態検証に成功し、[準備記録](measurements/2026-11-20-zx-spectrum-os-preparation.json)と[計画レビュー](reviews/1170-1171-review-response.md)を保存した。計時開始の返答待ち。以下は各作業時点の記録。

## CHIP-8 Windows/Linux受け入れ1165/1166完了（2026-11-20）

レモンの開始確認へのＯＫ後、6負荷32768frame×7processをWindows→WSL/Linuxで正式再測定した。最重の8kHz pattern/pitch更新は実時間比Windows33.78倍/Linux38.23倍。全PCM/状態・A5/RESET・queue件数/stack0を照合。実聴は両OSでclassicのtimer停止、XO高低の切替、物理Ctrl+C後の停止/再再生を確認し、handle0/underrun0/code0。宣言した音源はForth維持とし、CPU/ROM全体の性能は主張しない。[結果/採否](CHIP8_AUDIO_FORTH.md)、[全データ](measurements/2026-11-20-chip8-os-acceptance.json)、[レビュー](reviews/1165-1166-review-response.md)。

1164/1165/1166完了、Mac1167は未完了のため親1163は未完了・auto75%。YMのMac1154はtodo。999は未完了・auto59%。次はZX Spectrum1169の対象モデル/音源範囲を確定して仕様・実装へ進む。事前確認なしの速度値は参考値として保全し正式値とは分離した。今回の差分は未コミット。以下の測定待ち等は各作業時点の記録。

## CHIP-8/XO音源の実装1164完了（2026-11-20）

レモンが原型/SUPER-CHIPのブザーとXO-CHIP pattern/pitchを承認した。[仕様・結果](CHIP8_AUDIO_FORTH.md)、[全生データ/ソース指紋・本文](measurements/2026-11-20-chip8-audio.json)、[レビュー評価](reviews/1164-review-response.md)を保存。modern timer>0 gate、固定440Hzブザー、16byte所有コピー、Q32 pitch/phase、60Hz境界と時刻付きqueueをForthに追加した。CPU/ROMや原機speakerの電気特性は対象外で、native/Builtin/ABIは変更していない。

Windows/Linuxの通常・除外の8構成で各13モデル検査群、音声有効6構成で各11RAM送出/cleanup検査成功。全256pitch/65536frame、512pending patternの回収と2730event、同tick順、250境界のphaseを独立数理/手計算と照合。無音の実PCMも両OSで成功、最終ClaudeはHigh/Mediumなし。辞書HERE増加43120byteはlogical値でRSSではない。性能測定・生成音の実聴は未実施。

1164を完了、Windows1165/Linux1166/Mac1167は未完了のまま。親1163は未完了・auto25%、999は未完了・auto55%。次は1165/1166のサイズ/速度・採否と生成音の実聴へ進む。YMのMac1154はtodo。監査1139と今回の実装差分は未コミットで、コミット/プッシュは今回行っていない。

## 音源8対象の先行照合1139完了（2026-11-20）

[8対象の音源監査](AUDIO_TARGET_AUDIT.md)と[資料/ソース指紋・タスク出力](measurements/2026-11-20-audio-target-audit.json)を保存した。CHIP-8、ZX Spectrum、SNES、Apple IIに機種固有の状態/時刻/PCM生成の不足があり、機種別親1163/1168/1173/1178を999直下へ追加。各機種に仕様実装・Windows・Linux・Macの子を置き、Macの未確認を末尾へまとめない。1140は新4件への依存も保持し、モデル/変種の対象と保留理由を最終確認する。Forth先行は既存の利用者決定で、今回最終採否を決めていない。[レビュー評価](reviews/1139-review-response.md)、最終High/Mediumなし。

1139は完了、新4機種は未着手。YM2149のMac1154はtodo、1138は未完了・auto80%。999は未完了・auto52%（未着手4枝を追加したため表示が下がった。工数比ではない）。1140は未完了で依存待ち。次はCHIP-8の仕様/実装1164から着手し、対象変種と波形・timer境界を先に確定する。今回の監査差分は未コミット。

## 最新の音声受け入れ状態（2026-11-20）

Linux版からpacat/WSLg PulseAudio経由の実聴を完了し、PCM998、NES1132、SID1136、Paula1137は完了。YM2149はWindows1161/Linux1162に続きMac1154も合格し、1138は完了（[Mac記録](YM2149_FORTH.md#mac実機受け入れ11542026-11-20)）。音源全体999は未完了・auto68%。[Linux実聴の全記録](measurements/2026-11-20-linux-audio-listening.json)。Linux実機ALSA装置の確認とは区別する。以下は各時点の履歴。

## 現在状態：Atari ST YM2149の実装・Windows/Linux検証（2026-11-20）

基点mainはcf080b4（Paulaまでpush済み）。今回のYM2149差分は未コミット。1152（監査と実装）・1153（Windows/Linux検証と測定）を完了し、Mac1154を1138の子に残した。1138は未完了・auto66%、999はauto49%。PaulaのMac1147は完了し、Windows実聴1155/Linux実聴1156が未完了のためPaula1137はtodo・auto60%。Macの確認まで親タスクの完了とはしない。以下は各作業時点の履歴で、この節を優先する。

[YM2149の契約・資料・結果](YM2149_FORTH.md)、[レビュー評価](reviews/1138-review-response.md)、[全測定・ソース本文](measurements/2026-11-20-ym2149.json)を参照。3声/noise/全16envelope、時刻指定、raw読取り、2つのI/O latchとFF8800/FF8802のbyte busをForthに追加した。既存native YMの固定音量0が微小出力になる問題も修正し、非ゼロ固定音量・envelope level1と停止後のfilter tailを保持する回帰検査を追加した。Builtin/ABIは追加しない。

両OSの通常・debug/graphics/extension除外・さらにfloat除外の6構成で各11検査群と補助12検査が成功。audio除外の2構成でも全512frame/状態が一致。全8実行体はnative修正後の新ビルド。native Windows全体検査成功、Linux core1126成功/10skip、host167成功/17skip、失敗0。通常負荷は実時間比Windows9.532倍/Linux11.431倍、全period1は3.212/3.834倍。各6負荷32768frameの全PCM/状態と、各7計時の最終37状態を独立Pythonと照合した。辞書HERE増加25152byte、通常実行体はPCM1128保存済み版比Windows+512/Linux+48byte。最終ClaudeレビューはHigh/Mediumなし。

Mac1154では新ビルドのnative fixed-zero回帰・core/host検査、Forth通常/除外構成・サイズ/速度と生成音の実聴・中断/資源回収を確認する。Windows/Linuxのfixtureは実聴を証明しない。次は1139で8対象の既存音源経路と不足を照合し、追加不要の根拠または必要な機種別タスクを記録する。1140の最終採否は各機能のMac確認を含む依存が済むまで完了にしない。

作成日：2026-11-18
状態：方針の3点を決定済み（2026-11-18）。語の名前とスタック効果などの細部は未確定（実装未着手）

管理タスク：tque **1003**（レトロPCエミュレータ向け拡張。親613 本体の機能拡張）と配下の既存5件（997〜1001）、共通の保存アプリ起動基盤1066（配下1067〜1069）

この文書は、613の「サウンド」と「グラフィックス」の語群（項目8〜12）と、語群に依存しない本体コアの保存アプリ起動基盤1066を扱う。全体の構成、語群の分け方、進める順序は[本体の機能拡張の全体](CORE_EXTENSION_PLAN.md)、段階0の共通の取り決め（900）は[共通の取り決め](ASYNC_COMMON_RULES.md)、「拡張モジュール」の語群（項目1〜7）は[TUI・非同期実行基盤の対応方法](ASYNC_CORE_PLAN.md)にある。項目の番号は3つの文書で通しである。

2026-11-18にCodex（codex-cli 0.169.0、読み取り専用）のレビューを受け、指摘10件を反映した。指摘が根拠としたソースの箇所は、反映の前に読んで確かめた。Codexは実行テストをしていない。依頼文と結果は `.work/emulator-core/`（Git管理外）にある。

## 目的と範囲

CHIP-8、ZX Spectrum、NES、Commodore 64、SNES、Apple II、Amiga、Atari STのエミュレータをForthで書くために、本体に足す機能である。エミュレータそのものはアプリ側（Forth）で書くので、ここには含めない。8、9、10は待機・キュー・資源の持ち主にかかわるので、[共通の取り決め（900）](ASYNC_COMMON_RULES.md)に従う。10は音のスレッドへのコマンドのキューを使う（いまの `SOUND` も64個のキューを通し、満杯なら待つ。`src/core/sound_engine.zig` の `commands`、`src/core/words_audio.zig` の `putCommand`）。11と12は待機も資源も持たない、グラフィックスの語の拡張である。CPUコア、機種ごとの描画の合成、キーボードの走査、ROMやディスクの形式は、本体に置かずForthで書く。

## 追加する共通基盤：保存アプリの起動（1066）

2026-11-19、利用者の指示により、SAVESYSで作った実行体が登録したForthの起動語を自動実行し、アプリ引数・初期化・終了・診断を扱う共通基盤を1003へ追加する。本体コアとネイティブホストに置き、audio/graphics/extensionの公開語群へは依存させない。LOGOの言語処理・タートル・UIはSigmaへ組み込まず、機種固有のエミュレータと同様にForthアプリ側に置く。

設計1067は先行可能。実装1068は1067・1056・1064、受け入れ1069は1068に依存する。既存997〜1001との一律の完了待ちは付けない。1003と最終1057の完了には1066の成果も含める。保存アプリの自動起動は2026-11-20に1066として実装・3OS受け入れ済み（[実装記録](SAVED_APPLICATION_STARTUP_IMPLEMENTATION.md)）。[採用範囲・設計論点・完了条件](SAVED_APPLICATION_STARTUP_PLAN.md)。

## 現状の一覧

| 項目 | tque | 語群 | Sigmaにあるもの | 足りないもの |
|---|---|---|---|---|
| 8 物理キー | 997 | グラフィックス | GRAPHICSの `INKEY`、`KEY-HELD?`（ASCIIの1バイトの文字と `K-UP` などの特殊キー、同時に16個まで） | 修飾キー単独と左右の区別、配列によらないキーの番号、押下と解放のイベント |
| 9 PCMストリーム | 998 | サウンド | `PLAY`（MML）、`SOUND`（PSG）、`SAMPLE` と `SFX`（1回だけ、同時に4つ）、`PLAY-MOD` | Forthが作った標本を途切れなく流す語、キューの残量 |
| 10 音源のレジスタ | 999 | サウンド | `SOUND`（PSGのレジスタ0〜13）、SID・NES・Paulaに似せた合成（`sound_c64.zig`、`sound_nes.zig`、`sound_amiga.zig`。MMLの音符と音色を受ける作りで、実機のレジスタは持たない） | レジスタの状態と副作用、チップの時計による進行、書込みの時刻を扱う層 |
| 11 直接色の画素転送 | 1000 | グラフィックス | `GFX-INDEXED`（1画素1バイト。1回の転送で使える色番号は256種類。画像は24ビット色）、`GFX-PSET` | メモリ上のRGBの並びを一括で写す語 |
| 12 描画の補助 | 1001 | グラフィックス | `DRAW-TILEMAP`、`DRAW-SPRITES`（行ごとの上限）、`RASTER-SCROLL`、`RASTER-COLOR` | タイル1行の描画、ビットプレーンから色番号への変換 |

Gforthに同じ働きの語があるかは調べていない。

## 調べたこと（2026-11-18）

- `docs/GRAPHICS_AND_SOUND.ja.md`、`docs/GRAPHICS_MODES.ja.md`、`docs/USER_MANUAL.ja.md` の語の一覧、`src/graphics/game.fs`、`src/core/graphics_input.zig` の押下状態の部分、`docs/NATIVE_WINDOW_STUDY.md` の#909の入力の契約を読んだ。
- 速度：Linux x86_64（Intel Core i7-8700K、Zig 0.17.1、コミット `493faeb` に作業中のLinuxウィンドウの変更が載った作業ツリー）、`-Doptimize=fast` のビルドで、6502に似せた最小のループ（1バイトを読み、表から実行トークンを引いて `EXECUTE`、フラグの更新を含む。命令は6種類）を2000万命令実行し、約3.2秒（約620万命令/秒）だった。256×240のバイトの並びを1画素ずつ書く処理は、60フレームで約0.12秒（約2 ms/フレーム）だった。画素は `C!` でメモリへ書いただけで、画像への転送と `SHOW` は含まない。1回だけの測定で、実際のCPUコアや描画の速度を表す値ではない。測定のソースは `.work/emulator-core/bench.fs`（Git管理外）。
- 調べていないこと：Gforthに同じ働きの語があるか、WindowsとmacOSでの速度、Tkのウィンドウの表示にかかる時間、各機種のエミュレータの実際の負荷。

## 8. 物理キーの状態とイベント（997、段階A）

利用者決定により、物理キーは`EKEY`に出さず、GRAPHICSの別の語で読む。`KEY-HELD?`の文字／特殊キーと同時16個の契約は変えない。

2026-11-19に[詳細設計](PHYSICAL_KEY_DESIGN.md)を作成し、[Claude Codeレビューと採否](reviews/997-review-response.md)を反映した。[実装記録](PHYSICAL_KEY_IMPLEMENTATION.md)と実機確認は分けて管理する。

- 番号はUSB HID Keyboard/Keypad page 0x07の0〜255。予約0〜3は生成しない。Windows Set1、Mac keyCode、XKB key nameから変換し、文字配列から推定しない。
- 公開語は`SCAN-INPUT?`、`SCAN-SUPPORTED?`、`SCAN-HELD?`、`KEY-EVENT`、`KEY-RESYNC`とSC-*定数。キーごとに実際の押下／解放が両方得られるかを調べられる。
- 専用256ビット状態・256件edgeキュー。あふれたら先の256件を残して新しいedgeを捨て、状態更新は続ける。履歴の後にstickyな再同期要求を返し、32バイトsnapshot採取とackを原子的に行う。通信snapshot待ちなら要求を消さない。
- `INKEY`、`EKEY`、文字／IMEキューと独立。フォーカス喪失と閉鎖では全解放し、閉鎖前の履歴は取り出せる。端末・SIXEL・Tkは未対応とし、自動でnativeウィンドウを開かない。
- 本体コアは純粋な型・検査・optional Writer Ops、GRAPHICSは公開語、ホストはOS変換・入力所有を担う。AUDIOには追加しない。イメージには一時入力を保存せず、復元成功時にTrackerを境界状態にする。OS／pipeに未読で残り復元後に届く通知は取り込む。
- Macは左右修飾と独立SCAN IPCを追加する。最新snapshotの非blocking再送で最後の解放が落ちても復旧させる。Linuxは完了済み982のX11経路にXKB GetNames/NamesNotifyを足し、keycode-8という固定換算は使わない。

作業順：1079設計→1080実装（1083 pure Tracker→1084 nativeホスト→1085公開語→1086統合レビュー）→1081 Windows/Linux自動受け入れを完了。残りは1082 Mac実機と1087 Windows/Linux実キーボード。公開語・native接続は実装済みだが、997全体は未完了。

## 9. PCMストリーム出力（998、段階B）

2026-11-20追記：1125の[採用設計](PCM_STREAM_DESIGN.md)と1126の[内部実装・検証](PCM_STREAM_IMPLEMENTATION.md)へ分割して着手。以下の候補・未決点は元の計画であり、現在のAPI・値は採用設計を優先する。公開語1128とホスト寿命1127、OS受け入れ1129/1130は別工程。（追記：1127〜1130まで完了し、998は[実装・検証済み](PCM_PUBLIC_IMPLEMENTATION.md)。）

Forthが作った波形を途切れなく流す語がない。ZX SpectrumとApple IIの1ビットの音、NESのDMC、Paula、SNESのDSPに要る。キューの残量が分かれば、音を基準にしてエミュレータの速度を合わせることにも使える。

- **語の候補**：ストリームを始める語（標本化周波数とチャンネル数）、標本を書く語、キューにあるフレームの数を返す語、止める語。名前とスタック効果は未決。数はフレーム（全チャンネルの1組）で数える。
- **専用の有界のリングを足す。** いまの標本の領域（`src/core/sound_pcm.zig`）は末尾に足すだけで、音のスレッドが読む部分を書き換えない作りなので、流し続ける用途には使い回せない。エンジンの `Ring` は生産者1つ・消費者1つの受渡しで、同じ形が使える。書く語は標本をリングへ写すので、戻った後は呼出し側のメモリを使ってよい。
- **標本化周波数の変換**：出力は48 kHz・16ビット・ステレオである（`src/host_audio.zig`）。ストリームの周波数からの変換を本体が行う。
- **空になったときは無音を出す。** 足りなくなった回数を読めるようにするかを決める。
- **残量と再生位置を分ける。** リングにある数、エンジンが取り出した数、出力装置の側の遅れ（10 msのバッファが8個）は別のものである。残量だけでは、実際に鳴っている位置は分からない。音を基準に速度を合わせたときの精度は確かめていない。
- **段階Bに置く（決定）。** 共通基盤だけに依存し、項目3（639）の実装は待たない。2026-11-19の利用者指示により直接依存は900全体から実装確認済み1064へ切り替え、Mac実機1065は別に残す。部分書込みの形は、900で3と同じ仕様として決める。
- **満杯のときの扱いは共通の取り決め（900）で決める。** 待つ形と、書けた分だけ書いて戻る形がある。項目3の部分書込みとそろえる。
- **待機中の中断**：`PLAY` はキューの空きを待つ間のCtrl+Cを受け取り、入れた音符を取り消している（`src/host_audio.zig` の `wait` は中断を知らせるだけで、取り消すのは `src/core/words_audio.zig` の側）。PCMでは、中断のときに書けた数を返すか、まだ鳴っていない分を捨てるか残すかを決める。止める語も、鳴らし切ってから止めるか、すぐ止めるかを決める。
- **実装場所**：`src/core/sound_engine.zig`、`src/core/sound_pcm.zig`、`src/core/words_audio.zig`、`src/audio/audio.fs`。

未決の点：

- 標本の形（符号付き8ビットか16ビットか、モノラルかステレオか）。
- MML、`SFX`、モジュールと同時に鳴らすときの混ぜ方。
- 出力が失敗したとき（`AUDIO?` が偽）に、書く語がどう戻るか。出力装置がないとき（エンジンは時間に合わせて合成して捨てる）と、エンジンを起動できないときを分ける。
- キューの長さと遅れの上限。

## 10. 音源チップのレジスタ書込み（999、段階C）

2026-11-22現在：8対象の音源モデルと3つのOSの受け入れ、最終採否1140が完了し、999は完了した。対象は各文書が宣言したモデルで確定し、変種は保留、機種によらない本体の部品は足さない（`SNES-FRAMES`は本体に残す）。表と保留の一覧は[音源監査](AUDIO_TARGET_AUDIT.md)の「最終採否」。この節の下の表と記述は、各時点の記録である。

2026-11-20最新：各音源のWindows/Linux実聴を機能ごとの子に置いた（NES1150/1151、SID1157/1158、Paula1155/1156）。Mac受け入れ1144/1143/1147は合格だが、親1132/1136/1137は未完了。以下は当時の記録。

2026-11-20リモート取り込み後の現在状態：NES/SIDのMac受け入れ1144/1143が合格し、親1132/1136も完了。Paulaは実装1145・Windows/Linux1146が完了、Mac1147と親1137は未完了66%。999はauto52%。

2026-11-20現在：[PaulaのForthモデル](PAULA_FORTH.md)の実装1145とWindows/Linux検証・測定1146を完了。Mac1147が未完了のため親1137は未完了66%。確認を最後へ集約せず、1137の配下で完了を管理する。次はAtari ST1138の充足・不足監査。

2026-11-20のMac確認前：Mac確認1143/1144はSID1136/NES1132の子へ移動し、両親を未完了に戻した（追記：Mac確認1143/1144合格後、親1136/1132は完了）。モデル実装の完了とは分ける。PCM実聴1133もPCM998の子へ移動し、998を未完了へ戻した。1057の最後へ集約せず、各機能内で確認・完了を管理する。以下の「1136/1132完了」は実装完了時の履歴。

2026-11-20最新追記：[DMCを含む5声のForthモデル](NES_DMC_FORTH.md)1135/1132と[SIDの決定的3声モデル・独自フィルター近似](SID_FORTH.md)1136を完了。測定した音源単独の範囲はForthで維持し、Paula/STと先行照合1139・最終採否1140は未完了。以下の4声/DMC未実装の記述は各時点の履歴。


### 音源の対象と現在状態（999）

2026-11-20修正。NESを最初に進めるという利用者の選択は、他機種を対象外にする決定ではない。旧タスク木でSID/Paula等が未登録だったため、999の75%表示は対象範囲を反映できていなかった。機種別作業と上位計画8機種の照合1139を登録し直した。既存の音声機能と、レジスタ/エミュレータ用途の充足は分けて確認する。

| 上位計画の機種 | 確認済みの既存基盤・進捗 | 残る確認・作業 | tque |
| --- | --- | --- | --- |
| CHIP-8 | BEEP/PCMの共通基盤 | 機種固有用途を既存機能で満たすか未判定 | 1139 |
| ZX Spectrum | PSG/PCMの共通基盤 | 対象モデルと音源用途の充足・不足を照合 | 1139 |
| NES | NTSC 5声のForthモデル1132/1135完了、定義した範囲はForthで維持 | DMA/CPU/PPU・bus競合・実機/ROM互換は範囲外、Mac実行・実聴は1144で確認、Windows/Linux実聴は未確認 | 1132 / 1135 / 1144 |
| Commodore 64 | 決定的3声レジスタモデルと独自Q16フィルターをForthで検証・測定、1136完了 | 合成波形・実機6581/8580アナログ特性・ROM互換は範囲外。Mac例/実聴は1143で確認、Windows/Linux実聴は未確認。重い混在のWindows約1.03倍は音源単独 | 1136 / 1141 / 1142 / 1143 |
| SNES | PCMの共通基盤 | DSPレジスタ用途の充足・不足を照合 | 1139 |
| Apple II | PCMの共通基盤 | 機種固有用途を既存機能で満たすか未判定 | 1139 |
| Amiga | 4声stereoレジスタ/DMA/手動DAT/IRQ/attachの実装1145と検証/測定1146完了、Mac受け入れ1147も合格。1137はWindows/Linuxの実聴1155/1156が残り未完了 | Windows/Linuxの実聴は未確認。Agnus bus/実機pipeline・analog/ROM互換は範囲外 | 1137 / 1145 / 1146 / 1147 |
| Atari ST | ST-SOUNDがYM2149を選択し、SOUNDで0〜13を書き込む既存経路 | 書込み時刻・読取り・I/Oポート・副作用の充足、不足分の実装/実測・採否を確認 | 1138 |

Atari STの根拠はsrc/core/sound_engine.zigのchip reset時のPsg.init(.ym2149)、同じengineのwrite command、src/core/words_audio.zigのSOUND 0..13検査、src/core/sound_psg.zigのレジスタ処理。既存経路があることを、機種全体の互換性が完了した意味にはしない。未検証の不足を推測で実装する前に、1138でソースと資料を照合する。

999の現在表示はauto52%。直下の共通1131=100、NES1132=100、SID1136=100、Paula1137=66、Atari ST1138=0、先行照合1139=0、最終採否1140=0の7枝を均等平均する。工数比や対応済み機種の比率ではない。1139で不足が見つかったら機種別の子タスクを追加し、1140の依存にも追加する。分母が増えると進捗表示が下がる場合がある。既存基盤で足りる機種も、その根拠と追加実装が不要な理由を記録する。未判定を暗黙に対象外・完了扱いにしない。

先行照合1139は機種別実装を待たず進められる。最終採否1140は1132/1136/1137/1138/1139へ依存し、先に完了できない。DMC1135/NES1132とSID1136は、それぞれ宣言したモデル・測定・採否を完了した。実機DMAやCPU/PPUの実装・完全互換を完了した意味ではない。

以下の追記は対象漏れ修正前を含む各時点の履歴。


2026-11-20最新追記：利用者選択でNES APUから着手。[NTSC 4声のForth試作1134](NES_APU_FORTH.md)を完了し、定義したサブセットは本体へ移さずForthで維持する。DMCと残る互換性・再測定は1135、1132/999全体は未完了。PCM基盤のMac1130はdde0547で完了済み。以下の「Mac未確認」は各時点の履歴。

2026-11-20追記：PCMは9d1c528で公開語・Windows/Linux自動確認までpush済み、Mac1130は未確認。利用者指示により999の着手依存を998全体から完了済み1129へ変更し、1064は維持する。先行子1131の[独自4声Forth試作と測定](PCM_SYNTH_PROTOTYPE.md)を進める。機種別音源の負荷と本体移行の採否は1132として分離し、999全体は未完了。

Forthからレジスタを書ける音源は、いまはPSG（`SOUND`）だけである。Commodore 64、NES、Amigaのエミュレータは、SID、APU、Paulaのレジスタへの書込みで音を出す。

いまのSID・NES・Paulaの合成は、MMLの音符と音色を受ける作りで、レジスタへの書込みを受けられない。語を足すだけでは済まない。

- **SID**（`src/core/sound_c64.zig`）：音符の高さと音色の設定から鳴らす。波形は出力の周波数で作っており、実機の写しではない。
- **NES**（`src/core/sound_nes.zig`）：スイープ、長さカウンター、ハードウェアのエンベロープ、DPCMを省いている。
- **Paula**（`src/core/sound_amiga.zig`）：登録した標本を、音符の高さ、MMLの音量、ADSRで鳴らす。DMA、メモリの参照、再生の終わりの割込みはない。
- **書込みの時刻**：`SOUND` のコマンドは、音のスレッドが合成の区切りの先頭でまとめて反映する（`src/core/sound_engine.zig` の `render`）。フレームの中の位置は持たない。

対応方法の候補は3つある。**本体に置かない形で始める（決定）。**項目9だけで全機種の音を出せ、(b)は機種ごとに音源のエミュレータを本体に書く規模になるためである。速度が足りなかった機種だけ、後から本体に移す。

- **(a) 近似の音源を操作する語**：いまの合成の部品（発振、ノイズ、フィルター）を、レジスタに近い引数で鳴らす。実機と同じ音にはならない。
- **(b) 実機のレジスタに合わせた音源**：レジスタの状態と副作用、チップの時計による進行、時刻を付けた書込みを扱う層を新しく作る。時刻を付けるなら、時間の軸と停止の処理を項目9と共有する。
- **本体に置かない形**：音源をForthで合成し、項目9のPCMで流す。本体の追加は要らないが、速度が要る（未測定）。

未決の点（本体に移すことになった場合）：(a)と(b)のどちらを採るか。実機の状態の読取り（SIDのOSC3など）と割込みをForthの側に残すか。キューの容量、満杯のときの待機、中断、リセット、MMLと同じ声部を使うときの持ち主（900で決める）。語の名前。

## 11. 直接色の画素転送（1000、段階C）

`GFX-INDEXED` は1画素1バイトの色番号を、渡した256セルのパレットで写す（`src/core/graphics_images.zig` の `drawIndexed`）。画像は24ビット色なので、行ごとにパレットを変えて何回かに分けて写せば、画像全体では256色を超える色を置ける。SNES（32768色）やAmigaのHAMのように、1行の中で256色を超える合成の結果を渡すには、メモリ上のRGBの並びを一括で写す語のほうが速い見込みである（未測定）。色の復号（SNESの15ビット色、HAM）はForthの側に置く。

未決の点：1画素の形（セルか、3バイトか4バイトか）とバイトの順、行の間隔、範囲の検査と切取り、透明色・反転・拡大（`IMAGE-SCALE`）を効かせるか。語は呼出しの間に写し終える。

### 実装（1000、2026-11-22）

利用者が上の未決の点を決め、`GFX-RGB ( addr w h stride x y key -- )`を本体に足した（`src/core/graphics_images.zig`の`drawRgb`）。

| 点 | 決定 |
| --- | --- |
| 1画素の形 | 4バイト。`L!`が書き込む形（下位のバイトが先）の32ビットで、下位24ビットが色`$RRGGBB`。4バイト目は使わない。本体の画像と同じ形なので、変換なしで写せる |
| 行の間隔 | `stride`（バイト数）で渡す。0はw×4を表す。w×4より小さい数と負の数は-24 |
| 範囲の検査と切取り | `GFX-INDEXED`と同じ。メモリは絵の全体を先に検査し（外なら-9）、描画先の画像からはみ出た部分は描かない |
| 透明色・反転・拡大 | 透明色（`key`、負ならなし）だけを持つ。反転と拡大は持たない |
| ゲームの語彙の包む語 | 足さない。`GFX-RGB`だけにする |

- 実行制限：描く画素256個につき1単位を、画素を書く前にまとめて数える（`checkWorkBlock`）。制限に当たった場合は1画素も書かない。
- 基本語`gfx_rgb`は`Builtin`の最後に、`GFX-RGB`は`GFX-`の語の並びの最後に足した。前からある語の実行トークンは変わらない。
- 確認：`zig build test`（`src/tests/graphics_test.zig`の「GFX-RGB draws colors of four bytes each from memory」を含む）、`-Dgraphics=false`の`zig build test`、`-Dfloat=false`の`zig build`、`word-reference.py --check`、`check-docs.py`（指摘0件）がWindowsで成功した。LinuxはWSL（1324）で、macOSは1294（2026-11-23、macOS 27.2.1 arm64）で`zig build test`と12節の背景試作の照合が成功した（macOSの照合値はWindowsと同じ。[記録](measurements/2026-11-23-background-prototype-macos.json)。時間は測っていない）。
- 速度は12節の「背景1画面の試作と測定」で測った。256×240の1画面を写すのに、`GFX-RGB`は24.63 µs、`GFX-INDEXED`の1回は24.59 µs、`GFX-INDEXED`を行ごとに呼ぶと43.24 µsだった（Windows）。

## 12. 描画の補助（1001、段階C）

1画素ずつメモリへ書くだけの処理が約2 ms/フレームだった。背景・スプライト・優先順位の合成はこれより重い見込みである（見積もり。未測定）。タイル1行の描画や、ビットプレーンから色番号への変換を本体に置く候補である。企画書の区分と同じく、まずForthで書いて速度を測り、足りない部分だけを本体に移す。

本体に置くのは、入力の形が決まっていて、測って効果を確かめた、機種によらない変換までとする。機種ごとの優先順位と走査線ごとの動作はForthの側に置く。

### 背景1画面の試作と測定（1001、2026-11-22）

NESに似せた背景1画面（256×240、32×30タイル、ビットプレーン2枚、属性バイトでパレットを選ぶ。スクロールとスプライトはない）をForthで書き、復号と画像への転送を分けて測った。Windows 11（AMD Ryzen 7 7700）、`-Doptimize=fast -Dcpu=baseline`の実行ファイル、利用者がほかのアプリを止めたあと。各負荷を別のプロセスで7回、順番を回して実行し、語の実行だけの時間の中央値を取った。バッファと画像の内容は、Pythonで別に書いた計算と毎回一致した。ウィンドウへの表示（`SHOW`）は含まない。値とソースは[測定記録](measurements/2026-11-22-background-prototype-windows.json)にある。

| 負荷 | 内容 | 1画面 | 60 Hzの1コマに占める割合 |
| --- | --- | ---: | ---: |
| naive8 | 1画素ずつ色番号のバイトへ復号する | 4276.55 µs | 25.66% |
| fast8 | 256セルの表を使い、8画素を1回のセルの書込みで復号する | 691.38 µs | 4.15% |
| to32 | 色番号をパレットで32ビットの色へ直す（1画素ずつ） | 1969.00 µs | 11.81% |
| put_indexed | `GFX-INDEXED`で1画面を1回で写す | 24.59 µs | 0.15% |
| put_rgb | `GFX-RGB`で1画面を1回で写す | 24.63 µs | 0.15% |
| put_rows | `GFX-INDEXED`を1行ごとに呼ぶ（行ごとにパレット） | 43.24 µs | 0.26% |

- 画像への転送は、どの方法でも1コマの0.3%以下である。`GFX-RGB`と`GFX-INDEXED`の1回の転送は同じ速さで、行ごとに`GFX-INDEXED`を呼んでも43 µsである。`GFX-RGB`の利点は速さではなく、1行に256色を超える絵を1回で写せることにある。
- 時間がかかるのは、Forthで1画素ずつ行う処理である。1画素ずつの復号は1コマの約26%、色番号から32ビットの色への変換は約12%かかる。
- 8画素を1セルにまとめる書き方（ビットプレーンの1バイトを8バイトに広げた表を引き、足し合わせて`!`で書く）にすると、復号は1コマの約4%になる。色番号のまま`GFX-INDEXED`で写せば、色への変換は本体が行う。
- この背景については、Forthの書き方で足り、本体に置く処理は見つからなかった。スプライト、優先順位の合成、4枚以上のビットプレーン（Atari ST、Amiga、SNES）は測っていない。

決定（利用者、2026-11-22）：1001はこの測定で完了とする。測った範囲では本体に置く処理はない。スプライト、優先順位の合成、4枚以上のビットプレーンは、エミュレータの描画をForthで書いて不足が出たときに、機種によらない入力の形を決めてタスクを足す。

当時の未決の点：どの処理を本体に置くか（NESとAtari STをForthで書いた後に決める）。SNESとAmigaは、実機と同じ速度で全部の機能を動かす場合、描画の補助を足しても実時間に届かない見込みである（見積もり。未測定）。CPUコアを本体に置くか、VMの速度を上げるかは、ここでは決めない。

## 既存の項目に足すこと

- **共通の取り決め（900）**：資源の持ち主の表に、ウィンドウのスレッドのキーの状態、音のスレッドのPCMのキュー、音源へのコマンドのキューを加える。キューの容量、辞書イメージに含めない状態、語群の依存（物理キーはgraphics、PCMはaudio）にも加える。
- **単調時計の語（段階A）**：60 Hzの1フレームは約16.67 msで、`FRAME` のミリ秒の整数では合わない（`FRAME` は `UTIME` を使い、待つ時間をミリ秒に切り捨てる。`src/graphics/graphics.fs`）。分解能をマイクロ秒以下にする。時計を読めるだけでは待機の精度は上がらないので、900で、絶対の時刻を期限とする待機、待機の精度を保証する範囲、時計の幅と一周したときの扱いを決める。フレームの周期は機種ごとの値を分数で持ち、端数を積み上げて進める処理はForthの側に書く。
- **実行制御（652）**：エミュレータのCPUのループは、数える実行ループの速度の低下を測る対象に加える。項目11と12で足す大きな転送と変換のループは、数える対象に入れる（`checkWorkBlock`）。いまの `drawIndexed` のループは数えていない。

## Codexのレビューの反映（2026-11-18）

項目8〜12の節をCodex（codex-cli 0.169.0、読み取り専用）にレビューしてもらい、指摘10件をソースと照合してから反映した。Codexはビルド、テスト、速度の測定をしていない。大枠（物理キーをGRAPHICSの別の語にする、PCMを900・639とそろえて段階Bに置く、描画の補助は測ってから選ぶ）は妥当という評価だった。

| # | 重要度 | 指摘 | 照合の結果 | 反映 |
|---|---|---|---|---|
| 1 | 高 | 項目10は、レジスタを書く語を足すだけでは済まない | SID・NES・Paulaの合成はMMLの音符と音色を受ける作りだった（`sound_c64.zig`、`sound_nes.zig`、`sound_amiga.zig` の冒頭の説明と `noteOn`） | 項目10を書き直し、足りないものと3つの候補を挙げた。現状の一覧も直した |
| 2 | 高 | 「10〜12は待機も資源も持たない」は項目10に当てはまらない | `SOUND` は64個のコマンドのキューを通し、満杯なら待つ。コマンドは `render` の先頭でまとめて反映する | 項目10を900の対象にした。「進める順序」の独立の記述を11と12だけにした。tque 999に900への依存を足した |
| 3 | 中 | `KEY-HELD?` の16個を超えたときの扱いは、#909で採用済み | `docs/NATIVE_WINDOW_STUDY.md` の10.10節に「16を維持し、満杯なら最も古いものを外す」とある。コアも同じ処理 | 256キーの表は物理キー専用とし、`KEY-HELD?` は変えないと書いた。現状の一覧を「ASCIIの1バイトの文字と特殊キー」に直した |
| 4 | 高 | 状態の差から解放を作るだけでは、押下と解放の履歴を保証できない | Windowsは押下のキューを先に返し、その後に状態の差から解放を返す（`host_window.zig` の `poll`）。#909も解放の通知と状態の同期を区別している | 押下と解放はキューに入れ、状態の差は復旧に使う形にした。あふれの知らせ方と再同期を契約に加えた |
| 5 | 中 | USB HIDの番号の範囲と、ホスト側の作業を限定して書く | ホスト共通のイベントは物理キーの番号を持たない。Windowsは仮想キーと文字、macOSはkeyCodeを文字に結び付けている | ページ0x07の0〜255と書き、対応の取れないキーの扱いと、ホスト側で調べる点を足した |
| 6 | 高 | PCMは既存のスレッドに載るが、既存の標本の領域は使い回せない | `sound_pcm.zig` の領域は末尾に足すだけの作り。`Ring` は生産者1つ・消費者1つ | 専用の有界のリング、フレーム単位、周波数の変換、空になったときの扱いを足した |
| 7 | 中 | キューの残量だけでは、再生位置と全体の遅れは分からない。中断のときの扱いも要る | 出力は48 kHz・16ビット・ステレオで、10 msのバッファが8個。`wait` は中断を知らせるだけで、取り消すのは `PLAY` の側 | 残量と再生位置の区別、中断と停止の扱い、`AUDIO?` が偽のときの2つの場合を足した |
| 8 | 中 | 項目11の制約は、画像が256色なのではなく、1回の転送の色番号が256種類 | `drawIndexed` は呼出しごとに256セルのパレットで展開する。画像は24ビット色 | 項目11と現状の一覧を直した。行の間隔、バイトの順、範囲の検査を未決の点に足した |
| 9 | 中 | 単調時計には、分解能に加えて期限の待機と端数の扱いが要る | `FRAME` は `UTIME` を使い、待つ時間をミリ秒に切り捨てる | 「既存の項目に足すこと」の単調時計に、900で決める点とForthの側に書く点を足した |
| 10 | 中 | 項目12は、速度の比較の条件と、実行制御への追加が足りない | `drawIndexed` のループに `checkWorkBlock` はない | 測定の環境とソースの場所を記録し、見積もりと書き分けた。652に、新しいループを数える対象に入れる点を足した |

## 決定事項（2026-11-18）

次の3点を利用者が決定した（推奨案の採用）。

| # | 判断点 | 決定 | レビューの評価 |
|---|---|---|---|
| 1 | 物理キーの押下と解放のイベントの出し方 | `EKEY` に出さず、GRAPHICSの別の語で読む | 賛成（入力の取込みは共有し、`EKEY`・`INKEY` の読取りで物理キーのイベントが消えない規則を置く） |
| 2 | PCMストリームの段階 | 段階B。依存は900だけで、639の実装は待たない | 賛成（900の仕様が決まれば独立に実装できる） |
| 3 | 音源チップのレジスタ書込み | 本体に置かず、Forthで合成してPCMで流す形で始める。速度が足りなかった機種だけ、後から本体に移す | 近似の音源を操作する機能と、実機に合わせた音源を分けて採否を判断する、という指摘に沿う |

3により、項目10（999）は、Forthで書いた音源の速度を測るまで本体の作業を始めない。

同じ日に、語群の分け方も利用者が決定した。項目9と10はサウンド、項目8、11、12はグラフィックスの語群に入れ、どちらもビルドのときに切り離せるようにする。細部は[共通の取り決め](ASYNC_COMMON_RULES.md)の8節にある。

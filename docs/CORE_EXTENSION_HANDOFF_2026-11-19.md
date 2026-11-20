# 613 本体機能拡張の引継ぎ（2026-11-19）

## Linux実聴5件の完了（2026-11-20）

WSL Ubuntu26.04.1へpulseaudio-utilsを導入し、Linux静的musl版→pacat→WSLg PulseAudio RDPSink→Windows出力で、レモンがPCM全8項目、NES4声/DMC単独/混合、SID3声、Paula4声stereo/左右分離、YM2149デモ/noise/envelopeの計20caseを聞いて確認した。各音源の物理Ctrl+C後の停止・再再生はCATCH=-28、handle=0、REPLAY-OK handle=0、PCMはclose0/hello入力、全process code0。記録したunderrunはすべて0。最後にPulse sink-inputとpacat processが残らないことも確認した。[環境・全コマンド・実聴結果・ソース本文](measurements/2026-11-20-linux-audio-listening.json)。Linux実機ALSA装置の確認とは区別する。

1149/1151/1158/1156/1162と親1133/998/1132/1136/1137を完了。1138はtodo・auto80%、Mac1154はtodo。999は未完了・auto68%。今回のLinux記録は未コミット。以下のLinux未確認やAUDIO?=0は当時の状態。

## Linux PCM実聴1149と親998の完了（2026-11-20）

WSL Ubuntu26.04.1へpulseaudio-utilsと依存ライブラリを導入し、静的musl版Sigmaのpacat pipe経由でWSLg PulseAudio RDPSinkへ出力した。AUDIO?=-1を確認し、レモンがmono/stereo左右・MML/SFX混合・破棄と再開・drain後停止・保存アプリ・物理Ctrl+C後の停止とhello入力の全8項目を実聴してＯＫと回答。case1〜7のunderrun0、case8はCATCH=-28/CLOSE=0、全process code0。1149・1133・998を完了した。[環境・コマンド・実聴記録](measurements/2026-11-20-linux-audio-listening.json)。これはWSL/Linux実行体からPulseAudioを経た実出力の確認で、Linux実機のALSA装置確認とは区別する。以降のLinux未確認・AUDIO?=0は当時の記録。

## 今回のコミット対象（2026-11-20）

YM2149のForthモデル・native固定音量0修正と検証/測定、PCM語群除外の再確認1159/1160、Windows実聴1148/1150/1157/1155/1161の受け入れ記録を含む。Linux実聴1149/1151/1158/1156/1162とYM2149のMac1154は未完了のまま各機能配下に残す。以下は作業時点の履歴であり、未コミット等の記述も当時の状態。

## WindowsのPaula/YM2149実聴1155・1161完了（2026-11-20）

レモンがPaula4声stereo・左だけ/右だけ、YM2149デモ・noise単独/envelope音量変化を実聴し、両例の物理Ctrl+C後の停止と再再生を確認した。CATCH=-28、handle=0、REPLAY-OK handle=0、code0、記録したunderrun0を保存し1155/1161を完了。[Paula](PAULA_FORTH.md)、[YM2149](YM2149_FORTH.md)、[全生データ](measurements/2026-11-20-paula-ym-windows-listening.json)。Linux1156/1162、YMのMac1154は未完了。親1137は未完了・auto80%、1138は未完了・auto60%、999は未完了・auto57%。今回コミット/プッシュは行っていない。

## YM2149のOS別実聴タスク追加（2026-11-20）

1138直下にWindows1161・Linux1162を追加し、1153へ依存させた。両方未完了・0%。3声/ノイズ/envelopeの実聴、Ctrl+C後の停止・再再生とhandle解放、OS/版/装置を確認する。Mac1154も維持し、親1138は未完了・auto40%。[確認範囲](YM2149_FORTH.md)。末尾の統合タスクへ移さない。

## WindowsのNES/SID実聴1150・1157完了（2026-11-20）

レモンがNES4声・DMC単独・4声＋DMC、SID3声を実聴し、両例の物理Ctrl+C後の停止と再再生を確認。CATCH=-28、handle=0、REPLAY-OK handle=0、underrun0、code0を保存し1150/1157を完了した。[NESの記録](NES_DMC_FORTH.md)、[SIDの記録](SID_FORTH.md)、[原データ](measurements/2026-11-20-nes-sid-windows-listening.json)。Linux実聴1151/1158が未完了のため親1132/1136はともに未完了・auto80%。999は未完了・auto55%。機能ごとの確認を末尾へ集約しない。今回コミット/プッシュは行っていない。

## Windows実聴1148の受け入れ完了（2026-11-20）

レモンがWindows実装置で8項目を順番に聞き、各項目をokで確認した。48000Hz mono、22050Hz stereo左右、MML/SFXとの混合、破棄と再open、drain後の停止、SAVESYS保存アプリの2音を確認。最後は前面のPowerShellで物理Ctrl+Cを押し、CATCH=-28/CLOSE=0、続くhelloのACCEPTとcode0を記録し、中断後の音の停止も追加確認した。case1〜7のUNDERRUNSはすべて0。Windows11 Pro 10.0.26300、waveOut既定出力（個別endpoint表示名は未取得）。[全実行記録と利用者の確認](measurements/2026-11-20-pcm-windows-listening.json)。

1148を完了。Linux1149は未完了・0%、1133は未完了・auto50%、998は未完了・auto94%。現WSLはAUDIO?=0のため、Linuxの実聴成功とは扱わない。以下の「Windows実聴未確認」はこの受け入れ以前の履歴。

## PCM998の再確認と実聴準備（2026-11-20）

Windows1159/Linux1160の語群除外再確認を完了し998は未完了・auto88%。旧[DEFINED]の0 0を除外の証拠とした部分は撤回。実行したREQUIRE-AUDIOをCATCHで捕捉して無効版-275、有効版でAUDIO内のPCM語を確認し、元の16構成と新4実行体で成功した。残件は1133配下の実聴1148/1149。[現在の検査記録](PCM_PUBLIC_IMPLEMENTATION.md)、[実聴の手順と8項目](PCM_LISTENING_ACCEPTANCE.md)。スクリプト既定は無音。現WSLはAUDIO?=0で音声client library未導入、実聴成功とは扱わない。YM2149の未コミット差分は保持する。

## 現在状態：Atari ST YM2149の実装・Windows/Linux検証（2026-11-20）

基点mainはcf080b4（Paulaまでpush済み）。今回のYM2149差分は未コミット。1152（監査と実装）・1153（Windows/Linux検証と測定）を完了し、Mac1154を1138の子に残した。1138は未完了・auto66%、999はauto49%。PaulaのMac1147は完了し、Windows実聴1155/Linux実聴1156が未完了のためPaula1137はtodo・auto60%。Macの確認まで親タスクの完了とはしない。以下は各作業時点の履歴で、この節を優先する。

[YM2149の契約・資料・結果](YM2149_FORTH.md)、[レビュー評価](reviews/1138-review-response.md)、[全測定・ソース本文](measurements/2026-11-20-ym2149.json)を参照。3声/noise/全16envelope、時刻指定、raw読取り、2つのI/O latchとFF8800/FF8802のbyte busをForthに追加した。既存native YMの固定音量0が微小出力になる問題も修正し、非ゼロ固定音量・envelope level1と停止後のfilter tailを保持する回帰検査を追加した。Builtin/ABIは追加しない。

両OSの通常・debug/graphics/extension除外・さらにfloat除外の6構成で各11検査群と補助12検査が成功。audio除外の2構成でも全512frame/状態が一致。全8実行体はnative修正後の新ビルド。native Windows全体検査成功、Linux core1126成功/10skip、host167成功/17skip、失敗0。通常負荷は実時間比Windows9.532倍/Linux11.431倍、全period1は3.212/3.834倍。各6負荷32768frameの全PCM/状態と、各7計時の最終37状態を独立Pythonと照合した。辞書HERE増加25152byte、通常実行体はPCM1128保存済み版比Windows+512/Linux+48byte。最終ClaudeレビューはHigh/Mediumなし。

Mac1154では新ビルドのnative fixed-zero回帰・core/host検査、Forth通常/除外構成・サイズ/速度と生成音の実聴・中断/資源回収を確認する。Windows/Linuxのfixtureは実聴を証明しない。次は1139で8対象の既存音源経路と不足を照合し、追加不要の根拠または必要な機種別タスクを記録する。1140の最終採否は各機能のMac確認を含む依存が済むまで完了にしない。

## 最新追記：PaulaのMac実機受け入れ1147（2026-11-20）

この節を最新状態とする。基点main `cf080b4`。macOS 27.2.1 / Apple M5で1147を実施し合格、tqueの1147を完了にした。各音源のWindows/Linux実聴を機能ごとの子へ移した（NES1150/1151→1132、SID1157/1158→1136、Paula1155/1156→1137）ため、親1132/1136/1137は未完了。合成中のCtrl+CをEXEC-LIMITEDで捕捉する例の修正は、合成が約2.8倍遅くなるため取り消し、文書に記載した。3構成の全検査がWindowsと一致し、Ghosttyで4声stereo・左右の分離・Ctrl+C中断と再再生を実聴で確認した。結果は[Paulaの記録](PAULA_FORTH.md#mac実機受け入れ1147)。

## 現在状態：Mac受け入れ結果の取り込み（2026-11-20）

mainは9baef92（NES/DMC・SIDのMac受け入れ記録まで取り込み済み）。1144/1143と親1132/1136は完了。Paulaの1145/1146は完了、Mac1147と親1137は未完了（auto66%）のまま。999はauto52%。未コミットのPaula実装・測定・タスク配置の文書は保全した。以下の節は各作業時点の記録であり、Mac未確認や古い進捗表示は、この現在状態と各Mac受け入れ節を優先する。

## 最新追記：NES/SID音源例のMac実機受け入れ1144/1143（2026-11-20）

この節を最新状態とする。基点main `1f1a67c`。macOS 27.2.1 / Apple M5で1144（NES APU/DMC）と1143（SID）を実施し合格した。tqueの1144・1143を完了にした（親1132・1136は後に実聴の子を移したため未完了）。全検査がWindows/Linuxの記録と一致し、Ghosttyで実聴とCtrl+C中断・再再生を確認した。結果は[NES](NES_DMC_FORTH.md#mac実機受け入れ1144)、[SID](SID_FORTH.md#mac実機受け入れ1143)。合成中のCtrl+CはOS終了になる（既存規則、20回中7回）。Windows/Linuxの実聴はNES 1150/1151、SID 1157/1158で未確認。

## 最新追記：Paulaの実装・Windows/Linux確認、Mac未完了（2026-11-20）

Paula実装時のmainは1f1a67c（SIDまでpush済み）。今回のPaulaとタスク配置修正の文書は未コミット。1145のレジスタモデルと1146のWindows/Linux検証・測定を完了した。Mac受け入れ1147は1137の子で未完了に残し、親1137は未完了・auto66%。Macの確認までタスク全体の完了とはしない。999はauto42%（子タスクの均等平均）。

[契約・資料・検証と測定](PAULA_FORTH.md)、[レビュー評価と原文](reviews/1137-review-response.md)、[生データ・コマンド・ソース本文](measurements/2026-11-20-paula.json)を参照。4声stereo、DMA/手動DATの1word保持、IRQ、attachと予定書込みをForthに追加。Agnusのslot/CPU/Copper競合・IRQ pipeline、analog/LEDfilter・実機/ROM互換はモデルに含めない。既存AMIGA-SOUND/Builtinは変更しない。

Windows/Linuxの通常・debug/graphics/extension除外・さらにfloat除外の6構成で各10検査群と補助10検査が成功。全256attach mask、全128volume値、512KiB全memory、固定PCM、6負荷の全32768frameを照合した。stereo部分書込みは実装置を開かないfixtureで非ゼロデータの4byte offset/全byteコピーを検証し、oddLEN3の位相resetも手計算・負の対照で補った。最終ClaudeレビューはHigh/Mediumなし。実聴成功とは区別する。

通常まとめ版はWindows約9.44倍、Linux約10.46倍、変調負荷は約5.52/6.44倍。音源単独の宣言範囲をForthで維持する採否で、Amiga全体の性能ではない。辞書増加549616byte（512KiB memoryと24KiB queueが中心）、本体実行ファイルの増加0。再開時はGit/tqueとJSONのLF指紋を照合する。

Mac側は1147でverify-paula.py/verify-paula-stream.pyの通常/除外・全PCM照合、サイズと速度、生成音のstereo実聴・中断と回収を実施し、OS/CPU/版と結果を記録する。既存PCMのMac1130完了とは別。PCM実聴は998→1133→Windows1148/Linux1149、SID/NESのMacは1136→1143/1132→1144に残す。次の実装はAtari ST1138の既存レジスタ経路の充足・不足監査。以下は各時点の履歴。

PCM実聴1133は、Windows1148とLinux1149の子タスクに分割した。両方とも未完了・0%。OSごとに実装置の確認と実聴結果を記録し、両方が済むまで親1133を完了にしない。

## 最新追記：実機確認を各機能の配下へ移動（2026-11-20）

利用者の「最後にまとめないで」に従い、1057の末尾へ集約していた未確認を移動した。1133（Windows/Linux PCM実聴）は998 PCM配下、1143（Mac SID）は1136 SID配下、1144（Mac NES APU/DMC）は1132 NES配下で管理する。確認を残す親998/1136/1132は未完了へ戻し、実装・検証済みの子タスクは完了を維持した。依存先は完了済みの実装・受け入れ項目へ付け替え、子から親への循環依存を避けた。

現在は998=auto85%、1136=auto66%、1132=auto66%、999=auto33%。均等平均であり、実装を取り消した意味ではない。3件は着手可能で、他機種の実装を待つ条件はない。Mac確認を残して次の実装へ進めることと、確認自体を最後の工程へ移すことは区別する。以下の1136/1132/998完了や999=42%等は、確認タスクを各機能へ戻す前の記録。

## 最新追記：SID1136の決定的モデル・実測・採否完了（2026-11-20）

mainは8eff166（NES/DMCと対象修正までpush済み）。今回のSID差分は未コミット。1141/1142/1136を完了し、999は7枝の均等平均auto42%になった。6581/8580のアナログ再現やROM互換の完了ではない。既存C64-SOUND/Builtinを変更せず、宣言したレジスタ/ADSR/波形・時刻指定と独自Q16フィルターをForthで維持する。

[SIDの契約・制限・実測](SID_FORTH.md)、[レビュー評価と原文](reviews/1136-review-response.md)、[全測定・ソース本文](measurements/2026-11-20-sid.json)を参照。Windows/Linuxの通常・debug/graphics/extension除外・floatも除外した6構成で各12検査群成功。5負荷すべて32768frameの全PCM/終了状態をPythonと照合し、7processずつ測定した。最終ClaudeレビューはHigh/Mediumなし。Windows通常約2.53倍、重い混在約1.03倍。単独音源でも余裕が小さく、C64全体の実時間性を立証していない。辞書増加41688byte、本体実行ファイルの増加0。

Mac上のSID例、生成波形の実聴、実機/ROM照合は未確認として残す。既存PCMのMac1130は完了済み。次はAmiga Paula1137の再現範囲・DMA/IRQ契約を資料と照合し、既存近似を調べてForth側の試作へ進む。Atari ST1138、対象一覧の先行照合1139、依存付き最終採否1140も未完了。以下の28%等とSID未着手は各時点の履歴。

## 最新追記：DMCと5声モデル・採否1135/1132完了（2026-11-20）

mainは816129a（汎用試作までpush済み）。4声/DMC・対象一覧修正の今回の差分は未コミット。DMCのreader/buffer/DAC/loop/IRQ、専用32KB map、非線形5声混合と8kHz直接DACをForth側に追加し、1135とNES1132のモデル・実測・採否を完了した。定義したzero DMA-delayのAPU単独の範囲はForthに維持する。CPU/PPUや実機DMA/bus競合、ROM互換を完了した意味ではない。

[現行5声の契約・結果](NES_DMC_FORTH.md)、[レビュー採否](reviews/1135-review-response.md)、[全測定・ソース指紋](measurements/2026-11-20-nes-dmc.json)を参照。Windows/Linuxの通常/除外の4構成で回帰12+DMC8検査群が成功し、最終ClaudeレビューはHigh/Mediumなし。旧1134の生データは変更せず、当時のソース本文と固定出力SHAを保存した。Mac上の新しいNES例と生成波形の実聴は未確認。既存PCMのMac1130は完了済み。

999は7枝のauto28%。共通1131とNES1132が100、SID1136/Paula1137/ST1138/先行照合1139/最終採否1140は0で、工数比ではない。最終1140は機種別作業と照合に依存する。不足を見つけたら子タスクと1140の依存へ追加する。次はSID1136の資料・再現範囲の確定と実装/実測、または先行照合1139を進める。以下の21%/25%とDMC未着手は各時点の履歴。

## 最新追記：DMC実装・対象一覧の完了条件（2026-11-20、作業中）

NES DMC1135を実装・検証中。5声の現行契約は[NES DMCの記録](NES_DMC_FORTH.md)を参照。旧4声の拒否契約や測定は1134時点の履歴としてソース本文とともに保持する。

1139を先行照合、1140を最終採否へ分離した。1140はNES1132/SID1136/Paula1137/ST1138/照合1139に依存し、先に完了できない。不足が見つかれば機種別タスクと1140の依存へ追加し、分母が増えると均等平均の表示が下がる場合もある。現在999は7枝のauto21%で、DMC工程はまだ完了にしていない。以下の25%/6枝は1140追加前の履歴。

## 最新追記：音源の対象漏れ・進捗の修正（2026-11-20）

NESを最初に進める指示は、他機種を対象外にする決定ではない。999にC64 SID1136・Amiga Paula1137・Atari ST YM2149の充足/不足確認1138、および上位計画8機種の照合1139を追加した。SID/Paulaはレジスタ対応Forth実装・実測が未着手。Atari STには既存ST-SOUND/SOUNDのYM2149レジスタ経路があり、不足を監査して必要部分を進める。機種別一覧は[計画の対象表](EMULATOR_CORE_PLAN.md#音源の対象と現在状態999)を参照。

999はauto25%。共通試作1131=100、NES1132=50、SID1136/Paula1137/ST1138/対象照合1139=0の6枝を均等平均した表示で、工数や対応機種数の達成率ではない。旧75%はSID等が未登録だった時点の値で、現在進捗として扱わない。NESの測定結果から他機種の本体移行の採否を決めない。下の工程記録は各時点の履歴。

## 最新追記：NES APUのForth 4声試作1134（2026-11-20）

現在のmainは816129a（汎用合成1131までcommit/push済み）。利用者がNES APUを最初の機種に指定し、NTSC 4声のレジスタモデルと予定書込み、frame IRQ、まとめ処理をForth側に追加した。今回の差分は未コミット。1134完了、1132は50%。対象漏れ修正後の999は25%（子タスクの均等平均）。次は1135のDMCと残る互換性・負荷再測定。既存PCMのMac1130はdde0547で完了済みで、今回のNES例のMac実行は未確認。

[仕様・資料・測定と採否](NES_APU_FORTH.md)、[レビュー採否](reviews/1134-review-response.md)、[原データ](measurements/2026-11-20-nes-apu.json)を参照。4構成各12検査群が成功。1クロック版/まとめ処理版/Pythonの出力・状態を照合し、累計1024件で止まった予定表を未処理1024件と領域回収へ直した。Claudeの実装・文書再レビューまで反映し、High/Mediumの残件なし。

定義したNTSC 4声の範囲はForthに維持し、本体への追加は行わない。DMC/DMA、CPU/PPUの実行やバス競合、実機/ROM互換、生成波形の実聴、analog filteringは未確認・未実装として分ける。この結果をNES全体の実時間性能と扱わない。再開時はGit/tqueとJSONのソース指紋を照合する。以下は各時点の履歴。

## 最新追記：PCMのMac実機受け入れ1130（2026-11-20）

この節を最新状態とする。基点main `9d1c528`。macOS 27.2.1 / Apple M5でPCM06（1130）を実施し合格した。tqueの1130と親998を完了にした。core1124成功・host152成功、11構成、専用PTY、AudioQueue実装置での1000回開閉（fd/thread不変）・再生中終了50回、Ghosttyでの実聴（単独・左右・混合・破棄と再開・drain・保存アプリ）とCtrl+C中断を確認した。結果は[実装記録](PCM_PUBLIC_IMPLEMENTATION.md#mac実機受け入れ1130)。以下の「Mac実機1130は未完了」は当時の記録。LinuxのPulseAudio/ALSA実装置とWindowsの実聴は未確認のまま（tque 1133）。

## Forth音源の先行試作1131（2026-11-20、Mac受け入れ統合前の記録）

現在のmainは9d1c528（PCM公開語/host寿命/Windows/Linux確認までcommit/push済み）。その後999の先行子1131として、独自4声のForth合成・PCM送出例と検証/測定を追加した。今回の差分は未コミット。Mac実機1130は未完了で残す。

1131完了、999は50%。次は1132の機種別Forth音源・実測と採否判断。今回の汎用試作をNES/SID/Paulaの再現や本体移行不要の証拠とは扱わない。[試作仕様と結果](PCM_SYNTH_PROTOTYPE.md)、[Claude採否](reviews/1131-review-response.md)、[生データ](measurements/2026-11-20-pcm-synth.json)を参照。通常/除外のWindows/Linux各18検査群が成功。ClaudeのMedium試験不足2件を補強し、再レビューは解決済み・新しいHigh/Mediumなし。可聴確認はしていない。

999の着手依存は利用者の「Macを残して進める」指示に合わせ、1064と完了済み1129へ変更した。998全体と1130は完了にしていない。再開時はGit/tqueとJSONのソース指紋を照合する。以下は各時点の履歴。

## PCM公開語・Windows/Linux自動確認（2026-11-20）

この節を最新状態とする。基点mainは416caf9（PCM設計/内部までpush済み）。その後1127・1128・1129を実装/自動検証し、差分は未コミット。1128/1129はtque完了、親998は83%。Mac実機1130は未完了で残す。保存アプリのMac受け入れ1124/1069/1066はc822e53で統合済み。

[PCM公開語の実装・検証記録](PCM_PUBLIC_IMPLEMENTATION.md)、[Claudeレビュー採否](reviews/1128-review-response.md)、[測定一次データ](measurements/2026-11-20-pcm-public.json)を参照。7公開語、State所有、CLOSE中断時の再試行、完全復元busy/辞書追記保持、英日HELPを実装した。Claude最終静的レビューはHigh/Mediumなし。Windows/Linuxの22構成、専用console/PTY入力保持、core各1124成功、host162/167成功、zig build test、全参考書の照合が成功。可聴音・Linux実音声装置・Mac実機は未確認。

再開時はGit/tqueと最新JSONのソース指紋を照合する。以下の「未実装」「次は1128」等は各時点の履歴。次のMac受け入れは1130のタイトルと親998を再照合して進める。

## 最新追記：音声ホスト停止・回収1127（2026-11-20）

この節を最新状態とする。PCM設計/内部リングはmain `416caf9`でcommit/push済み。その後1127を実装し、host関連の差分は未コミット。今回の後続実装はまだcommit/pushしていない。

- 1127完了、998はauto50%。次は1128（公開語・PCM storage/owner/handle・画像busy/append・英日HELP）。1129 Windows/LinuxのPCM受け入れと1130 Mac実機は未完了。保存アプリ1124/1069/1066のMac受け入れはc822e53で統合済み。
- [1127の実装・検証](PCM_HOST_LIFETIME_IMPLEMENTATION.md)、[レビュー採否](reviews/1127-review-response.md)、[原データ/ソース指紋](measurements/2026-11-20-audio-lifetime.json)を参照。Claudeの指摘を修正し、最後の限定再レビューは対象に高・中の指摘なし。
- 音声threadのstop/join、device/callback終了、libraryはjoin後unload、pool freeを実装。未停止時は領域を保持し再start拒否。通常deferとflush後に専用hard exitでstatus1。時計故障・初期化途中・一時的/恒久的cleanup失敗も照合。
- Windows host160成功15除外、Linux host165成功17除外、graphics/audio/extension/debug全除外host158成功15除外、全失敗0。Windows zig build test成功。別プロセスの阻害fixtureはWindows/Linux各3回status1。実waveOut20回/途中open、Linux pipe EOF/TERM/KILL・ALSA差替え・native資源数を確認。Macはhost/fixture cross compileのみ。
- Windows通常/THROW/保存アプリからのaudio起動を確認。Linux GNUは装置なしsilentで終了。**Linux Pulse/ALSA実装置、実際に聞く音、Mac実機は未確認。** 公開PCM語・stream Frameのhost確保は1128で未実装なので、PCMアプリが使えると報告しない。

再開時はGit/tqueと最新JSONのLF正規化ソース指紋を照合する。1128は採用設計のms/中断/closing再試行・同一processのhandle検査・完全復元busy/append保持を実装する。workerが残る間にState/runtimeやstream storageを参照させない。1130のMac実機を未完了で残して開発を続ける。

## 最新追記：保存アプリ起動のMac実機受け入れ（2026-11-20）

この節を最新状態とする。基点main `6512916`。macOS 27.2.1 / Apple M5 / Zig 0.17.1で1124を実施して合格し、tqueの1124・1069・1066を完了にした。生成実行体の公開試験（通常と10構成）、image除外、補助確認、Ghosttyでの実端末Ctrl+C（status1、その後のecho正常）を確認した。結果は[実装記録](SAVED_APPLICATION_STARTUP_IMPLEMENTATION.md#mac実機受け入れ1124)。下の節の「Mac実機1124（未確認）」は当時の記録。

## PCMの設計・内部リング（2026-11-20、Mac受け入れ統合前の記録）

以下は着手時点の記録。保存アプリMac1124は上のリモート受け入れ記録により完了。PCM自体のMac1130は別項目で未実施。

この節を最新状態とする。Git基点main `6512916`（保存アプリ起動・測定記録をcommit/push済み）。新しいPCM関連のソース/文書は未コミット。今回コミット・push・タグは行っていない。

- レモンの「Macの確認は残して次へ」により、保存アプリMac1124を未完了で保持し、段階BのPCM998へ進んだ。998を1125仕様、1126内部リング、1127host寿命、1128公開語/所有、1129 Windows/Linux、1130 Mac実機へ分割。1125/1126完了、998 auto33%。1130も未実行。
- [採用設計](PCM_STREAM_DESIGN.md)、[実装/試験記録](PCM_STREAM_IMPLEMENTATION.md)、[レビュー評価](reviews/998-review-response.md)、[ソースと実行結果の指紋](measurements/2026-11-20-pcm-internal.json)。Claude Codeへ設計・リング・限定再レビュー2回を読み取り専用で依頼。最終は高・中の指摘なし。
- sound_stream.zigとEngine.renderへ有界SPSC・s16LE mono/stereo・整数ZOH・skip持越し・飽和混合・制御ackを実装。sourceを借用せず、consumer参照終了後のackまで旧storageを保持する。drain尾部のunderrun抑制も追加。
- Windows Debug/ReleaseFast、Linux Debug core1113成功10除外。hostはWindows151成功12除外/Linux155成功15除外。graphics/audio/extension全除外core933成功190除外/host149成功12除外。全失敗0。zig build testに含まれるCortex-M0+の64bit atomic制約を検出し、内部counter/serialを32bitへ修正して成功。Macはcore/host cross compileのみ成功。
- **公開PCM語とhost storage/終了回収は未実装。** 現行host_audioはdetach/無限消費のままで、アプリからPCMを使えるとは報告しない。新しいBuiltin/画像ABI/語一覧の変更はない。実音や装置latencyを測定していない。

次は1127（host寿命）。採用設計のbackend別停止・join・途中open失敗回収を実装し、blocked Pulse writeで期限内に失敗を返して参照領域を保持すること、Windows反復handleとLinux pipe child/fdを検証する。その後1128を実装する。完全復元は適用前busy、append保持。CLOSEでringをfreeせずhost join後にfreeする。PCM全体998やMac1130を完了扱いにしない。

## 最新追記：保存アプリ起動基盤と測定記録（2026-11-20）

この節を最新状態とする。Git基点main `d9e88f2`、origin/mainとの差分コミットなし。サイズ/速度の記録と保存アプリ起動の実装・文書が未コミット。コミット・タグ・pushは行っていない。

- 保存アプリ1066は設計1067・実装1068を完了し、受け入れ1069をWindows/Linux1123（完了）とMac実機1124（未確認）へ分割した。親1066はauto83%、1069はauto50%。番号は再開時にタイトル・親子関係で照合する。
- APP-ENTRY! / APP-ENTRY@ / APP-ENTRY-OFF、保存実行体からの一度だけの自動起動、アプリ引数と--sigmaホストprefix、起動回避、rootの寿命/画像検査、SAVESYS原子的公開を実装。新Builtinにより画像ABIが変わる。既存画像はソースから保存し直す。
- Claude Codeへ設計・metadata・実装と限定再レビューを読み取り専用で依頼し、採否を別保存した。最終限定レビューは対象に高・中の具体的欠陥なし。POSIXのumask変更を除き、Windows drive-relativeのtempと診断準備順を整理した。
- Windows core1097成功10除外/host151成功12除外、Linux core1097成功10除外/host155成功15除外。22構成の生成実行体試験、専用console/PTYの中断、破損画像/自己別名/readonly/日本語pathを確認。Mac aarch64はcore/hostクロスコンパイルのみ成功。
- 全語1805・HELP1591・文書例28・個別例401、check-docs指摘0。[採用設計](SAVED_APPLICATION_STARTUP_DESIGN.md)、[実装・生値・Mac手順](SAVED_APPLICATION_STARTUP_IMPLEMENTATION.md)を参照。LOGOやタスク制御は実装していない。後続資源との結合は1057。
- [サイズ・速度記録](SIZE_SPEED_MEASUREMENT.md)は789420eの実測（Zig 0.17.1）で、今回の起動機能を含まない。前回11/17との比較・Windowsの大きなばらつきを記録済み。起動時間の参考値は別の起動実装記録に保存。

再開時はGit/tqueと`docs/measurements/2026-11-20-saved-startup.json`の指紋を確認する。Mac実機1124は上記の手順に従って実際に生成実行体を起動し、実端末Ctrl+Cも確認する。Windows/Linuxの成功やMacクロスコンパイルからMac実機受け入れ済みとはしない。

## 最新追記：640・646・652のMac実機受け入れ（2026-11-20）

この節を最新状態とする。基点main `789420e`。macOS 27.2.1 / Apple M5 / Zig 0.17.1で、1111（書記素）・1116（ファイルシステム）・1122（実行制御）のMac実機受け入れをすべて実施して合格した。tqueでは3件と親の640・646・652、1002を完了にした。
結果は[書記素](GRAPHEME_IMPLEMENTATION.md#mac実機受け入れ1111)、[ファイルシステム](FILESYSTEM_IMPLEMENTATION.md#mac実機受け入れ1116)、[実行制御](EXECUTION_CONTROL_IMPLEMENTATION.md#mac実機受け入れ1122)の各実装記録へ記載。1122の実端末操作は利用者が行い、Terminal.app・WezTerm・Ghosttyの貼付け動作を記録した。
macOSでは`verify-execution-control.py`のtermios比較がカーネルの`PENDIN`ビットで失敗していたため、比較から除くよう修正した。以下の節で「Mac実機を残す」とあるのは各時点の記録。


## 最新追記：652実行制御のWindows/Linux受け入れ、Mac実機を残す（2026-11-20）

この節を最新状態とする。Raw入力を捨てない方針と、満杯の後ろのCtrl+Cを検出できない場合がある制約をレモンが了承した。640/646のMac実機を残し、652を実装した。Git基点main `8f4a968`。640/646/652の変更は未コミットで、コミット・タグ・pushは行っていない。

- 652は1117仕様→1118コア/1119ホスト→1120 Windows/Linux/1121画像・文書/1122 Mac実機。1117〜1121を完了、652はauto83%。1122は未着手のままで652全体は未完了。640の1111、646の1116も未着手（640 auto75%、646 auto80%）。
- EXTENSIONかつdebugへ`EXEC-LIMITED ( i*x xt u -- j*x ior )`を追加。u=0は無制限の中断確認、正常0、自分の予算切れ-280。最大16段、外側予算も消費し、CLI・通常THROW・-28は外へ伝える。CATCH相当の深さだけ戻し、副作用の巻戻し・継続再開はしない。
- [採用設計](EXECUTION_CONTROL_DESIGN.md)、[実装・測定・検証記録](EXECUTION_CONTROL_IMPLEMENTATION.md)、[レビュー評価](reviews/652-review-response.md)、[Mac手順](EXECUTION_CONTROL_MAC_ACCEPTANCE.md)を参照する。
- 通常VM loop(false)本体には確認を追加せず、counted・有効入口内の解釈token・native hookを使う。signal所有をNS/audio/inputと共有。RawはPOSIX byte queue/Windows未デコードrecord ringに保持し、貼付け・UTF-8・特殊キー・未完成ESCを維持する。
- 実装レビューで見つかった未完成ESC直後のCtrl+C削除位置と、inner endの割込み早期消費を修正。大きな再生領域をstaticへ移動。debugなしの登録/HELP/画像復元も修正した。限定再レビューでは対象修正に高・中の具体的欠陥なし。原文・採否・採用設計を別保存。
- 最終Windows core1093成功10除外・host148成功12除外。Linux（graphics/audioなし）core938成功165除外・host138成功15除外。debugなし/extensionなしも失敗0件。native FAXPYの部分更新、画像保存除外・LOAD後の予算維持を確認。
- Windows private console/Linux PTYで文字・貼付けの3・ESC保持、Raw→KEYのBackspace、Raw→READ-FILEのUTF-8、NS/Cooked KEYと計算の中断、端末mode復元を確認。Windowsの満杯70文字保持とOS割込みも成功。ReleaseFastの公開語/consoleも成功。
- 確認間隔256/1024/4096を比較し1024を採用。CLI countedには基準より約10%の追加費用が観測されている。通常/入口/nativeの別表を実装記録へ残し、20ms保証とは扱わない。
- 実辞書1802項目、HELP1588項目、文書例28件・個別例398件を照合。check-docs指摘0、diff --check成功。Mac aarch64の代表構成はcore/hostクロスコンパイルのみ成功で実行はしていない。

再開時はGit/tqueのタイトルと親子関係、`.work/652/source-fingerprints.json`を再確認する。Mac実機の1111/1116/1122を残して次へ進める方針は継続するが、次の本体項目は着手前に現在の計画と依存を照合する。

## 最新追記：646のWindows/Linux受け入れ、Mac実機を残す（2026-11-20）

この節を最新状態とする。640のMac1111を残して646へ進む指示を受け、SYNCも含めることを確認した。
基点main `8f4a968`。640と646の差分は未コミットで、コミット・タグ・push・配布物作成は行っていない。

- 646は1112仕様→1113ホスト→1114コア/文書→1115 Windows/Linux、1114→1116 Mac実機。
  1112〜1115を完了し646はauto80%。1116は未着手で、646全体は未完了。640のMac1111も未着手。
- EXTENSIONへCOMPACT-FILENAME、FILE>REALPATH、FILE-METADATA、SYNC-FILEを追加。
  [採用設計](FILESYSTEM_DESIGN.md)、[実装・検証記録](FILESYSTEM_IMPLEMENTATION.md)、
  [レビュー評価](reviews/646-review-response.md)、[Mac手順](FILESYSTEM_MAC_ACCEPTANCE.md)を読む。
- COMPACTはGforth1.0.2の実測1,010例と一致し、8,003バイトでも成功。GPLソースを移植していない。
  実パスはhost所有結果を呼出し側bufferへコピーし、metadataは通常fileのサイズとUTC秒/nsを返す。
  SYNCは通常fileに限定し、C/OS同期を要求する。FLUSH-FILEやRENAME-FILEの意味は変えない。
- Windowsで書込み→読取り→SYNC後にNULが混じる問題を再現し、入力前のprepareFileReadを4経路へ接続して修正。
  読取り値・位置・内容、CR先読みの保留byteとEOF保持をWindows/Linuxで確認した。
- Windows通常23/23 step、Linux core1085成功10除外・host149成功14除外・runtime15成功。
  extension除外・代表files/graphics/audio除外、Windows fast、公開語9ケース群も成功。
  native1,000反復の資源数はWindows handle126→126、Linux fd5→5。open前device拒否10照会も成功。
- Macはaarch64向け14/14 stepクロスコンパイルだけ。実ネットワークshare・serial device・停電耐性は確認していない。
  Windowsでは負時刻を実測し、WSL作業領域は設定後もstatで0となったためLinux負時刻合格とは扱わない。
- 英日HELP・全語参照・マニュアル・試験手順を更新。実辞書1801項目、HELP1587項目、文書例28件・使用例397件を照合。
  check-docs指摘0件。設計・実装・限定再レビューの原文と採否を別保存している。

再開時はGitとtqueのタイトル・親子関係を取り直し、640/646の未コミット差分を保持する。
Mac実機を行うか、独立した次工程へ進むかはレモンの指示に従う。

## 最新追記：640のWindows/Linux受け入れ、Mac実機を残す（2026-11-20）

この節を最新状態とする。下の「640未着手」「次は640」は以前の記録。
基点main `8f4a968`。今回の640は未コミットで、コミット・タグ・pushは行っていない。

- 640を1108仕様→1109実装→1110 Windows/Linux、1109→1111 Mac実機へ分割。
  1108〜1110を完了し、640はauto75%。1111は未着手で、640全体は未完了。
- レモンの決定：書記素はUnicode18.0.0／UAX #29改訂49、表示幅は既存15.1.0を維持。
  前方のUTF-8検査は探索に必要な範囲へ限定する。
- EXTENSIONへX-GRAPHEMEとX-GRAPHEME-LASTを追加。結果はバイト数、空は0。
  前方はクラスタと境界判定用の次の1コードポイントまで、末尾は元の先頭から全文を走査。
  不正符号化は-24、領域外は-9。引数を保持して失敗する。
- Windows通常23/23 step、Linux core1082成功9除外・host148成功14除外・runtime15成功。
  公開語の公式853ケース／3,096項目はWindows・Linux・Windows fastで成功。
  公式適合試験を通常core単体にも組み込んだ。extension除外と代表的な他機能除外も試験。
- Macはaarch64向けクロスコンパイルだけ。実機は[1111の手順](GRAPHEME_MAC_ACCEPTANCE.md)へ残す。
- [採用設計](GRAPHEME_DESIGN.md)、[実装・検証記録](GRAPHEME_IMPLEMENTATION.md)、
  [レビュー評価](reviews/640-review-response.md)を参照。設計・実装・限定再レビューの原文を別保存。
  初回認証失敗の後、レモンの再認証でレビューを完了した。
- 公式入力・ライセンス・manifestをtests/data/unicode-18.0.0へ同梱し、txtのGit改行変換を抑止。
  製品には生成表だけを含める。check-docsは生成再現性と固定入力SHAも検査し指摘0件。

再開時はGitとtqueのタイトル・親子を再照合する。Mac実機で1111を完了するか、
独立した次工程へ進むかはレモンの指示に従う。番号だけでタスクを特定しない。

## 現在の引継ぎ：Mac検証の取込み後、次は640

2026-11-19、この節を最新情報とする。下の過去の追記にある「Mac未完了」「643は80%」「未コミット」や古いHEADは、各時点の履歴であり現在の状態ではない。今回の引継ぎではコード変更・ビルド・試験・tque変更は行っていない。現在のGit/tqueと、取り込んだ検証記録を照合した。

### 作業環境とGit

- 利用者はレモン、担当はロク。作業場所は`D:\home\source\zig\forthz`、PowerShell、Zig `0.17.1`。
- ブランチ`main`、HEAD `fa34ada`（Verify process management on macOS）。直前のpullはfast-forward成功。引継ぎ更新前の作業ツリーはクリーンで、ローカルの`origin/main`参照と一致していた。今回の引継ぎ作成では追加fetchは行っていない。
- `164fc6b`：非ブロッキングFILE I/O・PROC管理・Tcl移行・設計/レビュー/試験をまとめてコミットし、push済み。
- `afac042`：Mac実機で検出したprocess rollbackを修正。
- `fa34ada`：Macの受け入れ記録、OS差を扱う検証scriptを更新。
- 引継ぎ作成後、レモンからコミット・pushの追加指示を受けた。この最新節は、その指示による引継ぎコミットに含める。

### tqueの現在地

番号は振り直されることがある。再開時は番号だけでなくタイトル・親・依存関係も再照合する。

| タスク | 現在の状態 | 内容 |
| --- | --- | --- |
| 637 | 完了 | ターミナル制御 |
| 638 | 完了 | イベントキュー |
| 639 | 完了 | 非ブロッキングFILE I/O。Mac実機1092/1096も完了 |
| 643 | 完了 | 子プロセス管理。1097〜1107の関連工程とMac実機1101も完了 |
| 640 | 未着手 | Unicode書記素クラスタ。次の候補としてレモンへ案内済み。実装開始の指示はまだ受けていない |
| 646 | 未着手 | ファイルシステム。640と独立して着手可能 |
| 652 | 未着手 | debug構成の実行制御。通常ビルドのタスク制御1048とは分ける |

640/646の先行条件1056は完了。652の先行条件1056/1064も完了。親1002は未完了で、640/646/652が残る。1048配下の方式比較1049も未完了であり、PROC管理が完了したことをForthタスク制御全体の完了とは扱わない。

### 今回取り込んだMacの結果と変更

詳細は[FILE待機](FILE_INPUT_WAIT_IMPLEMENTATION.md)、[非ブロッキングI/O](ASYNC_IO_IMPLEMENTATION.md)、[子プロセス管理](PROCESS_MANAGEMENT_IMPLEMENTATION.md)を読む。Mac実行は、取り込んだコミット内の記録に基づく。Windows側でMac試験を再実行したものではない。

- macOS `27.2.1 arm64` / Zig `0.17.1`。PROCの通常試験はcore 1077成功・8除外、host 136成功・15除外、runtime/freestandingを含む23/23 step成功。
- native backendの16ケース、PROCの大量3stream・timeout/状態・終了259の再読、64同時起動と超過/再利用、SIGINT、Tcl内部枠/再起動/script削除/終了時子孫killをMacで確認。除外構成でも実行した。
- 639のFILE待機・読取り・書込み・stdin継承・方向切替・FILE ID再利用もMacで受け入れ済み。
- Macで`waitid(WNOWAIT)`が終了値259を返す差に対応し、POSIXの通常終了値を0..255へ正規化。group signalがEPERMとなるrollbackでは、所有する子PIDへのfallbackを追加した。
- 検証scriptの`prctl`・`/proc`依存をLinux限定にし、Macの資源/生存確認を追加した。
- Macの`.work/1101/mac`、`.work/1101/mac-excluded`、`.work/639-mac`はMac側の証拠の場所。Gitで取り込んだ本文記録と、このWindows checkoutに実在するログを混同しない。

**再開時の確認事項：** Windows/Linuxの既存成功記録は主に`164fc6b`時点。取り込んだ`afac042`のnative C修正について、このWindowsセッションではまだ再ビルド・再試験していない。640の実装へ進む前にdiffを読み、Windows通常試験とLinuxのprocess回帰（native・公開語・rollback）を確認する。引継ぎ時に新たな失敗を検出したという意味ではない。

### 実装上の分担と維持する契約

- 本体コア：optional host口、スタック/論理メモリの検査、EXTENSION語の登録。PROCはgraphicsに依存せず、files/extension無効またはhost未提供では-21。OS資源をVM Stateや保存画像へ足していない。
- host：process registry/設定/OS payload/終了結果。公開64枠とTcl内部予約1枠。WindowsはJobと継承3端点の許可リスト、POSIXはWNOWAITとPGID保持、最終FREEでreap。
- 公開pipeはFileSlot所有で639のFILE/WAIT/AVAILABLEと共有。`(proc所有者ID, FILE ID)`で再利用を照合し、別fileを誤って閉じない。
- Tclは共通registryへ移行済み。wish探索・一時script・privateプロトコル・display budgetはadapterに残す。close前にraw参照を外し、registry除去後にscriptを削除。Sigma終了はTclも含め全group/JobへKILLして共通期限で回収する。
- WRITE-AVAILABLEの受付は配送完了ではない。CLOSE-FILE/FLUSH-FILEは配送待ちになり得るため、子が先に大量出力する場合はstdout/stderrを並行して読み、入力の半閉じと調整する。
- native/PROC/Tcl fixtureの成功を、実wish/TkのGUI表示成功とは扱わない。Linux display budgetのnative socketケースには、socket directoryがなく除外したものがある。

設計とレビューは[PROCESS_MANAGEMENT_DESIGN.md](PROCESS_MANAGEMENT_DESIGN.md)、[643-review-response.md](reviews/643-review-response.md)、[643-tcl-claude-review.md](reviews/643-tcl-claude-review.md)。FILE側は[ASYNC_IO_DESIGN.md](ASYNC_IO_DESIGN.md)を参照する。

### 次の640で行うこと

現在は[ASYNC_CORE_PLAN.mdの項目4](ASYNC_CORE_PLAN.md#4-unicode処理640)に検討案があるだけで、640用の詳細設計・実装・Claude Codeレビュー・子タスク分割はまだ行っていない。

1. 既存の`src/core/char_width.zig`、`scripts/make-width-table.py`、Unicode関連語と試験、`THIRD_PARTY_NOTICES.md`を読む。幅生成器の現在の版はUnicode 15.1.0。新機能も同じ版にするかは未決であり、最新版へ変更するとも既存版を維持するとも決めつけない。
2. 書記素境界の語名/スタック効果、前方/後方探索、空文字、不正UTF-8、途中位置、長い結合列での計算量、結果の単位とエラーを詳細設計へまとめる。`X-GRAPHEME`は候補名であり確定名ではない。後方探索では文字列の先頭情報が必要という計画を確認する。
3. UAX #29とUnicode版を対応させ、GraphemeBreakProperty・emoji-data・DerivedCoreProperties・GraphemeBreakTestの使用ファイル、生成方法、ライセンスを確定する。公式資料/データは採用版に合わせて確認し、記憶だけで挙動を実装しない。
4. 書記素境界と表示幅を分け、結合絵文字の幅など未決の範囲を明記する。単語境界とタブを含む表示列計算は現在の計画ではアプリ側。語群とビルド除外条件も既存基盤に合わせて設計する。
5. tqueを仕様/実装/Windows・Linux/Mac実機へ分け、Claude Codeへread-onlyレビューを依頼する。レビュー原文・評価/採否・採用設計を別に残し、指摘を反映してから実装する。レモンは「レビューを依頼しながら、できるだけ止めないで進めて」を希望している。
6. 採用版のGraphemeBreakTestで照合し、メモリ/stack/不正入力/計算量/除外構成/保存画像の回帰を確認。英日HELP・全語参照・第三者ライセンス・実装記録を更新する。MacクロスビルドとMac実機実行を区別する。

### 再開時の操作と注意

```powershell
git status -sb
git log -3 --oneline
tque ls --root 1002 --all --json
zig version
zig build test --summary all
```

process回帰の再現方法は`tests/scripts/README.md`と`README.ja.md`、前記の実装記録にある。`.work/643`の旧Windows/Linux証拠は旧基点のものとして扱い、新しいsourceの証拠で上書きする場合は対象commit/sourceを記録する。

質問にはまず回答し、仕様の重大な曖昧さを推測で埋めない。今回の引継ぎ作成から640の実装許可までを読み込まない。コミット・タグ・pushはその依頼で明示されたときだけ行う。LOGOはSigmaへ組み込まず、汎用基盤を使う外部Forthアプリに置く方針を維持する。

---

## ここから過去の記録

## 最新追記：639から643へ（2026-11-19）

利用者の「macは残して、次に進めて」により643へ着手。639の1091・1094・1095は完了、Mac実機1092・1096は未完了のまま。643と1051の開発依存は639全体から完了済みI/O実装へ置き換え、最終統合はMacも待つ。

643は1097仕様→1098ホスト→1099コア/Tcl→1100 Windows/Linux→1101 Mac実機。1098と1102〜1104を完了し、native OS backend・FILE所有・公開PROC語14個を実装した。1099は1105コア接続、1106 Tcl共通backend移行、1107資料に分割。1106のTcl移行を完了し、旧OS起動コードを除去した。Windows/Linux全体受け入れ1100まで完了し、643はauto80%、未完了はMac実機1101。[実装/検証記録](PROCESS_MANAGEMENT_IMPLEMENTATION.md)、[詳細設計](PROCESS_MANAGEMENT_DESIGN.md)、[レビュー採否](reviews/643-review-response.md)を参照。

Tclはregistry内部予約枠を使い、wish探索・script・display budgetとprivate I/Oをadapterへ残した。終了時はTclも共通group/Job KILLと単一期限で回収する。公開64プロセス、多量3stream、Ctrl+C、FILE再利用/rollback、子孫と継承制限、Tcl再起動とscript削除をWindows/Linuxで実行。最終結果は[実装記録](PROCESS_MANAGEMENT_IMPLEMENTATION.md)。Mac実機1101を残す。Linux native socketの一部ケースと実wish GUI表示はfixtureでの成功扱いにしない。

現ブランチmain、基点085fef2。639と今回の643資料・基盤は未コミット。コミット・プッシュは今回依頼されていない。以下の「最新追記」や未実装という記述は各時点の履歴。


## 最新追記：638イベントキュー（2026-11-19）

現在の基点は`e66c701`、main。637はMac実機1073を含め完了済み。以下の637の残作業の記述は履歴。638のコード・設計・試験・レビュー資料は、この追記と同じコミットに含む。2026-11-19、利用者からコミット・プッシュの指示を受けた。

638を1074仕様→1075実装→1076 Windows/Linux→1077 Mac実機へ分割した。13:02 JST確認。1074〜1076は完了、638はauto75%、1077は未着手。最終12構成の成功とsource_sha256の一致も確認済み。[設計](EVENT_QUEUE_DESIGN.md)、[実装記録](CORE_EXTENSION_IMPLEMENTATION.md)、[レビュー採否](reviews/638-review-response.md)を先に読むこと。

EKEY-WAITの固定3セル、mouse付随情報、paste境界、部分入力と全体期限、peek/byte/GRAPHICSの切替、stdin入れ子、checked押戻しとEOFの順序を実装した。Windows独立console/pipeと既存回帰、LinuxのReleaseFast・PTY/pipe・NS、Mac向けコンパイルが成功。クロスコンパイルをMac実行の証拠とは扱わない。

EKEY-WAITはstdin専用。選択ファイルの期限待機は639配下1078へ追加した。1067保存アプリ起動設計は独立して着手可能だが、起動機能の実装は未着手。LOGO本体は外部Forthアプリの方針を維持する。


## 最新追記：637端末制御（2026-11-19）

以下の旧09:32時点の記録は履歴。現在の基点は`b4af2fb`で、共通基盤・語群のMac実機1065と900・1055は完了済み。今回の637の実装・設計・試験・レビュー資料は、この追記と同じコミットに含む。2026-11-19、利用者からコミット・プッシュの指示を受けた。

637を1070仕様→1071実装→1072 Windows/Linux→1073 Mac実機へ分割して進めた。[端末制御設計](TERMINAL_CONTROL_DESIGN.md)、[実装記録](CORE_EXTENSION_IMPLEMENTATION.md)、[レビュー評価](reviews/637-review-response.md)を先に読むこと。TERM-MODE!/@、COLS/ROWS、4定数、表示管理と入力境界の処理を実装。Windows cooked Ctrl+C後の入力再開は専用CONIN$ハンドルで修正し、外部生成イベントとConPTYで確認した。Mac向けコンパイルは成功したが、637のMac実行は1073に残る。

11:29 JST確認。最終の12構成マトリクスと追加レビュー・再試験が完了し、tqueの1070〜1072を完了にした。637はauto75%、1073は未着手0%。マトリクスのsource_sha256は現在のbuild.zig/srcと一致する。次は638で、先行条件1056・1064は完了している。1067保存アプリ起動の設計は別途着手可能だが、まだ実装していない。LOGOは外部Forthアプリに置く。


確認日時：2026-11-19 09:32 JST。作業場所：`D:\home\source\zig\forthz`、PowerShell、ブランチ`main`、HEADは`935b4e7 docs: detail core extension design and review findings`。

この引継ぎ作成時にGit・tque・実装記録・保存ログを再確認した。下記の試験結果は直前の開発で実施した記録であり、引継ぎ作成のための再実行ではない。タスク番号は振り直されることがあるため、再開時はタイトルと親子関係も照合する。

## 引継ぎ作成後の追記：保存アプリ起動基盤

2026-11-19、利用者の追加指示により1003配下へ1066「保存アプリの起動基盤」を追加した。仕様設計1067→コア実装1068→受け入れ1069。実装は1067・1056・1064に依存する。LOGOの言語処理・タートル・UIをSigmaへ組み込まず、本体は汎用のSAVESYS起動基盤を担当する。[追加計画](SAVED_APPLICATION_STARTUP_PLAN.md)。計画・tqueへの登録のみで、新しい起動機能は未実装。既存の次工程637・638も引き続き着手可能。以下の確認日時時点の記録とは区別する。

## 利用者の指示と現在の到達点

- 利用者はレモン、担当の呼称はロク。
- 「claude codeのレビューを依頼しながら、できるだけ止めないで進めて」を受け、読み取り専用レビューと実装・検証を並行して進めた。
- 「mac部分は残して、次に進めて」を受け、Mac実機確認1065を残したまま1056「語群基盤」と1036「OS判別」を完了した。
- 共通基盤の実装を利用する後続タスクは、900全体ではなく完了済み1064を先行条件に変更した。900の契約担当は維持する。最終受け入れ1057は1055を通して900とMac確認も待つ。
- 現在のコード・実装記録・レビュー記録は未コミット・未プッシュ。今回の引継ぎ依頼にはコミット・プッシュの指示はない。

## tqueの確認結果

| 番号 | タイトルの要点 | 状態 |
|---|---|---|
| 613 | 本体の機能拡張 | 未完了、auto16% |
| 1055 | 共通基盤 | 未完了、auto97% |
| 900 | 共通契約と内部最小基盤 | 未完了、auto91% |
| 1058〜1062 | 共通部品・ホスト統合・信号所有 | 完了 |
| 1063 | 統合後の受け入れ | 未完了、auto50% |
| 1064 | Windows/Linux自動受け入れ・Macコンパイル | 完了 |
| 1065 | Mac実機受け入れ | 未着手、0%。語群構成とHOST-OSもここに残す |
| 1056 | 語群のビルド・読込み基盤 | 完了。依存1064 |
| 1036 | OS判別 | 完了。依存1056 |
| 637 | ターミナル制御 | 未着手、着手可能。依存1056・1064 |
| 638 | イベントキュー | 未着手、着手可能。依存1056・1064 |
| 1049 | タスク実行方式の比較 | 未着手、依存なし。設計を並行して進められる |

自動進捗はタスク構造からの値であり、工数の消化率ではない。637・638を開始した扱いにはしていない。タスク制御1048の実装も未着手。

## 実装済みの内容と重要な契約

### 900 共通内部基盤

- `src/core/runtime_base.zig`：差替え時計、期限、取消し印、型付き台帳、信号所有スコープ。OSサービスを使わない。
- `src/host_clock.zig`、`host_wake.zig`：Windows QPC/Event、POSIX単調時計/pipe。通知の集約、早着通知、取消し、期限、継承属性を試験。
- `src/host_runtime.zig`：共通所有者、時計・Wake・取消し・Broker、台帳の寿命と終了順。ownerと台帳epochはプロセス内で再利用しない。
- `src/host_signal_broker.zig`、`host_wait.zig`：NSと音待機の信号所有を仲介。復元失敗は保持して再試行し、古い端末モードの保存値を再適用しない。
- `main.zig`、`host_input.zig`、`host_audio.zig`：ホスト文脈への接続、端末変更前の復元フック、shutdown/deinit順。音待機のホスト障害は既存-265へ伝える。

Runtime/Wakeは共有後にコピー・移動しない。OwnedTableは`initTable(out)`で安定アドレスへ束縛し、操作・解放は所有スレッドに限る。解放前に利用者を停止・joinする。台帳のgetが返すポインターはremove/deinitまでの借用。起動をまたぐハンドルの一意性や公開Forthハンドル形式は未実装。

### 1056・1036 語群基盤とOS判別

- `-Dextension`は既定true。audio/graphicsから独立し、除外しても共有の内部Runtime・時計・Wakeを使える。
- `REQUIRE-EXTENSION`がEXTENSION語彙を初回だけ登録する。利用例：

```forth
REQUIRE-EXTENSION ALSO EXTENSION HOST-OS TYPE PREVIOUS
```

- `HOST-OS ( -- c-addr u )`はコンパイル対象のOS系列を`windows`、`linux`（WSL/Androidを含む）、`macos`、その他は`unknown`で返す。Wine上のWindows版もwindows。未知の文字列はunknownと同様に扱う。
- 借用文字列を呼ぶたびに論理領域へ書き直す。次のHOST-OSかイメージ復元まで有効、書換え禁止。保存された別OSの値をそのまま返さない。
- extension除外時は通常の未定義語-13。読込みはparserの入口なので`[DEFINED] REQUIRE-EXTENSION`では機能検出できない。
- 記録セルは`0x0dc0`、文字列は`0x0dc8`から8バイト。領域の重複をcomptimeで検査する。
- `src/core/library_groups.zig`で語群一覧を共通化し、State追加とバイト列追加の両方で読込み済み認識を更新する。
- 新BuiltinによりイメージABI署名が変わる。新magicは増やさない。旧版互換は追加要件にしていない。
- 復元・追加のpreflightは、除外された追加builtin語と直接builtin OpをInvalidImageで拒否する。以前読めたaudio/graphicsイメージを一部拒否する変更。wire codecとSAVEは構造検査を維持する。
- 予約された基本辞書欄への普通の呼出しは従来どおり読込み可能で、除外語の実行時に-261となる。生xtデータの実行時防御も残す。
- `State.extension_library`が増え、直下フィールドは168項目。ワーカー隔離監査表と1053へ反映済み。再帰的な隔離監査は未完了。

## 検証の記録

Zig 0.17.1。詳細は[実装・検証記録](CORE_EXTENSION_IMPLEMENTATION.md)。

| 対象 | 確認済みの結果 |
|---|---|
| Windows通常構成 | 23/23ステップ成功。core1027成功・8skip、host87成功・10skip。runtimeは先行成功のキャッシュ |
| Windows構成マトリクス | audio/graphics/extensionの8通り＋代表除外4構成、計12構成成功。異なるextension構成間のイメージ拒否も成功 |
| Windows結合試験 | 通常・extension除外それぞれ38件成功 |
| WSL/Linux通常構成 | core1027成功・8skip、host98成功・5skip、runtime15/15成功。HOST-OS実出力はlinux |
| WSL/Linux extension除外 | core1023成功・12skip、host98成功・5skip、runtime15/15、結合38件成功 |
| Mac向け | aarch64-macos、graphics/audio/float除外、extension有効でcore/host/runtimeの14/14ステップがコンパイル成功。実行は未確認 |
| OS非依存性 | Cortex-M0+ freestandingのコンパイル成功 |
| 全語リファレンス | 1536項目、HELP1322項目を照合。文書例28件、独立例136件、選択器5試験、動作回帰19件が成功 |
| 共通基盤の先行検証 | Windows独立コンソール36ケース、Linux NSの期限・信号復帰・PTY5ケースも実施済み。物理キーボード操作の確認とは別 |

主な保存先（`.work`はローカル成果物。別環境には自動で引き継がれない）：

- `.work/extension-matrix/matrix.json`：12構成のcomplete=trueとイメージ拒否。source_sha256は実行開始時の参照値で、GitコミットIDではない。実行途中に行った追加整形はlibrary_loadingのコメントのみ。
- `.work/1056-review/matrix-final.log`、`linux-*-final.log`、`macos-compile-final.log`、`reference-*-final.log`。
- `.work/p10/linux/`：extension除外の明示配置した試験と結合試験。
- `.work/900-review/`、`.work/p05b-ns-check/sigma-only.json`：共通基盤・NSの先行検証。
- `.work/1056-windows/bin/sigma.exe`、`.work/1056-linux/bin/sigma`：検証用実行体。インストール済みアプリやリリース版の更新ではない。

## Claude Codeレビューと未確認事項

900では4回、1056・1036では3回の読み取り専用レビューを実施した。原文・依頼・評価・採用判断を別々に保存した。

- [900の指摘対応](reviews/900-runtime-response.md)
- [1056・1036の指摘対応](reviews/1056-response.md)
- [詳細設計の判断記録](CORE_EXTENSION_DESIGN_DECISIONS.md)

追加確認の評価は「読んだ範囲で新たな高・中の問題なし」。実OS・全機能の承認ではない。低い指摘への試験・HELP等の補強は、その後の回帰試験で検証した。

残る制約：POSIXでSIGINTハンドラーそのものの復元に失敗している間、待機外SIGINTが既定動作へ戻ることは保証しない。失敗を報告して次の待機・モード変更・終了で回復を試みる。実OSの復元失敗の注入は未実施。Mac実機、通常VMループの速度比較、リリース用パッケージ作成も未実施。ライブラリ失敗の巻戻しは辞書・検索設定が対象で、任意のForthのスタック・メモリー副作用を取り消すものではない。

## 再開する順序

1. Git状態とtqueを再取得し、未コミットの900・1056・1036の差分を保持する。番号だけでタスクを特定しない。
2. [全体計画](CORE_EXTENSION_PLAN.md)、[詳細設計](CORE_EXTENSION_DETAILED_DESIGN.md)、[語群の採用設計](EXTENSION_GROUP_DESIGN.md)を確認する。
3. 次の候補は637「ターミナル制御」と638「イベントキュー」。[TUI・非同期計画](ASYNC_CORE_PLAN.md)から担当する仕様を詰める。637では端末の表示設定をraw modeから分け、既存の信号復元フックと終了順を維持する。638では期限・時計・取消しを共通基盤から再利用し、既存のWindows入力レコードと保留入力を保持する。
4. 未決API・具体値は既存決定と照合し、Claude Codeに具体案をレビュー依頼しながら進める。レビューには固定コピーを渡し、原文と対応を保存する。レビュー待ちの間は独立した検証・文書作業を進める。
5. 1049の方式比較は並行可能。独立Forth VM採用、通常ループの変更、デバッグ必須のタスク取消しを既決事項として扱わない。[タスク制御計画](TASK_CONTROL_PLAN.md)と[State監査表](CORE_EXTENSION_WORKER_STATE_AUDIT.md)を使う。
6. Mac確認は[1065の実機手順](CORE_EXTENSION_MAC_ACCEPTANCE.md)へ残す。クロスコンパイルで完了にせず、900・1063・1055・1057の最終完了条件も維持する。

再開時の確認コマンド：

```powershell
git status --short
git log -1 --oneline
tque ls --root 613 --all --json
zig version
```

変更内容に応じて選ぶ検証コマンド（この引継ぎ作成時には再実行していない）：

```powershell
zig build test --summary all
python tests/scripts/verify-extension-matrix.py
python tests/scripts/verify-feature-matrix.py --platform linux --groups extension
python scripts/word-reference.py --check --sigma .work/1056-windows/bin/sigma.exe
```

最後のコマンドで使う実行体は検証対象のソースから作り直す。日本語リファレンスのsource fingerprint更新は、日本語説明と実装の対応を確認した後に行う。

Claude Codeへ読み取り専用レビューを依頼したときのCLI設定：

```powershell
Get-Content -Raw .work/<review>/request.txt | claude -p --tools 'Read,Glob,Grep' --allowedTools 'Read,Glob,Grep' --permission-mode dontAsk --strict-mcp-config --disable-slash-commands --no-session-persistence --output-format json
```

## Gitと作業範囲

HEADは上記の設計文書コミット。実装には追跡済みファイルの変更と未追跡の新ファイルが混在する。`src/core/runtime_base.zig`、host側のRuntime/時計/Wake/Broker、`words_extension.zig`、`image_features.zig`、`library_groups.zig`、追加試験・Forthソース・レビュー原文・実装記録を含めて差分を確認する。

現在は`docs/LOGO_TURTLE_STUDY.md`も未追跡として存在し、文書索引にリンクがある。その内容は今回の613の引継ぎでは確認対象にしていない。コミット対象は再開時にGit状態と差分を照合して選ぶ。

コミット・タグ・プッシュは、その依頼で明示された場合に行う。リポジトリ外と外部データへのアクセスは利用者のアクセス規則に従う。今回の引継ぎではソース修正・tque更新・ビルド・リリースは行っていない。

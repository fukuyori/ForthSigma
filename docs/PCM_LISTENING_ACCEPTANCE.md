# PCM実聴の確認（1148 Windows / 1149 Linux）

## Linux PCM実聴1149と親998の完了（2026-11-20）

WSL Ubuntu26.04.1へpulseaudio-utilsと依存ライブラリを導入し、静的musl版Sigmaのpacat pipe経由でWSLg PulseAudio RDPSinkへ出力した。AUDIO?=-1を確認し、レモンがmono/stereo左右・MML/SFX混合・破棄と再開・drain後停止・保存アプリ・物理Ctrl+C後の停止とhello入力の全8項目を実聴してＯＫと回答。case1〜7のunderrun0、case8はCATCH=-28/CLOSE=0、全process code0。1149・1133・998を完了した。[環境・コマンド・実聴記録](measurements/2026-11-20-linux-audio-listening.json)。これはWSL/Linux実行体からPulseAudioを経た実出力の確認で、Linux実機のALSA装置確認とは区別する。以降のLinux未確認・AUDIO?=0は当時の記録。

## Windows実聴1148の受け入れ完了（2026-11-20）

レモンがWindows実装置で8項目を順番に聞き、各項目をokで確認した。48000Hz mono、22050Hz stereo左右、MML/SFXとの混合、破棄と再open、drain後の停止、SAVESYS保存アプリの2音を確認。最後は前面のPowerShellで物理Ctrl+Cを押し、CATCH=-28/CLOSE=0、続くhelloのACCEPTとcode0を記録し、中断後の音の停止も追加確認した。case1〜7のUNDERRUNSはすべて0。Windows11 Pro 10.0.26300、waveOut既定出力（個別endpoint表示名は未取得）。[全実行記録と利用者の確認](measurements/2026-11-20-pcm-windows-listening.json)。

1148を完了。Linux1149は未完了・0%、1133は未完了・auto50%、998は未完了・auto94%。現WSLはAUDIO?=0のため、Linuxの実聴成功とは扱わない。以下の「Windows実聴未確認」はこの受け入れ以前の履歴。

準備時点の記録（Windowsは上記のとおり確認済み、Linuxは未確認）。以下は確認用スクリプトと無音の実行検査であり、聞こえ方の合格を意味しない。998の子1133配下に1148/1149を残す。

## 実行するもの

`tests/scripts/pcm-listen.py`は指定されたSigmaを別processで起動し、独自の三角波をPCMへ送る。既定は全標本0で、`--audible`を明示した場合だけ音を生成する。読み込む音声素材や外部ライブラリのコードはない。Python標準ライブラリだけを使う。生成アプリの確認では作業用一時directoryへSAVESYSを作り、実行後に回収する。

リポジトリ直下のPowerShellで、低いシステム音量から1項目ずつ実行する。以下の実行体は今回のWindows検査で使った版。

```powershell
python tests/scripts/pcm-listen.py .work/1138/matrix/windows/bin/sigma.exe --case 1 --audible --record .work/998-followup/windows-audible-1.json
```

`--case`を下表の番号へ変える。8では手前に表示されたREADYを確認し、約1秒待ってからCtrl+Cを1回だけ押し、CATCH/CLOSEの表示後に`hello`とEnterを入力する。8は物理入力を使うため、前面の通常端末で実行し、パイプや出力リダイレクトを付けない。PythonのJSONには実行結果だけを記録し、聞こえ方は利用者の確認を別に記録する。

| case | 聞く内容・操作 | 確認する結果 |
| --- | --- | --- |
| 1 | 48000Hz mono、440Hzを2秒 | 一定の音が鳴り、終了後は停止 |
| 2 | 22050Hz stereo、左440Hz→右660Hzを各1.5秒 | 左右が入れ替わる。sample hold再標本化を含む |
| 3 | PCM220HzとMMLの短いメロディを混合 | 低い一定音とメロディが同時に聞こえる |
| 4 | PCM220Hzと独自signed8bit SFX880Hz（1秒）を混合 | 最初の1秒は2音、後半はPCMだけ |
| 5 | PCMを32768frame入れ、150ms後に破棄、1秒後に開き直す | DISCARDED付近で停止し、間を空けて再開する。backend側の既送信分は残り得る |
| 6 | 2秒のPCMをdrain | DRAINED表示後に停止。drainはengine消費で、device再生位置ではない |
| 7 | SAVESYS保存アプリで523Hz→784Hzを各1秒 | 保存アプリでも2音が鳴り、正常終了 |
| 8 | 550Hzを連続出力。READY後にCtrl+C、続いてhelloとEnter | 音が停止、CATCH=-28、CLOSE=0、入力helloが表示され正常終了 |

各processの終了でhostと音声資源を回収する。音切れがあればそのcaseとUNDERRUNS、音量・左右・終了後の残音、OS/装置名を記録する。AUDIO?=-1はbackendが使えることだけを示し、実聴成功とはしない。`--audible`時にAUDIO?が真でなければ実聴を開始せずエラーにする。

## Linux

通常のLinux端末で同じスクリプトを使い、SigmaのパスをLinux版へ変える。

```sh
python3 tests/scripts/pcm-listen.py .work/1138/matrix/linux/bin/sigma --case 1 --audible --record .work/998-followup/linux-audible-1.json
```

今回のWSL（Ubuntu26.04.1）ではPULSE_SERVER=unix:/mnt/wslg/PulseServerでsocketはあるが、libpulse0/libasound2t64は未導入でAUDIO?=0だった。現在の環境では実聴を実施していない。PulseAudio/ALSAが利用できるLinux環境で上記を実行するか、現環境の音声環境を整えた後にAUDIO?を再確認する。今回システムへのパッケージ導入・設定変更はしていない。

## 検証済みと未確認の境界

Windows/Linux両方でcase1〜7を無音で実行し、stereo22.05kHzの容量制約、部分書込みの再試行、drain/close、保存アプリの起動と終了を確認した。case8は専用の非表示console/PTYへ合成キーを注入してCATCH=-28/CLOSE=0と後続ACCEPTを検証した。合成キーはabcdeとEnterを使い、物理キーボードによるhelloの確認とは区別する。

WindowsでAUDIO?=-1、Linuxで0。Windowsでも実際に聞いて確認した結果はまだない。全caseの無音実行だけで1148/1149を完了にしない。[検査記録](measurements/2026-11-20-pcm-listen-preparation.json)。

親PythonへのOS中断も別に検証した。Windowsは専用非表示console全体へのCTRL_C_EVENT、Linuxは専用process group全体へのSIGINTを送り、Python親が終了せず、SigmaのCATCH=-28/CLOSE=0、続けて注入したhelloのACCEPTとJSON出力が成功した。これは合成入力の自動検査であり、利用者の実聴・物理キーの受け入れとは区別する。case8の連続波形は4800frame（550Hzの55周期）を繰り返して位相を保ち、次block分の空きだけ待つ。case6はdrain後も1秒processを保持して終了前の無音を聞く区間を設けた。

[Claudeレビューの評価と対応](reviews/998-pcm-followup-review-response.md)。修正後レビューでHigh/Mediumの指摘はない。

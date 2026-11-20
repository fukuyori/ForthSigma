# SNES nativeフレームkernel 1183のレビュー反映

[設計原文](1183-design-claude-review.md)、[実装原文](1183-implementation-claude-review.md)、[追レビュー原文](1183-followup-claude-review.md)、[最終絞込みレビュー](1183-final-claude-review.md)。すべてClaude Code CLIのRead/Glob/Grepだけを許可した読み取りレビューで、レビュー側は実行・測定していない。レモンの「レビューを依頼しながら進める」という依頼に基づく。

設計B1は両バックエンドの完了フレームごとの時刻更新と `( frames -- )` tokenに統一。B2はnativeだけが途中フレームを見せない保証と明記。B3は範囲外のprivate stateは参照Forthでは未規定、nativeでは0frameも-24で拒否すると明記した。

実装レビューはHighなし・Medium M1（個別検査がForth側のhelperを呼んでいた）。native frameを通すBRR256header×16nibble×3履歴、317ENV、Gauss256位相×4極端履歴、FIR8tap/volume/feedback/mute/write-disable検査を追加した。

追レビューではfeedbackの初期値が書戻し値と同じというMediumが残った。初期wordを-1234とし、FIR=-32768→EFB -128のsigned16折り返しで32768を書き、flag32だけ初期64302が残ることを実際のARAM wordで照合するよう修正。MVOL負数とvoiceごとの飽和を区別する2声fixtureも追加した。GaussのENVを2032にし、更新前ENVX127と更新後126を区別した。SAVESYS後も選択tokenがSD-NATIVE-FRAMESと一致することを確認する。

no-audioのMediumは、両OSで語が未定義、旧ABI画像とnativeを含む画像がINVALID IMAGE/exit1で拒否される記録を追加して解消。no-floatは既存matrix定義でdebug/extensionも除外するため、EXEC-LIMITEDを省く指定は正しいと最終レビューで訂正された。

registryは実際のENVX/OUTX/ENDX/echo byteだけを通知し、無関係なARAMのtyped slotがdamagedにならないことをZig testで確認。cellは全体in/out記録なので、未変更セルも完全書込み通知され得るという参照Forthとの差を明記した。Fixtureの5領域は連続配置で隣接の正常系も通る。voice/global/history/overlap/address/layout/count不正について、検査後の全fixtureメモリと引数スタックを照合する。

毎frame138cellを書き戻す性能上のLowは初回候補のまま維持する。次の実測にはこの費用も含め、必要性が分かってから最適化を判断する。native版の速度・実装置の生成音受け入れは未実施である。

最終絞込みレビューはHigh/Mediumなし。全構成の実行記録・ソース/実行体ハッシュは [検証記録](../measurements/2026-11-20-snes-dsp-native.json) にまとめる。レビュー側で未計算だったハッシュ整合は、記録作成時にこちらで検査する。1175/1176/1177と親1173は未完了のまま維持する。

## 後続の速度測定

機能レビュー後、レモンの新たなＯＫを受けてWindows→WSL/Linuxで6負荷各7回を測定した。全回のPCM/state/queue/ARAMとForth版との一致、現物binary/source hash、中央値をこちらで検査し記録した。最小余裕28.69/30.34倍で次の再生受け入れにnative候補を採用する。[全値と環境制限](../measurements/2026-11-20-snes-dsp-os-acceptance.json)。実聴・物理中断とMacは未完了のまま。Claudeが測定を実行・追認したという意味ではない。

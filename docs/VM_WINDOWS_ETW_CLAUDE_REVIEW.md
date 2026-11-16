# Windows ETW解析 Claude Codeレビュー

2026-11-16。読取り専用レビュー、exit0。以下は最終補正前の結果。

## レビュー結果（docs/VM_WINDOWS_ETW_ANALYSIS.md と生QPC照合）

**総評: High/Blocker なし。** 式・表の数値・主張範囲は、読んだ成果物と整合しています。Medium 2件、Low 5件です。再実行はしておらず、`capture.json`、`events.csv`、`raw-cswitch.csv`、`tracestats.txt`、`docs/measurements/*.json` は読んでいません。

### 確認できた点

- **取得の整合性**: 6標本、`capture_status=samples_captured`、`cleanup_confirmed=true`、Lost Events/Buffers=0、CSwitch 723,767件、連鎖不一致0、InvalidEvent行0。`stop_exit==0` は `analyze-etw.py:5` の assert で担保されています。
- **全生存期間表**: 6行とも `cswitch-net.txt` / `cswitch-gross.txt` の対象TID行と一致。範囲/中央値の4つの%（5.440、0.608、2.917、0.056）も再計算で一致しました。
- **QPC換算**: `analyze-etw-qpc.py:30-34` は tick×1e9 と ns×frequency の整数比較で、frequency=10,000,000 なら丸めなしです。
- **payload順序**: `analyze-etw-qpc.py:15-16,24` が全行で cpu/new/old を assert し、raw の読み切りと件数も確認しています。offset 幅は実測0.9us（assert は1.01us以下）。
- **DPC/ISR 境界**: `excluded_min`/`excluded_max` の式は妥当で、部分重なりは6行とも0件なので上下限が一致しています。行1を手計算し、6207.768〜6208.882 を再現しました。
- **境界の区別**: 全生存期間と READY/DONE は表も文も分離されています。終了イベントから最終 switch-out までの14〜125usも一致。
- **LogicalDisk 警告**: 44.493519秒は、最後の対象 switch-out（約44.342253秒）より後です。
- **過剰主張**: 因果、OS不具合、時計精度、校正、採用のいずれも主張していません。幅は「信頼区間でも精度保証でもない」と明記されています（md:48、qpc-analysis.json の limits）。
- **残差**: Sigma初回 −427.632〜−426.518ms、native最終 +96.692〜+98.118ms は JSON と一致します。

### Medium

1. **API側の粒度が幅に含まれておらず、文書にも記載がない**（md:48-59、`analyze-etw-qpc.py:41-43`）
   - API値12個（生存期間6、区間6）はすべて15.625msの整数倍です。生存期間と区間の差も0か15.625msだけです。
   - 幅（約±0.6〜0.7ms）は ETW 側の丸めと bracket だけなので、API−ETW 列が sub-ms 精度に見えます。行2の +4.3〜5.7ms は API の1刻み未満です。
   - 対応: md:48 に「API値は15.625ms刻みで観測され、この幅には含めていない」と事実だけ追記し、limits にも1行足す。原因の示唆にはしないこと。

2. **「同じQPC時計」の確認が解析側プロセスに限られる**（md:44、`analyze-etw-qpc.py:6`）
   - assert は解析時の Python の実装名を見るだけです。取得時 observer の Python と同一か、`perf_counter_ns` が原点補正なしの QPC 値かは直接検証していません。
   - 間接的な裏付けはあります。QPC区間の gross と UTC 近似窓の gross が6行とも16〜33us差で一致し、部分重なりも0件です。
   - 対応: md:44 を「解析環境で確認、原点一致は UTC 近似窓との一致による間接確認」と弱める。あるいは observer の Python 版と clock info を取得記録から引用する。

### Low

3. **13usは実測値で、コードの許容値ではない**（`analyze-etw.py:54`、md:10）: assert は `slices*2` us（約1.0〜1.3ms）です。文面は「実測最大13us」のままで正しいので、「parser が13us以下を保証」とは書かないこと。締めるなら assert を20us程度にする。
4. **QPC側で DPC 行と slice の対応を再検証していない**（`analyze-etw-qpc.py:28`）: 件数一致のみです。start/end/cpu の整合は `analyze-etw.py:32` に依存しています。同じ assert を足すか、依存を limits に明記する。
5. **警告情報と件数が直書き**（`analyze-etw.py:26,57`、`analyze-etw-qpc.py:24`）: 「全対象終了後」をコードが検証していません。`time_us > max(最終switch-out)` の assert を追加する。
6. **表2の列名**（md:50）: 「API区間CPU」は process の値（`s['cpu_us']`）で、表1は primary thread です。差は6行とも0ですが、列名か注記で明示する。
7. **文書の時系列**（md:35-39）: 「未完了」「次は…確認し」が、直後の実施済み節と並んでいます。35-37行に「以下で実施済み」と入れるか、節を統合する。md:39 のリンク先に QPC 行が含まれるかは未確認です。

`read-etw-qpc.c` は provider GUID、opcode 36、RAW_TIMESTAMP、PerfFreq、ReservedFlags の扱いに問題ありません。`fclose` の戻り値は未検査ですが、後段の件数 assert と SHA で実害はありません。

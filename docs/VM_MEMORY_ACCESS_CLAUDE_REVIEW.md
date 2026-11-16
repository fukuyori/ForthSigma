静的レビューの結果、結論や選定を覆す重大な問題はありませんでした。ただし証拠と食い違う記述が1件あり、修正を勧めます。確認はRead/Grepのみで、変更・再実行はしていません。

## 重大事項

**結論を覆すものはなし。** 次の主要な主張は証拠と一致しました。

- **表の数値**：`memory-summary.json` の6ケースが文書の表と全て一致。pinball-logicでは readCell 5,281,651 + writeCell 1,056,276 = memoryAddress 6,337,927 と入口の内訳も整合します。
- **+!の検査融合**：`add_store_disassembly_excerpt` で、検査1組（`js`/`jb`/`jb`）→ `add QWORD PTR [rcx+rsi*1],rax` → `!` と共有の末尾へ `jmp`、という連続経路を確認しました。「1組」は注釈行のフィルターだけでなく逆アセンブル断片でも裏付けられています。
- **Ir/反復と呼出し**：152/152、146/219、140/213、172/211 は一致。登録0の `!`/`+!` は `calls` が空、`C!` は `written` が1回/反復で 2300 Ir/100回 = 23命令です。
- **入口と機械語の区別**：計測版は Windows の counted VM、生成コードは Linux の未変更 uncounted VM と分けて書かれており、混同はありません。
- **計測差分**：`instrumented/src` の差分はカウンター加算と `plain_calls`、reset、出力行だけで、`notifyRecord` の `else` 展開も意味を変えていません。

**要修正（1件）：「対照の時点では既に索引が温まっていた」は証拠と不一致。**
`control-registered-{other,exact,partial}-store-1.stderr` はいずれも `linear_notifications 0`、`indexed_notifications 100`、`index_rebuilds 1` です。reset前に消化済みだったのは線形32回の枠で、索引の構築自体はWORKLOAD内の最初の通知で起きています。`registered-add-store` だけ `index_rebuilds 0` で、この差の理由は静的には特定できませんでした。「線形段階は終わっていたが、3対照では索引構築が計測区間内に1回入った」と書くのが正確です。

## 任意事項

**計測の取りこぼし**

- **MOVE/CMOVE**：登録0のとき `copy()` は `copyBytes` へ直行し、`written` にも `writeCell` にも入りません。登録ありなら `copyTracked` 内の `written` で数えられるので「登録あり通知0」は崩れませんが、その全件走査自体はカウンター対象外です。
- **charローカルの書込み**：`src/core/local_variables.zig:128` は `memoryAddress` 後に直接書き、`written` を呼びません。基準版も同じで、計測では通知として見えない経路です。登録スロットと重なり得るかは未確認なので、別件として確認する価値があります。
- **8バイト幅の別経路**：`words_width.zig:50` と `words_data.zig:51` は `writeInt` + `written` で、`writeCell入口` には入りません。表の列は「writeCell経由」であって全セル書込みではありません。
- **`written_early_return`**：`length==0` と登録0を区別しません。「全て登録0で即復帰」はこのカウンター単独では言えず、writeCell側のgate一致と合わせた推定です。
- **対話行**：対照の `M-X @` が数えられていない（`read_cell_entries 100`）とおり、終了行の解釈実行は対象外です。文書の「in_counted内だけ」と整合しますが、明記するとよいです。

**過剰な断定**

- **修復の確認**：unit testは `registry.written()` を直接呼ぶだけで、メモリーには書いていません。「全体書込みのvalid復帰」は「全体セル通知で」が正確です。CLI対照はカウンターとstdoutだけを見ており、damaged/validの状態は観測していません。
- **登録1のIr差**（+73、+73、+39）：1レコード・`notify_attempts 0` の二分探索だけの値です。件数増、線形段階、重なり通知の費用は表していません。
- **+!の範囲**：確認したのは `1 M-X +!` の1カーネルです。文書冒頭で触れている `1+!`/`1-!` の生成コードは未確認なので、選定欄にも一言あると安全です。

**試験記録**

- **失敗2件目の原因は推定**：`a word that takes the place…` のログには差分がありません。1件目のfound出力が `MEASURE-MEM memory_address_entries ` の途中で切れているので、stderr捕捉の打切りで末尾の `NEW` 行が落ちたと読むのが自然です。「追加行による」は妥当ですが、推定と書くべきです。
- **counter-onlyの3件**：ログにテスト名がなく、どの3件かは特定できません。Debugビルドでの確認でもあります。
- **グローバル状態の漏れ**：1件目のfound出力に `initial_registered 1` が出ており、`stats` がテスト間で持ち越されています。害はありませんが記録に値します。

**選定**

- **4項目の選定は妥当**です。
- **C!のgate**：compiled `C!` は最大28回、`written` 入口も最大140回なので、「時間効果は未判定」より「この6実例では効果が出ない規模」と書けます。
- **gateの置き場所**：やるなら `C!` の呼出し元だけでなく、`written` を登録数検査つきの薄いラッパーにすれば約50箇所の呼出し元すべてに効きます。

**文書の体裁**

- 前半（5〜15行目）の「未計測」「未確認」「次は#792で」は後段で解消済みです。段階記録と断ってはいますが、読み違いの恐れがあります。
- `.work/instrumentation.patch` は修正前の `std.meta.fields` 版のままです。最終版は notifications JSON の `source_patches` 側にあります。

対照の `-2.stderr` は直接見ておらず、スクリプトの一致assertに依拠しています。
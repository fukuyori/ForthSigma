レモン、`docs/SNES_DSP_NATIVE_DESIGN.md` は今のままでは実装に入れません。実装前に設計書で決めておくべき点が 3 つあります。どれも本文に1〜2文足せば解消できます。今回はファイルを読んだだけで、実装・ビルド・テスト・計測は一切していません。

## ブロッカー(実装前に設計書で確定すべき点)

**B1. 中断したときの時刻の扱いが、Forth 版と native 版で揃っていない**
- 今の Forth 版 `SD-RAW-RUN`(`examples/snes-dsp-audio.fs:176-180`)は、frame を回す前に `SD-DIV` を最終値へ書き、`SD-CYCLE +!` は最後にまとめて行います。途中で step 制限などで止まると、DIV は新しい値、CYCLE は古い値、FRAME は途中まで進んだ状態が残ります。
- 設計書が言う「frame ごとに時刻を更新して、止まっても完了分の進行を整合した状態で残す」は native 側だけの話で、Forth 側をどう変えるかが書かれていません。
- 推奨:
  - 実行トークンの stack を `( frames -- )` に決める。
  - Forth 版も「`SD-STEP` のあと CYCLE += 32−DIV、DIV = 0」を frame ごとに行う形に直す。
  - `SD-RAW-RUN` は全 frame を終えてから、端数 tick を CYCLE と DIV に加える。
  - Python oracle の `advance`(`verify-snes-dsp-audio.py:115-119`)はすでにこの順序なので、この形にすれば 3 者を揃えて比べられます。

**B2. 「途中の frame を見せない」が成り立つのは native 版だけ**
- Forth 版の `SD-STEP` は途中で止まり得るため、途中まで処理した frame が見えます。
- 推奨: 設計書に「native 版だけの保証」と明記する。中断テストは「backend 同士の一致」ではなく、「止まった時点の FRAME を k として、Python で k frame 進めた状態と一致する」という形にする。

**B3. 範囲外の状態を渡したときの結果が backend で変わる**
- native 版は範囲外の値を -24 で拒否しますが、Forth 版は検査せずにそのまま計算します。
- 推奨: 「宣言した範囲の外は Forth 版では未定義」と明記し、backend 同士の比較は範囲内の状態に限る。Forth 側に検査を足すと参照モデルが遅くなるので勧めません。
- frame 数 0 の呼び出しを dispatcher で省くかどうかも決めておく必要があります(省くと、0 frame のときは範囲外の状態でも -24 が出なくなります)。推奨は「0 frame でも呼ぶ」です。

## 正確性リスク(実装とレビューで確認すべき点)

**中**
1. **呼ぶたびに 1 frame しか進まない**: `SD-RENDER` は出力 1 sample ごとに `32 SD-RUN` を呼ぶ(`:222`)ので、native には毎回 frame 数 1 で入ります。
   - 結果として、7 引数の受け渡し、5 buffer の検査、138 cell の読み書きが毎 frame 発生し、速くなる幅が限られる可能性があります(※推測です。計測はしていません)。
   - 既存テストの大半がこの 1 frame 経路なので、複数 frame をまとめて回す経路がほとんど試されないことも問題です。
2. **書込み通知の範囲**:
   - 背景: `written(..., full_cell=false)` は、重なった typed slot を damaged にします(`address_registry.zig:109-142`)。
   - 通知が 1 つでも抜けると、damaged にすべき slot がそのまま残ります。逆に ARAM 全体などを広くまとめて通知すると、Forth 版では無傷の slot まで damaged になり、registry の状態が backend でずれます。
   - Forth 版が 1 frame に書く byte は次の 3 種類です。native も同じ番地だけを通知することを推奨します。
     - voice ごとの reg 8/9
     - ENDX(reg 124)
     - echo の書込み 2+2 byte
   - cell buffer は commit 時に `writeCell` 相当(full_cell=true)で通知すれば十分です。
3. **16bit wrap は byte 単位**: `SD-W@`/`SD-W!` は 1 byte ごとに `65535 AND` しています。このため word 番地 65535 は、65535 番地と 0 番地の 2 byte になります。設計書の「16-bit address wrap」に「byte 単位」と書き添えることを推奨します。
4. **ARAM 由来の値を cache しない**: echo の書込みと queue の書込みは、次の frame の BRR、directory、header の読込みに影響します。高速化のために decode 済み BRR を cache することは禁止、と明記するよう推奨します。
5. **floor 演算**: 設計書の約束どおり、すべての除算を floor にする必要があります。Zig では `>>`(算術シフト)か `@divFloor` を使い、`@divTrunc` は使わないこと。`count*32` などの時刻計算は checked 演算で行うこと。

**低**
6. 発音していない voice や KON 遅延中の voice でも、ENVX には `env>>4` を書きます。0 ではありません(`SD-PUBLISH`、`:105-112`)。
7. voice 処理の順序: 同じ voice の中で FLG soft reset → KOFF → KON の順を守り、KON が reset より優先されるようにします(`:159-164`)。
8. 作業用の `SD-MIX`/`SD-EMIX` は native 実行後に古い値のまま残ります。「未規定」と明記してください。既存テストには、これを直接設定して `SD-ECHO` を呼ぶもの(`verify:223`)があります。
9. builtin tag を追加すると、末尾に追加しても ABI の fingerprint が変わり、全 build で既存 image が読めなくなります(`docs/IMAGE_FORMAT45.md:33`)。設計書の書き方を「ID は動かないが、旧 image は作り直しになる」に変えることを推奨します。
10. globals を CREATE にまとめると、参照 Forth のソースが変わります。HERE の記録値(122880→218632)と既存の検証記録は取り直しになります。
11. native を選んだまま MARKER/FORGET で adapter を消すと、選択中の実行トークンが消えた word を指したままになります(一般的な Forth の注意事項として記載)。

## インターフェース選択の推奨

- **stack と名前**: 設計どおりで構いません。別名 `SNES-FRAMES` は `audio.fs` で `: SNES-FRAMES SND-SNES-FRAMES ;` と定義し、`help_text.zig` には両方の名前を登録します。help テストが library word の定義を確かめているので、その対象にも入ります。
- **検査の順序**: stack 深さ → layout → frames<0 → 5 範囲(-9) → 重なり(-24。隣接は可、1 byte でも重なれば不可) → 状態の各 field → overflow の順を推奨します。どれかで失敗したら、stack とすべての buffer は変更しません。
- **charge**: 設計どおり、frame の前に毎回 `checkWorkBlock` 相当(`charge(.native)`)を呼びます。
  - 制限付き実行中は `.native` で毎回 host を poll するので、その間は遅くなります。ただし通常の VM ループは影響を受けません。
  - poll は Forth コードを実行しないため、借りた slice は呼び出し中ずっと有効です(`main.zig:3294`)。
- **Gauss 係数表**: `scripts/snes-tables.py` で Zig の表を生成してコミットします。Zig のテストで既存の pinned hash `0acd5077…` を確認し、Forth の `SD-GAUSS` と 512 値が一致することも確かめます。
- **PCM の出力先**: 上のリスク 1 に対処するなら、出力先 address(0 なら出力しない)を引数に加え、RENDER が次の queue 時刻までまとめて生成できるようにする案があります。採るかどうかはレモンの判断です。後から引数を足すと builtin ID が増えるので、決めるなら最初に決めるのが安上がりです。

## 不足しているテスト

- **builtin 単体**:
  - 14 voice field、10 global、history の各境界(min−1/min/max/max+1)
  - 10 組の重なり判定と、隣接している場合
  - memory 末尾ちょうどの範囲と、負の address
  - layout 0/2、frames −1、frames 0 で状態が範囲外の場合
  - overflow の境界の両側
  - 引数不足
  - 失敗後に stack と buffer が全 byte 変わっていないこと
- **複数 frame の経路**: queue なしの大きな `SD-RUN`/`SD-TO` 1 回と、RENDER を 1 frame ずつ回した場合の PCM・状態・ARAM の一致。1175 の 6 負荷 × 16384 frame について、Python・Forth・native の 3 者で照合する(計時なし)。
- **中断**: debug build で `--max-steps` を使い、k frame 時点の状態が Python と一致すること、CYCLE と DIV が整合していること、queue index が変わっていないこと、その後同じ目標時刻へ再実行すると中断しなかった場合と同じ PCM になること。
- **backend の切替**: 任意の frame で Forth→native→Forth と切り替えても PCM が一致すること。`SD-RESET` 後も選択が保たれること。
- **registry**: ARAM 内で書き込まれない typed slot が damaged にならないこと。echo の書込み番地にある slot は、Forth 版と同じように damaged になること。
- **image**: native を選んだ状態で save→load→render が一致すること。no-audio build では native の entry が規定どおりのエラーになること。
- **検証スクリプトの改修**: `verify-snes-dsp-audio.py:162` は entry を `examples/snes-dsp-audio.fs` に固定しています。native 版の entry と no-audio 時の期待値を指定できるようにする必要があります。

## 未確認

`src/tests/audio_test.zig`、help テストの実装、image の ABI 生成コード、Builtin enum が feature で絞られるかどうかは、実際には読んでいません。リスク 9 は `docs/IMAGE_FORMAT45.md` の記述だけを根拠にしています。

# P03 メモリーとデータ配置の実装記録

2026-11-13。P03（tque 546）のうち、P03a（560）の44語を実装。P03b（561）はデータ配置12語（子615）まで実装し、型付きアドレス3語・再配置（子616/617）は未実装。P03c（562）のヒープ・伸長バッファーは未着手。対象語と完了条件は[実装フェーズ](GFORTH_WORD_PHASES.md)、確定設計は[P00仕様](GFORTH_P00_SPEC.md)。

## P03aの幅とスタック表現

実装はsrc/core/words_width.zig。既存の組込enumをずらさず末尾に44語を追加した。`FLOAT`、`FLOAT/`、`DFLOAT/`、`SFLOAT/`等はバイト数の演算なので、float無効構成でも利用できる。

|語群|動作|
|---|---|
|/W /L /X FLOAT|バイト数2 / 4 / 8 / 8を返す|
|CELL/ FLOAT/ DFLOAT/ SFLOAT/|8 / 8 / 8 / 4で床除算。負数も算術右シフトと同じ結果|
|CHAR-|1バイト減算。セル幅で折り返す|
|C>S W>S L>S X>S|下位8 / 16 / 32 / 64ビットをセルへ符号拡張|
|W@ L@ X@ / W! L! X!|16 / 32 / 64ビット。読込はゼロ拡張、格納は下位ビットのみ|
|XD@ XD!|メモリー幅は**64ビット（8バイト）**。XD@は2セルへゼロ拡張し、XD!は2セル入力の下位64ビットだけを格納|
|XD>S|**1セル入力から2セル出力**。64ビットセルを符号拡張するS>D相当。利用者の「おすすめで」により指定64ビットGforthの実測を採用|
|WBE LBE XBE XDBE|下位16 / 32 / 64 / 64ビットをバイト反転。XDBEは二倍長入力を消費し、反転した64ビットをゼロ拡張して返す|
|WLE LLE XLE XDLE|Sigmaの論理メモリーは常にリトルエンディアンなので恒等演算。XDLEは二倍長のまま保持|
|TH TH@ TH!|base + index*8のアドレス／セル読込／セル格納。アドレス計算はセル幅で折り返し、メモリーアクセス時に範囲検査|
|!@ +!@|古いセルを返し、置換／折返し加算を行う。並行処理の原子操作ではない|

GforthのXD系のxd/udという型名を、メモリー幅128ビットの意味に読み替えない。指定GforthでXD!が8バイト先を変更しないこと、XD@が上位セル0を返すこと、XD>Sがトップの1セルを符号拡張することを確認した。

全幅のメモリー範囲を検査してから格納する。未整列のアクセスを許す。論理アドレス0は既存Sigmaの@と同様にアクセス可能であり、GforthのホストNULLアクセスによる-9を模倣しない。負数やメモリー終端をまたぐアクセスはInvalidAddress（-9）。

## 整列

W/L/Xの整列は2/4/8バイト、MAXALIGNEDは8バイト。*ALIGNEDは指定された非0の2の累乗に切り上げ、*ALIGNはHEREを整列する。0・非2累乗の指定はResultOutOfRange（-11）。

ALIGNED系の計算は64ビットの折返しで、アドレスの有効性は後続アクセスで検査する。ALIGN系はreserveDataで全増分を事前検査し、容量不足ではHEREを変更しない。未整列バイトの内容を初期化する保証はない。

## 検証

- src/tests/p03a_test.zig：未整列・生バイト順・切捨て格納・ゼロ／符号拡張・隣接バイト保持・負アドレス・終端ちょうど／1バイト超過・非部分書込み・整列／容量不足・交換／添字・スタック不足・コンパイル・辞書復元／追加。
- verify-p03a.py：保存済み44ケースと境界／コンパイル等1,332ケース、計1,376ケースでSigma・指定Gforthが一致。無効なホストポインターは比較元で実行しない。
- 通常と全機能群無効構成のzig build testが成功。ログは.zig-cache/p03a-test.log、p03a-minimal.log。

```sh
ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-global-cache" zig build test --cache-dir .zig-cache
ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-global-cache" zig build test \
  -Dfloat=false -Dgraphics=false -Daudio=false -Dfiles=false \
  -Dimage=false -Dhelp=false -Dtools=false -Ddebug=false --cache-dir .zig-cache
ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-global-cache" zig build --cache-dir .zig-cache
python3 scripts/verify-p03a.py zig-out/bin/sigma --gforth-build .work/gforth-audit/gforth-build --report .work/p03a-check/results.json
```

比較元はP00と同じ作業用Gforth 1.0.1 arm64。--gforth-buildなしではSigmaのみ検証する。GPLコードは転用していない。Windows/Linux確認はここでは行わず、別環境の607で確認する。版番号変更・パッケージ作成は行わない。

## P03b データ配置基盤（12語、子615）

実装はsrc/core/words_data.zig。親561は未完了で、A,/ACONSTANT/AVARIABLEはまだ登録していない。

|語|仕様|
|---|---|
|W, / L, / X,|下位16/32/64ビットをHEREへLEで格納。自動整列なし。必要な全幅を先に確保|
|XD,|二倍長入力を消費し、下位64ビットだけを8バイト格納。2,の16バイト格納とは異なる|
|WFIELD: / LFIELD: / XFIELD:|オフセットを2/4/8バイトに整列して幅2/4/8を加える。作成した語は入力アドレスにフィールドオフセットを加える|
|2FIELD:|8バイト整列、サイズ16のフィールド|
|MAXALIGN|HEREを8バイト整列。容量不足はHEREを保持|
|MEM,|HEREに指定バイト数を確保し、重なりを考慮してコピー。自動整列なし|
|SAVE-MEM-DICT|MEM,相当の確保・コピー後、新領域のaddr/lengthを返す|
|->HERE|既存のデータ領域内でHEREを設定。領域外はMemoryExhausted。辞書項目は削除しない|

幅付きカンマ、MEM,/SAVE-MEM-DICT、->HEREは、入力不足・範囲外・容量不足を変更前に検査し、失敗時にHEREと入力を保持する。書込前に失敗する場合は格納内容も保持する。コピーした生セルをアドレスと推測しない。復元・追加後もフィールドオフセットを維持し、X,で格納した生の数値を自動再配置しないことを確認した。

->HEREで名前付き語が使っている領域を回収しないこと。これはFORGET/MARKERの代用ではない。型付き参照の寿命追跡との統合は子616で行う。

検証：通常／全機能群無効のzig build test成功。src/tests/p03b_data_test.zigで格納順・容量不足・入力保持・重複コピー・フィールド・辞書復元追加を確認。verify-p03b-data.pyは基本12＋境界/コンパイル等276＝288ケースでSigma・指定Gforthとも成功。

```sh
python3 scripts/verify-p03b-data.py zig-out/bin/sigma --gforth-build .work/gforth-audit/gforth-build --report .work/p03b-data-check/results.json
```

ログは.zig-cache/p03b-data-test.log、p03b-data-minimal.log。JSONは.work/p03b-data-check/。P03aは737b660でpush済み、今回の12語は未コミット。

## 後続のP03b / P03c

A,等のアドレス登録と新イメージSIGIMG45/46/47は未実装。現時点の形式はSIGIMG42/43/44のまま。今回の新語も古い組込表のイメージとは互換でなく、既存の検証で安全に拒否する。

子616は型付きアドレスの登録・書込み・寿命追跡、子617は616に依存する新イメージ・追加読込・事前検証。P03bを完了にするには、P00の再配置表・到達可能ヒープ・部分書込み・MOVE・FREE・FORGET/MARKER・破損表の事前検証をまとめて満たす必要がある。writeCellだけでなく、words_width.zigとwords_data.zigの直接書込みも追跡対象に接続する。アドレスに見える生数値の自動再配置は行わない。

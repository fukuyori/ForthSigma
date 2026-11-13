# P03 メモリーとデータ配置の実装記録

2026-11-13。P03（tque 546）のうち、P03a（560）の44語を実装。P03b（561）はデータ配置12語（子615）と型付きアドレス3語・寿命追跡（子616）を実装。新イメージ・再配置（子617）は構造コーデック（子618）まで実装し、保存・復元への統合は未実装。P03c（562）のヒープ・伸長バッファーは未着手。対象語と完了条件は[実装フェーズ](GFORTH_WORD_PHASES.md)、確定設計は[P00仕様](GFORTH_P00_SPEC.md)。

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

実装はsrc/core/words_data.zig。親561は未完了。A,/ACONSTANT/AVARIABLEと追跡は後述の子616で追加した。

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

->HEREで名前付き語が使っている領域を回収しないこと。これはFORGET/MARKERの代用ではない。型付き参照の寿命追跡は子616で接続した。

検証：通常／全機能群無効のzig build test成功。src/tests/p03b_data_test.zigで格納順・容量不足・入力保持・重複コピー・フィールド・辞書復元追加を確認。verify-p03b-data.pyは基本12＋境界/コンパイル等276＝288ケースでSigma・指定Gforthとも成功。

```sh
python3 scripts/verify-p03b-data.py zig-out/bin/sigma --gforth-build .work/gforth-audit/gforth-build --report .work/p03b-data-check/results.json
```

ログは.zig-cache/p03b-data-test.log、p03b-data-minimal.log。JSONは.work/p03b-data-check/。P03aは737b660、データ配置12語はad34fefでpush済み。

## P03b 型付きアドレス登録・寿命追跡（3語、子616）

実装はsrc/core/address_registry.zig。生数値からの型推測はしない。

- `A, ( addr -- )`は8バイトをHEREへ格納し、そのセルをアドレスとして明示登録する。
- `ACONSTANT ( addr "name" -- )`は定数の辞書項目の値を登録する。
- `AVARIABLE ( "name" -- )`は0初期化の8バイト変数を作り、その値セルを登録する。名前入力は既存の定義処理を使い、複数行・コンパイルされた定義語でも使える。

登録表はVMごとに最大2,048件。格納位置（メモリー／辞書項目）、値、参照先の領域、状態（有効／部分破損／無効）を分けて保持する。これは実行中の内部表であり、P00の32バイトのディスクレコードとは別である。表が満杯ならMemoryExhausted。A,とMOVE等は容量をデータ変更前に検査し、型情報を捨てて処理を続行しない。

NULL、固定システム領域、辞書データ、使用中ヒープの参照を区別する。入力バッファー・ローカルフレーム・範囲外等は無効参照となる。HEREへの参照は後続確保の前にも登録できる。格納位置自身も永続化対象の領域内でなければ有効にならない。

全セル幅の!、X!、XD!、F!/DF!等で既存の型付きセルを更新すると型を保ち、値を再検証する。部分書込みは、同じバイトを書いただけでも破損状態にする。全セル更新で修復できる。新たな通常のカンマには型を付けない。COPYは明示登録のあるセルだけを引き継ぐ。

MOVE/CMOVE/CMOVE>はコピー前の登録を退避して処理し、全登録セルが含まれる場合に型も複製する。部分セル・破損元のコピーは有効な参照へ昇格させない。CMOVEの重なりで実際の値が元の登録値と変わった場合も破損扱い。重なる格納セルは検証で拒否する。登録がない通常のコピーは大きな退避バッファーを使わない経路を通る。

FREEとRESIZEの縮小は消えた格納位置を除去し、残った参照先が消えた場合は無効にする。番地が再利用されても無効参照は復活しない。RESIZEで移動した場合、呼出元は返却アドレスを型付きセルへ書き戻す必要がある。FORGET/MARKER、負のALLOT、->HERE、コンパイル失敗時の巻戻しも追跡する。

メモリー・幅付きアクセスのほか、文字列、文字／浮動小数点の部分格納、ACCEPT、ファイル読込、書式変換等の書込みも登録へ通知する。キャッシュした値と実際のセルも検証し、不一致を黙認しない。

### 永続化の暫定制限

**新形式の保存・復元への統合前なので、型付き登録が1件でもある辞書のSAVE/SAVESYS/LOAD-DICTIONARY、直接のencode/restore/appendは暫定的に拒否する。** 有効な型付き登録でもInvalidImage（-264）。部分破損・解放済み等の無効参照はInvalidAddress（-9）。型情報なしの既存の辞書は従来どおり保存・復元できる。

Forthの保存・読込入口でホスト処理前に検査し、Tcl資源解放やファイル変更の前に失敗する。SAVE/SAVESYSが既存ファイルを変更しないことをCLIでも確認した。617で新形式の検証・保存に置き換えるまで、旧形式へ型情報を落として保存しない。

### 検証

- src/tests/p03b_address_test.zigの11回帰：明示型と生セルの区別、部分破損と修復、重複／方向付きコピー、解放後の同番地再利用、縮小、MARKER/HERE巻戻し、失敗した定義の掃除、容量不足時の変更前失敗、未確保領域にコピーした型の非復活、旧形式の保存拒否、複数行／コンパイルされた定義語。
- verify-p03b-address.pyは基本3＋実行／定義／コピー15＝18ケースで指定Gforthと一致。型・寿命・保存のSigma固有検証は上記のZig回帰とCLIで行う。
- 通常／全機能群無効のzig build test成功。P03a 1,376とデータ配置288ケースも現在の実行体で再確認。
- CLIでSAVE/SAVESYSの-264、部分破損SAVEの-9と既存ファイル保持を確認。

```sh
python3 scripts/verify-p03b-address.py zig-out/bin/sigma --gforth-build .work/gforth-audit/gforth-build --report .work/p03b-address-check/results.json
```

ログは.zig-cache/p03b-address-test.log、p03b-address-minimal.log。JSONは.work/p03b-address-check/（legacy-guard.jsonも含む）。子616は16862f1でpush済み。

## P03b 新形式コーデック・構造検証（子618）

src/core/image_format.zigにSIGIMG45/46/47の読み書き部品と、Stateを書き換えない構造パーサーを追加。[形式の記録](IMAGE_FORMAT45.md)。112バイトヘッダー、32バイト再配置、24バイトのヒープオブジェクトヘッダー、CRCを扱う。Word/Opのパディングはゼロ化し、ネイティブABIのサイズ・配置・エンディアンを検査する。

長さ・個数・予約領域・enum・範囲・重複セル・参照値の一致と、明示登録をたどったヒープ到達可能性を検査する。ルートのある循環参照は許し、孤立オブジェクトを拒否する。生の数値から型を推測しない。

src/tests/image_format_test.zigの10テストで3種類のマジック、破損ヘッダー／レコード／コード、境界参照、循環、重複、標準バイト列と128件のビット変異を確認。通常／全機能群無効のzig build testが成功。ログは.zig-cache/p03b-format-test.logとp03b-format-minimal.log。freestanding_checkはコンパイル確認であり、Windows/Linux実機確認ではない。

この部品は入力とWorkspaceを借用し、辞書をインストールしない。組込語一覧との照合、Stateからの収集、容量確保と保存・復元・追加は後続619/620で行う。公開SAVE/LOADはSIGIMG42/43/44のままで、型付き登録の暫定拒否を維持する。子618はb01ec43でpush済み。

## P03b 到達可能ヒープ収集（619配下621）

src/core/image_graph.zigに明示登録からの収集部を追加。Stateを書き換えず、システム／データ／利用者定数の登録を根に、ヒープ内の登録をたどる。共有・循環を重複させず、元のペイロード番地順に並べる。結果のオブジェクト内容はState.memoryを借用するため、消費中はStateを変更しない。再配置レコードは618の形式へ変換する。

到達しないブロック・生の数値・孤立領域内の登録は含めない。孤立した破損登録も収集対象外とする一方、収集する登録の実値・寿命・範囲・重複は検査する。address_registry.validateRecordを切り出し、既存の全件検査は従来どおり維持する。

src/tests/image_graph_test.zigの3テストでルート付き循環・共有・内部参照、孤立した破損登録と生セルの除外、NULL／固定／データ／定数ルート、解放済み・部分破損・入力領域参照の拒否とState保持を確認。通常／全機能群無効のzig build testが成功。ログは.zig-cache/p03b-graph-test.logとp03b-graph-minimal.log。収集部は753f259でpush済み。

619は収集621と内部ポインター生成更新の接続622に分割。622で動的文字列等の自動登録と除外の確認を追加（後述）。SAVE/LOADへの接続もまだ行わない。

## P03b 内部ポインター登録（619配下622）

動的文字列の$!/$INITとsetStringLength（伸長・挿入・連結・ファイル読込等の共通経路）で所有セルを明示登録する。文字列配列は外側の所有セルと、初期化した各要素の所有セルが対象。RESIZEの移動時は既存の型コピーを使い、所有セルを書き戻して参照を修復する。FREEや縮小は既存の寿命追跡で登録を除去する。

words_tools.zigのREPLACES連結リストは固定ルートと各nodeのnextを登録し、$SUBSTITUTE/$UNESCAPE等の一時文字列スロットも登録する。新しい所有セルとREPLACESの必要件数はヒープ確保前に容量を検査する。

heapAllocate/heapResize呼出箇所を確認。text_input.zigの解釈時S"、words_defining.zig/words_memory.zigの割当は生アドレスを返すので自動で根にしない。Tcl受信バッファーはState内のホスト実行状態が所有し、登録せず到達しないものを収集しない。入力・ローカル領域の一時所有セルも保存用登録から除外する。ホストの数値をポインターとして推測しない。利用者が除外領域へのアドレスを明示登録した場合は保存前検査で拒否する。

src/tests/internal_pointer_test.zigの4回帰で文字列の移動・置換・解放、配列の移動・縮小・解放、入力所有セルの除外、ローカル/範囲外アドレスの分類、表満杯時の確保前失敗、置換リスト更新と一時スロットの到達性を確認する。通常／全機能群無効のzig build testが成功。ログは.zig-cache/p03b-internal-test.logとp03b-internal-minimal.log。622と親619は完了（auto）。今回の変更は未コミット。

型付き登録が増えるため、動的文字列・置換リストも旧形式では保存拒否となる。既存2件の往復回帰は暫定拒否と実行時の内容保持を検証する形へ変更した。620で新形式の往復検証へ戻す。通常の旧形式メモリー節検証は生のヒープ文字列を使って維持した。公開SAVE/LOADへの統合は引き続き620で行う。

## 後続のP03b / P03c

子617は616に依存する新イメージ・追加読込・事前検証。現時点の形式はSIGIMG42/43/44のまま。構造コーデックは618で実装済み。619で到達可能ヒープ収集・内部ポインター登録を行い、620で保存・復元・追加へ統合する。

617では動的文字列等の既存内部ポインターを明示登録し、ホスト資源・入力・ローカル等の除外を保存時にも検証する。現在の暫定拒否はwords_system.zigとdictionary_image.zigのrequireLegacyImageにある。型付き新形式を保存・復元できるように置き換える際、ファイルopenより前の検証・容量確保、Tcl資源解放との順序も確認する。

空／既存データありの追加、同一イメージ2回追加、再保存、NULL/固定/データ/ヒープ相互参照、破損表、容量不足、部分書込み・MOVE・FREE・FORGET/MARKERをまとめて検証するまで親561を完了にしない。P03c（562）は引き続き未着手。

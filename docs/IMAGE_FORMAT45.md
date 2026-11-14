# SIGIMG45/46/47 構造コーデック

2026-11-13。P03bの公開SAVE/SAVESYS/復元/追加で使用する形式。[P00仕様](GFORTH_P00_SPEC.md)、[P03記録](P03_IMPLEMENTATION.md)。コーデックはimage_format.zig、エンコードはimage_encoder.zig、完全復元はimage_restore.zig、追加配置計画はimage_append_plan.zig。旧SIGIMG44以前は拒否する。

ファイルはヘッダー、Word列、Op列、名前、論理メモリー、再配置表、ヒープオブジェクト列、CRC32の順。フレーミングの整数はLE。Word/OpのみネイティブABIを使用し、書込み時にパディングをゼロ化する。

|オフセット|バイト数|内容|
|---|---:|---|
|0|8|SIGIMG45（通常）/46（graphics）/47（audio）|
|8/12/16/20|各4|語数、Op数、HERE、名前長|
|24/28|各4|メモリー構成m/l|
|32|2|ヘッダー長112|
|34/35|各1|セル幅8、ABIエンディアン（1 LE / 2 BE）|
|36|4|予約、0|
|40/44|各4|再配置数、オブジェクト数|
|48/56/64/72/80/88|各8|Word/Op/名前/メモリー/再配置/ヒープの各節長|
|96|4|組込語数|
|100/102|各2|Word/Opのサイズ|
|104|8|ABI配置署名|

ABI配置署名はWord/Opのサイズ・アラインメント、Word全フィールドのオフセットとサイズ、Opのkind/valueオフセットに加え、WordKind/OpKind/Builtinのフィールド名とタグ値をFNV-1aで畳み込む。これはネイティブ配置の照合であり、組込語の意味やIDの互換性を保証しない。組込語一覧との照合はローダー側の責務。

メモリー節は固定システム領域、data_startからHEREまでのデータ、ソースファイル表と読込フラグ。ヒープ全体をこの節へコピーしない。

再配置レコードは32バイト。0:格納領域u8（system=1/data=2/heap=3/word=4）、1:参照領域u8（NULL=0/system=1/data=2/heap=3）、2:予約u16=0、4:語ID u32、8:格納位置u64、16:参照位置u64、24:セル幅u64=8。word以外は語ID=0、wordは格納位置=0で、利用者定数のvalueだけを対象にする。systemは論理番地、dataはdata_startから、heapは保存時mからの相対位置。NULLの参照位置は0で、systemの0は拒否する。

各ヒープ要素は24バイトのヘッダーとペイロード。ヘッダーは0:連続ID u32、4:予約u32=0、8:保存時mからのペイロード位置u64、16:サイズu64。サイズと位置は8バイト整列。元の16バイト管理ヘッダーを含む領域が重ならない昇順とし、保存時heap_top以内に収める。再配置数・オブジェクト数の上限は各2,048。

末尾4バイトは、それ以外の全バイトに対するCRC32。パーサーは節長の整合・オーバーフロー・ABI・列挙値・語/コード/データ範囲・予約領域・再配置の重複や実値との一致を検査する。明示登録だけをたどり、非ヒープのルートから到達するオブジェクトのみ許可する。ルート付き循環は有効、孤立循環は無効。生セルをアドレスと推測しない。

parseは入力と呼出元Workspaceを借用し、Stateを変更しない。戻りViewは両方の寿命に依存する。これは構造検査であり、実行可能な辞書の復元完了を意味しない。Stateからの到達可能ヒープ収集は619配下621のimage_graph.zigへ追加済み。内部ポインター生成更新の接続も622で追加済み。容量確保・組込語照合・保存/復元/追加は620〜630で公開経路へ統合済み。

The ABI signature includes the complete builtin enum. Adding builtin tags may invalidate older files using the same magic. Startup builtin count and tag matching are also strict; stable execution-token numbers alone do not guarantee acceptance across implementation revisions.

A string_value WordKind has an eight-byte data-space owner field. Its memory relocation is mandatory. A non-NULL pointer must name the start of a reachable heap payload whose first eight bytes contain a length no larger than the remaining payload. This validates known ownership without guessing pointer types from raw cells.

Macro words use the fixed case-sensitive namespace id 255, distinct from regular wordlists 1 through wordlist_count (at most 64). Word/vocabulary validation permits that fixed id; both append paths preserve it. REPLACES now uses string_value data owners as roots instead of a fixed system replacement-list head. Private in-progress capture buffers and capture targets are not persisted. Older builtin tables/ABI signatures remain incompatible even with the same image magic.

P07a adds the Word compile_only boolean to the serialized fields and ABI layout signature. The byte must be0 or1 before decoding a Word. Full restore and both append routes retain user restrictions. Earlier builtin/Word ABI signatures are rejected even though the framing magic remains SIGIMG45/46/47.

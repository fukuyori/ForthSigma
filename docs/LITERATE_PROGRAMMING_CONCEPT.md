# 文芸的プログラミング・ソース内ヘルプ・ソース内テストの構想

2026-11-21。構想段階であり、実装は行わない。tque には登録していない。

Knuth の文芸的プログラミング(WEB)の考え方を forthz に取り入れる。ヘルプテキストとテストコードを
ソースに書けるようにし、デバッグ機能として使う。

## 方針

- ヘルプテキストとテストコードはソースファイルに書く。辞書と辞書イメージ(SIGIMG)には入れず、
  サイズを増やさない。
- デバッグ機能を使うときだけソースファイルから読む。
- `-Ddebug=false` のビルドでも、同じソースを読み込めるようにする。

## 1. Markdown ソースの読み込み(`.fs.md`)

- `INCLUDE` / `REQUIRE` は、`.fs.md` の中の ```` ```forth ```` で囲んだブロックだけを解釈し、
  地の文は読み飛ばす。
- 読み飛ばした行も行番号に数える。`LOCATE`、エラー表示、`--lint` は `.md` の行番号のまま使える。
- tangle の工程は設けない。Markdown を表示できるツールで開けば、その表示が weave の出力になる。
- WEB の名前付きチャンクと並べ替えは採用しない。Forth は定義済みのワードしか使えず、
  IMMEDIATE ワードやパースするワードがあるので、実行しないとソースの意味が決まらない。
  並べ替えると行番号の対応と対話的な読み込みが崩れる。上から下へ説明したい場合は `DEFER` を使う。
- noweb でも、`#line` を持たない言語ではエラー位置が tangle 後のファイルの行になる。
  そのため、エラーメッセージを書き換える別ツール Noerr が作られている(Ramsey)。
  `.fs.md` を直接読み込めば、この書き換えは要らない。
- コードは整形表示(prettyprint)しない。Ramsey は、プログラムは読むのと同じくらい編集するので、
  コードは書いたままに近い形で表示するのがよいとして、整形表示をほとんど使わない。

未決定:

- フェンスの言語名を `forth` だけにするか。
- 拡張子で切り替えるか、別のワード(例: `INCLUDE-MD`)にするか。

## 2. ソース内ヘルプテキスト

定義の直前に続く `\` 行をヘルプテキストとする。印は付けない。空行があればそこで区切る。

```forth
\ The chosen instrument gets chip's steps (one of MSX ST NES C64 SCC AMIGA), or the
\ standard sound's for 0.
: STYLE ( chip -- )
```

```
HELP STYLE
STYLE ( chip -- )
  The chosen instrument gets chip's steps (one of MSX ST NES C64 SCC AMIGA), or the
  standard sound's for 0.
```

- `HELP name` を実行したとき、`LOCATE` が使う `source_file`、`source_line`
  (`src/core/defs.zig` の Word)をもとにファイルを開き、直前の行を読んで表示する。
  ヘルプテキストは保存しない。
- `.fs.md` では、コードブロックの直前にある地の文をヘルプテキストとする。
- 組み込みのグラフィックス・オーディオライブラリは、`embeddedSource` の内蔵テキストから読む。
- ソースファイルがない場合(辞書イメージだけを別の環境に持っていった場合など)は、
  今の案内(SEE で定義を見る)を表示する。
- 読み込んだ後にファイルを編集すると、行がずれる。`LOCATE` と同じ制約である。
- 区切りの見出しコメントやコメントアウトしたコードが混ざることがある。表示だけなので許容する。
- `include/` の既存ソースは、書き直さなくてもそのまま表示できる。
- JONESFORTH の `jonesforth.f`(1788 行)は、専用のツールを使わず、定義の直前の `\` 行で
  そのワードを説明している。この規則は、こうしたコメントだけの文芸的な書き方にもそのまま当てはまる。

## 3. ソース内テスト

### 書き方

Hayes 形式の `T{ ... -> ... }T` で書く。Forth 2012 は、テストケースを John Hayes の
tester.f に合わせて書くよう求めている(`reference/forth-2012.pdf` の序文)。

```forth
TEST: STYLE
  T{ 0 STYLE -> }T
  T{ 99 ' STYLE CATCH NIP -> -24 }T
;TEST
```

- `T{` `->` `}T` は普通のワードとし、書いた場所で実行する。トップレベルに `T{ }T` を
  並べた既存のテストファイルも、そのまま動く。
- `TEST: name ... ;TEST` で囲んだ部分は、通常の読み込みでは `[IF]` の読み飛ばしと同じように
  扱い、実行もコンパイルもしない。
- `-Ddebug=false` のビルドでは、`TEST:` から `;TEST` までを読み飛ばすだけにする。

### 実行

- 起動オプション `--test`: ファイルを読み込んだ後に、`TEST:` ブロックを実行して結果を報告する。
- ワード `RUN-TESTS`: 対話中に同じことを行う。
- `TEST:` ブロックの位置は記録しない。実行するときに、読み込み済みのソースファイルを走査して
  探す。サイズは増えない。走査の時間はテストを実行するときだけかかる。
- テストのためにコンパイルした分は、終わったら辞書を巻き戻して破棄する(`MARKER` と同じ考え方)。

### 終わらないテスト

あるプログラムが停止するかどうかを判定するプログラムは作れない(Stoddart は Forth で、
`( xt -- f )` の判定ワード H が存在しないことを示している)。テストが無限ループに入った場合に
備え、実行する操作の数に上限を設ける必要がある。

既存の `--max-steps N` は、コンパイル済みコードを N 操作実行したところで `STEP LIMIT !` で実行を
終える。`CATCH` では捕まえられない(`docs/DEBUGGING.md`)。このままでは、上限に達したテストを失敗と
数えて次のテストに進むことができない。テストごとの上限をどう設けるかは未決定である。

### 出力の照合

JONESFORTH のテストは Hayes 形式ではなく、出力を照合する方式である。`test_*.f` を実行した出力を、
期待する出力のファイル `test_*.f.out` と diff で比べる(Makefile)。起動メッセージを抑えるため、
テストの前に `: TEST-MODE ;` を定義している。`T{ }T` では書きにくい、表示するワード(`.`、`TYPE` など)
の検査に向く。Hayes 形式の補助として採用するかどうかは未決定である。

### 例外の検査

Hayes 形式には例外を検査する専用の書き方がないので、`CATCH` と組み合わせる。
Forth 2012 の THROW(9.6.1.2275)は、例外が起きたとき、すべてのスタックの深さを CATCH の前と
同じにし、例外コードを積むと定めている。戻した位置にある値の中身は規定していない。
そのため、引数の位置に残った値は `NIP` などで捨ててから比べる。
Read も、ANSI Forth は THROW がパラメータスタックポインタを CATCH の時点の値に戻すことを
求めていると述べている。

### 名前の衝突

2026-11-21 に、組み込みワード(`src/core/help_text.zig`)、`include/`、`examples/` を検索した。
`TEST:`、`;TEST`、`RUN-TESTS`、`T{`、`}T`、`->` と衝突する名前はなかった。

## 未確認・未決定

- Hayes の tester.f の詳細な仕様(`T{` `->` `}T` の失敗時の表示、`TESTING` の動作、
  浮動小数点の比較)は未確認。`reference/forth-2012.pdf` にはテストの付録が含まれていない。
- `.fs.md` のフェンスの言語名と、読み込みを切り替える方法(第1節)。
- テスト結果の報告の形式と、`--test` が失敗時に返す終了コード。
- 終わらないテストを止める方法(テストごとの操作数の上限と、`--max-steps` との関係)。
- JONESFORTH の出力照合方式を、Hayes 形式の補助として採用するかどうか。

## 参考文献

文書はすべて `reference/` にある。JONESFORTH は、`reference/` のリンク先のリポジトリを読んだ。

- Norman Ramsey, "Noweb — A Simple, Extensible Tool for Literate Programming," Tufts University. https://www.cs.tufts.edu/~nr/noweb/
- Richard W.M. Jones, "JONESFORTH," GitHub (nornagon/jonesforth のミラー), 2009-09-11. https://github.com/nornagon/jonesforth (jonesforth.S 1.47、jonesforth.f 1.18。パブリックドメイン)
- Bill Stoddart, "The Halting Problem in Forth," 2016-09-01.
- Andrew Read, "Concept and implementation of an extended return stack to enhance subroutine and exception handling in FORTH," 2014-06.
- Forth 200x Standardisation Committee, *Forth 2012 Standard*. 9.6.1.0875 CATCH、9.6.1.2275 THROW.

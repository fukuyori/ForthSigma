# 640 設計レビュー依頼と実行状態

2026-11-20。対象はdocs/GRAPHEME_DESIGN.mdの仕様案。API、Unicode 18.0.0 / UAX #29 revision 49の状態機械、strict UTF-8、不正入力と計算量、試験方針について、関連実装も参照して高・中の問題と具体的な解決案を日本語で報告するようClaude Codeへ依頼した。Read/Glob/Grepだけを許可し、編集・コマンド実行は禁止。

実行は認証段階で失敗し、レビュー結果は得られていない。API使用量とツール実行は0。返された理由：`Failed to authenticate: this login reached its time limit and cannot be renewed.` 再認証方法として`claude auth login`を案内された。詳細設計は未レビューの案であり、採用済みの仕様として扱わない。本体実装・生成器は未着手。

固定した依頼と設計コピー、CLI応答は.work/640/review/{request.txt,design.md,result.json}に保存。認証回復後に同じ案をレビューし、原文・評価/採否・採用設計を分けて保存してから実装する。

## 再認証後の結果

レモンの再認証後に再実行し、正常終了した（34 turn、permission denialなし）。[原文](640-design-claude-review.md)と[評価・採否](640-review-response.md)を保存。上記の未レビュー・未実装は初回失敗時の記録であり、現在状態は採用設計と実装記録を参照する。

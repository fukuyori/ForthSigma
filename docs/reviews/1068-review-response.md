# 1068 保存アプリ起動：実装レビュー評価

2026-11-20。[実装レビュー原文](1068-implementation-claude-review.md)、[限定再レビュー](1068-followup-claude-review.md)。Read/Glob/Grepのみで、実行確認はロクが担当。

- M1を採用し、POSIXのumask一時変更を除いた。空の排他fileを0777で作ってkernel適用後のmodeをfstatし、内容書込み前に0600へ下げる。footerのfflush成功後、同じfdへ取得modeを戻してcloseする。process-wide umaskは変更しない。
- L1はコード側の既存順を維持する。format以外のlog/lint/profileとdeferを復元前に用意し、復元失敗を記録できるようにする。formatではこれらを作らず、Presentの完全検査後にだけ整形する。採用設計をこの順へ合わせた。
- L2を採用し、WindowsのX:filenameで一時ファイルもそのdrive-relative directoryへ作る。
- L3は空argvならINVALID ARGUMENTSの診断とstatus1を追加した。通常のOS起動ではargv0がある。
- L4のhidden_word重複行は既存のもので、今回の動作修正には含めていない。

限定再レビューは修正箇所に高・中の欠陥なし。低指摘の電源断耐性は初期設計でも保証しておらずfsync等を追加しない。新しい生成実行体のmode/ACLはumask/directory継承によるものとし、既存出力先の独自ACLコピーは行わない方針を明記した。readonly、自己file ID、最終symlink/reparse pointは拒否する。

一時的に最終権限で作る瞬間は空のfileであり、内容は0600への変更成功後に書く。OS/FSによるACLの全パターン・電源断・敵対的なdirectory同時変更を実証したわけではない。所有する通常の保存失敗では、既存先保持とtemp回収をテストする。

実行確認は[実装・検証記録](../SAVED_APPLICATION_STARTUP_IMPLEMENTATION.md)に保存した。Windows/Linuxの22構成、core/host、保存故障7段階、専用console/PTY、画像破損、引数と英日文書を確認。Macはクロスコンパイルのみで実機1124を残す。レビュー原文の静的評価と実行結果を混同しない。

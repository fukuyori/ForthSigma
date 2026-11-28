# 参照元と移植の通知

作成日：2026-11-28

## Rust版

参照プロジェクトは利用者の arduboy-emu、読取り元は `D:/home/source/rust/arduboy-emu` である。MIT/Apache-2.0の選択から、本ディレクトリでの翻訳・移植にはMITを選ぶ。

Copyright (c) 2025 arduboy-emu contributors

許諾全文は [LICENSE-MIT-RUST.txt](LICENSE-MIT-RUST.txt) に保存した。

今回の成果物は `docs/SPECIFICATION.md` である。opcode分類・mask、CPU状態・演算、busと周辺register、ボタン配線、HEXの対応typeの確認に下表のソースを参照した。Rustのコード本文・依存crate・ゲームROMを取り込んだ実装は今回作成していない。仕様は非対応での停止、厳格なHEX、時刻付きSPI/EEPROM、mono音声、OLEDの表示変換、保存規則を別途定めた。RustのTimer4 vectorと通常実機のスピーカー配線には差があり、一次資料を優先した。

後続実装がコード・テストを翻訳/移植する場合は、移植先ファイル先頭にも元パス、MIT選択、変更の旨を記し、ここに元→移植先の対応と変更内容を追記する。依存物やROMは個別に権利を確認する。

Git操作をせず2026-11-28に読んだファイルを識別するため、SHA256を記録する。

| 元ファイル | SHA256 |
| --- | --- |
| `crates/core/src/opcodes.rs` | `f0890d8e292c7b256f5b4043616c3c2d8048dcffb73bc96e3b0f2f1ad2b14a7e` |
| `crates/core/src/cpu.rs` | `ac54f9054cf5b9483e93926f5d6d22521794d3448fee49f0e92b954c50e7df1c` |
| `crates/core/src/memory.rs` | `dd12097c00eee2c7f7be12a65a0102c30147b0c1bab5d727440173d73f67a373` |
| `crates/core/src/lib.rs` | `ada6b45b855fa83b5c429194a947f720f49f610a8d48e408c2233844deba5683` |
| `crates/core/src/hex.rs` | `82082bd7cfa4776061fe7cb247c4b305cf6e1254f39cc86b6da2e4a9412bf64b` |
| `crates/core/src/display.rs` | `35194479e489ace55beb85126272f4e28fb93fe6dd9be81a5eb4cb9bfd96dbcc` |
| `crates/core/src/peripherals/mod.rs` | `153719e045a28a2b68324d633714bdc59b501e907fdb6b4a6a000738821fe125` |
| `crates/core/src/peripherals/timer8.rs` | `6dcac4aadf37bf88ef20ac7da4835c015580a9a57772f5207aec7dce4596eaf4` |
| `crates/core/src/peripherals/timer16.rs` | `28892bf19178ad8f8033a3c3004867ebfa16f356fa2c0411c84d2a17d48e2559` |
| `crates/core/src/peripherals/timer4.rs` | `d252e56afcc59a2e4a9b148e3e7912806c3f3db9b2129278e6844d4318e03527` |
| `crates/core/src/peripherals/adc.rs` | `e71653f458d5262147048a8c6d48f9a53e3367554b6681776c14190165aaffcc` |
| `crates/core/src/peripherals/pll.rs` | `695b3c0fb3ff2a88b31abac0fb8cbea1578f77f0cce33f1d4f85b7a2cbaeafa4` |
| `crates/core/src/peripherals/spi.rs` | `bf7409dea1090ab653146f3e254dbf81858053264b230b3c8e63414110a05ad6` |
| `crates/core/src/peripherals/eeprom.rs` | `4678c594419c3c3b1c6c84dfa900acde52eb045de4ebcefd62d40ad32879a07d` |
| `LICENSE-MIT` | `ff1c5ae4ce74fb0b21d500da47f0e143623c335b3845e4bcf7b6b8c1dbc127ac` |

## 一次資料の照合

- [avr-libc iom32u4.h](https://github.com/avrdudes/avr-libc/blob/main/include/avr/iom32u4.h)：Timer4 vector、register位置、bit定義を照合した。ヘッダー本文はコピーしていない。
- [Arduboy2Core.h](https://github.com/MLXXXp/Arduboy2/blob/master/src/Arduboy2Core.h)：通常ARDUBOY_10のボタン、OLED、speaker PC6/PC7、RGBのactive-lowを照合した。ライブラリ本文は取り込んでいない。

参照日は2026-11-28である。Web上のmain/masterは可変であり、ここでは参照箇所と照合結果を仕様書に残す。将来コードを取り込む場合は、その版とライセンス全文を別途固定する。

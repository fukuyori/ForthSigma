# 1179 Apple II speaker + Mockingboard model: independent review

2026-11-22. The reviewer was a separate Claude agent that had not seen the design discussion. It read the code, the tests, the specification and the source documents, ran the three scripts with the Debug executable, and ran fuzz and mutation experiments of its own. It did not modify the repository and opened no audio device. The text below is its report as received; the response is in [1179-review-response.md](1179-review-response.md).

---

No High findings. The model code matches its declared rules everywhere I probed except one Medium doc/code contradiction (AY reset pin). The batched advance is exactly equivalent to single-stepping in every case I could construct. The rest is test gaps and doc issues.

All three scripts pass with `zig-out/bin/sigma` (Debug): `verify-apple2-audio.py` exit 0 with 19 groups, `verify-apple2-audio-stream.py` 19 cases, `verify-model-common-words.py` 42/42. Nothing in the repository was modified; no audio device was opened.

## Confirmed findings

### Medium

**M1. "While PB2 is low the AY stays in reset" is not what the code does** — `include/apple2-audio.fs` lines 75-89, 127-130, 142-145; doc line 73.

The reset acts once, on the falling edge. During the hold:
- the generators keep running (tones flip every step at period 1, the LFSR shifts);
- direct writes (`A2-AY!`, targets 65536+) are accepted and make sound;
- those writes survive the release.

Only bus-function writes are blocked. Reproduction:

```
4 A2-CARD! A2-RESET 7 50178 0 A2-WRITE          \ DDRB=7, ORB=0: PB2 low
15 8 0 0 A2-AY! 62 7 0 0 A2-AY! 100 0 0 0 A2-AY!
8 0 0 A2-AY@ .                                   \ 15  (register written while in reset)
800 A2-TO A2-SAMPLE . .                          \ 0 5461  (left channel sounds while held)
0 A2-CHIP! A2-HELD @ . A2-LFSR @ .               \ -1 37378  (LFSR not at its reset value 1)
4 50176 800 A2-WRITE 0 A2-CHIP! 8 A2-R@ . A2-LFSR @ .   \ 15 37378 after release
```

Expected from the doc: registers 0 and silence while held, reset state on release.

The Python oracle has the same behaviour (`Chip.step` ignores `in_reset`; `Model.store` bypasses it). A mutant that freezes the generators while held is killed only because the oracle disagrees with it, at line 279.

Fix, either:
- in code: skip `A2-ADVANCE-STEPS` while `A2-HELD`, and ignore or refuse direct writes while held; or
- in the doc: state that the reset is edge-triggered, the generators keep running from reset values, and direct access bypasses the pin.

Then add a hand test for whichever is chosen.

### Low

**L1. The batched advance is not constant-time** — lines 83 and 87; doc lines 114, 147.

The noise loop runs once per expiry, and so does the envelope loop for non-holding shapes. Measured on ReleaseFast:

| Input | Time |
| --- | --- |
| `4 A2-CARD! A2-RESET 100000000 A2-TO` | 0.76 s |
| same with `1000000000` (16 emulated minutes) | 7.6 s |

`9223372036854775807 A2-TO` with a card would effectively never return, although the API accepts ticks up to that value. The end-of-time tests poke `A2-CYCLE` directly, so they never see this. Results stay correct; per-frame rendering is unaffected.

Fix: reduce noise expiries modulo 131071 (the LFSR period) and non-holding envelope expiries modulo 64, or document the cost.

**L2. Large batches are untested** — `tests/scripts/verify-apple2-audio.py` lines 346-364 and the hand tests.

In the "54321-cycle jump" test the queued events split the jump into batches of at most about 37 steps. The hand tests reach 255 steps with one generator relevant. Three mutants survive the whole script:
- envelope expiries capped at 100 per batch;
- noise expiries capped at 100 per batch;
- tone parity wrong when there are more than 300 expiries in a batch.

The current code is correct here (see "Checked and correct"). Add a test with jumps of 10^4 to 10^6 cycles and no intervening events, and/or an exhaustive `A2-EXPIRE` check against a loop.

**L3. The documented error-check order is untested** — doc line 127; code lines 110-112 and 171-175.

Mutants that throw -21 (no card, direct target) before the tick check survive, in both `A2-CHECK` and `A2-READ`. Add cases such as `1 65536 99 A2-WRITE` and `65536 99 A2-READ` with slot 0 after `100 A2-RUN`, expecting -24.

**L4. `A2-RESET` clearing `A2-SLOW` is undocumented and untested** — line 44; doc line 114. The ZX doc states it; this one does not. The mutant that removes it survives.

**L5. `A2-MAX-FRAMES` rounding is only pinned by the stream script** — test line 392. The value checked is 0, and the expectation is the same formula as the code. Dropping the `DEN-1-fraction` term survives the main script; only `prime-exact-clock-limit-success` in the stream script would catch it. No test puts the first rejected frame count one past the limit.

**L6. Post-reset envelope state is not declared in this doc** — doc line 82.

After `A2-RESET` or a pin reset, the envelope is held at level 15 until R13 is written:

```
4 A2-CARD! A2-RESET 16 8 0 0 A2-AY! 63 7 0 0 A2-AY! 1000000 A2-TO A2-SAMPLE . .   \ 0 5461, forever
```

The ZX doc declares this explicitly (its line 59). Here it hides behind "same as ZX", and it matters more because Mockingboard software routinely pulses RESET. Add the sentence.

**L7. Doc statements stronger than the cited sources.**
- Line 76 (address 16 or more deselects the chip; the latch keeps all 8 bits) is not marked as a declaration. The datasheet says only that a valid high-order address latches the low 4 bits and that the buffers go high-impedance on an incorrect one. Whether an invalid latch deselects or leaves the previous address is not stated.
- Line 73: the datasheet says RESET zeroes the registers. Initialising the generators and the address latch is the model's choice and is not marked.
- BC2 tied high and the mapping PB0=BC1, PB1=BDIR, PB2=RESET are inferred from the manual's $07/$06/$04/$00 values. No cited source states them; the read function ($05) appears nowhere in the manual. Say this is an inference.
- Line 54 ("Apple's IIe material says a write toggles twice") has no entry in the source table.

**L8. Doc links to files that do not exist** — lines 8-9: `docs/measurements/2026-11-22-apple2-audio.json`, `docs/reviews/1179-claude-review.md`, `docs/reviews/1179-review-response.md`. Line 26 says the source SHA256s are in that JSON, so they are currently unverifiable.

**L9. The selected chip changes more often than the doc says** — doc lines 98 and 120.

The doc says the selection changes when time-advancing words are called. It also changes on `A2-SAMPLE` (leaves chip 0), `A2-READ`/`A2-WRITE`/`A2-AY@` with no advance, and `A2-RESET` (leaves chip 1). "A2-SAMPLE does not change state" is true only for model state.

Test line 294 is affected: after `8 A2-TO` it reads chip 1 while meaning the first chip. It passes only because both chips are identical there. Add `0 A2-CHIP!` before those reads.

**L10. Doc line 118 omits a precondition.** An emulator with its own 6522 that forwards pin values to `$Cs00`/`$Cs01` must first set this model's DDRA=$FF and DDRB=$07. Otherwise the model sees inputs and ignores everything.

**L11. Loading two play wrappers redefines the shared stream words** — `examples/apple2-audio-play.fs` line 3. `pcm-synth-play.fs` is `INCLUDED`, not `REQUIRED`. Loading the ZX and Apple wrappers together prints 35 "SAME NAME WORD EXISTS" warnings and creates a second `PS-HANDLE`; a handle retained after a failed close stays in the old one. This is the existing pattern, identical in the ZX wrapper.

## Suspicions (not defects I could reproduce)

- The oracle's `bus()`, `pb()`/`pa()`, `MASKS`, decode and `<= end` event rule mirror the Forth closely. They implement the declared rules, and I found no shared mistake other than M1, but an error in the declaration itself would pass both.
- Doc line 141 (silent output to a real device, 0 underruns) and the Debug underrun count of 85 were not re-run, since that opens the audio device.

## Checked and found correct

- **Batched advance.** `A2-EXPIRE` matches a per-tick reference loop for every count 0-69 (including counts at or past the period), period 1-32, n 0-149: 0 mismatches. A fuzz of 150 seeds compared fast, `A2-SLOW` and the oracle on full state and samples: no mismatch. It used direct register traffic on both chips, gaps from 0 to 600000 cycles in one batch, shortened periods, all R13 shapes. Noise half-step parity, hold reached mid-batch (count zeroed, remaining expiries dropped) and alternate shapes were also traced by hand.
- **Chip context.** Every path that touches chip state selects the chip explicitly. `A2-RESET` rewrites all 43 cells of both blocks whatever was current. The `/MOD` stack order in direct read and store is right. All errors are thrown before `A2-TO` or `A2-CHIP!`. Ctrl+C is only delivered inside audio waits (`src/host_audio.zig`), so it cannot split the swap.
- **Bus and pins.** Speaker decode `$C030-$C03F`, card page per slot, bit 7 chip select, bits 4-6 mirrored, ORA at registers 1 and 15, registers 4-14 ignored on write and -21 on read. PB/PA pin formulas, act-once function logic, latch to write without inactive, release straight into latch, read function driving only input bits.
- **AY.** Register masks against the datasheet, R14/R15 read rule, mixer, left = chip 0 and right = chip 1, byte order.
- **Time and queue.** Speaker mean and window; 284375/13376 and the 1/7-cycle claim; `A2-MAX-FRAMES` algebra and overflow (double-cell intermediate); queue full/order/compaction logic; same-cycle ordering.
- **Demo.** 1000 events (under 1024); chord periods and speaker toggle spacing give the stated pitches.
- **Stream wrapper.** A line-for-line stereo port of the ZX wrapper; cleanup paths are the same.
- **Counts in the doc.** 19 groups, 11 hand cases, 27 error cases, 42/9 common-word cases all match.
- **Citations.** Gayler PDF pages 29, 80, 95; Redbook printed pages 31, 43, 75, 137; Mockingboard A-9 to A-11, 3-10 and Appendix E "fCLOCK 1.023 MHz"; AY datasheet page 2 (reset pull-up, BDIR/BC1 table, DA7-DA4, I/O pull-ups); Rockwell RES and port read text. All say what the table claims, apart from L7.
- **Speed figures.** Rendering 49152 demo frames took 0.26 s on ReleaseFast and 3.75 s on Debug, in line with the doc's single measurement.

## Not checked

- Audible or silent output to a real device, underrun counts, Ctrl+C during playback.
- Windows, macOS and reduced-feature builds.
- The dictionary size claim (122880 to 148840).
- AY datasheet pages 4-5 (the envelope and divider text the doc defers to 1169) and `zx-ay-levels.fs` itself.
- Source file hashes (the JSON is missing).
- Read decode for slots other than 0 and 4 beyond reading the code.

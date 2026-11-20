# S-DSP native frame kernel design (task 1183)

2026-11-20. The approved emulator plan permits moving only measured slow sound models into the core. After ARSHIFT, the maximum BRR workload runs at 0.496 x real time on Windows and 0.556 x on WSL Linux. Forth remains the reference and default backend. This design accelerates the declared model, not real hardware micro-slots or SPC 700 execution.

## Boundary and ownership

Append AUDIO builtin `SND-SNES-FRAMES` and alias `SNES-FRAMES`, with stack `( regs aram voices globals history frames layout -- )`. Layout must be 1. Buffers are borrowed synchronously and never retained. No allocation, sound device, engine, handles, thread or audio output is involved. AUDIO-disabled builds reject REQUIRE-AUDIO normally; the reference Forth model remains usable.

Five nonoverlapping VM-memory buffers: 128 register bytes, 65536 owned ARAM bytes, 112 little-endian signed 64-bit voice cells (8 x 14), 10 little-endian signed 64-bit global cells, 16 little-endian signed 64-bit echo-history cells. Field order is exactly the existing Forth SNAP format. Globals become an explicit contiguous CREATE allocation, with existing variable names retained as address constants. Queue entries, queue indices and scratch mix buffers are not part of this interface.

All buffer ranges, pairwise disjointness, layout, frame count, state fields and clock overflow must be checked before popping arguments or changing buffers. Invalid address is -9; invalid layout/count/state/overlap is -24. Zero frames still validates the interface but changes nothing. ON accepts any cell as Forth truth. Voice fields: pos 0..65535, nibble 0..15, header 0..255, predictors/history -16384..16383, phase 0..4095, env 0..2047, mode 0..3, delay 0..5. Globals: cycle >=0, divider 0..31, frame >=0, pending 0..255, noise 0..32767, echo length 4 or n*2048 (n 1..15), echo offset a multiple of 4 below length, echo index 0..7, cached outputs signed 16. Echo history signed 15. Frame+count and clock+count*32-divider must fit signed 64. Do not require clock modulo 32 == divider: boundary tests deliberately set synthetic clocks.

Each completed native frame advances the global clock by 32-divider (then by 32), resets divider, and commits all state. Debug execution work is charged before every frame (at most 256 iterations per required checkpoint); interruption may preserve completed frames, and no partial frame is exposed. Reuse VM cell-write notifications when committing borrowed cell buffers, and notify byte-buffer writes according to existing bulk-memory policy. No raw host-pointer interface.

## Equivalent algorithm

New original Zig module ports our declared Forth algorithm: BRR prediction and clamp-before-signed 15 wrap; Gaussian first-three signed 16 wrap; old ENV output then envelope update; 5-frame KON delay and odd-frame polling; shared rate phase/noise; full previous-voice PMON; signed per-add saturated mix; FIR first-seven signed 16 wrap; shared ARAM echo/BRR/directory aliasing, EDL latching, 16-bit address wrap and muted output with continued echo. The 512 numerical Gaussian coefficients are generated from the existing provenance-pinned JSON, with no third-party implementation copied. Preserve all current sample-boundary approximations documented in SNES_DSP_AUDIO_FORTH.md.

## Forth dispatch

Keep `SD-STEP` and the default Forth backend. Add a selected frame execution token, outside reset chip state. `SD-RAW-RUN` preflights the target tick, computes complete frames, dispatches those frames and then commits the remaining fractional ticks. The selected kernel updates clocks after each completed frame, allowing a failed batch to expose coherent completed progress. Queued writes remain entirely in Forth and split native batches at their exact ticks. RENDER continues to request 32 ticks per output sample.

Add explicit native core and native play entry files. They load the ordinary module and a backend-only adapter requiring AUDIO. No auto-probing or device startup. Selecting Forth again is supported; SD-RESET retains backend selection. Saved execution tokens use normal image machinery. Append builtin identifiers and AUDIO registration entries so existing IDs do not move; verify images and feature masks rather than assuming compatibility.

## Validation before measurement/adoption

Build new isolated Windows/Linux full, no-debug, no-float and no-audio outputs without overwriting baseline binaries. Compare independent Python, reference Forth and native output for all PCM bytes, all semantic cells, queue indices and all 65536 ARAM bytes. Retain existing boundary tests, extend native coverage for BRR/Gaussian/envelope branches, validation failures, disjoint buffers, time limits, fractional divider, interrupted batches, feature-disabled behavior and saved images. Callback tests use RAM-only sinks; no audible output is authorized by this design. Review implementation with Claude Code. Native adoption remains pending until functional evidence and a separately user-approved measurement start.

## Design review decisions

Claude design review B1: both backends now update the clock after each complete frame, followed by fractional ticks only after successful dispatch. The token stack is `( frames -- )`, including zero frames. B2: only the native kernel guarantees no partially exposed frame; interruption of reference Forth can expose a partially executed SD-STEP. B3: private state outside declared ranges is unspecified for the Forth reference and explicitly rejected by the native interface, even for zero frames. Comparison covers valid state only.

Registers notify only ENVX/OUTX and ENDX writes that actually execute, including same-value writes. ARAM notifies only the four echo bytes when write-enabled, individually across byte-wise 16 bit wrap. Cell buffers are whole in/out records and each cell is committed with full-cell notification. Scratch SD-MIX/SD-EMIX are unspecified after native dispatch. No decoded BRR cache is retained. Selecting an adapter that is subsequently removed with MARKER/FORGET requires switching to Forth before removal.

Appending the builtin preserves its predecessors' IDs but changes the saved-image ABI signature in every build. Older images must be recreated. No image format version change is needed: the existing signature check rejects old signatures. Same-revision round trips and feature exclusion must be tested. Historical HERE/source records remain historical; current source and HERE will be recorded separately.

The frame-only interface is intentionally retained for this first candidate. Adding PCM output/batched RENDER now would expand the queue/render contract before measuring whether it is necessary. Per-call validation cost is included in the next candidate measurement; real-time adoption remains undecided until that measurement.

Cell-buffer notifications intentionally differ from reference Forth: every cell of the three in/out records is a full-cell store, including unchanged values. A damaged typed slot in these records may be reclassified or repaired; callers must not use these numeric state records as pointer storage. Byte-buffer notifications preserve unrelated typed slots.

## Layout 1 field order

| Buffer | Bytes | Representation |
| --- | ---: | --- |
| regs | 128 | Raw register bytes; ENVX/OUTX/ENDX are updated |
| aram | 65536 | Owned sample/directory/echo bytes; shared aliases and byte-wise16-bit wrap |
| voices | 896 | 8 consecutive records of14 little-endian signed64 cells |
| globals | 80 | 10 little-endian signed64 cells |
| history | 128 | 8 ring slots, each left/right signed15 value stored in signed64 cells |

Each voice record is `on,pos,nibble,header,p1,p2,phase,env,mode,delay,hist0,hist1,hist2,hist3`; history runs oldest to newest. Globals are `cycle,divider,frame,pending,noise,echo_offset,echo_length,echo_index,left,right`. Echo index selects the slot replaced by the next frame. Unaligned VM addresses and adjacent buffers are accepted; overlapping buffers are rejected. Success consumes seven arguments with no result. Validation failure preserves arguments and all buffers. Runtime interruption consumes the arguments but retains complete frame progress; standard CATCH/EXEC-LIMITED rules govern the caller's stack.

This frame-only entry returns the last sample in globals; it does not copy intermediate PCM. SD-RENDER calls it per frame and copies the cached pair, while SD-RUN may batch without retaining intermediate PCM. The primitive never processes the Forth event queue itself. A zero-frame kernel call validates only; the surrounding SD-TO still owns same-tick queue application. RENDER0 retains its no-flush behavior.

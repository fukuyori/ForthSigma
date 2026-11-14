# Terminal SHOW output activity (tque698)

## Problem and change

SHOW compares an output activity marker with the marker recorded after the last terminal image. If equal, it moves the cursor back and draws over that image. Direct `STDOUT WRITE-FILE` and `WRITE-LINE` bypassed this marker, as did SYSTEM output. On macOS PTYs, both a direct write and `SYSTEM` printing text reproduced an incorrect cursor-up before the next frame (`.work/698-native-before.json`).

`State.writeFile` now handles output accounting for direct file words, OUTFILE-EXECUTE output and graphics file output. STDOUT counts attempted bytes even on an error, since the host can have emitted a prefix. Other file handles do not affect this marker. A zero-byte WRITE-FILE leaves it unchanged; WRITE-LINE's line end counts. Return iors and callback ordering are preserved.

SYSTEM, SH and external editor callbacks mark unknown output activity immediately before calling the host. This also applies inside a private string capture: host output bypasses the VM's capture/redirection. A silent command, nonzero exit or callback error conservatively separates frames; a missing callback or earlier preflight error does not. Later consecutive SHOW calls can reuse the new frame normally. The marker is therefore an activity counter rather than an exact byte total. The coarse external-host policy does not infer shell redirections or inspect command text.

Ordinary TYPE/EMIT output, private captures, ordinary file output and existing explicit STDOUT redirection retain their behavior. Terminal renderer geometry, window/Tk rendering and image ABI are unchanged; there are no new words or persistent fields.

## Validation

Four regressions in `src/tests/output_activity_test.zig` cover both half-block/Sixel frame reuse, direct writes and empty writes/line ends, nonterminal destinations, private captures, partial-write errors, SYSTEM success/nonzero/error, missing host callbacks, captured SH and editor callbacks. The first three failed before fixes (`.work/698-before.log`). Normal tests pass1061 with6 skips; the minimal configuration passes585 with453 skips, including freestanding checks (`.work/698-final-test.log`, `.work/698-minimal.log`). Normal build passes. P09b comparison, editor stand-in and image regressions also pass after the shared editor integration change (`.work/698-p09b.log`).

`scripts/verify-output-activity.py` checks20 native POSIX PTY cases across both renderers without opening a GUI. Intervening direct output and external callbacks no longer emit the cursor-up sequence; consecutive frames, empty file writes and private captures still do. Evidence: `.work/698-native-after.json` and `.work/698-native.log`. Windows/Linux native checks are excluded here. No package/version change or external review was performed for this task. The user subsequently requested commit/push and a handoff; the fix and handoff are recorded in the corresponding commit (see git history).

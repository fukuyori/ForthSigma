# P07 implementation and validation

Current: prework457 and P07a570/P07b571/P07c572 are complete. New words32/40; next573 P07d. P07c implementation is included in the corresponding commit; see git history.

## Prework: dictionary assignment words (457)

Status: IS, ACTION-OF, TO and +TO are dictionary words; prework457 is complete with auto progress. P07's40 new words remain separate; prework committed as96625de, followed by P07a below. Implementation, validation and documentation are included in the P07 prework commit; see git history.

The whole-unit probe observed all four words before implementation. The user approved preserving Sigma's existing IS extension (FVALUE/2VALUE/$VALUE as well as VALUE/DEFER) and existing errors, while matching Gforth's interpretation/compilation selection. Unsupported targets and missing names retain InvalidDefinition(-259); Gforth returns-21/-16 respectively. ACTION-OF remains restricted to DEFER. Existing Sigma redefinition warnings remain.

### Semantics

- Ordinary input selects interpretation or compilation for the dictionary entry found through the search order. Local names retain precedence. Redefinitions and SYNONYM work through dictionary identity rather than matching the spelling of TO/IS/+TO/ACTION-OF.
- Tick, bracket-tick and NAME>INTERPRET/NAME>INT give interpretation tokens. Executing them always interprets the assignment or action read, even while STATE is compiling. They do not temporarily alter STATE.
- POSTPONE and NAME>COMPILE select a separate compilation action. NAME>COMPILE returns that token with EXECUTE. [COMPILE] selects the combined word's compiler action; COMPILE, of its interpretation token deliberately compiles interpretation execution. A compiler action may run with STATE false inside an open definition; outside a definition Sigma retains CompileOnly.
- Four builtin enum tags for public interpretation and four unnamed builtin entries for compilation are appended to the builtin enum/table before the existing final sentinel. The shared word_semantics helper selects actions for normal compilation, POSTPONE, NAME>COMPILE and [COMPILE], and resolves interpretation tokens. Ordinary alias call identities remain intact for debugger display.
- Existing scalar/double/float/string assignment, compiled typed locals, source-name parsing, error behavior and DEFER storage are reused. Watched assignments explicitly use the selected action mode; they no longer infer it from STATE when an interpretation token executes during compilation. Existing normal WATCH behavior is retained.

### Images and validation

SIGIMG45/46/47 framing is unchanged. New builtin enum tags change the existing ABI signature, and the builtin table/count also changes. Images from the previous builtin ABI are rejected; recreate them with this build. No old-ABI migration or version/package change was introduced. Interpretation tokens referencing builtins and compiled calls to unnamed compiler entries survive full restore and both dictionary-append routes.

Nine Zig regressions cover token identities and immediate flags, interpretation during compilation, POSTPONE/NAME>COMPILE/[COMPILE]/COMPILE,, synonyms/shadowing/search order, existing value types and locals, multiline parsing/error restoration, full restore/both append routes, WATCH mode and source-use records. Existing typed-local, debug, alias and image tests also pass. An early ordinary-alias resolution change altered debugger names; ordinary calls now preserve their original identity.

Normal tests, minimal tests with all optional feature groups disabled (including the freestanding object), and normal build pass. scripts/probe-p07-prework.py records63 cases; scripts/verify-p07-prework.py passes51 Gforth comparisons and12 approved Sigma-difference checks. It also verifies native SAVE/LOAD-DICTIONARY and SAVESYS execution (2 checks) with token-bearing definitions. Artifacts are in .work/p07-prework-check/; logs are .zig-cache/p07-prework-*.log. Windows/Linux native checks were not performed and remain under607. No GPL implementation code was copied; the implementation follows independently observed public behavior.

## P07a: compilation tokens and execution restrictions (570)

Status: all8 words are implemented and validated;570 is complete(auto). P07a was committed asdbc344c; P07b follows below. P07's new-word count is8/40; the four prework words are separate. P07a implementation and validation are included in the corresponding commit; see git history.

The user approved strict Sigma errors instead of Gforth's warning-and-continue behavior: ordinary interpretation of a COMPILE-ONLY/RESTRICT word throws CompileOnly(-14). Tick, NAME>INTERPRET and explicit EXECUTE remain available; the word body's own existing execution guards still apply. [COMP'] and EXECUTE-EXIT require compile state; POSTPONE, requires an open definition. A latest anonymous word or no user word gives InvalidDefinition(-259), following Sigma's existing defining-word error policy.

### API and behavior

| Word | Stack/behavior |
| --- | --- |
| COMP' | `( "name" -- xt1 xt2 )`; parse a dictionary name and obtain its compilation token. In a compiled definition it parses when executed. |
| [COMP'] | Compilation parses a name and emits the pair; runtime `( -- xt1 xt2 )`. |
| POSTPONE, | `( xt1 xt2 -- )`; append the represented compilation semantics to an open definition. Handles EXECUTE/COMPILE, tokens and a generic callable second token. |
| COMPILE-ONLY / RESTRICT | `( -- )`; mark the latest named user entry as unavailable for ordinary interpretation. SYNONYM copies the restriction along with its immediate flag. |
| EXECUTE-EXIT | Compilation emits EXECUTE followed by EXIT; runtime consumes xt, executes it and exits the current definition. Existing call/local cleanup and explicit UNLOOP rules apply. This does not promise tail-call optimization. |
| SELECT | `( u1 u2 flag -- u )`; any nonzero flag selects u1, zero selects u2. |
| [NOOP] | `( -- )`; ordinary, non-immediate no-operation. Its compilation token uses COMPILE,. It does not push an xt. |

The implementation uses the prework word_semantics selector for ordinary, immediate and combined-word tokens. Token/stack validation precedes emission; the two-operation forms reserve code space before emitting. The runtime execution loop itself is unchanged.

### Image representation and regression correction

Word gains an explicit compile_only boolean. It is serialized with the existing Word field list, validated as0/1 before reading a native Word, and included in the ABI signature. Full restore and both append routes preserve user restrictions. SIGIMG45/46/47 framing is unchanged; previous builtin/Word ABIs remain rejected and images must be regenerated.

The new round-trip regression caught EXECUTE-EXIT emitting an EXECUTE primitive without its original word id. Execution worked before saving, but image normalization and SEE used operand0 and treated it as DROP. The emitter now retains builtinWord(EXECUTE), consistent with normal primitive compilation. The same regression passes on full restore and both append routes, and native SAVE/LOAD/SAVESYS verifies execution. Additional flag measurements corrected an initial [NOOP] immediate assumption: Gforth reports it non-immediate; the final implementation and test use default compilation semantics.

### Validation

Nine Zig tests cover token pairs for ordinary/immediate/combined words; POSTPONE, including generic tokens and STATE-false compilation; strict interpretation vs explicit xt execution and SYNONYM; invalid latest definitions; EXECUTE-EXIT caller/local/loop/exception cleanup; SELECT/non-immediate [NOOP]; capacity/invalid-token preflight; all3 image routes; and a malformed compile_only byte with repaired CRC rejected without mutation.

Normal/minimal tests (all optional groups disabled, including freestanding object) and normal build pass. Final probe-p07a.py records70 observations across all8 words, including immediate flags. verify-p07a.py passes57 Gforth comparisons,13 documented Sigma error-policy checks, and2 native SAVE/LOAD/SAVESYS checks. The prework verifier also passes51 comparisons,12 approved differences and2 native image checks with the new Word ABI. Logs: .zig-cache/p07a-*.log; reports and verification executables: .work/p07a-check/. Exploratory invalid probes are not counted as passing comparisons. Windows/Linux native checks remain deferred under607; no package, version change or GPL implementation reuse.

## P07b: quotations, anonymous definitions and postponing (571)

Status: all6 items are implemented;571 is complete(auto). P07 now has14/40 new words plus the four prework words. P07b was committed as0bd77d8. P07b implementation/documentation are included in the corresponding commit; the preceding P07a commit is dbc344c and the initial P07b probe is608e55c.

The user approved interpreted and nested quotations without outer-local capture, postponing only inside an open definition (also from temporary interpretation), and strict errors/rollback for malformed quotations. [[ is a postponing delimiter, not an ordinary dictionary word. Gforth's invalid-memory behavior and unfinished-compiler state on malformed inputs are not reproduced.

### Public behavior

- `[: ... ;]` produces an anonymous execution token. In compilation it emits that token for runtime; in interpretation it leaves the token immediately. Nested quotations are supported up to16 active levels (ControlStackOverflow beyond that). Each quotation has its own locals, recursion target and control stack. Parent compiler state, locals and controls resume afterward. Outer locals are invisible; quotation-owned typed locals work normally. No closures are introduced.
- `NONAME ( -- )` makes the next defining operation omit name parsing and create an unnamed entry. Use LATESTXT to obtain it; LATEST returns0. Existing colon, data, deferred, field, vocabulary, marker and alias defining interfaces use the same name-selection helper. Repeating NONAME does not queue multiple requests. The pending request is runtime parser state and is not saved.
- `IN-COLON-DEF? ( -- flag )` reports an unfinished colon definition, independently of STATE; ordinary runtime execution outside compilation returns false.
- `]] ... [[` postpones word compilation semantics, including the prework combined assignment words. Integer, double and floating literals generate runtime compilation through LITERAL/2LITERAL/FLITERAL. Cell/float/double locals supply macro values; XT locals compile the stored word rather than executing it immediately. Variable-flavour local addresses retain their existing frame-bound lifetime; they are not shared or captured buffers.
- Parsing strings (`S"`, escaped S/print forms, `."`, `C"`, `ABORT"`, `.(`) are parsed when the macro executes, from its caller's input. Thus `: M ]] S" [[ ; IMMEDIATE : T M text" ;` is the intended pattern; putting the text immediately after S" within the postponed macro is not that pattern. Square-bracket operations within postponing are also deferred. [[ ends postponing and resumes compilation. Outside postponing [[ remains an undefined name; ]] outside any open definition throws CompileOnly.

### Compiler state, rollback and persistence

A bounded quotation-frame array saves the parent's compiler state. A branch skips nested anonymous code in its parent's executable body; closing the quotation records the body and emits a relocatable execution-token operation. An internal Word.quotation boolean marks nested entries so LATEST/LATESTXT, IMMEDIATE and COMPILE-ONLY still refer to the enclosing user definition. The flag is serialized and validated (0/1; true only for unnamed colon entries), changing the existing Word/builtin ABI. Older ABI images remain rejected under SIGIMG45/46/47.

Malformed control flow, wrong quote terminators and errors inside an open quotation discard the whole unfinished outer definition, including nested entries, code, names, typed data registrations and data-area allocation. Already-existing definitions remain. EVALUATE and include EOF reject a newly unfinished quotation; the native shutdown path also rejects unfinished quotation/postponing state. CATCH cannot resurrect a compiler discarded by quotation rollback. One-shot NONAME and postponing state participate in exception restoration. Active quotation/postponing compilers cannot be encoded or imported as image sources. Full restore clears these runtime parser states; completed quote bodies and macro helpers survive full restore and both append routes.

### Validation

Thirteen Zig tests cover interpreted/nested/stable tokens, isolated controls/typed locals/recursion and parent restoration, callbacks/CATCH/IN-COLON-DEF?, NONAME defining operations, literals/parsing strings/macros/XT locals, rollback and caught errors, depth/resource bounds, complete images/both append routes, multiline/include EOF, data/name rollback and malformed metadata with repaired CRC.

Normal tests, minimal tests with all optional groups disabled (including freestanding object), and normal build pass. The final whole-unit probe has76 observations; verification passes70 Gforth comparisons,6 explicit Sigma error checks and2 native SAVE/LOAD/SAVESYS execution checks. Two additional native EOF checks reject unfinished quotation/postponing state. Gforth's standalone ;] invalid-memory failure is an exploratory observation, not a passing conformance case. Prework and P07a comparisons and their native image checks also pass with the new ABI. Reports: .work/p07b-check/; logs: .zig-cache/p07b-*.log. No Windows/Linux native execution, package/version change or GPL implementation reuse.

## P07c: counted loops and control-stack operations (572)

Status: all18 words are implemented;572 is complete(auto). P07 now has32/40 new words plus the four prework words. Next is P07d573 (8 words). P07c implementation is included in the corresponding commit; see git history. Previous commits: P07b0bd77d8; P07c initial probe3b225fa.

The user directed continued implementation with recommended choices and no pauses for undecided implementation details. Accordingly, valid loop behavior follows the measurements; invalid memory stride/range arithmetic uses Sigma errors, helper calls read VM loop frames rather than arbitrary return-stack cells, and CS operations accept temporary interpretation inside an open definition. Git operations still require an explicit request.

### Words and boundaries

- +DO/U+DO enter only when start<limit (signed/unsigned); -DO/U-DO require start>limit. -[DO/U-[DO allow start=limit. The ending still determines the termination border: a negative +LOOP includes the lower boundary; -LOOP subtracts an unsigned magnitude and stops at/crossing the lower boundary, excluding it. Zero -LOOP increments retain looping behavior; work limits and LEAVE remain available. ARRAY>MEM multiplies with cell-width wrapping and retains the element size.
- FOR/NEXT count unsigned n down through0, giving n+1 body executions. I' is0 for FOR and DELTA-I is limit-index modulo cell width. Body locals initialized by FOR remain visible afterward unless a LEAVE can skip them. Existing plain DO's equal-bound behavior is retained; it is not imposed on the new inclusive loops (a zero-step equal-bound loop can repeat).
- MEM+DO/MEM-DO require LOOP and a positive signed stride. They reject zero/negative stride and unsigned addr+bytes overflow with InvalidNumber(-24), before consuming arguments or creating a frame. Upward indices are addr, addr+stride,... while below the end; downward indices start at addr+bytes-stride and continue while at/above addr. bytes<stride gives no downward iterations. For bytes5/stride2 the offsets are0,2,4 upward and3,1 downward. The iterator itself does not dereference memory; ordinary memory words perform address checks.
- I' and DELTA-I read the innermost VM loop frame and work through helper calls, consistently with Sigma I. A missing frame raises LoopMismatch. This deliberately avoids the unrelated return-address values observed in Gforth helper calls.
- ?DUP-IF and ?DUP-0=-IF preserve a nonzero input on the selected path and compose with ordinary ELSE/THEN.
- CS-DROP removes an orig/dest entry. CS-PICK/ROLL/DROP require an open definition but work during [ ... ]. MEM loop control entries reject CS-PICK/ROLL, matching the documented special do-sys restriction. Loop/control kind mismatches fail with ControlMismatch. FOR must end with NEXT, and MEM loops with LOOP.
- DONE resolves LEAVE targets without generating runtime cleanup. Its destination must perform the required UNLOOP. A private flag on the entry target keeps the frame for that cleanup; ordinary loop endings and LEAVE behavior remain unchanged. Sigma's conditional DONE entry retains a cleanup frame on the skip path, avoiding an absent-frame pop. SEE reconstructs DONE from the target marker.

### VM and images

Eleven dedicated operation tags extend the VM, and Loop gains runtime mode/stride/cleanup fields. Regular LOOP keeps its existing fast path for ordinary frames; extended modes use bounded arithmetic. DONE marks bit32 on a loop-entry target; validation accepts only the flag plus an in-range code target. Both append routes relocate the target without altering the flag. Inline reconstruction marks these targets, and lint/decompilation/debug naming recognize the new operations. Runtime loop frames are not image state.

The existing ABI signature includes the new OpKind/Builtin tags, so earlier ABI files are rejected even with SIGIMG45/46/47 framing. Completed definitions survive full restore, both append routes and SAVESYS. Native EOF now rejects any unfinished colon definition, including unfinished loops, instead of treating it as successful termination; multiline interactive definitions remain supported until EOF.

### Validation

Thirteen Zig regressions cover signed/unsigned/equal bounds, -LOOP magnitudes and zero steps, FOR/nested loops/body locals, helper limit/delta reads, memory order and non-multiple lengths, invalid stride/range argument preservation, ARRAY>MEM and combined IF, DONE/UNLOOP, CS operations, THROW/EXIT cleanup, all3 image paths, malformed control kinds, SEE and work-limit interruption. StepLimit deliberately bypasses CATCH as before; report recovery clears the loop frames.

Normal/minimal tests (all optional groups disabled, including the freestanding object) and normal build pass. Final probe:162 observations, all bounded potentially long loops, no timeouts. verify-p07c.py passes149 Gforth comparisons,13 Sigma policy/error checks,2 native SAVE/LOAD/SAVESYS checks and2 native unfinished-loop EOF checks. Earlier prework/P07a/P07b comparisons and native image checks also pass. Logs: .zig-cache/p07c-*.log; reports: .work/p07c-check/. Gforth's invalid-control crashes and helper return-address values are observations, not passing conformance requirements. No Windows/Linux native checks, package/version changes or GPL implementation reuse.

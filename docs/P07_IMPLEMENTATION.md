# P07 implementation and validation

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

Status: all8 words are implemented and validated;570 is complete(auto). Next is P07b571 (6 words). P07's new-word count is8/40; the four prework words are separate. P07a implementation and validation are included in the corresponding commit; see git history.

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

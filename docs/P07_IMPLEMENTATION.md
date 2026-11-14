# P07 implementation and validation

## Prework: dictionary assignment words (457)

Status: IS, ACTION-OF, TO and +TO are dictionary words; prework457 is complete with auto progress. P07's40 new words remain separate; next is P07a570. Implementation, validation and documentation are included in the P07 prework commit; see git history.

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

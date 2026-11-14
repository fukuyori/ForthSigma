# P08 implementation and validation

Current: P08a574 and P08b575 are complete(auto),29/29 words; parent551 is complete. P07 review fixes and P08a were pushed as39e5501; P08b was pushed as4033ef1. P08 Claude Code review and fixes are complete under700; review changes are included in the corresponding commit; see git history. [Review](P08_REVIEW.md). Next implementation candidate:576 P09a.

## P08a: name tokens and wordlists (574)

All23 words were probed before implementation; supplementary metadata and multiline probes were added while resolving concrete questions. The user authorized recommended decisions without stopping for routine approval. Implementation is in words_names.zig with shared wordlist/name helpers. No Gforth implementation code was copied.

| Word | Stack effect | Meaning |
| --- | --- | --- |
| `.ID` | `( nt -- )` | Print a valid name token's name. |
| `.VOC` | `( wid -- )` | Print a valid wordlist's name. |
| `COMPILE-ONLY?` | `( nt -- flag )` | Test a name token's compile-only flag. |
| `CONTEXT` | `( -- addr )` | Address of the first-searched wordlist cell. |
| `CS-VOCABULARY` | `( "name" -- )` | Create a case-sensitive vocabulary. |
| `CS-WORDLIST` | `( -- wid )` | Allocate a case-sensitive wordlist. |
| `CURRENT` | `( -- addr )` | Address of the compilation wordlist cell. |
| `FIND-NAME-IN` | `( addr u wid -- nt\|0 )` | Find a name token in one wordlist. |
| `IN` | `( "vocabulary" "word" -- )` | Execute the next word with a vocabulary as one-shot compilation destination. |
| `IN-WORDLIST` | `( wid "word" -- )` | Execute the next word with wid as one-shot compilation destination. |
| `LATESTNT` | `( -- nt )` | Name token of the latest definition, including anonymous definitions. |
| `MAP-VOCS` | `( ... xt -- ... )` | Call xt with each wordlist from a snapshot of allocated ids. |
| `MWORDS` | `( "pattern" -- )` | List oldest-first names containing the optional pattern in the first wordlist. |
| `NAME>LINK` | `( nt -- previous-nt\|0 )` | Previous named entry in the same wordlist, or zero. |
| `NEXTNAME` | `( addr u -- )` | Copy a one-shot name for the next defining operation without parsing a name. |
| `OBSOLETE?` | `( nt -- flag )` | Test obsolescence; Sigma currently marks no definitions obsolete. |
| `ROOT` | `( -- )` | Replace the first search-order entry with Root. |
| `SEAL` | `( -- )` | Keep only the first search-order entry. |
| `TABLE` | `( -- wid )` | Allocate a case-sensitive wordlist without redefinition warnings. |
| `VLIST` | `( -- )` | Alias of Sigma WORDS. |
| `VOCS` | `( -- )` | List allocated wordlists and the fixed Macros namespace. |
| `WORDLIST-WORDS` | `( wid -- )` | List names from the specified wordlist in Sigma order. |
| `XT>NAME` | `( xt -- nt )` | Convert a valid execution token to a name token, including anonymous words. |

### Behavior and recommended policies

- NEXTNAME owns a copied one-shot name of at most255 bytes, integrated with NONAME and all existing defining-name helpers. Replacement is last-wins. Anonymous colon/quotation creation leaves a pending choice for the next named defining operation. CATCH saves/restores its bytes. Full image restore and parser error cleanup clear pending naming state. Empty NEXTNAME is anonymous in Sigma; Gforth exposes an empty named header instead (two measured cases).
- IN/IN-WORDLIST parse and execute one dictionary word under a temporary CURRENT, restored with defer on success/THROW. They do not change the search order. Restoration happens immediately after a colon-starting word returns, not at its later semicolon. IN requires a vocabulary (synonyms work); wrong-kind constants throw InvalidDefinition(-259) rather than reproducing Gforth's invalid-memory path.
- CURRENT/CONTEXT expose the existing VM cells. Appending an entry validates CURRENT before narrowing it to a wordlist byte. ROOT/SEAL reuse existing order representation; ROOT, SEAL and VOCS are also available in Root. An empty SEAL gives SearchOrderUnderflow.
- Case and silent-warning policies use two persistent64-bit masks in the system area, at0x0d70/0x0d78 (bit wid-1). Fixed Forth/Root/EKEYS bits remain clear, Macros stays separately case-sensitive. Lookup, redefinition checks and FORWARD binding consult the same case policy. TABLE suppresses warnings only in its own list. Allocated wordlists remain allocated after FORGET, as in the existing VM model.
- NAME>LINK skips anonymous entries in the same list. LATESTNT and XT>NAME support anonymous definitions; tick/NAME>INTERPRET aliases retain existing canonical token behavior. Invalid nt/xt values throw Sigma's InvalidExecutionToken. Forgotten numeric tokens have no validity guarantee after ids are reused.
- Compile-only metadata is populated for the measured intrinsic control words, keeping their existing errors. ]] remains unmarked to preserve the approved ability to start postponing during temporary interpretation within a definition; this is one measured metadata difference. COMPILE-ONLY? does not promise that a false result bypasses body guards. OBSOLETE? returns false after token validation; Sigma has no obsolete-marked entries.
- MWORDS uses literal case-sensitive substring matching, oldest first, and takes an optional pattern only from the current input line. A regression demonstrated that using the cross-line defining-name parser stole PREVIOUS from the next included line; the line-local parser fixes it. WORDLIST-WORDS/VLIST retain Sigma's existing WORDS oldest-first layout (two measured ordering differences); whitespace is normalized by the comparison script.
- MAP-VOCS snapshots allocated-list count, visits descending ids then fixed Macros, and propagates callback errors. Newly allocated lists are for the next traversal. VOCS uses Sigma's actual list set, including unnamed lists and Macros; its system vocabulary set differs from Gforth.

These account for7 explicit policy checks: two empty-name observations, invalid IN target, two listing-order observations, VOCS system set, and ]] metadata. Existing redefinition-warning placement is retained; the CS-WORDLIST warning is checked then removed for stdout comparison. Exploratory Gforth invalid-memory behavior is not treated as a conformance result.

### Images and compatibility

Full restore retains case/table policy masks. Both append routes merge and shift those masks with relocated user wordlist ids while preserving destination policies; vocabulary Word.value targets are relocated as before. Image validation rejects bits for unallocated/fixed lists and silent bits without case bits before mutating the VM. Boundary tests cover the64th bit and capacity failure.

Raw wid cells/constants, like other untyped handles, are not automatically relocated on append; applications must use vocabulary references or reconstruct ids. The implementation does not infer typed ids from arbitrary integers. Runtime pending-name bytes are not serialized. New builtin tags and additional Root entries change builtin ABI/count; SIGIMG45/46/47 framing is unchanged and previous-ABI images must be recreated.

Two existing fixture names TABLE were renamed because TABLE is now public; warning semantics were retained. HELP covers every new registered word. Existing graphics/audio/input behavior is unchanged.

### Validation

scripts/probe-p08a.py records170 observations from the designated Gforth build. scripts/verify-p08a.py passes163 matching cases and7 explicit Sigma policy checks, comparing tokenized output to allow display whitespace differences. It also passes native SAVE/LOAD-DICTIONARY into a destination with an extra wordlist and SAVESYS execution (2 checks). Artifacts: .work/p08a-check/.

Twelve Zig regressions cover named/anonymous tokens and forgetting, case/table warnings, copied and caught NEXTNAME state, scoped compilation destination/error restoration, writable VM context, finite traversal callbacks, listing/filter output, full restore/both append routes with rebasing, malformed policy validation without mutation, line-local MWORDS, control metadata/aliases and capacity/bit63 persistence. Normal/minimal tests (all optional groups disabled, including freestanding checks) and normal build pass. P07 prework/a/b/c/d comparison/image/EOF verifiers also pass after the code changes. Logs: .zig-cache/p08a-*.log.

Windows/Linux native checks remain deferred under607. No package/release/version change or unrequested external review was performed during implementation validation.

## P08b: addressable values and deferred actions (575)

All6 words complete(auto); P08 now has29/29 implemented words. P07 review fixes and P08a were committed/pushed as39e5501 before this unit. P08 external review and fixes are recorded in [P08_REVIEW.md](P08_REVIEW.md).

| Word | Stack effect | Behavior |
| --- | --- | --- |
| AVALUE | `( addr "name" -- )` | Define a VALUE with explicitly tracked logical-address storage. |
| ADDRESSABLE: | `( -- )` | Compatibility annotation; Sigma values already have stable backing storage. |
| ADDR | `( "name" -- addr )` | Address a value or, during compilation, a value-flavoured local. |
| :IS | `( "deferred" -- )` | Begin an anonymous definition assigned to the DEFER at successful semicolon. |
| PRESERVE | `( compilation: "deferred" -- ; runtime: -- )` | Restore the action captured at compilation, not the action present on entry. |
| WRAP-XT | `( ... action deferred callback -- ... )` | Temporarily install action, execute callback and restore the entry action. |

AVALUE does not allocate/free its target. TO, +TO and full-cell stores refresh its typed address record; partial writes damage it and prevent image saving until repaired by a full-cell update. Use logical data addresses, not xt/wid handles. Invalid address values can be held at runtime but cannot be serialized as valid addresses.

ADDR supports VALUE/AVALUE, FVALUE, 2VALUE, $VALUE and DEFER; it rejects constants, variables and variable-flavoured locals. Ordinary Sigma values need no annotation and produce no Gforth-style addressability warning. Compiled ADDR uses a relocatable word reference; its explicit interpretation token still returns an address immediately during compilation. Local addresses last only for that invocation's frame. To persist a raw returned address, use explicit address storage such as AVALUE, ACONSTANT or A!.

:IS accepts only DEFER (including synonyms). Its old action remains available to DEFERS until the definition completes. An error leaves the old action intact. An active :IS compiler cannot be saved/imported; completed definitions survive images normally.

PRESERVE requires compilation and captures a fixed action, including the uninitialized sentinel. WRAP-XT restores on normal return, THROW, interruption and work-limit errors; callback errors retain priority. Nested scopes are supported up to64. If FORGET/MARKER or successful full image restoration invalidates its target, cleanup never writes into the removed/reused cell; normal callback return then gives InvalidExecutionToken(-261), while an existing callback error is propagated. Forgetting unrelated later words does not invalidate the target. Runtime wrapper guards are not serialized; saving inside a valid scope snapshots the currently installed action.

Six public words and one hidden ADDR compilation action change builtin ABI/count. Recreate earlier-ABI images. [Implementation and validation](P08_IMPLEMENTATION.md).


### Implementation and decisions

- words_value_extensions.zig provides the public words and a hidden compile_addr action. ADDR uses the same interpretation/compilation selector as assignment words. Dictionary addresses compile as typed execution_token + >BODY; local addresses use the existing local_address operation. No native pointers or inferred cell literals enter serialized code.
- AVALUE reuses VALUE and the existing typed-memory registry. Full-cell writes already refresh records; damaged/invalid pointers fail image validation. SEE identifies registered value storage as AVALUE. No new Word fields/kinds are needed.
- ADDRESSABLE: is deliberately a no-op annotation because all Sigma values already have backing storage. ADDR on ordinary values/locals is accepted without Gforth's warning. Variable-flavoured locals and non-value targets retain InvalidDefinition(-259). Runtime input parsing follows existing Sigma name rules; a missing name gives-259 rather than Gforth's-16.
- :IS tracks its anonymous word and target only while compilation is active. endDefinition commits after all ordinary close checks/code emission. Nested quotations cannot commit the outer target early. Error cleanup, FORGET and full restore clear the pending assignment. Compilation into an already removed current word is rejected. Non-DEFER targets are rejected rather than emulating Gforth's obsolescent value-target access.
- PRESERVE emits a captured typed xt (or raw-1 sentinel) and store_value. It is a fixed compile-time reset, not an automatic exception scope. Outside compilation it throws CompileOnly(-14), instead of emitting orphan code with Gforth warnings.
- WRAP-XT validates all3 tokens before changing state or consuming arguments. A stack-local guard chain tracks live target ids; dropWordsFrom and successful full restore invalidate affected guards before ids/storage are reused. Defer cleanup restores only a still-valid slot, including callback failures. A removed target on normal return gives-261; callback errors retain priority. Guards survive failed restore preflight, and an unrelated tail FORGET leaves the target valid. Host callback nesting is bounded at64 with ReturnStackOverflow and full unwind.
- WRAP-XT uses the existing InvalidExecutionToken error for a non-DEFER target (-261 vs Gforth-21). Existing uninitialized-DEFER warning placement is retained and verified, then normalized in two comparisons. Gforth incomplete compiler/banner and invalid-memory behavior are exploratory observations, not copied failure semantics.

### Images and validation

AVALUE's typed slot retains heap roots and data pointers through full restore and both append routes. Compiled ADDR, captured PRESERVE actions and completed anonymous :IS assignments use existing typed word-id relocation. Active :IS compilers cannot be encoded or used as append sources. Runtime guards are never serialized; a successful full restore invalidates live scopes only after preflight, while failed preflight leaves them intact. No new framing/Word/Op layout:7 appended Builtin tags/table entries change ABI/count, so old-ABI SIGIMG45/46/47 images must be recreated.

scripts/probe-p08b.py records64 observations. scripts/verify-p08b.py passes54 matching stdout/exit cases plus10 explicit Sigma error/compiler policies. Native SAVE/LOAD-DICTIONARY into a nonempty dictionary/heap and SAVESYS execution both pass, exercising an AVALUE heap root, compiled ADDR and deferred-action relocation. Artifacts: .work/p08b-check/.

Twelve Zig regressions pass: typed full/partial writes, separate ADDR actions and scalar/float/double/xt locals, :IS timing/rollback/active-save rejection, captured/uninitialized actions, nested/throwing/rebinding wrappers, same-id reuse and error priority, unrelated FORGET, successful/failed image restoration,64-level unwind and all3 image routes. Normal/minimal tests (all optional groups disabled, including freestanding checks) and build pass; P08a and every P07 verifier also pass. Logs: .zig-cache/p08b-*.log. No Windows/Linux native execution, version change, package creation or unrequested external review was performed.

## P08 review follow-up (700)

The requested full review found saved-action lifetime, lazy naming and callback-reuse bugs; Codex additionally reproduced stale CURRENT after full restore and leaked masks after failed loading. Five regressions failed before fixes; eight final regressions pass, along with normal/minimal tests, build, P08/P07 verifiers and3 native before/after checks. Guarded MAP/WRAP scopes now share64 levels; invalidated saved actions become uninitialized, and a full-restore generation prevents reinstalling old CURRENT. Library naming/masks are isolated with prerequisite preservation. Verifiers reject unmatched policy names. No wire ABI changes. [Findings, scope and evidence](P08_REVIEW.md).

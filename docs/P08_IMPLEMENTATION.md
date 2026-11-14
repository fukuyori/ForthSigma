# P08 implementation and validation

Current: P08a574 is complete(auto),23/29 words. Next:575 P08b (addressable values and deferred-word extensions). P07 review fixes and P08a are included in the corresponding commit; see git history.

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

Windows/Linux native checks remain deferred under607. No package/release/version change, Git commit/push or unrequested external review was performed for this unit.

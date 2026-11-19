#!/usr/bin/env python3
"""P10 integration and feature-registration contracts for one native build."""
import argparse
import csv
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--sigma', type=Path, required=True)
p.add_argument('--disabled', choices=['float', 'files', 'help', 'tools', 'image', 'graphics', 'audio', 'extension', 'debug'])
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
sigma = str(a.sigma.resolve(strict=True))
output = a.output.resolve()
output.parent.mkdir(parents=True, exist_ok=True)
temporary = tempfile.TemporaryDirectory(prefix='p10-', dir=output.parent)
root = Path(temporary.name).resolve()
passed = []
newline = b'\r\n' if os.name == 'nt' else b'\n'

def run(name, source, expected=None, binary=None, status=0, options=()):
    r = subprocess.run([binary or sigma, *options, '-e', source + ' BYE'], cwd=root,
                       input=b'', capture_output=True, timeout=30)
    assert r.returncode == status, (name, r.returncode, r.stdout, r.stderr)
    if expected is not None:
        assert r.stdout == expected, (name, r.returncode, r.stdout, expected, r.stderr)
    passed.append({'case': name, 'exit': r.returncode, 'stdout_hex': r.stdout.hex()})
    output.write_text(json.dumps({'complete': False, 'disabled': a.disabled, 'cases': passed}, indent=2) + '\n')
    return r.stdout

groups = {
    'float': ['F+', 'F>R', 'FLOAT%', 'FCLEARSTACK'],
    'files': ['OPEN-FILE', 'READ-CSV', 'FPATH', 'INFILE-EXECUTE', 'FILENAME-MATCH', 'OPEN-PIPE'],
    'help': ['HELP', 'LICENSE'], 'tools': ['SEE', 'WHERE', 'EDIT', 'WHEREG'],
    'image': ['SAVE', 'LOAD-DICTIONARY', 'SAVESYS'],
    'debug': ['DBG', 'ASSERT0('],
}
for group, names in groups.items():
    run(f'registration-{group}', ' '.join(f'[DEFINED] {name} .' for name in names),
        ''.join(f'{0 if group == a.disabled else -1} ' for _ in names).encode())
for group, vocabulary, word, code in [('graphics', 'GRAPHICS', 'GFX-INIT', -270), ('audio', 'AUDIO', 'SND-PLAY', -275), ('extension', 'EXTENSION', 'HOST-OS', -13)]:
    if a.disabled == group:
        run(f'registration-{group}', f': TRY-W S" REQUIRE-{group.upper()}" EVALUATE ; \' TRY-W CATCH . [DEFINED] {vocabulary} .', f'{code} 0 '.encode())
    else:
        run(f'registration-{group}', f'REQUIRE-{group.upper()} ALSO {vocabulary} [DEFINED] {word} . PREVIOUS', b'-1 ')

run('macro-quotation-core', ': ADD8 ]] 8 + [[ ; IMMEDIATE : T 3 ADD8 ; : Q [: [: 7 ;] ;] ; T . Q EXECUTE EXECUTE . DEPTH .', b'11 7 0 ')
run('macro-string-wordlist', 'GET-CURRENT MACROS-WORDLIST SET-CURRENT S" :NONAME 6 7 * ;" MACRO: CODE-W SET-CURRENT S" %CODE-W%" $SUBSTITUTE DROP EVALUATE EXECUTE . DEPTH .', b'42 0 ')
run('marker-redefinition', '0 WARNINGS ! : KEPT 7 ; MARKER BACK-W : KEPT 8 ; : Q [: KEPT ;] ; Q EXECUTE . BACK-W KEPT . [DEFINED] Q . DEPTH .', b'8 7 0 0 ')
run('forget-redefinition', '0 WARNINGS ! : KEPT 7 ; : KEPT 8 ; FORGET KEPT KEPT . DEPTH .', b'7 0 ')
run('compiler-rollback', ': FAIL-W S" : BROKEN IF ;" EVALUATE ; \' FAIL-W CATCH . [DEFINED] BROKEN . : GOOD 42 ; GOOD . DEPTH .', b'-22 0 42 0 ')
run('capacity-rollback', 'VARIABLE H-W : BAD-W S" : TOO-BIG-W [ 999999999 ALLOT ] ;" EVALUATE ; HERE H-W ! \' BAD-W CATCH 0<> . HERE H-W @ = . [DEFINED] TOO-BIG-W . : GOOD 42 ; GOOD . DEPTH .', b'-1 -1 0 42 0 ')
run('compilation-token-assignment', '1 VALUE V-W \' TO CONSTANT SET-W : M-W POSTPONE TO ; IMMEDIATE : T-W 8 M-W V-W ; S" 3 SET-W EXECUTE V-W" EVALUATE T-W V-W . DEPTH .', b'8 0 ')

if a.disabled != 'float':
    run('float-return-through-quotation', ': Q [: 1.25E F>R FR@ FR> F+ ;] ; Q EXECUTE 2.5E F= . FDEPTH . DEPTH .', b'-1 0 0 ')
if a.disabled != 'debug':
    run('assert-catch-restore', ': BAD-W ASSERT( 0 ) ; \' BAD-W CATCH -2 = . : OK-W ASSERT( -1 ) 42 ; OK-W . DEPTH .', b'*the terminal*:0:19: failed assertion-1 42 0 ')

if a.disabled != 'files':
    run('number-string-csv-file', ': ROW-W 1234567890123456789. <# #S #> .QUOTED-CSV 44 EMIT S" 日本,語" .QUOTED-CSV CR ; S" data.csv" W/O CREATE-FILE THROW CONSTANT F \' ROW-W F OUTFILE-EXECUTE F CLOSE-FILE THROW', b'')
    csv_bytes = (root / 'data.csv').read_bytes()
    assert list(csv.reader(io.StringIO(csv_bytes.decode()))) == [['1234567890123456789', '日本,語']], csv_bytes
    expected = b'1234567890123456789|0 1 ' + '日本,語|1 1 '.encode() + b'0 '
    run('csv-read-back', ': FIELD-W >R >R TYPE 124 EMIT R> . R> . ; S" data.csv" \' FIELD-W READ-CSV DEPTH .', expected)
    run('io-switch-throw', 'S" a.txt" W/O CREATE-FILE THROW CONSTANT FA S" b.txt" W/O CREATE-FILE THROW CONSTANT FB : INNER-W 66 EMIT -123 THROW ; : OUTER-W 65 EMIT [\'] INNER-W FB OUTFILE-EXECUTE ; : RUN-W [\'] OUTER-W FA OUTFILE-EXECUTE ; \' RUN-W CATCH . OUTFILE-ID STDOUT = . FA CLOSE-FILE THROW FB CLOSE-FILE THROW DEPTH .', b'-123 -1 0 ')
    assert (root / 'a.txt').read_bytes() == b'A' and (root / 'b.txt').read_bytes() == b'B'
    run('csv-throw-closes-source', ': FIELD-W 2DROP 2DROP -123 THROW ; : RUN-W S" data.csv" [\'] FIELD-W READ-CSV ; \' RUN-W CATCH . SOURCE-ID . DEPTH .', b'-123 0 0 ')
    (root / 'broken.fs').write_text(': BROKEN-FILE-W IF ;\n', encoding='utf-8')
    run('include-compiler-rollback', ': KEPT 42 ; : BAD-W S" broken.fs" INCLUDED ; \' BAD-W CATCH . [DEFINED] BROKEN-FILE-W . KEPT . SOURCE-ID . DEPTH .', b'-22 0 42 0 0 ')
    run('capture-inside-file', 'S" capture.txt" W/O CREATE-FILE THROW CONSTANT F : STR-W S" 日本語" TYPE ; : WRITER-W [\'] STR-W >STRING-EXECUTE OVER >R TYPE R> FREE THROW ; \' WRITER-W F OUTFILE-EXECUTE F CLOSE-FILE THROW DEPTH .', b'0 ')
    assert (root / 'capture.txt').read_bytes() == '日本語'.encode()
    block = b': BLOCK-W 41 1+ ; BLOCK-W .'
    (root / 'blocks.fb').write_bytes(b' ' * 1024 + block.ljust(1024, b' '))
    run('block-definitions-and-save', '1 LOAD BLOCK-W . ' + ('SAVE block.sigma LOAD-DICTIONARY block.sigma BLOCK-W . ' if a.disabled != 'image' else '') + 'DEPTH .', b'42 42 42 0 ' if a.disabled != 'image' else b'42 42 0 ')

image_source = ': ADD-W ]] 8 + [[ ; IMMEDIATE VOCABULARY V-W ALSO V-W DEFINITIONS : T-W 3 ADD-W ; : Q-W [: [: 7 ;] ;] ; ALSO FORTH DEFINITIONS 16 ALLOCATE THROW AVALUE P-W 65 P-W C! : ORIG-W 1 ; DEFER D-W \' ORIG-W IS D-W : RESET-W PRESERVE D-W ; :IS D-W 3 ; : RUN-W P-W C@ . D-W . RESET-W D-W . T-W . Q-W EXECUTE EXECUTE . DEPTH . ; PREVIOUS PREVIOUS '
if a.disabled != 'image':
    suffix = '.exe' if os.name == 'nt' else ''
    run('image-create', image_source + f'SAVE composite.sigma SAVESYS composite{suffix}', b'')
    expected = b'65 3 1 11 7 0 '
    run('image-append-relocation', 'CREATE BEFORE-W 77 ALLOT 500 ALLOCATE THROW DROP LOAD-DICTIONARY composite.sigma RUN-W', expected)
    run('image-executable', 'RUN-W', expected, binary=str(root / ('composite' + suffix)))
    run('image-marker-forget', '0 WARNINGS ! : KEPT 91 ; MARKER BACK-W LOAD-DICTIONARY composite.sigma RUN-W BACK-W [DEFINED] RUN-W . KEPT . DEPTH .', expected + b'0 91 0 ')
    run('image-resave', 'LOAD-DICTIONARY composite.sigma SAVE second.sigma LOAD-DICTIONARY second.sigma RUN-W', expected)
    run('image-forget-typed-root', 'LOAD-DICTIONARY composite.sigma P-W C@ . FORGET P-W [DEFINED] RUN-W . [DEFINED] P-W . DEPTH .', b'65 0 0 0 ')
    # Corruption must leave preexisting definitions available after caught failure.
    corrupt = bytearray((root / 'composite.sigma').read_bytes())
    corrupt[-1] ^= 1
    (root / 'corrupt.sigma').write_bytes(corrupt)
    run('image-corrupt-atomic', ': KEPT 42 ; : BAD-W S" LOAD-DICTIONARY corrupt.sigma" EVALUATE ; \' BAD-W CATCH 0<> . KEPT . [DEFINED] RUN-W . DEPTH .', b'-1 42 0 0 ')
    for group, magic, source, call, expected in [
        ('graphics', b'SIGIMG46', 'REQUIRE-GRAPHICS ALSO GRAPHICS : RUN-GFX-W 2 2 GFX-INIT 0 0 123 GFX-PSET 0 0 GFX-PGET . ; PREVIOUS ', 'RUN-GFX-W', b'123 '),
        ('audio', b'SIGIMG47', 'REQUIRE-AUDIO ALSO AUDIO : RUN-AUDIO-W [\'] SND-PLAY DROP 42 . ; PREVIOUS ', 'RUN-AUDIO-W', b'42 '),
    ]:
        if a.disabled == group:
            continue
        run(f'image-{group}-create', source + f'SAVE {group}.sigma SAVESYS {group}{suffix}', b'')
        assert (root / (group + '.sigma')).read_bytes()[:8] == magic
        run(f'image-{group}-append', f'CREATE PREFIX-W 73 ALLOT LOAD-DICTIONARY {group}.sigma {call}', expected)
        run(f'image-{group}-standalone', call, expected, binary=str(root / (group + suffix)))

output.write_text(json.dumps({'complete': True, 'disabled': a.disabled, 'cases': passed}, indent=2) + '\n')
temporary.cleanup()
print(f'{len(passed)} P10 integration cases passed; disabled={a.disabled}')

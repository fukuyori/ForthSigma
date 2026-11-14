#!/usr/bin/env python3
"""Windows host boundaries using filesystem/Python oracles, not Gforth output."""
import argparse
import datetime
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--sigma', type=Path, default=Path('zig-out/bin/sigma.exe'))
p.add_argument('--minimal', type=Path)
a = p.parse_args()
if os.name != 'nt':
    p.error('Windows required')
sigma = str(a.sigma.resolve(strict=True))
report_dir = Path('.work/windows-boundaries').resolve()
root = report_dir / f'run-{time.time_ns()}'
root.mkdir(parents=True, exist_ok=True)
rows = []

def run(name, code, expected=None, data=b'', env=None, binary=None, options=()):
    flags = [] if binary else ['--max-steps', '30000000']
    r = subprocess.run([binary or sigma, *flags, *options, '-e', code + ' BYE'],
                       cwd=root, input=data, capture_output=True, timeout=30, env=env)
    assert r.returncode == 0, (name, r.returncode, r.stdout, r.stderr)
    if expected is not None:
        assert r.stdout == expected, (name, r.stdout, r.stderr, expected)
    rows.append({'case': name, 'stdout_hex': r.stdout.hex()})
    (report_dir / 'report.json').write_text(json.dumps({'complete': False, 'workdir': str(root), 'passed': rows}, indent=2) + '\n')
    return r.stdout

# CRT permissions are owner read/write; executable/group/other bits do not map
# to Windows ACLs. Check FILE_ATTRIBUTE_READONLY through Python's stat result.
mode_file = root / 'mode.bin'
for mode in [0, 0o400, 0o600, 0o640, 0o644, 0o666, 0o700, 0o755, 0o777]:
    if mode_file.exists():
        mode_file.chmod(stat.S_IWRITE | stat.S_IREAD)
        mode_file.unlink()
    run(f'fmode-create-{mode:o}', f'S" {mode_file}" W/O {mode} +FMODE CREATE-FILE THROW CLOSE-FILE THROW', b'')
    assert bool(mode_file.stat().st_mode & stat.S_IWRITE) == bool(mode & 0o200), (mode, mode_file.stat())
mode_file.chmod(stat.S_IWRITE | stat.S_IREAD)
run('fmode-existing-preserved', f'S" {mode_file}" W/O 256 +FMODE CREATE-FILE THROW CLOSE-FILE THROW', b'')
assert mode_file.stat().st_mode & stat.S_IWRITE

# Invalid UTF-8 and locale independence for the common Unicode glob matcher.
cases = [('日本語', '???', -1), ('é', '?', -1), ('é', '[[:alpha:]]', 0),
         ('a/b', '*', -1), ('.hidden', '*', -1), ('A', '[a-c]', 0),
         ('😀', '?', -1), ('abc', 'a*c', -1), ('abc', 'a?d', 0)]
for locale in ['C', 'Japanese_Japan.932', 'en_US.UTF-8']:
    code = ' '.join(f'S" {name}" S" {pattern}" FILENAME-MATCH .' for name, pattern, _ in cases)
    run('glob-locale-' + locale, code, ''.join(f'{flag} ' for _, _, flag in cases).encode(), env=dict(os.environ, LC_ALL=locale))
run('glob-invalid-utf8', 'CREATE BAD 255 C, BAD 1 S" ?" FILENAME-MATCH . DEPTH .', b'-1 0 ')
if a.minimal:
    run('glob-files-disabled', '[DEFINED] FILENAME-MATCH .', b'0 ', binary=str(a.minimal.resolve()))

# UTF-8 capacity includes the NUL terminator, not the UTF-16 length.
child = root / '日本語 dir'
child.mkdir(exist_ok=True)
setup = 'CREATE WIN-B 8192 ALLOT : WIN-CWD WIN-B 8192 GET-DIR TYPE ; '
for capacity in [0, 1, len(str(root).encode()), len(str(root).encode()) + 1]:
    out = run(f'cwd-capacity-{capacity}', setup + f'WIN-B 8192 88 FILL WIN-B {capacity} GET-DIR DUP . OVER 0= . 2DROP WIN-B {capacity} + C@ .')
    ok = capacity > len(str(root).encode())
    assert out == f'{len(str(root).encode()) if ok else 0} {0 if ok else -1} 88 '.encode(), out
for path in ['日本語 dir', './日本語 dir', str(child), str(child).replace('\\', '/')]:
    run('cwd-unicode-' + path, setup + f'S" {path}" SET-DIR THROW WIN-CWD', str(child).encode())
run('cwd-failed-unchanged', setup + 'S" missing" SET-DIR 0<> . WIN-CWD', b'-1 ' + str(root).encode())
run('cwd-home', setup + 'S" ~" SET-DIR THROW WIN-CWD', str(Path.home()).encode())
for capacity in [len(str(child).encode()), len(str(child).encode()) + 1]:
    out = run(f'cwd-unicode-capacity-{capacity}', setup + f'S" {child}" SET-DIR THROW WIN-B {capacity} GET-DIR DUP . OVER 0= . 2DROP')
    assert out == f'{len(str(child).encode()) if capacity > len(str(child).encode()) else 0} {0 if capacity > len(str(child).encode()) else -1} '.encode(), out
run('cwd-drive-relative', setup + f'S" {root.drive}" SET-DIR THROW WIN-CWD', str(root).encode())

for index, (word, name, expected) in enumerate([
    ('=MKDIR', '日本語 leaf', b'0 '), ('=MKDIR', '日本語 leaf', b'-529 '),
    ('=MKDIR', 'missing/leaf', b'-514 '), ('MKDIR-PARENTS', 'tree/a/b', b'0 '),
    ('MKDIR-PARENTS', 'tree/a/b', b'-529 '), ('MKDIR-PARENTS', 'tree\\c\\d', b'-514 '),
]):
    run(f'mkdir-{index}', f'S" {name}" 493 {word} .', expected)
assert (root / 'tree/a/b').is_dir() and not (root / 'tree/c/d').exists()
for mode in [0, 0o400, 0o600, 0o777]:
    run(f'mkdir-mode-ignored-{mode}', f'S" mode-dir-{mode}" {mode} =MKDIR .', b'0 ')
    assert (root / f'mode-dir-{mode}').is_dir()
(root / 'blocking-file').write_bytes(b'x')
run('mkdir-partial', 'S" fresh/../blocking-file/child" 493 MKDIR-PARENTS 0<> .', b'-1 ')
assert (root / 'fresh').is_dir() and (root / 'blocking-file').is_file()

empty = root / 'empty'
empty.mkdir(exist_ok=True)
run('dir-dot-entries', f'S" {empty}" OPEN-DIR THROW CONSTANT D : WIN-N 0 BEGIN PAD 128 D READ-DIR THROW WHILE DROP 1+ REPEAT DROP ; WIN-N . D CLOSE-DIR THROW', b'2 ')
entry_dir = root / 'entries'
entry_dir.mkdir(exist_ok=True)
(entry_dir / '日本語-long-file').write_bytes(b'x')
run('dir-truncation', f'S" {entry_dir}" OPEN-DIR THROW CONSTANT D : T BEGIN PAD 1 D READ-DIR DUP IF . 2DROP EXIT THEN DROP WHILE DROP REPEAT DROP ; T D CLOSE-DIR THROW', b'-550 ')
run('dir-missing', 'S" missing-dir" OPEN-DIR NIP 0<> .', b'-1 ')
run('dir-stale-id', 'S" ." OPEN-DIR THROW CONSTANT D D CLOSE-DIR THROW D CLOSE-DIR . PAD 8 D READ-DIR . . .', b'-521 -521 0 0 ')
run('dir-file-error', 'S" blocking-file" OPEN-DIR . .', b'-532 0 ')
run('dir-handle-capacity-release', 'CREATE IDS 64 CELLS ALLOT : TEST-DIRS 64 0 DO S" ." OPEN-DIR THROW IDS I CELLS + ! LOOP S" ." OPEN-DIR . . 64 0 DO IDS I CELLS + @ CLOSE-DIR THROW LOOP S" ." OPEN-DIR THROW CLOSE-DIR . ; TEST-DIRS', b'-536 0 0 ')

# FPATH lookup priority, explicit/source-relative paths, aliases and images.
for directory, value in [('cwd', 11), ('lib', 22), ('source', 33)]:
    (root / directory).mkdir(exist_ok=True)
    (root / directory / 'item.fs').write_text(f'{value} .\n')
(root / 'source/main.fs').write_text('INCLUDE ./item.fs\n')
for name, code, expected in [
    ('path-priority', 'FPATH PATH= cwd|lib INCLUDE item.fs', b'11 '),
    ('path-reverse', 'FPATH PATH= lib|cwd INCLUDE item.fs', b'22 '),
    ('path-source-relative', 'FPATH PATH= cwd|lib INCLUDE ./source/main.fs', b'33 '),
    ('path-drive', f'INCLUDE {root}/source/item.fs', b'33 '),
    ('path-save', 'FPATH PATH= lib SAVE path.sigma', b''),
    ('path-append-keeps-local', 'FPATH PATH= cwd LOAD-DICTIONARY path.sigma INCLUDE item.fs', b'11 '),
    ('path-full-image', 'FPATH PATH= lib SAVESYS fpath.exe', b''),
    ('path-file-lookup-closes', 'VARIABLE PP PP PATH= lib : MANY 100 0 DO S" item.fs" PP FILE>PATH 2DROP LOOP ; MANY DEPTH .', b'0 '),
    ('path-forward-drive', f'INCLUDE {str(root).replace(chr(92), "/")}/source/item.fs', b'33 '),
]:
    run(name, code, expected)
r = subprocess.run([str(root / 'fpath.exe'), '-e', 'INCLUDE item.fs BYE'], cwd=root, input=b'', capture_output=True, timeout=20)
assert (r.returncode, r.stdout) == (0, b'22 '), (r.returncode, r.stdout, r.stderr)
rows.append({'case': 'path-full-image-run'})
home_env = dict(os.environ, HOME=str(root))
run('path-home-expansion', 'FPATH PATH= ~+ INCLUDE ~/lib/item.fs', b'22 ', env=home_env)
(child / 'item.fs').write_text('44 .\n')
run('path-search-spaces', 'S" 日本語 dir" FPATH ALSO-PATH INCLUDE item.fs', b'44 ')

# File readiness/EOF and ungetc through the shared stdio route.
byte_file = root / 'byte.bin'
for value in range(-1, 256):
    byte_file.write_bytes(b'' if value < 0 else bytes([value]))
    code = f'S" {byte_file}" R/O OPEN-FILE THROW CONSTANT F F FILE-EOF? . F KEY?-FILE . F KEY-FILE . F KEY-FILE . F FILE-EOF? . 0 0 F REPOSITION-FILE THROW F FILE-EOF? . F CLOSE-FILE THROW'
    run(f'file-ready-eof-{value}', code, f'0 {-1 if value >= 0 else 0} {value} -1 -1 0 '.encode())
byte_file.write_bytes(b'\xc3Z')
run('infile-ungetc', f'S" {byte_file}" R/O OPEN-FILE THROW CONSTANT F : R EKEY . ; \' R F INFILE-EXECUTE F KEY-FILE . F CLOSE-FILE THROW', b'65533 90 ')
byte_file.write_bytes(b'AB\rZ\n')
run('infile-cr-ungetc', f'S" {byte_file}" R/O OPEN-FILE THROW CONSTANT F : R PAD 1 ACCEPT . PAD 1 TYPE ; \' R F INFILE-EXECUTE F KEY-FILE . F CLOSE-FILE THROW', b'1 A90 ')
run('key-ior-file-eof', 'KEY-IOR . KEY-IOR .', b'3 -512 ', data=b'\x03')
first = root / 'input-a.bin'
second = root / 'input-b.bin'
first.write_bytes(b'AC')
second.write_bytes(b'B')
open_inputs = f'S" {first}" R/O OPEN-FILE THROW CONSTANT FA S" {second}" R/O OPEN-FILE THROW CONSTANT FB '
run('input-nested', open_inputs + ': INNER KEY . ; : OUTER KEY . [\'] INNER FB INFILE-EXECUTE KEY . ; \' OUTER FA INFILE-EXECUTE FA CLOSE-FILE THROW FB CLOSE-FILE THROW INFILE-ID STDIN = .', b'65 66 67 -1 ')
run('input-nested-same', open_inputs + ': INNER KEY . ; : OUTER KEY . [\'] INNER FA INFILE-EXECUTE ; \' OUTER FA INFILE-EXECUTE FA CLOSE-FILE THROW FB CLOSE-FILE THROW', b'65 67 ')
first.write_bytes(b'')
run('input-selected-eof', open_inputs + ': R KEY DROP ; : W [\'] R FA INFILE-EXECUTE ; \' W CATCH . INFILE-ID STDIN = . FA CLOSE-FILE THROW FB CLOSE-FILE THROW', b'-262 -1 ')
first.write_bytes(b'A')
run('input-selected-ready', open_inputs + ': R KEY? . EKEY? . KEY . KEY? . ; \' R FA INFILE-EXECUTE FA CLOSE-FILE THROW FB CLOSE-FILE THROW', b'-1 -1 65 0 ')

# Borrowed SH-GET output is copied before a second call and survives independently.
run('shell-borrow-copy', 'VARIABLE COPY-OUT S" echo FIRST" SH-GET COPY-OUT $! S" echo SECOND" SH-GET TYPE COPY-OUT $@ TYPE COPY-OUT $FREE DEPTH .', b'SECOND\r\r\nFIRST\r\r\n0 ')

# Broken reader must report an ior rather than kill the VM.
run('broken-pipe', 'S" exit 0" W/O OPEN-PIPE THROW CONSTANT P : W 100 0 DO S" x" P WRITE-FILE DUP IF UNLOOP EXIT THEN DROP 10 MS LOOP 0 ; W . P CLOSE-PIPE 2DROP', b'-534 ')
run('sh-get-repeated', 'S" echo A" SH-GET 2DUP TYPE S" echo BC" SH-GET TYPE 2DROP DEPTH .', b'A\r\r\nBC\r\r\n0 ')
large = root / 'large-output.py'
large.write_text('import os\ntry:\n os.write(1,b"x"*2097152)\nexcept OSError: pass\n')
large_command = subprocess.list2cmdline([sys.executable, str(large)])
run('sh-get-failed-read-releases-pipe-and-heap', f': TRY-READ S" {large_command}" SH-GET 2DROP ; : REPEAT-FAIL 70 0 DO [\'] TRY-READ CATCH -524 <> IF -999 THROW THEN LOOP ; REPEAT-FAIL S" echo recovered" SH-GET TYPE DEPTH .', b'recovered\r\r\n0 ', options=['-m', '1M'])

# time_ns is independent of Sigma's FILETIME epoch conversion.
before = time.time_ns()
out = run('ntime-epoch', 'NTIME D.')
after = time.time_ns()
assert before <= int(out) <= after, (before, out, after)
out = run('cputime-units', 'CPUTIME D. D.')
assert all(int(x) >= 0 for x in out.split()), out
burn = root / 'burn.py'
burn.write_text('import time\nend=time.process_time()+0.4\nwhile time.process_time()<end: sum(i*i for i in range(10000))\n')
command = subprocess.list2cmdline([sys.executable, str(burn)])
started = time.monotonic()
out = run('cputime-child-excluded', f'2VARIABLE U0 2VARIABLE S0 CPUTIME S0 2! U0 2! S" {command}" SYSTEM CPUTIME S0 2@ D- D. U0 2@ D- D.')
assert sum(map(int, out.split())) < (time.monotonic() - started) * 500000, out
for ns in [-1, 0, 1, 1000000, 20000000]:
    out = run(f'ns-duration-{ns}', f'2VARIABLE T NTIME T 2! {ns}. NS NTIME T 2@ D- D.')
    assert int(out) >= max(0, ns), out
run('ns-range', ': W 170141183460469231731687303715884105727. NS ; \' W CATCH .', b'-11 ')
run('ns-pipe-input-preserved', '1000000. NS KEY-IOR . KEY-IOR .', b'3 65 ', data=b'\x03A')
for zone in ['UTC0', 'JST-9', 'EST5EDT']:
    env = dict(os.environ, TZ=zone)
    for stamp in [0, 1704067200, 1719792000, 2147483648]:
        # Python and Sigma both use the Windows CRT TZ grammar, not IANA names.
        oracle = subprocess.run([sys.executable, '-c', 'import time,sys,json; time.tzset() if hasattr(time,"tzset") else None; print(json.dumps(list(time.localtime(int(sys.argv[1])))[:6]))', str(stamp)], env=env, capture_output=True, check=True)
        fields = json.loads(oracle.stdout)
        run(f'timezone-{zone}-{stamp}', f'{stamp}. >TIME&DATE&TZ 2DROP 2DROP . . . . . .', ''.join(str(x) + ' ' for x in fields).encode(), env=env)
        out = run(f'timezone-offset-dst-{zone}-{stamp}', f'{stamp}. >TIME&DATE&TZ 2DROP . . . . . . . .', env=env)
        expected_local = datetime.datetime(*fields)
        offset = int((expected_local - datetime.datetime(1970, 1, 1)).total_seconds()) - stamp
        actual = list(map(int, out.split()))
        assert actual[0] == offset, (zone, stamp, actual, offset)
        assert actual[1] == (-1 if zone == 'EST5EDT' and 3 < expected_local.month < 11 else 0), (zone, stamp, actual)
        name = run(f'timezone-name-{zone}-{stamp}', f'{stamp}. >TIME&DATE&TZ TYPE', env=env).decode('utf-8')
        assert name and '\0' not in name, (zone, name)
for stamp in [2**80, -2**80, 2**63-1, -2**63, -1]:
    run(f'timezone-range-{stamp}', f': T {stamp}. >TIME&DATE&TZ ; \' T CATCH . DEPTH .', b'-11 0 ')
run('timezone-failure-preserves-zone', 'VARIABLE ZONE-SAVE VARIABLE ZONE-PTR VARIABLE ZONE-LEN 0. >TIME&DATE&TZ DUP ZONE-LEN ! OVER ZONE-PTR ! ZONE-SAVE $! 2DROP 2DROP 2DROP 2DROP : BAD-TIME 9223372036854775807. >TIME&DATE&TZ ; \' BAD-TIME CATCH . ZONE-PTR @ ZONE-LEN @ ZONE-SAVE $@ COMPARE . ZONE-SAVE $FREE DEPTH .', b'-11 0 0 ')
run('form-redirected-and-cursor-sequence', 'FORM . . 2 -3 AT-DELTAXY', b'80 24 \x1b[2C\x1b[3A')
(report_dir / 'report.json').write_text(json.dumps({'complete': True, 'workdir': str(root), 'passed': rows}, indent=2) + '\n')
print(f'{len(rows)} Windows boundary cases passed')

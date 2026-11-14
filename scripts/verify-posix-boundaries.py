#!/usr/bin/env python3
"""POSIX host acceptance using Python/OS oracles, without substituting Gforth."""
import argparse
import datetime
import errno
import json
import os
from pathlib import Path
import pwd
import shlex
import stat
import subprocess
import sys
import tempfile
import time
import zoneinfo

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--sigma', type=Path, required=True)
p.add_argument('--minimal', type=Path, required=True)
p.add_argument('--output', type=Path, default=Path('.work/wsl-boundaries/report.json'))
a = p.parse_args()
sigma = str(a.sigma.resolve(strict=True))
minimal = str(a.minimal.resolve(strict=True))
output = a.output.resolve()
output.parent.mkdir(parents=True, exist_ok=True)
temporary = tempfile.TemporaryDirectory(prefix='sigma-posix-boundaries-', dir='/tmp')
root = Path(temporary.name)
rows = []

def report(complete=False):
    output.write_text(json.dumps({'complete': complete, 'platform': sys.platform,
                                 'fixture_filesystem': str(root), 'cases': rows}, indent=2) + '\n')

def run(name, source, expected=None, *, data=b'', env=None, mask=None, options=(), binary=None):
    command = [binary or sigma]
    if not binary:
        command += ['--max-steps', '30000000']
    command += [*options, '-e', source + ' BYE']
    before = time.time_ns()
    r = subprocess.run(command, cwd=root, input=data, capture_output=True, timeout=30,
                       env=env, preexec_fn=None if mask is None else lambda: os.umask(mask))
    after = time.time_ns()
    assert r.returncode == 0, (name, r.returncode, r.stdout, r.stderr)
    if expected is not None:
        assert r.stdout == expected, (name, r.stdout, expected, r.stderr)
    rows.append({'case': name, 'stdout_hex': r.stdout.hex(), 'start_ns': before, 'end_ns': after})
    report()
    return r.stdout

# Use Linux /tmp, not DrvFs, for permissions and native directory semantics.
mode_file = root / 'permissions.bin'
for mask in [0, 0o022, 0o027, 0o077]:
    for mode in [0, 0o400, 0o600, 0o640, 0o644, 0o666, 0o700, 0o755, 0o777]:
        mode_file.unlink(missing_ok=True)
        run(f'fmode-{mode:o}-umask-{mask:o}', f'S" {mode_file}" W/O {mode} +FMODE CREATE-FILE THROW CLOSE-FILE THROW', b'', mask=mask)
        assert stat.S_IMODE(mode_file.stat().st_mode) == mode & ~mask, (mode, mask, mode_file.stat())
mode_file.chmod(0o600)
run('fmode-truncate-keeps-existing', f'S" {mode_file}" W/O 0 +FMODE CREATE-FILE THROW CLOSE-FILE THROW', b'')
assert stat.S_IMODE(mode_file.stat().st_mode) == 0o600
run('fmode-open-keeps-existing', f'S" {mode_file}" R/O 511 +FMODE OPEN-FILE THROW CLOSE-FILE THROW', b'')
assert stat.S_IMODE(mode_file.stat().st_mode) == 0o600

glob_cases = [('日本語', '???', -1), ('é', '?', -1), ('é', '[[:alpha:]]', 0),
              ('a/b', '*', -1), ('.hidden', '*', -1), ('A', '[a-c]', 0), ('😀', '?', -1)]
for locale in ['C', 'C.UTF-8', 'en_US.UTF-8']:
    code = ' '.join(f'S" {name}" S" {pattern}" FILENAME-MATCH .' for name, pattern, _ in glob_cases)
    run(f'glob-locale-{locale}', code, ''.join(f'{flag} ' for _, _, flag in glob_cases).encode(), env=dict(os.environ, LC_ALL=locale))
run('glob-invalid-byte', 'CREATE BAD 255 C, BAD 1 S" ?" FILENAME-MATCH .', b'-1 ')
run('glob-files-disabled', '[DEFINED] FILENAME-MATCH .', b'0 ', binary=minimal)

child = root / '日本語 dir'
child.mkdir()
setup = 'CREATE BUF-W 8192 ALLOT : PRINT-CWD-W BUF-W 8192 GET-DIR TYPE ; '
for path in [root, child]:
    length = len(str(path).encode())
    for capacity in [0, 1, length - 1, length, length + 1, 4096]:
        prefix = '' if path == root else f'S" {path}" SET-DIR THROW '
        code = setup + prefix + f'BUF-W 8192 88 FILL BUF-W {capacity} GET-DIR DUP . OVER 0= . 2DROP BUF-W {capacity} + C@ .'
        expected = f'{length if capacity > length else 0} {0 if capacity > length else -1} 88 '.encode()
        run(f'cwd-capacity-{path.name}-{capacity}', code, expected)
for path in ['日本語 dir', './日本語 dir', str(child), '日本語 dir/../日本語 dir']:
    run(f'cwd-path-{path}', setup + f'S" {path}" SET-DIR THROW PRINT-CWD-W', str(child).encode())
for path in ['missing', str(mode_file)]:
    run(f'cwd-failure-{path}', setup + f'S" {path}" SET-DIR 0<> . PRINT-CWD-W', b'-1 ' + str(root).encode())
run('cwd-home', setup + 'S" ~" SET-DIR THROW PRINT-CWD-W', str(root).encode(), env=dict(os.environ, HOME=str(root)))
user = pwd.getpwuid(os.getuid())
run('cwd-named-home', setup + f'S" ~{user.pw_name}" SET-DIR THROW PRINT-CWD-W', user.pw_dir.encode())

for mask in [0, 0o022, 0o077]:
    for mode in [0, 0o500, 0o700, 0o755, 0o777]:
        target = root / f'mkdir-{mask:o}-{mode:o}'
        run(f'mkdir-mode-{mask:o}-{mode:o}', f'S" {target}" {mode} =MKDIR .', b'0 ', mask=mask)
        assert stat.S_IMODE(target.stat().st_mode) == mode & ~mask
        target.chmod(0o700)  # Permit fixture cleanup after verifying mode zero.
run('mkdir-existing', 'S" 日本語 dir" 493 =MKDIR .', f'{-512-errno.EEXIST} '.encode())
run('mkdir-missing-parent', 'S" missing/leaf" 493 =MKDIR .', f'{-512-errno.ENOENT} '.encode())
run('mkdir-parents', 'S" tree/a/b" 493 MKDIR-PARENTS .', b'0 ')
run('mkdir-parents-existing', 'S" tree/a/b" 493 MKDIR-PARENTS .', f'{-512-errno.EEXIST} '.encode())
(root / 'blocking').write_bytes(b'x')
run('mkdir-partial', 'S" fresh/../blocking/leaf" 493 MKDIR-PARENTS .', f'{-512-errno.ENOTDIR} '.encode())
assert (root / 'fresh').is_dir()
run('mkdir-unicode', 'S" 親/子" 493 MKDIR-PARENTS .', b'0 ')
run('mkdir-backslash-is-name', r'S" slash\literal/leaf" 493 MKDIR-PARENTS .', b'0 ')
assert (root / 'slash\\literal/leaf').is_dir()
run('mkdir-home', 'S" ~/home-tree/leaf" 493 MKDIR-PARENTS .', b'0 ', env=dict(os.environ, HOME=str(root)))

entries = root / 'entries'
entries.mkdir()
for name in ['alpha', '日本語 file', 'a space']:
    (entries / name).write_bytes(b'x')
fd = os.open(os.fsencode(entries) + b'/bad-\xff', os.O_CREAT | os.O_WRONLY, 0o600)
os.close(fd)
code = f'S" {entries}" OPEN-DIR THROW CONSTANT D : ENUM-W BEGIN PAD 1024 D READ-DIR THROW WHILE PAD SWAP TYPE CR REPEAT DROP ; ENUM-W D CLOSE-DIR THROW'
out = run('directory-raw-utf8-enumeration', code)
assert set(out.splitlines()) == {b'.', b'..', *os.listdir(os.fsencode(entries))}, out
empty = root / 'empty'
empty.mkdir()
run('directory-empty-dot-entries', f'S" {empty}" OPEN-DIR THROW CONSTANT D : COUNT-W 0 BEGIN PAD 128 D READ-DIR THROW WHILE DROP 1+ REPEAT DROP ; COUNT-W . D CLOSE-DIR THROW', b'2 ')
run('directory-truncation', f'S" {entries}" OPEN-DIR THROW CONSTANT D : TRY-W BEGIN PAD 1 D READ-DIR DUP IF . 2DROP EXIT THEN DROP WHILE DROP REPEAT DROP ; TRY-W D CLOSE-DIR THROW', f'{-512-errno.ENAMETOOLONG} '.encode())
run('directory-not-dir', 'S" blocking" OPEN-DIR . .', f'{-512-errno.ENOTDIR} 0 '.encode())
run('directory-missing', 'S" absent-dir" OPEN-DIR . .', f'{-512-errno.ENOENT} 0 '.encode())
run('directory-stale', 'S" ." OPEN-DIR THROW CONSTANT D D CLOSE-DIR THROW D CLOSE-DIR . PAD 8 D READ-DIR . . .', b'-521 -521 0 0 ')
run('directory-capacity-release', 'CREATE IDS 64 CELLS ALLOT : TEST-DIRS 64 0 DO S" ." OPEN-DIR THROW IDS I CELLS + ! LOOP S" ." OPEN-DIR . . 64 0 DO IDS I CELLS + @ CLOSE-DIR THROW LOOP S" ." OPEN-DIR THROW CLOSE-DIR . ; TEST-DIRS', b'-536 0 0 ')

for directory, value in [('cwd', 11), ('lib', 22), ('source', 33), ('日本語 dir', 44)]:
    (root / directory).mkdir(exist_ok=True)
    (root / directory / 'item.fs').write_text(f'{value} .\n')
(root / 'source/main.fs').write_text('INCLUDE ./item.fs\n')
for name, code, expected in [
    ('path-priority', 'FPATH PATH= cwd|lib INCLUDE item.fs', b'11 '),
    ('path-reverse', 'FPATH PATH= lib|cwd INCLUDE item.fs', b'22 '),
    ('path-fallback', 'FPATH PATH= missing|lib INCLUDE item.fs', b'22 '),
    ('path-source-relative', 'FPATH PATH= cwd|lib INCLUDE ./source/main.fs', b'33 '),
    ('path-absolute', f'INCLUDE {root}/source/item.fs', b'33 '),
    ('path-save', 'FPATH PATH= lib SAVE path.sigma', b''),
    ('path-append-keeps-local', 'FPATH PATH= cwd LOAD-DICTIONARY path.sigma INCLUDE item.fs', b'11 '),
    ('path-executable', 'FPATH PATH= lib SAVESYS path-program', b''),
    ('path-handles-close', 'VARIABLE PP PP PATH= lib : MANY-W 100 0 DO S" item.fs" PP FILE>PATH 2DROP LOOP ; MANY-W DEPTH .', b'0 '),
    ('path-spaces', 'S" 日本語 dir" FPATH ALSO-PATH INCLUDE item.fs', b'44 '),
]:
    run(name, code, expected)
run('path-saved-executable-run', 'INCLUDE item.fs', b'22 ', binary=str(root / 'path-program'))
run('path-home', 'FPATH PATH= ~+ INCLUDE ~/lib/item.fs', b'22 ', env=dict(os.environ, HOME=str(root)))
run('path-named-home', f'VARIABLE PP S" ~{user.pw_name}/" PP FILE>PATH TYPE', f'~{user.pw_name}/'.encode())

byte_file = root / 'byte.bin'
for value in range(-1, 256):
    byte_file.write_bytes(b'' if value < 0 else bytes([value]))
    code = f'S" {byte_file}" R/O OPEN-FILE THROW CONSTANT F F FILE-EOF? . F KEY?-FILE . F KEY-FILE . F KEY-FILE . F FILE-EOF? . 0 0 F REPOSITION-FILE THROW F FILE-EOF? . F CLOSE-FILE THROW'
    run(f'file-ready-eof-{value}', code, f'0 {-1 if value >= 0 else 0} {value} -1 -1 0 '.encode())
run('stdin-binary', 'STDIN KEY-FILE . STDIN KEY-FILE . STDIN KEY-FILE . STDIN KEY-FILE . STDIN KEY-FILE . STDIN FILE-EOF? .', b'0 3 255 65 -1 -1 ', data=b'\0\x03\xffA')
for title, data, definition, action, expected in [
    ('xkey-unread', b'\xc3Z', ': R XKEY . ;', "' R F INFILE-EXECUTE F KEY-FILE .", b'65533 90 '),
    ('ekey-unread', b'\xc3Z', ': R EKEY . ;', "' R F INFILE-EXECUTE F KEY-FILE .", b'65533 90 '),
    ('cr-unread', b'AB\rZ\n', ': R PAD 1 ACCEPT . PAD 1 TYPE ;', "' R F INFILE-EXECUTE F KEY-FILE .", b'1 A90 '),
    ('selected-eof', b'', ': R KEY DROP ; : W [\'] R F INFILE-EXECUTE ;', "' W CATCH . INFILE-ID STDIN = .", b'-262 -1 '),
    ('selected-ready', b'A', ': R KEY? . EKEY? . KEY . KEY? . ;', "' R F INFILE-EXECUTE", b'-1 -1 65 0 '),
    ('selected-throw', b'AB', ': R KEY DROP -123 THROW ; : W [\'] R F INFILE-EXECUTE ;', "' W CATCH . F KEY-FILE . INFILE-ID STDIN = .", b'-123 66 -1 '),
]:
    byte_file.write_bytes(data)
    run(title, f'S" {byte_file}" R/O OPEN-FILE THROW CONSTANT F ' + definition + ' ' + action + ' F CLOSE-FILE THROW', expected)
other = root / 'other.bin'
byte_file.write_bytes(b'AC')
other.write_bytes(b'B')
open_inputs = f'S" {byte_file}" R/O OPEN-FILE THROW CONSTANT FA S" {other}" R/O OPEN-FILE THROW CONSTANT FB '
run('selected-nested', open_inputs + ': INNER KEY . ; : OUTER KEY . [\'] INNER FB INFILE-EXECUTE KEY . ; \' OUTER FA INFILE-EXECUTE FA CLOSE-FILE THROW FB CLOSE-FILE THROW INFILE-ID STDIN = .', b'65 66 67 -1 ')
run('selected-same', open_inputs + ': INNER KEY . ; : OUTER KEY . [\'] INNER FA INFILE-EXECUTE ; \' OUTER FA INFILE-EXECUTE FA CLOSE-FILE THROW FB CLOSE-FILE THROW', b'65 67 ')

for ns in [-1, 0, 1, 1000000, 20000000, 100000000]:
    out = run(f'ns-duration-{ns}', f'2VARIABLE T NTIME T 2! {ns}. NS NTIME T 2@ D- D.')
    assert int(out) >= max(0, ns), out
run('ns-range', ': W 170141183460469231731687303715884105727. NS ; \' W CATCH .', b'-11 ')
run('ns-pipe-preserved', '1000000. NS KEY-IOR . KEY-IOR .', b'3 65 ', data=b'\x03A')
before = time.time_ns()
stamp = int(run('ntime-epoch', 'NTIME D.'))
assert before <= stamp <= time.time_ns(), stamp
out = run('cpu-units', 'CPUTIME D. D.')
assert all(int(x) >= 0 for x in out.split())
burn = root / 'burn.py'
burn.write_text('import time\nend=time.process_time()+0.4\nwhile time.process_time()<end: sum(i*i for i in range(10000))\n')
command = shlex.join([sys.executable, str(burn)])
start = time.monotonic()
out = run('cpu-child-excluded', f'2VARIABLE U0 2VARIABLE S0 CPUTIME S0 2! U0 2! S" {command}" SYSTEM CPUTIME S0 2@ D- D. U0 2@ D- D.')
assert sum(map(int, out.split())) < (time.monotonic() - start) * 500000, out

show = ': SHOW-TZ >TIME&DATE&TZ DUP . 2DUP BOUNDS ?DO I C@ . LOOP 2DROP . . . . . . . . ; '
for zone in ['UTC', 'Asia/Tokyo', 'America/New_York', 'Europe/London', 'Europe/Dublin', 'Asia/Kathmandu', 'Pacific/Chatham']:
    for stamp in [-2208988800, -1, 0, 951782400, 1704067200, 1710053999, 1710054000, 1719792000, 1730613599, 1730613600, 2147483648, 4102444800, 32503680000]:
        out = run(f'timezone-{zone}-{stamp}', show + f'{stamp}. SHOW-TZ', env=dict(os.environ, TZ=zone))
        values = list(map(int, out.split()))
        length = values[0]
        name = bytes(values[1:1+length]).decode()
        rest = values[1+length:]
        expected = datetime.datetime.fromtimestamp(stamp, zoneinfo.ZoneInfo(zone))
        fields = [expected.year, expected.month, expected.day, expected.hour, expected.minute, expected.second]
        assert rest == [int(expected.utcoffset().total_seconds()), -1 if expected.dst() else 0, *fields], (zone, stamp, values, expected)
        assert name == expected.tzname(), (zone, stamp, name, expected.tzname())
for stamp in [2**80, -2**80, 2**63-1, -2**63]:
    run(f'timezone-range-{stamp}', f': BAD-T {stamp}. >TIME&DATE&TZ ; \' BAD-T CATCH . DEPTH .', b'-11 0 ')
run('timezone-failure-preserves-zone', 'VARIABLE ZS VARIABLE ZP VARIABLE ZL 0. >TIME&DATE&TZ DUP ZL ! OVER ZP ! ZS $! 2DROP 2DROP 2DROP 2DROP : BAD-T 9223372036854775807. >TIME&DATE&TZ ; \' BAD-T CATCH . ZP @ ZL @ ZS $@ COMPARE . ZS $FREE DEPTH .', b'-11 0 0 ')

run('broken-pipe', 'S" exit 0" W/O OPEN-PIPE THROW CONSTANT P : W 100 0 DO S" x" P WRITE-FILE DUP IF UNLOOP EXIT THEN DROP 10 MS LOOP 0 ; W . P CLOSE-PIPE 2DROP', f'{-512-errno.EPIPE} '.encode())
run('borrowed-output-copy', 'VARIABLE COPIED S" printf FIRST" SH-GET COPIED $! S" printf SECOND" SH-GET TYPE COPIED $@ TYPE COPIED $FREE DEPTH .', b'SECONDFIRST0 ')
large = root / 'large.py'
large.write_text('import os\ntry: os.write(1,b"x"*2097152)\nexcept OSError: pass\n')
command = shlex.join([sys.executable, str(large)])
run('failed-read-cleans-pipe-and-heap', f': TRY-W S" {command}" SH-GET 2DROP ; : REPEAT-W 70 0 DO [\'] TRY-W CATCH -524 <> IF -999 THROW THEN LOOP ; REPEAT-W S" printf recovered" SH-GET TYPE DEPTH .', b'recovered0 ', options=['-m', '1M'])
report(True)
temporary.cleanup()
print(f'{len(rows)} POSIX boundary cases passed')

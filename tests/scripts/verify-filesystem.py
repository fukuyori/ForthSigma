#!/usr/bin/env python3
"""Exercise filesystem extension words on owned files and Gforth reference cases."""
import argparse
import errno
import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def run(sigma):
    work = ROOT / '.work/646'
    work.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='public-', dir=work) as folder:
        folder = Path(folder)
        def execute(code):
            source = folder / 'check.fs'
            source.write_text('REQUIRE-EXTENSION ALSO EXTENSION\nCREATE FS-BUFFER-646 16384 ALLOT\n'+code+'\nBYE\n', encoding='utf-8')
            result = subprocess.run([str(sigma.resolve()), str(source)], cwd=ROOT, capture_output=True, text=True, encoding='utf-8', timeout=45)
            if result.returncode or result.stderr.strip():
                raise AssertionError(f'{code[:150]}: {result.returncode}: {result.stderr}\n{result.stdout}')
            return result.stdout.rstrip('\r\n')
        def quoted(path):
            return 'S" '+str(path)+'"'
        reports = []
        reference = json.loads((ROOT / 'tests/data/compact-filename.json').read_text(encoding='utf-8'))['cases']
        code = '\n'.join(f'{quoted(a)} COMPACT-FILENAME DUP . TYPE CR' for a, _ in reference)
        actual = execute(code).splitlines()
        assert len(actual) == len(reference), (len(actual), len(reference), actual[:3], actual[-3:])
        for line, (original, expected) in zip(actual, reference):
            size, _, text = line.partition(' ')
            assert int(size) == len(expected.encode()) and text == expected, (original, expected, line)
        reports.append({'case': 'gforth-compact', 'count': len(reference)})
        # More than the old 1024-byte internal buffer; no host path is opened.
        assert execute('FS-BUFFER-646 8003 97 FILL FS-BUFFER-646 8003 COMPACT-FILENAME NIP .').strip() == '8003'
        reports.append({'case': 'compact-over-1024'})
        file = folder / '確認 file.txt'
        file.write_bytes(b'abcdef')
        os.utime(file, ns=(1700000000123456700, 1700000000123456700))
        actual_stat = file.stat()
        values = [int(x) for x in execute(quoted(file)+' FILE-METADATA THROW . . D.').split()]
        seconds, ns = divmod(actual_stat.st_mtime_ns, 1000000000)
        assert values == [ns, seconds, 6], values
        reports.append({'case': 'metadata-size-nanoseconds', 'seconds': seconds, 'nanoseconds': ns})
        os.utime(file, ns=(-100000000, -100000000))
        negative_stat = file.stat()
        negative_seconds, negative_ns = divmod(negative_stat.st_mtime_ns, 1000000000)
        values = [int(x) for x in execute(quoted(file)+' FILE-METADATA THROW . . D.').split()]
        assert values == [negative_ns, negative_seconds, 6], values
        reports.append({'case': 'metadata-before-epoch', 'requested_nanoseconds': -100000000, 'seconds': negative_seconds, 'nanoseconds': negative_ns})
        real = execute(quoted(file)+' FS-BUFFER-646 16384 FILE>REALPATH THROW FS-BUFFER-646 SWAP TYPE')
        assert os.path.samefile(real, file), real
        assert execute(quoted(real)+' ABSOLUTE-FILE? .').split() == ['-1']
        if os.name == 'nt':
            assert real.startswith('\\\\?\\'), real
        values = [int(x) for x in execute('FS-BUFFER-646 16384 42 FILL '+quoted(file)+' FS-BUFFER-646 0 FILE>REALPATH . . FS-BUFFER-646 C@ .').split()]
        assert values[0] != 0 and values[1] == len(real.encode()) and values[2] == 42, values
        assert execute('FS-BUFFER-646 16384 42 FILL '+quoted(file)+' FS-BUFFER-646 1 FILE>REALPATH 0<> . DROP FS-BUFFER-646 C@ .').split() == ['-1', '42']
        assert execute(quoted(file)+' DUP >R FS-BUFFER-646 SWAP MOVE FS-BUFFER-646 R> FS-BUFFER-646 16384 FILE>REALPATH THROW FS-BUFFER-646 SWAP TYPE') == real
        reports.append({'case': 'realpath-query-short-alias'})
        missing = folder / 'missing'
        assert execute('FS-BUFFER-646 16384 42 FILL '+quoted(missing)+' FS-BUFFER-646 16384 FILE>REALPATH 0<> . . FS-BUFFER-646 C@ .').split() == ['-1', '0', '42']
        assert execute(quoted(missing)+' FILE-METADATA 0<> . . . D.').split() == ['-1', '0', '0', '0']
        assert execute(quoted(folder)+' FILE-METADATA 0<> . . . D.').split() == ['-1', '0', '0', '0']
        reports.append({'case': 'missing-directory-errors'})
        assert execute('S" " FS-BUFFER-646 16384 FILE>REALPATH . .').split() == ['-534', '0']
        assert execute('0 FS-BUFFER-646 C! FS-BUFFER-646 1 FILE-METADATA . . . D.').split() == ['-534', '0', '0', '0']
        long_error = str(-512 - errno.ENAMETOOLONG)
        assert execute('FS-BUFFER-646 4096 97 FILL FS-BUFFER-646 4096 FILE-METADATA . . . D.').split() == [long_error, '0', '0', '0']
        assert execute('FS-BUFFER-646 4096 97 FILL FS-BUFFER-646 4096 FS-BUFFER-646 16384 FILE>REALPATH . .').split() == [long_error, '0']
        code = quoted(file)+' R/W OPEN-FILE THROW CONSTANT FS-FILE-646 S" changed" FS-FILE-646 WRITE-FILE THROW FS-FILE-646 SYNC-FILE THROW FS-FILE-646 FILE-POSITION THROW D. FS-FILE-646 CLOSE-FILE THROW FS-FILE-646 SYNC-FILE 0<> . STDIN SYNC-FILE 0<> .'
        assert execute(code).split() == ['7', '-1', '-1']
        assert file.read_bytes() == b'changed'
        assert execute(quoted(file)+' R/O OPEN-FILE THROW CONSTANT FS-FILE-646 FS-FILE-646 SYNC-FILE 0<> . FS-FILE-646 CLOSE-FILE THROW').split() == ['-1']
        # A read/write stream keeps logical position and unread bytes across sync.
        code = quoted(file)+' R/W OPEN-FILE THROW CONSTANT FS-FILE-646 FS-BUFFER-646 2 FS-FILE-646 READ-FILE THROW . FS-FILE-646 FILE-POSITION THROW D. FS-FILE-646 SYNC-FILE THROW FS-FILE-646 FILE-POSITION THROW D. FS-BUFFER-646 5 FS-FILE-646 READ-FILE THROW FS-BUFFER-646 SWAP TYPE FS-FILE-646 CLOSE-FILE THROW'
        assert execute(code).split() == ['2', '2', '2', 'anged']
        # Exercise write -> read -> SYNC in the existing update-stream interface.
        code = quoted(file)+' R/W OPEN-FILE THROW CONSTANT FS-FILE-646 S" ZZ" FS-FILE-646 WRITE-FILE THROW FS-BUFFER-646 1 FS-FILE-646 READ-FILE THROW DROP FS-BUFFER-646 C@ . FS-FILE-646 SYNC-FILE THROW FS-FILE-646 FILE-POSITION THROW D. FS-FILE-646 CLOSE-FILE THROW'
        assert execute(code).split() == ['97', '3']
        assert file.read_bytes() == b'ZZanged', file.read_bytes()
        for method, expected in [
            ('FS-BUFFER-646 8 FS-FILE-646 READ-LINE THROW DROP DUP . FS-BUFFER-646 SWAP TYPE SPACE', ['5', 'bcdef', '7']),
            ('FS-FILE-646 KEY-FILE .', ['98', '2']),
            ('FS-FILE-646 KEY?-FILE . FS-FILE-646 SYNC-FILE THROW FS-FILE-646 KEY-FILE .', ['-1', '98', '2']),
        ]:
            file.write_bytes(b'abcdef\n')
            code = quoted(file)+' R/W OPEN-FILE THROW CONSTANT FS-FILE-646 S" Z" FS-FILE-646 WRITE-FILE THROW '+method+' FS-FILE-646 SYNC-FILE THROW FS-FILE-646 FILE-POSITION THROW D. FS-FILE-646 CLOSE-FILE THROW'
            assert execute(code).split() == expected, method
            assert file.read_bytes() == b'Zbcdef\n'
        file.write_bytes(b'a\rbc')
        code = quoted(file)+' R/W OPEN-FILE THROW CONSTANT FS-FILE-646 FS-BUFFER-646 8 FS-FILE-646 READ-LINE THROW 2DROP FS-FILE-646 SYNC-FILE THROW FS-FILE-646 FILE-POSITION THROW D. FS-BUFFER-646 2 FS-FILE-646 READ-FILE THROW FS-BUFFER-646 SWAP TYPE SPACE FS-BUFFER-646 8 FS-FILE-646 READ-FILE THROW DROP FS-FILE-646 SYNC-FILE THROW FS-FILE-646 FILE-EOF? . FS-BUFFER-646 8 FS-FILE-646 READ-FILE THROW . FS-FILE-646 CLOSE-FILE THROW'
        assert execute(code).split() == ['2', 'bc', '-1', '0']
        reports.append({'case': 'sync-flush-position-readonly-closed-directions'})
        sink = 'more > nul' if os.name == 'nt' else 'cat > /dev/null'
        code = quoted(sink)+' W/O OPEN-PIPE THROW CONSTANT FS-FILE-646 FS-FILE-646 SYNC-FILE 0<> . FS-FILE-646 CLOSE-PIPE THROW DROP'
        assert execute(code).split() == ['-1']
        reports.append({'case': 'sync-reject-pipe-before-flush'})
        if os.name != 'nt':
            link = folder / 'link'
            link.symlink_to(file.name)
            assert os.path.samefile(execute(quoted(link)+' FS-BUFFER-646 16384 FILE>REALPATH THROW FS-BUFFER-646 SWAP TYPE'), file)
            assert execute(quoted(link)+' FILE-METADATA THROW 2DROP D.').split() == ['4']
            link.unlink()
            link.symlink_to('missing')
            assert execute(quoted(link)+' FS-BUFFER-646 16384 FILE>REALPATH 0<> . DROP').split() == ['-1']
            assert execute('S" /dev/null" R/W OPEN-FILE THROW CONSTANT FS-FILE-646 FS-FILE-646 SYNC-FILE 0<> . FS-FILE-646 CLOSE-FILE THROW').split() == ['-1']
            reports.append({'case': 'symlink-dangling-device'})
        else:
            target = folder / 'target-dir'
            target.mkdir()
            junction = folder / 'junction'
            result = subprocess.run(['cmd', '/c', 'mklink', '/J', str(junction), str(target)], capture_output=True)
            if result.returncode:
                raise AssertionError('owned junction creation failed')
            try:
                actual = execute(quoted(junction)+' FS-BUFFER-646 16384 FILE>REALPATH THROW FS-BUFFER-646 SWAP TYPE')
                assert os.path.samefile(actual, target)
            finally:
                junction.rmdir()
            assert execute('S" \\\\.\\pipe\\sigma-must-not-connect" FS-BUFFER-646 16384 FILE>REALPATH 0<> . DROP').split() == ['-1']
            for name in ['/??/pipe/sigma-must-not-connect', 'COM1', 'NUL', 'CONIN$']:
                assert execute(quoted(name)+' FS-BUFFER-646 16384 FILE>REALPATH . .').split() == ['-534', '0']
                assert execute(quoted(name)+' FILE-METADATA . . . D.').split() == ['-534', '0', '0', '0']
            assert execute('S" NUL" R/W OPEN-FILE THROW CONSTANT FS-FILE-646 FS-FILE-646 SYNC-FILE 0<> . FS-FILE-646 CLOSE-FILE THROW').split() == ['-1']
            reports.append({'case': 'junction-explicit-pipe-device'})
        return {'platform': os.name, 'cases': reports}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sigma', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = run(args.sigma)
    if args.output:
        args.output.write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result))

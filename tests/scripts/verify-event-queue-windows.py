#!/usr/bin/env python3
"""Standard-event acceptance using an isolated hidden Windows console."""
import ctypes as c
from ctypes import wintypes as w
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def main():
    if not __debug__:
        raise SystemExit('Run acceptance tests without Python -O')
    if os.name != 'nt': raise SystemExit('Windows required')
    import msvcrt
    sigma = str(Path(sys.argv[1]).resolve(strict=True))
    folder = Path('.work/event-queue/windows').resolve(); folder.mkdir(parents=True, exist_ok=True)
    if '--child' not in sys.argv:
        startup = subprocess.STARTUPINFO(); startup.dwFlags = subprocess.STARTF_USESHOWWINDOW; startup.wShowWindow = 0
        with (folder / 'console.log').open('w') as log:
            result = subprocess.run([sys.executable, __file__, sigma, '--child'], stdout=log, stderr=log,
                                    creationflags=subprocess.CREATE_NEW_CONSOLE, startupinfo=startup, timeout=30)
        if result.returncode:
            print((folder / 'console.log').read_text(errors='replace')); raise SystemExit(result.returncode)
        report = json.loads((folder / 'result.json').read_text())
        assert report['complete']; print(f'{len(report["cases"])} Windows standard-event cases passed'); return
    kernel = c.WinDLL('kernel32', use_last_error=True)
    class Coord(c.Structure): _fields_ = [('x', c.c_short), ('y', c.c_short)]
    class Mouse(c.Structure): _fields_ = [('position', Coord), ('buttons', w.DWORD), ('control', w.DWORD), ('flags', w.DWORD)]
    class Event(c.Union): _fields_ = [('mouse', Mouse), ('padding', c.c_byte * 16)]
    class Record(c.Structure): _fields_ = [('kind', w.WORD), ('event', Event)]
    kernel.WriteConsoleInputW.argtypes = [w.HANDLE, c.POINTER(Record), w.DWORD, c.POINTER(w.DWORD)]
    kernel.GetConsoleMode.argtypes = [w.HANDLE, c.POINTER(w.DWORD)]
    cases = []
    with open('CONIN$', 'r+b', buffering=0) as cin, open('CONOUT$', 'wb', buffering=0) as cout:
        def mode():
            result = w.DWORD(); assert kernel.GetConsoleMode(msvcrt.get_osfhandle(cin.fileno()), c.byref(result)); return result.value
        def source(path, body):
            return (f'S" {path.as_posix()}" W/O CREATE-FILE THROW CONSTANT F REQUIRE-EXTENSION ALSO EXTENSION '
                    ': R EKEY-WAIT . . . ; ' + body)
        path = folder / 'timeout.txt'; before = mode()
        text = source(path, ': CASE-W 20 R ; \' CASE-W F OUTFILE-EXECUTE F CLOSE-FILE THROW BYE')
        result = subprocess.run([sigma, '-e', text], stdin=cin, stdout=cout, stderr=subprocess.PIPE, timeout=5)
        assert result.returncode == 0 and path.read_bytes() == b'0 0 0 ', (result, path.read_bytes())
        assert mode() == before; cases.append({'case': 'timeout', 'stdout_hex': path.read_bytes().hex()})
        path = folder / 'mouse.txt'; path.unlink(missing_ok=True); before = mode()
        text = source(path, ': CASE-W 8 TERM-MODE! DROP 0 EKEY-WAIT DROP 2DROP ." READY" F FLUSH-FILE THROW '
                      '100 MS EKEY? . EKEY-MOUSE . . . . 0 R EKEY-MOUSE . . . . ; '
                      '\' CASE-W F OUTFILE-EXECUTE F CLOSE-FILE THROW BYE')
        process = subprocess.Popen([sigma, '-e', text], stdin=cin, stdout=cout, stderr=subprocess.PIPE)
        try:
            until = time.monotonic() + 5
            while not path.exists() or b'READY' not in path.read_bytes():
                assert process.poll() is None and time.monotonic() < until
                time.sleep(.005)
            record = Record(); record.kind = 2; record.event.mouse = Mouse(Coord(2,3), 1, 0x10, 0)
            count = w.DWORD()
            assert kernel.WriteConsoleInputW(msvcrt.get_osfhandle(cin.fileno()), c.byref(record), 1, c.byref(count)) and count.value == 1
            _, errors = process.communicate(timeout=5)
            expected = b'READY-1 0 0 0 0 0 -1 2415919138 0 1 3 2 '
            assert process.returncode == 0 and path.read_bytes() == expected, (errors, path.read_bytes())
            assert mode() == before; cases.append({'case': 'native-mouse-modifier-peek', 'stdout_hex': path.read_bytes().hex()})
        finally:
            if process.poll() is None: process.kill()
            process.wait()
    for name, incoming, expected in [('pipe-esc-eof-byte-order', b'\x1b[', b'27 91 2147483681 '), ('pipe-utf8-eof-byte-order', b'\xe3\x81', b'227 65533 2147483681 ')]:
        result = subprocess.run([sigma, '-e', 'EKEY? DROP KEY . EKEY . EKEY . BYE'], input=incoming, capture_output=True)
        assert result.returncode == 0 and result.stdout == expected, (name, result)
        cases.append({'case': name, 'exit': result.returncode, 'stdout_hex': result.stdout.hex()})
    result = subprocess.run([sigma, '-e', 'REQUIRE-EXTENSION ALSO EXTENSION 0 EKEY-WAIT . . . BYE'], input=b'', capture_output=True)
    assert result.returncode == 0 and result.stdout == b'0 -1 2147483681 ', result
    cases.append({'case': 'pipe-eof', 'stdout_hex': result.stdout.hex()})
    (folder / 'result.json').write_text(json.dumps({'complete': True, 'cases': cases}, indent=2) + '\n')


if __name__ == '__main__': main()

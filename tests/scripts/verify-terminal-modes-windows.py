#!/usr/bin/env python3
"""Terminal-mode acceptance in an isolated hidden Windows console."""
import ctypes as c
from ctypes import wintypes as w
import json
import os
from pathlib import Path
import subprocess
import time
import sys


def main():
    if not __debug__:
        raise SystemExit("Run acceptance tests without Python -O: assertions are required")
    if os.name != 'nt':
        raise SystemExit('Windows required')
    import msvcrt
    sigma = str(Path(sys.argv[1]).resolve(strict=True))
    folder = Path('.work/terminal-modes/windows').resolve()
    folder.mkdir(parents=True, exist_ok=True)
    if '--child' not in sys.argv:
        startup = subprocess.STARTUPINFO()
        startup.dwFlags = subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 0
        with (folder / 'console.log').open('w') as log:
            result = subprocess.run([sys.executable, __file__, sigma, '--child'],
                                    stdout=log, stderr=log,
                                    creationflags=subprocess.CREATE_NEW_CONSOLE,
                                    startupinfo=startup, timeout=60)
        if result.returncode:
            print((folder / 'console.log').read_text(errors='replace'))
            raise SystemExit(result.returncode)
        report = json.loads((folder / 'result.json').read_text())
        assert report['complete']
        print(f'{len(report["cases"])} Windows terminal-mode cases passed')
        return

    kernel = c.WinDLL('kernel32', use_last_error=True)
    kernel.GetConsoleMode.argtypes = [w.HANDLE, c.POINTER(w.DWORD)]
    kernel.GetStdHandle.argtypes = [w.DWORD]
    kernel.GetStdHandle.restype = w.HANDLE
    kernel.GetConsoleCursorInfo.argtypes = [w.HANDLE, c.c_void_p]
    class Cursor(c.Structure):
        _fields_ = [('size', w.DWORD), ('visible', w.BOOL)]
    def input_mode():
        value = w.DWORD()
        assert kernel.GetConsoleMode(msvcrt.get_osfhandle(console_in.fileno()), c.byref(value))
        return value.value
    def cursor_visible():
        value = Cursor()
        assert kernel.GetConsoleCursorInfo(msvcrt.get_osfhandle(console_out.fileno()), c.byref(value))
        return bool(value.visible)

    records = []
    with open('CONIN$', 'r+b', buffering=0) as console_in, open('CONOUT$', 'wb', buffering=0) as console_out:
        def run(name, body, expected, status=0):
            path = folder / (name + '.txt')
            before = input_mode()
            # The VM output goes to a file; presentation must still go to CONOUT$.
            source = (f'S" {path.as_posix()}" W/O CREATE-FILE THROW CONSTANT F '
                      'REQUIRE-EXTENSION ALSO EXTENSION '
                      f': CASE-W {body} ; \' CASE-W F OUTFILE-EXECUTE F CLOSE-FILE THROW BYE')
            result = subprocess.run([sigma, '-e', source], stdin=console_in,
                                    stdout=console_out, stderr=subprocess.PIPE, timeout=10)
            assert result.returncode == status, (name, result.returncode, result.stderr)
            text = path.read_bytes()
            assert text == expected, (name, text, expected)
            assert input_mode() == before, (name, 'input flags not restored')
            assert cursor_visible(), (name, 'cursor not restored')
            records.append({'case': name, 'stdout_hex': text.hex(), 'input_mode_restored': True, 'cursor_restored': True})

        run('before-raw', '5 TERM-MODE! . TERM-MODE@ .', b'0 5 ')
        run('windows-paste-filtered', '2 TERM-MODE! . TERM-MODE@ .', b'0 0 ')
        run('raw-mouse-records', '15 TERM-MODE! . EKEY? DROP TERM-MODE@ .', b'0 13 ')
        run('explicit-reset', '5 TERM-MODE! . 0 TERM-MODE! . TERM-MODE@ .', b'0 0 0 ')
        run('invalid-mask', '-1 TERM-MODE! . 16 TERM-MODE! . TERM-MODE@ .', b'-24 -24 0 ')
        run('system-handoff', '5 TERM-MODE! DROP S" rem" SYSTEM TERM-MODE@ .', b'5 ')
        # Throw is caught inside the VM, so it must retain the accepted request.
        path = folder / 'caught.txt'
        source = (f'S" {path.as_posix()}" W/O CREATE-FILE THROW CONSTANT F '
                  'REQUIRE-EXTENSION ALSO EXTENSION : FAIL-W -123 THROW ; '
                  ': CASE-W 5 TERM-MODE! DROP [\'] FAIL-W CATCH . TERM-MODE@ . ; '
                  '\' CASE-W F OUTFILE-EXECUTE F CLOSE-FILE THROW BYE')
        before = input_mode()
        result = subprocess.run([sigma, '-e', source], stdin=console_in, stdout=console_out,
                                stderr=subprocess.PIPE, timeout=10)
        assert result.returncode == 0 and path.read_bytes() == b'-123 5 ', (result, path.read_bytes())
        assert input_mode() == before and cursor_visible()
        records.append({'case': 'caught-throw', 'stdout_hex': path.read_bytes().hex(), 'input_mode_restored': True, 'cursor_restored': True})
    # A handled Ctrl+C must not permanently mark ReadConsoleW input as EOF.
    handler_type = c.WINFUNCTYPE(w.BOOL, w.DWORD)
    keep_parent_alive = handler_type(lambda code: True)
    kernel.SetConsoleCtrlHandler.argtypes = [handler_type, w.BOOL]
    assert kernel.SetConsoleCtrlHandler(keep_parent_alive, True)
    # The helper can inherit an ignore-Ctrl+C flag from its launcher. Clear it
    # before spawning Sigma; callback registrations themselves are not inherited.
    assert kernel.SetConsoleCtrlHandler(handler_type(), False)
    kernel.GenerateConsoleCtrlEvent.argtypes = [w.DWORD, w.DWORD]
    class Key(c.Structure):
        _fields_ = [('down', w.BOOL), ('repeat', w.WORD), ('vk', w.WORD),
                    ('scan', w.WORD), ('char', w.WCHAR), ('control', w.DWORD)]
    class Event(c.Union):
        _fields_ = [('key', Key), ('padding', c.c_byte * 16)]
    class Record(c.Structure):
        _fields_ = [('kind', w.WORD), ('event', Event)]
    kernel.WriteConsoleInputW.argtypes = [w.HANDLE, c.POINTER(Record), w.DWORD, c.POINTER(w.DWORD)]
    def await_text(path, token, proc):
        until = time.monotonic() + 5
        while time.monotonic() < until:
            text = path.read_bytes() if path.exists() else b''
            if token in text:
                return
            assert proc.poll() is None, (proc.returncode, text)
            time.sleep(.02)
        raise AssertionError(('timeout', token, text))
    try:
        with open('CONIN$', 'r+b', buffering=0) as console_in, open('CONOUT$', 'wb', buffering=0) as console_out:
            path = folder / 'interrupt-recovery.txt'
            path.unlink(missing_ok=True)
            source = (f'S" {path.as_posix()}" W/O CREATE-FILE THROW CONSTANT F '
                      'REQUIRE-EXTENSION ALSO EXTENSION : FIRST-W KEY DROP ; '
                      ': CASE-W 5 TERM-MODE! DROP ." READY" F FLUSH-FILE THROW '
                      '[\'] FIRST-W CATCH . STDIN FILE-EOF? . ." NEXT" F FLUSH-FILE THROW KEY . ; '
                      '\' CASE-W F OUTFILE-EXECUTE F CLOSE-FILE THROW BYE')
            before = input_mode()
            proc = subprocess.Popen([sigma, '-e', source], stdin=console_in, stdout=console_out, stderr=subprocess.PIPE)
            try:
                await_text(path, b'READY', proc)
                time.sleep(.1)
                assert kernel.GenerateConsoleCtrlEvent(0, 0)
                await_text(path, b'NEXT', proc)
                assert b'-28 0 ' in path.read_bytes(), path.read_bytes()
                events = (Record * 2)()
                for i, (vk, char) in enumerate(((81, 'Q'), (13, '\r'))):
                    events[i].kind = 1
                    events[i].event.key = Key(1, 1, vk, 0, char, 0)
                written = w.DWORD()
                assert kernel.WriteConsoleInputW(msvcrt.get_osfhandle(console_in.fileno()), events, 2, c.byref(written)) and written.value == 2
                _, errors = proc.communicate(timeout=5)
                assert proc.returncode == 0, errors
                assert path.read_bytes() == b'READY-28 0 NEXT81 ', path.read_bytes()
                assert input_mode() == before and cursor_visible()
                records.append({'case': 'cooked-interrupt-recovery', 'stdout_hex': path.read_bytes().hex(), 'input_mode_restored': True, 'cursor_restored': True})
            finally:
                if proc.poll() is None: proc.kill()
                proc.wait()
    finally:
        kernel.SetConsoleCtrlHandler(keep_parent_alive, False)
    (folder / 'result.json').write_text(json.dumps({'complete': True, 'cases': records}, indent=2) + '\n')


if __name__ == '__main__':
    main()

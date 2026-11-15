#!/usr/bin/env python3
"""Inject Win32 console records into an isolated hidden console, not physical keys."""
import ctypes as c
from ctypes import wintypes as w
import json
import msvcrt
import os
from pathlib import Path
import subprocess
import sys
import time

if os.name != 'nt':
    raise SystemExit('Windows required')
sigma = str(Path(sys.argv[1] if len(sys.argv) > 1 else 'zig-out/bin/sigma.exe').resolve())
if '--child' not in sys.argv:
    Path('.work/windows-console.json').unlink(missing_ok=True)
    startup = subprocess.STARTUPINFO()
    startup.dwFlags = subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    with open('.work/windows-console.log', 'w') as log:
        r = subprocess.run([sys.executable, __file__, sigma, '--child'], stdout=log, stderr=log,
                           creationflags=subprocess.CREATE_NEW_CONSOLE, startupinfo=startup, timeout=60)
    raise SystemExit(r.returncode)

class Key(c.Structure):
    _fields_ = [('down', w.BOOL), ('repeat', w.WORD), ('vk', w.WORD),
                ('scan', w.WORD), ('char', w.WCHAR), ('control', w.DWORD)]

class Event(c.Union):
    _fields_ = [('key', Key), ('size', c.c_short * 2), ('padding', c.c_byte * 16)]

class Record(c.Structure):
    _fields_ = [('kind', w.WORD), ('event', Event)]

kernel = c.WinDLL('kernel32', use_last_error=True)
kernel.WriteConsoleInputW.argtypes = [w.HANDLE, c.POINTER(Record), w.DWORD, c.POINTER(w.DWORD)]
kernel.FlushConsoleInputBuffer.argtypes = [w.HANDLE]
kernel.GetConsoleMode.argtypes = [w.HANDLE, c.POINTER(w.DWORD)]
def mode(handle):
    value = w.DWORD()
    assert kernel.GetConsoleMode(handle, c.byref(value)), c.get_last_error()
    return value.value

passed = []
with open('CONIN$', 'rb', buffering=0) as console:
    handle = msvcrt.get_osfhandle(console.fileno())
    class Coord(c.Structure):
        _fields_ = [('x', c.c_short), ('y', c.c_short)]
    class Rect(c.Structure):
        _fields_ = [('left', c.c_short), ('top', c.c_short), ('right', c.c_short), ('bottom', c.c_short)]
    class Screen(c.Structure):
        _fields_ = [('size', Coord), ('cursor', Coord), ('attributes', w.WORD), ('window', Rect), ('maximum', Coord)]
    kernel.GetConsoleScreenBufferInfo.argtypes = [w.HANDLE, c.POINTER(Screen)]
    kernel.SetConsoleCursorPosition.argtypes = [w.HANDLE, Coord]
    kernel.SetConsoleMode.argtypes = [w.HANDLE, w.DWORD]
    with open('CONOUT$', 'wb', buffering=0) as output:
        output_handle = msvcrt.get_osfhandle(output.fileno())
        info = Screen()
        assert kernel.GetConsoleScreenBufferInfo(output_handle, c.byref(info))
        columns = info.window.right - info.window.left + 1
        lines = info.window.bottom - info.window.top + 1
        result = Path('.work/windows-form.txt').resolve()
        code = f'FORM S" {result}" W/O CREATE-FILE THROW CONSTANT F : PAIR . . ; \' PAIR F OUTFILE-EXECUTE F CLOSE-FILE THROW BYE'
        r = subprocess.run([sigma, '-e', code], stdin=console, stdout=output, stderr=subprocess.PIPE, timeout=10)
        assert r.returncode == 0 and result.read_bytes() == f'{columns} {lines} '.encode(), (r.returncode, result.read_bytes(), r.stderr)
        passed.append('form-console-geometry')
        old_mode = mode(output_handle)
        try:
            assert kernel.SetConsoleMode(output_handle, old_mode | 4)
            assert kernel.SetConsoleCursorPosition(output_handle, Coord(5, 5))
            r = subprocess.run([sigma, '-e', '2 -3 AT-DELTAXY BYE'], stdin=console, stdout=output, stderr=subprocess.PIPE, timeout=10)
            assert kernel.GetConsoleScreenBufferInfo(output_handle, c.byref(info))
            assert r.returncode == 0 and (info.cursor.x, info.cursor.y) == (7, 2), (r.returncode, info.cursor.x, info.cursor.y, r.stderr)
            passed.append('relative-console-cursor')
        finally:
            assert kernel.SetConsoleMode(output_handle, old_mode)
    for name, body, keys, expected in [
        ('unicode', 'EKEY . BYE', [(0, '日', 0)], b'26085 '),
        ('up', 'EKEY K-UP = . BYE', [(0x26, '\0', 0)], b'-1 '),
        ('shift-up', 'EKEY K-UP K-SHIFT-MASK OR = . BYE', [(0x26, '\0', 16)], b'-1 '),
        ('key-ekey', 'KEY . EKEY . BYE', [(65, 'A', 0), (0, 'é', 0), (13, '\r', 0)], b'65 233 '),
        ('accept', 'PAD 16 ACCEPT PAD SWAP TYPE BYE', [(65, 'a', 0), (66, 'b', 0), (13, '\r', 0)], b'ab'),
        ('accept-native-edit', 'PAD 128 ACCEPT PAD SWAP TYPE BYE', [(65, 'a', 0), (67, 'c', 0), (0x25, '\0', 0), (66, 'b', 0), (0x23, '\0', 0), (0, '!', 0), (0x24, '\0', 0), (0x2E, '\0', 0), (88, 'x', 0), (0x23, '\0', 0), (8, '\b', 0), (13, '\r', 0)], b'xbc'),
        ('accept-unicode-edit', 'PAD 128 ACCEPT PAD SWAP TYPE BYE', [(0, '日', 0), (0, '\ud83d', 0), (0, '\ude00', 0), (0, '本', 0), (0x24, '\0', 0), (0x2E, '\0', 0), (0x23, '\0', 0), (8, '\b', 0), (13, '\r', 0)], '😀'.encode()),
        ('accept-history-up', ': READ-LINE-W PAD 128 ACCEPT PAD SWAP TYPE ; READ-LINE-W ." NEXT!" READ-LINE-W BYE', [(65, 'a', 0), (66, 'b', 0), (13, '\r', 0), (0x26, '\0', 0), (13, '\r', 0)], b'ab'),
        ('accept-history-down', ': READ-LINE-W PAD 128 ACCEPT PAD SWAP TYPE ; READ-LINE-W ." NEXT!" READ-LINE-W ." NEXT!" READ-LINE-W BYE', [(65, 'a', 0), (66, 'b', 0), (13, '\r', 0), (67, 'c', 0), (68, 'd', 0), (13, '\r', 0), (0x26, '\0', 0), (0x26, '\0', 0), (0x28, '\0', 0), (13, '\r', 0)], b'cd'),
        ('ctrl-c', "' EKEY CATCH . BYE", [(67, '\x03', 8)], b'-28 '),
        ('resize-key-preserved', 'EKEY? DROP ." ARMED" 200 MS EKEY? . EKEY K-WINCH = . KEY . BYE', [(-1, '\0', 0), (65, 'A', 0), (13, '\r', 0)], b'-1 -1 65 '),
        ('key-ior', 'KEY-IOR . BYE', [(65, 'A', 0)], b'65 '),
        ('key-ior-interrupt', "' KEY-IOR CATCH . BYE", [(67, '\x03', 8)], b'-28 '),
        ('file-key-shared', 'STDIN KEY-FILE . STDIN KEY?-FILE . KEY . BYE', [(65, 'A', 0), (66, 'B', 0), (13, '\r', 0)], b'65 -1 66 '),
        ('shift-tab', 'EKEY K-TAB K-SHIFT-MASK OR = . BYE', [(9, '\t', 16)], b'-1 '),
        ('ctrl-enter', 'EKEY K-ENTER K-CTRL-MASK OR = . BYE', [(13, '\r', 8)], b'-1 '),
        ('mute', 'EKEY K-MUTE = . BYE', [(0xAD, '\0', 0)], b'-1 '),
        ('volume-up', 'EKEY K-VOLUP = . BYE', [(0xAF, '\0', 0)], b'-1 '),
        ('volume-down', 'EKEY K-VOLDOWN = . BYE', [(0xAE, '\0', 0)], b'-1 '),
        ('pause', 'EKEY K-PAUSE = . BYE', [(0x13, '\0', 0)], b'-1 '),
        ('select', 'EKEY K-SEL = . BYE', [(0x29, '\0', 0)], b'-1 '),
        ('graphics-standard-order', 'K-UP CONSTANT STD-UP REQUIRE-GRAPHICS ALSO GRAPHICS ." ARMED" EKEY STD-UP = . K-UP STD-UP <> . BYE', [(0x26, '\0', 0)], b'-1 -1 '),
        ('graphics-inkey-ekey', 'K-DOWN CONSTANT STD-DOWN REQUIRE-GRAPHICS ALSO GRAPHICS : WAIT-GKEY BEGIN INKEY DUP -1 = WHILE DROP 1 MS REPEAT ; ." ARMED" WAIT-GKEY K-UP = . ." NEXT!" EKEY STD-DOWN = . BYE', [(0x26, '\0', 0), (0x28, '\0', 0)], b'-1 '),
        ('ns-canonical-input', '100000000. NS EKEY . EKEY . BYE', [(65, 'A', 0), (66, 'B', 0)], b'65 66 '),
        ('ns-raw-input', 'EKEY? DROP 100000000. NS EKEY . EKEY . BYE', [(65, 'A', 0), (66, 'B', 0)], b'65 66 '),
        ('system-input', 'S" exit /b 0" SYSTEM ." ARMED" EKEY . BYE', [(65, 'A', 0)], b'65 '),
        ('system-nonzero-input', 'S" exit /b 7" SYSTEM ." ARMED" EKEY . $? . BYE', [(65, 'A', 0)], b'65 7 '),
        ('mixed-input-system', 'REQUIRE-GRAPHICS ALSO GRAPHICS : WAIT-GKEY BEGIN INKEY DUP -1 = WHILE DROP 1 MS REPEAT ; ." ARMED" EKEY . ." NEXT!" KEY . ." NEXT!" PAD 16 ACCEPT PAD SWAP TYPE ." NEXT!" S" exit /b 0" SYSTEM ." NEXT!" WAIT-GKEY K-UP = . BYE', [(65, 'A', 0), (66, 'B', 0), (13, '\r', 0), (67, 'c', 0), (68, 'd', 0), (13, '\r', 0), (0x26, '\0', 0)], b'-1 '),
        ('error-mode-restored', 'EKEY DROP S" missing-for-console.fs" INCLUDED', [(65, 'A', 0)], b'NO SUCH FILE OR DIRECTORY !\r\n'),
        ('supplementary-character', 'EKEY . BYE', [(0, '\ud83d', 0), (0, '\ude00', 0)], b'128512 '),
    ]:
        assert kernel.FlushConsoleInputBuffer(handle)
        original_mode = mode(handle)
        with subprocess.Popen([sigma, '-e', '." READY" ' + body], stdin=console,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE) as child:
            try:
                # The VM flushes before waiting for console input.
                assert child.stdout.read(5) == b'READY', name
                if name in ['graphics-standard-order', 'graphics-inkey-ekey', 'mixed-input-system', 'system-input', 'system-nonzero-input', 'resize-key-preserved']:
                    assert child.stdout.read(5) == b'ARMED', name
                if not name.startswith('accept') and name not in ['key-ekey', 'ns-canonical-input']:
                    deadline = time.monotonic() + 5
                    while mode(handle) & 6:
                        assert child.poll() is None and time.monotonic() < deadline, (name, 'raw mode not entered')
                        time.sleep(0.001)
                for key_index, (vk, char, flags) in enumerate(keys):
                    record = Record(4, Event(size=(c.c_short * 2)(100, 40))) if vk == -1 else Record(1, Event(key=Key(1, 1, vk, 0, char, flags)))
                    written = w.DWORD()
                    assert kernel.WriteConsoleInputW(handle, c.byref(record), 1, c.byref(written)), c.get_last_error()
                    if name == 'graphics-inkey-ekey' and key_index == 0:
                        assert child.stdout.read(8) == b'-1 NEXT!', name
                    if name.startswith('accept-history') and key_index == 2:
                        assert child.stdout.read(7) == b'abNEXT!', name
                    if name == 'accept-history-down' and key_index == 5:
                        assert child.stdout.read(7) == b'cdNEXT!', name
                    if name == 'mixed-input-system':
                        if key_index == 0:
                            assert child.stdout.read(8) == b'65 NEXT!', name
                        elif key_index == 2:
                            assert child.stdout.read(8) == b'66 NEXT!', name
                        elif key_index == 5:
                            assert child.stdout.read(12) == b'cdNEXT!NEXT!', name
                out, err = child.communicate(timeout=5)
                # ACCEPT may echo console input even when stdout is redirected.
                assert child.returncode == (1 if name == 'error-mode-restored' else 0) and out.endswith(expected), (name, child.returncode, out, err)
                assert mode(handle) == original_mode, (name, 'console mode not restored', mode(handle), original_mode)
                passed.append(name)
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait()
    # A real console control event exercises NS's scoped OS handler rather
    # than treating character 3 as ordinary input or as an injected key.
    handler_type = c.WINFUNCTYPE(w.BOOL, w.DWORD)
    protect_helper = handler_type(lambda event: 1)
    kernel.SetConsoleCtrlHandler.argtypes = [handler_type, w.BOOL]
    kernel.GenerateConsoleCtrlEvent.argtypes = [w.DWORD, w.DWORD]
    assert kernel.SetConsoleCtrlHandler(protect_helper, 1)
    try:
        for duration in [2000000000, 18446744073709551739]:
            for raw in [False, True]:
                assert kernel.FlushConsoleInputBuffer(handle)
                original_mode = mode(handle)
                code = ('EKEY? DROP ' if raw else '') + f': W {duration}. NS ; ." READY" \' W CATCH . 1000000. NS EKEY . BYE'
                with subprocess.Popen([sigma, '-e', code], stdin=console, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as child:
                    try:
                        assert child.stdout.read(5) == b'READY'
                        time.sleep(0.05)
                        record = Record(1, Event(key=Key(1, 1, 65, 0, 'A', 0)))
                        written = w.DWORD()
                        assert kernel.WriteConsoleInputW(handle, c.byref(record), 1, c.byref(written))
                        assert kernel.GenerateConsoleCtrlEvent(0, 0)
                        out, err = child.communicate(timeout=5)
                        assert child.returncode == 0 and out == b'-28 65 ', (duration, raw, child.returncode, out, err)
                        assert mode(handle) == original_mode, (duration, raw, mode(handle), original_mode)
                        passed.append(f'ns-control-event-{duration}-raw-{raw}')
                    finally:
                        if child.poll() is None:
                            child.kill()
                            child.wait()
    finally:
        assert kernel.SetConsoleCtrlHandler(protect_helper, 0)
Path('.work/windows-console.json').write_text(json.dumps({'injected_console_records': passed}, indent=2) + '\n')

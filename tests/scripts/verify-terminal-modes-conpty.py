#!/usr/bin/env python3
"""Exercise cooked Ctrl+C through a private ConPTY input stream (not physical keys)."""
import ctypes as c
from ctypes import wintypes as w
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time


def main():
    if not __debug__:
        raise SystemExit("Run acceptance tests without Python -O: assertions are required")
    if os.name != 'nt':
        raise SystemExit('Windows required')
    kernel = c.WinDLL('kernel32', use_last_error=True)
    class Coord(c.Structure):
        _fields_ = [('x', c.c_short), ('y', c.c_short)]
    class Startup(c.Structure):
        _fields_ = [('cb', w.DWORD), ('reserved', w.LPWSTR), ('desktop', w.LPWSTR), ('title', w.LPWSTR),
                    ('x', w.DWORD), ('y', w.DWORD), ('width', w.DWORD), ('height', w.DWORD),
                    ('chars_x', w.DWORD), ('chars_y', w.DWORD), ('fill', w.DWORD), ('flags', w.DWORD),
                    ('show', w.WORD), ('reserved_size', w.WORD), ('reserved_bytes', c.c_void_p),
                    ('stdin', w.HANDLE), ('stdout', w.HANDLE), ('stderr', w.HANDLE)]
    class StartupEx(c.Structure):
        _fields_ = [('startup', Startup), ('attributes', c.c_void_p)]
    class Process(c.Structure):
        _fields_ = [('process', w.HANDLE), ('thread', w.HANDLE), ('pid', w.DWORD), ('tid', w.DWORD)]
    kernel.CreatePipe.argtypes = [c.POINTER(w.HANDLE), c.POINTER(w.HANDLE), c.c_void_p, w.DWORD]
    kernel.CreatePseudoConsole.argtypes = [Coord, w.HANDLE, w.HANDLE, w.DWORD, c.POINTER(w.HANDLE)]
    kernel.ClosePseudoConsole.argtypes = [w.HANDLE]
    kernel.CloseHandle.argtypes = [w.HANDLE]
    kernel.InitializeProcThreadAttributeList.argtypes = [c.c_void_p, w.DWORD, w.DWORD, c.POINTER(c.c_size_t)]
    kernel.UpdateProcThreadAttribute.argtypes = [c.c_void_p, w.DWORD, c.c_size_t, c.c_void_p, c.c_size_t, c.c_void_p, c.c_void_p]
    kernel.DeleteProcThreadAttributeList.argtypes = [c.c_void_p]
    kernel.CreateProcessW.argtypes = [w.LPCWSTR, w.LPWSTR, c.c_void_p, c.c_void_p, w.BOOL, w.DWORD,
                                     c.c_void_p, w.LPCWSTR, c.POINTER(StartupEx), c.POINTER(Process)]
    kernel.ReadFile.argtypes = [w.HANDLE, c.c_void_p, w.DWORD, c.POINTER(w.DWORD), c.c_void_p]
    kernel.WriteFile.argtypes = [w.HANDLE, c.c_void_p, w.DWORD, c.POINTER(w.DWORD), c.c_void_p]
    kernel.WaitForSingleObject.argtypes = [w.HANDLE, w.DWORD]
    kernel.GetExitCodeProcess.argtypes = [w.HANDLE, c.POINTER(w.DWORD)]
    kernel.TerminateProcess.argtypes = [w.HANDLE, w.UINT]
    kernel.SetConsoleCtrlHandler.argtypes = [c.c_void_p, w.BOOL]
    kernel.SetConsoleCtrlHandler(None, False)
    handles = []
    pc = w.HANDLE()
    process = Process()
    attributes = None
    output = bytearray()
    try:
        read_in, write_in, read_out, write_out = (w.HANDLE() for _ in range(4))
        assert kernel.CreatePipe(c.byref(read_in), c.byref(write_in), None, 0)
        handles.extend([read_in, write_in])
        assert kernel.CreatePipe(c.byref(read_out), c.byref(write_out), None, 0)
        handles.extend([read_out, write_out])
        assert kernel.CreatePseudoConsole(Coord(80, 24), read_in, write_out, 0, c.byref(pc)) == 0
        size = c.c_size_t()
        kernel.InitializeProcThreadAttributeList(None, 1, 0, c.byref(size))
        attributes = c.create_string_buffer(size.value)
        assert kernel.InitializeProcThreadAttributeList(attributes, 1, 0, c.byref(size))
        assert kernel.UpdateProcThreadAttribute(attributes, 0, 0x20016, pc, c.sizeof(pc), None, None)
        startup = StartupEx()
        startup.startup.cb = c.sizeof(startup)
        startup.attributes = c.cast(attributes, c.c_void_p)
        source = ('REQUIRE-EXTENSION ALSO EXTENSION : FIRST-W KEY DROP ; '
                  '5 TERM-MODE! DROP ." READY" \' FIRST-W CATCH . STDIN FILE-EOF? . ." NEXT" KEY . BYE')
        command = c.create_unicode_buffer(subprocess.list2cmdline([str(Path(sys.argv[1]).resolve(strict=True)), '-e', source]))
        # Do not copy the test launcher's redirected standard handles into the
        # client. The child gets its standard handles from the pseudo console.
        kernel.GetStdHandle.argtypes = [w.DWORD]
        kernel.GetStdHandle.restype = w.HANDLE
        kernel.SetStdHandle.argtypes = [w.DWORD, w.HANDLE]
        std_ids = [(-10) & 0xffffffff, (-11) & 0xffffffff, (-12) & 0xffffffff]
        saved_handles = [kernel.GetStdHandle(i) for i in std_ids]
        try:
            for i in std_ids:
                assert kernel.SetStdHandle(i, None)
            assert kernel.CreateProcessW(None, command, None, None, False, 0x80000, None, None,
                                         c.byref(startup), c.byref(process)), c.get_last_error()
        finally:
            for i, h in zip(std_ids, saved_handles):
                kernel.SetStdHandle(i, h)
        def drain():
            buffer = c.create_string_buffer(4096)
            count = w.DWORD()
            while kernel.ReadFile(read_out, buffer, len(buffer), c.byref(count), None) and count.value:
                output.extend(buffer.raw[:count.value])
        thread = threading.Thread(target=drain, daemon=True)
        thread.start()
        def await_text(token):
            until = time.monotonic() + 8
            while token not in output and time.monotonic() < until:
                time.sleep(.01)
            assert token in output, (token, bytes(output))
        def send(data):
            count = w.DWORD()
            assert kernel.WriteFile(write_in, data, len(data), c.byref(count), None) and count.value == len(data)
        await_text(b'READY')
        time.sleep(.1)
        send(b'\x03')
        await_text(b'NEXT')
        assert b'-28 0 ' in output, bytes(output)
        send(b'Q\r')
        assert kernel.WaitForSingleObject(process.process, 8000) == 0, bytes(output)
        code = w.DWORD()
        assert kernel.GetExitCodeProcess(process.process, c.byref(code)) and code.value == 0, (code.value, bytes(output))
        # Drain the final output without closing the pseudo console too early.
        until = time.monotonic() + 2
        while b'81 ' not in output and time.monotonic() < until:
            time.sleep(.01)
        assert b'81 ' in output, bytes(output)
        folder = Path('.work/terminal-modes/windows')
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'conpty.json').write_text(json.dumps({'complete': True, 'case': 'cooked-ctrl-c-next-key',
                                                      'exit': code.value, 'stdout_hex': output.hex()}, indent=2) + '\n')
        print('ConPTY cooked Ctrl+C and next KEY passed')
    finally:
        if process.process:
            if kernel.WaitForSingleObject(process.process, 0) != 0:
                kernel.TerminateProcess(process.process, 1)
                kernel.WaitForSingleObject(process.process, 3000)
            kernel.CloseHandle(process.thread)
            kernel.CloseHandle(process.process)
        if attributes is not None:
            kernel.DeleteProcThreadAttributeList(attributes)
        if pc:
            kernel.ClosePseudoConsole(pc)
        for handle in handles:
            kernel.CloseHandle(handle)


if __name__ == '__main__':
    main()

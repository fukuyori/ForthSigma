#!/usr/bin/env python3
"""Check per-call native path ownership and OS handle/fd cleanup."""
import argparse
import ctypes
import errno
import json
import os
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def run(library):
    api = ctypes.CDLL(str(library.resolve()))
    api.sigma_fs_realpath.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_size_t)]
    api.sigma_fs_info.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_uint64), ctypes.POINTER(ctypes.c_int64), ctypes.POINTER(ctypes.c_uint32)]
    api.sigma_fs_free.argtypes = [ctypes.c_void_p]
    guard_checks = 0
    if os.name == 'nt':
        api.sigma_fs_test_opens.restype = ctypes.c_uint
        for name in [b'/??/pipe/sigma-must-not-connect', b'COM1', b'NUL', b'CONIN$', b'\\\\.\\pipe\\sigma-must-not-connect']:
            before_open = api.sigma_fs_test_opens()
            pointer = ctypes.c_void_p()
            length = ctypes.c_size_t()
            assert api.sigma_fs_realpath(name, ctypes.byref(pointer), ctypes.byref(length)) == errno.EINVAL
            size, seconds, ns = ctypes.c_uint64(), ctypes.c_int64(), ctypes.c_uint32()
            assert api.sigma_fs_info(name, ctypes.byref(size), ctypes.byref(seconds), ctypes.byref(ns)) == errno.EINVAL
            assert api.sigma_fs_test_opens() == before_open
            guard_checks += 2
    if os.name == 'nt':
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.GetCurrentProcess.restype = ctypes.c_void_p
        kernel.GetProcessHandleCount.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
        def count():
            result = ctypes.c_ulong()
            assert kernel.GetProcessHandleCount(kernel.GetCurrentProcess(), ctypes.byref(result))
            return result.value
    else:
        def count():
            directory = '/proc/self/fd' if Path('/proc/self/fd').exists() else '/dev/fd'
            return len(os.listdir(directory))
    work = ROOT / '.work/646'
    work.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='native-', dir=work) as temporary:
        folder = Path(temporary)
        file = folder / 'native-確認.txt'
        file.write_bytes(b'hello')
        encoded = str(file).encode()
        missing = str(folder / 'missing').encode()
        def check():
            pointer = ctypes.c_void_p()
            length = ctypes.c_size_t()
            opening_before = api.sigma_fs_test_opens() if os.name == 'nt' else 0
            assert api.sigma_fs_realpath(encoded, ctypes.byref(pointer), ctypes.byref(length)) == 0
            if os.name == 'nt':
                assert api.sigma_fs_test_opens() == opening_before + 1
            try:
                resolved = os.fsdecode(ctypes.string_at(pointer, length.value))
                assert os.path.samefile(resolved, file)
            finally:
                api.sigma_fs_free(pointer)
            size = ctypes.c_uint64()
            seconds = ctypes.c_int64()
            ns = ctypes.c_uint32()
            assert api.sigma_fs_info(encoded, ctypes.byref(size), ctypes.byref(seconds), ctypes.byref(ns)) == 0
            assert size.value == 5 and 0 <= ns.value < 1000000000
            assert api.sigma_fs_info(str(folder).encode(), ctypes.byref(size), ctypes.byref(seconds), ctypes.byref(ns)) == errno.EINVAL
            pointer = ctypes.c_void_p()
            assert api.sigma_fs_realpath(missing, ctypes.byref(pointer), ctypes.byref(length)) == errno.ENOENT
            assert pointer.value is None
        for _ in range(20):
            check()
        before = count()
        for _ in range(1000):
            check()
        after = count()
        assert before == after, (before, after)
        return {'platform': os.name, 'iterations': 1000, 'resource_count_before': before, 'resource_count_after': after, 'device_calls_rejected_before_open': guard_checks}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = run(args.library)
    if args.output:
        args.output.write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result))

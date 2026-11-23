#!/usr/bin/env python3
"""Check real unavailable-DwmFlush behavior without replacing the function.

Returns 2 (not applicable) when the system DwmFlush works. Missing DLL/export or
repeated real HRESULT errors are required before Sigma's false results can pass.
No changes to the desktop, services, display settings, or production executable.
"""
import argparse
import ctypes
from ctypes import wintypes
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma.exe')
parser.add_argument('--output', type=Path)
parser.add_argument('--expected-sha256', help='SHA-256 of the verified, unmodified Sigma build')
parser.add_argument('--probe-child', action='store_true', help=argparse.SUPPRESS)
args = parser.parse_args()


def native_probe():
    # Resolve only the system library, as Sigma does. No injected library/provider.
    result = dict(provider='system32/dwmapi.dll', calls=[])
    try:
        dwm = ctypes.WinDLL('dwmapi.dll', winmode=0x800)
    except OSError as error:
        result.update(kind='library-unavailable' if error.winerror == 126 else 'library-load-error',
                      winerror=error.winerror)
        return result
    kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel32.GetModuleFileNameW.argtypes = [wintypes.HMODULE, wintypes.LPWSTR, wintypes.DWORD]
    kernel32.GetSystemDirectoryW.argtypes = [wintypes.LPWSTR, wintypes.UINT]
    module_name, system_directory = ctypes.create_unicode_buffer(32768), ctypes.create_unicode_buffer(32768)
    module_length = kernel32.GetModuleFileNameW(dwm._handle, module_name, len(module_name))
    system_length = kernel32.GetSystemDirectoryW(system_directory, len(system_directory))
    if not 0 < module_length < len(module_name) or not 0 < system_length < len(system_directory):
        raise ctypes.WinError(ctypes.get_last_error())
    expected_library = Path(system_directory.value) / 'dwmapi.dll'
    if not expected_library.samefile(module_name.value):
        raise AssertionError(('Unexpected DWM provider', module_name.value, str(expected_library)))
    result.update(module_path=module_name.value, expected_system_module=str(expected_library),
                  system_module_identity_matched=True)
    try:
        flush = dwm.DwmFlush
    except AttributeError:
        result['kind'] = 'function-unavailable'
        return result
    flush.argtypes = []
    flush.restype = ctypes.c_long
    try:
        composition = dwm.DwmIsCompositionEnabled
        composition.argtypes = [ctypes.POINTER(wintypes.BOOL)]
        composition.restype = ctypes.c_long
        enabled = wintypes.BOOL()
        result['composition_hresult'] = composition(ctypes.byref(enabled))
        result['composition_enabled'] = bool(enabled.value)
    except AttributeError:
        result['composition_query_unavailable'] = True
    for _ in range(3):
        started = time.perf_counter()
        value = flush()
        result['calls'].append(dict(hresult=value, hresult_hex='0x%08x' % (value & 0xffffffff),
                                    elapsed_ms=(time.perf_counter() - started) * 1000))
    result['kind'] = 'hresult-failure' if all(row['hresult'] < 0 for row in result['calls']) else 'available'
    return result


if args.probe_child:
    if sys.stdin.buffer.readline() != b'\n':
        raise SystemExit('Missing private job gate')
    print(json.dumps(native_probe()), flush=True)
    raise SystemExit(0)

if args.output is None:
    parser.error('--output is required')
if args.output.exists():
    parser.error('Use a new output path; previous environment evidence is preserved')
if args.expected_sha256 is None or not re.fullmatch('[0-9a-fA-F]{64}', args.expected_sha256):
    parser.error('--expected-sha256 must identify the verified Sigma build')
from windows_display_test_support import (
    assert_empty_job, assign_job, binary_identity, create_job, kernel, run,
)
report = dict(task=1276, status='incomplete', started_at=datetime.now(timezone.utc).isoformat(),
              platform=platform.platform(), windows_version=list(sys.getwindowsversion()[:3]),
              binary=binary_identity(args.sigma), function_injection=False,
              expected_binary_sha256=args.expected_sha256.lower(),
              python_flags=dict(isolated=sys.flags.isolated, ignore_environment=sys.flags.ignore_environment,
                                no_site=sys.flags.no_site, no_user_site=sys.flags.no_user_site),
              probe_python_options=['-I', '-S'],
              source_sha256=__import__('hashlib').sha256(Path(__file__).read_bytes()).hexdigest())
job, child = None, None
try:
    if report['binary']['sha256'] != report['expected_binary_sha256']:
        raise AssertionError('Sigma differs from the verified build')
    job = create_job()
    child = subprocess.Popen([sys.executable, '-I', '-S', str(Path(__file__).resolve()), '--probe-child'],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assign_job(job, child)
    try:
        stdout, stderr = child.communicate(input=b'\n', timeout=3)
    except subprocess.TimeoutExpired:
        kernel.TerminateJobObject(job, 1)
        child.communicate(timeout=5)
        report['status'] = 'native-probe-timeout'
        report['limitation'] = 'A timed-out real API probe is not evidence of a missing DLL/export or a returned HRESULT error'
    else:
        if child.returncode != 0 or stderr:
            raise AssertionError((child.returncode, stdout, stderr))
        assert_empty_job(job)
        report['native_probe'] = json.loads(stdout)
        if report['native_probe']['kind'] == 'available':
            report['status'] = 'not-applicable'
            report['limitation'] = 'System DwmFlush succeeded; this run cannot complete unavailable-environment acceptance'
        elif report['native_probe']['kind'] in ('library-unavailable', 'function-unavailable', 'hresult-failure'):
            source = '''REQUIRE-GRAPHICS ALSO GRAPHICS DISPLAY-TERMINAL
VARIABLE START-US
: CHECK 8 0 DO UTIME D>S START-US ! VSYNC-WAIT
." WAIT " . UTIME D>S START-US @ - . CR LOOP ; CHECK ." DEPTH " DEPTH . CR BYE'''
            if binary_identity(args.sigma)['sha256'] != report['expected_binary_sha256']:
                raise AssertionError('Sigma changed before execution')
            output = run(args.sigma, source)
            report['binary_after'] = binary_identity(args.sigma)
            if report['binary_after']['sha256'] != report['expected_binary_sha256']:
                raise AssertionError('Sigma changed during execution')
            rows = []
            lines = output.splitlines()
            if not lines or lines[-1].split() != ['DEPTH', '0']:
                raise AssertionError(output)
            for line in lines[:-1]:
                fields = line.split()
                if len(fields) != 3 or fields[0] != 'WAIT':
                    raise AssertionError(output)
                value, elapsed = map(int, fields[1:])
                rows.append(dict(value=value, elapsed_us=elapsed))
            report['sigma_source'] = source
            report['sigma_waits'] = rows
            if len(rows) != 8 or any(row['value'] != 0 or not 0 <= row['elapsed_us'] < 500000 for row in rows):
                raise AssertionError(rows)
            report['status'] = 'pass'
        else:
            report['status'] = 'native-probe-failed'
            report['limitation'] = 'A load error other than ERROR_MOD_NOT_FOUND is not accepted as missing-library evidence'
except BaseException as error:
    report['status'] = 'failed'
    report['error'] = '%s: %s' % (type(error).__name__, error)
    raise
finally:
    cleanup_errors = []
    try:
        if job:
            if not kernel.TerminateJobObject(job, 1):
                cleanup_errors.append('TerminateJobObject failed: %s' % ctypes.get_last_error())
        if child is not None and child.poll() is None:
            child.kill()  # Also covers failure before assigning the private job.
            child.wait(timeout=5)
    except BaseException as error:
        cleanup_errors.append('%s: %s' % (type(error).__name__, error))
    finally:
        if job:
            if not kernel.CloseHandle(job):
                cleanup_errors.append('CloseHandle failed: %s' % ctypes.get_last_error())
        if cleanup_errors:
            report['cleanup_errors'] = cleanup_errors
            report['status'] = 'failed'
        report['finished_at'] = datetime.now(timezone.utc).isoformat()
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open('x', encoding='utf-8') as output:
            json.dump(report, output, indent=2)
            output.write('\n')
        print('%s: %s' % (report['status'], args.output))
raise SystemExit(0 if report['status'] == 'pass' else 2)

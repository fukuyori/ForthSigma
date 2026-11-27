#!/usr/bin/env python3
"""Untimed manual acceptance through ConPTY / POSIX pty; Python >= 3.9, stdlib only.
Run from the repository root. Deadlines detect hangs, never latency acceptance.
"""
import argparse
import base64
import ctypes
from ctypes import wintypes as W
import datetime
import errno
import hashlib
import json
import os
from pathlib import Path
import platform
import queue
import re
import runpy
import sys
import shlex
import signal
import struct
import subprocess
import threading
import time
import uuid


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def serial_attrs(value):
    """termios cc entries can be bytes, unlike flags and speeds."""
    if isinstance(value, bytes):
        return {'hex': value.hex()}
    if isinstance(value, (list, tuple)):
        return [serial_attrs(item) for item in value]
    return value


def clean(text):
    # Keep original bytes separately; remove only terminal control sequences here.
    # ConPTY can encode a line transition as an absolute cursor movement.
    text = re.sub(r'\x1b\[[0-9;]*[Hf]', '\n', text)
    # ConPTY can also encode spaces inside a line as cursor-forward moves.
    text = re.sub(r'\x1b\[(\d*)C', lambda m: ' ' * int(m[1] or 1), text)
    return re.sub(r'\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\))', '', text).replace('\r', '')


def generations(text):
    rows = [int(x) for x in re.findall(r'result generation=(\d+)', text)]
    if not rows or rows != sorted(rows):
        raise AssertionError('missing or backward result generations: %r' % rows)
    return rows


def latest_only(text, example):
    """Input markers precede TC-REQUEST; every applied result must be current."""
    requested = 1
    for item in re.finditer(r'input=(\d+)|result generation=(\d+)', text):
        if item.group(1):
            key = int(item.group(1))
            if (example == 'path' and key == 110) or (example == 'search' and key not in (0, 113)):
                requested += 1
        elif int(item.group(2)) != requested:
            raise AssertionError('stale/non-current result %s while requested=%d' % (item.group(2), requested))


def stty_report(body):
    # Only this known diagnostic is excluded, both before and inside the report.
    body = re.sub(r'(?<!\S)-?pendin(?=[;\s]|$)', 'pendin-ignored', body)
    return '\n'.join(line for line in body.splitlines()
                     if not re.fullmatch(r'sh: child setpgid .*Operation not permitted.*', line)).strip()


def comparable_state(state, pendin):
    result = dict(state)
    if 'termios' in result:
        attrs = list(result['termios'])
        attrs[3] &= ~pendin
        result['termios'] = attrs
    return result


def descendants(table, anchor):
    ids = {anchor}
    while True:
        expanded = ids | {pid for pid, row in table.items() if row['ppid'] in ids}
        if expanded == ids:
            return sorted(ids)
        ids = expanded


def confirmed_gone(pid):
    try:
        os.getpgid(pid)  # Existence probe only; never send even signal 0.
    except ProcessLookupError:
        if platform.system() == 'Darwin':
            # getsid/getpgid can race an exit. Confirm the PID is absent from
            # the kernel process table as well; EPERM is inconclusive.
            try:
                lib = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
                query = lib.proc_pidinfo
                query.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
                query.restype = ctypes.c_int
                buffer = ctypes.create_string_buffer(256)
                ctypes.set_errno(0)
                size = query(pid, 3, 0, buffer, len(buffer))
                return size == 0 and ctypes.get_errno() == errno.ESRCH
            except OSError:
                return False
        return True
    except OSError:
        pass
    return False


def linux_direct_children():
    # Called inside the single-threaded supervisor. Unlike a system-wide
    # ppid snapshot, an empty kernel child list is an ownership endpoint.
    pid = os.getpid()
    return [int(value) for value in Path('/proc/self/task/%d/children' % pid).read_text().split()]


def pending_input(fd, tty=None, io=None, read=None, nonblocking=None):
    """FIONREAD counts readable bytes; canonical partial lines may be hidden."""
    tty = tty if tty is not None else termios
    io = io if io is not None else fcntl
    read = read if read is not None else os.read
    nonblocking = nonblocking if nonblocking is not None else os.O_NONBLOCK
    original = tty.tcgetattr(fd)
    attrs = serial_attrs(original)
    count = struct.unpack('i', io.ioctl(fd, tty.FIONREAD, struct.pack('i', 0)))[0]
    data = b''
    raw_count = None
    probe = list(original)
    probe[6] = list(original[6])
    probe[3] &= ~(tty.ICANON | tty.ECHO)
    probe[6][tty.VMIN] = 0
    probe[6][tty.VTIME] = 0
    flags = io.fcntl(fd, io.F_GETFL)
    try:
        tty.tcsetattr(fd, tty.TCSANOW, probe)
        io.fcntl(fd, io.F_SETFL, flags | nonblocking)
        raw_count = struct.unpack('i', io.ioctl(fd, tty.FIONREAD, struct.pack('i', 0)))[0]
        if raw_count:
            try:
                data = read(fd, raw_count)
            except BlockingIOError:
                pass
    finally:
        try:
            io.fcntl(fd, io.F_SETFL, flags)
        finally:
            tty.tcsetattr(fd, tty.TCSANOW, original)
    return dict(time=utc(), termios_before_observation=attrs, fionread=count, hex=data.hex(), text=data.decode('utf-8', 'replace'),
                noncanonical_fionread=raw_count,
                captured_bytes=len(data), content_complete=len(data) == raw_count,
                note='Observer saves attrs, measures FIONREAD, temporarily disables ICANON/ECHO without flushing, reads residual bytes nonblocking and restores attrs before helpers. '
                     'Residual bytes are informational. Correlate send events and EKEY markers; trace reads on native OS to identify the reader.')


class ProcessRows(dict):
    def __init__(self):
        super().__init__()
        self.errors = []


if os.name == 'nt':
    K = ctypes.WinDLL('kernel32', use_last_error=True)
    HANDLE = W.HANDLE
    SIZE = ctypes.c_size_t

    class COORD(ctypes.Structure):
        _fields_ = [('X', ctypes.c_short), ('Y', ctypes.c_short)]

    class STARTUPINFO(ctypes.Structure):
        _fields_ = [('cb', W.DWORD), ('lpReserved', W.LPWSTR), ('lpDesktop', W.LPWSTR),
                    ('lpTitle', W.LPWSTR), ('dwX', W.DWORD), ('dwY', W.DWORD),
                    ('dwXSize', W.DWORD), ('dwYSize', W.DWORD), ('dwXCountChars', W.DWORD),
                    ('dwYCountChars', W.DWORD), ('dwFillAttribute', W.DWORD),
                    ('dwFlags', W.DWORD), ('wShowWindow', W.WORD), ('cbReserved2', W.WORD),
                    ('lpReserved2', ctypes.POINTER(ctypes.c_byte)),
                    ('hStdInput', HANDLE), ('hStdOutput', HANDLE), ('hStdError', HANDLE)]

    class STARTUPINFOEX(ctypes.Structure):
        _fields_ = [('StartupInfo', STARTUPINFO), ('lpAttributeList', ctypes.c_void_p)]

    class PROCESSINFO(ctypes.Structure):
        _fields_ = [('hProcess', HANDLE), ('hThread', HANDLE),
                    ('dwProcessId', W.DWORD), ('dwThreadId', W.DWORD)]

    class PROCESSENTRY(ctypes.Structure):
        _fields_ = [('dwSize', W.DWORD), ('cntUsage', W.DWORD), ('th32ProcessID', W.DWORD),
                    ('th32DefaultHeapID', ctypes.c_size_t), ('th32ModuleID', W.DWORD),
                    ('cntThreads', W.DWORD), ('th32ParentProcessID', W.DWORD),
                    ('pcPriClassBase', W.LONG), ('dwFlags', W.DWORD), ('szExeFile', W.WCHAR * 260)]

    class THREADENTRY(ctypes.Structure):
        _fields_ = [('dwSize', W.DWORD), ('cntUsage', W.DWORD), ('th32ThreadID', W.DWORD),
                    ('th32OwnerProcessID', W.DWORD), ('tpBasePri', W.LONG),
                    ('tpDeltaPri', W.LONG), ('dwFlags', W.DWORD)]

    def proto(name, result, args):
        f = getattr(K, name)
        f.restype, f.argtypes = result, args
        return f

    proto('CreatePipe', W.BOOL, [ctypes.POINTER(HANDLE), ctypes.POINTER(HANDLE), ctypes.c_void_p, W.DWORD])
    proto('CreatePseudoConsole', W.LONG, [COORD, HANDLE, HANDLE, W.DWORD, ctypes.POINTER(HANDLE)])
    proto('ResizePseudoConsole', W.LONG, [HANDLE, COORD])
    proto('ClosePseudoConsole', None, [HANDLE])
    proto('InitializeProcThreadAttributeList', W.BOOL, [ctypes.c_void_p, W.DWORD, W.DWORD, ctypes.POINTER(SIZE)])
    proto('UpdateProcThreadAttribute', W.BOOL, [ctypes.c_void_p, W.DWORD, SIZE, ctypes.c_void_p, SIZE, ctypes.c_void_p, ctypes.c_void_p])
    proto('DeleteProcThreadAttributeList', None, [ctypes.c_void_p])
    proto('CreateProcessW', W.BOOL, [W.LPCWSTR, W.LPWSTR, ctypes.c_void_p, ctypes.c_void_p,
          W.BOOL, W.DWORD, ctypes.c_void_p, W.LPCWSTR, ctypes.POINTER(STARTUPINFOEX), ctypes.POINTER(PROCESSINFO)])
    proto('ReadFile', W.BOOL, [HANDLE, ctypes.c_void_p, W.DWORD, ctypes.POINTER(W.DWORD), ctypes.c_void_p])
    proto('WriteFile', W.BOOL, [HANDLE, ctypes.c_void_p, W.DWORD, ctypes.POINTER(W.DWORD), ctypes.c_void_p])
    proto('CloseHandle', W.BOOL, [HANDLE])
    proto('WaitForSingleObject', W.DWORD, [HANDLE, W.DWORD])
    class JOB_BASIC_LIMIT(ctypes.Structure):
        _fields_ = [('PerProcessUserTimeLimit', ctypes.c_longlong), ('PerJobUserTimeLimit', ctypes.c_longlong),
                    ('LimitFlags', W.DWORD), ('MinimumWorkingSetSize', SIZE), ('MaximumWorkingSetSize', SIZE),
                    ('ActiveProcessLimit', W.DWORD), ('Affinity', SIZE), ('PriorityClass', W.DWORD), ('SchedulingClass', W.DWORD)]

    class JOB_EXTENDED_LIMIT(ctypes.Structure):
        _fields_ = [('BasicLimitInformation', JOB_BASIC_LIMIT), ('IoInfo', ctypes.c_ulonglong * 6),
                    ('ProcessMemoryLimit', SIZE), ('JobMemoryLimit', SIZE), ('PeakProcessMemoryUsed', SIZE), ('PeakJobMemoryUsed', SIZE)]

    proto('CreateJobObjectW', HANDLE, [ctypes.c_void_p, W.LPCWSTR])
    proto('SetInformationJobObject', W.BOOL, [HANDLE, ctypes.c_int, ctypes.c_void_p, W.DWORD])
    proto('QueryInformationJobObject', W.BOOL, [HANDLE, ctypes.c_int, ctypes.c_void_p, W.DWORD, ctypes.POINTER(W.DWORD)])
    proto('AssignProcessToJobObject', W.BOOL, [HANDLE, HANDLE])
    proto('TerminateJobObject', W.BOOL, [HANDLE, W.UINT])
    proto('ResumeThread', W.DWORD, [HANDLE])
    proto('CreateToolhelp32Snapshot', HANDLE, [W.DWORD, W.DWORD])
    for name in ('Process32FirstW', 'Process32NextW'):
        proto(name, W.BOOL, [HANDLE, ctypes.POINTER(PROCESSENTRY)])
    for name in ('Thread32First', 'Thread32Next'):
        proto(name, W.BOOL, [HANDLE, ctypes.POINTER(THREADENTRY)])
    proto('OpenProcess', HANDLE, [W.DWORD, W.BOOL, W.DWORD])
    proto('GetProcessTimes', W.BOOL, [HANDLE] + [ctypes.POINTER(W.FILETIME)] * 4)
    proto('GetExitCodeProcess', W.BOOL, [HANDLE, ctypes.POINTER(W.DWORD)])

    def checked(ok):
        if not ok:
            raise ctypes.WinError(ctypes.get_last_error())

    def process_table():
        snap = K.CreateToolhelp32Snapshot(2 | 4, 0)
        if snap == ctypes.c_void_p(-1).value:
            raise ctypes.WinError(ctypes.get_last_error())
        rows = ProcessRows()
        try:
            e = PROCESSENTRY(); e.dwSize = ctypes.sizeof(e)
            more = K.Process32FirstW(snap, ctypes.byref(e))
            while more:
                rows[e.th32ProcessID] = dict(pid=e.th32ProcessID, ppid=e.th32ParentProcessID,
                                            threads=e.cntThreads, name=e.szExeFile, thread_ids=[])
                more = K.Process32NextW(snap, ctypes.byref(e))
            t = THREADENTRY(); t.dwSize = ctypes.sizeof(t)
            more = K.Thread32First(snap, ctypes.byref(t))
            while more:
                if t.th32OwnerProcessID in rows:
                    rows[t.th32OwnerProcessID]['thread_ids'].append(t.th32ThreadID)
                more = K.Thread32Next(snap, ctypes.byref(t))
        finally:
            K.CloseHandle(snap)
        return rows
else:
    import fcntl
    import pty
    import select
    import termios

    def process_table():
        rows = ProcessRows()
        if platform.system() == 'Linux':
            for entry in Path('/proc').iterdir():
                if not entry.name.isdigit():
                    continue
                try:
                    fields = (entry / 'stat').read_text().rsplit(')', 1)[1].split()
                    tids = [int(x.name) for x in (entry / 'task').iterdir()]
                    rows[int(entry.name)] = dict(pid=int(entry.name), ppid=int(fields[1]),
                        threads=len(tids), thread_ids=tids, session=int(fields[3]), group=int(fields[2]), name=(entry / 'comm').read_text().strip())
                except (OSError, ValueError) as exc:
                    if isinstance(exc, OSError) and exc.errno == errno.ENOENT and confirmed_gone(int(entry.name)):
                        continue
                    rows.errors.append('proc collection missing for ' + entry.name + ': ' + str(exc))
        else:
            # Darwin's ps/getpgid/getsid loop races process exit: ps can report
            # a PID which has disappeared before the per-PID query. libproc
            # lets us enumerate and query processes without launching a helper.
            lib = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
            listpids = lib.proc_listpids
            listpids.argtypes = [ctypes.c_uint, ctypes.c_uint, ctypes.c_void_p, ctypes.c_int]
            listpids.restype = ctypes.c_int
            pidinfo = lib.proc_pidinfo
            pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
            pidinfo.restype = ctypes.c_int

            class BSDInfo(ctypes.Structure):
                _fields_ = [('flags', ctypes.c_uint32), ('status', ctypes.c_uint32),
                            ('xstatus', ctypes.c_uint32), ('pid', ctypes.c_uint32),
                            ('ppid', ctypes.c_uint32), ('uid', ctypes.c_uint32),
                            ('gid', ctypes.c_uint32), ('ruid', ctypes.c_uint32),
                            ('rgid', ctypes.c_uint32), ('svuid', ctypes.c_uint32),
                            ('svgid', ctypes.c_uint32), ('reserved', ctypes.c_uint32),
                            ('comm', ctypes.c_char * 16), ('name', ctypes.c_char * 32),
                            ('nfiles', ctypes.c_uint32), ('pgid', ctypes.c_uint32),
                            ('pjobc', ctypes.c_uint32), ('tdev', ctypes.c_uint32),
                            ('tpgid', ctypes.c_uint32), ('nice', ctypes.c_int32),
                            ('start_sec', ctypes.c_uint64), ('start_usec', ctypes.c_uint64)]

            def bsd_info(pid):
                info = BSDInfo()
                ctypes.set_errno(0)
                size = pidinfo(pid, 3, 0, ctypes.byref(info), ctypes.sizeof(info))
                return info if size == ctypes.sizeof(info) else None

            capacity = 1024
            while True:
                pids = (ctypes.c_int * capacity)()
                ctypes.set_errno(0)
                byte_count = listpids(1, 0, pids, ctypes.sizeof(pids))
                error = ctypes.get_errno()
                if byte_count < 0:
                    raise OSError(error, 'proc_listpids')
                if byte_count < ctypes.sizeof(pids):
                    break
                capacity *= 2
            for pid in sorted(set(p for p in pids[:byte_count // ctypes.sizeof(ctypes.c_int)] if p > 0)):
                info = bsd_info(pid)
                if info is None:
                    error = ctypes.get_errno()
                    # A process can leave the list between enumeration and
                    # lookup. Confirm disappearance with a second kernel query;
                    # otherwise this remains a collection error.
                    if error == errno.ESRCH and bsd_info(pid) is None and ctypes.get_errno() == errno.ESRCH:
                        continue
                    if error == errno.EPERM:
                        # Privacy controls hide parent/name metadata for some
                        # unrelated processes, while getsid/getpgid remain
                        # queryable. Keep the session/group identity and let
                        # owned-PID snapshots require parent metadata if needed.
                        info = None
                    elif error == errno.ESRCH:
                        rows.errors.append('proc_pidinfo missing for ' + str(pid) + ': ' + str(OSError(error, os.strerror(error))))
                        continue
                    else:
                        rows.errors.append('proc_pidinfo missing for ' + str(pid) + ': ' + str(OSError(error, os.strerror(error))))
                        continue
                try:
                    session = os.getsid(pid)
                except OSError as exc:
                    # getsid may lose the exit race. A repeated libproc lookup
                    # distinguishes that from a live process with unavailable
                    # session metadata (including zombies still in the table).
                    if exc.errno == errno.ESRCH and bsd_info(pid) is None and ctypes.get_errno() == errno.ESRCH:
                        continue
                    rows.errors.append('session/group collection missing for ' + str(pid) + ': ' + str(exc))
                    continue
                try:
                    group = os.getpgid(pid)
                except OSError as exc:
                    if exc.errno == errno.ESRCH and bsd_info(pid) is None and ctypes.get_errno() == errno.ESRCH:
                        continue
                    rows.errors.append('session/group collection missing for ' + str(pid) + ': ' + str(exc))
                    continue
                rows[pid] = dict(pid=pid, ppid=int(info.ppid) if info is not None else None,
                                 name=info.comm.decode('utf-8', 'replace') if info is not None else None,
                                 group=group, session=session, threads=None)
        return rows


class CollectionMissing(RuntimeError):
    pass


# Executed only by the POSIX session leader. The leader stays unreaped until
# group cleanup: its PID/PGID cannot be reused, even if it unexpectedly exits.
def supervise(control, slave, replies):
    os.setsid()
    signal.signal(signal.SIGCHLD, signal.SIG_DFL)
    linux = platform.system() == 'Linux'
    if linux:
        libc = ctypes.CDLL(None, use_errno=True)
        libc.prctl.argtypes = [ctypes.c_int] + [ctypes.c_ulong] * 4
        libc.prctl.restype = ctypes.c_int
        if libc.prctl(36, 1, 0, 0, 0) != 0:  # PR_SET_CHILD_SUBREAPER
            raise OSError(ctypes.get_errno(), 'PR_SET_CHILD_SUBREAPER failed')
    # Keep the anchor alive on terminal Ctrl+C; exec resets caught handlers in
    # sigma/helpers to the default, unlike SIG_IGN which would be inherited.
    signal.signal(signal.SIGINT, lambda signum, frame: None)
    signal.signal(signal.SIGTERM, lambda signum, frame: None)
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
    for fd in (0, 1, 2):
        os.dup2(slave, fd)
    if slave > 2:
        os.close(slave)
    active = None
    buffered = b''
    while True:
        if active is not None and active.poll() is not None:
            try:
                observation = pending_input(0)
            except OSError as exc:
                observation = dict(error=str(exc))
            print('\n' + active_token + '_INPUT=' + json.dumps(observation), flush=True)
            print('\n' + active_token + '=' + str(active.returncode), flush=True)
            active = None
        if b'\n' not in buffered:
            if not select.select([control], [], [], 0.02)[0]:
                continue
            chunk = os.read(control, 65536)
            if not chunk:
                break
            buffered += chunk
        if b'\n' not in buffered:
            continue
        line, buffered = buffered.split(b'\n', 1)
        request = json.loads(line)
        if request.get('operation') == 'inspect':
            table = process_table()
            first_errors = list(table.errors)
            direct = []
            if linux:
                try:
                    direct = linux_direct_children()
                    for pid in direct:
                        if active is not None and pid == active.pid:
                            continue
                        try:
                            os.waitpid(pid, os.WNOHANG)
                        except ChildProcessError:
                            pass
                    direct = linux_direct_children()
                except OSError as exc:
                    first_errors.append('kernel child list missing: ' + str(exc))
                table = process_table()
                table.errors.extend(first_errors)
            response = dict(ids=sorted(set(descendants(table, os.getpid())) | set(direct)), errors=table.errors,
                            subreaper=linux)
            os.write(replies, (json.dumps(response) + '\n').encode())
            continue
        if request.get('operation') == 'cleanup':
            errors = []
            # Signal only the anchored group. Descendant observations do not
            # authorize signals to processes that have left this group/session.
            os.killpg(os.getpgrp(), signal.SIGTERM)
            deadline = time.monotonic() + 5
            while linux:
                children = linux_direct_children()
                if not children or time.monotonic() >= deadline:
                    break
                while True:
                    try:
                        if os.waitpid(-1, os.WNOHANG)[0] == 0:
                            break
                    except ChildProcessError:
                        break
                time.sleep(0.01)
            table = process_table()
            direct = linux_direct_children() if linux else []
            os.write(replies, (json.dumps(dict(ids=sorted(set(descendants(table, os.getpid())) | set(direct)),
                     errors=errors + table.errors, subreaper=linux)) + '\n').encode())
            continue
        try:
            active = subprocess.Popen(request['argv'])
            active_token = request['token']
            continue
        except OSError as exc:
            print('SUPERVISOR_ERROR=' + str(exc), flush=True)
            code = 127
        print('\n' + request['token'] + '=' + str(code), flush=True)
    # Parent must kill the group before reaping us; never relinquish the anchor.
    while True:
        signal.pause()


class Terminal:
    def __init__(self, directory, timeout):
        self.directory = directory
        directory.mkdir(parents=True, exist_ok=True)
        self.timeout = timeout
        self.events = (directory / 'events.jsonl').open('w', encoding='utf-8')
        self.raw = (directory / 'output.bin').open('wb')
        self.output = bytearray()
        self.messages = queue.Queue()
        self.error = None
        self.closed = False
        self.snapshots = []
        self.collection_errors = []
        self.forced_cleanup = False
        self.residual_observations = []
        self.sent_keys = []
        if os.name == 'nt':
            try:
                self.start_windows()
            except BaseException:
                if getattr(self, 'job', None):
                    K.TerminateJobObject(self.job, 125)
                    K.CloseHandle(self.job)
                pi = getattr(self, 'pi', None)
                if pi and pi.hProcess:
                    K.WaitForSingleObject(pi.hProcess, 5000)
                    K.CloseHandle(pi.hProcess)
                if getattr(self, 'input', None):
                    K.CloseHandle(self.input)
                if getattr(self, 'hpc', None):
                    K.ClosePseudoConsole(self.hpc)
                if getattr(self, 'output_handle', None):
                    K.CloseHandle(self.output_handle)
                self.raw.close(); self.events.close()
                raise
        else:
            self.master, self.slave = pty.openpty()
            control_read, self.control = os.pipe()
            self.reply, reply_write = os.pipe()
            self.pid = os.fork()
            if self.pid == 0:
                try:
                    os.close(self.control)
                    os.close(self.master)
                    os.close(self.reply)
                    supervise(control_read, self.slave, reply_write)
                finally:
                    os._exit(127)
            os.close(control_read)
            os.close(reply_write)
            self.pidfd = None
            if hasattr(os, 'pidfd_open'):
                try:
                    self.pidfd = os.pidfd_open(self.pid)
                except OSError as exc:
                    # Optional: the unreaped leader already reserves the PGID.
                    self.event('pidfd-unavailable', error=str(exc))
        self.reader = threading.Thread(target=self.read, daemon=True)
        self.reader.start()
        self.tracker_stop = threading.Event()
        self.child_samples = []
        self.tracker = None
        if platform.system() == 'Darwin':
            self.tracker = threading.Thread(target=self.track_macos, daemon=True)
            self.tracker.start()
        try:
            self.command_echo('READY')
            if platform.system() == 'Linux':
                status = self.supervisor_query('inspect')
                if not status['subreaper']:
                    raise CollectionMissing('Linux supervisor is not a subreaper')
                self.event('subreaper', **status)
        except BaseException:
            self.close()
            raise

    def event(self, kind, _time=None, **fields):
        observed_time = fields.pop('time', None)
        self.events.write(json.dumps(dict(time=_time or observed_time or utc(), kind=kind, **fields)) + '\n')
        self.events.flush()

    def track_macos(self):
        try:
            lib = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
            children = lib.proc_listchildpids
            children.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
            children.restype = ctypes.c_int  # PID count, NOT byte count
            while not self.tracker_stop.is_set():
                begin = utc()
                ids, pending = {self.pid}, [self.pid]
                while pending:
                    parent = pending.pop()
                    capacity = 64
                    while True:
                        buffer = (ctypes.c_int * capacity)()
                        ctypes.set_errno(0)
                        count = children(parent, buffer, ctypes.sizeof(buffer))
                        error = ctypes.get_errno()
                        if count < 0 or (count == 0 and error):
                            if error == errno.ESRCH and confirmed_gone(parent):
                                count = 0
                                break
                            raise OSError(error, 'proc_listchildpids')
                        if count < capacity:
                            break
                        capacity *= 2
                    for pid in buffer[:count]:
                        if pid > 0 and pid not in ids:
                            ids.add(pid)
                            pending.append(pid)
                self.child_samples.append(dict(started=begin, finished=utc(), ids=sorted(ids)))
                self.tracker_stop.wait(0.02)
        except Exception as exc:
            self.collection_errors.append('macOS child polling failed: ' + str(exc))

    def start_windows(self):
        read_in, write_in, read_out, write_out = HANDLE(), HANDLE(), HANDLE(), HANDLE()
        checked(K.CreatePipe(ctypes.byref(read_in), ctypes.byref(write_in), None, 0))
        try:
            checked(K.CreatePipe(ctypes.byref(read_out), ctypes.byref(write_out), None, 0))
        except BaseException:
            K.CloseHandle(read_in); K.CloseHandle(write_in)
            raise
        self.input, self.output_handle, self.hpc = write_in, read_out, HANDLE()
        hr = K.CreatePseudoConsole(COORD(160, 60), read_in, write_out, 0, ctypes.byref(self.hpc))
        K.CloseHandle(read_in); K.CloseHandle(write_out)
        if hr < 0:
            raise OSError('CreatePseudoConsole HRESULT=%#x' % (hr & 0xffffffff))
        hr = K.ResizePseudoConsole(self.hpc, COORD(160, 60))
        if hr < 0:
            raise OSError('ResizePseudoConsole HRESULT=%#x' % (hr & 0xffffffff))
        self.job = K.CreateJobObjectW(None, None)
        checked(self.job)
        limits = JOB_EXTENDED_LIMIT()
        limits.BasicLimitInformation.LimitFlags = 0x2000  # KILL_ON_JOB_CLOSE; no breakaway
        checked(K.SetInformationJobObject(self.job, 9, ctypes.byref(limits), ctypes.sizeof(limits)))
        size = SIZE()
        K.InitializeProcThreadAttributeList(None, 2, 0, ctypes.byref(size))
        attributes = ctypes.create_string_buffer(size.value)
        checked(K.InitializeProcThreadAttributeList(attributes, 2, 0, ctypes.byref(size)))
        try:
            checked(K.UpdateProcThreadAttribute(attributes, 0, 0x00020016, self.hpc,
                                                ctypes.sizeof(HANDLE), None, None))
            # Atomic job assignment closes even the assignment-failure startup gap.
            # Unsupported JOB_LIST => CreateProcess fails; no PID fallback.
            jobs = (HANDLE * 1)(self.job)
            checked(K.UpdateProcThreadAttribute(attributes, 0, 0x0002000d, jobs,
                                                ctypes.sizeof(jobs), None, None))
            si = STARTUPINFOEX(); si.StartupInfo.cb = ctypes.sizeof(si)
            # Prevent redirected parent std handles bypassing ConPTY. See
            # https://github.com/microsoft/terminal/discussions/15814
            si.StartupInfo.dwFlags = 0x00000100  # STARTF_USESTDHANDLES, null handles
            si.lpAttributeList = ctypes.cast(attributes, ctypes.c_void_p)
            self.pi = PROCESSINFO()
            command = ctypes.create_unicode_buffer('cmd.exe /d /v:on /q')
            checked(K.CreateProcessW(None, command, None, None, False, 0x00080004,
                    None, str(Path.cwd()), ctypes.byref(si), ctypes.byref(self.pi)))
            self.pid = self.pi.dwProcessId
            try:
                checked(K.AssignProcessToJobObject(self.job, self.pi.hProcess))
                if K.ResumeThread(self.pi.hThread) == 0xffffffff:
                    raise ctypes.WinError(ctypes.get_last_error())
            finally:
                K.CloseHandle(self.pi.hThread)
        finally:
            K.DeleteProcThreadAttributeList(attributes)

    def read(self):
        try:
            while True:
                if os.name == 'nt':
                    buf = ctypes.create_string_buffer(16384); n = W.DWORD()
                    if not K.ReadFile(self.output_handle, buf, len(buf), ctypes.byref(n), None) or not n.value:
                        break
                    data = buf.raw[:n.value]
                else:
                    if not select.select([self.master], [], [], 0.2)[0]:
                        if self.closed:
                            break
                        continue
                    data = os.read(self.master, 16384)
                    if not data:
                        break
                self.messages.put((utc(), data))
        except OSError as exc:
            self.error = str(exc)
        finally:
            self.messages.put(None)

    def pump(self, wait=0.01):
        try:
            block = self.messages.get(timeout=wait)
        except queue.Empty:
            return
        while block is not None:
            received, data = block
            self.output.extend(data)
            if getattr(self, 'output_observer', None):
                pending = getattr(self, 'observer_pending', b'') + data
                end = pending.rfind(b'\n') + 1
                if end:
                    self.output_observer(clean(pending[:end].decode('utf-8', 'replace')))
                self.observer_pending = pending[end:]
            self.raw.write(data); self.raw.flush()
            self.event('receive', _time=received, base64=base64.b64encode(data).decode(), text=data.decode('utf-8', 'replace'))
            try:
                block = self.messages.get_nowait()
            except queue.Empty:
                break

    @property
    def text(self):
        self.pump(0)
        return clean(self.output.decode('utf-8', 'replace'))

    def interrupt(self):
        """Signal only this terminal's anchored group, independently of raw mode."""
        self.event('interrupt', method='CTRL_C_EVENT' if os.name == 'nt' else 'SIGINT')
        if os.name == 'nt':
            # A separate helper avoids detaching the adapter from the user's
            # console. CTRL_C_EVENT cannot target a nonzero process group;
            # broadcast only inside our private ConPTY console instead.
            helper = """import ctypes,sys,time
k=ctypes.WinDLL('kernel32',use_last_error=True)
k.FreeConsole()
if not k.AttachConsole(int(sys.argv[1])): raise ctypes.WinError(ctypes.get_last_error())
if not k.SetConsoleCtrlHandler(None,True): raise ctypes.WinError(ctypes.get_last_error())
k.GetStdHandle.restype=ctypes.c_void_p
h=k.GetStdHandle(-10)
mode=ctypes.c_ulong()
deadline=time.monotonic()+2
while True:
 if not k.GetConsoleMode(ctypes.c_void_p(h),ctypes.byref(mode)): raise ctypes.WinError(ctypes.get_last_error())
 if mode.value & 1: break
 if time.monotonic() >= deadline: raise RuntimeError('native interrupt wait did not enable processed input')
 time.sleep(0.001)
if not k.GenerateConsoleCtrlEvent(0,0): raise ctypes.WinError(ctypes.get_last_error())
time.sleep(0.1)
k.FreeConsole()
"""
            subprocess.run([sys.executable, '-c', helper, str(self.pid)],
                           creationflags=subprocess.CREATE_NO_WINDOW, check=True, timeout=5)
        else:
            # The supervisor remains unreaped and reserves this group ID.
            deadline = time.monotonic() + 2
            while not termios.tcgetattr(self.slave)[3] & termios.ISIG:
                if time.monotonic() >= deadline:
                    raise RuntimeError('native interrupt wait did not enable ISIG')
                time.sleep(0.001)
            os.killpg(self.pid, signal.SIGINT)

    def send(self, text):
        data = text.encode('utf-8')
        if os.name != 'nt':
            self.sent_keys.append(dict(text=text, hex=data.hex()))
        self.event('send', text=text, hex=data.hex())
        if os.name == 'nt':
            n = W.DWORD()
            checked(K.WriteFile(self.input, data, len(data), ctypes.byref(n), None))
            if n.value != len(data):
                raise OSError('short ConPTY write')
        else:
            while data:
                data = data[os.write(self.master, data):]

    def expect(self, pattern, start=0):
        deadline = time.monotonic() + self.timeout
        while True:
            match = re.search(pattern, self.text[start:])
            if match:
                return match
            if time.monotonic() >= deadline:
                raise AssertionError('hang guard: missing %r' % pattern)
            self.pump(0.02)

    def request(self, argv, token):
        data = (json.dumps(dict(argv=argv, token=token)) + '\n').encode()
        while data:
            data = data[os.write(self.control, data):]

    def supervisor_query(self, operation):
        os.write(self.control, (json.dumps(dict(operation=operation)) + '\n').encode())
        data = bytearray()
        deadline = time.monotonic() + self.timeout
        while not data.endswith(b'\n'):
            if time.monotonic() >= deadline:
                raise CollectionMissing('supervisor query timed out: ' + operation)
            if select.select([self.reply], [], [], 0.02)[0]:
                block = os.read(self.reply, 1)
                if not block:
                    raise CollectionMissing('supervisor reply closed')
                data.extend(block)
        result = json.loads(data)
        self.collection_errors.extend(result['errors'])
        return result

    def command_echo(self, label):
        token = 'TTY_' + uuid.uuid4().hex + '_' + label
        start = len(self.text)
        if os.name == 'nt':
            self.send('echo ' + token + '\r')
        else:
            self.request([sys.executable, '-c', 'print(' + repr(token) + ')'], token + '_HELPER')
            self.expect(r'(?m)^' + token + r'_HELPER=0\s*$', start)
        self.expect(r'(?m)^' + token + r'\s*$', start)

    def terminal_state(self):
        if os.name == 'nt':
            token = 'MODE_' + uuid.uuid4().hex
            start = len(self.text)
            command = subprocess.list2cmdline([sys.executable, str(Path(__file__).resolve()), '--console-state'])
            self.send(command + ' & echo ' + token + '\r')
            self.expect(r'(?m)^' + token + r'\s*$', start)
            match = re.search(r'CONSOLE_STATE=(\{[^\r\n]+\})', self.text[start:])
            if not match:
                raise CollectionMissing('console mode helper produced no state')
            state = json.loads(match.group(1))
            if any('error' in value for value in state.values()):
                raise CollectionMissing('console mode helper failed: %r' % state)
            return state
        attrs = termios.tcgetattr(self.slave)
        return {'termios': serial_attrs(attrs)}

    def stty(self, label):
        if os.name == 'nt':
            return None
        token = 'STTY_' + uuid.uuid4().hex
        start = len(self.text)
        self.request(['/bin/sh', '-c', "printf '\\n%s\\n' " + token + "; stty -a; result=$?; printf '\\n%s\\n' " + token + '_REPORT_END; exit "$result"'], token + '_END')
        match = self.expect(r'(?m)^' + token + r'_END=(-?\d+)\s*$', start)
        body = self.text[start:]
        (self.directory / ('stty-' + label + '.txt')).write_text(body, encoding='utf-8')
        if int(match.group(1)) != 0 or not re.search(r'(?m)^speed ', body):
            raise CollectionMissing('stty failed or report missing; rerun stty -a with exit status on the same native pty (1397-1399)')
        if token + '\n' not in body or token + '_REPORT_END\n' not in body:
            raise CollectionMissing('stty report boundary missing')
        body = body.split(token + '\n', 1)[1].split(token + '_REPORT_END\n', 1)[0]
        # Remove only the known shell diagnostic, wherever it occurs.
        return stty_report(body)

    def owned_ids(self):
        if os.name != 'nt':
            if platform.system() == 'Linux':
                return self.supervisor_query('inspect')['ids']
            table = process_table()
            self.collection_errors.extend(table.errors)
            return sorted(set(descendants(table, self.pid)) | {pid for pid, row in table.items() if row.get('session') == self.pid})
        capacity = 64
        while True:
            class IDS(ctypes.Structure):
                _fields_ = [('assigned', W.DWORD), ('count', W.DWORD), ('ids', SIZE * capacity)]
            result = IDS()
            if K.QueryInformationJobObject(self.job, 3, ctypes.byref(result), ctypes.sizeof(result), None):
                return list(result.ids[:result.count])
            if ctypes.get_last_error() != 234:
                raise CollectionMissing('JobObjectBasicProcessIdList failed: ' + str(ctypes.get_last_error()))
            capacity = max(capacity * 2, result.assigned)

    def snapshot(self, label):
        try:
            table = process_table()
            ids = self.owned_ids()
        except Exception as exc:
            self.collection_errors.append('process collection failed: ' + str(exc))
            self.event('collector-error', label=label, error=str(exc))
            raise CollectionMissing('process collection failed; rerun native process/thread collector with command and error (1397-1399): ' + str(exc)) from exc
        # The supervisor may launch a requested child between these reads.
        # Collect metadata again for newly observed members, retaining errors.
        if set(ids) - set(table):
            newer = process_table()
            table.update(newer)
            table.errors.extend(newer.errors)
        rows = [table[pid] for pid in ids if pid in table]
        missing = sorted(set(ids) - set(table))
        if os.name != 'nt':
            missing = [pid for pid in missing if not confirmed_gone(pid)]
        if missing:
            self.collection_errors.append('owned PID metadata unavailable: ' + str(missing))
        if os.name == 'nt':
            for row in rows:
                if not row.get('thread_ids') or len(row['thread_ids']) != row['threads']:
                    self.collection_errors.append('thread snapshot incomplete/changed for owned PID ' + str(row['pid']))
        if platform.system() == 'Darwin':
            lib = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
            pidinfo = lib.proc_pidinfo
            pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
            pidinfo.restype = ctypes.c_int
            class TaskInfo(ctypes.Structure):
                _fields_ = [('virtual_size', ctypes.c_uint64), ('resident_size', ctypes.c_uint64),
                            ('total_user', ctypes.c_uint64), ('total_system', ctypes.c_uint64),
                            ('threads_user', ctypes.c_uint64), ('threads_system', ctypes.c_uint64),
                            ('policy', ctypes.c_int32), ('faults', ctypes.c_int32),
                            ('pageins', ctypes.c_int32), ('cow_faults', ctypes.c_int32),
                            ('messages_sent', ctypes.c_int32), ('messages_received', ctypes.c_int32),
                            ('syscalls_mach', ctypes.c_int32), ('syscalls_unix', ctypes.c_int32),
                            ('csw', ctypes.c_int32), ('threadnum', ctypes.c_int32),
                            ('numrunning', ctypes.c_int32), ('priority', ctypes.c_int32)]
            for row in rows:
                info = TaskInfo()
                ctypes.set_errno(0)
                size = pidinfo(row['pid'], 4, 0, ctypes.byref(info), ctypes.sizeof(info))
                if size == ctypes.sizeof(info):
                    row['threads'] = int(info.threadnum)
                    row['proc_pidinfo_taskinfo'] = dict(thread_count=info.threadnum, running=info.numrunning)
                else:
                    error = ctypes.get_errno()
                    self.collection_errors.append('proc_pidinfo task collection missing for ' + str(row['pid']) + ': ' + str(OSError(error, os.strerror(error))))
        self.collection_errors.extend(table.errors)
        record = dict(time=utc(), label=label, anchor_pid=self.pid, processes=rows, collection_errors=list(self.collection_errors))
        self.snapshots.append(record)
        save(self.directory / 'processes.json', self.snapshots)
        return rows

    def launch(self, sigma, source):
        return self.launch_argv([str(sigma), source])

    def launch_argv(self, argv):
        """Launch an owned saved application using the same terminal/collector."""
        source = repr(argv)
        self.current_source = source
        self.sent_keys = []
        self.before = self.terminal_state()
        self.stty_before = self.stty('before-' + str(len(self.snapshots)))
        self.token = 'EXIT_' + uuid.uuid4().hex
        self.start = len(self.text)
        if os.name == 'nt':
            # ConPTY receives keystrokes: Enter is CR. A following LF can
            # reach Sigma as an extra input event after cmd launches it.
            command = subprocess.list2cmdline(argv) + ' & echo ' + self.token + '=!errorlevel!\r'
        else:
            command = shlex.join(argv)
        self.event('launch', command=command, source=source)
        if os.name == 'nt':
            self.send(command)
        else:
            self.request(argv, self.token)
        self.owned = set()
        self.observed_children = set()
        deadline = time.monotonic() + min(self.timeout, 5)
        while time.monotonic() < deadline:
            rows = self.snapshot('launch')
            self.owned |= {r['pid'] for r in rows if r['pid'] != self.pid and Path(r['name']).name.lower() == Path(argv[0]).name.lower()}
            self.observed_children |= {r['pid'] for r in rows if r['pid'] != self.pid}
            if self.owned or self.exited():
                break
            self.pump(0.01)
        self.active = self.snapshot('active')

    def exited(self):
        return re.search(r'(?m)^' + self.token + r'=(-?\d+)\s*$', self.text[self.start:])

    def finish(self, interrupted=False):
        match = self.expect(r'(?m)^' + self.token + r'=(-?\d+)\s*$', self.start)
        code = int(match.group(1))
        self.event('exit', code=code)
        residual = None
        if os.name != 'nt':
            captured = re.search(r'(?m)^' + self.token + r'_INPUT=(\{[^\r\n]+\})', self.text[self.start:])
            if not captured:
                raise CollectionMissing('exit input observation missing')
            residual = json.loads(captured.group(1))
            residual.update(source=self.current_source, sent_keys=list(self.sent_keys))
            self.residual_observations.append(residual)
            self.event('residual-input', **residual)
            if 'error' in residual:
                raise CollectionMissing('exit input observation failed: ' + residual['error'])
            if residual['hex'] or residual['fionread'] or residual['noncanonical_fionread']:
                print(self.directory.name, 'residual input:', repr(residual['text']), residual['hex'],
                      'FIONREAD=', residual['fionread'], 'noncanonical=', residual['noncanonical_fionread'],
                      'content_complete=', residual['content_complete'], flush=True)
        if not interrupted and code != 0:
            raise AssertionError('sigma exit code %d' % code)
        self.after = self.terminal_state()
        if residual is not None:
            self.after = {'termios': residual['termios_before_observation']}
        stty_after = self.stty('after-' + str(len(self.snapshots)))
        self.command_echo('RECOVERED')
        remaining = [pid for pid in self.owned_ids() if pid != self.pid]
        if platform.system() == 'Linux':
            remaining = sorted(set(remaining) | (set(self.supervisor_query('inspect')['ids']) - {self.pid}))
        self.snapshot('after-exit')
        recovery = dict(exit_code=code, before=self.before, after=self.after,
                        stty_before=self.stty_before, stty_after=stty_after,
                        owned_pids=sorted(self.owned), observed_children=sorted(self.observed_children), remaining=remaining,
                        shell_echo=True, evidence='pseudo-terminal only')
        recovery['residual_input'] = residual
        self.event('recovery', **recovery)
        if remaining:
            raise AssertionError('owned processes remain: %r' % remaining)
        pendin = getattr(termios, 'PENDIN', 0) if os.name != 'nt' else 0
        if comparable_state(self.before, pendin) != comparable_state(self.after, pendin) or self.stty_before != stty_after:
            raise AssertionError('terminal settings not restored')
        return recovery

    def close(self):
        if self.closed:
            return
        # Never derive signal targets from process snapshots or parent PIDs.
        try:
            try:
                ids = self.owned_ids()
            except Exception as exc:
                ids = []
                self.collection_errors.append('cleanup membership collection failed: ' + str(exc))
                self.event('collector-error', error=str(exc))
            self.forced_cleanup = any(pid != self.pid for pid in ids)
            self.event('session-cleanup', owned=ids, forced_workload_cleanup=self.forced_cleanup)
            if os.name == 'nt':
                checked(K.TerminateJobObject(self.job, 125))
                K.WaitForSingleObject(self.pi.hProcess, 5000)
                deadline = time.monotonic() + 5
                while self.owned_ids() and time.monotonic() < deadline:
                    self.pump(0.02)
                if self.owned_ids():
                    raise RuntimeError('job still contains processes after termination')
            else:
                try:
                    if platform.system() == 'Linux':
                        result = self.supervisor_query('cleanup')
                        self.cleanup_remaining = result['ids']
                        self.event('subreaper-cleanup', **result)
                        if result['ids'] != [self.pid]:
                            raise RuntimeError('subreaper descendants remain after cleanup: ' + str(result['ids']))
                finally:
                    # The unreaped direct leader reserves the group identity.
                    try:
                        os.killpg(self.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    os.waitpid(self.pid, 0)
        finally:
            self.closed = True
            self.tracker_stop.set()
            if self.tracker:
                self.tracker.join(5)
                save(self.directory / 'child-polling.json', dict(samples=self.child_samples,
                     interval_seconds=0.02, limitation='Sampling misses fork/exit/reparenting between calls; PID observations never authorize signals.'))
            if os.name == 'nt':
                K.CloseHandle(self.job)
                K.CloseHandle(self.input)
                K.ClosePseudoConsole(self.hpc)
                self.reader.join(5)
                K.CloseHandle(self.output_handle); K.CloseHandle(self.pi.hProcess)
            else:
                os.close(self.control)
                os.close(self.reply)
                if self.pidfd is not None:
                    os.close(self.pidfd)
                self.reader.join(1)
                os.close(self.master); os.close(self.slave)
            self.pump(0)
            (self.directory / 'output.txt').write_text(self.output.decode('utf-8', 'replace'), encoding='utf-8')
            self.raw.close(); self.events.close()


PENDING = {
    'AC-02': 'native screen/cursor: fixture 1394; Claude and user observe on each OS (1397-1399)',
    'AC-05': 'multiple tasks/audio/window ownership: implement combined fixture 1394, then Claude and user run on each OS (1397-1399)',
    'AC-18': 'native paint/close and physical screen unverified unless explicitly run on an available display; Claude and user run in a display session (1397-1399)',
    'AC-19': 'finite same-process progress observation does not prove all schedules or queue saturation; queue dwell/Snapshot availability: 1396',
    'AC-20': 'finite same-process progress observation; native Windows/macOS runs: 1397-1399; queue dwell/Snapshot availability: 1396; single-VM time: 1390-1393',
    'AC-24': 'child/audio/window retained at exit: fixture 1394, Claude and user run per OS (1397-1399); unstoppable-host recovery already covered by abadd1b tests/src reap reproduction (not rerun here)',
    'AC-25': 'native retained display under injected failures: fixture 1394; mixed real sources 1395; Claude and user run per OS (1397-1399)',
}


class Runner:
    def __init__(self, args, root):
        self.args, self.root = args, root
        self.fixtures = runpy.run_path('tests/scripts/acceptance-fixtures.py')['generate'](Path('.'), root / 'fixtures', 1000000000)
        self.prepare_sources()
        self.results = {ac: dict(status='unverified', evidence='pseudo-terminal only',
                                cases=[], unverified=[reason]) for ac, reason in PENDING.items()}

    def prepare_sources(self):
        data = self.root / 'checksum-64MiB.bin'
        with data.open('wb') as output:
            for _ in range(1024):
                output.write(bytes(range(256)) * 256)
        checksum = self.root / 'checksum-large.fs'
        checksum.write_text(Path('examples/task-checksum.fs').read_text(encoding='utf-8').replace('S" LICENSE"', 'S" ' + data.as_posix() + '"'), encoding='utf-8')
        self.large_checksum = checksum
        # An unending VM loop makes the running phase observable until cancellation.
        busy = self.root / 'running.fs'
        busy.write_text(r'''REQUIRE-EXTENSION ALSO EXTENSION
VARIABLE SS VARIABLE JJ
: BUSY 2DROP BEGIN AGAIN ;
: RUN TASK-SNAPSHOT THROW SS !
SS @ S" BUSY" S" x" TASK-I1 7 TASK-SUBMIT THROW JJ !
BEGIN JJ @ TASK-STATE THROW 2DROP DROP TASK-RUNNING = UNTIL
." WORKER-RUNNING" CR
BEGIN EKEY EKEY>CHAR IF 113 = ELSE DROP 0 THEN UNTIL
JJ @ TASK-CANCEL THROW JJ @ 30000 TASK-WAIT THROW
TASK-WAIT-EXPIRED AND IF -4095 THROW THEN
TASK-CANCELLED <> IF -4095 THROW THEN
JJ @ TASK-RELEASE THROW SS @ TASK-SNAPSHOT-RELEASE THROW ;
RUN BYE
''', encoding='utf-8')
        self.busy = busy
        sources = sorted(Path('examples').glob('task-*.fs')) + [
            Path('tests/scripts/check-task-console.fs'), Path('tests/scripts/check-task-wait-real.fs'),
            Path('tests/scripts/check-task-fair-real.fs'), Path('tests/scripts/task-wait-real-common.fs'),
            Path('tests/scripts/check-task-wait-paint-real.fs'), Path('tests/scripts/acceptance-fixtures.py'),
            busy, checksum] + sorted(self.fixtures.values())
        save(self.root / 'source-evidence.json', dict(
            files={str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources},
            scope='Source hashes support reinspection of intended child-free fixtures; not proof of runtime/native child absence.'))

    def workload(self, t, name):
        t.launch(self.args.sigma, str(self.fixtures[name]))
        t.expect('RESULT-BYTES=', t.start)
        t.send('q')
        return self.end(t)

    def response(self, t):
        t.launch(self.args.sigma, str(self.fixtures['response']))
        t.expect('INPUT-READY', t.start)
        t.send('b'); t.expect(r'INPUT-APPLIED=98\s', t.start)
        t.send('q'); t.expect(r'INPUT-APPLIED=113\s', t.start)
        return self.end(t)

    def running_quit(self, t, key):
        t.launch(self.args.sigma, str(self.busy))
        t.expect('WORKER-RUNNING', t.start)
        t.snapshot('worker-running-before-quit')
        t.send(key)
        result = self.end(t, key == '\x03')
        result['running_evidence'] = 'TASK-RUNNING observed before marker; unending worker until cancellation'
        return result

    def case(self, ac, name, action):
        terminal = None
        record = dict(name=name, evidence='pseudo-terminal only')
        try:
            terminal = Terminal(self.root / name, self.args.timeout)
            record.update(action(terminal) or {})
            missing = list(terminal.collection_errors)
            if platform.system() == 'Darwin':
                missing.append('macOS child polling cannot prove lifetime ownership/reclamation across fork/exit/reparenting between samples; rerun with native fork/exit tracing (1399)')
            if missing:
                record.setdefault('missing_observations', []).extend(missing)
                if record.get('status') != 'failed':
                    record.update(status='unverified', reason=record.get('reason', '') + '; ' + '; '.join(missing),
                                  verification=record.get('verification', '') + '; Repeat missing native process/thread collection with errors; track escaping descendants throughout their lifetime before claiming reclamation (1397-1399)')
            record.setdefault('status', 'passed')
            record.setdefault('reason', 'expected pseudo-terminal input/output, exit and shell recovery observed')
        except CollectionMissing as exc:
            record.update(status='unverified', reason=str(exc),
                          verification='Repeat the missing process/thread/stty collection on the native OS, retain command errors and exit status; add lifetime tracking for escaped groups before claiming ownership/reclamation (1397-1399)')
        except Exception as exc:
            record.update(status='failed', reason='%s: %s' % (type(exc).__name__, exc))
            if terminal:
                terminal.event('failure', reason=record['reason'])
                try:
                    terminal.snapshot('failure-before-owned-cleanup')
                except Exception as missing:
                    record['collection_error'] = str(missing)
        finally:
            if terminal:
                try:
                    terminal.close()
                    record['residual_input_observations'] = terminal.residual_observations
                    record['forced_workload_cleanup'] = terminal.forced_cleanup
                    if terminal.collection_errors:
                        record['collection_errors'] = list(terminal.collection_errors)
                        if record.get('status') == 'passed':
                            record.update(status='unverified', reason='process collection incomplete',
                                          verification='Rerun the failed native collector, preserving errors and exit status (1397-1399)')
                    if terminal.forced_cleanup and record.get('status') == 'passed':
                        record.update(status='failed', reason='workload remained and required forced cleanup')
                except Exception as exc:
                    record.update(status='failed', reason=record.get('reason', '') + '; cleanup failed: ' + str(exc))
        self.results[ac]['cases'].append(record)
        self.write()
        print(ac, name, record['status'], record['reason'], flush=True)

    def start(self, t, example):
        t.launch(self.args.sigma, 'examples/task-' + example + '.fs')

    def fresh(self, t):
        self.start(t, 'search')
        t.expect(r'T1:', t.start)
        t.send('b')
        t.expect(r'result generation=2 matches=0 stored=0', t.start)
        t.send('q')
        return t.finish()

    def end(self, t, interrupted=False):
        start = t.start
        recovery = t.finish(interrupted)
        output = t.text[start:]
        if 'result generation=' in output:
            generations(output)
        # A fresh sigma in the same terminal verifies input after every scenario.
        fresh = self.fresh(t)
        return dict(recovery=recovery, fresh_sigma=fresh, output_before_exit=output)

    def path(self, t, mode):
        self.start(t, 'path'); t.expect('G1:', t.start)
        if mode == 'replace':
            t.send('nnn')
            t.expect(r'result generation=4 vertices=95\s', t.start)
        elif mode == 'alternate':
            for gen in range(2, 5):
                t.send('n'); t.expect(r'result generation=%d ' % gen, t.start)
                start = len(t.text); t.send('x'); t.expect('input=120', start)
        else:
            t.send('n'); t.expect(r'result generation=2 ', t.start)
        text = t.text[t.start:]; rows = generations(text)
        t.send('nq' if mode == 'alternate' else 'q')
        result = self.end(t)
        latest_only(result['output_before_exit'], 'path')
        result['generations'] = rows
        if mode == 'alternate':
            result.update(reason='generations/input/exit/recovery passed; running-phase quit is checked separately by the unending fixture')
        return result

    def search(self, t):
        self.start(t, 'search'); t.expect('T1:', t.start)
        t.send('b'); t.expect(r'result generation=2 matches=0 stored=0', t.start)
        t.send('a'); t.expect(r'result generation=3 matches=1048576 stored=1000', t.start)
        rows = generations(t.text[t.start:]); t.send('q')
        result = self.end(t); result['generations'] = rows
        latest_only(result['output_before_exit'], 'search')
        return result

    def native(self, t, example):
        frame_count = self.args.native_frame_limit
        source = 'examples/task-native-' + example + '.fs'
        if example != 'bye':
            wrapper = self.root / ('native-' + example + '.fs')
            wrapper.write_bytes((('-1' if self.args.native_baseline else '0') + ' CONSTANT NV-BASELINE\n'
                                 + str(frame_count) + ' CONSTANT NV-FRAME-LIMIT\nS" ' + source + '" INCLUDED\n').encode('utf-8'))
            source = str(wrapper.resolve())
        t.launch(self.args.sigma, source)
        if example == 'bye':
            t.expect('NATIVE-BYE active:', t.start)
            t.snapshot('audio-window-worker-active')
            t.send('q')
            t.expect('NATIVE-BYE running; BYE owns reclamation', t.start)
            result = self.end(t)
            result.update(status='unverified', reason='running task at BYE, exit and terminal recovery recorded; native resource closure and audible stop require observation',
                verification='Claude inspects native process/thread/window/audio lifetime; human records that tone sounded and stopped, on each OS (1397-1399)')
            return result
        # Only the observer waits. The fixture continues drawing at its own pace.
        keys = list('nfnnnn' if example == 'path' else 'bfabab')
        replay = None
        if self.args.native_baseline:
            document = json.loads(self.args.native_baseline_schedule.read_text(encoding='utf-8'))
            candidate = next(c for c in document['results']['AC-25']['cases']
                             if c['name'] == 'native-' + example)
            if (candidate.get('native_baseline') is not False or candidate.get('status') == 'failed'
                    or candidate.get('frame_count') != frame_count
                    or 7 not in candidate.get('drawn_generations', [])):
                raise AssertionError('baseline requires successful load evidence with the same frame limit')
            replay = candidate['input_schedule']
            if ([r['key'] for r in replay] != keys
                    or any(not isinstance(r['frame'], int) or not 0 < r['frame'] < frame_count for r in replay)
                    or any(a['frame'] >= b['frame'] for a, b in zip(replay, replay[1:]))):
                raise AssertionError('invalid load input schedule')
        schedule = []
        deadline = time.monotonic() + t.timeout
        while len(schedule) < len(keys):
            output = t.text[t.start:]
            draws_seen = list(re.finditer(r'NATIVE-DRAW generation=(\d+) frame=(\d+) requested=(\d+)\s', output))
            if draws_seen:
                last = draws_seen[-1]
                generation, frame = int(last[1]), int(last[2])
                index = len(schedule)
                if replay is not None:
                    target = replay[index]['frame']
                    if frame > target + 2:
                        raise AssertionError('baseline observer exceeded send tolerance: target %d, saw %d' % (target, frame))
                    ready = frame >= target
                else:
                    expected = (1, 2, 2, 4, 5, 6)[index]
                    ready = generation == expected
                    if index == 2:
                        failure = re.search(r'NATIVE-FAILED retained=2\b', output)
                        ready = ready and failure is not None and failure.start() < last.start()
                if frame >= frame_count:
                    raise AssertionError('frame limit reached before input sequence completed')
                if ready:
                    t.send(keys[index])
                    schedule.append(dict(frame=frame, key=keys[index]))
                    if replay is not None:
                        schedule[-1].update(planned_frame=target, frame_delta=frame - target)
                    deadline = time.monotonic() + t.timeout
                    continue
            if time.monotonic() >= deadline:
                raise AssertionError('hang guard: native schedule did not advance')
            t.pump(0.002)
        result = self.end(t)
        draws = re.findall(r'NATIVE-DRAW generation=(\d+) frame=(\d+) requested=(\d+)', result['output_before_exit'])
        if [int(row[1]) for row in draws] != list(range(1, frame_count + 1)):
            raise AssertionError('native frame sequence does not match fixed schedule')
        drawn = [int(row[0]) for row in draws]
        if 1 not in drawn or (not self.args.native_baseline and
                not re.search(r'NATIVE-FAILED retained=2\b', result['output_before_exit'])):
            raise AssertionError('initial result or failure retention was not observed')
        if self.args.native_baseline and any(int(g) > 1 or int(requested) != 1 for g, _, requested in draws):
            raise AssertionError('baseline advanced beyond initial generation')
        if drawn != sorted(drawn) or 3 in drawn or (not self.args.native_baseline and (not any(int(g) == 7 and int(f) < frame_count for g, f, _ in draws))):
            raise AssertionError('stale, failed or missing final generation: %r' % drawn)
        output = result['output_before_exit']
        received = [dict(generation=int(g), frame=int(f), key=chr(int(k)))
                    for g, f, k in re.findall(r'NATIVE-INPUT generation=(\d+) frame=(\d+) key=(\d+)', output)]
        endpoints = [json.loads(line[len('PAINTTRACE '):]) for line in output.splitlines()
                     if line.startswith('PAINTTRACE ')]
        input_count = sum(row.get('event') == 'input' for row in endpoints)
        if [row['key'] for row in received] != keys or input_count != len(keys):
            raise AssertionError('native received keys/input endpoints do not match schedule')
        if replay is not None and (len(draws) != candidate['frame_count']
                or input_count != candidate['input_count']
                or ''.join(keys) != candidate['input_sequence']):
            raise AssertionError('baseline/load frame count, input count or key sequence mismatch')
        result.update(drawn_generations=drawn, frame_count=len(draws), input_count=input_count,
            input_schedule=schedule, received_inputs=received, native_frame_limit=frame_count,
            baseline_schedule_source=str(self.args.native_baseline_schedule) if replay is not None else None,
            input_sequence=''.join(keys), native_baseline=self.args.native_baseline, status='unverified',
            reason='result-driven load / replayed baseline schedule recorded; physical screen and paired rendering conditions require review',
            verification='Compare baseline/load counts and input_sequence; human verifies retained display and source/build/backend/rendering conditions before timing comparison.')
        return result

    def integration(self, t):
        t.launch(self.args.sigma, 'tests/scripts/check-task-console.fs')
        for marker, key in [('active', 'r'), ('replaced', 'c'), ('bye-active', 'b')]:
            t.expect(r'(?m)^' + marker + r'\s*$', t.start); t.send(key)
        result = self.end(t)
        for marker in ('frame=r', 'frame=c', 'frame=b', 'cancelled', 'released'):
            if marker not in result['output_before_exit'] + t.text:
                raise AssertionError('missing ' + marker)
        if Path('.work/task-console.tmp').exists():
            raise AssertionError('scratch file remains')
        return result

    def checksum(self, t):
        self.start(t, 'checksum')
        t.expect(r'chunk=1 checksum=%d\s' % (sum(Path('LICENSE').read_bytes()) & 0xffffffff), t.start)
        return self.end(t)

    def search_input_a(self, t):
        self.start(t, 'search'); t.expect('T1:', t.start)
        t.send('a')
        t.expect(r'result generation=2 matches=1048576 stored=1000', t.start)
        t.send('q')
        result = self.end(t)
        latest_only(result['output_before_exit'], 'search')
        return result

    def quit_case(self, t, example, key):
        if example == 'running':
            return self.running_quit(t, key)
        t.launch(self.args.sigma, str(self.large_checksum))
        t.expect(r'chunk=1 checksum=8355840\s', t.start)
        if t.exited():
            raise AssertionError('large checksum exited before quit')
        t.send(key)
        return self.end(t, key == '\x03')

    def concurrent(self, t):
        other = Terminal(self.root / 'ac20-checksum', self.args.timeout)
        try:
            self.start(t, 'search'); t.expect('T1:', t.start)
            other.launch(self.args.sigma, str(self.large_checksum))
            overlap = bool(t.owned and other.owned and not t.exited() and not other.exited())
            gen = 1
            for key in 'ababab':
                gen += 1; t.send(key)
                t.expect(r'result generation=%d matches=%d stored=%d' %
                         (gen, 1048576 if key == 'a' else 0, 1000 if key == 'a' else 0), t.start)
            other.expect(r'chunk=1 checksum=%d\s' % (8355840), other.start)
            overlap = overlap and not other.exited()
            checksum_q = not other.exited()
            if checksum_q:
                other.send('q')
            other_result = self.end(other)
            t.collection_errors.extend(other.collection_errors)
            rows = generations(t.text[t.start:]); t.send('q'); result = self.end(t)
            result.update(checksum=other_result, generations=rows, overlap_observed=overlap,
                          checksum_q_sent=checksum_q)
            if not overlap or not checksum_q:
                result.update(status='unverified', reason='search a/b and checksum output passed in separate ptys; checksum auto-exited before q/continuous overlap could be confirmed', verification='On each OS prepare a checksum workload that continues until quit, then confirm progress in both ptys and send q before it exits (1395, 1397-1399)')
            return result
        finally:
            other.close()
            t.collection_errors.extend(other.collection_errors)
            if other.forced_cleanup:
                raise AssertionError('second pty workload required forced cleanup')

    def composite(self, t, paint=False):
        t.launch(self.args.sigma, 'tests/scripts/check-task-wait-paint-real.fs' if paint else 'tests/scripts/check-task-wait-real.fs')
        t.expect('AC18-INPUT-READY', t.start)
        t.send('x')
        t.expect('AC18-INTERRUPT-READY', t.start)
        t.send('\x03')
        t.expect('AC18-THROW-DETACHED', t.start)
        if paint:
            t.expect('AC18-CLOSE-WINDOW-NOW', t.start)
            print('AC-18: close the red native window now; Claude/user must record visual observation.', flush=True)
        t.expect('AC18-DETACH-REUSE=80 PASS', t.start)
        result = self.end(t)
        if Path('.work/ac18-real.tmp').exists():
            raise AssertionError('AC18 scratch file remains')
        result.update(providers=['PTY/ConPTY input', 'temporary regular file read', 'task success', 'clock'] + (['native paint and user window close'] if paint else []),
                      simultaneous_events=5 if paint else 4, detach_reuse_calls=80,
                      limitation='Public observations: repeated registration, consumed input, closed file HANDLE and shell recovery; Ctrl+C THROW followed by re-registration; internal reference counts remain covered by Zig tests.')
        return result

    def fairness(self, t):
        t.launch(self.args.sigma, 'tests/scripts/check-task-fair-real.fs')
        t.expect('FAIR-INPUT-READY', t.start)
        observations = []
        output_origin = len(t.output)
        previous = None
        for key in 'abab':
            until = time.monotonic() + self.args.fair_window
            while time.monotonic() < until:
                t.pump(min(0.05, max(0, until - time.monotonic())))
                if t.exited():
                    raise AssertionError('fairness fixture exited before quit')
            start = len(t.text)
            t.send(key)
            match = t.expect(r'FAIR seq=(\d+) search=(\d+) checksum=(\d+) input=(\d+) file-bytes=(\d+)\s', start)
            row = dict(zip(('seq', 'search', 'checksum', 'input', 'file_bytes'), map(int, match.groups())))
            row.update(time=utc(), output_bytes=len(t.output) - output_origin, process_ids=sorted(t.owned))
            if previous is not None:
                for field in ('search', 'checksum', 'input', 'file_bytes', 'output_bytes'):
                    if row[field] <= previous[field]:
                        raise AssertionError('no progress in observed interval: ' + field)
            observations.append(row)
            previous = row
        t.send('q'); t.expect('FAIR-PASS', t.start)
        result = self.end(t)
        result.update(observations=observations, observation_window_seconds=self.args.fair_window,
                      reason='T1, I1, file reads, terminal input and output progressed in each recorded interval in one sigma process; no throughput/latency threshold',
                      limitation='Finite observation only; queue-full retry and arbitrary schedules are outside this fixture.')
        save(t.directory / 'progress.json', observations)
        return result

    def paint(self):
        env = dict(os.environ, FORTHZ_PAINT_SMOKE='1')
        command = ['zig', 'build', 'runtime-test', '--summary', 'all']
        record = dict(name='native-paint-supplement', evidence='supplement to pseudo-terminal acceptance; runtime log only',
                      command=command, environment={k: env[k] for k in ('FORTHZ_PAINT_SMOKE', 'DISPLAY') if k in env})
        path = self.root / 'native-paint.log'
        try:
            with path.open('wb') as log:
                run = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=self.args.paint_timeout)
            record['build_exit_code'] = run.returncode
            # Zig's build protocol suppresses individual successful test names.
            # Stage the identical runtime test artifact and run it without the
            # build protocol to obtain explicit named OK/SKIP lines.
            if run.returncode == 0:
                stage = ['zig', 'build', 'runtime-check', '--summary', 'all']
                arch = {'AMD64': 'x86_64', 'arm64': 'aarch64', 'ARM64': 'aarch64'}.get(platform.machine(), platform.machine())
                system = {'Windows': 'windows', 'Darwin': 'macos', 'Linux': 'linux'}[platform.system()]
                binary = Path('zig-out/runtime-tests') / (arch + '-' + system) / ('test.exe' if os.name == 'nt' else 'test')
                record['named_result_commands'] = [stage, [str(binary.resolve())]]
                with path.open('ab') as log:
                    log.write(b'\n--- Stage identical runtime tests for named results ---\n'); log.flush()
                    staged = subprocess.run(stage, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=self.args.paint_timeout)
                    record['stage_exit_code'] = staged.returncode
                    if staged.returncode == 0:
                        log.write(b'\n--- Standalone runtime tests (named results) ---\n'); log.flush()
                        run = subprocess.run([str(binary.resolve(strict=True))], env=env, stdout=log, stderr=subprocess.STDOUT, timeout=self.args.paint_timeout)
                    else:
                        run = staged
            text = path.read_text(encoding='utf-8', errors='replace')
            lines = [line for line in text.splitlines() if 'public paint real native window wait (opt in)' in line]
            record.update(exit_code=run.returncode, matching_lines=lines)
            if any(re.search(r'\bOK\b', line) and not re.search('skip', line, re.I) for line in lines) and run.returncode == 0:
                record.update(status='passed', reason='named real native window test explicitly OK, not skipped; physical screen unverified')
            elif run.returncode != 0:
                record.update(status='failed', reason='runtime build or tests failed; inspect native-paint.log')
            elif any(re.search('skip', line, re.I) for line in lines) or not lines:
                record.update(status='unverified', reason='named test skipped or no explicit named OK in runtime log; inspect native-paint.log')
            else:
                record.update(status='failed', reason='native paint runtime test failed; inspect native-paint.log')
        except (OSError, subprocess.TimeoutExpired) as exc:
            record.update(status='unverified', reason=str(exc), verification='Claude reruns named paint test on native backend; user observes window, tasks 1394 and 1397-1399')
        self.results['AC-18']['cases'].append(record)
        self.write()
        print('AC-18 paint:', record['status'], record['reason'], flush=True)

    def write(self):
        for entry in self.results.values():
            cases = entry['cases']
            entry['status'] = 'failed' if any(c['status'] == 'failed' for c in cases) else 'unverified'
            entry['reason'] = ('one or more pseudo-terminal subcases failed; ' if entry['status'] == 'failed' else
                               'available pseudo-terminal subcases recorded; full AC remains unverified: ') + '; '.join(entry['unverified'])
        for entry in self.results.values():
            for case in entry['cases']:
                if case['status'] == 'unverified':
                    case.setdefault('verification', '; '.join(entry['unverified']))
        save(self.root / 'results.json', dict(metadata=self.metadata, results=self.results))

    def run(self):
        self.metadata = dict(started=utc(), os=platform.platform(), python=platform.python_version(),
            terminal='ConPTY' if os.name == 'nt' else 'POSIX pty', shell='cmd.exe /d /v:on /q in non-breakaway Job' if os.name == 'nt' else 'direct sigma under unreaped session supervisor',
            sigma=str(self.args.sigma), sigma_sha256=hashlib.sha256(self.args.sigma.read_bytes()).hexdigest(),
            runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            source_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
            source_status=subprocess.check_output(['git', 'status', '--short'], text=True),
            evidence='pseudo-terminal, not physical terminal/screen acceptance', timing='hang guards only; no latency pass/fail')
        self.write()
        if self.args.native_paint:
            for example in ('path', 'search'):
                self.case('AC-25', 'native-' + example, lambda t, ex=example: self.native(t, ex))
            if not self.args.native_baseline:
                self.case('AC-05', 'native-bye', lambda t: self.native(t, 'bye'))
        if self.args.cases == 'native':
            self.metadata['finished'] = utc(); self.write()
            print('Results:', self.root / 'results.json')
            return int(any(r['status'] == 'failed' for r in self.results.values()))
        self.case('AC-18', 'ac18-real-composite', self.composite)
        self.case('AC-19', 'ac19-same-process', self.fairness)
        self.case('AC-20', 'ac20-same-process', self.fairness)
        if self.args.native_paint:
            self.case('AC-18', 'ac18-real-paint-close', lambda t: self.composite(t, paint=True))
            self.paint()
        else:
            self.results['AC-18']['cases'].append(dict(name='native-paint-close', status='unverified',
                reason=self.args.display_reason, verification='Claude runs --native-paint in a display-enabled session (1397-1399), observes native window and close; opt-in fixture combines paint with kinds 1-4; record red window and manual close.'))
        if self.args.cases == 'mixed':
            self.metadata['finished'] = utc(); self.write()
            print('Results:', self.root / 'results.json')
            return int(any(r['status'] == 'failed' for r in self.results.values()))
        self.case('AC-02', 'ac02-path', lambda t: self.path(t, 'alternate'))
        self.case('AC-05', 'ac05-console', self.integration)
        self.case('AC-18', 'ac18-path', lambda t: self.path(t, 'normal'))
        self.case('AC-18', 'ac18-search', self.search_input_a)
        self.case('AC-18', 'ac18-checksum', self.checksum)
        self.case('AC-20', 'ac20-search', self.concurrent)
        for example in ('running', 'checksum'):
            for label, key in [('q', 'q'), ('ctrl-c', '\x03')]:
                self.case('AC-24', 'ac24-' + example + '-' + label,
                          lambda t, ex=example, k=key: self.quit_case(t, ex, k))
        self.case('AC-02', 'ac02-response', self.response)
        for name in ('G1-open', 'G1-wall', 'G1-snake', 'G2', 'T1', 'I1'):
            self.case('AC-25', 'ac25-max-' + name, lambda t, n=name: self.workload(t, n))
        self.case('AC-25', 'ac25-path', lambda t: self.path(t, 'replace'))
        self.case('AC-25', 'ac25-search', self.search)
        self.metadata['finished'] = utc(); self.write()
        print('Results:', self.root / 'results.json')
        return int(any(r['status'] == 'failed' for r in self.results.values()))


def self_test():
    import ast
    import io
    logger = Terminal.__new__(Terminal)
    logger.events = io.StringIO()
    logger.event('observation', time='observed')
    logger.event('receive', _time='received', time='observed')
    logged = [json.loads(line) for line in logger.events.getvalue().splitlines()]
    assert [row['time'] for row in logged] == ['observed', 'received']
    ast.parse(Path(__file__).read_text(encoding='utf-8'), feature_version=(3, 9))
    assert generations('result generation=1\nresult generation=4 vertices=95') == [1, 4]
    for value in ('', 'result generation=4\nresult generation=2'):
        try:
            generations(value)
        except AssertionError:
            pass
        else:
            raise AssertionError('invalid generation sequence accepted')
    assert clean('\x1b[31mhello\r\n\x1b[0m') == 'hello\n'
    assert json.loads(json.dumps(serial_attrs([1, [b'\x03', 0]]))) == [1, [{'hex': '03'}, 0]]
    assert clean('EXIT_abc=0\x1b[7;1Hprompt') == 'EXIT_abc=0\nprompt'
    assert clean('NATIVE-DRAW\x1b[1Cgeneration=1 frame=37') == 'NATIVE-DRAW generation=1 frame=37'
    assert clean('a\x1b[Cb\x1b[3Cc') == 'a b   c'
    latest_only('input=110\ninput=110\ninput=110\nresult generation=4 vertices=95', 'path')
    try:
        latest_only('input=110\nresult generation=1', 'path')
    except AssertionError:
        pass
    else:
        raise AssertionError('stale result accepted')
    report = 'speed 38400 baud;\n-isig echo;'
    notice = 'sh: child setpgid (1 to 2): Operation not permitted'
    assert stty_report(notice + '\n' + report) == report
    assert stty_report(report + '\n' + notice) == report
    assert stty_report(report.replace('echo', '-echo')) != report
    assert stty_report(report + ' -pendin') == stty_report(report + ' pendin')
    for pendin in (0x20000000, 0x4000):
        before = {'termios': [1, 2, 3, 1483, 5, 6, [{'hex': '03'}]]}
        after = {'termios': [1, 2, 3, 1483 | pendin, 5, 6, [{'hex': '03'}]]}
        assert comparable_state(before, pendin) == comparable_state(after, pendin)
        after['termios'][3] ^= 8  # ECHO must still matter.
        assert comparable_state(before, pendin) != comparable_state(after, pendin)
        assert before['termios'][3] == 1483
    table = {1: {'ppid': 0}, 2: {'ppid': 1}, 3: {'ppid': 2}, 4: {'ppid': 0}}
    assert descendants(table, 1) == [1, 2, 3]
    class FakeTTY:
        FIONREAD, ICANON, ECHO, VMIN, VTIME, TCSANOW = 100, 2, 8, 0, 1, 0
        original = [1, 2, 3, 0x2000000a, 5, 6, [1, 0]]
        attrs = original
        def tcgetattr(self, fd):
            return self.attrs[:6] + [list(self.attrs[6])]
        def tcsetattr(self, fd, when, attrs):
            self.attrs = attrs
    class FakeIO:
        F_GETFL, F_SETFL = 1, 2
        flags = 0
        O_NONBLOCK = 2048
        def fcntl(self, fd, command, value=None):
            if command == self.F_GETFL:
                return self.flags
            self.flags = value
        def ioctl(self, fd, command, value):
            return struct.pack('i', 0 if fake_tty.attrs[3] & fake_tty.ICANON else 1)
    fake_tty, fake_io = FakeTTY(), FakeIO()
    observed = pending_input(9, fake_tty, fake_io, lambda fd, count: b'q', fake_io.O_NONBLOCK)
    assert observed['fionread'] == 0 and observed['noncanonical_fionread'] == 1
    assert observed['hex'] == '71' and observed['termios_before_observation'][3] == 0x2000000a
    assert fake_tty.attrs == fake_tty.original and fake_io.flags == 0
    def failed_read(fd, count):
        raise OSError('injected input read failure')
    try:
        pending_input(9, fake_tty, fake_io, failed_read, fake_io.O_NONBLOCK)
    except OSError:
        pass
    else:
        raise AssertionError('read failure hidden')
    assert fake_tty.attrs == fake_tty.original and fake_io.flags == 0
    root = Path('.work/acceptance/self-test-' + uuid.uuid4().hex)
    root.mkdir(parents=True)
    # Model a slow worker (80 frames per result), including asynchronous failure.
    # This regression would never reach generation 1 with the old 30-frame keys.
    from types import SimpleNamespace

    class NativeModel:
        start = 0
        timeout = 2

        def __init__(self, baseline=False, initial_due=80, observation_step=1):
            self.frame = self.generation = 0
            self.requested = 1
            self.due = initial_due
            self.observation_step = observation_step
            self.baseline = baseline
            self.buffer = ''

        def launch(self, *_):
            pass

        @property
        def text(self):
            return self.buffer

        def pump(self, _):
            for _ in range(self.observation_step):
                self.tick()

        def tick(self):
            self.frame += 1
            if self.frame == self.due:
                if self.requested == 3:
                    self.buffer += 'NATIVE-FAILED retained=2\n'
                else:
                    self.generation = self.requested
            self.buffer += 'NATIVE-DRAW generation=%d frame=%d requested=%d\n' % (
                self.generation, self.frame, self.requested)

        def send(self, key):
            next_generation = self.requested + 1
            if not self.baseline:
                self.requested = next_generation
            self.buffer += 'NATIVE-INPUT generation=%d frame=%d key=%d\n' % (
                next_generation, self.frame, ord(key))
            self.buffer += 'PAINTTRACE {"event":"input"}\n'
            if not self.baseline:
                self.due = self.frame + 80

    model_runner = Runner.__new__(Runner)
    model_runner.root = root
    model_runner.args = SimpleNamespace(native_frame_limit=1200, native_baseline=False,
                                        native_baseline_schedule=None, sigma=Path('unused'))

    def model_end(t):
        while t.frame < model_runner.args.native_frame_limit:
            t.pump(0)
        return dict(output_before_exit=t.text)

    model_runner.end = model_end
    for example in ('path', 'search'):
        load = model_runner.native(NativeModel(), example)
        assert [r['frame'] for r in load['input_schedule']] == [80, 160, 240, 320, 400, 480]
        assert load['frame_count'] == 1200 and load['input_count'] == 6
        schedule_path = root / 'model-results.json'
        save(schedule_path, dict(results={'AC-25': {'cases': [dict(load, name='native-' + example)]}}))
        model_runner.args.native_baseline = True
        model_runner.args.native_baseline_schedule = schedule_path
        baseline = model_runner.native(NativeModel(baseline=True), example)
        assert [r['frame'] for r in baseline['input_schedule']] == [r['frame'] for r in load['input_schedule']]
        assert all(r['frame_delta'] == 0 for r in baseline['input_schedule'])
        # First key precedes the slower initial result; batched output skips frame 80.
        delayed = model_runner.native(NativeModel(baseline=True, initial_due=86, observation_step=3), example)
        assert delayed['input_schedule'][0]['frame'] == 81
        assert delayed['input_schedule'][0]['frame_delta'] == 1
        assert 1 in delayed['drawn_generations']
        assert set(delayed['drawn_generations']) == {0, 1}
        assert delayed['frame_count'] == load['frame_count']
        assert delayed['input_count'] == load['input_count']
        try:
            model_runner.native(NativeModel(baseline=True, observation_step=7), example)
        except AssertionError as exc:
            assert 'exceeded send tolerance' in str(exc)
        else:
            raise AssertionError('send delay above two frames accepted')
        assert baseline['frame_count'] == load['frame_count']
        assert baseline['input_count'] == load['input_count']
        model_runner.args.native_baseline = False
        model_runner.args.native_baseline_schedule = None
    model_runner.args.native_frame_limit = 550
    try:
        model_runner.native(NativeModel(), 'path')
    except AssertionError as exc:
        assert 'missing final generation' in str(exc)
    else:
        raise AssertionError('missing generation 7 before cap was accepted')
    outside = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(300)'])
    terminal = None
    try:
        terminal = Terminal(root / 'owned', 15)
        script = root / 'child.py'
        script.write_text("import subprocess, sys, time\nsubprocess.Popen([sys.executable, '-c', 'import time; time.sleep(300)'])\nprint('OWNED-CHILD-READY', flush=True)\ntime.sleep(300)\n", encoding='utf-8')
        terminal.launch(Path(sys.executable), str(script.resolve()))
        terminal.expect('OWNED-CHILD-READY', terminal.start)
        assert len(terminal.owned_ids()) >= 3, 'owned grandchild not present'
        assert outside.pid not in terminal.owned_ids(), 'outside dummy entered containment'
        terminal.close()
        assert terminal.forced_cleanup, 'live workload was not marked forced cleanup'
        assert outside.poll() is None, 'outside dummy was stopped by cleanup'
        if os.name != 'nt':
            residual_test = Terminal(root / 'residual-input', 15)
            done = (root / 'residual-done').resolve()
            try:
                script.write_text('import time\nfrom pathlib import Path\nprint("RESIDUAL-READY",flush=True)\nwhile not Path(' + repr(str(done)) + ').exists(): time.sleep(0.01)\n', encoding='utf-8')
                residual_test.launch(Path(sys.executable), str(script.resolve()))
                residual_test.expect('RESIDUAL-READY', residual_test.start)
                residual_test.send('q')
                done.touch()
                recovery = residual_test.finish()
                assert recovery['residual_input']['hex'] == '71', recovery
                assert outside.poll() is None
            finally:
                residual_test.close()
        # A child created after the launch snapshot must fail natural recovery.
        late = Terminal(root / 'late-child', 15)
        try:
            script.write_text("import subprocess, sys, time\ntime.sleep(0.3)\nsubprocess.Popen([sys.executable, '-c', 'import time; time.sleep(300)'])\nprint('LATE-CHILD', flush=True)\n", encoding='utf-8')
            late.launch(Path(sys.executable), str(script.resolve()))
            late.expect('LATE-CHILD', late.start)
            try:
                late.finish()
            except AssertionError as exc:
                assert 'owned processes remain' in str(exc), str(exc)
            else:
                raise AssertionError('late surviving child counted as reclaimed')
        finally:
            late.close()
        # Collection failure is missing evidence, never permission to kill PIDs.
        original_table = globals()['process_table']
        collector = Terminal(root / 'collector-failure', 15)
        try:
            def unavailable():
                raise OSError('injected collection failure')
            globals()['process_table'] = unavailable
            try:
                collector.snapshot('injected-failure')
            except CollectionMissing:
                pass
            else:
                raise AssertionError('collector failure accepted')
            collector.close()
            assert outside.poll() is None, 'outside dummy stopped on collector failure'
        finally:
            globals()['process_table'] = original_table
            collector.close()
        if os.name == 'nt':
            # Assignment failure must never resume the atomically contained shell.
            original_assign, original_resume = K.AssignProcessToJobObject, K.ResumeThread
            resumed = []
            try:
                def reject(*args):
                    ctypes.set_last_error(5)
                    return False
                K.AssignProcessToJobObject = reject
                K.ResumeThread = lambda *args: resumed.append(True) or 0
                try:
                    Terminal(root / 'rejected-assignment', 5)
                except OSError:
                    pass
                else:
                    raise AssertionError('assignment failure accepted')
                assert not resumed, 'failed assignment resumed shell'
                assert outside.poll() is None, 'outside dummy stopped on assignment failure'
            finally:
                K.AssignProcessToJobObject, K.ResumeThread = original_assign, original_resume
        save(root / 'self-test.json', dict(outside_pid=outside.pid, outside_alive=outside.poll() is None,
                                         forced_cleanup=terminal.forced_cleanup, platform=platform.platform(),
                                         runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                                         portable_posix_checks=['PENDIN masking and other flags', 'descendant tree',
                                             'signals restricted to anchored process group', 'canonical residual input and restoration on read error'],
                                         native_posix_execution=os.name != 'nt',
                                         escaped_subreaper_test=False,
                                         escaped_descendants='unverified; observe with native lifetime tracing; never signal outside anchored group'))
    finally:
        if terminal:
            terminal.close()
        # Popen retains the direct child's identity; no discovered PID is used.
        outside.terminate()
        outside.wait(timeout=10)
    print('Grammar/expectations, contained child/grandchild cleanup, outside dummy survival and startup failure checks passed:', root)
    if os.name == 'nt':
        print('POSIX execution unverified; Claude must run self-test on Linux/macOS')


def console_state():
    get_handle = proto('GetStdHandle', HANDLE, [W.DWORD])
    get_mode = proto('GetConsoleMode', W.BOOL, [HANDLE, ctypes.POINTER(W.DWORD)])
    states = {}
    for name, number in [('input', -10), ('output', -11)]:
        mode = W.DWORD()
        ok = get_mode(get_handle(number & 0xffffffff), ctypes.byref(mode))
        states[name] = {'mode': mode.value} if ok else {'error': ctypes.get_last_error()}
    print('CONSOLE_STATE=' + json.dumps(states), flush=True)


def main():
    if '--console-state' in sys.argv:
        console_state(); return 0
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sigma', type=Path, default=Path('zig-out/bin/sigma.exe' if os.name == 'nt' else 'zig-out/bin/sigma'))
    parser.add_argument('--output', type=Path, help='new evidence directory (must not exist)')
    parser.add_argument('--timeout', type=float, default=120, help='per-expect hang guard seconds, not acceptance limit')
    parser.add_argument('--paint-timeout', type=float, default=1800, help='runtime-test hang guard seconds')
    parser.add_argument('--cases', choices=('all', 'mixed', 'native'), default='all', help='native: G1/T1 paint and audio/window BYE only; mixed: AC-18/19/20 real providers only')
    parser.add_argument('--fair-window', type=float, default=2, help='seconds per progress observation window; no speed threshold')
    parser.add_argument('--native-paint', action='store_true', help='opt in to five-source native fixture (human closes window) and supplementary test; requires usable screen')
    parser.add_argument('--native-baseline', action='store_true', help='native path/search only: stop task submission after initial result; same rendering loop')
    parser.add_argument('--native-frame-limit', type=int, default=1200, help='same fixed frame cap for load and baseline (default: 1200)')
    parser.add_argument('--native-baseline-schedule', type=Path, help='load results.json to replay; required for baseline')
    parser.add_argument('--display-reason', default='Native display not requested; rerun with --native-paint in a display-enabled session', help='record why physical paint/close is unverified')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.fair_window <= 0:
        parser.error("--fair-window must be positive")
    if args.self_test:
        self_test(); return 0
    if args.native_baseline and (not args.native_paint or args.cases != 'native'):
        parser.error('--native-baseline requires --native-paint --cases native')
    if args.native_frame_limit <= 0:
        parser.error('--native-frame-limit must be positive')
    if args.native_baseline and not args.native_baseline_schedule:
        parser.error('baseline cannot be compared without load evidence; run load first and pass --native-baseline-schedule results.json')
    if args.native_baseline_schedule and not args.native_baseline:
        parser.error('--native-baseline-schedule requires --native-baseline')
    if args.cases == 'native' and not args.native_paint:
        parser.error('--cases native requires --native-paint')
    args.sigma = args.sigma.resolve(strict=True)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    root = args.output or Path('.work/acceptance') / ('manual-' + platform.system().lower()) / stamp
    root.mkdir(parents=True, exist_ok=False)
    Path('.work').mkdir(exist_ok=True)
    return Runner(args, root).run()


if __name__ == '__main__':
    raise SystemExit(main())

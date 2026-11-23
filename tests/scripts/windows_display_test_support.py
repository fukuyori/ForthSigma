"""Bounded Windows display integration children; only owned jobs are terminated."""
import ctypes
from ctypes import wintypes
import hashlib
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import time

if not __debug__:
    raise SystemExit('Run these acceptance checks without Python -O')

if sys.platform != 'win32':
    raise SystemExit('Windows is required')

# Put Sigma in a private job before releasing its initial KEY gate. Children (wish)
# remain in that job and are collected even if Sigma fails or times out.
kernel = ctypes.WinDLL('kernel32', use_last_error=True)
from ctypes import wintypes
kernel.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
kernel.CreateJobObjectW.restype = wintypes.HANDLE
kernel.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
kernel.AssignProcessToJobObject.restype = wintypes.BOOL
kernel.TerminateJobObject.argtypes = [wintypes.HANDLE, wintypes.UINT]
kernel.TerminateJobObject.restype = wintypes.BOOL
kernel.CloseHandle.argtypes = [wintypes.HANDLE]
kernel.CloseHandle.restype = wintypes.BOOL


class BasicLimits(ctypes.Structure):
    _fields_ = [('process_time', ctypes.c_int64), ('job_time', ctypes.c_int64),
                ('flags', wintypes.DWORD), ('min_working', ctypes.c_size_t),
                ('max_working', ctypes.c_size_t), ('active_limit', wintypes.DWORD),
                ('affinity', ctypes.c_size_t), ('priority', wintypes.DWORD),
                ('scheduling', wintypes.DWORD)]


class ExtendedLimits(ctypes.Structure):
    _fields_ = [('basic', BasicLimits), ('io', ctypes.c_uint64 * 6),
                ('process_memory', ctypes.c_size_t), ('job_memory', ctypes.c_size_t),
                ('peak_process', ctypes.c_size_t), ('peak_job', ctypes.c_size_t)]


class Accounting(ctypes.Structure):
    _fields_ = [('times', ctypes.c_int64 * 4), ('faults', wintypes.DWORD),
                ('total', wintypes.DWORD), ('active', wintypes.DWORD),
                ('terminated', wintypes.DWORD)]


kernel.SetInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
kernel.SetInformationJobObject.restype = wintypes.BOOL
kernel.QueryInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD, ctypes.c_void_p]
kernel.QueryInformationJobObject.restype = wintypes.BOOL
kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
kernel.OpenProcess.restype = wintypes.HANDLE


def create_job():
    job = kernel.CreateJobObjectW(None, None)
    if not job:
        raise ctypes.WinError(ctypes.get_last_error())
    limits = ExtendedLimits()
    limits.basic.flags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    if not kernel.SetInformationJobObject(job, 9, ctypes.byref(limits), ctypes.sizeof(limits)):
        error = ctypes.WinError(ctypes.get_last_error())
        kernel.CloseHandle(job)
        raise error
    return job


def assign_job(job, process):
    handle = kernel.OpenProcess(0x101, False, process.pid)  # SET_QUOTA | TERMINATE
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        if not kernel.AssignProcessToJobObject(job, handle):
            raise ctypes.WinError(ctypes.get_last_error())
    finally:
        kernel.CloseHandle(handle)


def assert_empty_job(job):
    deadline = time.monotonic() + 2
    while True:
        accounting = Accounting()
        if not kernel.QueryInformationJobObject(job, 1, ctypes.byref(accounting), ctypes.sizeof(accounting), None):
            raise ctypes.WinError(ctypes.get_last_error())
        if not accounting.active:
            return
        if time.monotonic() >= deadline:
            raise AssertionError(('Child processes survived Sigma exit', accounting.active))
        time.sleep(.01)


def binary_identity(binary):
    path = binary.resolve()
    data = path.read_bytes()
    return dict(path=str(path), sha256=hashlib.sha256(data).hexdigest(), bytes=len(data))

def invoke(binary, source=None, cwd=None):
    job = create_job()
    process = None
    try:
        arguments = [str(binary.resolve())]
        if source is not None:
            arguments += ['-e', 'KEY DROP ' + source]
        process = subprocess.Popen(arguments, cwd=cwd,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE)
        assign_job(job, process)
        stdout, stderr = process.communicate(
            input=b'\n', timeout=30)
        output = stdout.decode('utf-8', 'replace')
        assert process.returncode == 0 and not stderr, (process.returncode, output, stderr)
        assert 'BACKTRACE:' not in output and 'STACK UNDER FLOW' not in output, output
        assert_empty_job(job)
        return output
    finally:
        kernel.TerminateJobObject(job, 1)
        if process is not None:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)
        kernel.CloseHandle(job)


def run(binary, source, cwd=None):
    return invoke(binary, source, cwd)


class SigmaSession:
    """Line protocol with a deadline, job ownership and an initial KEY gate."""
    def __init__(self, binary, source, cwd=None):
        self.job = create_job()
        self.process = None
        self.stderr = tempfile.TemporaryFile()
        self.lines = queue.Queue()
        try:
            self.process = subprocess.Popen([str(Path(binary).resolve()), '-e', 'KEY DROP ' + source], cwd=cwd,
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.stderr)
            assign_job(self.job, self.process)
            def read_lines():
                try:
                    for line in iter(self.process.stdout.readline, b''):
                        self.lines.put(line.rstrip(b'\r\n'))
                finally:
                    self.lines.put(None)
            self.reader = threading.Thread(target=read_lines, daemon=True)
            self.reader.start()
            self.send()
        except BaseException:
            self.close()
            raise

    def send(self):
        self.process.stdin.write(b'\n')
        self.process.stdin.flush()

    def line(self, timeout=7):
        try:
            line = self.lines.get(timeout=timeout)
        except queue.Empty:
            raise TimeoutError('Sigma stdout line deadline') from None
        if line is None:
            raise AssertionError(('Unexpected Sigma EOF', self.errors()))
        return line

    def errors(self):
        self.stderr.seek(0)
        return self.stderr.read()

    def finish(self):
        assert self.process.wait(timeout=10) == 0, self.errors()
        self.reader.join(timeout=5)
        assert not self.reader.is_alive()
        trailing = []
        while not self.lines.empty():
            item = self.lines.get_nowait()
            if item is not None:
                trailing.append(item)
        assert not trailing and not self.errors(), (trailing, self.errors())
        assert_empty_job(self.job)

    def close(self):
        if self.job:
            kernel.TerminateJobObject(self.job, 1)
        if self.process is not None:
            if self.process.poll() is None:
                self.process.kill()
            self.process.wait(timeout=5)
            if hasattr(self, 'reader'):
                self.reader.join(timeout=5)
            for stream in (self.process.stdin, self.process.stdout):
                if stream:
                    stream.close()
        if self.job:
            kernel.CloseHandle(self.job)
            self.job = None
        self.stderr.close()

    def __enter__(self):
        return self

    def __exit__(self, *unused):
        self.close()

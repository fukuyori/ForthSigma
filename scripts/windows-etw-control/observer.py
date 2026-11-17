"""Windows-only diagnostic observer; no product clock changes."""
import ctypes
from ctypes import wintypes as w
import time
import _winapi
import psutil

api = ctypes.WinDLL('kernel32', use_last_error=True)
api.QueryPerformanceCounter.argtypes = [ctypes.POINTER(ctypes.c_longlong)]
api.QueryPerformanceCounter.restype = w.BOOL
api.QueryPerformanceFrequency.argtypes = [ctypes.POINTER(ctypes.c_longlong)]
api.QueryPerformanceFrequency.restype = w.BOOL


def qpc():
    value = ctypes.c_longlong()
    if not api.QueryPerformanceCounter(ctypes.byref(value)):
        raise ctypes.WinError(ctypes.get_last_error())
    return value.value


def clock_info():
    freq = ctypes.c_longlong()
    if not api.QueryPerformanceFrequency(ctypes.byref(freq)) or freq.value <= 0:
        raise RuntimeError('QueryPerformanceFrequency failed')
    pairs = []
    for _ in range(8):
        before = qpc()
        ns = time.perf_counter_ns()
        after = qpc()
        # One ns for integer conversion rounding. Fail rather than join via UTC.
        if not before * 10**9 <= ns * freq.value + freq.value or not ns * freq.value <= after * 10**9 + freq.value:
            raise RuntimeError('QPC/perf_counter origin or scale mismatch')
        pairs.append([before, ns, after])
    info = vars(time.get_clock_info('perf_counter'))
    if 'QueryPerformanceCounter' not in info['implementation'] or not info['monotonic']:
        raise RuntimeError('Unexpected perf_counter clock')
    return {'frequency': freq.value, 'python_clock': info, 'qpc_perf_brackets': pairs}


def install(benchmark):
    original_create = _winapi.CreateProcess
    primary = {}

    def create(*args, **kwargs):
        result = original_create(*args, **kwargs)
        primary[result[2]] = result[3]
        return result

    _winapi.CreateProcess = create
    base = benchmark.WindowsProcessClock

    class Group(ctypes.Structure):
        _fields_ = [('mask', ctypes.c_size_t), ('group', w.WORD), ('reserved', w.WORD * 3)]

    class Clock(base):
        mode = 'minimal'
        cpu = 0
        sessions = []

        def __init__(self, pid):
            super().__init__(pid)
            self.pid, self.tid = pid, primary.pop(pid)
            self.process = psutil.Process(pid)
            self.api.OpenThread.argtypes = [w.DWORD, w.BOOL, w.DWORD]
            self.api.OpenThread.restype = w.HANDLE
            self.api.GetThreadTimes.argtypes = [w.HANDLE] + [ctypes.POINTER(w.FILETIME)] * 4
            self.api.GetThreadTimes.restype = w.BOOL
            self.api.GetThreadGroupAffinity.argtypes = [w.HANDLE, ctypes.POINTER(Group)]
            self.api.GetThreadGroupAffinity.restype = w.BOOL
            self.api.GetPriorityClass.argtypes = [w.HANDLE]
            self.api.GetPriorityClass.restype = w.DWORD
            self.api.GetThreadPriority.argtypes = [w.HANDLE]
            self.api.GetThreadPriority.restype = ctypes.c_int
            for name in ('QueryProcessCycleTime', 'QueryThreadCycleTime'):
                fn = getattr(self.api, name)
                fn.argtypes = [w.HANDLE, ctypes.POINTER(ctypes.c_ulonglong)]
                fn.restype = w.BOOL
            self.thread = self.api.OpenThread(0x0840, False, self.tid)
            if not self.thread:
                super().close()
                raise ctypes.WinError(ctypes.get_last_error())
            self.session = {'pid': pid, 'primary_tid': self.tid, 'mode': self.mode, 'cpu': self.cpu, 'queries': []}
            self.sessions.append(self.session)
            try:
                self.session['before'] = self.identity()
            except BaseException:
                self.close()
                raise

        def identity(self):
            group = Group()
            if not self.api.GetThreadGroupAffinity(self.thread, ctypes.byref(group)):
                raise ctypes.WinError(ctypes.get_last_error())
            process_priority = self.api.GetPriorityClass(self.handle)
            thread_priority = self.api.GetThreadPriority(self.thread)
            if process_priority == 0 or thread_priority == 0x7fffffff:
                raise ctypes.WinError(ctypes.get_last_error())
            affinity = self.process.cpu_affinity()
            if group.group != 0 or group.mask != 1 << self.cpu or affinity != [self.cpu]:
                raise RuntimeError('Child affinity/group drift')
            return {'affinity': affinity, 'group': group.group, 'mask': group.mask,
                    'process_priority': process_priority, 'thread_priority': thread_priority}

        def read_ns(self):
            # The third read is after process exit. Identity is checked while alive at DONE.
            index = len(self.session['queries'])
            row = {'index': index, 'start_qpc': qpc()}

            def measured(name, call):
                a = qpc()
                value = call()
                b = qpc()
                row[name] = {'before_qpc': a, 'after_qpc': b, 'value': value}
                return value

            def times(fn, handle):
                fields = [w.FILETIME() for _ in range(4)]
                if not fn(handle, *(ctypes.byref(x) for x in fields)):
                    raise ctypes.WinError(ctypes.get_last_error())
                return {name: ((x.dwHighDateTime << 32) | x.dwLowDateTime) * 100
                        for name, x in zip(('kernel_ns', 'user_ns'), fields[2:])}

            process = measured('process', lambda: times(self.api.GetProcessTimes, self.handle))
            measured('primary_thread', lambda: times(self.api.GetThreadTimes, self.thread))
            if index < 2 and self.mode == 'full':
                def cycles(name, handle):
                    value = ctypes.c_ulonglong()
                    if not getattr(self.api, name)(handle, ctypes.byref(value)):
                        raise ctypes.WinError(ctypes.get_last_error())
                    return value.value
                measured('process_cycles', lambda: cycles('QueryProcessCycleTime', self.handle))
                measured('thread_cycles', lambda: cycles('QueryThreadCycleTime', self.thread))
                measured('identity', self.identity)
                measured('threads', lambda: [x._asdict() for x in self.process.threads()])
                measured('contexts', lambda: self.process.num_ctx_switches()._asdict())
                measured('host_cpu', lambda: [x._asdict() for x in psutil.cpu_times(percpu=True)])
            row['end_qpc'] = qpc()
            self.session['queries'].append(row)
            # After the DONE CPU read, outside both process-CPU and wall end boundaries
            # only for CPU; benchmark wall includes this check, recorded as a limitation.
            if index == 1:
                a = qpc()
                self.session['after'] = self.identity()
                self.session['after_identity_bracket'] = [a, qpc()]
            return sum(process.values())

        def close(self):
            if getattr(self, 'thread', None):
                self.api.CloseHandle(self.thread)
                self.thread = None
            super().close()

    benchmark.WindowsProcessClock = Clock
    return Clock

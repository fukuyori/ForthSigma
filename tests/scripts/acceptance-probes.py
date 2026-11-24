"""1382 OS samplers and normal-path probe driver (stdlib only)."""
import ctypes
import json
import os
from pathlib import Path
import re
import subprocess
import threading
import time


def memory(pid):
    if os.name == 'nt':
        from ctypes import wintypes as w
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.OpenProcess.restype = w.HANDLE
        kernel.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
        kernel.CloseHandle.argtypes = [w.HANDLE]
        class MBI(ctypes.Structure):
            _fields_ = [('base', ctypes.c_void_p), ('allocation', ctypes.c_void_p),
                        ('protect', w.DWORD), ('partition', w.WORD), ('size', ctypes.c_size_t),
                        ('state', w.DWORD), ('protection', w.DWORD), ('kind', w.DWORD)]
        class PMC(ctypes.Structure):
            _fields_ = [('cb', w.DWORD), ('faults', w.DWORD)] + [(n, ctypes.c_size_t) for n in
                ['peak_working', 'working', 'peak_paged', 'paged', 'peak_nonpaged', 'nonpaged', 'pagefile', 'peak_pagefile', 'private']]
        kernel.VirtualQueryEx.argtypes = [w.HANDLE, ctypes.c_void_p, ctypes.POINTER(MBI), ctypes.c_size_t]
        kernel.VirtualQueryEx.restype = ctypes.c_size_t
        psapi = ctypes.WinDLL('psapi', use_last_error=True)
        psapi.GetProcessMemoryInfo.argtypes = [w.HANDLE, ctypes.POINTER(PMC), w.DWORD]
        handle = kernel.OpenProcess(0x410, False, pid)
        if not handle:
            raise OSError(ctypes.get_last_error(), 'OpenProcess')
        try:
            address = reserved = committed = 0
            item = MBI()
            while kernel.VirtualQueryEx(handle, address, ctypes.byref(item), ctypes.sizeof(item)):
                if item.state == 0x2000:
                    reserved += item.size
                if item.state == 0x1000:
                    committed += item.size
                nxt = (item.base or 0) + item.size
                if nxt <= address:
                    break
                address = nxt
            counters = PMC()
            counters.cb = ctypes.sizeof(counters)
            if not psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
                raise OSError(ctypes.get_last_error(), 'GetProcessMemoryInfo')
            return dict(process_reserved_bytes=reserved+committed,
                        process_committed_bytes=counters.private,
                        process_resident_bytes=counters.working,
                        virtual_committed_bytes=committed, peak_resident_bytes=counters.peak_working,
                        definition='VirtualQueryEx reserve+commit; PrivateUsage; WorkingSetSize')
        finally:
            kernel.CloseHandle(handle)
    smaps = Path(f'/proc/{pid}/smaps').read_text()
    totals = dict(size=0, rss=0, private=0, shared=0, stack=0, accountable=0, swap=0)
    block = {}
    name = ''
    for line in smaps.splitlines():
        if re.match(r'^[0-9a-f]+-', line):
            block = {}
            name = line
        elif ':' in line:
            key, value = line.split(':', 1)
            if key == 'VmFlags':
                if 'ac' in value.split():
                    totals['accountable'] += block.get('Size', 0)
                continue
            if value.strip().endswith('kB'):
                n = int(value.split()[0])*1024
                block[key] = n
                if key == 'Size': totals['size'] += n
                if key == 'Rss': totals['rss'] += n
                if key.startswith('Private_'): totals['private'] += n
                if key.startswith('Shared_'): totals['shared'] += n
                if key == 'Swap': totals['swap'] += n
                if key == 'Size' and '[stack' in name: totals['stack'] += n
    return dict(process_reserved_bytes=totals['size'], process_committed_bytes=totals['accountable'],
                process_resident_bytes=totals['rss'], details=totals,
                definition='smaps Size; VmFlags ac charged virtual mappings; Rss. Not Windows commit semantics')


def run(sigma, source, out, smoke, stage=None, native=None, seconds=None, memory_hold=False):
    env = dict(os.environ, SIGMA_ACCEPTANCE_SMOKE='1' if smoke or memory_hold else '0')
    if native: env["SIGMA_ACCEPTANCE_NATIVE"] = native
    else: env.pop("SIGMA_ACCEPTANCE_NATIVE", None)
    if stage: env['SIGMA_ACCEPTANCE_CANCEL_AT'] = stage
    else: env.pop('SIGMA_ACCEPTANCE_CANCEL_AT', None)
    if memory_hold: env["SIGMA_ACCEPTANCE_MEMORY_HOLD"] = "1"
    else: env.pop("SIGMA_ACCEPTANCE_MEMORY_HOLD", None)
    samples = []
    errors = []
    stopped = threading.Event()
    start = time.perf_counter()  # ONLY total trial cost, never an acceptance endpoint
    timed_out = False
    phase_missed = False
    checkpoints = []
    with (out.with_suffix('.raw.log')).open('wb') as log:
        child = subprocess.Popen([str(sigma), str(source)], stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.PIPE, env=env)
        def sample():
            nonlocal phase_missed
            holds = 0
            log_offset = 0
            found = 0
            tail = b""
            request_observed = False
            while not stopped.is_set():
                try:
                    samples.append(memory(child.pid))
                except (OSError, ValueError) as exc:
                    if child.poll() is not None: return
                    errors.append(str(exc))
                if memory_hold or native:
                    with out.with_suffix('.raw.log').open('rb') as stream:
                        stream.seek(log_offset)
                        block = stream.read()
                        log_offset += len(block)
                    lines = (tail + block).split(b'\n')
                    tail = lines.pop()
                    for line in lines:
                        found += line.count(b'ACCEPTANCE-MEMORY-HOLD') + line.count(b'BASELINE-READY')
                        request_observed |= b'phase_requested' in line
                if found > holds:
                    try:
                        point = memory(child.pid)
                        samples.append(point)
                        checkpoints.append(point)
                        child.stdin.write(b'\n')
                        child.stdin.flush()
                        holds += 1
                    except (OSError, ValueError) as exc:
                        errors.append(str(exc))
                if native and stage and not smoke and time.perf_counter()-start >= .25:
                    # An observation window, not a cancellation latency endpoint.
                    if not request_observed:
                        phase_missed = True
                        child.kill()
                        return
                stopped.wait(.01)
        sampler = threading.Thread(target=sample, daemon=True)
        sampler.start()
        def finish_duration():
            if not stopped.wait(seconds):
                try:
                    child.stdin.write(b'q')
                    child.stdin.flush()
                except (BrokenPipeError, OSError):
                    pass
        timer = None
        if seconds:
            timer = threading.Thread(target=finish_duration, daemon=True)
            timer.start()
        try:
            child.wait(timeout=(seconds or 0)+120)
        except subprocess.TimeoutExpired:
            timed_out = True
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
            stopped.set()
            sampler.join()
            if timer: timer.join()
            child.stdin.close()
    cost = time.perf_counter()-start
    rows = [json.loads(line.split('ACCEPTANCE ', 1)[1]) for line in
            out.with_suffix('.raw.log').read_text(errors='replace').splitlines() if line.startswith('ACCEPTANCE ')]
    expected_holds = out.with_suffix(".raw.log").read_text(errors="replace").count("ACCEPTANCE-MEMORY-HOLD") + out.with_suffix(".raw.log").read_text(errors="replace").count("BASELINE-READY") if memory_hold else 0
    phase_missed = phase_missed or any(r.get("metric") == "phase_missed" for r in rows)
    result = dict(timed_out=timed_out, phase_missed=phase_missed, memory_checkpoints=checkpoints, expected_memory_checkpoints=expected_holds, command=[str(sigma), str(source)], exit_code=child.returncode,
                  trial_wall_seconds=cost, events=rows, os_samples=samples, os_sample_errors=errors,
                  memory_sampling='10ms plus acknowledged resource-retention checkpoints; transient peaks outside checkpoints remain unproven')
    out.with_suffix('.json').write_text(json.dumps(result, indent=2)+'\n')
    if (timed_out or phase_missed) and stage is not None:
        return result  # retain the missing phase and allow the remaining trials
    if timed_out or child.returncode or any(x in out.with_suffix(".raw.log").read_text(errors="replace") for x in ["Error:", "error:", "ERROR #", "THROW", "unknown word"]):
        raise RuntimeError(f'probe failed or no endpoints: {out}')
    return result


def response(sigma, source, out, smoke, seconds=600):
    import runpy
    session_type = runpy.run_path(str(Path(__file__).with_name('verify-task-examples.py')))['Session']
    # Parent receipt includes both pipes and scheduling: an upper bound on state.
    session = session_type(str(sigma), str(source))
    rows = []
    raw_output = []
    failure = None
    start = time.perf_counter()
    try:
        session.expect('INPUT-READY')
        raw_output.append(bytes(session.output))
        session.output.clear()
        end = start + (seconds if not smoke else 0)
        i = 0
        while True:
            at = time.perf_counter_ns() if not smoke else None
            session.send('b')
            session.expect('INPUT-APPLIED=98 ')
            elapsed = time.perf_counter_ns()-at if at is not None else None
            raw_output.append(bytes(session.output))
            session.output.clear()
            rows.append(dict(trial=i, metric='input_state_ns', value=elapsed,
                             definition='parent write to receipt after state store: pipe/scheduling upper bound'))
            i += 1
            if smoke or time.perf_counter() >= end: break
            time.sleep(.1)
        session.send('q')
        session.finish()
    except Exception as exc:
        failure = str(exc)
    finally:
        session.close()
        raw_output.append(bytes(session.output))
        out.with_suffix('.raw.log').write_bytes(b''.join(raw_output))
    result = dict(events=rows, error=failure, trial_wall_seconds=time.perf_counter()-start)
    out.with_suffix('.json').write_text(json.dumps(result, indent=2)+'\n')
    if failure is not None:
        raise RuntimeError(f'input probe failed: {out}: {failure}')
    return result

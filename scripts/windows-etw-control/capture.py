"""Fixed baseline diagnostic. --prepare/--preflight/--smoke do not start ETW."""
import argparse
import ctypes
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import subprocess
import sys
import uuid
import psutil
import observer

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OLD = ROOT / '.work/windows-timing-followup-20261116'
WORK = ROOT / '.work/windows-etw-control-20261116'
MANIFEST = WORK / 'fixed.json'
ORDER = [(0, 'minimal', 'sigma'), (2, 'full', 'native'), (0, 'full', 'native'),
         (2, 'minimal', 'sigma'), (2, 'minimal', 'native'), (0, 'full', 'sigma'),
         (2, 'full', 'sigma'), (0, 'minimal', 'native')]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    pending = path.with_suffix(path.suffix + '.tmp')
    pending.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    pending.replace(path)


def load_benchmark():
    spec = importlib.util.spec_from_file_location('benchmark', ROOT / 'scripts/benchmark-runtime.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def paths():
    return [ROOT / 'zig-out/bin/sigma.exe', OLD / 'native-control.exe',
            ROOT / 'scripts/benchmark-runtime.py', OLD / 'etw/schedule.wprp',
            ROOT / 'docs/VM_WINDOWS_ETW_CONTROL_PLAN.md',
            *sorted(HERE.glob('*.py')), HERE / 'capture.ps1', HERE / 'read-etw-qpc.c']


def environment():
    buf = ctypes.create_unicode_buffer(32768)
    if not 0 < ctypes.windll.kernel32.GetSystemDirectoryW(buf, len(buf)) < len(buf):
        raise RuntimeError('System directory lookup failed')
    wpr = Path(buf.value) / 'wpr.exe'
    if not wpr.is_file():
        raise RuntimeError('System WPR missing')
    affinity = psutil.Process().cpu_affinity()
    if not {0, 2}.issubset(affinity):
        raise RuntimeError('CPU0/2 unavailable; no automatic substitution')
    return {'python': sys.version, 'executable': sys.executable, 'platform': platform.platform(),
            'psutil': psutil.__version__, 'wpr': str(wpr), 'affinity': affinity,
            'administrator': bool(ctypes.windll.shell32.IsUserAnAdmin()), 'clock': observer.clock_info()}


def verify(fixed):
    for name, expected in fixed['hashes'].items():
        if sha(ROOT / name) != expected:
            raise RuntimeError('Frozen input changed: ' + name)
    env = environment()
    for name in ('python', 'executable', 'platform', 'psutil', 'wpr', 'affinity'):
        if env[name] != fixed['environment'][name]:
            raise RuntimeError('Environment changed: ' + name)
    return env


def source(kind, n):
    if kind == 'native':
        return str(n)
    return (f'{n} CONSTANT BENCH-ITERATIONS : BENCH-RUN {{ | x -- }} 7 TO x 0 '
            'BENCH-ITERATIONS 0 DO x + LOOP ; ." BENCH-READY" CR KEY DROP '
            'BENCH-RUN ." BENCH-DONE " . CR KEY DROP BYE')


def run_sample(benchmark, clock, cpu, mode, kind, n, original):
    process = psutil.Process()
    process.cpu_affinity(original)
    benchmark.cpu_affinity(cpu)
    clock.cpu, clock.mode = cpu, mode
    executable = ROOT / 'zig-out/bin/sigma.exe' if kind == 'sigma' else OLD / 'native-control.exe'
    try:
        cpu_us, checksum, wall_us, total_us = benchmark.sample(str(executable), False, source(kind, n))
        if checksum != 7 * n:
            raise RuntimeError('Checksum mismatch')
        return {'cpu': cpu, 'mode': mode, 'kind': kind, 'n': n, 'cpu_us': cpu_us,
                'wall_us': wall_us, 'total_cpu_us': total_us, 'checksum': checksum,
                'observer': clock.sessions[-1]}
    finally:
        process.cpu_affinity(original)


def capture(fixed, env, smoke):
    if not smoke and not env['administrator']:
        raise RuntimeError('Administrator PowerShell required; no automatic elevation')
    folder = WORK / (('smoke-' if smoke else 'capture-') + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S') + '-' + uuid.uuid4().hex[:8])
    folder.mkdir(parents=True)
    report = {'fixed': fixed, 'environment': env, 'smoke': smoke, 'status': 'started',
              'blocks': [], 'samples': [], 'limitations': ['Diagnostic, not calibration/adoption',
              'Wall includes observer and DONE identity validation; no cost subtraction',
              'ETW off/on block order remains a temporal confound', 'Cycles are not elapsed time or instructions']}
    output = folder / 'capture.json'
    save(output, report)
    print(folder, flush=True)
    benchmark = load_benchmark()
    clock = observer.install(benchmark)
    original = env['affinity']

    def command(block, args):
        try:
            p = subprocess.run([env['wpr'], *args], capture_output=True, timeout=180)
            row = {'args': args, 'exit': p.returncode, 'stdout': p.stdout.decode(errors='replace'), 'stderr': p.stderr.decode(errors='replace')}
        except (OSError, subprocess.TimeoutExpired) as error:
            row = {'args': args, 'exit': -1, 'stdout': '', 'stderr': repr(error)}
        block['commands'].append(row)
        save(output, report)
        return row

    def idle(block, args):
        row = command(block, args)
        return row['exit'] == 0 and 'wpr is not recording' in row['stdout'].lower()

    try:
        for group in ([1] if smoke else [1, 2]):
            order = ORDER if group == 1 else list(reversed(ORDER))
            for etw in ([False] if smoke else ([False, True] if group == 1 else [True, False])):
                block = {'group': group, 'etw': etw, 'commands': [], 'clock_before': observer.clock_info()}
                if block['clock_before']['frequency'] != env['clock']['frequency']:
                    raise RuntimeError('QPC frequency changed before block')
                report['blocks'].append(block)
                instance = 'SigmaControl' + uuid.uuid4().hex[:10]
                block['instance'] = instance
                block['manual_cancel'] = f"& '{env['wpr']}' -cancel -instancename {instance}"
                if etw:
                    print(block['manual_cancel'], flush=True)
                if not smoke and (not idle(block, ['-status']) or not idle(block, ['-status', '-instancename', instance])):
                    raise RuntimeError('Existing or unresolved WPR state; no capture started')
                start_attempted = False
                try:
                    if etw:
                        temp = folder / f'g{group}-temp'
                        temp.mkdir()
                        start_attempted = True
                        result = command(block, ['-start', str(OLD / 'etw/schedule.wprp') + '!SigmaSchedule.Light', '-filemode', '-recordtempto', str(temp), '-instancename', instance])
                        if result['exit']:
                            raise RuntimeError('WPR start failed')
                    for cycle in (range(1) if smoke else range(4)):
                        for cpu, mode, kind in order:
                            n = (50_000_000 if kind == 'sigma' else 1_000_000_000) if smoke else fixed['iterations'][kind]
                            row = run_sample(benchmark, clock, cpu, mode, kind, n, original)
                            row.update(group=group, etw=etw, warmup=(cycle == 0 and not smoke), cycle=cycle)
                            report['samples'].append(row)
                            save(output, report)
                            print(len(report['samples']), group, etw, cpu, mode, kind, row['cpu_us'], flush=True)
                finally:
                    if start_attempted:
                        etl = folder / f'g{group}.etl'
                        stop = command(block, ['-stop', str(etl), 'Sigma control diagnostic', '-skipPdbGen', '-instancename', instance])
                        block['stop_exit'] = stop['exit']
                        if stop['exit'] != 0:
                            command(block, ['-cancel', '-instancename', instance])
                        block['cleanup_confirmed'] = idle(block, ['-status', '-instancename', instance])
                        if not block['cleanup_confirmed']:
                            command(block, ['-cancel', '-instancename', instance])
                            block['cleanup_confirmed'] = idle(block, ['-status', '-instancename', instance])
                        if etl.is_file():
                            block['etl'] = etl.name
                            block['etl_sha256'] = sha(etl)
                        save(output, report)
                        if stop['exit'] or not block['cleanup_confirmed'] or not etl.is_file():
                            print('Inspect owned session: ' + block['manual_cancel'], flush=True)
                            raise RuntimeError('ETW stop/cleanup/trace incomplete')
                block['clock_after'] = observer.clock_info()
                if block['clock_after']['frequency'] != env['clock']['frequency']:
                    raise RuntimeError('QPC frequency changed after block')
        if len(report['samples']) != (8 if smoke else 128):
            raise RuntimeError('Sample count mismatch')
        verify(fixed)
        report['status'] = 'complete'
    except BaseException as error:
        report['status'] = 'failed'
        report['error'] = repr(error)
        raise
    finally:
        psutil.Process().cpu_affinity(original)
        save(output, report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    for flag in ('prepare', 'preflight', 'smoke', 'capture'):
        modes.add_argument('--' + flag, action='store_true')
    args = parser.parse_args()
    env = environment()
    if args.prepare:
        if MANIFEST.exists():
            raise RuntimeError('Frozen manifest already exists; do not overwrite an existing protocol')
        old = json.loads((OLD / 'protocol.json').read_text())
        hashes = {p.relative_to(ROOT).as_posix(): sha(p) for p in paths()}
        if hashes['zig-out/bin/sigma.exe'] != old['baseline_sha256'] or hashes['scripts/benchmark-runtime.py'] != old['benchmark_sha256']:
            raise RuntimeError('Baseline/helper changed')
        if sha(OLD / 'native-control.exe') != json.loads((OLD / 'native-build.json').read_text())['binary_sha256']:
            raise RuntimeError('Native changed')
        if sha(OLD / 'etw/schedule.wprp') != json.loads((OLD / 'etw/capture.json').read_text())['profile_sha256']:
            raise RuntimeError('Profile changed')
        WORK.mkdir(parents=True, exist_ok=True)
        save(MANIFEST, {'environment': env, 'hashes': hashes, 'iterations': {'sigma': 1238709678, 'native': 38400000000}, 'order': ORDER})
        print(MANIFEST)
        return
    fixed = json.loads(MANIFEST.read_text(encoding='utf-8'))
    env = verify(fixed)
    if args.preflight:
        print(json.dumps(env, indent=2))
    else:
        capture(fixed, env, args.smoke)


if __name__ == '__main__':
    main()

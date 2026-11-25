#!/usr/bin/env python3
"""D07 single-VM A/A'/B runner. Smoke never produces a timing verdict."""
import argparse
import difflib
import hashlib
import itertools
import json
import math
import os
from pathlib import Path
import platform
import queue
import re
import shutil
import statistics
import subprocess
import tarfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
BASE = '35523f676836134c4fbaed19e3d01d2a23ec2a92'
LABELS = ('A', 'Aprime', 'B')
CASES = {
    'CALC': (': RUN 1 N 0 DO 3 * 7 + 65535 AND LOOP ;', '(3*x+7)&65535'),
    'XT': (": INC 1+ ; ' INC CONSTANT TOKEN : RUN 0 N 0 DO TOKEN EXECUTE LOOP ;", 'N'),
    'DEFERRED': ("DEFER ACTION : INC 1+ ; ' INC IS ACTION : RUN 0 N 0 DO ACTION LOOP ;", 'N'),
    'INTERPRET': (': RUN 0 N 0 DO S" 1+" EVALUATE LOOP ;', 'N'),
    'byte-scan': ('CREATE DATA 4096 ALLOT DATA 4096 7 FILL : RUN 0 N 0 DO DATA I 4095 AND + C@ + LOOP ;', '7*N'),
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def command(args, cwd=ROOT):
    return subprocess.check_output([str(x) for x in args], cwd=cwd, stderr=subprocess.STDOUT)


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def prepare(out, jobs):
    sources = out / 'sources'
    sources.mkdir()
    archive = out / 'A.tar'
    archive.write_bytes(command(['git', 'archive', BASE]))
    a = sources / 'A'
    a.mkdir()
    with tarfile.open(archive) as tar:
        tar.extractall(a, filter='data')
    # Copy tracked and untracked nonignored inputs, without repository/cache/output trees.
    names = command(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard']).decode().split('\0')
    manifest = {}
    for label in ('B', 'Aprime', 'B-copy'):
        dest = sources / label
        for name in filter(None, names):
            src = ROOT / name
            if not src.is_file():
                continue
            target = dest / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, target)
            manifest[name] = sha(src)
    path = sources / 'Aprime/src/forth.zig'
    before = path.read_text()
    old = 'if (self.workerCancellation() != null) return self.executeWordMode(true, id);'
    if before.count(old) != 1:
        raise RuntimeError('A-prime patch anchor changed; review source before proceeding')
    after = before.replace(old, 'if (comptime false) return self.executeWordMode(true, id);')
    path.write_text(after)
    (out / 'Aprime.patch').write_text(''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True), fromfile='B/src/forth.zig', tofile='Aprime/src/forth.zig')))
    save_json(out / 'source-manifest.json', manifest)
    builds = {}
    suffix = '.exe' if os.name == 'nt' else ''
    for label in (*LABELS, 'B-copy'):
        prefix = out / 'build' / label
        args = ['zig', 'build', '-Doptimize=ReleaseFast', '-Ddebug=false', '-Dstrip=false', '--prefix', prefix, f'-j{jobs}']
        if label != 'A':
            args += ['-Dtask-trace=false', '-Dtask-acceptance=false']
        (out / f'{label}-build.log').write_bytes(command(args, ROOT if label == 'B' else sources / label))
        builds[label] = {'cwd': str(ROOT if label == 'B' else sources / label), 'command': list(map(str, args)), 'binary': str(prefix / 'bin' / ('sigma' + suffix))}
    save_json(out / 'builds.json', builds)
    return builds


def disassemble(out, builds, objdump):
    sections = {}
    for label, info in builds.items():
        binary = info['binary']
        info['sha256'] = sha(binary)
        (out / f'{label}-sections.txt').write_bytes(command([objdump, '-h', binary]))
        # Full demangled output retains anonymous instantiations and addresses.
        assembly = command([objdump, '-d', '-C', binary]).decode(errors='replace')
        (out / f'{label}-disassembly.txt').write_text(assembly)
        selected = []
        keep = False
        for line in assembly.splitlines(True):
            if line.rstrip().endswith('>:'):
                keep = any(name in line for name in ('runOperations', 'executeWord', 'executeBuiltin', 'executeCompiled'))
            if keep:
                selected.append(line)
        (out / f'{label}-normal-functions.txt').write_text(''.join(selected))
        text = out / f'{label}.text'
        # objcopy is not needed: normalize addresses/headers from objdump hex rows.
        dump = command([objdump, '-s', '-j', '__text' if platform.system() == 'Darwin' else '.text', binary]).decode()
        data = bytearray()
        for line in dump.splitlines():
            fields = line.split()
            if fields and all(c in '0123456789abcdefABCDEF' for c in fields[0]):
                for field in fields[1:5]:
                    if len(field) % 2 or not all(c in '0123456789abcdefABCDEF' for c in field):
                        break
                    data.extend(bytes.fromhex(field))
        if not data:
            raise RuntimeError('objdump did not yield text bytes')
        text.write_bytes(data)
        sections[label] = {'bytes': len(data), 'sha256': sha(text)}
    save_json(out / 'text-comparison.json', sections)
    if sections['B'] != sections['B-copy']:
        raise RuntimeError('B and unmodified duplicate .text differ; investigate build placement')


def sample(binary, source):
    started = time.monotonic_ns()
    with subprocess.Popen([binary, '-e', source], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as child:
        lines = queue.Queue()
        transcript = []
        def reader():
            for line in iter(child.stdout.readline, b''):
                lines.put((time.monotonic_ns(), line))
            lines.put((time.monotonic_ns(), None))
        thread = threading.Thread(target=reader, daemon=True)
        thread.start()
        def receive():
            stamp, line = lines.get(timeout=120)
            transcript.append(None if line is None else line.decode(errors='replace'))
            return stamp, line.strip() if line else None
        try:
            _, ready = receive()
            if ready != b'READY':
                raise RuntimeError(f'expected READY: {transcript}')
            start = time.monotonic_ns()
            child.stdin.write(b'x'); child.stdin.flush()
            end, done = receive()
            if done is None or not done.startswith(b'DONE '):
                raise RuntimeError(f'expected DONE: {transcript}')
            checksum = int(done.split()[1])
            child.stdin.write(b'x'); child.stdin.flush()
            child.stdin.close()
            child.wait(timeout=120)
            thread.join(timeout=5)
            _, tail = receive()
            if child.returncode or tail is not None or thread.is_alive():
                raise RuntimeError(f'bad exit/output: {transcript}')
            return {'wall_ns': end-start, 'checksum': checksum, 'process_wall_ns': time.monotonic_ns()-started, 'stdout': transcript}
        finally:
            if child.poll() is None:
                child.kill(); child.wait()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--mode', choices=['prepare', 'smoke', 'measure'], required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--builds', type=Path, help='existing builds.json; otherwise prepare fresh sources/builds')
    p.add_argument('--rounds', type=int, help='required operator decision for measure; suggested 100')
    p.add_argument('--warmup', type=int, default=5)
    p.add_argument('--iterations', type=int, default=1000000)
    p.add_argument('--confirmed', help='premeasurement operator decision reference')
    p.add_argument('--environment', help='CPU/power/background load/terminal notes, required for measure')
    p.add_argument('--objdump', default='objdump')
    p.add_argument('--jobs', type=int, default=2)
    args = p.parse_args()
    if args.mode == 'measure' and (not args.rounds or not args.confirmed or not args.environment):
        p.error('measure requires --rounds, --confirmed and --environment fixed beforehand')
    if args.iterations < 1 or args.warmup < 1 or (args.rounds is not None and args.rounds < 1):
        p.error('counts must be positive')
    out = args.out.resolve(); out.mkdir(parents=True, exist_ok=False)
    os.environ['ZIG_GLOBAL_CACHE_DIR'] = str(ROOT / '.work/codex-cache/global')
    os.environ['ZIG_LOCAL_CACHE_DIR'] = str(ROOT / '.work/codex-cache/local')
    meta = {'args': vars(args) | {'out': str(out), 'builds': str(args.builds)}, 'platform': platform.platform(), 'head': command(['git','rev-parse','HEAD']).decode().strip(), 'status': command(['git','status','--short']).decode(), 'zig': command(['zig','version']).decode().strip(), 'A': BASE, 'script_sha256': sha(__file__), 'baseline_archive_sha256': sha(args.builds.resolve().parent / 'A.tar') if args.builds and (args.builds.resolve().parent / 'A.tar').exists() else None, 'zig_binary_sha256': sha(shutil.which('zig')), 'objdump_version': command([args.objdump, '--version']).decode().splitlines()[0]}
    save_json(out / 'manifest.json', meta)
    builds = json.loads(args.builds.read_text()) if args.builds else prepare(out, args.jobs)
    disassemble(out, builds, args.objdump)
    save_json(out / 'builds.json', builds)
    if (out / 'A.tar').exists():
        meta['baseline_archive_sha256'] = sha(out / 'A.tar')
        save_json(out / 'manifest.json', meta)
    if args.mode == 'prepare':
        return
    rounds = args.rounds if args.mode == 'measure' else 2
    iterations = args.iterations if args.mode == 'measure' else 1000
    orders = list(itertools.permutations(LABELS))
    summary = {}
    with (out / 'samples.jsonl').open('w') as log:
        for name, (body, expected) in CASES.items():
            body = re.sub(r'\b(N|RUN|INC|TOKEN|ACTION|DATA)\b', lambda m: 'SVAB-' + m[0], body)
            source = f'{iterations} CONSTANT SVAB-N {body} ." READY" CR KEY DROP SVAB-RUN ." DONE " . CR KEY DROP BYE'
            (out / f'{name}.fs').write_text(source + '\n')
            if expected == 'N': check = iterations
            elif expected == '7*N': check = 7*iterations
            else:
                check = 1
                for _ in range(iterations): check = (check*3+7)&65535
            values = {label: [] for label in LABELS}
            for phase, count in [('warmup', args.warmup if args.mode == 'measure' else 1), ('sample', rounds)]:
                for r in range(count):
                    for label in orders[r % len(orders)]:
                        result = sample(builds[label]['binary'], source)
                        row = {'fixture_sha256': sha(out / f'{name}.fs'), 'case': name, 'phase': phase, 'round': r, 'label': label, **result}
                        log.write(json.dumps(row) + '\n'); log.flush()
                        if result['checksum'] != check: raise RuntimeError(f'checksum mismatch: {row}, expected {check}')
                        if phase == 'sample': values[label].append(result['wall_ns'])
            if args.mode == 'measure':
                stats = {label: {'median_ns': statistics.median(v), 'p95_ns': sorted(v)[math.ceil(.95*len(v))-1]} for label,v in values.items()}
                comparisons = {}
                for baseline, candidate in [('A','B'), ('Aprime','B'), ('A','Aprime')]:
                    changes = {key: (stats[candidate][key]/stats[baseline][key]-1)*100 for key in ('median_ns','p95_ns')}
                    comparisons[f'{candidate}/{baseline}'] = {**changes, 'within_guideline': changes['median_ns'] <= 1 and changes['p95_ns'] <= 2}
                summary[name] = {'statistics': stats, 'comparisons': comparisons, 'verdict': 'operator review required; layout/noise uncertainty not resolved automatically'}
            else:
                summary[name] = {'functional_samples_per_engine': rounds, 'checksums_ok': True, 'timing_verdict': None}
            print(name, 'complete', flush=True)
    for label, info in builds.items():
        if sha(info['binary']) != info['sha256']:
            raise RuntimeError(f'{label} binary changed during run')
    save_json(out / 'summary.json', {'mode': args.mode, 'cases': summary})


if __name__ == '__main__':
    main()

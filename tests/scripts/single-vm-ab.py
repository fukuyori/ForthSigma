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
import struct
import subprocess
import tarfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
BASE = '35523f676836134c4fbaed19e3d01d2a23ec2a92'
LABELS = ('A', 'Aprime', 'B')
LAYOUTS = ('base', 'tail64', 'hot16', 'hot32')
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


PROBE_BYTES = {'base': 0, 'tail64': 64, 'hot16': 16, 'hot32': 32}


def layout_source(layout):
    """The padding contract is bytes, independent of the target instruction width."""
    size = PROBE_BYTES[layout]
    section = '.text' if layout == 'tail64' else '.text.hot'
    return (f'#define PROBE_BYTES {size}\n'
            '#if defined(__aarch64__) || defined(__arm64__)\n'
            '#define NOP_BYTES 4\n'
            '#elif defined(__x86_64__) || defined(_M_X64)\n'
            '#define NOP_BYTES 1\n'
            '#else\n#error unsupported layout probe architecture\n#endif\n'
            '#if PROBE_BYTES % NOP_BYTES\n#error padding bytes must be divisible by instruction width\n#endif\n'
            '#define STR1(x) #x\n#define STR(x) STR1(x)\n'
            '#if defined(__APPLE__)\n#define SEC "__TEXT,__text"\n'
            '#elif defined(_WIN32)\n#define SEC ".text$a"\n'
            f'#else\n#define SEC "{section}"\n#endif\n'
            '__attribute__((noinline,used,aligned(16),section(SEC))) '
            'void svab_layout_probe(void) { __asm__ __volatile__('
            '".globl svab_padding_begin\\nsvab_padding_begin:\\n" '
            '".rept " STR(PROBE_BYTES / NOP_BYTES) "\\nnop\\n.endr\\n" '
            '".globl svab_padding_end\\nsvab_padding_end:\\n"); }\n')


def probe_padding(assembly, symbols=''):
    """Measure the marked NOP region from disassembler addresses and aliases."""
    addresses = []
    for name in ('svab_padding_begin', 'svab_padding_end'):
        match = re.search(r'^([0-9a-fA-F]+) (?:<' + name + r'>|' + name + r'):\s*$', assembly, re.M)
        if not match:
            # Same-address aliases may be omitted from disassembly headers.
            match = re.search(r'^([0-9a-fA-F]+)\s+.*\s' + name + r'\s*$', symbols, re.M)
        if not match:
            return None
        addresses.append(int(match[1], 16))
    rows = []
    for line in assembly.splitlines():
        match = re.match(r'^\s*([0-9a-fA-F]+):\s+((?:[0-9a-fA-F]{2,8}\s+)+)\s*(.*)$', line)
        if match and addresses[0] <= int(match[1], 16) < addresses[1]:
            if not re.match(r'nop\b', match[3]):
                raise RuntimeError('non-NOP instruction in probe padding')
            rows.append((int(match[1], 16), sum(len(x)//2 for x in match[2].split())))
    cursor = addresses[0]
    for address, width in rows:
        if address != cursor:
            raise RuntimeError('gap in probe padding disassembly')
        cursor += width
    return cursor - addresses[0] if cursor == addresses[1] else None


def apply_layout(path, layout, patch):
    """Only the copied build.zig changes; WriteFiles supplies the extra C input."""
    before = path.read_text()
    if layout == 'base':
        patch.write_text('')
        return
    c = layout_source(layout)
    addition = ('    const layout_c = b.addWriteFiles().add("svab-layout.c", '
                + json.dumps(c) + ');\n'
                '    exe.root_module.addCSourceFile(.{ .file = layout_c, .flags = &.{"-std=gnu11"} });\n'
                '    exe.forceUndefinedSymbol("svab_padding_begin");\n'
                '    exe.forceUndefinedSymbol("svab_padding_end");\n'
                '    exe.forceUndefinedSymbol(if (target.result.os.tag == .macos) "_svab_layout_probe" else "svab_layout_probe");\n')
    anchor = '    exe.root_module.addOptions("build_options", options);\n'
    if before.count(anchor) != 1:
        raise RuntimeError('layout build.zig anchor changed or nonunique')
    after = before.replace(anchor, anchor + addition)
    path.write_text(after)
    patch.write_text(''.join(difflib.unified_diff(
        before.splitlines(True), after.splitlines(True),
        fromfile='a/build.zig', tofile='b/build.zig')))


def prepare(out, jobs, layout):
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
        apply_layout(sources / label / 'build.zig', layout, out / f'{label}-layout.patch')
        cwd = ROOT if label == 'B' and layout == 'base' else sources / label
        prefix = out / 'build' / label
        args = ['zig', 'build', '-Doptimize=ReleaseFast', '-Ddebug=false', '-Dstrip=false', '--prefix', prefix, f'-j{jobs}']
        if label != 'A':
            args += ['-Dtask-trace=false', '-Dtask-acceptance=false']
        try:
            build_log = command(args, cwd)
        except subprocess.CalledProcessError as error:
            (out / f'{label}-build.log').write_bytes(error.output)
            raise
        (out / f'{label}-build.log').write_bytes(build_log)
        builds[label] = {'cwd': str(cwd), 'command': list(map(str, args)), 'binary': str(prefix / 'bin' / ('sigma' + suffix)), 'layout': layout}
    save_json(out / 'builds.json', builds)
    return builds


def windows_symbols(out, label, binary, pdbutil, assembly):
    """Resolve PDB section-relative records through the executable PE headers."""
    pe = Path(binary).read_bytes()
    header = struct.unpack_from('<I', pe, 0x3c)[0]
    if pe[header:header+4] != b'PE\0\0':
        raise RuntimeError('invalid PE signature')
    count = struct.unpack_from('<H', pe, header+6)[0]
    optional_size = struct.unpack_from('<H', pe, header+20)[0]
    optional = header+24
    if struct.unpack_from('<H', pe, optional)[0] != 0x20b:
        raise RuntimeError('expected PE32+ executable')
    image_base = struct.unpack_from('<Q', pe, optional+24)[0]
    alignment = struct.unpack_from('<I', pe, optional+32)[0]
    sections = []
    for i in range(count):
        offset = optional+optional_size+40*i
        sections.append({'number': i+1, 'name': pe[offset:offset+8].rstrip(b'\0').decode(),
                         'virtual_address': struct.unpack_from('<I', pe, offset+12)[0],
                         'virtual_address_mod64': struct.unpack_from('<I', pe, offset+12)[0] % 64})
    pdb = Path(binary).with_suffix('.pdb')
    dump = command([pdbutil, 'dump', '--symbols', '--publics', pdb]).decode(errors='replace')
    (out / f'{label}-pdb-symbols.txt').write_text(dump)
    modules = list(re.finditer(r'Mod \d+ \| `([^`]+)`:', dump))
    records = []
    pattern = r'S_[LG]PROC32(?:_ID)? \[.*?\] `([^`]+)`\s+parent = .*?addr = (\d+):(\d+), code size = (\d+)'
    for match in re.finditer(pattern, dump):
        name, section, offset, size = match.groups()
        module = next((m[1] for m in reversed(modules) if m.start() < match.start()), None)
        section, offset, size = int(section), int(offset), int(size)
        if not 1 <= section <= len(sections):
            raise RuntimeError(f'invalid PDB section: {section}')
        address = image_base+sections[section-1]['virtual_address']+offset
        records.append({'symbol': name, 'module': module, 'section': section, 'offset': offset, 'size': size,
                        'address': address, 'address_hex': hex(address), 'mod64': address % 64,
                        'size_source': 'PDB code size'})
    functions = [r for r in records if any(t in r['symbol'] for t in
                 ('runOperations', 'executeWord', 'executeBuiltin', 'executeCompiled'))]
    probe = next((r for r in records if r['symbol'] == 'svab_layout_probe'), None)
    # Global inline-assembly labels are public symbols rather than procedure records.
    aliases = []
    for m in re.finditer(r'S_PUB32 \[.*?\] `([^`]+)`\s+flags = .*?addr = (\d+):(\d+)', dump):
        name, section, offset = m.groups()
        if name in ('svab_padding_begin', 'svab_padding_end'):
            address = image_base+sections[int(section)-1]['virtual_address']+int(offset)
            aliases.append(f'{address:x} T {name}\n')
    if probe:
        aliases.append(f"{probe['address']:x} T svab_layout_probe\n")
    rows = [(int(m[1], 16), line) for line in assembly.splitlines(True)
            if (m := re.match(r'^\s*([0-9a-fA-F]+):', line))]
    selected = []
    for function in functions:
        start = function['address']
        selected.append(f"\n{start:x} <{function['symbol']}>:\n")
        block = [line for address, line in rows if start <= address < start+function['size']]
        if not block:
            raise RuntimeError(f"no disassembly for {function['symbol']}")
        selected.extend(block)
    (out / f'{label}-normal-functions.txt').write_text(''.join(selected))
    zig_addresses = [r['address'] for r in records if r['module'] and r['module'].endswith('sigma_zcu.obj')]
    metadata = {'pdb': str(pdb), 'pdb_sha256': sha(pdb), 'pdbutil': str(pdbutil),
                'pdbutil_version': command([pdbutil, '--version']).decode().strip(),
                'image_base': image_base, 'image_base_mod64': image_base % 64,
                'section_alignment': alignment, 'section_alignment_mod64': alignment % 64,
                'sections': sections,
                'first_zig_procedure_address': hex(min(zig_addresses)) if zig_addresses else None,
                'probe_precedes_zig_code': probe['address'] < min(zig_addresses) if probe and zig_addresses else None,
                'probe_input_section': '.text$a' if probe else None,
                'probe_precedes_target_functions': (probe['address'] < min(r['address'] for r in functions))
                    if probe and functions else None}
    return functions, probe, ''.join(aliases), metadata


def disassemble(out, builds, objdump, pdbutil=None):
    sections = {}
    layouts = {}
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
            if re.match(r'^[0-9a-fA-F]+ (?:<.+>|[^\s]+):\s*$', line):
                keep = any(name in line for name in ('runOperations', 'executeWord', 'executeBuiltin', 'executeCompiled'))
            if keep:
                selected.append(line)
        (out / f'{label}-normal-functions.txt').write_text(''.join(selected))
        try:
            symbols = command([objdump, '-t', binary]).decode(errors='replace')
        except subprocess.CalledProcessError as error:
            if os.name != 'nt':
                raise
            symbols = error.output.decode(errors='replace')
        (out / f'{label}-symbols.txt').write_text(symbols)
        functions = []
        targets = ('runOperations', 'executeWordMode', 'executeBuiltin')
        if os.name != 'nt':
            for line in symbols.splitlines():
                fields = line.split()
                # ELF: address, flags, section, size, name. Mach-O lacks sizes.
                if len(fields) >= 5 and any(t in fields[-1] for t in targets):
                    try:
                        address, size = int(fields[0], 16), int(fields[-2], 16)
                    except ValueError:
                        continue
                    functions.append({'symbol': fields[-1], 'address': address,
                                      'address_hex': hex(address), 'size': size,
                                      'mod64': address % 64, 'size_source': 'objdump symbol table'})
            if not functions:
                # Mach-O nm gives ordered symbol addresses; disassembly gives code extent.
                nm = command(['nm', '-n', binary]).decode(errors='replace')
                (out / f'{label}-nm.txt').write_text(nm)
                nm_addresses = {int(m[1], 16) for m in re.finditer(r'^([0-9a-fA-F]+)\s+[tT]\s+', nm, re.M)}
                headers = list(re.finditer(r'^([0-9a-fA-F]+) (?:<(.+)>|([^\s]+)):\s*$', assembly, re.M))
                for i, header in enumerate(headers):
                    symbol = header[2] or header[3]
                    if not any(t in symbol for t in targets):
                        continue
                    address = int(header[1], 16)
                    if address not in nm_addresses:
                        raise RuntimeError(f'{label}: disassembly target absent from nm: {symbol}')
                    block = assembly[header.end():headers[i+1].start() if i+1 < len(headers) else len(assembly)]
                    ends = [int(m[1], 16) + sum(len(x)//2 for x in m[2].split()) for m in re.finditer(
                        r'^\s*([0-9a-fA-F]+):\s+((?:[0-9a-fA-F]{2,8}\s+)+)', block, re.M)]
                    functions.append({'symbol': symbol, 'address': address,
                                      'address_hex': hex(address), 'size': max(ends)-address if ends else None,
                                      'mod64': address % 64, 'size_source': 'nm address / disassembly extent (may include padding)'})
        probe = re.search(r'^([0-9a-fA-F]+) (?:<_?svab_layout_probe>|_?svab_layout_probe):\s*$', assembly, re.M)
        if not probe:
            # A disassembler can print the padding label instead of its function alias.
            probe = re.search(r'^([0-9a-fA-F]+)\s+.*\s_?svab_layout_probe\s*$', symbols, re.M)
        windows = {}
        if os.name == 'nt':
            functions, pdb_probe, aliases, windows = windows_symbols(out, label, binary, pdbutil, assembly)
            symbols += '\n' + aliases
            probe = re.search(r'^([0-9a-fA-F]+) T svab_layout_probe$', aliases, re.M)
        actual_bytes = probe_padding(assembly, symbols)
        layout = info.get('layout', 'unknown')
        layouts[label] = {'layout': layout, 'functions': functions,
                          'symbols_status': 'available' if functions else 'missing',
                          'probe_retained': bool(probe), 'probe_bytes': PROBE_BYTES.get(layout), 'probe_actual_bytes': actual_bytes, 'probe_address': hex(int(probe[1], 16)) if probe else None}
        layouts[label].update(windows)
        save_json(out / 'layout.json', layouts)
        if layout not in ('base', 'unknown') and not probe:
            raise RuntimeError(f'{label}: retained layout probe missing from disassembly')
        if layout not in ('base', 'unknown') and actual_bytes != PROBE_BYTES[layout]:
            raise RuntimeError(f'{label}: probe padding {actual_bytes} bytes != {PROBE_BYTES[layout]} expected')
        if not functions:
            raise RuntimeError(f'{label}: target function symbols missing')

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
    save_json(out / 'layout.json', layouts)
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
    p.add_argument('--pdbutil', default=shutil.which('llvm-pdbutil') or r'C:\Program Files\LLVM\bin\llvm-pdbutil.exe')
    p.add_argument('--jobs', type=int, default=2)
    p.add_argument('--layout', choices=LAYOUTS, default='base', help='matched copied-build layout; base preserves the original build')
    args = p.parse_args()
    if args.builds and args.layout != 'base':
        p.error('--layout selects fresh builds; reused builds retain their recorded layout')
    if args.mode == 'measure' and (not args.rounds or not args.confirmed or not args.environment):
        p.error('measure requires --rounds, --confirmed and --environment fixed beforehand')
    if args.iterations < 1 or args.warmup < 1 or (args.rounds is not None and args.rounds < 1):
        p.error('counts must be positive')
    out = args.out.resolve(); out.mkdir(parents=True, exist_ok=False)
    os.environ['ZIG_GLOBAL_CACHE_DIR'] = str(ROOT / '.work/codex-cache/global')
    os.environ['ZIG_LOCAL_CACHE_DIR'] = str(ROOT / '.work/codex-cache/local')
    meta = {'args': vars(args) | {'out': str(out), 'builds': str(args.builds)}, 'platform': platform.platform(), 'head': command(['git','rev-parse','HEAD']).decode().strip(), 'status': command(['git','status','--short']).decode(), 'zig': command(['zig','version']).decode().strip(), 'A': BASE, 'script_sha256': sha(__file__), 'baseline_archive_sha256': sha(args.builds.resolve().parent / 'A.tar') if args.builds and (args.builds.resolve().parent / 'A.tar').exists() else None, 'zig_binary_sha256': sha(shutil.which('zig')), 'objdump_version': command([args.objdump, '--version']).decode().splitlines()[0]}
    save_json(out / 'manifest.json', meta)
    builds = json.loads(args.builds.read_text()) if args.builds else prepare(out, args.jobs, args.layout)
    disassemble(out, builds, args.objdump, args.pdbutil)
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

#!/usr/bin/env python3
"""Task API representative configurations. No performance/time measurement.

Artifacts and command output stay in .work/task-public-matrix. No packaging,
Git changes or external OS execution. See TASK_CONTROL_CONFIG_MATRIX.md.
"""
import argparse
import json
import os
import platform
import re
import uuid
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
CONFIGS = {
    'C00': dict(audio=False, graphics=False, extension=False),
    'C01': dict(audio=False, graphics=False),
    'C02': dict(audio=False, extension=False),
    'C03': dict(audio=False),
    'C04': dict(graphics=False, extension=False),
    'C05': dict(graphics=False),
    'C06': dict(extension=False),
    'C07': {},
    'C08': dict(audio=False, graphics=False, debug=False),
    'C09': dict(audio=False, graphics=False, files=False),
    'C10': dict(debug=False, files=False),
    'C11': dict(audio=False, graphics=False, files=False, debug=False,
                float=False, image=False, x11=False),
    'C12': dict(audio=False, graphics=False, extension=False, debug=False),
    'C13': dict(audio=False, extension=False, debug=False),
    'C14': dict(debug=False, help=False),
    'C15': dict(debug=False, tools=False),
    'C16': dict(audio=False, debug=False, x11=False),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--configs', nargs='+', choices=CONFIGS, default=list(CONFIGS))
    parser.add_argument('--build-only', action='store_true',
                        help='compile executable and core/host/runtime tests; do not run target code')
    parser.add_argument('--target', help='Zig target triple (requires --build-only)')
    parser.add_argument('--fresh-cache', action='store_true',
                        help='use new checkout-local global and local Zig caches')
    args = parser.parse_args()
    if args.target and not args.build_only:
        parser.error('--target requires --build-only; run native tests on the target OS')
    folder = ROOT / '.work/task-public-matrix'
    if args.build_only:
        folder /= args.target or 'native-build-only'
    folder.mkdir(parents=True, exist_ok=True)
    # Keep compiler cache writes inside this checkout on Windows and Linux alike.
    cache_root = ROOT / '.work' / ('fresh-' + uuid.uuid4().hex) if args.fresh_cache else ROOT
    global_cache = cache_root / '.zig-global-cache'
    local_cache = cache_root / '.zig-cache'
    os.environ['ZIG_GLOBAL_CACHE_DIR'] = str(global_cache)
    cache_flags = ['--cache-dir', str(local_cache),
                   '--summary', 'all']
    environment = dict(platform=platform.platform(), os=sys.platform, arch=platform.machine(),
                       zig_version=subprocess.check_output(['zig', 'version'], cwd=ROOT).decode().strip(),
                       python_version=platform.python_version(), DISPLAY=os.environ.get('DISPLAY'),
                       WAYLAND_DISPLAY=os.environ.get('WAYLAND_DISPLAY'), TERM=os.environ.get('TERM'),
                       tty={name: stream.isatty() for name, stream in
                            [('stdin', sys.stdin), ('stdout', sys.stdout), ('stderr', sys.stderr)]},
                       fresh_cache=args.fresh_cache, global_cache=str(global_cache),
                       local_cache=str(local_cache))
    report = []
    (folder / 'results.json').write_text('[]\n', encoding='utf-8')
    commands = []
    names = re.findall(r'\.\{ "(TASK-[^"]+)",',
                       (ROOT / 'src/core/words_extension.zig').read_text(encoding='utf-8'))
    if len(names) != 58 or len(set(names)) != 58:
        parser.error('expected exactly 58 distinct public TASK- words')

    def command(argv, log):
        if argv[:2] == ['zig', 'build']:
            argv = [*argv, *cache_flags]
        entry = dict(argv=argv, log=str(log.relative_to(ROOT)))
        commands.append(entry)
        (folder / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n', encoding='utf-8')
        outcome = subprocess.run(argv, cwd=ROOT, input=b'', capture_output=True)
        log.write_bytes(outcome.stdout + outcome.stderr)
        entry['exit_code'] = outcome.returncode
        (folder / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n', encoding='utf-8')
        if outcome.returncode:
            raise RuntimeError(f'{argv}: exit {outcome.returncode}; {log}')
        return outcome.stdout

    try:
        for name in args.configs:
            features = CONFIGS[name]
            flags = [f'-D{k}={str(v).lower()}' for k, v in features.items()]
            if args.target:
                flags.append(f'-Dtarget={args.target}')
            prefix = folder / name
            print(f'{name}: testing', flush=True)
            if args.build_only:
                command(['zig', 'build', 'core-check', 'host-check', 'runtime-check',
                         'freestanding', '-j2', *flags, '--prefix', str(prefix)],
                        folder / f'{name}-compile.log')
                command(['zig', 'build', '-j2', *flags, '--prefix', str(prefix)],
                        folder / f'{name}-build.log')
                report.append(dict(config=name, features=features, target=args.target,
                                   build=True, test_compile=True, executed=False, environment=environment,
                                   runtime_passed=None, runtime_skipped=None))
                (folder / 'results.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
                print(f'{name}: compiled (not executed)', flush=True)
                continue
            command(['zig', 'build', 'test', '-j2', *flags], folder / f'{name}-test.log')
            command(['zig', 'build', '-j2', *flags, '--prefix', str(prefix)], folder / f'{name}-build.log')
            command(['zig', 'build', 'runtime-check', '-j2', *flags, '--prefix', str(prefix)],
                    folder / f'{name}-runtime-build.log')
            arch = {'amd64': 'x86_64', 'arm64': 'aarch64'}.get(
                platform.machine().lower(), platform.machine().lower())
            os_tag = {'win32': 'windows', 'darwin': 'macos'}.get(sys.platform, sys.platform)
            runtime = prefix / 'runtime-tests' / f'{arch}-{os_tag}' / (
                'test.exe' if sys.platform == 'win32' else 'test')
            command([str(runtime)], folder / f'{name}-runtime.log')
            runtime_log = (folder / f'{name}-runtime.log').read_text(encoding='utf-8')
            for contract in (
                'runtime deadlines keep a single deadline and handle the whole signed range',
                'runtime clock failures and sticky cancellation are observable',
                'runtime resource identity rejects stale, foreign, wrong-kind and exhausted handles',
                'runtime signal ownership rejects cross-owner and out-of-order releases',
                'runtime identities and table lifetimes reject foreign and previous incarnations',
                'runtime injected wake and clock preserve failures and ownership',
                'runtime producers can notify while the owner begins shutdown',
            ):
                if f'{contract}...OK' not in runtime_log:
                    raise RuntimeError(f'{name}: runtime contract did not pass: {contract}')
            counts = re.search(r'(\d+) passed; (\d+) skipped; (\d+) failed', runtime_log)
            if not counts or int(counts[3]):
                raise RuntimeError(f'{name}: missing or failing runtime summary')
            capability_acceptance = []
            if features.get('extension', True):
                for feature, contract in [
                    ('files', 'public many wait preserves inputs on Ctrl-C equivalent and combines IO reasons'),
                    ('graphics', 'public paint many validates arguments, backend, lifetime and simultaneous events'),
                ]:
                    if features.get(feature, True):
                        if f'{contract}...OK' not in runtime_log:
                            raise RuntimeError(f'{name}: enabled {feature} contract did not pass')
                        # Paint acceptance branch requires a supported native backend.
                        if feature != 'graphics' or sys.platform == 'win32' or (sys.platform == 'linux' and features.get('x11', True)):
                            capability_acceptance.append(feature + '-controlled-runtime')
            exe = prefix / 'bin' / ('sigma.exe' if sys.platform == 'win32' else 'sigma')
            enabled = features.get('extension', True)
            source = ('REQUIRE-EXTENSION ALSO EXTENSION ' if enabled else '')
            source += ' '.join(f'[DEFINED] {word} .' for word in names) + ' BYE'
            output = command([str(exe), '-e', source], folder / f'{name}-words.log')
            expected = ('-1 ' if enabled else '0 ').encode() * len(names)
            if output != expected:
                raise RuntimeError(f'{name}: public vocabulary mismatch')
            source = ('REQUIRE-EXTENSION ALSO EXTENSION ' if enabled else '')
            source += '[DEFINED] EXEC-LIMITED . [DEFINED] DBG . BYE'
            output = command([str(exe), '-e', source], folder / f'{name}-debug.log')
            debug = features.get('debug', True)
            expected = (b'-1 ' if enabled and debug else b'0 ') + (b'-1 ' if debug else b'0 ')
            if output != expected:
                raise RuntimeError(f'{name}: debug vocabulary mismatch: {output!r}')
            if enabled:
                output = command([str(exe), 'tests/scripts/check-task-public.fs'], folder / f'{name}-forth.log')
                if output.replace(b'\r\n', b'\n') != b'task public ABI passed\n':
                    raise RuntimeError(f'{name}: Forth checks: {output!r}')
                if debug:
                    source = ('REQUIRE-EXTENSION ALSO EXTENSION '
                              ': FOREVER BEGIN AGAIN ; : SHORT 42 ; '
                              'TASK-SNAPSHOT THROW CONSTANT SNAP '
                              'SNAP S" FOREVER" 0 0 TASK-I1 0 TASK-SUBMIT THROW CONSTANT JOB '
                              "' FOREVER 20 EXEC-LIMITED . "
                              'JOB TASK-CANCEL THROW JOB -1 TASK-WAIT THROW DROP . '
                              'JOB TASK-RELEASE THROW SNAP TASK-SNAPSHOT-RELEASE THROW '
                              "' SHORT 0 EXEC-LIMITED . . BYE")
                    output = command([str(exe), '-e', source], folder / f'{name}-budget.log')
                    if output != b'-280 5 0 42 ':
                        raise RuntimeError(f'{name}: execution budgets: {output!r}')
                for feature, kind in [('files', 2), ('graphics', 5)]:
                    if feature == 'files' and features.get(feature, True):
                        continue
                    # No native window is opened: paint must reject even with graphics enabled.
                    source = ('REQUIRE-EXTENSION ALSO EXTENSION CREATE T '
                              f'{kind} , 0 , 1 , 0 , 0 , CREATE E 32 ALLOT '
                              'T 1 E 1 0 TASK-WAIT-MANY . . . BYE')
                    output = command([str(exe), '-e', source], folder / f'{name}-{feature}.log')
                    if output != b'-311 0 0 ':
                        raise RuntimeError(f'{name}: {feature} capability: {output!r}')
            report.append(dict(config=name, features=features, test=True, build=True,
                               runtime=True, environment=environment,
                               runtime_passed=int(counts[1]), runtime_skipped=int(counts[2]),
                               runtime_failed=int(counts[3]), capability_acceptance=capability_acceptance,
                               paint_without_window_rejected=enabled, public_words=len(names),
                               public_words_present=len(names) if enabled else 0, forth=enabled,
                               debug_vocabulary=True, budget=enabled and debug,
                               capability_rejections=[f for f in ('files', 'graphics')
                                                      if enabled and not features.get(f, True)]))
            (folder / 'results.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
            print(f'{name}: passed', flush=True)
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

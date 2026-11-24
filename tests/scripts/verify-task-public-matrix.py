#!/usr/bin/env python3
"""Task API representative configurations. No performance/time measurement.

Artifacts and command output stay in .work/task-public-matrix. No packaging,
Git changes or external OS execution. See TASK_CONTROL_CONFIG_MATRIX.md.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
CONFIGS = {
    'C00': dict(audio=False, graphics=False, extension=False),
    'C01': dict(audio=False, graphics=False),
    'C06': dict(extension=False),
    'C07': {},
    'C08': dict(audio=False, graphics=False, debug=False),
    'C09': dict(audio=False, graphics=False, files=False),
    'C11': dict(audio=False, graphics=False, files=False, debug=False,
                float=False, image=False, x11=False),
    'C13': dict(audio=False, extension=False, debug=False),
    'C14': dict(debug=False, help=False),
    'C15': dict(debug=False, tools=False),
    'C16': dict(audio=False, debug=False, x11=False),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--configs', nargs='+', choices=CONFIGS, default=list(CONFIGS))
    args = parser.parse_args()
    folder = ROOT / '.work/task-public-matrix'
    folder.mkdir(parents=True, exist_ok=True)
    report = []
    import re
    names = re.findall(r'\.\{ "(TASK-[^"]+)",',
                       (ROOT / 'src/core/words_extension.zig').read_text(encoding='utf-8'))

    def command(argv, log):
        outcome = subprocess.run(argv, cwd=ROOT, input=b'', capture_output=True)
        log.write_bytes(outcome.stdout + outcome.stderr)
        if outcome.returncode:
            raise RuntimeError(f'{argv}: exit {outcome.returncode}; {log}')
        return outcome.stdout

    try:
        for name in args.configs:
            features = CONFIGS[name]
            flags = [f'-D{k}={str(v).lower()}' for k, v in features.items()]
            prefix = folder / name
            print(f'{name}: testing', flush=True)
            command(['zig', 'build', 'test', '-j2', *flags], folder / f'{name}-test.log')
            command(['zig', 'build', '-j2', *flags, '--prefix', str(prefix)], folder / f'{name}-build.log')
            exe = prefix / 'bin' / ('sigma.exe' if sys.platform == 'win32' else 'sigma')
            enabled = features.get('extension', True)
            source = ('REQUIRE-EXTENSION ALSO EXTENSION ' if enabled else '')
            source += ' '.join(f'[DEFINED] {word} .' for word in names) + ' BYE'
            output = command([str(exe), '-e', source], folder / f'{name}-words.log')
            expected = ('-1 ' if enabled else '0 ').encode() * len(names)
            if output != expected:
                raise RuntimeError(f'{name}: public vocabulary mismatch')
            if enabled:
                output = command([str(exe), 'tests/scripts/check-task-public.fs'], folder / f'{name}-forth.log')
                if output.replace(b'\r\n', b'\n') != b'task public ABI passed\n':
                    raise RuntimeError(f'{name}: Forth checks: {output!r}')
                for feature, kind in [('files', 2), ('graphics', 5)]:
                    if features.get(feature, True):
                        continue
                    source = ('REQUIRE-EXTENSION ALSO EXTENSION CREATE T '
                              f'{kind} , 0 , 1 , 0 , 0 , CREATE E 32 ALLOT '
                              'T 1 E 1 0 TASK-WAIT-MANY . . . BYE')
                    output = command([str(exe), '-e', source], folder / f'{name}-{feature}.log')
                    if output != b'-311 0 0 ':
                        raise RuntimeError(f'{name}: {feature} capability: {output!r}')
            report.append(dict(config=name, features=features, test=True, build=True,
                               public_words=len(names), forth=enabled))
            (folder / 'results.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
            print(f'{name}: passed', flush=True)
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

#!/usr/bin/env python3
"""Compare public EXTENSION words with the pinned Unicode GraphemeBreakTest."""
import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def run(sigma):
    data_root = ROOT / 'tests/data/unicode-18.0.0'
    manifest = json.loads((data_root / 'manifest.json').read_text(encoding='utf-8'))
    fixture = data_root / 'GraphemeBreakTest.txt'
    if hashlib.sha256(fixture.read_bytes()).hexdigest() != manifest['files'][fixture.name]['sha256']:
        raise ValueError('GraphemeBreakTest hash mismatch')
    lines = ['REQUIRE-EXTENSION ALSO EXTENSION', 'CREATE GB-BUFFER 4096 ALLOT']
    expected = []
    labels = []
    cases = 0
    for number, line in enumerate(fixture.read_text(encoding='utf-8').splitlines(), 1):
        fields = line.split('#')[0].split()
        if not fields:
            continue
        data = bytearray()
        boundaries = []
        for field in fields:
            if field == '÷':
                boundaries.append(len(data))
            elif field != '×':
                data.extend(chr(int(field, 16)).encode('utf-8'))
        if len(data) > 4096:
            raise ValueError('fixture exceeds buffer')
        for offset, value in enumerate(data):
            lines.append(f'{value} GB-BUFFER {offset} + C!')
        # Test every cluster boundary from both ends, retaining required context.
        for start, end in zip(boundaries, boundaries[1:]):
            lines.append(f'GB-BUFFER {start} + {len(data)-start} X-GRAPHEME .')
            lines.append(f'GB-BUFFER {end} X-GRAPHEME-LAST .')
            expected.extend([end-start, end-start])
            labels.extend([f'line {number} first at {start}', f'line {number} last at {end}'])
        cases += 1
    lines.extend(['GB-BUFFER 0 X-GRAPHEME .', 'GB-BUFFER 0 X-GRAPHEME-LAST .', 'BYE'])
    expected.extend([0, 0])
    labels.extend(['empty first', 'empty last'])
    with tempfile.TemporaryDirectory(prefix='sigma-graphemes-') as temporary:
        source = Path(temporary) / 'check.fs'
        source.write_text('\n'.join(lines)+'\n', encoding='utf-8')
        result = subprocess.run([str(sigma.resolve()), str(source)], cwd=ROOT, capture_output=True, text=True, encoding='utf-8', timeout=120)
    if result.returncode or result.stderr.strip():
        raise RuntimeError(f'{result.returncode}: {result.stderr}\n{result.stdout[-2000:]}')
    actual = [int(value) for value in result.stdout.split()]
    if len(actual) != len(expected):
        raise AssertionError(f'expected {len(expected)} values, got {len(actual)}')
    for label, wanted, got in zip(labels, expected, actual):
        if wanted != got:
            raise AssertionError(f'{label}: expected {wanted}, got {got}')
    return {'unicode': '18.0.0', 'cases': cases, 'public_word_checks': len(expected)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sigma', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = run(args.sigma)
    if args.output:
        args.output.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(report))

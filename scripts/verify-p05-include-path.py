#!/usr/bin/env python3
"""Compare configured source lookup behavior; no reference implementation copied."""
import argparse
import json
import pathlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--gforth-build', type=pathlib.Path, required=True)
args = parser.parse_args()
root = pathlib.Path('.work/p05-include-path-check').resolve()
for directory in ['cwd', 'lib', 'source']:
    (root / directory).mkdir(parents=True, exist_ok=True)
for directory, value in [('cwd', 11), ('lib', 22), ('source', 33)]:
    (root / directory / 'item.fs').write_text(f'{value} .\n')
(root / 'source/main.fs').write_text('INCLUDE item.fs\n')
(root / 'source/explicit.fs').write_text('INCLUDE ./item.fs\n')
(root / 'source/count.fs').write_text('HITS 1+ TO HITS\n')
build = args.gforth_build.resolve()
commands = {
    'sigma': [str(pathlib.Path('zig-out/bin/sigma').resolve()), '--max-steps', '100000', '-e'],
    'gforth': [str(build / 'gforth-ditc'), '-p', str(build) + ':~+', '-i', str(build / 'gforth.fi'), '-e'],
}
cases = [
    ('first', 'FPATH PATH= cwd|lib INCLUDE item.fs'),
    ('reverse', 'FPATH PATH= lib|cwd INCLUDE item.fs'),
    ('fallback', 'FPATH PATH= missing|lib INCLUDE item.fs'),
    ('nested', 'FPATH PATH= cwd|lib INCLUDE ./source/main.fs'),
    ('explicit', 'FPATH PATH= cwd|lib INCLUDE ./source/explicit.fs'),
    ('source-entry', 'FPATH PATH= ./|cwd INCLUDE ./source/main.fs'),
    ('normalized', '0 VALUE HITS FPATH PATH= ~+ REQUIRE source/count.fs REQUIRE ./source/count.fs REQUIRE source/../source/count.fs HITS .'),
    ('absolute-alias', f'0 VALUE HITS FPATH PATH= ~+ REQUIRE source/count.fs REQUIRE {root}/source/count.fs HITS .'),
    ('exact-history', '0 VALUE HITS FPATH PATH= ~+ REQUIRE ./source/count.fs S" source/count.fs" INCLUDED? . S" ./source/count.fs" INCLUDED? .'),
    ('marker', '0 VALUE HITS FPATH PATH= ~+ MARKER BACK REQUIRE source/count.fs BACK REQUIRE source/count.fs HITS .'),
    ('empty-component', ': RUN S" item.fs" INCLUDED ; FPATH PATH= |cwd \' RUN CATCH .'),
    ('no-fallback', ': RUN S" cwd/item.fs" INCLUDED ; FPATH PATH= missing \' RUN CATCH .'),
]
results = []
for title, source in cases:
    outputs = {}
    for runtime, command in commands.items():
        result = subprocess.run(command + [source + ' DEPTH . BYE'], cwd=root,
                                input='', text=True, capture_output=True, timeout=15)
        assert result.returncode == 0, (title, runtime, result.stdout, result.stderr)
        outputs[runtime] = result.stdout
    assert outputs['sigma'] == outputs['gforth'], (title, outputs)
    results.append({'case': title, 'output': outputs['sigma']})
report = {'pass': True, 'comparisons': len(results), 'cases': results,
          'intentional_difference': 'Empty/unset FPATH retains Sigma legacy direct-cwd/raw-history loading.'}
(root / 'comparison.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False))

#!/usr/bin/env python3
"""The chip libraries against the chips' settings removed in tque 1199 (tque 1206).

Takes the commit before the removal (e90b6f6) and a commit with the libraries (HEAD by
default) as git worktrees in a new folder of this run under .work/1206 (it removes only
the worktrees it made), builds tests/data/chip-compare/old_probe.zig
and new_probe.zig in their src/core, plays the same 21 one-note cases on both, and
prints the measurements side by side as JSON: the fundamental (from the rising zero
crossings; for a noise only their rate, not the noise's own rate), the RMS, the zero
crossings a second, and the harmonics 2 to 8 against the first. No timing is measured.

The new side does not read include/: new_probe.zig writes the libraries' settings out
again, and src/tests/audio_test.zig checks that the libraries give them. A change to a
library needs the same change there. --new WORKTREE copies only src/core's sound files.

  python tests/scripts/compare-chip-libraries.py
  python tests/scripts/compare-chip-libraries.py --new 9e5860a
  python tests/scripts/compare-chip-libraries.py --new WORKTREE   (the files as they are now)
"""
import argparse, json, math, os, shutil, subprocess, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / '.work/1206'
DATA = ROOT / 'tests/data/chip-compare'
OLD = 'e90b6f6'


def run(args, cwd):
    r = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    assert r.returncode == 0, (args, r.stdout[-2000:], r.stderr[-2000:])
    return r.stdout


def working_side(folder, probe):
    """The sound files of src/core as they are now, copied (not a commit)."""
    core = folder / 'new/src/core'
    core.mkdir(parents=True)
    for f in (ROOT / 'src/core').glob('sound_*.zig'):
        shutil.copy(f, core / f.name)
    for f in ['measure.zig', 'cases.zig', probe]:
        shutil.copy(DATA / f, core / f)
    exe = folder / 'new-probe.exe'
    run(['zig', 'build-exe', '-OReleaseFast', '-lc', '-femit-bin=' + str(exe), 'src/core/' + probe], folder / 'new')
    status = run(['git', 'status', '--porcelain', '--', 'src/core'], ROOT)
    return 'WORKTREE at ' + run(['git', 'rev-parse', 'HEAD'], ROOT).strip() + (' with changes' if status else ''), json.loads(run([str(exe)], folder))


def side(folder, name, commit, probe):
    tree = folder / name
    assert not tree.exists(), tree
    run(['git', 'worktree', 'add', '--detach', str(tree), commit], ROOT)
    try:
        for f in ['measure.zig', 'cases.zig', probe]:
            shutil.copy(DATA / f, tree / 'src/core' / f)
        exe = folder / (name + '-probe.exe')
        run(['zig', 'build-exe', '-OReleaseFast', '-lc', '-femit-bin=' + str(exe), 'src/core/' + probe], tree)
        result = json.loads(run([str(exe)], tree))
        sha = run(['git', 'rev-parse', 'HEAD'], tree).strip()
    finally:
        # Only the worktree this run made, which holds nothing but the copied probes.
        run(['git', 'worktree', 'remove', '--force', str(tree)], ROOT)
    return sha, result


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--new', default='HEAD', help='the commit with the chip libraries')
    a = p.parse_args()
    folder = WORK / ('run-%d-%d' % (int(time.time()), os.getpid()))
    folder.mkdir(parents=True)
    old_sha, old = side(folder, 'old', OLD, 'old_probe.zig')
    new_sha, new = working_side(folder, 'new_probe.zig') if a.new == 'WORKTREE' else side(folder, 'new', a.new, 'new_probe.zig')
    assert list(old) == list(new)
    cases = {}
    for k in old:
        o, n = old[k], new[k]
        cases[k] = {'old': o, 'new': n,
                    'f0_ratio': n['f0'] / o['f0'] if o['f0'] else None,
                    'rms_db': 20 * math.log10(n['rms'] / o['rms']) if o['rms'] and n['rms'] else None}
    report = {'old_commit': old_sha, 'new_commit': new_sha, 'rate': 48000,
              'scope': 'One note of two seconds a case, the first half second left out, the left side; '
                       'the old side is the chips\' settings of e90b6f6, the new side the standard sound '
                       'with the settings of the chip libraries (as src/tests/audio_test.zig checks them). '
                       'Not heard; no timing.',
              'cases': cases}
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

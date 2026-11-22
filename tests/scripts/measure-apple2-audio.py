#!/usr/bin/env python3
"""Apple II audio workloads. The default only verifies them; --measure needs the user's approval of the timing first.

Six workloads of 32768 stereo frames each. Every run, timed or not, compares the whole
PCM and the final state with the per-cycle oracle of verify-apple2-audio.py. With
--measure each workload runs in seven fresh processes, in rotated order, and the wall
time of the synthesis alone (not the set-up, the file write or the comparison) is kept.
"""
import argparse, hashlib, importlib.util, json, platform, statistics, subprocess, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('a2_oracle', ROOT / 'tests/scripts/verify-apple2-audio.py')
oracle = importlib.util.module_from_spec(spec); spec.loader.exec_module(oracle)
FRAMES = 32768; BLOCKS = FRAMES // 6; NUM, DEN = oracle.NUM, oracle.DEN
VIA1, VIA2 = 50176, 50304


# Block i sets register 8 of one AY (the first on even blocks) to i mod 16, by the manual's six writes, one cycle after the block starts.
HELPER = (': A2-BLOCK-VOLUME { i | tick base -- } i 6 * A2-NUM * A2-DEN / 1+ TO tick i 1 AND 128 * 50176 + TO base\n'
          '  8 base 1+ tick A2-EVENT! 7 base tick A2-EVENT! 4 base tick A2-EVENT!\n'
          '  i 15 AND base 1+ tick A2-EVENT! 6 base tick A2-EVENT! 4 base tick A2-EVENT! ;\n')


def card_init():
    return [(0, v, base + r) for base in (VIA1, VIA2) for v, r in [(255, 3), (7, 2), (4, 0)]]


def registers(base, values, tick):
    return [e for reg, value in enumerate(values) for e in oracle.psg_write(base, reg, value, tick)]


def order(events):
    """By tick only: the order of the accesses within one cycle is kept."""
    return sorted(events, key=lambda e: e[0])


def workloads():
    """name -> (slot, events queued before the work, Forth words run inside each block of 6 frames, the same as events)."""
    end = FRAMES * NUM // DEN
    tone = [(i * 1160, 0, 0xC030) for i in range(end // 1160 + 1)]
    start = lambda block: block * 6 * NUM // DEN + 1
    dense = [(start(b) + i * 31, 0, 0xC030) for b in range(BLOCKS) for i in range(4)]
    chord = card_init() + registers(VIA1, [244, 0, 194, 0, 163, 0, 0, 56, 11, 10, 10], 1) + registers(VIA2, [208, 3, 232, 1, 244, 0, 0, 56, 12, 11, 10], 2)
    mix = (card_init() + registers(VIA1, [28, 1, 227, 1, 82, 2, 9, 48, 12, 10, 16, 100, 0, 14], 1)
           + registers(VIA2, [208, 3, 60, 2, 9, 0, 20, 46, 16, 6, 13, 0, 16, 14], 2) + [(100 + i * 2320, 0, 0xC030) for i in range(250)])
    least = card_init() + registers(VIA1, [0, 0, 0, 0, 0, 0, 0, 0, 16, 16, 16, 1, 0, 8], 1) + registers(VIA2, [1, 0, 1, 0, 1, 0, 1, 0, 16, 16, 16, 1, 0, 10], 2)
    bus_base = card_init() + registers(VIA1, [244, 0, 0, 0, 0, 0, 0, 62, 15], 0) + registers(VIA2, [163, 0, 0, 0, 0, 0, 0, 62, 15], 1)
    bus = [e for b in range(BLOCKS) for e in oracle.psg_write(VIA2 if b & 1 else VIA1, 8, b % 16, start(b))]
    toggles = ' 4 0 DO J 6 * A2-NUM * A2-DEN / 1+ I 31 * + A2-TOGGLE-EVENT! LOOP'
    volume = ' I A2-BLOCK-VOLUME'
    return {'speaker_tone': (0, tone, '', []), 'speaker_dense': (0, [], toggles, dense), 'card_chord': (4, order(chord), '', []),
            'card_mix': (4, order(mix), '', []), 'card_least_periods': (4, order(least), '', []), 'card_8khz_bus': (4, bus_base, volume, bus)}


def program(slot, events, inner):
    work = (f': WORK {BLOCKS} 0 DO{inner} OUT I 24 * + 6 A2-RENDER LOOP OUT {BLOCKS * 24} + {FRAMES - BLOCKS * 6} A2-RENDER ;\n' if inner
            else f': WORK OUT {FRAMES} A2-RENDER ;\n')
    return f'CREATE OUT {FRAMES * 4} ALLOT\n{slot} A2-CARD! A2-RESET\n' + oracle.queue(events) + HELPER + work


def main():
    p = argparse.ArgumentParser(description=__doc__); p.add_argument('sigma', type=Path); p.add_argument('--measure', action='store_true')
    a = p.parse_args(); binary = a.sigma.resolve(); folder = ROOT / '.work/1180-1181'; folder.mkdir(parents=True, exist_ok=True)
    cases = {}
    for name, (slot, events, inner, during) in workloads().items():
        assert len(events) < 1024, (name, len(events))
        m = oracle.Model(slot); pcm = m.render(FRAMES, sorted(events + during, key=lambda e: e[0]))
        assert len(set(pcm)) > 8, name
        cases[name] = {'slot': slot, 'queued_events': len(events), 'events_during_work': len(during), 'program': program(slot, events, inner),
                       'pcm': pcm, 'state': m.state(), 'pcm_sha256': hashlib.sha256(pcm).hexdigest(), 'wall_us': []}

    def run(name):
        case = cases[name]
        with tempfile.TemporaryDirectory(prefix='measure-', dir=folder) as tmp:
            out = Path(tmp) / 'pcm.bin'; file = Path(tmp) / 'run.fs'
            file.write_text(oracle.DUMP + case['program'] + f'UTIME WORK UTIME 2SWAP D- D. S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD '
                            f'OUT {FRAMES * 4} FD WRITE-FILE THROW FD CLOSE-FILE THROW SNAP DEPTH . BYE\n', encoding='utf-8')
            r = subprocess.run([str(binary), 'include/apple2-audio.fs', str(file)], cwd=ROOT, input=b'', capture_output=True, timeout=600)
            assert r.returncode == 0 and not r.stderr, (name, r.returncode, r.stdout[:1000], r.stderr)
            values = list(map(int, r.stdout.split())); assert values.pop() == 0, 'stack leak'
            assert out.read_bytes() == case['pcm'], name
            assert values[1:1 + oracle.STATE] == case['state'] and values[1 + oracle.STATE] == values[2 + oracle.STATE], name
            return values[0]

    names = list(cases)
    for name in names: run(name)
    if a.measure:
        for round_ in range(7):
            for name in names[round_ % len(names):] + names[:round_ % len(names)]: cases[name]['wall_us'].append(run(name))
    report = {}
    for name, case in cases.items():
        report[name] = {k: case[k] for k in ('slot', 'queued_events', 'events_during_work', 'pcm_sha256')}
        if a.measure:
            median = statistics.median(case['wall_us'])
            report[name].update({'wall_us': case['wall_us'], 'median_ns_per_frame': round(median * 1000 / FRAMES, 2),
                                 'median_realtime_ratio': round(FRAMES / 48000 * 1e6 / median, 2)})
    files = ['tests/scripts/measure-apple2-audio.py', 'tests/scripts/verify-apple2-audio.py', 'include/apple2-audio.fs', 'include/zx-ay-levels.fs']
    print(json.dumps({'platform': platform.platform(), 'timing_enabled': a.measure, 'frames': FRAMES, 'scope': __doc__,
                      'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(), 'workloads': report,
                      'source_sha256_lf': {f: hashlib.sha256((ROOT / f).read_bytes().replace(b'\r\n', b'\n')).hexdigest() for f in files}}, indent=2))


if __name__ == '__main__': main()

#!/usr/bin/env python3
"""Six owned CHIP-8/XO workloads, fullPCM/state validation and seven-process timings."""
import argparse, hashlib, importlib.util, json, math, platform, statistics, struct, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('chip8_verifier', ROOT / 'tests/scripts/verify-chip8-audio.py')
oracle = importlib.util.module_from_spec(spec); spec.loader.exec_module(oracle)
FRAMES = 32768
BASE = [(0, 2, 1), (0, 3, oracle.PATTERN), (0, 0, 255)]


def workloads():
    changing = list(BASE)
    for i in range(128):
        tick = 113 + i * 123457
        kind = [1, 3, 0][i % 3]
        value = (i * 37 & 255) if kind == 1 else bytes((i + j * 13) & 255 for j in range(16)) if kind == 3 else [0, 2, 20][i % 5 % 3]
        changing.append((tick, kind, value))
    dense = list(BASE)
    for i in range(FRAMES // 6):
        tick = i * 6000 + 1
        dense.extend([(tick, 3, bytes((i + j * 13) & 255 for j in range(16))), (tick, 1, i * 37 & 255)])
    gates = [(0, 0, 255)] + [(i * 800000, 0, [0, 1, 2][i % 3]) for i in range(1, 41)]
    return {'classic': [(0, 0, 255)], 'xo_default': BASE,
            'xo_pitch255': BASE + [(0, 1, 255)], 'classic_60hz_gates': gates,
            'xo_changes128': changing, 'xo_8khz_pattern_pitch': dense}


def program(events, dense=False):
    constants = []; initial = []
    for i, (tick, kind, value) in enumerate(BASE if dense else events):
        if kind == 3:
            constants.append('CREATE P' + str(i) + ' ' + ' '.join(str(v) + ' C,' for v in value))
            initial.append(f'P{i} {tick} C8-PATTERN-EVENT!')
        else: initial.append(f'{value} {tick} C8-' + ['TIMER', 'PITCH', 'MODE'][kind] + '-EVENT!')
    source = '\n'.join(constants) + '\nCREATE OUT 65536 ALLOT\n'
    source += ': SETUP C8-RESET ' + '\n'.join(initial) + ' ;\n'
    if dense:
        source += '''CREATE STREAM-PAT 16 ALLOT
: MAKE-PAT { n -- } 16 0 DO n I 13 * + 255 AND STREAM-PAT I + C! LOOP ;
: WORK 5461 0 DO I MAKE-PAT STREAM-PAT I 6000 * 1+ C8-PATTERN-EVENT!
  I 37 * 255 AND I 6000 * 1+ C8-PITCH-EVENT! OUT I 12 * + 6 C8-RENDER LOOP
  OUT 65532 + 2 C8-RENDER ;
'''
    else: source += ': WORK OUT 32768 C8-RENDER ;\n'
    source += '2VARIABLE W0 2VARIABLE W1 2VARIABLE U0 2VARIABLE U1\n: CPU-ALL CPUTIME D+ ;\n'
    source += ': CHECKSUM 0 65536 0 DO OUT I + C@ + LOOP ;\n'
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sigma', type=Path)
    args = parser.parse_args(); binary = args.sigma.resolve()
    folder = ROOT / '.work/1165-1166'; folder.mkdir(parents=True, exist_ok=True)
    files = ['tests/scripts/measure-chip8-audio.py', 'tests/scripts/verify-chip8-audio.py',
             'include/chip8-audio.fs', 'include/chip8-pitches.fs', 'scripts/chip8-pitches.py']
    report = {'platform': platform.platform(), 'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
              'source_sha256_lf': {f: hashlib.sha256((ROOT / f).read_bytes().replace(b'\r\n', b'\n')).hexdigest() for f in files},
              'scope': 'Sequential full-build timings only; seven fresh-process rounds with rotated workload order. Initial setup/warmup/reset and A5 buffer fill/pre-state check outside timing; dense pattern generation/owned enqueue/compaction inside. Wall is primary, CPU reference only (possibly quantized). No device or CPU emulator. Full32768frame PCM and22 semantic states checked before timing and after every timed run. Clock/background apps uncontrolled; Linux in this session is WSL2.', 'workloads': {}}
    cases = {}
    for name, events in workloads().items():
        model = oracle.Model(); expected = model.render(FRAMES, events)
        assert any(expected) and 165 not in expected, name
        base = program(events, name == 'xo_8khz_pattern_pitch')
        active = 0; counter = oracle.Model(); pending = list(events)
        for frame in range(FRAMES):
            tick = (frame + 1) * 1000
            while pending and pending[0][0] <= tick:
                t, kind, value = pending.pop(0); counter.write(t, kind, value)
            counter.advance(tick); active += counter.timer > 0
        initial_count = 3 if name == 'xo_8khz_pattern_pitch' else len(events)
        count = initial_count; index = 0
        if name == 'xo_8khz_pattern_pitch':
            for _ in range(FRAMES // 6):
                for _ in range(2):
                    if count >= 1024: count -= index; index = 0
                    count += 1
                index = count
        cases[name] = {'model': model, 'expected': expected, 'base': base, 'initial_count': initial_count,
                       'final_count': count, 'active': active, 'events': events,
                       'wall': [], 'cpu': [], 'states': [], 'pre_states': [], 'sources': []}
    names = list(cases); order = []
    with tempfile.TemporaryDirectory(prefix='bench-', dir=folder) as tmp:
        for sample in range(8):
            rotation = sample % len(names)
            round_names = names[rotation:] + names[:rotation]
            order.append(round_names)
            for name in round_names:
                case = cases[name]; model = case['model']; expected = case['expected']; base = case['base']
                pcm = Path(tmp) / (name + '.pcm'); script = Path(tmp) / (name + '.fs')
                timed = sample > 0
                pre = 'OUT 65536 165 FILL OUT C@ . OUT 65535 + C@ . SNAP STDOUT FLUSH-FILE THROW\n'
                body = 'SETUP WORK SETUP\n' if timed else 'SETUP\n'
                body += pre
                body += 'NTIME W0 2! CPU-ALL U0 2! WORK CPU-ALL U1 2! NTIME W1 2! W1 2@ W0 2@ D- D. U1 2@ U0 2@ D- D.\n' if timed else 'WORK 0 . 0 .\n'
                tail = f'CHECKSUM . SNAP S" {pcm.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 65536 FD WRITE-FILE THROW FD CLOSE-FILE THROW DEPTH . BYE\n'
                source = oracle.DUMP + base + body + tail
                script.write_text(source, encoding='utf-8', newline='\n')
                result = subprocess.run([str(binary), 'tests/audio/chip8-audio-demo.fs', str(script)], cwd=ROOT,
                                        input=b'', capture_output=True, timeout=45)
                assert result.returncode == 0 and not result.stderr, (name, result.returncode, result.stdout, result.stderr)
                values = list(map(int, result.stdout.split())); assert len(values) == 54 and values[-1] == 0, values
                assert values[:2] == [165, 165]
                before = values[2:26]
                assert before[:6] + before[8:] == oracle.Model().state()
                assert before[6:8] == [case['initial_count'], 0]
                values = values[26:]
                actual = pcm.read_bytes(); assert actual == expected, (name, sample)
                snap = values[3:27]
                assert snap[:6] + snap[8:] == model.state() and snap[6:8] == [case['final_count']] * 2, (name, snap, model.state())
                assert values[2] == sum(expected)
                case['sources'].append(source)
                if timed:
                    assert values[0] > 0 and values[1] >= 0
                    case['wall'].append(values[0]); case['cpu'].append(values[1]); case['states'].append(snap[:6] + snap[8:]); case['pre_states'].append(before)
    report['round_workload_order'] = order
    for name, case in cases.items():
        wall, cpu, states, sources = (case[k] for k in ['wall', 'cpu', 'states', 'sources'])
        expected, model, events = (case[k] for k in ['expected', 'model', 'events'])
        report['workloads'][name] = {'frames': FRAMES, 'virtual_ticks': FRAMES * 1000, 'events': len(events),
                                    'oracle_pcm_sha256': hashlib.sha256(expected).hexdigest(),
                                    'all8_full_pcm_and_state_match_python': True, 'timed_semantic_states': states,
                                    'all8_poison_and_reset_pre_states_checked': True, 'timed_pre_states': case['pre_states'],
                                    'expected_final_queue_count_and_index': [case['final_count']] * 2,
                                    'wall_nanoseconds': wall, 'process_cpu_microseconds': cpu,
                                    'median_ns_per_frame': statistics.median(wall) / FRAMES,
                                    'median_realtime_ratio': FRAMES / 48000 * 1e9 / statistics.median(wall),
                                    'nonzero_samples': sum(v != 0 for v in struct.unpack('<32768h', expected)),
                                    'timer_active_frames': case['active'], 'timer_active_frame_fraction': case['active'] / FRAMES,
                                    'cpu_observed_positive_delta_gcd_us_not_calibrated_resolution': math.gcd(*cpu),
                                    'forth_verification_source': sources[0], 'forth_timed_source': sources[1],
                                    'final_semantic_state': model.state()}
    print(json.dumps(report, indent=2))


if __name__ == '__main__': main()

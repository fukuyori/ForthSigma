#!/usr/bin/env python3
"""The standard sound's 16-voice load (tque 1201).

Runs the probe that `zig build sound-load-check -Doptimize=ReleaseFast` builds. By
default it only checks the three loads, with no timing. Use --measure only after the
user has approved the start of timing (the user stops other apps first); each load is
then rendered once untimed and seven times timed, ten seconds of 48 kHz stereo each.
"""
import argparse, hashlib, json, platform, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOADS = {
    'square16': '16 plain squares',
    'full16': '16 voices with noise mix, a looping envelope, vibrato, pitch and volume '
              'modulation, ring, resonant low-pass, pan, sweep, and reverb send; the '
              'master reverb with 8 FIR coefficients, filter, and tone control',
    'table16': '8 wavetables and 8 looping samples with band-pass and reverb send',
}
SOURCES = ['src/sound_load_probe.zig', 'src/core/sound_engine.zig', 'src/core/sound_voice.zig',
           'src/core/sound_master.zig', 'tests/scripts/measure-standard-sound-load.py']


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('probe', type=Path, help='zig-out/audio-check/<arch>-<os>/sound-load(.exe)')
    p.add_argument('--measure', action='store_true', help='time the loads (needs the user\'s approval)')
    a = p.parse_args()
    probe = a.probe.resolve()
    r = subprocess.run([str(probe)], input=b'm' if a.measure else b'', capture_output=True, timeout=600)
    assert r.returncode == 0 and not r.stderr, (r.returncode, r.stdout[-2000:], r.stderr)
    report = json.loads(r.stdout)
    assert report['timing_enabled'] == a.measure, report
    assert list(report['loads']) == list(LOADS), report['loads'].keys()
    for name, load in report['loads'].items():
        assert load['sounding'] == 16 and load['heard'] == 16 and 0 < load['peak'] < 32767, (name, load)
        assert name != 'full16' or load['sides_differ'] * 2 > report['frames'], (name, load)
        assert load['nonzero_samples'] >= report['frames'], (name, load)
        if a.measure:
            assert len(load['wall_ns']) == 7 and all(t > 0 for t in load['wall_ns']), (name, load)
            assert load['median_realtime_ratio'] > 0, (name, load)
        else:
            assert load['wall_ns'] == [] and load['median_realtime_ratio'] is None, (name, load)
        load['description'] = LOADS[name]
    report['platform'] = platform.platform()
    report['machine'] = platform.machine()
    report['processor'] = platform.processor()
    report['probe_sha256'] = hashlib.sha256(probe.read_bytes()).hexdigest()
    report['scope'] = ('The engine alone, as the audio thread renders it in blocks of 480 frames; '
                       'not the host\'s audio device or the Forth program. Every load starts '
                       'from a fresh engine with all 16 voices sounding. The untimed round checks '
                       'that each voice stays active and sounds, and that the output is neither '
                       'silent nor clipped; each timed round times only the rendering and must '
                       'make the same output, sample for sample. Wall time from the host clock.')
    report['source_sha256_lf'] = {f: hashlib.sha256((ROOT / f).read_bytes().replace(b'\r\n', b'\n')).hexdigest() for f in SOURCES}
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

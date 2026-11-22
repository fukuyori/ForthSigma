#!/usr/bin/env python3
"""Where the Forth S-DSP model spends its time (tque 1188). The default only checks that the probes run; --measure needs the user's approval of the timing first.

For each of the six workloads of measure-snes-dsp-audio.py (the Forth backend), after
256 frames of warm-up, it times 4096 calls of SD-STEP (one output frame) and, each on
its own from that same state, loops of the words a frame is made of:

  consume  SD-CONSUME: one BRR nibble decoded, with the block and loop bookkeeping
  gauss    SD-GAUSS-SAMPLE: the four-point interpolation with the table
  envelope SD-ENV-STEP
  voice    SD-VOICE: all of a voice (the three above, pitch, noise, the publishing)
  mix      SD-WMIX: the two sides of a voice added to the main and echo sums
  fir      SD-FIRS: the eight-tap filter for both sides
  echo     SD-ECHO: both FIRs, the echo buffer read and written, the output

The words that take a voice number copy the voice's record in and out around the work,
which a frame does once a voice. The loops change the model's state (the voices run on), so the numbers say what a call
costs, not what one particular frame costs; nibbles a frame is the pitch registers' sum
over 4096, the number of SD-CONSUME calls a frame needs before pitch modulation.
With --measure each workload is run in three fresh processes and the medians are kept.
"""
import argparse, hashlib, importlib.util, json, platform, statistics, subprocess, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'tests/scripts' / file)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module


bench = load('sd_bench', 'measure-snes-dsp-audio.py')
PROBES = r'''
VARIABLE PF-N
: PF-EMPTY PF-N @ 0 DO 8 0 DO LOOP LOOP ;
: PF-CONSUME PF-N @ 0 DO 8 0 DO I SD-CONSUME LOOP LOOP ;
: PF-GAUSS PF-N @ 0 DO 8 0 DO I SD-GAUSS-SAMPLE DROP LOOP LOOP ;
: PF-ENVELOPE PF-N @ 0 DO 8 0 DO I SD-ENV-STEP LOOP LOOP ;
: PF-VOICE PF-N @ 0 DO 8 0 DO I 0 SD-VOICE DROP LOOP LOOP ;
: PF-MIX PF-N @ 0 DO 0 SD-MIX ! 0 SD-MIX1 ! 0 SD-EMIX ! 0 SD-EMIX1 ! 8 0 DO I SD-LOAD 1234 SD-WMIX LOOP LOOP ;
: PF-FIR PF-N @ 0 DO 8 0 DO SD-FIRS 2DROP LOOP LOOP ;
: PF-ECHO PF-N @ 8 * 0 DO SD-ECHO LOOP ;
: PF-STEP PF-N @ 0 DO SD-STEP LOOP ;
: PF-WARM 256 0 DO SD-STEP LOOP ;
: PF-TIME ( xt -- ) UTIME 2>R EXECUTE UTIME 2R> D- D. ;
'''
NAMES = ['empty', 'consume', 'gauss', 'envelope', 'voice', 'mix', 'fir', 'echo']   # each is 8 calls an iteration


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('sigma', type=Path); p.add_argument('--measure', action='store_true'); a = p.parse_args()
    binary = a.sigma.resolve(); folder = ROOT / '.work/1188'; folder.mkdir(parents=True, exist_ok=True)
    count = 4096 if a.measure else 16; report = {}
    for name, (model, _) in bench.workloads().items():
        source, _ = bench.source_for(model, False)
        nibbles = sum(model.r[v * 16 + 2] + (model.r[v * 16 + 3] & 63) * 256 for v in range(8)) / 4096
        text = source + PROBES + f'{count} PF-N !\n'
        # The whole frame first, then each part from a fresh, warmed state.
        text += "SETUP PF-WARM ' PF-STEP PF-TIME\n" + ''.join(f"SETUP PF-WARM ' PF-{n.upper()} PF-TIME\n" for n in NAMES) + 'DEPTH . BYE\n'
        runs = []
        for _ in range(3 if a.measure else 1):
            with tempfile.NamedTemporaryFile('w', encoding='utf-8', suffix='.fs', dir=folder, delete=False) as f:
                file = Path(f.name); f.write(text)
            try: r = subprocess.run([str(binary), 'examples/snes-dsp-audio-demo.fs', str(file)], cwd=ROOT, input=b'', capture_output=True, timeout=600)
            finally: file.unlink()
            assert r.returncode == 0 and not r.stderr, (name, r.returncode, r.stdout[:1000], r.stderr)
            values = list(map(int, r.stdout.split())); assert len(values) == len(NAMES) + 2 and values[-1] == 0, (name, values)
            runs.append(values[:-1])
        entry = {'nibbles_a_frame_from_pitch_registers': round(nibbles, 3)}
        if a.measure:
            median = [statistics.median(run[i] for run in runs) for i in range(len(NAMES) + 1)]
            empty = median[1] * 1000 / (count * 8)
            entry['frame_ns'] = round(median[0] * 1000 / count, 1)
            entry['realtime_ratio'] = round(1e9 / 32000 / entry['frame_ns'], 3)
            entry['call_ns'] = {n: round(median[i + 1] * 1000 / (count * 8) - (empty if n != 'empty' else 0), 1) for i, n in enumerate(NAMES)}
            entry['wall_us'] = {'step': [run[0] for run in runs], **{n: [run[i + 1] for run in runs] for i, n in enumerate(NAMES)}}
        report[name] = entry
    files = ['tests/scripts/profile-snes-dsp-audio.py', 'tests/scripts/measure-snes-dsp-audio.py', 'include/snes-dsp-audio.fs', 'include/snes-gauss.fs']
    print(json.dumps({'platform': platform.platform(), 'timing_enabled': a.measure, 'iterations': count,
                      'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(), 'scope': __doc__, 'workloads': report,
                      'source_sha256_lf': {f: hashlib.sha256((ROOT / f).read_bytes().replace(b'\r\n', b'\n')).hexdigest() for f in files}}, indent=2))


if __name__ == '__main__': main()

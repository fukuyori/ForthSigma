#!/usr/bin/env python3
"""The S-DSP model's acceptance on a machine's audio device (tque 1175, 1176, 1177).

Three steps, each its own run; the first plays nothing that can be heard.

  python tests/scripts/accept-snes-dsp-audio.py SIGMA
      Checks two notes (a low one on the left, a high one on the right) against the
      independent model of verify-snes-dsp-audio.py in memory, then sends the same
      number of frames of silence to the device. No sound.
  python tests/scripts/accept-snes-dsp-audio.py SIGMA --play
      Plays the two notes: LEFT LOW about 3 seconds, a pause, RIGHT HIGH about 3
      seconds. A person listens and reports what was heard.
  python tests/scripts/accept-snes-dsp-audio.py SIGMA --interrupt
      Plays a long high note on both sides. Press Ctrl+C once, about a second after
      READY is shown; the note must stop, and half a second later a low note plays for
      about 3 seconds (the device was given back and taken again). Run it in a
      terminal in the foreground.

SIGMA is the executable to accept, built with the audio words. --record FILE adds the
run to FILE (JSON): the system, the executable's SHA-256, the Forth source, the output,
and whether the run's own checks passed. What was heard is reported by the person and
is not in the file. The temporary Forth files go under .work/snes-acceptance.
"""
import argparse
import hashlib
import importlib.util
import json
import platform
import re
import struct
import subprocess
import tempfile
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FOLDER = ROOT / '.work/snes-acceptance'
FRAMES = 98304   # 192 blocks of 512 frames, about 3 seconds at 32 kHz
NOTES = [('LEFT LOW', 451, 16, 0), ('RIGHT HIGH', 901, 0, 16)]

# Loading is silent; a TRUE SD-STREAM is the explicit playback.
COMMON = r'''S" examples/snes-dsp-audio-native-play.fs" INCLUDED
: SD-NOTE { pitch left right -- }
  SD-DEMO-SETUP
  32 108 SD-STORE 0 44 SD-STORE 0 60 SD-STORE 0 77 SD-STORE
  pitch 255 AND 2 SD-STORE pitch 8 RSHIFT 3 SD-STORE
  left 0 SD-STORE right 1 SD-STORE 64 7 SD-STORE 1 76 SD-STORE ;
: SD-ACCEPT-DONE { frames -- }
  PS-HANDLE @ IF -528 THROW THEN
  PS-UNDERRUN-COUNT @ IF -528 THROW THEN
  PS-FRAMES @ frames <> IF -24 THROW THEN
  ." handle=" PS-HANDLE @ . ." underruns=" PS-UNDERRUN-COUNT @ . ." frames=" PS-FRAMES @ . CR STDOUT FLUSH-FILE THROW ;
'''


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_shown(binary, source, seconds, guard=None):
    """Runs Sigma on `source`, showing its output as it comes: (text, exit, timed out)."""
    lines = []
    timed_out = False

    def body():
        nonlocal timed_out
        with subprocess.Popen([str(binary), str(source)], cwd=ROOT, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace', bufsize=1) as proc:
            def read_lines():
                for line in proc.stdout:
                    lines.append(line)
                    print('    ' + line, end='', flush=True)
            reader = threading.Thread(target=read_lines, daemon=True)
            reader.start()
            try:
                proc.wait(timeout=seconds)
            except subprocess.TimeoutExpired:
                timed_out = True
                proc.kill()   # only this script's own child
                proc.wait()
            reader.join()
            return proc.returncode

    if guard:
        with guard():
            code = body()
    else:
        code = body()
    return ''.join(lines), code, timed_out


def stream_ok(text, count):
    return len(re.findall(rf'handle=\s*0\s+underruns=\s*0\s+frames=\s*{FRAMES}', text)) == count


def check_models(binary, sd):
    """The two notes in memory against the independent model: PCM, state, and ARAM."""
    results = []
    for label, pitch, left, right in NOTES:
        model = sd.demo()
        for register, value in [(108, 32), (44, 0), (60, 0), (77, 0), (2, pitch % 256), (3, pitch // 256),
                                (0, left), (1, right), (7, 64), (76, 1)]:
            model.store(value, register)
        expected = model.render(FRAMES)
        with tempfile.TemporaryDirectory(dir=FOLDER, prefix='model-') as tmp:
            tmp = Path(tmp)
            source, pcm, ram = tmp / 'fixture.fs', tmp / 'out.bin', tmp / 'ram.bin'
            source.write_text(COMMON + sd.DUMP + f'''CREATE OUT {FRAMES * 4} ALLOT {pitch} {left} {right} SD-NOTE
OUT {FRAMES} SD-RENDER SNAP
S" {pcm.as_posix()}" W/O CREATE-FILE THROW CONSTANT PF OUT {FRAMES * 4} PF WRITE-FILE THROW PF CLOSE-FILE THROW
S" {ram.as_posix()}" W/O CREATE-FILE THROW CONSTANT RF SD-ARAM 65536 RF WRITE-FILE THROW RF CLOSE-FILE THROW
DEPTH . BYE
''', encoding='utf-8', newline='\n')
            result = subprocess.run([str(binary), str(source)], cwd=ROOT, input=b'', capture_output=True, timeout=120)
            if result.returncode != 0 or result.stderr:
                raise SystemExit(f'FAIL  {label}: Sigma ended with {result.returncode}: {(result.stdout + result.stderr)[-400:]!r}')
            state_ok = list(map(int, result.stdout.split())) == model.state() + [0, 0, 0]
            pcm_ok = pcm.read_bytes() == expected
            ram_ok = ram.read_bytes() == model.ram
        samples = struct.unpack(f'<{FRAMES * 2}h', expected)
        active = 0 if left else 1
        sides_ok = any(samples[active::2]) and not any(samples[1 - active::2])
        ok = state_ok and pcm_ok and ram_ok and sides_ok
        print(f'{"PASS" if ok else "FAIL"}  {label}: PCM {pcm_ok}, state {state_ok}, ARAM {ram_ok}, only its side sounds {sides_ok}')
        results.append({'note': label, 'pitch': pitch, 'frames': FRAMES, 'pcm_match': pcm_ok, 'state_match': state_ok,
                        'aram_match': ram_ok, 'other_side_silent': sides_ok, 'peak_abs_s16': max(abs(x) for x in samples),
                        'pcm_sha256': hashlib.sha256(expected).hexdigest(), 'passed': ok})
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('sigma', type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--play', action='store_true', help='play the two notes (heard)')
    mode.add_argument('--interrupt', action='store_true', help='the Ctrl+C step (heard; needs a foreground terminal)')
    parser.add_argument('--record', type=Path, help='add this run to a JSON file')
    args = parser.parse_args()
    binary = args.sigma.resolve()
    FOLDER.mkdir(parents=True, exist_ok=True)
    report = {'step': 'interrupt' if args.interrupt else 'play' if args.play else 'silent',
              'platform': platform.platform(), 'machine': platform.machine(),
              'sigma': str(binary), 'sigma_sha256': hashlib.sha256(binary.read_bytes()).hexdigest()}
    print(f'system: {report["platform"]} ({report["machine"]})')
    print(f'sigma: {binary}  sha256 {report["sigma_sha256"][:16]}...')

    probe = subprocess.run([str(binary), '-e', 'REQUIRE-AUDIO ALSO AUDIO AUDIO? . BYE'], cwd=ROOT, input=b'', capture_output=True, timeout=30)
    report['audio_device'] = probe.stdout.decode(errors='replace').strip()
    print(f'AUDIO? (is there a device): {report["audio_device"]!r}  (-1 is yes)')

    if args.interrupt:
        listen = load('listen', ROOT / 'tests/scripts/pcm-listen.py')
        source = FOLDER / 'interrupt.fs'
        code = COMMON + f'''
: LONG 901 16 16 SD-NOTE 1875 TRUE SD-STREAM ;
: CHECK DUP -28 <> IF DROP -528 THROW THEN DROP PS-HANDLE @ IF -528 THROW THEN ;
." READY: wait about 1 second, then press Ctrl+C once; a lower note follows" CR STDOUT FLUSH-FILE THROW
' LONG CATCH DUP ." CATCH=" . ." handle=" PS-HANDLE @ . ." accepted-frames=" PS-FRAMES @ . CR STDOUT FLUSH-FILE THROW CHECK
500 MS ." REPLAY" CR STDOUT FLUSH-FILE THROW
451 16 16 SD-NOTE 192 TRUE SD-STREAM {FRAMES} SD-ACCEPT-DONE
." REPLAY-OK DEPTH=" DEPTH . CR STDOUT FLUSH-FILE THROW 250 MS BYE
'''
        source.write_text(code, encoding='utf-8', newline='\n')
        print('A long high note on both sides plays. Press Ctrl+C once after READY.')
        text, status, timed_out = run_shown(binary, source, 60, listen.parent_sigint_guard)
        checks = {'stopped_by_ctrl_c_with_the_device_given_back': bool(re.search(r'CATCH=\s*-28\s+handle=\s*0', text)),
                  'replayed_all_frames_without_underruns': stream_ok(text, 1),
                  'ended_with_an_empty_stack': bool(re.search(r'REPLAY-OK DEPTH=\s*0', text)),
                  'exit_0': status == 0, 'no_timeout': not timed_out}
    else:
        if not args.play:
            sd = load('sd', ROOT / 'tests/scripts/verify-snes-dsp-audio.py')
            report['models'] = check_models(binary, sd)
        audible = 'TRUE' if args.play else 'FALSE'
        source = FOLDER / ('play.fs' if args.play else 'silent.fs')
        code = COMMON + ''.join(f'''." {label}: about 3 seconds" CR STDOUT FLUSH-FILE THROW
{pitch} {left} {right} SD-NOTE 192 {audible} SD-STREAM {FRAMES} SD-ACCEPT-DONE
500 MS
''' for label, pitch, left, right in NOTES) + '." DEPTH=" DEPTH . CR 250 MS BYE\n'
        source.write_text(code, encoding='utf-8', newline='\n')
        print('LEFT LOW, a pause, RIGHT HIGH: ' + ('HEARD' if args.play else 'silence only (zeros to the device)'))
        text, status, timed_out = run_shown(binary, source, 60)
        checks = {'both_streams_sent_all_frames_without_underruns': stream_ok(text, 2),
                  'ended_with_an_empty_stack': bool(re.search(r'DEPTH=\s*0', text)),
                  'exit_0': status == 0, 'no_timeout': not timed_out}
        if not args.play:
            checks['models_match'] = all(m['passed'] for m in report['models'])
    passed = all(checks.values())
    for name, ok in checks.items():
        print(f'{"PASS" if ok else "FAIL"}  {name.replace("_", " ")}')
    report.update({'source': code, 'output': text, 'exit': status, 'checks': checks, 'checks_passed': passed,
                   'heard': 'to be reported by the person' if args.play or args.interrupt else 'nothing is played'})
    if args.record:
        runs = json.loads(args.record.read_text(encoding='utf-8')) if args.record.exists() else []
        runs.append(report)
        args.record.write_text(json.dumps(runs, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
        print(f'recorded in {args.record}')
    print('RESULT: ' + ('the run\'s checks passed' if passed else 'FAILED') +
          ('; now report what was heard' if passed and (args.play or args.interrupt) else ''))
    if not passed:
        raise SystemExit(1)


if __name__ == '__main__':
    main()

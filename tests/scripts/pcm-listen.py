#!/usr/bin/env python3
"""Prepare/run owned PCM acceptance cases; silent unless --audible is explicit.

Run from a foreground terminal for case8 (physical Ctrl+C and hello input).
The JSON records execution only; a human must separately report what was heard.
"""
import argparse
import contextlib
import hashlib
import json
import os
import re
import signal
import struct
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CASES = {
    1: '48000Hz mono 440Hz, 2 seconds',
    2: '22050Hz stereo: left 440Hz then right 660Hz, 1.5 seconds each',
    3: '48000Hz mono 220Hz mixed with MML melody',
    4: '48000Hz mono 220Hz mixed with signed-8-bit SFX 880Hz',
    5: 'queued PCM discard after150ms, 1 second pause, reopen and restart',
    6: 'PCM drain followed by DRAINED, silence after completion',
    7: 'SAVESYS app plays523Hz then784Hz, each1second',
    8: 'continuous550Hz; physical Ctrl+C during PCM-WAIT, then type hello',
}


def triangle(rate, hz, index, amplitude):
    phase = index * hz % rate
    return (rate - abs(2 * phase - rate)) * 2 * amplitude // rate - amplitude


def prepare(folder, case, audible):
    if any(c in folder.as_posix() for c in ['"', '\n', '\r']):
        raise ValueError('Forth S" paths cannot contain quotes or line breaks')
    if case == 7 and any(c.isspace() for c in folder.as_posix()):
        raise ValueError('SAVESYS acceptance requires a repository path without whitespace')
    rate = 22050 if case == 2 else 48000
    channels = 2 if case == 2 else 1
    frames = rate * (3 if case == 2 else 2)
    amplitude = 4096 if audible else 0
    data = bytearray()
    for i in range(frames):
        hz = 440 if case in [1, 2, 5, 6] else 220 if case in [3, 4] else (523 if i < rate else 784) if case == 7 else 550
        if channels == 2:
            left = i < rate * 3 // 2
            value = triangle(rate, 440 if left else 660, i, amplitude)
            data.extend(struct.pack('<hh', value if left else 0, 0 if left else value))
        else:
            data.extend(struct.pack('<h', triangle(rate, hz, i, amplitude)))
    pcm = folder / 'input.pcm'
    pcm.write_bytes(data)
    common = f'''REQUIRE-AUDIO ALSO AUDIO
CREATE BUF {len(data)} ALLOT
S" {pcm.as_posix()}" R/O OPEN-FILE THROW CONSTANT FD
BUF {len(data)} FD READ-FILE THROW {len(data)} <> IF -37 THROW THEN
FD CLOSE-FILE THROW
VARIABLE P VARIABLE OFFSET VARIABLE SENT VARIABLE REQUEST VARIABLE WRITES
: OPEN-PCM {rate} {channels} {32768 if rate == 48000 else 16384} PCM-OPEN THROW P ! ;
: CLEANUP P @ DUP IF PCM-CLOSE DUP 0= IF 0 P ! THEN ELSE DROP 0 THEN ;
: SEND ( frames -- )
  0 SENT ! BEGIN DUP SENT @ > WHILE
    DUP SENT @ - 512 MIN REQUEST !
    BUF OFFSET @ {channels * 2} * + REQUEST @ P @ PCM-WRITE THROW
    DUP SENT +! OFFSET +! 1 WRITES +!
    DUP SENT @ > IF 1 1000 P @ PCM-WAIT THROW 0= IF -528 THROW THEN THEN
  REPEAT DROP ;
: DRAIN 1 3000 P @ PCM-STOP THROW 0= IF -528 THROW THEN ." DRAINED" CR ;
: REPORT ." UNDERRUNS=" P @ PCM-UNDERRUNS THROW .
  ." WRITES=" WRITES @ . CR ;
: TONE 0 OFFSET ! {frames} SEND ;
'''
    # Keep the file-size guard inside a definition: IF is compile-only.
    common = common.replace(f'BUF {len(data)} FD READ-FILE THROW {len(data)} <> IF -37 THROW THEN',
                            f': LOAD-PCM BUF {len(data)} FD READ-FILE THROW {len(data)} <> IF -37 THROW THEN ; LOAD-PCM')
    extra = ''
    if case == 4:
        sfx = bytes((triangle(48000, 880, i, 24 if audible else 0) & 255) for i in range(48000))
        sample = folder / 'sfx.raw'; sample.write_bytes(sfx)
        extra = f'''CREATE FX 48000 ALLOT
S" {sample.as_posix()}" R/O OPEN-FILE THROW CONSTANT FXFD
: LOAD-FX FX 48000 FXFD READ-FILE THROW 48000 <> IF -37 THROW THEN ; LOAD-FX
FXFD CLOSE-FILE THROW FX 48000 48000 0 SAMPLE
'''
    if case == 5:
        body = 'OPEN-PCM 0 OFFSET ! 32768 SEND 150 MS 0 1000 P @ PCM-STOP THROW 0= IF -528 THROW THEN ." DISCARDED" CR CLEANUP THROW 1000 MS OPEN-PCM TONE DRAIN REPORT 250 MS'
    elif case == 8:
        # 4800 frames contain exactly55 periods at550Hz/48000Hz. Repeating
        # this block preserves phase; wait for one block of space, not empty.
        body = 'OPEN-PCM EKEY? DROP ." READY: Ctrl+C during PCM-WAIT; then type hello" CR STDOUT FLUSH-FILE THROW BEGIN 0 OFFSET ! 4800 SEND 4800 -1 P @ PCM-WAIT THROW 0= IF -528 THROW THEN AGAIN'
    else:
        mix = ('S" T120 O5 L8 CEG>C<GE" PLAY ' if audible else '') if case == 3 else ('0 SFX ' if case == 4 else '')
        body = 'OPEN-PCM ' + mix + 'TONE DRAIN REPORT ' + ('1000 MS' if case == 6 else '250 MS')
    source = common + extra + ': BODY ' + body + ' ;\n'
    source += ': RUN [\'] BODY CATCH >R [\'] CLEANUP CATCH DUP IF ELSE DROP THEN R> ?DUP IF SWAP DROP THROW THEN THROW ;\n'
    if case == 7:
        app = folder / ('pcm-saved.exe' if os.name == 'nt' else 'pcm-saved')
        source += ': MAIN RUN ; \' MAIN APP-ENTRY! SAVESYS ' + app.as_posix() + ' BYE\n'
    elif case == 8:
        source += "' BODY CATCH .\" CATCH=\" . CLEANUP .\" CLOSE=\" . CR CREATE LINE 64 ALLOT LINE 64 ACCEPT . CR LINE SWAP TYPE CR BYE\n"
        # ACCEPT's count is needed for TYPE; retain it when printing.
        source = source.replace('LINE 64 ACCEPT . CR LINE SWAP TYPE', 'LINE 64 ACCEPT DUP . CR LINE SWAP TYPE')
    else:
        source += 'RUN ." COMPLETE DEPTH=" DEPTH . CR BYE\n'
    script = folder / 'listen.fs'; script.write_text(source, encoding='utf-8', newline='\n')
    return script, source, data


@contextlib.contextmanager
def parent_sigint_guard():
    # A caught (rather than SIG_IGN) handler resets to default across POSIX
    # exec. Sigma installs its own wait handler. Only the Python parent keeps
    # this no-op, so Ctrl+C can reach Sigma without aborting the supervisor.
    previous = signal.signal(signal.SIGINT, lambda signum, frame: None)
    try:
        yield
    finally:
        signal.signal(signal.SIGINT, previous)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sigma', type=Path)
    parser.add_argument('--case', type=int, choices=CASES, required=True)
    parser.add_argument('--audible', action='store_true')
    parser.add_argument('--record', type=Path)
    args = parser.parse_args()
    binary = args.sigma.resolve()
    work = ROOT / '.work/998-followup'; work.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='listen-', dir=work) as tmp:
        folder = Path(tmp); script, source, data = prepare(folder, args.case, args.audible)
        print(CASES[args.case] + (' [AUDIBLE]' if args.audible else ' [SILENT]'), flush=True)
        if args.audible:
            probe = subprocess.run([str(binary), '-e', 'REQUIRE-AUDIO ALSO AUDIO AUDIO? . BYE'], capture_output=True, text=True, timeout=15)
            if probe.returncode or probe.stderr or probe.stdout.split() != ['-1']:
                raise RuntimeError('AUDIO? is not true; no device audition attempted: ' + repr(probe.stdout))
        start = time.monotonic()
        if args.case == 8:
            # Inherit physical stdin; tee stdout for both user and evidence.
            with parent_sigint_guard():
                with subprocess.Popen([str(binary), str(script)], cwd=ROOT,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                      text=True, encoding='utf-8', bufsize=1) as result:
                    lines = []
                    for line in result.stdout:
                        print(line, end='', flush=True); lines.append(line)
                    result.wait()
            stdout = ''.join(lines); stderr = None
            if not re.search(r'CATCH=\s*-28\s+CLOSE=\s*0[\s\S]*5\s+hello\s*$', stdout):
                raise RuntimeError('Interruption/cleanup/hello did not match: ' + repr(stdout))
        else:
            result = subprocess.run([str(binary), str(script)], cwd=ROOT, capture_output=True, text=True, encoding='utf-8', timeout=25)
            stdout, stderr = result.stdout, result.stderr
            if result.returncode or stderr:
                raise RuntimeError((result.returncode, stdout, stderr))
            if args.case == 7:
                app = folder / ('pcm-saved.exe' if os.name == 'nt' else 'pcm-saved')
                saved = subprocess.run([str(app)], cwd=ROOT, capture_output=True, text=True, encoding='utf-8', timeout=25)
                if saved.returncode or saved.stderr or 'DRAINED' not in saved.stdout:
                    raise RuntimeError((saved.returncode, saved.stdout, saved.stderr))
                stdout += saved.stdout
            elif 'COMPLETE DEPTH=0' not in stdout or 'DRAINED' not in stdout:
                raise RuntimeError(stdout)
            if args.case == 5 and 'DISCARDED' not in stdout:
                raise RuntimeError('Discard acknowledgement missing: ' + stdout)
            print(stdout, end='')
        report = {'case': args.case, 'description': CASES[args.case], 'audible_requested': args.audible,
                  'human_listening_result': 'not recorded; requires user confirmation',
                  'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
                  'pcm_sha256': hashlib.sha256(data).hexdigest(), 'pcm_bytes': len(data),
                  'source': source, 'exit': result.returncode, 'stdout': stdout, 'stderr': stderr,
                  'underruns': [int(n) for n in re.findall(r'UNDERRUNS=\s*(\d+)', stdout or '')],
                  'elapsed_seconds': time.monotonic() - start}
        if result.returncode:
            raise RuntimeError(report)
        if args.record:
            args.record.parent.mkdir(parents=True, exist_ok=True)
            args.record.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')


if __name__ == '__main__':
    main()

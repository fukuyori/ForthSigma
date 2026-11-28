#!/usr/bin/env python3
"""The Apple II model's acceptance on a machine's audio device (tque 1180, 1181, 1182).

Three steps, each its own run; the first plays nothing that can be heard.

  python tests/scripts/accept-apple2-audio.py SIGMA
      Sends the three pieces below to the device as silence (the model runs, zeros are
      sent). No sound.
  python tests/scripts/accept-apple2-audio.py SIGMA --play
      Plays three pieces with a pause between them. A person listens and reports:
        SPEAKER  a plain 440 Hz tone on both sides, about 1 second
        LEFT     a C major chord (the first AY) on the left only, about 2 seconds
        RIGHT    a low note that swells and fades about twice, with a hiss (the
                 second AY's envelope and noise), on the right only, about 2 seconds
  python tests/scripts/accept-apple2-audio.py SIGMA --interrupt
      Plays a long high note on both sides. Press Ctrl+C once, about a second after
      READY is shown; the note must stop, and half a second later a low note plays for
      about 2 seconds (the device was given back and taken again). Run it in a
      terminal in the foreground.

SIGMA is the executable to accept, built with the audio words (a ReleaseFast build: a
Debug build is too slow for the card and underruns). --record FILE adds the run to FILE
(JSON): the system, the executable's SHA-256, the Forth source, the output, and whether
the run's own checks passed. What was heard is reported by the person and is not in the
file. The temporary Forth files go under .work/apple2-acceptance.
"""
import argparse, hashlib, importlib.util, json, platform, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FOLDER = ROOT / '.work/apple2-acceptance'

# Loading is silent; a TRUE A2-STREAM is the explicit playback. Slot 4: the 6522s are at 50176 and 50304.
COMMON = r'''S" tests/audio/apple2-audio-play.fs" INCLUDED
: A2-ACCEPT-CARD ( -- ) 4 A2-CARD! A2-RESET 50176 A2-DEMO-INIT 50304 A2-DEMO-INIT ;
: A2-ACCEPT-LEFT ( -- ) A2-ACCEPT-CARD
  244 0 50176 1 A2-DEMO-PSG! 194 2 50176 1 A2-DEMO-PSG! 163 4 50176 1 A2-DEMO-PSG!
  56 7 50176 1 A2-DEMO-PSG! 11 8 50176 1 A2-DEMO-PSG! 10 9 50176 1 A2-DEMO-PSG! 10 10 50176 1 A2-DEMO-PSG! ;
: A2-ACCEPT-RIGHT ( -- ) A2-ACCEPT-CARD
  208 0 50304 1 A2-DEMO-PSG! 3 1 50304 1 A2-DEMO-PSG! 20 6 50304 1 A2-DEMO-PSG! 46 7 50304 1 A2-DEMO-PSG!
  16 8 50304 1 A2-DEMO-PSG! 6 9 50304 1 A2-DEMO-PSG! 0 11 50304 1 A2-DEMO-PSG! 8 12 50304 1 A2-DEMO-PSG!
  14 13 50304 1 A2-DEMO-PSG! ;
: A2-ACCEPT-BOTH { period -- } A2-ACCEPT-CARD
  period 0 50176 1 A2-DEMO-PSG! 62 7 50176 1 A2-DEMO-PSG! 12 8 50176 1 A2-DEMO-PSG!
  period 0 50304 1 A2-DEMO-PSG! 62 7 50304 1 A2-DEMO-PSG! 12 8 50304 1 A2-DEMO-PSG! ;
: A2-ACCEPT-DONE { frames -- }
  PS-HANDLE @ IF -528 THROW THEN
  PS-UNDERRUN-COUNT @ IF -528 THROW THEN
  PS-FRAMES @ frames <> IF -24 THROW THEN
  ." handle=" PS-HANDLE @ . ." underruns=" PS-UNDERRUN-COUNT @ . ." frames=" PS-FRAMES @ . CR STDOUT FLUSH-FILE THROW ;
'''
PIECES = [('SPEAKER: a 440 Hz tone on both sides, about 1 second', 'A2-SPEAKER-SETUP', 96),
          ('LEFT: a C major chord on the left only, about 2 seconds', 'A2-ACCEPT-LEFT', 192),
          ('RIGHT: a low note that swells and fades about twice, with a hiss, on the right only, about 2 seconds', 'A2-ACCEPT-RIGHT', 192)]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def streams_ok(text, frames):
    found = [int(n) for n in re.findall(r'handle=\s*0\s+underruns=\s*0\s+frames=\s*(\d+)', text)]
    return found == frames


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('sigma', type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--play', action='store_true', help='play the three pieces (heard)')
    mode.add_argument('--interrupt', action='store_true', help='the Ctrl+C step (heard; needs a foreground terminal)')
    parser.add_argument('--record', type=Path, help='add this run to a JSON file')
    args = parser.parse_args()
    binary = args.sigma.resolve(); FOLDER.mkdir(parents=True, exist_ok=True)
    snes = load('snes_accept', ROOT / 'tests/scripts/accept-snes-dsp-audio.py')   # for its runner
    report = {'step': 'interrupt' if args.interrupt else 'play' if args.play else 'silent',
              'platform': platform.platform(), 'machine': platform.machine(),
              'sigma': str(binary), 'sigma_sha256': hashlib.sha256(binary.read_bytes()).hexdigest()}
    print(f'system: {report["platform"]} ({report["machine"]})')
    print(f'sigma: {binary}  sha256 {report["sigma_sha256"][:16]}...')
    probe = snes.subprocess.run([str(binary), '-e', 'REQUIRE-AUDIO ALSO AUDIO AUDIO? . BYE'], cwd=ROOT, input=b'', capture_output=True, timeout=30)
    report['audio_device'] = probe.stdout.decode(errors='replace').strip()
    print(f'AUDIO? (is there a device): {report["audio_device"]!r}  (-1 is yes)')

    if args.interrupt:
        listen = load('listen', ROOT / 'tests/scripts/pcm-listen.py')
        source = FOLDER / 'interrupt.fs'
        code = COMMON + '''
: LONG 61 A2-ACCEPT-BOTH 1875 TRUE A2-STREAM ;
: CHECK DUP -28 <> IF DROP -528 THROW THEN DROP PS-HANDLE @ IF -528 THROW THEN ;
." READY: wait about 1 second, then press Ctrl+C once; a lower note follows" CR STDOUT FLUSH-FILE THROW
' LONG CATCH DUP ." CATCH=" . ." handle=" PS-HANDLE @ . ." accepted-frames=" PS-FRAMES @ . CR STDOUT FLUSH-FILE THROW CHECK
500 MS ." REPLAY" CR STDOUT FLUSH-FILE THROW
244 A2-ACCEPT-BOTH 192 TRUE A2-STREAM 98304 A2-ACCEPT-DONE
." REPLAY-OK DEPTH=" DEPTH . CR STDOUT FLUSH-FILE THROW 250 MS BYE
'''
        source.write_text(code, encoding='utf-8', newline='\n')
        print('A long high note on both sides plays. Press Ctrl+C once after READY.')
        text, status, timed_out = snes.run_shown(binary, source, 60, listen.parent_sigint_guard)
        checks = {'stopped_by_ctrl_c_with_the_device_given_back': bool(re.search(r'CATCH=\s*-28\s+handle=\s*0', text)),
                  'replayed_all_frames_without_underruns': streams_ok(text, [98304]),
                  'ended_with_an_empty_stack': bool(re.search(r'REPLAY-OK DEPTH=\s*0', text)),
                  'exit_0': status == 0, 'no_timeout': not timed_out}
    else:
        audible = 'TRUE' if args.play else 'FALSE'
        source = FOLDER / ('play.fs' if args.play else 'silent.fs')
        code = COMMON + ''.join(f'''." {label}" CR STDOUT FLUSH-FILE THROW
{setup} {blocks} {audible} A2-STREAM {blocks * 512} A2-ACCEPT-DONE
500 MS
''' for label, setup, blocks in PIECES) + '." DEPTH=" DEPTH . CR 250 MS BYE\n'
        source.write_text(code, encoding='utf-8', newline='\n')
        print('SPEAKER, LEFT, RIGHT: ' + ('HEARD' if args.play else 'silence only (zeros to the device)'))
        text, status, timed_out = snes.run_shown(binary, source, 60)
        checks = {'all_streams_sent_all_frames_without_underruns': streams_ok(text, [blocks * 512 for _, _, blocks in PIECES]),
                  'ended_with_an_empty_stack': bool(re.search(r'DEPTH=\s*0', text)),
                  'exit_0': status == 0, 'no_timeout': not timed_out}
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

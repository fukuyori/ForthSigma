#!/usr/bin/env python3
"""Listening cases for the standard sound (tque 1201).

Each case is a small Forth program that Sigma plays; this script prints what should be
heard before it plays, then waits for Enter (or goes on at once with --no-wait). The
JSON it prints records only what ran; a human reports separately what was heard.

  python tests/scripts/listen-standard-sound.py zig-out/bin/sigma.exe
  python tests/scripts/listen-standard-sound.py zig-out/bin/sigma.exe --case 6 --case 17
  python tests/scripts/listen-standard-sound.py zig-out/bin/sigma.exe --list
  python tests/scripts/listen-standard-sound.py zig-out/bin/sigma.exe --silent

The generated programs and the MOD file go under .work/1201.
"""
import argparse, hashlib, json, math, platform, struct, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FOLDER = ROOT / '.work/1201'

PRELUDE = r'''
REQUIRE-AUDIO
ALSO AUDIO
DECIMAL
: WAIT-PLAY ( -- )   BEGIN 0 PLAY? WHILE 10 MS REPEAT 300 MS ;
: WAIT-MOD ( -- )   BEGIN MOD? WHILE 10 MS REPEAT 300 MS ;
'''

# --silent: the volume stays 0, also when a case sets it (case 19).
SILENT = r'''
0 MASTER-VOLUME
GET-CURRENT AUDIO DEFINITIONS
: MASTER-VOLUME ( ratio -- )   DROP 0 4 SND-GLOBAL ;
SET-CURRENT
'''


def sample_bytes():
    """0.4 s of a decaying 440 Hz sine at 8000 Hz, signed 8-bit."""
    out = []
    for i in range(3200):
        v = math.sin(2 * math.pi * 440 * i / 8000) * math.exp(-i / 1200) * 120
        out.append(int(round(v)))
    return out


def forth_bytes(name, values):
    lines = [' '.join(f'{v} C,' for v in values[i:i + 32]) for i in range(0, len(values), 32)]
    return f'CREATE {name}\n' + '\n'.join(lines) + '\n'


def forth_cells(name, values):
    return f'CREATE {name} ' + ' '.join(f'{v} ,' for v in values) + '\n'


def mod_file():
    """A four-channel module of one pattern: a looping square sample; channel 1 C-3,
    channel 2 E-3, channel 3 G-3, channel 4 C-4, each starting 8 rows after the last,
    and E01 (MOD-FILTER on) on channel 1 at row 32."""
    data = bytearray(1084 + 1024 + 64)
    data[0:4] = b'1201'
    h = 20
    struct.pack_into('>H', data, h + 22, 32)   # 32 words = 64 bytes
    data[h + 24] = 0                            # finetune 0
    data[h + 25] = 48                           # volume
    struct.pack_into('>H', data, h + 26, 0)     # loop start
    struct.pack_into('>H', data, h + 28, 32)    # loop length in words
    data[950] = 1
    data[951] = 127
    data[1080:1084] = b'M.K.'
    periods = [428, 339, 285, 214]
    for ch, period in enumerate(periods):
        row = ch * 8
        cell = 1084 + row * 16 + ch * 4
        data[cell:cell + 4] = bytes([(1 & 0xF0) | (period >> 8), period & 0xFF, (1 << 4) | 0, 0])
    cell = 1084 + 32 * 16
    data[cell + 2] = (data[cell + 2] & 0xF0) | 0xE
    data[cell + 3] = 0x01
    for i in range(64):
        # One cycle in the 64 bytes, so that the note is the period's (428: C-3, 129 Hz).
        data[1084 + 1024 + i] = 60 if i < 32 else 256 - 60
    return bytes(data)


def cases(mod_path):
    m = mod_path.as_posix()
    return [
        (1, 'PLAY: three voices, a C major scale in eighths over C E G C quarters and a C G bass, square waves',
         'S" T120 O4 L8 CDEFGAB>C" S" T120 O3 L4 CEGC" S" T120 O2 L2 CG" PLAY3 WAIT-PLAY'),
        (2, 'MML V: one C six times, each 9 dB quieter (V15 V12 V9 V6 V3), the sixth (V0) silent',
         'S" T120 O5 L4 V15C V12C V9C V6C V3C V0C" PLAY WAIT-PLAY'),
        (3, 'MML S and M (a ramp of 16 x 256 x M / 1789773 s): S0 M200 falls away in about 0.46 s; S8 M20 falls again every 46 ms (a fast rattle); S14 M400 goes up and down, 0.92 s each way, over the 2 s note',
         'S" T60 O4 L2 S0M200C S8M20C S14M400C" PLAY WAIT-PLAY'),
        (4, 'BEEP: two short high blips (about 1316 Hz, 40 ms), half a second apart',
         'BEEP 500 MS BEEP 500 MS'),
        (5, 'PLAY-TONE: 440 Hz for half a second, then 880 Hz for half a second',
         '440 500 PLAY-TONE 600 MS 880 500 PLAY-TONE 600 MS'),
        (6, 'Waves: C E G C five times as square, pulse of 1/8 (thinner), triangle (soft), saw (bright), noise (hiss)',
         '1 INSTRUMENT SQUARE S" T120 @1 O4 L8 CEG>C" 2DUP PLAY WAIT-PLAY\n'
         'PULSE 8192 DUTY 2DUP PLAY WAIT-PLAY TRIANGLE 2DUP PLAY WAIT-PLAY\n'
         'SAW 2DUP PLAY WAIT-PLAY NOISE PLAY WAIT-PLAY'),
        (7, 'ADSR: two long notes that swell in over 0.4 s, fall to a low level, and fade out over 0.6 s after each ends',
         '2 INSTRUMENT SQUARE 400 200 16000 600 ADSR S" T60 @2 O4 L2 C R4 E R2" PLAY WAIT-PLAY'),
        (8, 'ENVELOPE with a loop: a long note that pulses at 5 Hz (tremolo)',
         'CREATE TREM 65535 , 100 , 0 , 8000 , 100 , 0 ,\n'
         '3 INSTRUMENT TRIANGLE TREM 2 0 -1 ENVELOPE S" T60 @3 O4 L1 C" PLAY WAIT-PLAY'),
        (9, 'Noise: the default 15-bit noise (hiss), then a 7-bit register (metallic, pitched), then a square with noise added',
         '4 INSTRUMENT NOISE S" T120 @4 O5 L2 C" 2DUP PLAY WAIT-PLAY\n'
         '7 6 NOISE-LFSR 2DUP PLAY WAIT-PLAY\n'
         'SQUARE 15 1 NOISE-LFSR 1 NOISE-MIX PLAY WAIT-PLAY'),
        (10, 'Pitch: a falling laser (an octave in 0.12 s), then C G C gliding over 0.2 s, then a long note with vibrato after 0.3 s',
         '5 INSTRUMENT SQUARE -100 10 PITCH-SWEEP S" T120 @5 O6 L4 C R4" PLAY WAIT-PLAY\n'
         '6 INSTRUMENT SQUARE 200 PORTAMENTO S" T120 @6 O4 L4 CGC" PLAY WAIT-PLAY\n'
         '7 INSTRUMENT SQUARE 50 6 300 VIBRATO S" T60 @7 O4 L1 C" PLAY WAIT-PLAY'),
        (11, 'FILTER: a saw C E G C plain, then through a resonant low-pass at 600 Hz (dark, ringing), then a high-pass at 2000 Hz (thin)',
         '8 INSTRUMENT SAW S" T120 @8 O3 L8 CEG>C" 2DUP PLAY WAIT-PLAY\n'
         '1 600 50000 FILTER 2DUP PLAY WAIT-PLAY 3 2000 0 FILTER PLAY WAIT-PLAY'),
        (12, 'RING and SYNC: voice 1 a triangle ringed by voice 2 (bell-like), then voice 1 a saw synced to a low voice 2 (sync sweep sound)',
         '9 INSTRUMENT TRIANGLE 2 RING S" T60 @9 O4 L1 C" S" T60 O5 L1 G" PLAY2 WAIT-PLAY\n'
         '10 INSTRUMENT SAW 2 SYNC S" T120 @10 O5 L8 CDEFGAB>C" S" T120 O3 L1 C" PLAY2 WAIT-PLAY'),
        (13, 'PITCH-MOD and VOLUME-MOD from a voice that is not heard (MOD-ONLY): a wobbling pitch, then a fast tremolo; no low tone of its own',
         '11 INSTRUMENT TRIANGLE TRUE MOD-ONLY\n'
         '12 INSTRUMENT SQUARE 2 100 PITCH-MOD S" T60 @12 O4 L1 C" S" T60 @11 O1 L1 C" PLAY2 WAIT-PLAY\n'
         '13 INSTRUMENT SQUARE 2 50000 VOLUME-MOD S" T60 @13 O4 L1 C" S" T60 @11 O1 L1 C" PLAY2 WAIT-PLAY'),
        (14, 'VOICE-PAN: C E G C on the left only, then on the right only',
         '14 INSTRUMENT 65535 0 VOICE-PAN 15 INSTRUMENT 0 65535 VOICE-PAN\n'
         'S" T120 @14 O4 L8 CEG>C" PLAY WAIT-PLAY S" T120 @15 O4 L8 CEG>C" PLAY WAIT-PLAY'),
        (15, 'WAVETABLE: C E G C with a 32-step wave of a sine and its third harmonic (organ-like)',
         forth_cells('WT', [int(round(20000 * math.sin(2 * math.pi * i / 32) + 7000 * math.sin(6 * math.pi * i / 32))) for i in range(32)])
         + '16 INSTRUMENT WT 32 WAVETABLE S" T120 @16 O4 L8 CEG>C" PLAY WAIT-PLAY'),
        (16, 'SAMPLE: SFX plays a 440 Hz ping that fades out, twice; then the ping as an instrument on C E G (at O4 C its own pitch)',
         forth_bytes('PING', sample_bytes())
         + 'PING 3200 8000 0 SAMPLE 0 SFX 600 MS 0 SFX 600 MS\n'
         '17 INSTRUMENT 0 SAMPLE-INSTRUMENT S" T120 @17 O4 L4 CEG" PLAY WAIT-PLAY'),
        (17, 'MOD: four square notes come in one by one (C left, E right, G right, C left), and from the middle (E01) all go darker (MOD-FILTER low-pass 800 Hz)',
         f'1 800 MOD-FILTER S" {m}" LOAD-MOD FALSE PLAY-MOD WAIT-MOD'),
        (18, 'REVERB: short notes with echoes 0.2 s apart dying away; then with REVERB-FIR 64 64 the later echoes are duller',
         '18 INSTRUMENT SQUARE 40000 REVERB-SEND 200 32768 40000 REVERB\n'
         'S" T120 @18 O5 L16 CR8.ER8.GR8." 2DUP PLAY WAIT-PLAY 1500 MS\n'
         'CREATE FIR 64 , 64 , FIR 2 REVERB-FIR PLAY WAIT-PLAY 1500 MS\n'
         'FIR 0 REVERB-FIR 0 0 0 REVERB'),
        (19, 'Master: C E G C plain; with MASTER-FILTER low-pass 500 Hz (muffled); TONE-CONTROL 12 -12 (boomy); MASTER-VOLUME 1/4 (quieter)',
         '19 INSTRUMENT SAW S" T120 @19 O4 L8 CEG>C" 2DUP PLAY WAIT-PLAY\n'
         '1 500 MASTER-FILTER 2DUP PLAY WAIT-PLAY 0 0 MASTER-FILTER\n'
         '12 -12 TONE-CONTROL 2DUP PLAY WAIT-PLAY 0 0 TONE-CONTROL\n'
         '16384 MASTER-VOLUME PLAY WAIT-PLAY 65535 MASTER-VOLUME'),
        (20, 'All 16 voices: the MOD of case 17 (its four notes all in after 3 s), then 8 PLAY voices at V8 (a chord moving up), and in the middle the ping of case 16 four times 50 ms apart as SFX; no dropouts or crackles. It prints how many voices were on with all of them sounding (16)',
         forth_bytes('PING', sample_bytes())
         + 'PING 3200 8000 0 SAMPLE\n'
         + ': VOICES-ON ( -- n )   0  17 1 DO I VOICE-ON? IF 1+ THEN LOOP ;\n'
         + f'S" {m}" LOAD-MOD FALSE PLAY-MOD 3000 MS\n'
         + ' '.join(f'S" T60 V8 O{3 + i // 4} L2 {"CEGB"[i % 4]}{"DFAC"[i % 4]}{"EGBD"[i % 4]}"' for i in range(8))
         + ' 8 PLAYS 1000 MS 0 SFX 50 MS 0 SFX 50 MS 0 SFX 50 MS 0 SFX 50 MS\n'
         + '.( voices on: ) VOICES-ON . CR WAIT-PLAY WAIT-MOD'),
        (21, 'Loudness: 8 PLAY voices of square at V15 on one chord; at this level the sum goes past full scale, so listen for distortion',
         ' '.join(f'S" T60 V15 O{3 + i // 4} L1 {"CEGC"[i % 4]}"' for i in range(8)) + ' 8 PLAYS WAIT-PLAY'),
    ]


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('sigma', type=Path)
    p.add_argument('--case', type=int, action='append', help='play only these cases')
    p.add_argument('--list', action='store_true', help='print the cases without playing')
    p.add_argument('--no-wait', action='store_true', help='do not wait for Enter between cases')
    p.add_argument('--silent', action='store_true', help='run with 0 MASTER-VOLUME, to check that the cases run')
    a = p.parse_args()
    FOLDER.mkdir(parents=True, exist_ok=True)
    mod_path = FOLDER / 'listen.mod'
    mod_path.write_bytes(mod_file())
    all_cases = cases(mod_path)
    chosen = [c for c in all_cases if not a.case or c[0] in a.case]
    if a.list:
        for n, text, _ in all_cases:
            print(f'{n:2}  {text}')
        return
    binary = a.sigma.resolve()
    record = {'platform': platform.platform(), 'silent': a.silent,'sigma_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(), 'cases': []}
    for n, text, body in chosen:
        source = FOLDER / f'case{n:02}.fs'
        source.write_text(PRELUDE + (SILENT if a.silent else '') + body + '\nBYE\n', encoding='utf-8', newline='\n')
        print(f'\n[{n}] {text}', flush=True)
        if not a.no_wait and not a.silent:
            input('    Enter to play: ')
        r = subprocess.run([str(binary), str(source)], cwd=ROOT, input=b'', capture_output=True, timeout=120)
        ok = r.returncode == 0 and not r.stderr
        print('    ran' if ok else f'    FAILED {r.returncode}: {(r.stdout + r.stderr)[-500:].decode(errors="replace")}', flush=True)
        record['cases'].append({'case': n, 'expected': text, 'returncode': r.returncode,
                                'output': r.stdout.decode(errors='replace')[-500:], 'stderr': r.stderr.decode(errors='replace')[-500:]})
    print(json.dumps(record, indent=2))
    failed = [c['case'] for c in record['cases'] if c['returncode'] != 0 or c['stderr']]
    if failed:
        raise SystemExit(f'failed cases: {failed}')


if __name__ == '__main__':
    main()

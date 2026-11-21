#!/usr/bin/env python3
"""Listening cases for the standard sound (tque 1201; the chip libraries 1207; 33 on 1240 to 1242).

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
        (3, 'MML S and M (a ramp of 256 x M / 1789773 s): S0 M3000 falls away in about 0.43 s; S8 M300 falls again every 43 ms (a fast rattle); S14 M6000 goes up and down, 0.86 s each way, over the 2 s note',
         'S" T60 O4 L2 S0M3000C S8M300C S14M6000C" PLAY WAIT-PLAY'),
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
        (14, 'INSTRUMENT-PAN: C E G C on the left only, then on the right only',
         '14 INSTRUMENT 65535 0 INSTRUMENT-PAN 15 INSTRUMENT 0 65535 INSTRUMENT-PAN\n'
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
         '1 500 1 MASTER-FILTER 2DUP PLAY WAIT-PLAY 0 0 1 MASTER-FILTER\n'
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
        # ---- The chip libraries of include/ (tque 1207) ----
        (22, 'MSX-SOUND: a melody, a C E G C line, and a bass on the PSG\'s three voices; the fourth voice (a high held C) is not heard',
         'REQUIRE chips.fs MSX-SOUND\n'
         'S" T150 V13 O5 L8 CEGCEGCE" S" T150 V12 O4 L4 CEGC" S" T150 V12 O3 L2 CG" S" T150 V12 O6 L1 C" 4 PLAYS WAIT-PLAY'),
        (23, 'MSX-SOUND with S and M: as case 3 (S0 M3000 a 0.43 s fall, S8 M300 a rattle, S14 M6000 up and down), with the PSG\'s 16 steps',
         'REQUIRE chips.fs MSX-SOUND S" T60 O4 L2 S0M3000C S8M300C S14M6000C" PLAY WAIT-PLAY'),
        (24, 'Volume steps: a triangle fading over 3 s, first on MSX-SOUND (16 steps, the steps can be heard), then on ST-SOUND (32 steps, smoother)',
         'REQUIRE chips.fs MSX-SOUND 1 INSTRUMENT TRIANGLE 0 3000 0 0 ADSR\n'
         'S" T60 @1 O5 L1 C" 2DUP PLAY WAIT-PLAY ST-SOUND PLAY WAIT-PLAY'),
        (25, 'NES-SOUND: a thin 1/8 pulse lead, a square harmony, the 32-step triangle bass, and noise drums, mixed with the NES\'s formulas',
         'REQUIRE chips.fs NES-SOUND 1 INSTRUMENT NES-TRIANGLE 2 INSTRUMENT NES-NOISE 3 INSTRUMENT NES-PULSE 8192 DUTY\n'
         'S" T150 @3 O5 L8 EGAG EDC<A" S" T150 O4 L8 CEFE C<GEF" S" T150 @1 O3 L4 CG<AF" S" T150 @2 O6 L8 CRCC CRCC" 4 PLAYS WAIT-PLAY'),
        (26, 'C64-SOUND: a bright saw lead with ADSR, a softer saw line under it, and a pulse bass, three voices on the SID\'s steps',
         'REQUIRE chips.fs C64-SOUND 1 INSTRUMENT SAW 5 200 30000 300 ADSR 2 INSTRUMENT PULSE 12000 DUTY 5 100 40000 200 ADSR\n'
         'S" T140 @1 O5 L8 CDEG EDC<G" S" T140 @1 V10 O4 L2 EG" S" T140 @2 O3 L4 CC<GG" PLAY3 WAIT-PLAY'),
        (27, 'SCC-SOUND: a five-voice chord on a 32-sample wave (a sine and its second harmonic), played as steps',
         forth_bytes('SW', [int(round(90 * math.sin(2 * math.pi * i / 32) + 35 * math.sin(4 * math.pi * i / 32))) for i in range(32)])
         + 'REQUIRE chips.fs SCC-SOUND SW 1 SCC-WAVE\n'
         + ' '.join(f'S" T60 @1 V12 O{o} L1 {n}"' for o, n in [(3, 'C'), (4, 'C'), (4, 'E'), (4, 'G'), (5, 'C')]) + ' 5 PLAYS WAIT-PLAY'),
        (28, 'AMIGA-SOUND: the ping of case 16 as an instrument on C E G C through the A500 low-pass, then the same with AMIGA-FILTER on (the LED filter after it: duller)',
         forth_bytes('PING', sample_bytes())
         + 'REQUIRE chips.fs AMIGA-SOUND PING 3200 8000 0 SAMPLE 1 INSTRUMENT 0 SAMPLE-INSTRUMENT\n'
         'S" T120 @1 O4 L4 CEG>C" 2DUP PLAY WAIT-PLAY TRUE AMIGA-FILTER PLAY WAIT-PLAY'),
        (29, 'SOUND, a tone: voice 1 at about 440 Hz (period 254) at full volume for 1 s, then at level 10 (quieter) for 0.5 s, then silent',
         'REQUIRE chips.fs 7 62 SOUND 0 254 SOUND 1 0 SOUND 8 15 SOUND 1000 MS 8 10 SOUND 500 MS 8 0 SOUND 300 MS'),
        (30, 'SOUND, noise: a high hiss (noise period 10) for 0.7 s, then a low rumble (period 31) for 0.7 s',
         'REQUIRE chips.fs 6 10 SOUND 7 55 SOUND 8 15 SOUND 700 MS 6 31 SOUND 700 MS 8 0 SOUND 300 MS'),
        (31, 'SOUND, the envelope: a 440 Hz note falling once in 0.37 s (shape 0, period 2560), then going up and down every 0.37 s (shape 14) for 2 s',
         'REQUIRE chips.fs 7 62 SOUND 0 254 SOUND 1 0 SOUND 11 0 SOUND 12 10 SOUND 8 16 SOUND 13 0 SOUND 1000 MS\n'
         '13 14 SOUND 2000 MS 8 0 SOUND 300 MS'),
        (32, 'STYLE: voice 1 a pulse with the NES\'s steps and voice 2 a square with the SCC\'s, then the same after STANDARD-SOUND (smoother pitch slides)',
         'REQUIRE chips.fs 1 INSTRUMENT PULSE 16384 DUTY 200 PORTAMENTO NES STYLE 2 INSTRUMENT 200 PORTAMENTO SCC STYLE\n'
         'S" T120 @1 O4 L4 C>C<C>C" S" T120 @2 O5 L4 G>G<G>G" 2OVER 2OVER PLAY2 WAIT-PLAY STANDARD-SOUND PLAY2 WAIT-PLAY'),
        # ---- What tque 1239 added (1240, 1241, 1242) ----
        (33, 'VOICE-HOLD, a moving pulse width: one low note for 3 s whose tone goes thin and full again once a second, smoothly; no clicks and no new attacks',
         ': PWM ( -- )   300 0 DO  I 100 MOD 50 - ABS 1000 * 8000 + DUTY  1 220000 40000 1 VOICE-HOLD  10 MS  LOOP ;\n'
         '1 INSTRUMENT PULSE PWM 0 0 0 1 VOICE-HOLD 300 MS'),
        (34, 'VOICE-HOLD, a moving filter: one low saw for 3 s through a resonant low-pass that opens and closes once a second (wah-wah), smoothly; no clicks',
         ': WAH ( -- )   300 0 DO  1  50 I 100 MOD 50 - ABS - 80 * 200 +  50000 FILTER  2 110000 40000 1 VOICE-HOLD  10 MS  LOOP ;\n'
         '2 INSTRUMENT SAW WAH 0 0 0 1 VOICE-HOLD 300 MS'),
        (35, 'VOICE-PAN: C E G C on the left only, then on the right only, then in the middle (the same instrument each time)',
         'S" T120 O4 L8 CEG>C" 65535 0 1 VOICE-PAN 2DUP PLAY WAIT-PLAY\n'
         '0 65535 1 VOICE-PAN 2DUP PLAY WAIT-PLAY 65535 65535 1 VOICE-PAN PLAY WAIT-PLAY'),
        (36, 'NES-SHORT-NOISE: four hits of the ordinary noise (hiss), then four of the short mode (metallic, with a pitch)',
         'REQUIRE chips.fs NES-SOUND 2 INSTRUMENT NES-NOISE 3 INSTRUMENT NES-SHORT-NOISE\n'
         'S" T120 R1" 2DUP 2DUP S" T120 @2 O6 L4 CCCC" 4 PLAYS WAIT-PLAY\n'
         'S" T120 R1" 2DUP 2DUP S" T120 @3 O6 L4 CCCC" 4 PLAYS WAIT-PLAY'),
        (37, 'NES-DMC: the ping of case 16 on voice 5 as the DMC on C E G C alone, then the same under a pulse melody',
         forth_bytes('PING', sample_bytes())
         + 'REQUIRE chips.fs NES-SOUND PING 3200 8000 0 SAMPLE 4 INSTRUMENT 0 SAMPLE-INSTRUMENT NES-DMC\n'
         'S" T120 R1" 2DUP 2DUP 2DUP S" T120 @4 O4 L4 CEG>C" 5 PLAYS WAIT-PLAY\n'
         'S" T120 O5 L8 EGAG EDC<A" S" T120 R1" 2DUP 2DUP S" T120 @4 O4 L4 CEG>C" 5 PLAYS WAIT-PLAY'),
        (38, 'C64-FILTER: a saw C E G C plain; through the low-pass with resonance (dark, ringing); through the high-pass (thin); through the low-pass and band-pass together (dark, a little fuller than the low-pass)',
         'REQUIRE chips.fs C64-SOUND 1 INSTRUMENT SAW S" T120 @1 O3 L8 CEG>C" 2DUP PLAY WAIT-PLAY\n'
         '1 100 12 C64-FILTER 2DUP PLAY WAIT-PLAY 4 400 0 C64-FILTER 2DUP PLAY WAIT-PLAY\n'
         '3 100 12 C64-FILTER PLAY WAIT-PLAY'),
        (39, 'AMIGA-SOUND, the voices\' sides: four notes one after the other, C on the left, E on the right, G on the right, the high C on the left; then all four together',
         'REQUIRE chips.fs AMIGA-SOUND\n'
         'S" T120 O4 L4 CRRR" S" T120 O4 L4 RERR" S" T120 O4 L4 RRGR" S" T120 O5 L4 RRRC" 4 PLAYS WAIT-PLAY\n'
         'S" T120 O4 L2 C" S" T120 O4 L2 E" S" T120 O4 L2 G" S" T120 O5 L2 C" 4 PLAYS WAIT-PLAY'),
        (40, 'STE-LEFT and STE-RIGHT: the ping of case 16 twice on the left, then twice on the right (a little sharp: its rate is one of 50066 / 1 to 8)',
         forth_bytes('PING', sample_bytes())
         + 'REQUIRE chips.fs STE-SOUND PING 3200 8000 0 SAMPLE\n'
         '1 INSTRUMENT 0 SAMPLE-INSTRUMENT STE-LEFT 2 INSTRUMENT 0 SAMPLE-INSTRUMENT STE-RIGHT\n'
         'S" T120 R1" 2DUP 2DUP S" T120 @1 O4 L4 CCRR" S" T120 @2 O4 L4 RRCC" 5 PLAYS WAIT-PLAY'),
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

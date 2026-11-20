#!/usr/bin/env python3
"""Independent CHIP-8/XO math, state and full-PCM checks; no native audio opened."""
import argparse, hashlib, json, math, platform, struct, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CLOCK, PERIOD, TURN = 48000000, 800000, 1 << 32
VARS = ['CYCLE', 'DIV', 'TIMER', 'PITCH', 'MODE', 'PHASE', 'EVENT-COUNT', 'EVENT-INDEX']
DUMP = ': SNAP ' + ' '.join('C8-' + v + ' @ .' for v in VARS) + ' 16 0 DO C8-PATTERN I + C@ . LOOP ;\n'
PATTERN = bytes((i * 37 + 11) & 255 for i in range(16))


class Model:
    def __init__(self):
        self.t = self.div = self.timer = self.mode = self.phase = 0
        self.pitch = 64; self.pattern = bytes(16)

    def advance(self, end):
        assert end >= self.t
        # Independent arithmetic: locate absolute timer boundaries, including
        # an inactive tail in one operation. Phase uses the declared Q32 rate.
        step = math.floor((4000 * 2 ** ((self.pitch - 64) / 48) if self.mode else 440) * TURN / CLOCK)
        while self.t < end and self.timer:
            boundary = (self.t // PERIOD + 1) * PERIOD
            stop = min(end, boundary)
            self.phase = (self.phase + (stop - self.t) * step) % (128 * TURN if self.mode else TURN)
            self.t = stop
            if stop == boundary:
                self.timer -= 1
                if not self.timer: self.phase = 0
        self.t = end; self.div = end % PERIOD

    def write(self, tick, kind, value):
        self.advance(tick)
        if kind == 0:
            self.timer = value
            if not value: self.phase = 0
        elif kind == 1: self.pitch = value
        elif kind == 2:
            if self.mode != value: self.phase = 0
            self.mode = value
        else: self.pattern = bytes(value)

    def sample(self):
        if not self.timer: return 0
        if not self.mode: return 4096 if self.phase < TURN // 2 else -4096
        bit = self.phase // TURN
        return ((self.pattern[bit // 8] >> (7 - bit % 8)) & 1) * 4096

    def render(self, frames, events):
        result = bytearray(); pending = list(events)
        for _ in range(frames):
            tick = self.t + 1000
            while pending and pending[0][0] <= tick:
                t, k, v = pending.pop(0); self.write(t, k, v)
            self.advance(tick); result.extend(struct.pack('<h', self.sample()))
        return bytes(result)

    def state(self):
        return [self.t, self.div, self.timer, self.pitch, self.mode, self.phase] + list(self.pattern)


def events_source(events):
    parts = []
    for t, k, value in events:
        if k == 3:
            parts.append('CREATE P' + str(len(parts)) + ' ' + ' '.join(str(v) + ' C,' for v in value))
            parts.append('P' + str(len(parts) - 1) + f' {t} C8-PATTERN-EVENT!')
        else: parts.append(f'{value} {t} C8-' + ['TIMER', 'PITCH', 'MODE'][k] + '-EVENT!')
    return '\n'.join(parts) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('sigma', type=Path)
    args = parser.parse_args(); binary = args.sigma.resolve()
    work = ROOT / '.work/1164'; work.mkdir(parents=True, exist_ok=True)
    tests = []
    def run(code):
        with tempfile.NamedTemporaryFile('w', encoding='utf-8', suffix='.fs', dir=work, delete=False) as f:
            path = Path(f.name); f.write(DUMP + code + '\nDEPTH . BYE\n')
        try: q = subprocess.run([str(binary), 'examples/chip8-audio.fs', str(path)], cwd=ROOT, input=b'', capture_output=True, timeout=30)
        finally: path.unlink()
        assert q.returncode == 0 and not q.stderr, (q.returncode, q.stdout[:2000], q.stderr)
        values = list(map(int, q.stdout.split()))
        assert values.pop() == 0, 'Case leaked Forth stack values'
        return values
    def check_state(actual, model):
        assert actual[:6] + actual[8:] == model.state(), (actual, model.state())
    levels = run(': C8-TEST-TABLE 256 0 DO I CELLS C8-PITCHES + @ . LOOP ; C8-TEST-TABLE')
    expected = [math.floor(4000 * 2 ** ((p - 64) / 48) * TURN / CLOCK) for p in range(256)]
    assert levels == expected
    errors = [4000 * 2 ** ((p - 64) / 48) - levels[p] * CLOCK / TURN for p in range(256)]
    assert all(0 <= error < CLOCK / TURN for error in errors)
    tests.append({'case': 'all256-pitches-independent-double-formula', 'steps': levels,
                  'max_bit_rate_error_hz': max(4000 * 2 ** ((p - 64) / 48) - levels[p] * CLOCK / TURN for p in range(256)),
                  'classic_step': 440 * TURN // CLOCK, 'classic_actual_hz': (440 * TURN // CLOCK) * CLOCK / TURN})
    # Exact hand timer boundaries; timer writes do not restart global60Hz phase.
    assert run('SNAP C8-SAMPLE .') == [0, 0, 0, 64, 0, 0, 0, 0] + [0] * 17
    assert run('1 0 C8-TIMER! 799999 C8-TO C8-TIMER @ . 800000 C8-TO C8-TIMER @ . C8-PHASE @ .') == [1, 0, 0]
    assert run('5 799999 C8-TIMER! 800000 C8-TIMER@ .') == [4]
    assert run('1 0 C8-TIMER! 2 800000 C8-TIMER-EVENT! 800000 C8-TO C8-TIMER @ . C8-PHASE @ . 1600000 C8-TIMER@ .') == [2, 0, 1]
    assert run('800000 C8-TO 1 800000 C8-TIMER! 2 800000 C8-TIMER-EVENT! 0 C8-RUN 0 C8-RUN 800000 C8-TIMER@ . 1600000 C8-TIMER@ .') == [2, 1]
    assert run('1 0 C8-TIMER-EVENT! C8-SAMPLE . 0 C8-RUN C8-SAMPLE . 1 0 C8-MODE! C8-SAMPLE .') == [0, 4096, 0]
    tests.append({'case': 'reset-and-hand-timer-boundaries-expiry-before-tied-write'})
    # Every timer byte and both render modes, without256 separate startups.
    code = ': TIMERS 256 0 DO C8-RESET I 0 C8-TIMER! 800000 C8-RUN C8-TIMER @ . LOOP ; TIMERS'
    assert run(code) == [max(i - 1, 0) for i in range(256)]
    tests.append({'case': 'all256-timer-values-saturate-at-zero'})
    # Pattern is copied before queued application; bit order is hand checked.
    pattern_source = 'CREATE P ' + ' '.join(str(v) + ' C,' for v in PATTERN) + '\n'
    code = pattern_source + '1 0 C8-MODE! P 0 C8-PATTERN! 255 0 C8-TIMER! P 16 ERASE\n'
    code += ': BITS 128 0 DO I 32 LSHIFT C8-PHASE ! C8-SAMPLE . LOOP ; BITS'
    bits = [(v >> b & 1) * 4096 for v in PATTERN for b in range(7, -1, -1)]
    assert run(code) == bits
    assert run(pattern_source + 'P 1000 C8-PATTERN-EVENT! P 16 ERASE 1000 C8-TO SNAP')[8:] == list(PATTERN)
    # A pending overwrite must not change the source captured by immediate copy.
    code = pattern_source + 'P 0 C8-PATTERN! P 16 255 FILL P 500 C8-PATTERN-EVENT! C8-PATTERN 1000 C8-PATTERN! SNAP'
    assert run(code)[8:] == list(PATTERN)
    tests.append({'case': 'all128-msb-first-bits-and-immediate-queued-copy-ownership'})
    assert run('2 999 C8-TIMER-EVENT! 5 999 C8-TIMER! C8-TIMER @ . C8-EVENT-INDEX @ .') == [5, 1]
    code = 'CREATE P 16 ALLOT P 16 255 FILL P 999 C8-PATTERN-EVENT! P 16 ERASE P 999 C8-PATTERN! SNAP'
    assert run(code)[8:] == [0] * 16
    tests.append({'case': 'queued-then-immediate-at-same-tick-timer-and-pattern'})
    events = [(0, 2, 1), (0, 3, PATTERN), (0, 0, 4), (1133, 1, 247), (1444, 0, 3),
              (1987, 3, bytes(reversed(PATTERN))), (800000, 0, 2), (1600000, 0, 0),
              (1600000, 1, 255), (1600000, 0, 5), (1800001, 2, 0), (2000000, 2, 1)]
    model = Model(); source = events_source(events)
    # Sparse sub-sample events and same-tick order; all bytes and state checked.
    with tempfile.TemporaryDirectory(prefix='pcm-', dir=work) as tmp:
        out = Path(tmp) / 'pcm.bin'
        def pcm_code(parts):
            return ('CREATE OUT 16384 ALLOT ' + parts + f' S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 16384 FD WRITE-FILE THROW FD CLOSE-FILE THROW SNAP DEPTH .')
        wanted = model.render(8192, events)
        for parts in ['OUT 8192 C8-RENDER', 'OUT 123 C8-RENDER OUT 246 + 8069 C8-RENDER']:
            state = run(source + pcm_code(parts)); assert out.read_bytes() == wanted; assert state[-1] == 0
            check_state(state[:-1], model); assert state[6] == state[7]
    tests.append({'case': 'full8192frame-changing-state-pcm-and-split-render', 'pcm_sha256': hashlib.sha256(wanted).hexdigest()})
    # All pitches at nonzero timer and asymmetric pattern; independently sample.
    with tempfile.TemporaryDirectory(prefix='pitch-', dir=work) as tmp:
        out = Path(tmp) / 'pcm.bin'; expected_pcm = bytearray()
        code = pattern_source + 'CREATE OUT 131072 ALLOT\n: PITCHES 256 0 DO C8-RESET 1 0 C8-MODE! P 0 C8-PATTERN! I 0 C8-PITCH! 255 0 C8-TIMER! OUT I 512 * + 256 C8-RENDER LOOP ; PITCHES\n'
        run(code + f'S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 131072 FD WRITE-FILE THROW FD CLOSE-FILE THROW')
        for pitch in range(256):
            m = Model(); m.mode = 1; m.pitch = pitch; m.timer = 255; m.pattern = PATTERN
            expected_pcm.extend(m.render(256, []))
        assert out.read_bytes() == expected_pcm
    tests.append({'case': 'all256-pitches-full65536frame-pcm', 'pcm_sha256': hashlib.sha256(expected_pcm).hexdigest()})
    with tempfile.TemporaryDirectory(prefix='dense-', dir=work) as tmp:
        out = Path(tmp) / 'pcm.bin'; ev = []
        for i in range(1365): ev.extend([(i * 6000 + 1, 3, bytes([i & 255]) * 16), (i * 6000 + 1, 1, i * 37 & 255)])
        m = Model(); m.mode = 1; m.timer = 255; expected_dense = m.render(8190, ev)
        code = '1 0 C8-MODE! 255 0 C8-TIMER! CREATE P 16 ALLOT CREATE OUT 16380 ALLOT\n'
        code += ': DENSE 1365 0 DO P 16 I 255 AND FILL P I 6000 * 1+ C8-PATTERN-EVENT! I 37 * 255 AND I 6000 * 1+ C8-PITCH-EVENT! OUT I 12 * + 6 C8-RENDER LOOP ; DENSE\n'
        result = run(code + f'S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 16380 FD WRITE-FILE THROW FD CLOSE-FILE THROW SNAP')
        assert out.read_bytes() == expected_dense; check_state(result, m); assert result[6] == result[7]
    tests.append({'case': '8khz-owned-pattern-and-pitch-stream2730events', 'frames': 8190, 'pcm_sha256': hashlib.sha256(expected_dense).hexdigest()})
    with tempfile.TemporaryDirectory(prefix='compact-', dir=work) as tmp:
        out = Path(tmp) / 'pcm.bin'
        ev = [(i * 1000, 3, bytes(((i - 1) + j * 13) & 255 for j in range(16))) for i in range(1, 1026)]
        m = Model(); m.mode = 1; m.timer = 255; wanted = m.render(1025, ev)
        code = '''1 0 C8-MODE! 255 0 C8-TIMER! CREATE P 16 ALLOT CREATE OUT 2050 ALLOT
: MAKE-PAT { n -- } 16 0 DO n I 13 * + 255 AND P I + C! LOOP ;
: FILL-PAT 1024 0 DO I MAKE-PAT P I 1+ 1000 * C8-PATTERN-EVENT! LOOP ;
FILL-PAT OUT 512 C8-RENDER 1024 MAKE-PAT P 1025000 C8-PATTERN-EVENT!
OUT 1024 + 513 C8-RENDER
'''
        result = run(code + f'S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 2050 FD WRITE-FILE THROW FD CLOSE-FILE THROW SNAP')
        assert out.read_bytes() == wanted; check_state(result, m); assert result[6:8] == [513, 513]
    tests.append({'case': 'compaction-preserves512-pending-owned-pattern-payloads-and-full-pcm', 'pcm_sha256': hashlib.sha256(wanted).hexdigest()})
    # Expiry is the only implicit offset reset; classic pitch/pattern do not tune440Hz.
    assert run('10 0 C8-TIMER! 123 C8-RUN C8-PHASE @ . 20 123 C8-TIMER! C8-PHASE @ . 200 123 C8-PITCH! C8-PHASE @ . 0 123 C8-TIMER! C8-PHASE @ .') == [123 * (440 * TURN // CLOCK)] * 3 + [0]
    assert run('10 0 C8-TIMER! 123 C8-RUN 0 123 C8-MODE! C8-PHASE @ . 1 123 C8-MODE! C8-PHASE @ .') == [123 * (440 * TURN // CLOCK), 0]
    assert run('1000 C8-TO CREATE OUT 4 ALLOT OUT 1 C8-RENDER C8-CYCLE @ . 3500 C8-TO OUT 1 C8-RENDER C8-CYCLE @ .') == [2000, 4500]
    tests.append({'case': 'positive-timer-pitch-preserves-phase-zero-resets'})
    m = Model(); m.mode = 1; m.pitch = 255; m.timer = 255; end = 200123456
    m.advance(end); assert m.phase == end * levels[255] % (128 * TURN)
    result = run(f'1 0 C8-MODE! 255 0 C8-PITCH! 255 0 C8-TIMER! 12345 C8-TO {end} C8-TO SNAP')
    check_state(result, m)
    tests.append({'case': 'large-active-250-boundary-q32-advance-matches-closed-form'})
    bad = [('-1 0 C8-TIMER!', -24), ('256 0 C8-TIMER!', -24), ('256 0 C8-PITCH!', -24),
           ('2 0 C8-MODE!', -24), ('-1 C8-TO', -24), ('-1 C8-RUN', -24),
           ('0 -1 C8-RENDER', -24), ('-1 1000 C8-PATTERN!', -9), ('-1 1000 C8-PATTERN-EVENT!', -9),
           ('1 50 C8-TIMER-EVENT!', -24)]
    for body, error in bad:
        # Pending event at100 makes event50 unsorted and other errors atomic.
        code = '2 100 C8-TIMER-EVENT! CREATE COPY 40960 ALLOT C8-EVENTS COPY 40960 MOVE SNAP\n: BAD ' + body + ' ; \' BAD CATCH . SNAP C8-EVENTS 40960 COPY 40960 COMPARE .'
        result = run(code); assert result[24] == error and result[:24] == result[25:49] and result[49] == 0, (body, result)
    tests.append({'case': 'atomic-errors-preserve-state-and-all40960queue-bytes', 'cases': len(bad)})
    code = ': FILLQ 1024 0 DO I 255 AND I C8-TIMER-EVENT! LOOP ; FILLQ\n'
    assert run(code + ': BAD 2 1024 C8-TIMER-EVENT! ; \' BAD CATCH . 512 C8-TO 7 1024 C8-TIMER-EVENT! C8-EVENT-COUNT @ . C8-EVENT-INDEX @ . 1024 C8-TO C8-TIMER @ .') == [-528, 512, 0, 7]
    atomic = '512 C8-TO CREATE COPY 40960 ALLOT C8-EVENTS COPY 40960 MOVE SNAP : BAD -1 1024 C8-PATTERN-EVENT! ; \' BAD CATCH . SNAP C8-EVENTS 40960 COPY 40960 COMPARE .'
    result = run(code + atomic); assert result[24] == -9 and result[:24] == result[25:49] and result[49] == 0
    assert run(code + ': BAD -1 1024 C8-PATTERN-EVENT! ; \' BAD CATCH .') == [-528]
    assert run('9223372036854775807 C8-TO : BAD 1 C8-RUN ; \' BAD CATCH . SNAP')[:3] == [-24, (1 << 63) - 1, ((1 << 63) - 1) % PERIOD]
    assert run('1 0 C8-MODE! 255 0 C8-PITCH! 255 0 C8-TIMER! 9223372036854775807 C8-TO SNAP')[:6] == [(1 << 63) - 1, ((1 << 63) - 1) % PERIOD, 0, 255, 1, 0]
    result = run('9223372036854774307 C8-TO CREATE OUT 4 ALLOT OUT 4 42 FILL SNAP : BAD OUT 2 C8-RENDER ; \' BAD CATCH . SNAP OUT C@ . OUT 3 + C@ .')
    assert result[24] == -24 and result[:24] == result[25:49] and result[49:] == [42, 42]
    assert run('9223372036854774807 C8-TO CREATE OUT 2 ALLOT OUT 1 C8-RENDER C8-CYCLE @ . OUT C@ . OUT 1+ C@ .') == [(1 << 63) - 1, 0, 0]
    assert run('1 0 C8-TIMER! : BAD -1 1 C8-RENDER ; \' BAD CATCH . C8-CYCLE @ .') == [-9, 1000]
    tests.append({'case': 'queue-capacity-reclaim-and-int64-overflow'})
    files = ['examples/chip8-audio.fs', 'examples/chip8-pitches.fs', 'examples/chip8-audio-play.fs', 'scripts/chip8-pitches.py', 'tests/scripts/verify-chip8-audio.py']
    print(json.dumps({'platform': platform.platform(), 'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
                      'source_sha256_lf': {f: hashlib.sha256((ROOT / f).read_bytes().replace(b'\r\n', b'\n')).hexdigest() for f in files},
                      'tests': tests, 'scope': __doc__}, indent=2))


if __name__ == '__main__': main()

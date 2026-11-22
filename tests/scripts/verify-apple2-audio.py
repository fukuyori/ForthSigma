#!/usr/bin/env python3
"""Independent per-cycle oracle and exhaustive bus checks for the Apple II speaker and Mockingboard model; no audio."""
import argparse, hashlib, json, math, platform, random, struct, subprocess, tempfile
from fractions import Fraction
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
LEVELS = [0] + [math.floor(32767 * 10 ** (3 * (i - 15) / 20)) for i in range(1, 16)]
MASKS = [255, 15, 255, 15, 255, 15, 31, 255, 31, 31, 31, 255, 255, 15, 255, 255]
# 14.31818 MHz is 315/22 MHz; 65 CPU cycles take 912 of its periods; 48000 frames a second.
PER_FRAME = Fraction(315_000_000, 22) * Fraction(65, 912) / 48000
NUM, DEN = PER_FRAME.numerator, PER_FRAME.denominator
CHIP = ['NOISE-COUNT', 'NOISE-HALF', 'LFSR', 'ENV-COUNT', 'ENV-STEP', 'ENV-ATTACK', 'ENV-HOLD', 'ENV-ALTERNATE',
        'ENV-HOLDING', 'LATCH', 'FUNC', 'HELD', 'ORB', 'ORA', 'DDRB', 'DDRA']
GLOBAL = ['SLOT', 'SPEAKER', 'HIGH', 'WINDOW', 'CYCLE', 'DIV', 'FRACTION', 'EVENT-COUNT', 'EVENT-INDEX']
DUMP = (': SNAP 2 0 DO I A2-CHIP! 16 0 DO I A2-R@ . LOOP 3 0 DO A2-TONE-COUNT I CELLS + @ . LOOP '
        '3 0 DO A2-TONE-HIGH I CELLS + @ . LOOP ' + ' '.join('A2-' + v + ' @ .' for v in CHIP) + ' LOOP '
        + ' '.join('A2-' + v + ' @ .' for v in GLOBAL) + ' ;\n')
STATE = 2 * 38 + 7   # the values of SNAP that the oracle predicts (not the two queue counters)
SNAPPED = STATE + 2


class Chip:
    """One 6522's two ports and the AY-3-8910 on them."""
    def __init__(self):
        self.orb = self.ora = self.ddrb = self.ddra = 0
        self.function = 0; self.in_reset = False; self.psg_reset()

    def psg_reset(self):
        self.r = [0] * 16; self.tc = [0] * 3; self.th = [False] * 3
        self.nc = self.nh = 0; self.lfsr = 1
        self.ec = self.half = 0; self.level = 15; self.attack = 0
        self.hold = True; self.alt = False; self.held = True; self.fresh = True; self.latch = 0

    def step(self):
        for i in range(3):
            self.tc[i] += 1
            if self.tc[i] >= max(1, self.r[i * 2] + 256 * self.r[i * 2 + 1]):
                self.tc[i] = 0; self.th[i] = not self.th[i]
        self.nh = 1 - self.nh
        if self.nh:
            self.nc += 1
            if self.nc >= max(1, self.r[6]):
                self.nc = 0; self.lfsr = (self.lfsr // 2) | (((self.lfsr ^ (self.lfsr // 8)) & 1) << 16)
        if not self.held:
            self.ec += 1
            if self.ec >= max(1, self.r[11] + 256 * self.r[12]):
                self.ec = 0; self.half = 1 - self.half
                if self.half == 0:
                    if self.level: self.level -= 1
                    else:
                        if self.alt: self.attack = 15 - self.attack
                        if self.hold: self.held = True
                        else: self.level = 15

    def reg(self, reg, value):
        self.r[reg] = value & MASKS[reg]
        if reg == 13:
            shape = self.r[13]; self.attack = 15 if shape & 4 else 0
            self.hold = bool(shape & 1) if shape & 8 else True
            self.alt = bool(shape & 2) if shape & 8 else bool(self.attack)
            self.level = 15; self.half = self.ec = 0; self.held = self.fresh = False

    def reg_read(self, reg):
        if reg == 14 and not self.r[7] & 64: return 255
        if reg == 15 and not self.r[7] & 128: return 255
        return self.r[reg]

    def pb(self):
        """Port B pin by pin: an output shows ORB; undriven BC1 and BDIR are low, the rest high."""
        return sum(((self.orb >> i & 1) if self.ddrb >> i & 1 else (0 if i < 2 else 1)) << i for i in range(8))

    def pa(self):
        reading = self.function == 1 and not self.in_reset and self.latch < 16
        ay = self.reg_read(self.latch) if reading else 255
        return sum(((self.ora >> i & 1) if self.ddra >> i & 1 else (ay >> i & 1)) << i for i in range(8))

    def bus(self):
        pins = self.pb()
        if not pins & 4:
            if not self.in_reset: self.psg_reset()
            self.in_reset = True; self.function = 0; return
        self.in_reset = False
        function = 2 * (pins >> 1 & 1) + (pins & 1)
        if function == self.function: return
        self.function = function
        if function == 3: self.latch = self.pa()
        if function == 2 and self.latch < 16: self.reg(self.latch, self.pa())

    def via_write(self, reg, value):
        if reg == 0: self.orb = value
        elif reg in (1, 15): self.ora = value
        elif reg == 2: self.ddrb = value
        elif reg == 3: self.ddra = value
        else: return
        self.bus()

    def via_read(self, reg):
        return {0: self.pb(), 2: self.ddrb, 3: self.ddra}.get(reg, self.pa())

    def sample(self):
        total = 0
        for i in range(3):
            gate = (self.th[i] or bool(self.r[7] & (1 << i))) and (bool(self.lfsr & 1) or bool(self.r[7] & (8 << i)))
            level = (self.level ^ self.attack) if self.r[8 + i] & 16 else self.r[8 + i] & 15
            total += LEVELS[level] if gate else 0
        return total // 6

    def state(self):
        step = 31 if self.fresh else 0 if self.held else self.level * 2 + 1 - self.half
        return (self.r + self.tc + [-int(v) for v in self.th]
                + [self.nc, self.nh, self.lfsr, self.ec, step, 31 if self.attack else 0, -int(self.hold),
                   -int(self.alt), -int(self.held), self.latch, self.function, -int(self.in_reset),
                   self.orb, self.ora, self.ddrb, self.ddra])


class Model:
    def __init__(self, slot):
        self.slot = slot; self.chips = [Chip(), Chip()]
        self.speaker = 0; self.levels = []; self.window = 0
        self.t = self.div = self.frac = 0

    def advance(self, tick):
        assert tick >= self.t
        while self.t < tick:
            self.levels.append(self.speaker); self.t += 1
            if self.slot:
                self.div += 1
                if self.div == 8:
                    self.div = 0
                    for chip in self.chips:
                        if not chip.in_reset: chip.step()

    def card(self, address):
        return self.slot and address // 256 == 0xC0 + self.slot

    def store(self, value, target):
        if target >= 65536:
            chip = self.chips[(target - 65536) // 16]
            if not chip.in_reset: chip.reg(target % 16, value)
        elif 0xC030 <= target <= 0xC03F: self.speaker ^= 1
        elif self.card(target): self.chips[target >> 7 & 1].via_write(target & 15, value)

    def read(self, target):
        """None means the model declines the read (-21)."""
        if target >= 65536: return self.chips[(target - 65536) // 16].reg_read(target % 16) if self.slot else None
        if 0xC030 <= target <= 0xC03F: self.speaker ^= 1; return 0
        if self.card(target) and target & 15 in (0, 1, 2, 3, 15): return self.chips[target >> 7 & 1].via_read(target & 15)
        return None

    def sample(self):
        window = self.levels[self.window:]
        speaker = 4096 * sum(window) // len(window) if window else 4096 * self.speaker
        if not self.slot: return speaker, speaker
        return speaker + self.chips[0].sample(), speaker + self.chips[1].sample()

    def render(self, frames, events):
        pending = list(events); index = 0; out = bytearray()
        for _ in range(frames):
            advance, self.frac = divmod(self.frac + NUM, DEN); end = self.t + advance
            while index < len(pending) and pending[index][0] <= end:
                tick, value, target = pending[index]; self.advance(tick); self.store(value, target); index += 1
            self.advance(end); out.extend(struct.pack('<hh', *self.sample())); self.window = len(self.levels)
        return bytes(out)

    def state(self):
        return (self.chips[0].state() + self.chips[1].state()
                + [self.slot, self.speaker, sum(self.levels[self.window:]), self.window, self.t, self.div, self.frac])


def psg_write(base, reg, value, tick):
    """The manual's sequence on one 6522: address, LATCH, inactive, data, WRITE, inactive."""
    return [(tick, reg, base + 1), (tick, 7, base), (tick, 4, base), (tick, value, base + 1), (tick, 6, base), (tick, 4, base)]


def queue(events):
    return '\n'.join(f'{value} {target} {tick} A2-EVENT!' for tick, value, target in events) + '\n'


def main():
    p = argparse.ArgumentParser(description=__doc__); p.add_argument('sigma', type=Path); args = p.parse_args()
    binary = args.sigma.resolve(); work = ROOT / '.work/1179'; work.mkdir(parents=True, exist_ok=True); tests = []

    def run(code):
        with tempfile.NamedTemporaryFile('w', encoding='utf-8', suffix='.fs', dir=work, delete=False) as f:
            file = Path(f.name); f.write(DUMP + code + '\nDEPTH . BYE\n')
        try: r = subprocess.run([str(binary), 'include/apple2-audio.fs', str(file)], cwd=ROOT, input=b'', capture_output=True, timeout=300)
        finally: file.unlink()
        assert r.returncode == 0 and not r.stderr, (r.returncode, r.stdout[:2000], r.stderr)
        values = list(map(int, r.stdout.split())); assert values.pop() == 0, 'stack leak'; return values

    assert (NUM, DEN) == (284375, 13376)
    assert run('A2-NUM . A2-DEN . A2-RATE . : TBL 16 0 DO I CELLS ZX-LEVELS + @ . LOOP ; TBL') == [NUM, DEN, 48000] + LEVELS
    tests.append({'case': 'frame-ratio-from-315/22MHz-65/912-and-16-levels', 'cycles_per_frame': f'{NUM}/{DEN}'})

    # Every address, written once after a reset: the speaker and the two 6522s' four registers.
    for slot in [0, 4]:
        values = run(f': PORTS 65536 0 DO {slot} A2-CARD! A2-RESET I 13 * 255 AND I 0 A2-WRITE A2-SPEAKER @ . '
                     '2 0 DO I A2-CHIP! A2-ORB @ A2-ORA @ 256 * + A2-DDRB @ 65536 * + A2-DDRA @ 16777216 * + . LOOP LOOP ; PORTS')
        wanted = []
        for address in range(65536):
            value = address * 13 & 255; regs = [0, 0]
            card = slot and address >> 8 == 0xC0 + slot
            if card and address & 15 in (0, 1, 2, 3, 15):
                regs[address >> 7 & 1] = value << {0: 0, 1: 8, 15: 8, 2: 16, 3: 24}[address & 15]
            wanted.extend([int(address >> 4 == 0xC03)] + regs)
        assert values == wanted, slot
        tests.append({'case': f'all65536-write-decodes-slot{slot}', 'sha256': hashlib.sha256(struct.pack(f'<{len(values)}I', *values)).hexdigest()})
    # The card's page in each of the seven slots; no other page reaches the card.
    values = run(': SLOTS 8 1 DO 256 192 DO J A2-CARD! A2-RESET 255 I 256 * 3 + 0 A2-WRITE 0 A2-CHIP! A2-DDRA @ . LOOP LOOP ; SLOTS')
    assert values == [255 if page == 0xC0 + slot else 0 for slot in range(1, 8) for page in range(192, 256)]
    tests.append({'case': 'card-page-in-slots1to7'})
    # Every address read: the speaker toggles and returns 0, five 6522 registers answer, the rest decline.
    for slot in [0, 4]:
        values = run(f'{slot} A2-CARD! A2-RESET VARIABLE AT : GET AT @ 0 A2-READ ; '
                     ': READS 65536 0 DO I AT ! A2-SPEAKER @ [\'] GET CATCH ?DUP IF . ELSE . THEN A2-SPEAKER @ XOR . LOOP ; READS')
        wanted = []
        for address in range(65536):
            if address >> 4 == 0xC03: wanted.extend([0, 1])
            elif slot and address >> 8 == 0xC0 + slot and address & 15 in (0, 1, 2, 3, 15):
                wanted.extend([{0: 252, 2: 0, 3: 0}.get(address & 15, 255), 0])
            else: wanted.extend([-21, 0])
        assert values == wanted, slot
        tests.append({'case': f'all65536-reads-slot{slot}'})

    # All 16 registers and 256 values through the direct path. R7 ends at 255, so ports A and B are outputs.
    values = run('4 A2-CARD! A2-RESET : MASKS 2 0 DO 16 0 DO 256 0 DO I J K 0 A2-AY! J K 0 A2-AY@ . LOOP LOOP LOOP ; MASKS')
    assert values == [v & MASKS[reg] for _ in range(2) for reg in range(16) for v in range(256)]
    assert run('4 A2-CARD! A2-RESET 165 14 0 0 A2-AY! 90 15 0 0 A2-AY! 14 0 0 A2-AY@ . 15 0 0 A2-AY@ . 64 7 0 0 A2-AY! 14 0 0 A2-AY@ . 15 0 0 A2-AY@ . 128 7 0 0 A2-AY! 14 0 0 A2-AY@ . 15 0 0 A2-AY@ .') == [255, 255, 165, 255, 255, 90]
    tests.append({'case': 'all16-registers256values-masks-both-chips-and-io-port-directions'})

    # The 6522 and the AY bus, by hand. Slot 4: the first 6522 is at 50176, the second at 50304.
    def via(code):
        return run('4 A2-CARD! A2-RESET : W ( value reg -- ) 50176 + 0 A2-WRITE ; : R ( reg -- ) 50176 + 0 A2-READ . ; '
                   ': AY ( reg -- ) 0 0 A2-AY@ . ; ' + code)
    init = '255 3 W 7 2 W '
    # The manual's INIT, RESET, LATCH, WRITE; then the read function with port A as an input.
    assert via(init + '0 0 W 4 0 W 8 1 W 7 0 W 4 0 W 13 1 W 6 0 W 4 0 W 8 AY 0 3 W 5 0 W 1 R 4 0 W 1 R') == [13, 13, 255]
    # After a reset of the machine port B is an input: PB2 reads high, BC1 and BDIR low, the AY is not in reset.
    assert via('0 R 1 R 2 R 3 R 0 A2-CHIP! A2-HELD @ . A2-FUNC @ .') == [252, 255, 0, 0, 0, 0]
    # DDRB to outputs with ORB 0 pulls RESET low: the registers clear and stay closed until PB2 is high.
    assert via('9 8 0 0 A2-AY! 8 AY 7 2 W 8 AY 0 A2-CHIP! A2-HELD @ . 255 3 W 8 1 W 3 0 W 5 1 W 2 0 W 8 AY 4 0 W 8 AY') == [9, 0, -1, 0, 0]
    # A function acts once, on entry: data that changes while WRITE is held does not reach the register.
    assert via(init + '4 0 W 8 1 W 7 0 W 4 0 W 5 1 W 6 0 W 9 1 W 8 AY 6 0 W 8 AY 4 0 W 6 0 W 8 AY') == [5, 5, 9]
    # LATCH to WRITE without passing through inactive is still a change of function.
    assert via(init + '4 0 W 8 1 W 7 0 W 6 0 W 8 AY 0 A2-CHIP! A2-LATCH @ .') == [8, 8]
    # Leaving reset straight into LATCH latches; an address of 16 or more deselects the chip.
    assert via(init + '0 0 W 9 1 W 7 0 W 0 A2-CHIP! A2-LATCH @ . 4 0 W 16 1 W 7 0 W 4 0 W 77 1 W 6 0 W 4 0 W '
               '0 A2-CHIP! A2-LATCH @ . : Z 16 0 DO I A2-R@ . LOOP ; Z 0 3 W 5 0 W 1 R') == [9, 16] + [0] * 16 + [255]
    # Port A bit by bit: outputs show ORA, inputs show the AY (reading register 0 = 165) or stay high.
    assert via(init + '4 0 W 165 0 0 0 A2-AY! 0 1 W 7 0 W 4 0 W 60 1 W 240 3 W 5 0 W 1 R 15 R 4 0 W 1 R') == [53, 53, 63]
    # Port B bit by bit: with DDRB 5 the undriven BDIR is low, so ORB 7 gives READ (1), not LATCH.
    assert via('255 3 W 5 2 W 7 0 W 0 R 0 A2-CHIP! A2-FUNC @ . 2 0 W 0 R A2-HELD @ .') == [253, 1, 248, -1]
    # Registers 4 to 14 of a 6522 are not modelled: a write does nothing, a read declines.
    assert via(': T 11 0 DO I 4 + 50176 + 0 [\'] A2-READ CATCH NIP NIP . 255 I 4 + W LOOP ; T SNAP')[:11] == [-21] * 11
    r = via(': T 11 0 DO 255 I 4 + W LOOP ; SNAP T SNAP'); assert r[:SNAPPED] == r[SNAPPED:]
    # The two 6522s are separate, and the page mirrors bits 4 to 6.
    assert via('1 50176 0 A2-WRITE 2 50304 0 A2-WRITE 3 50176 112 + 1 + 0 A2-WRITE 4 50304 112 + 15 + 0 A2-WRITE '
               ': Z 2 0 DO I A2-CHIP! A2-ORB @ . A2-ORA @ . LOOP ; Z') == [1, 3, 2, 4]
    tests.append({'case': 'hand-6522-ports-and-ay-bus-functions', 'cases': 11})

    # Random bus traffic on both 6522s, direct AY writes and the speaker, against the oracle: every read and the final state.
    rng = random.Random(1179); m = Model(4); lines = []; reads = []; tick = 0
    for _ in range(6000):
        tick += rng.choice([0, 0, 1, 3, 8, 21, 100]); kind = rng.random(); m.advance(tick)
        if kind < 0.55:
            target = 50176 + 128 * rng.randrange(2) + 16 * rng.randrange(8) + rng.choice([0, 0, 0, 1, 1, 1, 2, 3, 15, rng.randrange(4, 15)])
            value = rng.choice([4, 5, 6, 7, 0, 3, 255, rng.randrange(256), rng.randrange(16)])
            m.store(value, target); lines.append(f'{value} {target} {tick} A2-WRITE')
        elif kind < 0.8:
            target = 50176 + 128 * rng.randrange(2) + rng.choice([0, 1, 2, 3, 15])
            reads.append(m.read(target)); lines.append(f'{target} {tick} A2-READ .')
        elif kind < 0.9:
            target = 65536 + rng.randrange(32); value = rng.randrange(256)
            m.store(value, target); lines.append(f'{value} {target} {tick} A2-WRITE')
        elif kind < 0.95:
            target = 65536 + rng.randrange(32); reads.append(m.read(target)); lines.append(f'{target} {tick} A2-READ .')
        else:
            target = 0xC030 + rng.randrange(16)
            if rng.random() < 0.5: m.store(0, target); lines.append(f'0 {target} {tick} A2-WRITE')
            else: reads.append(m.read(target)); lines.append(f'{target} {tick} A2-READ .')
    values = run('4 A2-CARD! A2-RESET\n' + '\n'.join(lines) + '\nSNAP')
    assert values[:len(reads)] == reads and values[len(reads):len(reads) + STATE] == m.state()
    tests.append({'case': 'random6000-bus-accesses-reads-and-state', 'reads': len(reads),
                  'state_sha256': hashlib.sha256(json.dumps(m.state()).encode()).hexdigest()})

    # The AY's 16 levels, by hand; each level lasts 2 EP steps of 8 CPU cycles, on the second chip.
    for shape in range(16):
        down = list(range(15, -1, -1)); up = list(range(16))
        sequences = {**{i: down + [0] * 80 for i in range(4)}, **{i: up + [0] * 80 for i in range(4, 8)},
                     8: down * 6, 9: down + [0] * 80, 10: (down + up) * 3, 11: down + [15] * 80,
                     12: up * 6, 13: up + [15] * 80, 14: (up + down) * 3, 15: up + [0] * 80}
        code = f'4 A2-CARD! A2-RESET 1 11 1 0 A2-AY! {shape} 13 1 0 A2-AY! : ENV 96 0 DO I 16 * A2-TO 1 A2-CHIP! A2-ENV-LEVEL 1 RSHIFT . LOOP ; ENV'
        assert run(code) == sequences[shape]
    tests.append({'case': 'all16-envelope-shapes96levels-hand-sequences'})
    # Hand timing: the shared step every 8 cycles, period 0 as 1, shortened periods, R13 and the divider.
    c = '4 A2-CARD! A2-RESET 0 A2-CHIP! '
    assert run(c + '7 A2-TO 0 A2-CHIP! A2-TONE-COUNT @ . A2-TONE-HIGH @ . 8 A2-TO 0 A2-CHIP! A2-TONE-COUNT @ . A2-TONE-HIGH @ . A2-LFSR @ . 16 A2-TO 0 A2-CHIP! A2-LFSR @ . 24 A2-TO 0 A2-CHIP! A2-LFSR @ .') == [0, 0, 0, -1, 65536, 65536, 32768]
    assert run(c + '10 0 0 0 A2-AY! 72 A2-TO 0 A2-CHIP! A2-TONE-COUNT @ . 2 0 0 72 A2-AY! 80 A2-TO 0 A2-CHIP! A2-TONE-COUNT @ . A2-TONE-HIGH @ .') == [9, 0, -1]
    assert run(c + '10 11 0 0 A2-AY! 8 13 0 0 A2-AY! 72 A2-TO 0 A2-CHIP! A2-ENV-COUNT @ . 1 11 0 72 A2-AY! 80 A2-TO 0 A2-CHIP! A2-ENV-COUNT @ . A2-ENV-STEP @ . '
               '8 13 0 81 A2-AY! 87 A2-TO 0 A2-CHIP! A2-ENV-STEP @ . 88 A2-TO 0 A2-CHIP! A2-ENV-STEP @ .') == [9, 0, 30, 31, 30]
    assert run(c + '10 6 0 0 A2-AY! 144 A2-TO 0 A2-CHIP! A2-NOISE-COUNT @ . A2-LFSR @ . 1 6 0 144 A2-AY! 160 A2-TO 0 A2-CHIP! A2-NOISE-COUNT @ . A2-LFSR @ .') == [9, 1, 0, 65536]
    assert run(c + '1 12 0 0 A2-AY! 8 13 0 0 A2-AY! 2047 A2-TO 0 A2-CHIP! A2-ENV-STEP @ . 2048 A2-TO 0 A2-CHIP! A2-ENV-STEP @ .') == [31, 30]
    # A tone of period 100 on the first chip only: 800 cycles a half wave; the second chip stays silent.
    assert run(c + '100 0 0 0 A2-AY! 62 7 0 0 A2-AY! 15 8 0 0 A2-AY! 799 A2-TO A2-SAMPLE . . 800 A2-TO A2-SAMPLE . . 1600 A2-TO A2-SAMPLE . .') == [0, 0, 0, 5461, 0, 0]
    # The reset pin clears the generators but not the shared divider.
    assert run(c + '2 0 0 0 A2-AY! 20 A2-TO 7 50178 20 A2-WRITE 0 A2-CHIP! A2-TONE-COUNT @ . A2-TONE-HIGH @ . A2-DIV @ . A2-HELD @ .') == [0, 0, 4, -1]
    # While the pin holds the AY in reset it does not run and takes no write, by the bus or directly; the other AY goes on.
    # 101 steps by cycle 808: the second AY's tone (period 1) is high, the held first AY has not moved; one step after the release it has.
    assert run(c + '7 50178 0 A2-WRITE 15 8 0 0 A2-AY! 62 7 0 0 A2-AY! 15 8 1 0 A2-AY! 62 7 1 0 A2-AY! 8 0 0 A2-AY@ . 808 A2-TO A2-SAMPLE . . '
               '0 A2-CHIP! A2-HELD @ . A2-LFSR @ . A2-TONE-HIGH @ . 1 A2-CHIP! A2-TONE-HIGH @ . 4 50176 808 A2-WRITE 9 8 0 808 A2-AY! 8 0 808 A2-AY@ . '
               '816 A2-TO 0 A2-CHIP! A2-TONE-HIGH @ . A2-HELD @ .') == [0, 5461, 0, -1, 1, 0, -1, 9, -1, 0]
    # After a reset the envelope stays at level 15 until R13 is written, and A2-RESET puts A2-SLOW back to FALSE.
    assert run(c + '16 8 0 0 A2-AY! 63 7 0 0 A2-AY! 1000000 A2-TO A2-SAMPLE . . TRUE A2-SLOW ! A2-RESET A2-SLOW @ .') == [0, 5461, 0]
    tests.append({'case': 'hand-divider-zero-periods-shortening-retrigger-and-pin-reset'})
    # 64 mixer truth tables with all four tone/noise combinations.
    vals = run(': GATES 4 A2-CARD! A2-RESET 15 8 0 0 A2-AY! 64 0 DO I 7 0 0 A2-AY! 0 A2-CHIP! 2 0 DO I A2-TONE-HIGH ! 2 0 DO I A2-LFSR ! 0 A2-CHANNEL . LOOP LOOP LOOP ; GATES')
    assert vals == [32767 if (tone or mask & 1) and (noise or mask & 8) else 0 for mask in range(64) for tone in range(2) for noise in range(2)]
    tests.append({'case': 'all64-mixer-truth-tables'})

    # The speaker by hand. Frames 0 and 1 are cycles 0-20 and 21-41 (284375/13376 = 21.26).
    def speaker(code): return run('0 A2-CARD! A2-RESET CREATE OUT 64 ALLOT : F ( n -- ) OUT SWAP A2-RENDER ; : S OUT C@ OUT 1+ C@ 256 * + . OUT 2 + C@ OUT 3 + C@ 256 * + . ; ' + code)
    assert speaker('1 F S 21 A2-TOGGLE 1 F S A2-CYCLE @ . A2-FRACTION @ .') == [0, 0, 4096, 4096, 42, 6958]
    # A toggle at cycle 10 leaves 11 of the 21 cycles high: 4096 x 11 / 21 = 2145; then low again from cycle 30: 9 of 21 = 1755.
    assert speaker('10 A2-TOGGLE-EVENT! 30 A2-TOGGLE-EVENT! 1 F S 1 F S 1 F S') == [2145, 2145, 1755, 1755, 0, 0]
    # Two accesses in one cycle cancel; a read and a write each toggle once; all of C030-C03F, and not C02F or C040.
    assert speaker('5 A2-TOGGLE 5 A2-TOGGLE A2-SPEAKER @ . 49200 6 A2-READ . A2-SPEAKER @ . 9 49215 7 A2-WRITE A2-SPEAKER @ . '
                   '0 49199 8 A2-WRITE 0 49216 8 A2-WRITE A2-SPEAKER @ . 1 F S') == [0, 0, 1, 0, 0, 141, 141]  # one high cycle of the 29 since the reset
    # A sample covers every cycle since the last rendered frame, also after A2-TO; A2-SAMPLE does not close the window.
    assert speaker('0 A2-TOGGLE 30 A2-TO 30 A2-TOGGLE 60 A2-TO A2-SAMPLE . . A2-SAMPLE . . 1 F S A2-HIGH @ . A2-WINDOW @ . A2-SAMPLE . .') == [2048, 2048, 2048, 2048, 1517, 1517, 0, 81, 0, 0]
    # Exactly 284375 cycles in 13376 frames, with no remainder; a second of frames is 1020484 cycles.
    assert speaker(f': RUN1 13376 0 DO 1 F LOOP ; RUN1 A2-CYCLE @ . A2-FRACTION @ . : RUN2 48000 13376 - 0 DO 1 F LOOP ; RUN2 A2-CYCLE @ . A2-FRACTION @ .') == [284375, 0, 48000 * NUM // DEN, 48000 * NUM % DEN]
    assert 48000 * NUM // DEN == 1020484
    tests.append({'case': 'hand-speaker-mean-toggles-decode-window-and-frame-ratio'})

    # Whole PCM and state against the per-cycle oracle: fast, per-cycle (slow) and split rendering.
    for slot in [0, 4]:
        m = Model(slot); assert run(f'{slot} A2-CARD! A2-RESET SNAP')[:STATE] == m.state()
        events = [(i * 513 + 7, 0, 0xC030 + i % 16) for i in range(169)] + [(30000 + i * 5, 0, 0xC030) for i in range(300)]
        if slot:
            for base in (50176, 50304): events += [(0, 255, base + 3), (0, 7, base + 2), (0, 4, base)]
            for reg, value in enumerate([28, 1, 227, 1, 82, 2, 9, 48, 12, 10, 16, 100, 0, 14]): events += psg_write(50176, reg, value, 1)
            for reg, value in enumerate([120, 0, 60, 2, 9, 0, 3, 28, 16, 9, 13, 40, 2, 10]): events += psg_write(50304, reg, value, 2)
            events += psg_write(50176, 7, 0, 20011) + psg_write(50304, 13, 12, 41000) + psg_write(50176 + 96, 0, 1, 52000)
            events += [(60000, 0, 50304), (60003, 4, 50304)] + psg_write(50304, 0, 77, 60010) + psg_write(50304, 8, 15, 60010) + psg_write(50304, 7, 62, 60010)
            events += [(70000, 64, 65536 + 7), (70001, 1, 65536 + 11), (70002, 0, 65536 + 12), (70003, 14, 65536 + 13), (70004, 0, 65536 + 16 + 6)]
        events.sort(key=lambda x: x[0]); assert len(events) < 1024
        expected = m.render(4096, events)
        with tempfile.TemporaryDirectory(prefix='pcm-', dir=work) as tmp:
            out = Path(tmp) / 'pcm.bin'; base = f'{slot} A2-CARD! A2-RESET\n' + queue(events) + 'CREATE OUT 16384 ALLOT\n'
            for slow, body in [(False, 'OUT 4096 A2-RENDER'), (True, 'OUT 4096 A2-RENDER'), (False, 'OUT 13 A2-RENDER OUT 52 + 4083 A2-RENDER')]:
                result = run(base + ('TRUE A2-SLOW !\n' if slow else '') + body + f' S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 16384 FD WRITE-FILE THROW FD CLOSE-FILE THROW SNAP')
                assert out.read_bytes() == expected, (slot, slow); assert result[:STATE] == m.state(); assert result[STATE] == result[STATE + 1]
        assert len(set(expected)) > 16 and (slot == 0) == (expected[0::4] == expected[2::4] and expected[1::4] == expected[3::4])
        tests.append({'case': f'full4096frame-stereo-slow-fast-split-state-slot{slot}', 'events': len(events), 'pcm_sha256': hashlib.sha256(expected).hexdigest()})

    # Random register traffic with short and shortened periods, and a jump of 54321 cycles between two renders:
    # the batched advance (fast) against the per-cycle path (slow) and the oracle.
    rng = random.Random(11790); events = []; tick = 0
    for _ in range(900):
        tick += rng.choice([1, 5, 40, 90, 300, 300]); reg = rng.choice([0, 1, 2, 3, 4, 5, 6, 6, 7, 8, 9, 10, 11, 11, 12, 13, 13])
        value = rng.choice([0, 1, 2, 3, rng.randrange(256)]) if reg in (0, 2, 4, 6, 11) else 0 if reg in (1, 3, 5, 12) and rng.random() < 0.8 else rng.randrange(256)
        events.append((tick, value, 65536 + 16 * rng.randrange(2) + reg))
    m = Model(4); first = m.render(1500, events); start = m.t; end = start + 54321
    for tick, value, target in events:
        if start < tick <= end: m.advance(tick); m.store(value, target)
    m.advance(end); later = [e for e in events if e[0] > end]; expected = first + m.render(548, later)
    assert 50 < len(later) < 850 and later[0][0] < m.t and len(set(expected)) > 64
    with tempfile.TemporaryDirectory(prefix='pcm-', dir=work) as tmp:
        out = Path(tmp) / 'pcm.bin'; base = '4 A2-CARD! A2-RESET\n' + queue(events) + 'CREATE OUT 8192 ALLOT\n'
        for slow in [False, True]:
            result = run(base + ('TRUE A2-SLOW !\n' if slow else '') + 'OUT 1500 A2-RENDER 54321 A2-RUN OUT 6000 + 548 A2-RENDER'
                         + f' S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 8192 FD WRITE-FILE THROW FD CLOSE-FILE THROW SNAP')
            assert out.read_bytes() == expected, slow; assert result[:STATE] == m.state()
    tests.append({'case': 'random900-register-writes-short-periods-jump-slow-fast-state', 'pcm_sha256': hashlib.sha256(expected).hexdigest()})

    # Long advances with nothing queued, up to more than one whole noise sequence (131071 shifts at period 1 take 2097136 cycles).
    rng = random.Random(117900); m = Model(4); lines = ['4 A2-CARD! A2-RESET']; wanted = []
    for jump in [10000, 123457, 1000003, 3000001, 77, 250000]:
        for chip in range(2):
            for reg in rng.sample(range(14), 6):
                value = rng.choice([0, 1, 2, rng.randrange(256)]) if reg != 13 else rng.choice([8, 10, 12, 14, 9, 0, 4, 11])
                m.store(value, 65536 + 16 * chip + reg); lines.append(f'{value} {reg} {chip} {m.t} A2-AY!')
        m.advance(m.t + jump); lines.append(f'{jump} A2-RUN A2-SAMPLE SWAP . . SNAP'); wanted += list(m.sample()) + m.state() + [0, 0]
    assert run('\n'.join(lines)) == wanted
    tests.append({'case': 'long-advances-up-to-3000001-cycles-samples-and-state', 'sha256': hashlib.sha256(json.dumps(wanted).encode()).hexdigest()})

    # Same cycle: events already queued, then the immediate access; a later event for that cycle waits for the next advance.
    assert run('0 A2-CARD! A2-RESET 100 A2-TOGGLE-EVENT! A2-SPEAKER @ . 100 A2-TOGGLE A2-SPEAKER @ . 100 A2-TOGGLE-EVENT! A2-SPEAKER @ . 0 A2-RUN A2-SPEAKER @ .') == [0, 0, 0, 1]
    assert run('4 A2-CARD! A2-RESET 5 8 0 100 A2-AY-EVENT! 7 8 0 100 A2-AY! 8 0 100 A2-AY@ . 5 8 0 100 A2-AY-EVENT! 0 A2-CHIP! 8 A2-R@ . 8 0 100 A2-AY@ .') == [7, 7, 5]
    tests.append({'case': 'same-cycle-queued-then-immediate-order'})
    # Errors leave the whole state and queue as they were.
    bad = [(0, '1 65536 100 A2-WRITE', -21), (0, '65536 100 A2-READ', -21), (0, '50177 100 A2-READ', -21), (0, '1 0 0 100 A2-AY!', -21),
           (4, '256 49200 100 A2-WRITE', -24), (4, '-1 49200 100 A2-WRITE', -24), (4, '1 65568 100 A2-WRITE', -24), (4, '1 -1 100 A2-WRITE', -24),
           (4, '65568 100 A2-READ', -24), (4, '-1 100 A2-READ', -24), (4, '50180 100 A2-READ', -21), (4, '49199 100 A2-READ', -21),
           (4, '50433 100 A2-READ', -21), (4, '0 49200 99 A2-WRITE', -24), (4, '49200 99 A2-READ', -24), (4, '99 A2-TO', -24),
           (4, '-1 A2-RUN', -24), (4, '8 A2-CARD!', -24), (4, '-1 A2-CARD!', -24), (4, '1 16 0 100 A2-AY!', -24), (4, '1 0 2 100 A2-AY!', -24),
           (4, '1 -1 0 100 A2-AY!', -24), (4, '0 2 100 A2-AY@', -24), (4, '0 49200 150 A2-EVENT!', -24), (4, '256 49200 300 A2-EVENT!', -24),
           (0, '1 65536 300 A2-EVENT!', -21), (4, '256 65600 99 A2-WRITE', -24),
           (0, '1 65536 99 A2-WRITE', -24), (0, '65536 99 A2-READ', -24), (0, '50177 99 A2-READ', -24), (0, '1 65536 150 A2-EVENT!', -21)]
    for slot, body, error in bad:
        code = (f'{slot} A2-CARD! A2-RESET 0 A2-TOGGLE 100 A2-RUN 0 49200 200 A2-EVENT! CREATE COPY 24576 ALLOT A2-EVENTS COPY 24576 MOVE '
                f'SNAP A2-NEXT-SLOT @ . : BAD {body} ; \' BAD CATCH . SNAP A2-NEXT-SLOT @ . A2-EVENTS 24576 COPY 24576 COMPARE .')
        r = run(code); n = SNAPPED + 1
        assert r[n] == error and r[:n] == r[n + 1:2 * n + 1] and r[2 * n + 1] == 0, (body, r)
    tests.append({'case': 'atomic-input-errors-state-and-entire-queue', 'cases': len(bad)})
    q = '0 A2-CARD! A2-RESET : FILLQ 1024 0 DO I A2-TOGGLE-EVENT! LOOP ; FILLQ '
    assert run(q + ': BAD 0 A2-TOGGLE-EVENT! ; \' BAD CATCH .') == [-528]
    assert run(q + ': BAD 1024 A2-TOGGLE-EVENT! ; \' BAD CATCH . 511 A2-TO 1024 A2-TOGGLE-EVENT! A2-EVENT-COUNT @ . A2-EVENT-INDEX @ . A2-SPEAKER @ . 1024 A2-TO A2-SPEAKER @ . A2-HIGH @ .') == [-528, 513, 0, 0, 1, 512]
    for slot in [0, 4]:
        # Near the end of time the preflight declines before anything changes; one frame that fits succeeds.
        r = run(f'{slot} A2-CARD! A2-RESET 9223372036854775780 A2-CYCLE ! CREATE OUT 8 ALLOT OUT 8 42 FILL SNAP : BAD OUT 2 A2-RENDER ; \' BAD CATCH . SNAP OUT C@ . OUT 7 + C@ .')
        assert r[SNAPPED] == -24 and r[:SNAPPED] == r[SNAPPED + 1:2 * SNAPPED + 1] and r[2 * SNAPPED + 1:] == [42, 42], (slot, r)
        r = run(f'{slot} A2-CARD! A2-RESET 9223372036854775780 A2-CYCLE ! 9223372036854775780 A2-WINDOW ! CREATE OUT 4 ALLOT OUT 1 A2-RENDER A2-CYCLE @ . A2-FRACTION @ . A2-MAX-FRAMES .')
        assert r == [9223372036854775780 + NUM // DEN, NUM % DEN, (6 * DEN + DEN - 1 - NUM % DEN) // NUM]
    # The frame limit against a search with whole numbers: the most frames whose cycles still fit, at five states.
    top = 2 ** 63 - 1
    for cycle, fraction in [(0, 0), (top - 87081, 0), (top - 87081, 8831), (top - 87081, 8832), (top - 1000000, 13375)]:
        limit = ((top - cycle) * DEN + DEN - 1 - fraction) // NUM
        assert (fraction + limit * NUM) // DEN <= top - cycle < (fraction + (limit + 1) * NUM) // DEN
        assert run(f'0 A2-CARD! A2-RESET {cycle} A2-CYCLE ! {cycle} A2-WINDOW ! {fraction} A2-FRACTION ! A2-MAX-FRAMES . '
                   f': BAD 0 A2-MAX-FRAMES 1+ A2-RENDER ; \' BAD CATCH . A2-CYCLE @ .') == [limit, -24, cycle]
    assert [(87081 * DEN + DEN - 1 - f) // NUM for f in (0, 8831, 8832)] == [4096, 4096, 4095]
    assert run('0 A2-CARD! A2-RESET : BAD -1 1 A2-RENDER ; \' BAD CATCH . A2-CYCLE @ . A2-FRACTION @ . : BAD2 0 -1 A2-RENDER ; \' BAD2 CATCH .') == [-9, 21, 3479, -24]
    tests.append({'case': 'queue-capacity-reclaim-wide-time-preflight-and-partial-memory-error'})
    files = ['tests/scripts/verify-apple2-audio.py', 'include/apple2-audio.fs', 'include/zx-ay-levels.fs']
    print(json.dumps({'platform': platform.platform(), 'scope': __doc__, 'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
                      'source_sha256_lf': {f: hashlib.sha256((ROOT / f).read_bytes().replace(b'\r\n', b'\n')).hexdigest() for f in files}, 'tests': tests}, indent=2))


if __name__ == '__main__': main()

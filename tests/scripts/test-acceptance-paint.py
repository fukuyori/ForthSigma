"""Synthetic endpoint checks only: never launches Sigma or measures elapsed time."""
import json
from pathlib import Path
import runpy
import uuid

summary = runpy.run_path(str(Path(__file__).with_name('run-acceptance.py')))['paint_summary']
directory = Path(__file__).resolve().parents[2] / '.work' / ('paint-parser-' + uuid.uuid4().hex)
directory.mkdir(parents=True)
path = Path(directory) / 'paint.log'
rows = []
for event, frame, detail, at in [('request', 1, 0, 100), ('complete', 1, 0, 200),
        ('wait-register', 1, 0, 110), ('wait-painted', 1, 0, 210), ('input', 2, 0, 1000),
        ('request', 2, 0, 2000), ('wait-register', 2, 0, 2100), ('complete', 2, 0, 3000),
        ('wait-painted', 2, 0, 3100), ('terminal', 2, 2, 3200)]:
    rows.append(dict(event=event, frame=frame, detail=detail, at=at, smoke=False))
def write(values):
    path.write_text(''.join('PAINTTRACE ' + json.dumps(r) + '\n' for r in values), encoding='utf-8')
write(rows)
result = summary(path, 'measure')
assert not result['missing']
write(rows + [dict(event=kind, frame=1, detail=0, at=150, smoke=False)
              for kind in ('take', 'draw-begin', 'draw-end', 'roundtrip', 'future-event')])
assert summary(path, 'measure') == result
assert result['statistics']['input_screen_ns']['maximum'] == 2000
assert result['statistics']['input_terminal_ns']['maximum'] == 2200
assert summary(path, 'smoke')['status'] == 'format-only'
assert 'statistics' not in summary(path, 'smoke')
write([r for r in rows if r['event'] != 'complete' or r['frame'] != 2])
assert summary(path, 'measure')['missing']
write(rows + [dict(lost_events=1)])
assert 'paint ring overflow' in summary(path, 'measure')['missing']
for invalid in (rows + [rows[0]], [dict(rows[0], at=-1)],
                [dict(r, at=0) if r['event'] == 'input' else r for r in rows], [dict(rows[0], smoke=True)],
                [dict(rows[0], at=400), *rows[1:]]):
    write(invalid)
    try:
        summary(path, 'measure')
    except ValueError:
        pass
    else:
        raise AssertionError('invalid endpoints accepted')
# Plan v8: a frame is late only when its own request->complete exceeds 1/60 s. A loop period
# slightly over 16.67 ms accumulates cadence misses without per-frame misses.
period, paint = 17_000_000, 5_000_000
cadence_rows = []
for frame in range(1, 61):
    start = frame * period
    cadence_rows += [dict(event='request', frame=frame, detail=0, at=start, smoke=False),
                     dict(event='wait-register', frame=frame, detail=0, at=start + 1, smoke=False),
                     dict(event='complete', frame=frame, detail=0, at=start + paint, smoke=False),
                     dict(event='wait-painted', frame=frame, detail=0, at=start + paint + 1, smoke=False)]
late = dict(cadence_rows[-2], at=cadence_rows[-4]['at'] + 17_000_000)
write(cadence_rows[:-2] + [late, dict(cadence_rows[-1], at=late['at'] + 1)])
paced = summary(path, 'measure', baseline=True)
assert paced['frame_deadline_exceedances'] == 1, paced['frame_deadline_exceedances']
assert paced['cadence_deadline_exceedances'] >= 5, paced['cadence_deadline_exceedances']
# Baseline inputs share one requested generation: counted, not joined, not duplicates.
write(cadence_rows + [dict(event='input', frame=2, detail=0, at=k, smoke=False) for k in (5, 6, 7)])
assert summary(path, 'measure', baseline=True)['input_count'] == 3
try:
    summary(path, 'measure')
except ValueError:
    pass
else:
    raise AssertionError('duplicate load input endpoints accepted')
print('Paint endpoint joins, missing/overflow, duplicate/backwards rejection, smoke exclusion, per-frame deadline and baseline inputs passed')

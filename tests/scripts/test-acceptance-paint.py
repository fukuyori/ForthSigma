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
assert result['statistics']['input_screen_ns']['maximum'] == 2000
assert result['statistics']['input_terminal_ns']['maximum'] == 2200
assert summary(path, 'smoke')['status'] == 'format-only'
assert 'statistics' not in summary(path, 'smoke')
write([r for r in rows if r['event'] != 'complete' or r['frame'] != 2])
assert summary(path, 'measure')['missing']
write(rows + [dict(lost_events=1)])
assert 'paint ring overflow' in summary(path, 'measure')['missing']
for invalid in (rows + [rows[0]], [dict(rows[0], at=-1)], [dict(rows[0], smoke=True)],
                [dict(rows[0], at=400), *rows[1:]]):
    write(invalid)
    try:
        summary(path, 'measure')
    except ValueError:
        pass
    else:
        raise AssertionError('invalid endpoints accepted')
print('Paint endpoint joins, missing/overflow, duplicate/backwards rejection, smoke exclusion passed')

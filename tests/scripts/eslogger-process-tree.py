"""Trace sigma process trees in an eslogger fork/exec/exit JSONL file.

usage: eslog.py ESLOGGER_JSONL BINARY_SUBSTRING [BINARY_SUBSTRING...]
A process life starts at its fork (or its first sighting) and ends at its exit; lives
are matched by pid in time order (pidversion changes across fork/exec). Roots are
lives that exec or run a binary whose path contains a substring; descendants are fork
children of traced lives. Lists lives that never exited within the log.
"""
import json, sys

path, needles = sys.argv[1], sys.argv[2:]
events = []
with open(path, errors='replace') as f:
    for line in f:
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass
events.sort(key=lambda e: e['mach_time'])
live = {}      # pid -> current traced life
lives = []
def start(pid, **kw):
    life = dict(pid=pid, parent=None, path=None, fork=None, exec=None, exit=None, children=0)
    life.update({k: v for k, v in kw.items() if v is not None})
    live[pid] = life
    lives.append(life)
    return life
for e in events:
    p = e['process']; pid = p['audit_token']['pid']; ev = e['event']; t = e['time']
    path_ = p['executable']['path']
    mine = any(n in path_ for n in needles)
    if pid not in live and mine:
        start(pid, path=path_, parent=None)
    if 'fork' in ev and pid in live:
        child = ev['fork']['child']
        live[pid]['children'] += 1
        start(child['audit_token']['pid'], parent=pid, path=child['executable']['path'], fork=t)
    elif 'exec' in ev:
        tpath = ev['exec']['target']['executable']['path']
        if pid in live:
            live[pid]['exec'] = t; live[pid]['path'] = tpath
        elif any(n in tpath for n in needles):
            start(pid, path=tpath, exec=t)
    elif 'exit' in ev and pid in live:
        live[pid]['exit'] = t
        del live[pid]
roots = [l for l in lives if l['parent'] is None]
kids = [l for l in lives if l['parent'] is not None]
print(f'events={len(events)} span={events[0]["time"]} .. {events[-1]["time"]}')
print(f'traced lives={len(lives)} roots={len(roots)} descendants={len(kids)}')
for l in kids:
    print('  child', l['pid'], 'of', l['parent'], (l['path'] or '')[-45:], 'fork', l['fork'][11:23], 'exit', (l['exit'] or 'NONE')[11:23], 'children', l['children'])
open_ = [l for l in lives if l['exit'] is None]
print('without exit:', len(open_))
for l in open_:
    print('  OPEN', l)

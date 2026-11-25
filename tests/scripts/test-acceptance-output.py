"""Regression: workload log files are written only after the child has exited."""
import argparse
import json
from pathlib import Path
import runpy
import subprocess
import unittest.mock as mock
import uuid


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--sigma', required=True, type=Path)
    a = p.parse_args()
    namespace = runpy.run_path('tests/scripts/acceptance-probes.py')
    driver = namespace['run']
    temp = Path('.work')/('acceptance-output-'+uuid.uuid4().hex)
    temp.mkdir(parents=True)
    fixture = temp/'turns.fs'
    fixture.write_text('''REQUIRE-EXTENSION ALSO EXTENSION
CREATE TARGET 4 , 0 , 0 , 0 , 0 , CREATE EVENT 32 ALLOT
: RUN 20000 0 DO TARGET 1 EVENT 1 0 TASK-WAIT-MANY THROW 2DROP LOOP
  ." OUTPUT-DONE" CR ; RUN BYE
''')
    original_open, original_popen = Path.open, subprocess.Popen
    children, writes = [], []

    def spawn(*args, **kwargs):
        assert kwargs['stdout'] == subprocess.PIPE
        assert kwargs['stderr'] == subprocess.STDOUT
        child = original_popen(*args, **kwargs)
        children.append(child)
        return child

    class GuardedLog:
        def __init__(self, file): self.file = file
        def __enter__(self): return self
        def __exit__(self, *args): return self.file.__exit__(*args)
        def write(self, data):
            assert children and children[-1].poll() is not None, 'disk write during child execution'
            writes.append(len(data))
            return self.file.write(data)

    def open_file(path, mode='r', *args, **kwargs):
        file = original_open(path, mode, *args, **kwargs)
        return GuardedLog(file) if mode == 'wb' and path.suffix == '.log' else file

    with mock.patch.object(Path, 'open', open_file), mock.patch.object(subprocess, 'Popen', spawn):
        result = driver(a.sigma.resolve(), fixture.resolve(), temp/'complete', False, buffer_output=True)
        turns = [e for e in result['events'] if e.get('metric') == 'management_turn_ns']
        assert len(turns) == 20000, len(turns)
        assert result['exit_code'] == 0 and writes
        assert all(0 < e['start'] <= e['end'] for e in turns)
        assert all(a['end'] <= b['start'] for a, b in zip(turns, turns[1:]))
        assert result['output_capture_bytes'] == sum(writes)
        driver.__globals__['OUTPUT_CAPTURE_LIMIT'] = 1024
        try:
            driver(a.sigma.resolve(), fixture.resolve(), temp/'overflow', False, buffer_output=True)
        except RuntimeError as exc:
            assert 'output capture failed' in str(exc), exc
        else:
            raise AssertionError('overflow was accepted')
        failed = json.loads((temp/'overflow.json').read_text())
        assert failed['output_capture_error'] and failed['output_capture_bytes'] > 1024
        assert children[-1].returncode == 0, 'overflow must continue draining the pipe'
    print('buffered output: 20000 ordered records; no live disk writes; overflow rejected')


if __name__ == '__main__':
    main()

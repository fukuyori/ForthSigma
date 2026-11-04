#!/usr/bin/env python3
"""Linux tests for the external process-clock benchmark protocol."""

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest


sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("benchmark_runtime", Path(__file__).with_name("benchmark-runtime.py"))
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)


class BenchmarkProtocolTests(unittest.TestCase):
    def child(self, source):
        workspace = Path(__file__).resolve().parent.parent / ".work"
        workspace.mkdir(exist_ok=True)
        temporary = tempfile.TemporaryDirectory(dir=workspace)
        self.addCleanup(temporary.cleanup)
        path = Path(temporary.name) / "child.py"
        path.write_text(source, encoding="utf-8")
        return str(path)

    def test_excludes_startup_teardown_and_sleep_from_execution_cpu(self):
        child = self.child('''import sys, time
def burn(seconds):
    end = time.process_time() + seconds
    while time.process_time() < end:
        pass
burn(0.1)
print("BENCH-READY", flush=True)
assert sys.stdin.read(1) == "x"
time.sleep(0.05)
burn(0.03)
print("BENCH-DONE 7", flush=True)
assert sys.stdin.read(1) == "x"
burn(0.1)
''')
        cpu, checksum, wall, total = benchmark.sample(sys.executable, False, child)
        self.assertEqual(checksum, 7)
        self.assertGreater(cpu, 20_000)
        self.assertGreater(total - cpu, 150_000)
        self.assertGreater(wall - cpu, 30_000)

    def test_unexpected_output_is_rejected_and_waiting_child_is_reaped(self):
        child = self.child('import sys\nprint("BAD", flush=True)\nsys.stdin.read()\n')
        with self.assertRaisesRegex(RuntimeError, "unexpected startup"):
            benchmark.sample(sys.executable, False, child)

    def test_early_exit_is_rejected(self):
        child = self.child('pass\n')
        with self.assertRaisesRegex(RuntimeError, "exited before"):
            benchmark.sample(sys.executable, False, child)


if __name__ == "__main__":
    unittest.main()

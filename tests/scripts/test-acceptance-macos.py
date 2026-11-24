#!/usr/bin/env python3
"""Host-independent macOS parser/ABI/sampler checks. No acceptance measurements."""
import ctypes
from pathlib import Path
import runpy
import struct
import sys
import uuid
import unittest
from unittest.mock import Mock

HERE = Path(__file__).resolve().parent
runner = runpy.run_path(str(HERE / 'run-acceptance.py'))
probes = runpy.run_path(str(HERE / 'acceptance-probes.py'))


def macho(cpu=0x0100000c, section=b'__text', segment=b'__TEXT'):
    data = bytearray(200)
    struct.pack_into('<8I', data, 0, 0xfeedfacf, cpu, 0, 2, 1, 152, 0, 0)
    struct.pack_into('<II16sQQQQIIII', data, 32, 0x19, 152, b'__TEXT', 0, 200, 0, 200, 7, 5, 1, 0)
    struct.pack_into('<16s16sQQIIIIIIII', data, 104, section, segment, 0, 16, 184, 0, 0, 0, 0x80000400, 0, 0, 0)
    return data


class MachOTests(unittest.TestCase):
    def parse(self, data):
        work = HERE.parents[1] / '.work/1383/parser-tests'
        work.mkdir(parents=True, exist_ok=True)
        directory = work / uuid.uuid4().hex
        directory.mkdir()
        path = directory / 'sigma'
        try:
            path.write_bytes(data)
            return runner['text_section'](path)
        finally:
            path.unlink(missing_ok=True)
            directory.rmdir()

    def test_arm64_text(self):
        self.assertEqual(self.parse(macho()), dict(format='Mach-O64-arm64', logical_bytes=16, file_bytes=16))

    def test_reject_fat(self):
        for magic in ('cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca'):
            with self.subTest(magic=magic), self.assertRaisesRegex(ValueError, 'fat'):
                self.parse(bytes.fromhex(magic))

    def test_wrong_cpu_and_section(self):
        for data in (macho(cpu=0x01000007), macho(section=b'__cstring'), macho(segment=b'__DATA')):
            with self.assertRaises(ValueError): self.parse(data)

    def test_truncated(self):
        for length in (4, 31, 40, 183, 199):
            with self.subTest(length=length), self.assertRaises(ValueError): self.parse(macho()[:length])

    def test_bad_commands(self):
        for offset, value in ((20, 999), (36, 0), (36, 151), (96, 2), (16, 2), (148, 999)):
            data = macho()
            struct.pack_into('<I', data, offset, value)
            with self.subTest(offset=offset), self.assertRaises(ValueError): self.parse(data)

    def test_zero_fill_rejected(self):
        data = macho()
        struct.pack_into('<I', data, 168, 1)
        with self.assertRaises(ValueError): self.parse(data)


class RunnerTests(unittest.TestCase):
    def test_plan_selection(self):
        self.assertEqual(runner['acceptance_plan'](platform_name='darwin').name, 'TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md')
        for platform in ('win32', 'linux'):
            self.assertEqual(runner['acceptance_plan'](platform_name=platform).name, 'TASK_CONTROL_ACCEPTANCE_PLAN.md')
        explicit = HERE / 'custom-plan.md'
        self.assertEqual(runner['acceptance_plan'](explicit, 'darwin'), explicit.resolve())

    def test_memory_budget_mapping(self):
        self.assertEqual(runner['memory_metrics']('darwin'), ['process_virtual_bytes', 'process_phys_footprint_bytes', 'process_resident_bytes'])
        self.assertEqual(runner['memory_budget']('process_phys_footprint_bytes'), 128*1024*1024)
        for metric in ('process_virtual_bytes', 'process_resident_bytes'):
            self.assertIsNone(runner['memory_budget'](metric))
        for platform in ('win32', 'linux'):
            self.assertIn('process_committed_bytes', runner['memory_metrics'](platform))


class MemoryTests(unittest.TestCase):
    def test_sdk_layout(self):
        usage, task = probes['RusageInfoV4'], probes['ProcTaskInfo']
        self.assertEqual(ctypes.sizeof(usage), 296)
        self.assertEqual(usage.ri_resident_size.offset, 64)
        self.assertEqual(usage.ri_phys_footprint.offset, 72)
        self.assertEqual(usage.ri_lifetime_max_phys_footprint.offset, 240)
        self.assertEqual(usage.ri_runnable_time.offset, 288)
        self.assertEqual(ctypes.sizeof(task), 96)
        self.assertEqual(task.pti_virtual_size.offset, 0)

    def library(self):
        lib = Mock()
        def rusage(pid, flavor, buffer):
            self.assertEqual((pid, flavor), (123, 4))
            # Write raw bytes at SDK offsets, independently of ctypes fields.
            ctypes.memmove(buffer, bytes(296), 296)
            for at, value in ((64, 111), (72, 222), (240, 333)):
                ctypes.memmove(ctypes.cast(buffer, ctypes.c_void_p).value + at, struct.pack('<Q', value), 8)
            return 0
        def pidinfo(pid, flavor, arg, buffer, size):
            self.assertEqual((pid, flavor, arg, size), (123, 4, 0, 96))
            ctypes.memmove(buffer, struct.pack('<Q', 444), 8)
            return 96
        lib.proc_pid_rusage.side_effect = rusage
        lib.proc_pidinfo.side_effect = pidinfo
        return lib

    def test_decode_and_semantics(self):
        result = probes['darwin_memory'](123, self.library())
        self.assertEqual([result[k] for k in ('process_resident_bytes', 'process_phys_footprint_bytes', 'process_virtual_bytes', 'lifetime_max_phys_footprint_bytes')], [111, 222, 444, 333])
        self.assertNotIn('process_committed_bytes', result)
        self.assertNotIn('process_reserved_bytes', result)

    def test_rusage_failure(self):
        lib = self.library()
        lib.proc_pid_rusage.side_effect = None
        lib.proc_pid_rusage.return_value = -1
        with self.assertRaises(OSError): probes['darwin_memory'](123, lib)
        lib.proc_pidinfo.assert_not_called()

    def test_short_pidinfo(self):
        for size in (0, -1, 8):
            lib = self.library()
            lib.proc_pidinfo.side_effect = None
            lib.proc_pidinfo.return_value = size
            with self.assertRaises(OSError): probes['darwin_memory'](123, lib)


class PipeTests(unittest.TestCase):
    def test_no_terminal_checkpoint_acknowledgement(self):
        # Exercise the same Popen/PIPE/reader/join path on the current host,
        # without starting sigma or collecting acceptance timings.
        work = HERE.parents[1] / '.work/1383/pipe-tests' / uuid.uuid4().hex
        work.mkdir(parents=True)
        source = work / 'child.py'
        source.write_text(
            'import sys\n'
            'print(\'ACCEPTANCE {"clock":"synthetic","monotonic":true,"resolution_ns":1}\', flush=True)\n'
            'for marker in ("BASELINE-READY", "ACCEPTANCE-MEMORY-HOLD"):\n'
            ' print(marker, flush=True)\n'
            ' assert sys.stdin.buffer.read(1) == b"\\n"\n', encoding='utf-8')
        driver = probes['run']
        original = driver.__globals__['memory']
        driver.__globals__['memory'] = lambda pid: dict(process_resident_bytes=1)
        try:
            result = driver(Path(sys.executable), source, work / 'probe', True, memory_hold=True)
        finally:
            driver.__globals__['memory'] = original
        self.assertFalse(result['timed_out'])
        self.assertEqual(result['exit_code'], 0)
        self.assertEqual(result['expected_memory_checkpoints'], 2)
        self.assertEqual(len(result['memory_checkpoints']), 2)
        self.assertEqual(result['os_sample_errors'], [])
        self.assertEqual(result['child_clocks'][0]['clock'], 'synthetic')

    def test_no_terminal_input_and_quit(self):
        work = HERE.parents[1] / '.work/1383/pipe-tests' / uuid.uuid4().hex
        work.mkdir(parents=True)
        source = work / 'response.py'
        source.write_text(
            'import sys\n'
            'print("INPUT-READY", flush=True)\n'
            'while True:\n'
            ' ch = sys.stdin.buffer.read(1)\n'
            ' if ch == b"q": break\n'
            ' if ch == b"b": print("INPUT-APPLIED=98 ", flush=True)\n', encoding='utf-8')
        result = probes['response'](Path(sys.executable), source, work / 'response', True)
        self.assertIsNone(result['error'])
        self.assertEqual(len(result['events']), 1)
        self.assertIsNone(result['events'][0]['value'])


if __name__ == '__main__':
    unittest.main()

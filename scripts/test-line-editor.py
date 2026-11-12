#!/usr/bin/env python3
"""Verify interactive history and editing of Sigma through a POSIX pseudo-terminal."""

import argparse
import os
from pathlib import Path
import select
import signal
import codecs
import unicodedata
import struct
import subprocess
import sys
import time
import unittest

if os.name != 'posix':
    raise SystemExit('This test requires a POSIX pseudo-terminal.')
import fcntl
import pty
import termios

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', required=True, type=Path)
args, remaining = parser.parse_known_args()
SIGMA = str(args.sigma.resolve(strict=True))


def terminal_settings(descriptor):
    settings = termios.tcgetattr(descriptor)
    # macOS sets the transient PENDIN bit even for a Python-only raw -> canonical
    # round trip. Compare the restored settings without this kernel-generated bit.
    settings[3] &= ~getattr(termios, 'PENDIN', 0)
    return settings


class Screen:
    """The cursor movement needed by these tests, including delayed auto-wrap."""
    def __init__(self, columns, reply):
        self.columns = columns if columns >= 2 else 80
        self.row = self.column = 0
        self.pending_wrap = False
        self.escape = None
        self.cells = {}
        self.reply = reply
        self.decoder = codecs.getincrementaldecoder('utf-8')('replace')

    def feed(self, chunk):
        for char in self.decoder.decode(chunk):
            if self.escape is not None:
                self.escape += char
                if len(self.escape) >= 2 and '@' <= char <= '~':
                    if self.escape == '[6n':
                        self.reply(f'\x1b[{self.row + 1};{self.column + 1}R'.encode())
                    self.escape = None
                continue
            if char == '\x1b':
                self.escape = ''
            elif char == '\r':
                self.column = 0
                self.pending_wrap = False
            elif char == '\n':
                self.row += 1
                self.pending_wrap = False
            elif char == '\x08':
                self.column = max(0, self.column - 1)
                self.pending_wrap = False
            elif ord(char) >= 32 and not unicodedata.combining(char):
                width = 2 if unicodedata.east_asian_width(char) in ('W', 'F') else 1
                if self.pending_wrap or self.column + width > self.columns:
                    self.row += 1
                    self.column = 0
                    self.pending_wrap = False
                self.cells[self.row, self.column] = char
                if width == 2:
                    self.cells[self.row, self.column + 1] = ''
                self.column += width
                if self.column == self.columns:
                    self.column -= 1
                    self.pending_wrap = True


    def text(self, row):
        return ''.join(self.cells.get((row, column), ' ') for column in range(self.columns))


def prepare_child():
    # A separate, non-orphaned process group permits a real Ctrl+Z / SIGCONT test.
    os.setpgrp()
    signal.signal(signal.SIGTSTP, signal.SIG_DFL)


class Session:
    def __init__(self, columns=80, answer_cursor=True, stderr=None):
        self.master, self.slave = pty.openpty()
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, columns, 0, 0))
        self.original_settings = terminal_settings(self.slave)
        self.screen = Screen(columns, lambda text: os.write(self.master, text) if answer_cursor else None)
        self.child = subprocess.Popen([SIGMA], stdin=self.slave, stdout=self.slave, stderr=self.slave if stderr is None else stderr,
                                      preexec_fn=prepare_child)
        self.output = bytearray()
        try:
            self.until(b"Type `help' for basic help\r\n")
        except BaseException:
            self.close()
            raise

    def send(self, text):
        os.write(self.master, text.encode('utf-8') if isinstance(text, str) else text)

    def until(self, expected, timeout=5):
        start = len(self.output)
        deadline = time.monotonic() + timeout
        while expected not in self.output[start:]:
            left = deadline - time.monotonic()
            if left <= 0:
                raise AssertionError(f'missing {expected!r}; received {bytes(self.output[start:])!r}')
            ready, _, _ = select.select([self.master], [], [], min(left, 0.1))
            if ready:
                self.read_output()
            elif self.child.poll() is not None:
                raise AssertionError(f'Sigma exited {self.child.returncode}: {bytes(self.output[start:])!r}')
        return bytes(self.output[start:])

    def read_output(self):
        chunk = os.read(self.master, 65536)
        self.output.extend(chunk)
        self.screen.feed(chunk)

    def drain(self):
        while select.select([self.master], [], [], 0.25)[0]:
            self.read_output()

    def resume_after_ctrl_z(self):
        self.send('\x1a')
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            pid, status = os.waitpid(self.child.pid, os.WNOHANG | os.WUNTRACED)
            if pid:
                if not os.WIFSTOPPED(status):
                    raise AssertionError(f'expected a stopped child: {status}')
                os.kill(self.child.pid, signal.SIGCONT)
                return
            select.select([], [], [], 0.01)
        raise AssertionError('Sigma did not suspend')

    def close(self):
        if self.child.poll() is None:
            self.child.kill()
        self.child.wait(timeout=5)
        os.close(self.master)
        os.close(self.slave)


class LineEditorTests(unittest.TestCase):
    def session(self, columns=80, answer_cursor=True, stderr=None):
        session = Session(columns, answer_cursor, stderr)
        self.addCleanup(session.close)
        return session

    def test_history_reexecution_editing_and_draft_restore(self):
        s = self.session()
        s.send('40 2 + .\r')
        s.until(b'\r\n42  OK\r\n')
        s.send('\x1b[A\r')
        s.until(b'\r\n42  OK\r\n')
        s.send('\x1b[A\x1b[H\x1b[3~\x1b[3~41\x1b[F\r')
        s.until(b'\r\n43  OK\r\n')
        s.send('5 .\x1b[A\x1b[B\r')
        s.until(b'\r\n5  OK\r\n')
        s.send('BYE\r')
        self.assertEqual(s.child.wait(timeout=5), 0)
        self.assertEqual(terminal_settings(s.slave), s.original_settings)

    def test_japanese_insertion_and_delete_with_complete_utf8_output(self):
        s = self.session()
        s.send('." 日語"\x1b[D\x1b[D\x1b[3~本\x1b[F\r')
        s.until('\r\n日本 OK\r\n'.encode('utf-8'))
        bytes(s.output).decode('utf-8', errors='strict')
        s.send('BYE\r')
        self.assertEqual(s.child.wait(timeout=5), 0)

    def test_long_line_and_eof_restore_terminal_settings(self):
        s = self.session(columns=12)
        s.send(' ' * 80 + '41 .\x1b[H \x1b[F\r')
        s.until(b'\r\n41  OK\r\n')
        s.send('\x04')
        self.assertEqual(s.child.wait(timeout=5), 0)
        self.assertEqual(terminal_settings(s.slave), s.original_settings)

    def test_accept_has_editing_but_does_not_replace_command_history(self):
        s = self.session()
        s.send('." ASK " PAD 20 ACCEPT PAD SWAP TYPE CR\r')
        s.until(b'\r\nASK ')
        s.send('ab\x1b[DX\r')
        s.until(b'\r\naXb\r\n OK\r\n')
        s.send('\x1b[A\r')
        s.until(b'\r\nASK ')
        s.send('ok\r')
        s.until(b'\r\nok\r\n OK\r\n')
        s.send('BYE\r')
        self.assertEqual(s.child.wait(timeout=5), 0)

    def test_a_new_process_starts_with_empty_history(self):
        s = self.session()
        s.send('\x1b[A7 .\r')
        s.until(b'\r\n7  OK\r\n')
        s.send('BYE\r')
        self.assertEqual(s.child.wait(timeout=5), 0)

    def test_suspend_redraw_streams_all_bytes_and_restores_cursor(self):
        s = self.session(columns=200)
        s.send('a' * 150 + '\x1b[H')
        s.drain()
        s.resume_after_ctrl_z()
        s.until(b'\r\n' + b'a' * 150 + b'\x08' * 150)
        self.assertEqual(s.screen.column, 0)
        s.send('\x15BYE\r')
        self.assertEqual(s.child.wait(timeout=5), 0)

    def test_unset_terminal_width_uses_a_bounded_viewport(self):
        s = self.session(columns=0)
        row = s.screen.row
        s.send(' ' * 100 + '7 .')
        s.drain()
        self.assertEqual(s.screen.row, row)
        s.send('\r')
        s.until(b'\r\n7  OK\r\n')
        s.send('BYE\r')
        self.assertEqual(s.child.wait(timeout=5), 0)

    def test_compilation_prompt_reserves_its_starting_column(self):
        s = self.session(columns=12)
        s.send(': X .( hi)\r')
        s.until(b'\r\nhi')
        row = s.screen.row
        s.send(' ' * 20 + ';')
        s.drain()
        self.assertEqual(s.screen.row, row)
        s.send('\r')
        s.until(b' OK\r\n')
        s.send('BYE\r')
        self.assertEqual(s.child.wait(timeout=5), 0)

    def test_accept_with_prompt_scrolls_without_wrapping(self):
        s = self.session(columns=12)
        s.send('." ASK " PAD 60 ACCEPT PAD SWAP TYPE CR\r')
        s.until(b'\r\nASK ')
        row = s.screen.row
        s.send('a' * 40 + '\x1b[DX')
        s.drain()
        self.assertEqual(s.screen.row, row)
        s.send('\r')
        s.until(b'\r\n' + b'a' * 39 + b'Xa\r\n OK\r\n')
        s.send('BYE\r')
        self.assertEqual(s.child.wait(timeout=5), 0)

    def test_large_paste_is_preserved(self):
        s = self.session(answer_cursor=False)
        s.send(' ' * 320 + '42 .\r')
        s.until(b'\r\n42  OK\r\n')
        s.send('BYE\r')
        self.assertEqual(s.child.wait(timeout=5), 0)

    def test_typeahead_reaches_key_query_and_key_in_order(self):
        s = self.session(answer_cursor=False)
        s.send('KEY? . KEY .\rZ\n')
        s.until(b'\r\n-1 90  OK\r\n')
        s.send('BYE\r')
        self.assertEqual(s.child.wait(timeout=5), 0)

    def test_multi_line_paste_keeps_prompt_origin(self):
        for spaces in (29, 300):
            with self.subTest(spaces=spaces):
                s = self.session()
                s.drain()  # Start injecting both lines after the editor is ready.
                s.send('1 .\r' + ' ' * spaces + '\r')
                s.until(b'\r\n1  OK\r\n')
                s.drain()
                s.send('." ASK " PAD 20 ACCEPT PAD SWAP TYPE CR\r')
                s.until(b'\r\nASK ')
                s.drain()
                self.assertEqual(s.screen.column, 4)
                s.send('ok\r')
                s.until(b'\r\nok\r\n OK\r\n')
                s.send('BYE\r')
                self.assertEqual(s.child.wait(timeout=5), 0)

    def test_large_paste_cannot_corrupt_prompted_accept_origin(self):
        s = self.session(columns=12)
        s.drain()
        s.send('1 .\r' + ' ' * 300 + '." ASK " PAD 60 ACCEPT PAD SWAP TYPE CR\r')
        s.until(b'\r\nASK ')
        s.drain()
        row = s.screen.row
        s.send('a' * 40 + '\x1b[DX')
        s.drain()
        self.assertEqual(s.screen.row, row)
        self.assertEqual(s.screen.text(row)[:4], 'ASK ')
        self.assertNotIn(b'\x1b[6n', s.output)
        s.send('\r')
        s.until(b'\r\n' + b'a' * 39 + b'Xa\r\n OK\r\n')
        s.send('BYE\r')
        self.assertEqual(s.child.wait(timeout=5), 0)

    def test_backtrace_does_not_insert_an_extra_blank_input_row(self):
        s = self.session()
        s.send(': T 1 0 / ; T\r')
        s.until(b'BACKTRACE:')
        s.drain()
        self.assertFalse(s.output.endswith(b'\r\n\r\n'), repr(bytes(s.output[-160:])))
        s.send('BYE\r')
        self.assertEqual(s.child.wait(timeout=5), 0)

    def test_redirected_or_separate_stderr_does_not_move_the_prompt(self):
        other_master, other_slave = pty.openpty()
        self.addCleanup(os.close, other_master)
        self.addCleanup(os.close, other_slave)
        for target in (subprocess.DEVNULL, other_slave):
            with self.subTest(target=target):
                s = self.session(columns=12, stderr=target)
                s.send('." ASK " S" hidden" STDERR WRITE-FILE THROW PAD 20 ACCEPT PAD SWAP TYPE CR\r')
                s.until(b'\r\nASK ')
                s.drain()
                self.assertEqual(s.screen.column, 4)
                s.send('ok\r')
                s.until(b'\r\nok\r\n OK\r\n')
                s.send('BYE\r')
                self.assertEqual(s.child.wait(timeout=5), 0)

    def test_stderr_prompt_on_the_same_terminal_is_tracked(self):
        s = self.session(columns=12)
        s.send('S" ASK " STDERR WRITE-FILE THROW PAD 60 ACCEPT PAD SWAP TYPE CR\r')
        s.until(b'\r\nASK ')
        s.drain()
        row = s.screen.row
        s.send('a' * 40)
        s.drain()
        self.assertEqual(s.screen.row, row)
        self.assertEqual(s.screen.text(row)[:4], 'ASK ')
        s.send('\r')
        s.until(b'\r\n' + b'a' * 40 + b'\r\n OK\r\n')
        s.send('BYE\r')
        self.assertEqual(s.child.wait(timeout=5), 0)

    def test_prompt_leaves_room_for_a_full_width_character(self):
        s = self.session(columns=12)
        s.send('." 123456789 " PAD 20 ACCEPT PAD SWAP TYPE CR\r')
        s.until(b'\r\n123456789 ')
        s.drain()
        self.assertEqual(s.screen.column, 0)
        s.send('日本')
        s.drain()
        self.assertTrue(s.screen.text(s.screen.row).startswith('日本'))
        s.send('\r')
        s.until('\r\n日本\r\n OK\r\n'.encode())
        s.send('BYE\r')
        self.assertEqual(s.child.wait(timeout=5), 0)

    def test_pipe_input_has_no_editor_echo(self):
        r = subprocess.run([SIGMA], input=b'40 2 + .\nBYE\n', capture_output=True, timeout=5)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(b'42  OK\n', r.stdout)
        self.assertNotIn(b'40 2 + .', r.stdout)
        self.assertNotIn(b'\x08', r.stdout)
        self.assertNotIn(b'\x1b', r.stdout)


if __name__ == '__main__':
    unittest.main(argv=[sys.argv[0], *remaining])

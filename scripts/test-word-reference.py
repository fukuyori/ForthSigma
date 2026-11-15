"""Regression checks for reviewed word-description and example-selection failures."""
import argparse
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
import sys

sys.dont_write_bytecode = True
from word_reference_examples import InputState

ROOT = Path(__file__).resolve().parent.parent


class ExampleSelection(unittest.TestCase):
    def test_parsed_text_is_not_a_call(self):
        refs, complete = InputState().scan('CHAR ? ( K | ) S" ST ROOT"')
        self.assertTrue(complete)
        self.assertTrue({'CHAR', '(', 'S"'} <= refs)
        self.assertFalse({'?', ')', 'K', '|', 'ST', 'ROOT'} & refs)

    def test_shadowing_and_locals(self):
        state = InputState()
        refs, complete = state.scan(': K 42 ; K 2 CONSTANT ST ST : X { ROOT -- } ROOT ;')
        self.assertTrue(complete)
        self.assertFalse({'K', 'ST', 'ROOT'} & refs)
        self.assertNotIn('K', state.scan('K')[0])
        refs, complete = InputState().scan('SPRITE: ST ST TILEMAP: ROOT ROOT PALETTE: K K INDEXED: P P')
        self.assertTrue(complete)
        self.assertFalse({'ST', 'ROOT', 'K', 'P'} & refs)

    def test_local_prefix_is_a_form(self):
        refs, complete = InputState().scan(': X { XT: action | W: scratch -- } action scratch ;')
        self.assertTrue(complete)
        self.assertTrue({'XT:', 'W:', '|', '--', '}'} <= refs)
        self.assertFalse({'ACTION', 'SCRATCH'} & refs)

    def test_incomplete_definition_is_not_a_complete_example(self):
        self.assertFalse(InputState().scan(': X DUP')[1])

    def test_fingerprints_include_stack_flags_and_body(self):
        spec = importlib.util.spec_from_file_location('reference', ROOT / 'scripts/word-reference.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        e = dict(namespace='FORTH', name='X', text='example', stack='( -- )', compile_only=False)
        baseline = module.translation_sources([e], ['X'])['translations']['X']
        for field, value in [('stack', '( -- x )'), ('compile_only', True), ('definition', ': X 1 ;')]:
            self.assertNotEqual(baseline, module.translation_sources([{**e, field: value}], ['X'])['translations']['X'])


def runtime_checks(sigma):
    sigma = str(sigma.resolve())
    count = 0

    def check(source, expected, cwd=ROOT, status=0):
        nonlocal count
        r = subprocess.run([sigma, '-e', source + '\nBYE'], input='', capture_output=True,
                           text=True, encoding='utf-8', timeout=15, cwd=cwd)
        assert r.returncode == status and not r.stderr.strip(), (source, r.returncode, r.stderr)
        assert r.stdout.split() == expected.split(), (source, expected, r.stdout)
        count += 1

    check('1 10 100 UNDER+ .S', '<2> 101 10')
    check('KEY-IOR DEPTH . .', '1 -512')
    check("VARIABLE HIT : TARGET 1 HIT +! 99 ; : RUN-XT { XT: action -- } action ; ' TARGET RUN-XT HIT @ . .", '1 99')
    check(": GET-XT { XT^ action -- } action @ ; ' DUP GET-XT ' DUP = .", '-1')
    check('1 MAXDEPTH-.S ! 10 20 30 .S', '<3> 30')
    check('1 MAXDEPTH-.S ! 3 TO F.S-PRECISION 1e 2e 3e F.S', '<3> 3E0')
    check('1e 0e F/ FS. ." X"', 'infinityX')
    check('1e 0e F/ FE. ." X"', 'infinityX')
    check('1e 0e F/ FP. ." X"', 'infinity X')
    check('1e 0e F/ F. ." X"', 'infinity X')
    check('VARIABLE P P CLEAR-PATH S" VERSION" P OPEN-PATH-FILE .', '-37')
    check('VARIABLE P P CLEAR-PATH S" ./VERSION" P OPEN-PATH-FILE . 2DROP CLOSE-FILE .', '0 0')
    check('REQUIRE-AUDIO ALSO AUDIO ST .', '2')
    check(': ZERO { | a b -- } a . b . ; ZERO', '0 0')
    (ROOT / '.work').mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='word-reference-', dir=ROOT / '.work') as folder:
        folder = Path(folder)
        (folder / 'tail.csv').write_bytes(b'a,b,\nx,,\n\n')
        check(': REVIEW-CSV-FIELD { addr u col row -- } row . col . u . ; S" tail.csv" \' REVIEW-CSV-FIELD READ-CSV',
              '1 0 1 1 1 1 2 0 1 2 1 0 3 0 0', folder)
        block = b'SOURCE-ID . SAVE-INPUT 2 = . 2DROP SOURCE NIP . BYE'
        (folder / 'blocks.fb').write_bytes(b' ' * 1024 + block.ljust(1024, b' ') + b' ' * 1024)
        check('1 LOAD', '2 -1 1024', folder)
        block = b': NEXT-BLOCK REFILL . SOURCE NIP . BYE ; NEXT-BLOCK'
        (folder / 'blocks.fb').write_bytes(b' ' * 1024 + block.ljust(1024, b' ') + b' ' * 1024)
        check('1 LOAD', '-1 1024', folder)
        block = b'( comment'.ljust(64, b' ') + b'continued ) 42 . BYE'
        (folder / 'blocks.fb').write_bytes(b' ' * 1024 + block.ljust(1024, b' '))
        check('1 LOAD', '42', folder)
        (folder / 'target.txt').write_text('fixture', encoding='utf-8')
        (folder / 'source.fs').write_text('VARIABLE P P CLEAR-PATH S" ./target.txt" P OPEN-PATH-FILE . 2DROP CLOSE-FILE .', encoding='utf-8')
        check('S" ' + (folder / 'source.fs').as_posix() + '" INCLUDED', '0 0')
    print('Behavior regressions: %d passed' % count)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--sigma', type=Path)
    args = parser.parse_args()
    result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(ExampleSelection))
    if not result.wasSuccessful():
        raise SystemExit(1)
    if args.sigma:
        runtime_checks(args.sigma)

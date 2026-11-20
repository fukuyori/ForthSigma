#!/usr/bin/env python3
"""Check audio loading with an executed parser word, without opening audio."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

PCM_WORDS = ['PCM-' + name for name in ['OPEN', 'WRITE', 'QUEUED', 'WAIT', 'STOP', 'CLOSE', 'UNDERRUNS']]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sigma', type=Path)
    parser.add_argument('--audio', choices=['enabled', 'disabled'], required=True)
    args = parser.parse_args()
    binary = args.sigma.resolve()
    # REQUIRE-AUDIO is a parsing word. EVALUATE runs it inside CATCH rather
    # than trying to compile it into PROBE. FIND-NAME checks the actual order.
    common = ': PROBE S" REQUIRE-AUDIO" EVALUATE ; \' PROBE CATCH . '
    lookups = ' '.join(f'S" {name}" FIND-NAME 0<> .' for name in PCM_WORDS + ['SND-' + name for name in PCM_WORDS])
    if args.audio == 'enabled':
        source = common + 'ALSO AUDIO ' + lookups + ' DEPTH . BYE'
        expected = ['0'] + ['-1'] * 14 + ['0']
    else:
        source = common + 'S" AUDIO" FIND-NAME 0<> . ' + lookups + ' DEPTH . BYE'
        expected = ['-275'] + ['0'] * 16
    result = subprocess.run([str(binary), '-e', source], capture_output=True,
                            text=True, encoding='utf-8', timeout=15)
    if result.returncode or result.stderr or result.stdout.split() != expected:
        raise RuntimeError((result.returncode, result.stdout, result.stderr, expected))
    print(json.dumps({'binary': str(binary), 'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
                      'audio': args.audio, 'source': source, 'expected': expected,
                      'exit': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}, indent=2))


if __name__ == '__main__':
    main()

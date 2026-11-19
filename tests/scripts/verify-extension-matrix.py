#!/usr/bin/env python3
"""Run the three optional groups in all eight combinations on the native host.

Also test files/debug exclusions and reject an extension image in an excluded build.
All artifacts and logs stay under .work/extension-matrix; no packaging is performed.
"""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import platform
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zig', default='zig')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    folder = root / '.work/extension-matrix'
    folder.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256()
    for path in [root / 'build.zig', *sorted((root / 'src').rglob('*'))]:
        if path.is_file():
            digest.update(path.relative_to(root).as_posix().encode() + b'\0' + path.read_bytes())
    report = {'complete': False, 'host': platform.platform(),
              'zig': subprocess.check_output([args.zig, 'version'], cwd=root, text=True).strip(),
              'source_sha256': digest.hexdigest(), 'configurations': []}

    def save():
        (folder / 'matrix.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')

    def command(argv, log):
        result = subprocess.run(argv, cwd=root, capture_output=True, timeout=600)
        log.write_bytes(result.stdout + result.stderr)
        assert result.returncode == 0, (argv, str(log), result.returncode)
        return result

    def evaluate(exe, name, source, expected):
        result = subprocess.run([str(exe), '-e', source + ' BYE'], cwd=folder,
                                input=b'', capture_output=True, timeout=30)
        assert result.returncode == 0 and result.stdout == expected, (
            name, result.returncode, result.stdout, result.stderr, expected)

    save()
    binaries = {}
    configs = [(bits, {}) for bits in itertools.product((False, True), repeat=3)]
    configs += [((False, False, True), {'files': False}),
                ((False, False, True), {'debug': False}),
                ((True, True, True), {'files': False, 'debug': False}),
                ((False, False, True), {'files': False, 'debug': False,
                                        'float': False, 'image': False, 'x11': False})]
    for bits, extras in configs:
        features = dict(zip(('audio', 'graphics', 'extension'), bits)) | extras
        label = ''.join(str(int(b)) for b in bits) + ''.join('-no-' + k for k in extras)
        flags = [f'-D{k}={str(v).lower()}' for k, v in features.items()]
        prefix = folder / label
        command([args.zig, 'build', 'test', *flags, '--summary', 'all'], folder / (label + '-test.log'))
        command([args.zig, 'build', *flags, '--prefix', str(prefix), '--summary', 'all'], folder / (label + '-build.log'))
        exe = prefix / 'bin' / ('sigma.exe' if platform.system() == 'Windows' else 'sigma')
        binaries[label] = exe
        checks = []
        for group, vocabulary, word, error in [('audio', 'AUDIO', 'SND-PLAY', -275),
                                               ('graphics', 'GRAPHICS', 'GFX-INIT', -270),
                                               ('extension', 'EXTENSION', 'HOST-OS', -13)]:
            if features[group]:
                source = f'REQUIRE-{group.upper()} ALSO {vocabulary} [DEFINED] {word} . PREVIOUS'
                expected = b'-1 '
            else:
                source = f': TRY-W S" REQUIRE-{group.upper()}" EVALUATE ; \' TRY-W CATCH . [DEFINED] {vocabulary} .'
                expected = f'{error} 0 '.encode()
            evaluate(exe, label + ':' + group, source, expected)
            checks.append(group)
        if features['extension']:
            os_name = {'Windows': 'windows', 'Linux': 'linux', 'Darwin': 'macos'}.get(platform.system(), 'unknown')
            evaluate(exe, label + ':os', 'REQUIRE-EXTENSION ALSO EXTENSION HOST-OS TYPE PREVIOUS', os_name.encode())
            evaluate(exe, label + ':reload',
                     'MARKER BACK-W REQUIRE-EXTENSION BACK-W [DEFINED] EXTENSION . REQUIRE-EXTENSION ALSO EXTENSION [DEFINED] HOST-OS . PREVIOUS', b'0 -1 ')
            checks += ['os', 'marker-reload']
        report['configurations'].append({'name': label, 'features': features, 'tests': True, 'build': True, 'checks': checks})
        save()
        print(label + ': passed', flush=True)
    # With matching base dictionaries, only the extension's appended builtin differs.
    image = folder / 'extension.sigma'
    evaluate(binaries['001'], 'image-save', 'REQUIRE-EXTENSION SAVE extension.sigma', b'')
    evaluate(binaries['000'], 'image-excluded',
             ': KEPT-W 42 ; : LOAD-W S" LOAD-DICTIONARY extension.sigma" EVALUATE ; \' LOAD-W CATCH 0<> . KEPT-W . [DEFINED] EXTENSION .', b'-1 42 0 ')
    assert image.exists()
    report['excluded_image_rejected_atomically'] = True
    report['complete'] = True
    save()
    print(f'{len(configs)} configurations passed; excluded extension image rejected', flush=True)


if __name__ == '__main__':
    main()

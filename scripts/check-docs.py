#!/usr/bin/env python3
"""Checks the documents against the source. Run it from anywhere:

    python scripts/check-docs.py [BASE]

BASE is the commit to compare with, the latest tag when it is not given. The
checks:

  1. Each built-in word added since BASE has a HELP text and is in
     docs/COMPATIBILITY.md and docs/COMPATIBILITY.ja.md.
  2. Each command-line option added since BASE is in docs/USER_MANUAL.md,
     docs/USER_MANUAL.ja.md, and CHANGELOG.md.
  3. Each document with a Japanese version (*.ja.md) has the same headings,
     the same number of table rows, and the same number of code fences in both.
  4. Each file with the version of VERSION is named in
     docs/version-update-checklist.md, and no start-up line or start event of
     the log in a document shows another version.
  5. Each built-in word, whenever it was added, is in docs/USER_MANUAL.md and
     docs/USER_MANUAL.ja.md, and in the table of registered words of each;
     that table has no word that is not a built-in word.

The exit status is 1 when something is found, 0 otherwise.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
findings = []


def read(path):
    with open(os.path.join(ROOT, path), encoding='utf-8') as file:
        return file.read()


def git(*arguments):
    result = subprocess.run(['git', '-C', ROOT] + list(arguments), capture_output=True)
    if result.returncode != 0:
        sys.exit('git %s: %s' % (' '.join(arguments), result.stderr.decode('utf-8', 'replace').strip()))
    return result.stdout.decode('utf-8', 'replace')


def found(text):
    findings.append(text)
    print('  ' + text)


def word_names(source):
    names = re.findall(r'\.\{ "((?:[^"\\]|\\.)+)", \.[a-z_0-9]+ \}', source)
    return set(name.replace('\\"', '"').replace('\\\\', '\\') for name in names)


def option_names(source):
    return set(re.findall(r'"(--[a-z][a-z-]*)"', source))


def mentions(text, token):
    # The token, followed by a blank or by punctuation that ends a name in a list.
    return re.search(re.escape(token) + r'(?=[\s`,;|=)、。；）]|$)', text) is not None


base = sys.argv[1] if len(sys.argv) > 1 else git('describe', '--tags', '--abbrev=0').strip()
print('compared with %s' % base)

# 1. The built-in words.
words = sorted(word_names(read('src/forth.zig')) - word_names(git('show', base + ':src/forth.zig')))
print('built-in words added: %d' % len(words))
help_text = read('src/core/help_text.zig')
compatibility = ['docs/COMPATIBILITY.md', 'docs/COMPATIBILITY.ja.md']
for word in words:
    quoted = word.replace('\\', '\\\\').replace('"', '\\"')
    if ('.name = "%s"' % quoted) not in help_text:
        found('%s has no HELP text' % word)
    for document in compatibility:
        if not mentions(read(document), word):
            found('%s is not in %s' % (word, document))

# 2. The options.
options = sorted(option_names(read('src/main.zig')) - option_names(git('show', base + ':src/main.zig')))
print('options added: %d' % len(options))
for option in options:
    for document in ['docs/USER_MANUAL.md', 'docs/USER_MANUAL.ja.md', 'CHANGELOG.md']:
        if not mentions(read(document), option):
            found('%s is not in %s' % (option, document))

# 3. The two languages.
japanese = [path for path in git('ls-files', '*.ja.md').split('\n') if path]
print('documents with a Japanese version: %d' % len(japanese))
for path in japanese:
    english = path[:-len('.ja.md')] + '.md'
    if not os.path.exists(os.path.join(ROOT, english)):
        found('%s has no %s' % (path, english))
        continue
    a, b = read(english), read(path)
    for what, pattern in [('headings', r'^(#+) '), ('table rows', r'^\|'), ('code fences', r'^\s*```')]:
        in_a, in_b = re.findall(pattern, a, re.M), re.findall(pattern, b, re.M)
        if in_a != in_b:
            found('%s and %s differ in their %s (%d and %d)' % (english, path, what, len(in_a), len(in_b)))

# 4. The version.
version = read('VERSION').strip()
checklist = read('docs/version-update-checklist.md')
print('version: %s' % version)
with_version = [path for path in git('grep', '-l', '-F', version, '--', '.').split('\n') if path]
for path in with_version:
    if path == 'docs/version-update-checklist.md':
        continue
    if ('`%s`' % path) not in checklist:
        found('%s has %s and is not in docs/version-update-checklist.md' % (path, version))
shown = re.compile(r'FORTH/Sigma (\d+\.\d+\.\d+)  MIT License|"event":"start","version":"(\d+\.\d+\.\d+)"')
for path in git('ls-files', 'README*.md', 'docs/USER_MANUAL*.md', 'docs/DEBUGGING*.md', 'src/core/debug_log.zig').split('\n'):
    if not path:
        continue
    for number, line in enumerate(read(path).split('\n'), 1):
        for match in shown.finditer(line):
            other = match.group(1) or match.group(2)
            if other != version:
                found('%s:%d shows %s' % (path, number, other))

# 5. The user manual has every built-in word.
every = sorted(word_names(read('src/forth.zig')))
print('built-in words: %d' % len(every))
for document, heading in [('docs/USER_MANUAL.md', '\n## Registered words'), ('docs/USER_MANUAL.ja.md', '\n## 登録済みワード一覧')]:
    manual = read(document)
    if heading not in manual:
        found('%s has no section%s' % (document, heading.replace('\n', ' ')))
        continue
    # The table of registered words: the rows up to the next heading, which is
    # that of the forms that are not words of the dictionary (TO, IS, S" ...).
    start = manual.index(heading)
    end = manual.find('\n#', start + len(heading))
    rows = [line for line in manual[start:end if end >= 0 else len(manual)].split('\n') if line.startswith('|')]
    registered = set(re.findall(r'`([^`]+)`', '\n'.join(rows[2:])))
    for word in every:
        if not mentions(manual, word):
            found('%s is not in %s' % (word, document))
        elif word not in registered:
            found('%s is not in the registered words of %s' % (word, document))
    for word in sorted(registered - set(every)):
        found('%s is in the registered words of %s and is not a built-in word' % (word, document))

print('findings: %d' % len(findings))
sys.exit(1 if findings else 0)

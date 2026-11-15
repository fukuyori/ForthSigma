"""Select Forth call sites, excluding parsed text and shadowed dictionary names.

This reads literal interpreter inputs and embedded Forth, not arbitrary quoted
strings. Excerpts keep their test context and expected-error classification.
"""
import json
from pathlib import Path
import re

STRING = r'"(?:[^"\\]|\\.)*"'
DEFINERS = set('VARIABLE VAR 2VARIABLE FVARIABLE AVARIABLE CREATE CONSTANT CONST 2CONSTANT FCONSTANT VALUE 2VALUE FVALUE $VALUE MACRO: DEFER VOCABULARY CS-VOCABULARY MARKER ARRAY FARRAY BUFFER: $VARIABLE $[]VARIABLE BEGIN-STRUCTURE END-STRUCT FIELD: CFIELD: FFIELD: SFFIELD: DFFIELD: WFIELD: LFIELD: XFIELD: 2FIELD: FIELD +FIELD ACONSTANT AVALUE ALIAS REPLACER: FORWARD EXCEPTIONS'.split())
PREFIXES = set('W: W^ D: D^ F: F^ C: C^ XT: XT^'.split())
DEFINERS.update(('SPRITE:', 'TILEMAP:', 'PALETTE:', 'INDEXED:'))
PARSED_NAMES = set('CHAR [CHAR] HELP TO IS +TO ACTION-OF ADDR PRESERVE'.split())


class InputState:
    def __init__(self, canonical=()):
        self.defined = set()
        self.canonical = set(canonical)
        self.locals = set()
        self.compiling = False
        self.quotation = 0

    def scan(self, source):
        refs = set()
        started_inside = self.compiling or self.quotation > 0
        cursor = 0
        expect_name = False
        skip_name = False
        locals_end = None
        local_comment = False
        noname = False
        while cursor < len(source):
            match = re.search(r'\S+', source[cursor:])
            if not match:
                break
            start, end = cursor + match.start(), cursor + match.end()
            token = source[start:end]
            upper = token.upper()
            cursor = end
            if expect_name:
                if upper not in self.canonical:
                    self.defined.add(upper)
                expect_name = False
                continue
            if skip_name:
                skip_name = False
                continue
            if token == '(':
                refs.add('(')
                close = source.find(')', cursor)
                cursor = close + 1 if close >= 0 else len(source)
                continue
            if token == '\\':
                refs.add('\\')
                close = source.find('\n', cursor)
                cursor = close + 1 if close >= 0 else len(source)
                continue
            if locals_end:
                if upper == locals_end:
                    refs.add(upper)
                    locals_end = None
                    local_comment = False
                elif not local_comment:
                    if upper == '--':
                        refs.add('--')
                        local_comment = True
                    elif upper == '|':
                        refs.add('|')
                    elif upper in PREFIXES:
                        refs.add(upper)
                    else:
                        self.locals.add(upper)
                continue
            string_form = upper in ('S"', 'C"', 'ABORT"', 'S\\"', '.\\"', '"', '."') or token.startswith('."')
            if string_form or token == '.(':
                form = '."' if token.startswith('."') else upper
                refs.add(form)
                quote = ')' if token == '.(' else '"'
                cursor = start + len(form)
                escaped = '\\' in form
                while cursor < len(source):
                    if escaped and source[cursor] == '\\':
                        cursor += 2
                    elif source[cursor] == quote:
                        cursor += 1
                        break
                    else:
                        cursor += 1
                continue
            if upper in self.locals or upper in self.defined:
                continue
            refs.add(upper)
            if upper in ('{', '{:', 'LOCALS|'):
                locals_end = {'{': '}', '{:': ':}', 'LOCALS|': '|'}[upper]
            elif upper == 'NONAME':
                noname = True
            elif upper in (':', ':NONAME', ':IS'):
                self.compiling = True
                self.locals = set()
                if upper == ':':
                    expect_name = not noname
                elif upper == ':IS':
                    skip_name = True
                noname = False
            elif upper == ';':
                self.compiling = False
                self.locals = set()
            elif upper == '[:':
                self.quotation += 1
            elif upper == ';]':
                self.quotation = max(0, self.quotation - 1)
            elif upper in DEFINERS and not self.compiling:
                expect_name = not noname
                noname = False
            elif upper in PARSED_NAMES:
                skip_name = True
            elif upper == 'SYNONYM' and not self.compiling:
                expect_name = True
        complete = not (started_inside or self.compiling or self.quotation or locals_end or expect_name or skip_name)
        return refs, complete


def collect_examples(root, entries):
    wanted = {e['name'].upper() for e in entries}
    result = {}
    paths = list(sorted((root / 'src/tests').glob('*.zig'))) + list(sorted((root / 'src/graphics').glob('*.fs'))) + list(sorted((root / 'src/audio').glob('*.fs')))
    for path in paths:
        relative = path.relative_to(root).as_posix()
        lines = path.read_text(encoding='utf-8').splitlines()
        state = InputState(wanted if path.suffix == '.fs' else ())
        test_start = 0
        context = ''
        i = 0
        while i < len(lines):
            line = lines[i]
            if path.suffix == '.zig' and re.match(r'^test ', line):
                state = InputState()
                test_start = i
                end = next((j for j in range(i + 1, len(lines)) if re.match(r'^test ', lines[j])), len(lines))
                context = '\n'.join(lines[i:end]).upper()
            number = i + 1
            snippets = []
            if path.suffix == '.fs':
                # Read a complete colon definition, preserving comments for the lexer.
                if line.lstrip().startswith(': '):
                    gathered = [line]
                    while not re.search(r'(?<!\S);(?=\s|$)', '\n'.join(gathered)) and i + 1 < len(lines):
                        i += 1
                        gathered.append(lines[i])
                    snippets = ['\n'.join(gathered)]
                else:
                    snippets = [line]
            elif 'interpretLine(' in line or 'expectOutput(' in line:
                marker = 'interpretLine(' if 'interpretLine(' in line else 'expectOutput('
                tail = line.split(marker, 1)[1]
                rest = tail + '\n' + '\n'.join(lines[i + 1:i + 60])
                position = 0
                pieces = []
                while True:
                    match = re.match(r'\s*(' + STRING + ')', rest[position:])
                    if not match:
                        break
                    try:
                        pieces.append(json.loads(match.group(1)))
                    except ValueError:
                        pieces = []
                        break
                    position += match.end()
                    concat = re.match(r'\s*\+\+', rest[position:])
                    if concat:
                        position += concat.end()
                        continue
                    if re.match(r'\s*[,)]', rest[position:]):
                        snippets = [''.join(pieces)]
                    break
                if not snippets and not tail.strip():
                    gathered = []
                    j = i + 1
                    while j < len(lines) and lines[j].lstrip().startswith('\\\\'):
                        gathered.append(lines[j].lstrip()[2:])
                        j += 1
                    if gathered:
                        snippets = ['\n'.join(gathered)]
                        i = j - 1
            error = path.suffix == '.zig' and 'expectError' in '\n'.join(lines[max(test_start, number - 4):number])
            for snippet in snippets:
                if not snippet.strip() or '{s}' in snippet:
                    continue
                active = InputState() if path.suffix == '.zig' and 'expectOutput(' in line else state
                refs, complete = active.scan(snippet)
                if not complete or len(snippet) > 1800:
                    continue
                for e in entries:
                    if e['name'].upper() not in refs:
                        continue
                    ns = e['namespace']
                    if ns in ('FORTH', 'Root', 'Syntax'):
                        if path.suffix != '.zig' or 'help_test' in path.name:
                            continue
                    elif ns == 'EKEYS':
                        continue
                    elif path.suffix == '.zig':
                        group = ns.lower()
                        if group not in path.name and 'REQUIRE-' + ns not in context:
                            continue
                    elif ns == 'AUDIO' and 'audio' not in relative:
                        continue
                    elif ns == 'GUI' and path.name != 'gui.fs':
                        continue
                    elif ns == 'GAME' and path.name != 'game.fs':
                        continue
                    navigation = e['name'] in {'B','L','N','G','GG','LL','WW','NW','BW','TT','NT','BT','BROWSE','EDIT','WHEREG'}
                    score = (error, 0 if navigation and path.name == 'p09b_test.zig' else 1, path.suffix != '.zig', len(snippet))
                    key = (ns, e['name'])
                    if key not in result or score < result[key][0]:
                        result[key] = (score, snippet, relative, number, 'error' if error else 'context')
            i += 1
    return result

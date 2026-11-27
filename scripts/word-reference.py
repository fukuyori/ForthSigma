#!/usr/bin/env python3
"""Generate/check the complete word reference from local registration and HELP data.

No network or build is used. --sigma runs the explicitly supplied executable.
--check never rewrites the generated documents or reviewed source record.
"""
import argparse
from collections import Counter
from functools import lru_cache
import html
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

ROOT = Path(__file__).resolve().parent.parent
STRING = r'"(?:[^"\\]|\\.)*"'


@lru_cache(maxsize=None)
def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


def decode(value):
    # These source tables use the JSON-compatible subset of Zig string escapes.
    return json.loads(value)


def table(source, name):
    match = re.search(r'\b(?:pub )?const ' + re.escape(name) + r'\s*=\s*\[_\](?:struct\s*\{[^}]*\}|[^{}\n]+)\{(.*?)\};', source, re.S)
    if not match:
        raise ValueError('registration table not found: ' + name)
    return match.group(1)


def pairs(source, name):
    return [(decode(a), b) for a, b in re.findall(r'\.\{\s*(' + STRING + r')\s*,\s*\.([a-z_0-9]+)\s*\}', table(source, name)) if decode(a)]


def names(source, name):
    return [decode(s) for s in re.findall(STRING, table(source, name))]


def anchor(namespace, name):
    return 'w-' + (namespace + ':' + name).encode('utf-8').hex()


def code(text):
    fence = '`' * (max([len(s) for s in re.findall(r'`+', text)] or [0]) + 1)
    return fence + ' ' + text + ' ' + fence


def prose(text):
    return re.sub(r'([\\`*_\[\]|])', r'\\\1', html.escape(text, quote=False))


def forth_definitions(path):
    """Read declarations in the embedded libraries, skipping comments/strings/bodies.

    This is a deliberately small scanner for these source files, not a Forth parser.
    --sigma independently checks the actual resulting dictionaries.
    """
    source = read(path)
    tokens = []
    cursor = 0
    while cursor < len(source):
        match = re.search(r'\S+', source[cursor:])
        if not match:
            break
        start = cursor + match.start()
        end = cursor + match.end()
        token = source[start:end]
        if token == '\\':
            cursor = source.find('\n', end)
            if cursor < 0:
                break
            continue
        if token == '(':
            cursor = source.find(')', end)
            if cursor < 0:
                raise ValueError('unterminated comment in ' + path)
            cursor += 1
            continue
        if token.upper() in ('S"', 'C"', '."', 'ABORT"', 'S\\"', '.\\"', '"'):
            escaped = '\\' in token
            cursor = end
            while cursor < len(source):
                if escaped and source[cursor] == '\\':
                    cursor += 2
                elif source[cursor] == '"':
                    cursor += 1
                    break
                else:
                    cursor += 1
            tokens.append((token, start, cursor))
            continue
        tokens.append((token, start, end))
        cursor = end
    result = []
    index = 0
    definers = {':', 'VARIABLE', 'FVARIABLE', '2VARIABLE', 'CREATE', 'CONSTANT', 'FCONSTANT', '2CONSTANT', 'VALUE', 'FVALUE', 'FIELD:', 'CFIELD:', 'BEGIN-STRUCTURE'}
    while index < len(tokens):
        token, start, end = tokens[index]
        if token.upper() not in definers:
            index += 1
            continue
        kind = token.upper()
        name, _, name_end = tokens[index + 1]
        index += 2
        stop = name_end
        if kind == ':':
            while index < len(tokens) and tokens[index][0] != ';':
                index += 1
            if index == len(tokens):
                raise ValueError('unterminated definition: ' + name)
            stop = tokens[index][2]
            index += 1
        line_start = source.rfind('\n', 0, start) + 1
        preceding = []
        for line in reversed(source[:line_start].splitlines()):
            if not line.lstrip().startswith('\\'):
                break
            text = line.lstrip()[1:].strip()
            if text.startswith('----'):
                break
            preceding.append(text)
        # A paragraph before a group of storage declarations describes the group,
        # not the behavior of each variable. Do not attach it to those entries.
        comment = ' '.join(reversed(preceding)).strip() if kind == ':' else ''
        body = source[start:stop]
        stack_match = re.match(r'\s*(\([^)]*--[^)]*\)|\{[^}]*\})', source[name_end:stop], re.S)
        if kind == ':':
            stack = stack_match.group(1).replace('\n', ' ') if stack_match else '( see definition )'
            text = comment or 'Internal library operation. Its exact implementation is reproduced below; it is not a stable public interface.'
        elif kind in ('VARIABLE', 'FVARIABLE', '2VARIABLE', 'CREATE'):
            stack = '( -- addr )'
            text = 'Return the address of private library storage. ' + comment
        elif kind in ('FIELD:', 'CFIELD:'):
            stack = '( struct -- field-addr )'
            text = 'Return the address of this structure field. ' + comment
        else:
            stack = '( -- x )' if kind != 'FCONSTANT' else '( F: -- r )'
            text = 'Return the private library constant or structure size defined on the source line below. ' + comment
            body = source[line_start:source.find('\n', stop) if '\n' in source[stop:] else len(source)]
        result.append(dict(name=name, stack=stack, text=text.strip(), definition=body, declaration=kind, origin=path, origin_line=source.count('\n', 0, start) + 1))
    return result


def inventory():
    help_source = read('src/core/help_text.zig')
    help_entries = {}
    category = ''
    for number, line in enumerate(help_source.splitlines(), 1):
        if line.startswith('    // '):
            category = line[7:]
        match = re.fullmatch(r'\s*\.\{ \.name = (' + STRING + r'), \.stack = (' + STRING + r'), \.text = (' + STRING + r') \},\s*', line)
        if match:
            name, stack, text = map(decode, match.groups())
            if name in help_entries:
                raise ValueError('duplicate HELP entry: ' + name)
            help_entries[name] = dict(name=name, stack=stack, text=text, category=category, help_line=number)
        elif '.name =' in line:
            raise ValueError('unparsed HELP entry at line %d' % number)

    entries = {}
    source = read('src/forth.zig')

    def add(namespace, name, origin, kind, builtin=None, override=None):
        key = (namespace, name)
        if key in entries:
            raise ValueError('duplicate registration: ' + str(key))
        if override is None and name not in help_entries:
            raise ValueError('no explanation for %s:%s' % key)
        data = dict(help_entries.get(name, {}))
        data.update(namespace=namespace, name=name, origin=origin, kind=kind, builtin=builtin)
        if override:
            data.update(override)
        entries[key] = data

    for name, builtin in pairs(source, 'builtin_definitions'):
        add('FORTH', name, 'src/forth.zig', 'builtin', builtin)

    root_names = names(read('src/core/memory_map.zig'), 'root_word_names')
    for name in root_names:
        entry = entries[('FORTH', name)]
        add('Root', name, 'src/core/memory_map.zig', 'builtin', entry['builtin'])

    add('FORTH', 'EKEYS', 'src/forth.zig', 'vocabulary')
    add('Root', 'EKEYS', 'src/forth.zig', 'vocabulary')
    keys = re.findall(r'\.\{\s*(' + STRING + r')\s*,\s*([0-9]+)\s*\}', table(read('src/core/standard_keys.zig'), 'constants'))
    for literal, value in keys:
        name = decode(literal)
        # HELP's K-LEFT etc. refer to GRAPHICS, whose encoding is different.
        individual = help_entries.get(name, {}).get('text', '')
        if 'FORTH/Sigma graphics' in individual:
            individual = ''
        text = (individual + ' ' if individual else '') + ('Standard EKEYS modifier mask ' if name.endswith('-MASK') else 'Standard EKEYS event code ') + value + ' (hex ' + hex(int(value)) + '). Use with EKEY/EKEY>FKEY, not with GRAPHICS INKEY. Host support determines which events can be received.'
        add('EKEYS', name, 'src/core/standard_keys.zig', 'constant', override=dict(stack='( -- u )', text=text, category='Standard keyboard constants', value=int(value), help_line=None))

    for group in ['graphics', 'gui', 'game', 'audio', 'extension']:
        namespace = group.upper()
        path = 'src/core/words_%s.zig' % group
        module = read(path)
        for name, builtin in pairs(module, 'definitions') if group in ('graphics', 'audio', 'extension') else []:
            add(namespace, name, path, 'builtin', builtin)
        for name in names(module, 'library_words'):
            add(namespace, name, path, 'library')
        if group == 'graphics':
            for name in names(module, 'float_library_words'):
                add(namespace, name, path, 'float library')
        vocabulary_text = 'Select ' + namespace + ' as the first-searched vocabulary. Load it first with REQUIRE-' + namespace + '; use ALSO to retain the current first vocabulary.'
        add('FORTH', namespace, path, 'vocabulary', override=dict(stack='( -- )', text=vocabulary_text, category='Optional vocabularies', help_line=None))

        libraries = ['src/extension/extension.fs'] if group == 'extension' else ['src/audio/audio.fs'] if group == 'audio' else ['src/graphics/' + group + '.fs']
        if group == 'graphics':
            libraries += ['src/graphics/graphics_float.fs']
        for library in libraries:
            for definition in forth_definitions(library):
                name = definition['name']
                if (namespace, name) in entries:
                    entries[(namespace, name)]['definition'] = definition['definition']
                    entries[(namespace, name)]['definition_source'] = library
                    entries[(namespace, name)]['origin_line'] = definition['origin_line']
                    entries[(namespace, name)]['declaration'] = definition['declaration']
                else:
                    if not (name.startswith('(') and name.endswith(')')):
                        raise ValueError('library declaration missing from public registry: %s:%s' % (namespace, name))
                    add(namespace, name, library, 'private library helper', override=definition)

    # HELP describes parser syntax and local declaration forms as well as words.
    registered = {name for _, name in entries}
    for name in help_entries.keys() - registered:
        add('Syntax', name, 'src/core/help_text.zig', 'syntax')

    # Local declaration prefixes are parser forms, absent from runtime HELP.
    local_types = re.findall(r'\.\{\s*(' + STRING + r'),\s*\.([a-z]+),\s*(true|false)\s*\}', table(read('src/core/local_variables.zig'), 'types'))
    for literal, kind, variable in local_types:
        name = decode(literal)
        text = 'Inside { ... } or {: ... :}, declare the next local as ' + ('addressable ' if variable == 'true' else 'value-flavoured ') + {'cell': 'one cell', 'double': 'a double cell', 'float': 'a floating-point number', 'char': 'a character', 'xt': 'an execution token'}[kind] + '. Inputs before | are initialized from their stack; locals after | start at zero. F: and F^ require floating-point support.'
        if name == 'XT:':
            text = 'Declare an execution-token local: using its name EXECUTES the stored token. Use W: to fetch a token value, or XT^ for its storage address. Inputs before | come from the stack; locals after | start at zero.'
        else:
            local_type = {'cell': 'cell', 'double': 'double-cell integer', 'float': 'floating-point value', 'char': 'character', 'xt': 'execution token'}[kind]
            text = 'Declare the next local to store a ' + local_type + '. Its name returns ' + ('its storage address.' if variable == 'true' else 'its value.')
            text += ' Inputs before | come from the ' + ('floating-point' if kind == 'float' else 'data') + ' stack; locals after | start at zero.'
            if kind == 'float':
                text += ' Floating-point support is required.'
        add('Syntax', name, 'src/core/local_variables.zig', 'local declaration prefix', override=dict(stack='( compilation: "local-name" -- )', text=text, category='Locals', help_line=None))
    for name, text in {'}': 'End a { ... } local declaration.', ':}': 'End a {: ... :} local declaration.', '|': 'Inside a local declaration, start zero-initialized locals; in LOCALS|, end the declaration.', '--': 'Inside a local declaration, start a stack-effect comment up to its closing delimiter.'}.items():
        add('Syntax', name, 'src/core/local_variables.zig', 'local declaration delimiter', override=dict(stack='( compilation: -- )', text=text, category='Locals', help_line=None))

    parser_names = {decode(s) for s in re.findall(r'(?:asciiEqlIgnoreCase\(token,\s*|std\.mem\.(?:eql|startsWith)\(u8,\s*token,\s*)(' + STRING + r')', source)}
    for name in parser_names:
        if not any(key[1] == name for key in entries):
            raise ValueError('parser token without documentation: ' + name)

    # Flag tables are the implementation's authority, not guesses based on names.
    for attribute, function in [('compile_only', 'isCompileOnlyBuiltin'), ('immediate', 'isImmediateBuiltin')]:
        match = re.search(r'fn ' + function + r'\(.*?\n    \}', source, re.S)
        if not match:
            raise ValueError('missing flag function: ' + function)
        flags = set(re.findall(r'\.([a-z_0-9]+)', match.group())) - {'builtin'}
        for entry in entries.values():
            entry[attribute] = entry.get('builtin') in flags

    storage = json.loads(read('docs/word-reference/private-storage.json'))
    valid_storage = {e['namespace'] + ':' + e['name'] for e in entries.values() if e['kind'] == 'private library helper'}
    if set(storage) - valid_storage:
        raise ValueError('private storage without an inventory entry: ' + repr(sorted(set(storage) - valid_storage)))
    for entry in entries.values():
        key = entry['namespace'] + ':' + entry['name']
        if key in storage:
            entry['text'], entry['storage_ja'] = storage[key]
        if entry.get('builtin'):
            enrich(entry)

    return sorted(entries.values(), key=lambda e: (e['namespace'], e['kind'] == 'private library helper', e['name'].casefold(), e['name'])), help_entries


def enrich(entry):
    """Per-operation details for HELP families that share a short description.

    Authority: words_arithmetic.zig, integer_math.zig and words_width.zig.
    Keep the original HELP text intact and show these as documentation notes.
    """
    name = entry['name']
    for suffix, rounding, rounding_ja in [('F', 'toward negative infinity', '負の無限大方向'), ('S', 'toward zero', 'ゼロ方向')]:
        for stem, product, results, results_ja in [('/', False, 'the quotient', '商'), ('/MOD', False, 'the remainder followed by the quotient', '余り、商の順'), ('MOD', False, 'the remainder', '余り'), ('*/', True, 'the quotient', '商'), ('*/MOD', True, 'the remainder followed by the quotient', '余り、商の順')]:
            if name == stem + suffix:
                dividend = 'the signed 128-bit product n1*n2' if product else 'signed n1'
                entry['note_en'] = 'Divide %s by %s, rounding %s; return %s. Zero divisor throws -10; an out-of-range signed cell quotient throws -11.' % (dividend, 'n3' if product else 'n2', rounding, results)
                entry['note_ja'] = ('n1×n2の符号付き128ビット積をn3で割り' if product else '符号付きn1をn2で割り') + '、商を' + rounding_ja + 'へ丸めます。戻り値は' + results_ja + 'です。除数0は-10、商が符号付き1セルの範囲外なら-11を投げます。'
    unsigned = {'U/': ('u1', 'u2', 'the quotient', '商'), 'U/MOD': ('u1', 'u2', 'remainder then quotient', '余り、商の順'), 'UMOD': ('u1', 'u2', 'the remainder', '余り'), 'U*/': ('the unsigned 128-bit product u1*u2', 'u3', 'the quotient', '商'), 'U*/MOD': ('the unsigned 128-bit product u1*u2', 'u3', 'remainder then quotient', '余り、商の順')}
    if name in unsigned:
        dividend, divisor, result, result_ja = unsigned[name]
        entry['note_en'] = 'Divide %s by %s as unsigned integers; return %s. Multiplication uses a 128-bit intermediate. Zero divisor throws -10; a quotient outside unsigned 64-bit range throws -11.' % (dividend, divisor, result)
        entry['note_ja'] = ('u1×u2の符号なし128ビット積をu3で割ります。' if name.startswith('U*') else 'u1をu2で符号なし除算します。') + '戻り値は' + result_ja + 'です。除数0は-10、商が符号なし64ビットの範囲外なら-11を投げます。'
    sizes = {'/W': 2, '/L': 4, '/X': 8, 'FLOAT': 8}
    if name in sizes:
        entry['note_en'] = 'Push the byte size %d; no memory is allocated.' % sizes[name]
        entry['note_ja'] = 'バイト単位の大きさ%dを積みます。領域の割当ては行いません。' % sizes[name]
    divisions = {'CELL/': 8, 'FLOAT/': 8, 'DFLOAT/': 8, 'SFLOAT/': 4}
    if name in divisions:
        entry['note_en'] = 'Divide signed n by %d, rounding toward negative infinity.' % divisions[name]
        entry['note_ja'] = '符号付きnを%dで割り、負の無限大方向へ丸めます。' % divisions[name]
    alignments = {'WALIGN': 2, 'WALIGNED': 2, 'LALIGN': 4, 'LALIGNED': 4, 'XALIGN': 8, 'XALIGNED': 8, 'MAXALIGNED': 8, '*ALIGN': None, '*ALIGNED': None}
    if name in alignments:
        alignment = alignments[name]
        value = str(alignment) if alignment else 'the supplied power-of-two n'
        moves_here = name.endswith('ALIGN')
        entry['note_en'] = ('Advance HERE to' if moves_here else 'Return, without moving HERE,') + ' the next address aligned to %s bytes (an already aligned address stays unchanged).' % value
        entry['note_ja'] = ('HEREを' if moves_here else 'HEREを変えず、入力番地を') + ('指定した2のべき乗n' if alignment is None else str(alignment)) + 'バイト境界へ切り上げ' + ('ます。' if moves_here else 'た番地を返します。') + '既に整列していれば同じ番地です。'
    stores = {'W!': 2, 'L!': 4, 'X!': 8, 'TH!': 8}
    if name in stores:
        width = stores[name]
        location = 'a-addr + n*8' if name == 'TH!' else 'addr'
        entry['note_en'] = 'Write the low %d bits at %s in logical little-endian order. Validate all %d bytes before modifying memory. This operation is not atomic.' % (width * 8, location, width)
        entry['note_ja'] = '%sへ下位%dビットを論理リトルエンディアンで書き込みます。%dバイト全体の範囲を確認してから変更します。アトミックな操作ではありません。' % (location, width * 8, width)
    if name in ('WLE', 'LLE', 'XLE', 'XDLE'):
        entry['note_en'] = 'Return the input unchanged; this operation does not truncate high bits. XDLE preserves both cells.'
        entry['note_ja'] = '入力をそのまま返し、上位ビットを切り捨てません。XDLEでは2セルとも保持します。'


@lru_cache(maxsize=None)
def manual_links(name, japanese, namespace):
    result = []
    suffix = '.ja.md' if japanese else '.md'
    preferred = {'EXTENSION': 'EXTENSION', 'GRAPHICS': 'GRAPHICS_AND_SOUND',
                 'AUDIO': 'GRAPHICS_AND_SOUND', 'GUI': 'GRAPHICS_AND_SOUND',
                 'GAME': 'GRAPHICS_AND_SOUND'}.get(namespace)
    bases = list(dict.fromkeys([preferred] + ['EXTENSION', 'GRAPHICS_AND_SOUND', 'USER_MANUAL', 'DEBUGGING']))
    for base in filter(None, bases):
        heading = None
        chapter = None
        matches = []
        exact = []
        for line in read('docs/' + base + suffix).splitlines():
            if line.startswith('## '):
                chapter = line[3:]
            if re.match(r'^#{2,3} ', line):
                heading = line.lstrip('# ')
                if heading in ('Words in this chapter', 'この章の語'):
                    heading = chapter
            exact_word = ('#' + anchor(namespace, name) + ')') in line
            if heading and (exact_word or (re.search(r'`' + re.escape(name) + r'`', line) and not (line.startswith('|') and line.count('`') > 16))):
                if heading in ('登録済みワード一覧', 'Registered words', '構文・定義形式', 'Syntax and defining forms', '語群別の案内', 'Vocabulary overview'):
                    continue
                fragment = re.sub(r'[^\w\-\s\u3000-\u9fff]', '', heading.lower()).replace(' ', '-')
                link = '[%s](%s#%s)' % (heading, base + suffix, fragment)
                target = exact if ('#' + anchor(namespace, name) + ')') in line else matches
                if link not in target:
                    target.append(link)
        if base == preferred and not (exact or matches):
            fallback = {'GRAPHICS': ('グラフィックス', 'Graphics'), 'AUDIO': ('サウンド', 'Sound'),
                        'GUI': ('GUI', 'GUI'), 'GAME': ('スプライトとタイルマップ', 'Sprites and tile maps')}
            if namespace in fallback:
                title = fallback[namespace][0 if japanese else 1]
                matches.append('[%s](%s#%s)' % (title, base + suffix, title.lower().replace(' ', '-')))
        # Chapter word lists identify the namespace even for overloaded names.
        for link in exact + matches:
            if link not in result:
                result.append(link)
    return result[:3]


def translation_sources(entries, keys):
    result = {}
    for key in keys:
        sources = [{k: v for k, v in e.items() if k not in ('usage', 'text_ja')} for e in entries if key in (e['name'], e['namespace'] + ':' + e['name'])]
        if not sources:
            raise ValueError('translation without a source: ' + key)
        result[key] = hashlib.sha256(json.dumps(sources, ensure_ascii=False, sort_keys=True).encode('utf-8')).hexdigest()
    # Git may check sources out with CRLF on Windows and LF on Unix.
    implementation = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_text(encoding='utf-8').encode('utf-8')).hexdigest()
                      for p in sorted((ROOT / 'src').rglob('*')) if p.suffix in ('.zig', '.fs', '.c', '.h')}
    return dict(translations=result, implementation=implementation)


def localize(entries, record_sources=False):
    translations = {}
    for number, line in enumerate(read('docs/word-reference/translations.ja.tsv').splitlines(), 1):
        if not line:
            continue
        key, text = line.split('\t', 1)
        if key in translations or not re.search(r'[ぁ-んァ-ヶ一-龯]', text):
            raise ValueError('invalid Japanese translation at line %d: %s' % (number, key))
        translations[key] = text
    fingerprints = translation_sources(entries, translations)
    lock_path = ROOT / 'docs/word-reference/translation-sources.json'
    if not lock_path.exists() and not record_sources:
        raise ValueError('reviewed translation source record is missing')
    if not record_sources:
        recorded = json.loads(lock_path.read_text(encoding='utf-8'))
        changed = [key for key in fingerprints if fingerprints[key] != recorded.get(key)]
        if changed or set(recorded) - set(fingerprints):
            details = {group: sorted(k for k in set(fingerprints[group]) | set(recorded.get(group, {})) if fingerprints[group].get(k) != recorded.get(group, {}).get(k)) for group in changed}
            raise ValueError('translation sources changed; review Japanese text before recording sources: ' + repr(details or sorted(set(recorded) - set(fingerprints))))
    missing = []
    for e in entries:
        name = e['name']
        key = e['namespace'] + ':' + name
        text = translations.get(key, translations.get(name))
        if e['namespace'] == 'EKEYS':
            text = (text + ' ' if text else '') + '標準EKEYSの' + ('修飾マスク' if name.endswith('-MASK') else 'キーイベント定数') + 'です。値は%d（%s）です。EKEY系で使います。GRAPHICSとは別の符号化体系です。' % (e['value'], hex(e['value']))
        elif e['kind'] == 'vocabulary' and name in ('GRAPHICS', 'GUI', 'GAME', 'AUDIO', 'EXTENSION'):
            text = 'REQUIRE-%sで読み込んだ%s語彙を検索順の先頭へ選びます。現在の先頭を残すにはALSOを先に実行します。' % (name, name)
        if text is None and e.get('note_ja'):
            text = e['note_ja']
        if text is None and re.match(r'(?:Host primitive|Primitive) for ', e['text']):
            target = re.match(r'(?:Host primitive|Primitive) for ([^ (]+)', e['text']).group(1).rstrip('.')
            text = target + 'を実装するホスト側の基本処理です。スタックに示した引数を直接受け取ります。通常は対応するライブラリ語を使います。'
        if text is None and e['namespace'] == 'GRAPHICS' and name.startswith('K-'):
            text = 'GRAPHICSのINKEYが返す' + name[2:] + 'キーの値です。標準EKEYSの同名定数とは区別します。'
        if text is None and e['kind'] == 'local declaration prefix':
            kind = {'W': '1セル', 'D': '倍長整数', 'F': '浮動小数点数', 'C': '文字', 'XT': '実行トークン'}[name.rstrip(':^')]
            text = '次のローカル名を%s型の%sとして宣言します。|の前はスタックから初期化し、後は0です。' % (kind, '番地を返す変数' if name.endswith('^') else '値を返すローカル')
            if name.startswith('F'):
                text += '浮動小数点機能が必要です。'
            if name == 'XT:':
                text = '実行トークンを保持するローカルを宣言します。名前を使うと保持したトークンを実行します。値として取り出す場合はW:、格納先の番地にはXT^を使います。|の前はスタックから初期化し、後は0です。'
        if text is None and e['kind'] == 'local declaration delimiter':
            text = {'}': '{で始めたローカル宣言を閉じます。', ':}': '{:で始めた標準ローカル宣言を閉じます。', '|': 'ローカル宣言で0初期化領域を開始します。LOCALS|では宣言を終了します。', '--': 'ローカル宣言の閉じ記号までをスタック効果のコメントとして扱います。'}[name]
        if e.get('storage_ja'):
            text = e['storage_ja']
        if text is None:
            missing.append(key)
        else:
            e['text_ja'] = text
    valid = {e['name'] for e in entries} | {e['namespace'] + ':' + e['name'] for e in entries}
    if set(translations) - valid:
        raise ValueError('translations without an inventory entry: ' + repr(sorted(set(translations) - valid)))
    if missing:
        raise ValueError('Japanese explanations missing: ' + repr(missing))
    if record_sources:
        lock_path.write_text(json.dumps(fingerprints, ensure_ascii=False, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')


def attach_usages(entries):
    from word_reference_examples import collect_examples
    candidates = collect_examples(ROOT, entries)
    overrides = json.loads(read('docs/word-reference/usage-overrides.json'))
    valid = {e['name'] for e in entries} | {e['namespace'] + ':' + e['name'] for e in entries}
    if set(overrides) - valid:
        raise ValueError('usage overrides without an inventory entry: ' + repr(sorted(set(overrides) - valid)))
    missing = []
    for e in entries:
        name, namespace = e['name'], e['namespace']
        explicit = overrides.get(namespace + ':' + name, overrides.get(name))
        e['usage_mode'] = 'standalone'
        if explicit is not None:
            if isinstance(explicit, dict):
                e['usage_mode'] = explicit.get('mode', 'standalone')
                explicit = explicit['code']
            if not isinstance(explicit, str) or not explicit.strip():
                raise ValueError('empty usage override: ' + namespace + ':' + name)
            e['usage'] = (explicit, None, None)
        elif namespace == 'EKEYS':
            e['usage'] = ('ALSO EKEYS %s . PREVIOUS' % name, None, None)
        elif namespace == 'FORTH' and name in ('GRAPHICS', 'GUI', 'GAME', 'AUDIO', 'EXTENSION'):
            e['usage'] = ('REQUIRE-%s ALSO %s WORDS PREVIOUS' % (name, name), None, None)
        elif namespace in ('GRAPHICS', 'GUI', 'GAME', 'AUDIO', 'EXTENSION') and e.get('declaration') in ('CONSTANT', 'FCONSTANT', 'BEGIN-STRUCTURE'):
            output = 'F.S' if e.get('declaration') == 'FCONSTANT' else '.'
            e['usage'] = ('REQUIRE-%s ALSO %s %s %s PREVIOUS' % (namespace, namespace, name, output), None, None)
        elif namespace == 'GAME' and e.get('declaration') in ('FIELD:', 'CFIELD:'):
            size = '/SPRITE' if name.startswith('SPRITE-') else '/TILEMAP' if name.startswith('TILEMAP-') else '/INDEXED'
            e['usage'] = ('REQUIRE-GAME ALSO GAME CREATE REVIEW-OBJECT %s ALLOT REVIEW-OBJECT %s REVIEW-OBJECT - . PREVIOUS' % (size, name), None, None)
        elif e['kind'] == 'private library helper' and e.get('declaration') in ('VARIABLE', '2VARIABLE', 'FVARIABLE', 'CREATE'):
            output = 'F@ F.S' if e.get('declaration') == 'FVARIABLE' else '@ .'
            e['usage'] = ('REQUIRE-%s ALSO %s %s %s PREVIOUS' % (namespace, namespace, name, output), None, None)
        elif (namespace, name) in candidates:
            _, snippet, path, number, mode = candidates[(namespace, name)]
            e['usage'] = (snippet, path, number)
            e['usage_mode'] = mode
        elif e['kind'] == 'private library helper' and e.get('definition'):
            e['usage'] = (e['definition'], e.get('definition_source', e['origin']), e.get('origin_line', 1))
            e['usage_mode'] = 'definition'
        else:
            missing.append(namespace + ':' + name)
    if missing:
        raise ValueError('usage examples missing: ' + repr(missing))


def caution(e, japanese):
    notes = []
    if e['kind'] == 'private library helper' or (e['name'].startswith('(') and e['name'] != '('):
        notes.append('内部処理です。通常は対応する公開語を使い、内部状態や呼出規約に依存しないでください。' if japanese else 'Internal operation: prefer its public wrapper; internal state and calling conventions may change.')
    if e['compile_only']:
        notes.append('コンパイル専用です。通常の解釈時入力では実行できません。' if japanese else 'Compile-only: ordinary interpreted execution is not allowed.')
    elif e['immediate']:
        notes.append('即時語なので、定義のコンパイル中にもその場で実行されます。' if japanese else 'Immediate: it executes during definition compilation.')
    if e['namespace'] in ('GRAPHICS', 'GUI', 'GAME', 'AUDIO', 'EXTENSION'):
        notes.append('対象語彙の読込みと検索順が必要です。表示・入力・音声のホスト対応は利用環境に依存します。' if japanese else 'Load and select the vocabulary first. Host display, input and sound support depends on the environment.')
    if e['name'] == 'KEY-IOR':
        notes.append('結果は1セルです。バイト値をTHROWへ渡さず、負の値かどうかを先に判定してください。' if japanese else 'The result is one cell. Test for a negative result before treating it as an ior; do not pass an ordinary byte to THROW.')
    elif 'ior' in e['stack'].lower():
        notes.append('戻り値のiorを確認してください。0が成功です。THROWへ渡す方法もあります。' if japanese else 'Check the returned ior; zero is success. Passing it to THROW is one option.')
    if 'addr' in e['stack'].lower():
        notes.append('番地・長さ・容量は有効な論理メモリー範囲を指定します。所有領域と借用領域の寿命を区別してください。' if japanese else 'Use valid logical-memory addresses, lengths and capacities; distinguish owned storage from borrowed lifetimes.')
    if '( F:' in e['stack']:
        notes.append('F:の値はデータスタックではなく浮動小数点スタックで受け渡します。' if japanese else 'F: items belong to the floating-point stack, not the data stack.')
    if not notes:
        notes.append('スタック効果の入力順を守ってください。使用例の名前・値は例の定義や初期状態に依存します。' if japanese else 'Follow the operand order in the stack effect. Example names and values depend on their setup.')
    return ' '.join(notes)


def worker_policy(entry, japanese):
    source = read('src/core/task_permissions.zig').split('pub fn policy(', 1)[1].split('const Dictionary', 1)[0]
    builtin = entry.get('builtin')
    policy = re.search(r'\.' + re.escape(builtin or '__unknown__') + r'\s*=>\s*\.(allow|memory)', source)
    category = policy.group(1) if policy else 'deny'
    if not builtin:
        if entry.get('declaration') in ('CONSTANT', 'FCONSTANT', 'VARIABLE', '2VARIABLE', 'FVARIABLE', 'CREATE', 'FIELD:', 'CFIELD:') or entry['namespace'] == 'EKEYS':
            category = 'allow'
        elif entry.get('definition'):
            category = 'definition'
    if japanese:
        return {'allow': '許可。入口の静的到達検査・最適化後Op検査を通る必要がある。', 'memory': '条件付き。許可された論理ペイロード範囲・書込権限・native総処理量64 KiB/回以下を検査する。入口全体の許可を保証しない。', 'deny': '不可。未登録・将来の語も既定で不可とする。', 'definition': '定義による（depends on definition）。投入時に定義と到達する命令を検査する。'}[category]
    return {'allow': 'allowed; entry reachability and optimized operations must also pass validation.', 'memory': 'conditional; granted logical payload ranges, write permission, and total native work <=64 KiB per call; this does not grant entry-wide permission.', 'deny': 'forbidden; unregistered and future words default to forbidden.', 'definition': 'depends on definition; admission checks the definition and reachable operations.'}[category]


def render(entries, japanese=False):
    counts = Counter(e['namespace'] for e in entries)
    title = '全ワードリファレンス' if japanese else 'Complete word reference'
    out = ['# FORTH/Sigma ' + title, '']
    if japanese:
        out += ['このリファレンスは、古い語と追加語を区別せず、現在の実装の登録語、標準キー定数、追加ライブラリの語、入力構文とローカル宣言形式を対象にします。ライブラリ内部の補助定義も収録し、公開語と区別します。利用者が定義する任意の名前は対象に含めません。', '',
                '各項目にスタック効果、日本語の動作説明、使用例、注意点を掲載します。照合用にHELP・実装に基づく英語の説明も併記します。使用例は単独例、または既存コードの抜粋です。抜粋は準備・入力・期待結果を参照先で確認してください。[使用例と読み方](WORD_REFERENCE_GUIDE.ja.md)には単独で確認した例をまとめています。', '',
                '通常構成を基準とします。機能を除いた構成では対象の語を使えません。追加語彙はREQUIREで読み込んでから検索順へ加えます。即時語・コンパイル専用の印は、組込み語の実装にある属性です。構文の実行条件は説明本文に従ってください。', '']
    else:
        out += ['This reference covers every registered word, standard keyboard constant, optional-library word, parser form and local declaration form in the current implementation, regardless of when it was added. Private library helpers are included and marked separately from the public API. Arbitrary user-defined names are outside this inventory.', '',
                'Each entry has a stack effect and a behavior description based on runtime HELP, registration sources and implementation definitions. See the [reading guide and examples](WORD_REFERENCE_GUIDE.md) for notation, prerequisites, examples and cautions, and the related manual sections for longer explanations.', '',
                'Coverage assumes the full build. Feature-disabled builds omit their respective words. Load optional vocabularies with REQUIRE before adding them to the search order. Immediate/compile-only flags come from the built-in implementation; syntax forms have their own conditions in their descriptions.', '']
    out += [('項目数（語彙と名前の組）：**%d**。同名でも語彙が異なる項目は別に数えます。' if japanese else 'Entries (namespace/name pairs): **%d**. The same name in different vocabularies counts separately.') % len(entries), '',
            ('## 目次' if japanese else '## Contents'), '']
    for namespace, count in sorted(counts.items()):
        out.append('- [%s](#namespace-%s) (%d)' % (namespace, namespace.lower(), count))
    out += ['', ('更新：`python scripts/word-reference.py`。照合のみ：`python scripts/word-reference.py --check`。生成文書の本文を直接編集せず、HELP原文・登録定義または生成スクリプトを更新してください。' if japanese else 'Regenerate: `python scripts/word-reference.py`. Check only: `python scripts/word-reference.py --check`. Edit the HELP/registration sources or generator, rather than editing generated entries.'), '']
    for namespace in sorted(counts):
        out += ['<a id="namespace-%s"></a>' % namespace.lower(), '', '## ' + namespace, '']
        subset = [e for e in entries if e['namespace'] == namespace]
        out += ['- [%s](#%s)' % (code(e['name']), anchor(namespace, e['name'])) for e in subset]
        out.append('')
        for e in subset:
            out += ['<a id="%s"></a>' % anchor(namespace, e['name']), '', '### ' + code(e['name']), '', code(e['stack']), '', prose(e['text_ja'] if japanese else e['text']), '']
            if japanese:
                out += ['<details><summary>英語の説明（HELP・実装に基づく）</summary>', '', prose(e['text']), '', '</details>', '']
            out += ['worker: ' + worker_policy(e, japanese), '']
            flags = [label for flag, label in [('immediate', 'immediate'), ('compile_only', 'compile-only')] if e[flag]]
            out += [('種別：' if japanese else 'Kind: ') + e['kind'] + (('; ' + ', '.join(flags)) if flags else '') + '.', '']
            if e.get('note_en'):
                out += [('補足：' if japanese else 'Detail: ') + prose(e['note_ja' if japanese else 'note_en']), '',
                        '[%s](../src/core/%s)' % ('補足の根拠' if japanese else 'Detail source', 'words_width.zig' if e['name'] in {'/W', '/L', '/X', 'FLOAT', 'CELL/', 'FLOAT/', 'DFLOAT/', 'SFLOAT/', 'WALIGN', 'WALIGNED', 'LALIGN', 'LALIGNED', 'XALIGN', 'XALIGNED', 'MAXALIGNED', '*ALIGN', '*ALIGNED', 'W!', 'L!', 'X!', 'TH!', 'WLE', 'LLE', 'XLE', 'XDLE'} else 'words_arithmetic.zig'), '']
            if namespace in ('GRAPHICS', 'GUI', 'GAME', 'AUDIO', 'EXTENSION'):
                out += [code('REQUIRE-' + namespace + ' ALSO ' + namespace) + (' で読み込み、検索対象にします。' if japanese else ' loads the vocabulary and makes it searchable.'), '']
            elif namespace == 'EKEYS':
                out += [code('ALSO EKEYS') + (' で標準キー定数を検索します。GRAPHICSとは別の符号化体系です。' if japanese else ' selects standard keyboard constants, using an encoding independent of GRAPHICS.'), '']
            links = manual_links(e['name'], japanese, namespace)
            if links:
                out += [('関連説明：' if japanese else 'Related: ') + ', '.join(links) + '.', '']
            example, example_path, example_line = e['usage']
            mode = e['usage_mode']
            labels = {'error': ('例外を意図する入力です。正常終了の例ではありません。', 'This input intentionally raises an exception.'),
                      'caught-error': ('例外をCATCHで捕捉する例です。', 'This example catches an expected exception.'),
                      'indirect': ('対応する公開構文を使う間接使用例です。', 'Indirect use through the corresponding public syntax.'),
                      'definition': ('内部補助語の定義です。単独での呼出例ではありません。', 'Private helper definition; not a standalone call example.')}
            if mode in labels:
                out += [labels[mode][0 if japanese else 1], '']
            out += [('使用例' if japanese else 'Usage example') + ('（既存コードの抜粋。準備や期待結果はリンク先を参照）' if japanese and example_path else (' (source excerpt; consult the link for setup and expectations)' if example_path else '')), '', '```forth', example, '```', '']
            if example_path:
                out += ['[%s](../%s#L%d)' % ('使用例の文脈' if japanese else 'Example context', example_path, example_line), '']
            elif mode == 'indirect':
                out += [('この内部処理を生成する公開構文の例です。定義だけの例は、ステップ実行や診断出力を起動しません。' if japanese else 'This public syntax generates the internal operation. Definition-only examples do not start stepping or diagnostic output.'), '']
            out += [('注意：' if japanese else 'Caution: ') + caution(e, japanese), '']
            if e.get('definition'):
                out += [('実装定義（内部補助語は変更される場合があります）：' if japanese else 'Implementation definition (private helpers may change):'), '', '```forth', e['definition'], '```', '']
            origin = e['origin']
            sources = ['[%s](../%s)' % (origin, origin)]
            if e.get('help_line'):
                sources.append('[HELP](../src/core/help_text.zig#L%d)' % e['help_line'])
            out += [('出典：' if japanese else 'Sources: ') + ', '.join(sources) + '.', '']
    return '\n'.join(line.rstrip() for line in '\n'.join(out).split('\n'))


def audit_runtime(entries, sigma):
    sigma = str(sigma.resolve())
    namespaces = {e['namespace'] for e in entries} - {'Syntax'}
    for namespace in sorted(namespaces):
        if namespace == 'FORTH':
            source = 'REQUIRE-GRAPHICS REQUIRE-GUI REQUIRE-GAME REQUIRE-AUDIO REQUIRE-EXTENSION WORDS BYE'
        elif namespace == 'Root':
            source = 'ONLY WORDS FORTH BYE'
        elif namespace == 'EKEYS':
            source = 'ALSO EKEYS WORDS BYE'
        else:
            source = 'REQUIRE-%s ALSO %s WORDS BYE' % (namespace, namespace)
        result = subprocess.run([sigma, '-e', source], capture_output=True, text=True, encoding='utf-8', timeout=30, cwd=ROOT)
        if result.returncode or result.stderr.strip():
            raise ValueError('runtime dictionary query failed: %s: %s %s' % (namespace, result.stdout, result.stderr))
        actual = result.stdout.split()
        expected = {e['name'] for e in entries if e['namespace'] == namespace}
        if len(actual) != len(set(actual)):
            raise ValueError('duplicate runtime name in ' + namespace)
        if set(actual) != expected:
            raise ValueError('dictionary mismatch %s: undocumented=%r; absent=%r' % (namespace, sorted(set(actual) - expected), sorted(expected - set(actual))))
        print('runtime %s: %d names, no omissions' % (namespace, len(actual)))
    constants = [e for e in entries if e['namespace'] == 'EKEYS']
    source = 'ALSO EKEYS ' + ' '.join(e['name'] + ' .' for e in constants) + ' BYE'
    result = subprocess.run([sigma, '-e', source], capture_output=True, text=True, encoding='utf-8', timeout=30, cwd=ROOT)
    if result.returncode or result.stderr.strip() or result.stdout.split() != [str(e['value']) for e in constants]:
        raise ValueError('EKEYS constant values differ from the documented values')
    print('runtime EKEYS values: %d matched' % len(constants))


def render_guide(japanese):
    language = 'ja' if japanese else 'en'
    suffix = '.ja.md' if japanese else '.md'
    out = ['# ' + ('ワードリファレンスの読み方と使用例' if japanese else 'Reading the word reference and running the examples'), '']
    out += [read('docs/word-reference/guide.' + language + '.txt').strip(), '']
    examples = json.loads(read('docs/word-reference/examples.json'))
    out += [('## 使用例' if japanese else '## Examples'), '']
    for example in examples:
        out += ['### ' + example['title_' + language], '', example['note_' + language], '', '```forth', example['code'], '```', '', ('出力：' if japanese else 'Output:'), '', '```text', example['output'].rstrip(), '```', '']
    out += [('## 更新と照合' if japanese else '## Regeneration and checks'), '',
            ('本文は実装の登録一覧・HELP原文・埋込みForthライブラリから生成します。番号や追加時期で対象を絞りません。`--check`はファイルを書き換えず、説明欠落と生成済み文書の古さを検出します。`--sigma`は指定実行体の実際の辞書と全件比較し、使用例の出力も確認します。実行体は通常構成で事前にビルドしてください。機能除外版を指定すると一致しません。' if japanese else 'Entries are generated from implementation registration tables, HELP and embedded Forth libraries, without filtering by age or task number. --check detects missing descriptions and stale generated files without writing them. --sigma compares every name with the actual dictionaries of the supplied executable and checks example outputs. Build the full configuration first; a feature-disabled binary will not match.'), '',
            '```powershell', 'zig build', 'python scripts/word-reference.py', 'python scripts/word-reference.py --check --sigma zig-out/bin/sigma.exe', 'python scripts/check-docs.py', '```', '',
            ('使用例は各々新しいプロセスで実行します。ファイル保存・シェル起動・対話入力・画面表示・音声再生は行いません。これらの操作が必要な語の詳しい使用方法は、各項目の関連マニュアルを参照してください。この確認は全語の振る舞いを実機検証したという意味ではありません。' if japanese else 'Each example runs in a fresh process. Examples do not save files, launch a shell, request input, display a window or play sound. Consult each entry\'s related manuals for words requiring those operations. This check does not mean that every word\'s behavior has been tested on a physical device.'), '',
            '[%s](WORD_REFERENCE%s)' % ('全ワードリファレンスへ戻る' if japanese else 'Back to the complete reference', suffix), '']
    return '\n'.join(line.rstrip() for line in '\n'.join(out).split('\n'))


def audit_examples(sigma):
    examples = json.loads(read('docs/word-reference/examples.json'))
    for example in examples:
        result = subprocess.run([str(sigma.resolve()), '-e', example['code'] + '\nBYE'], capture_output=True, text=True, encoding='utf-8', timeout=30, cwd=ROOT)
        if result.returncode or result.stderr.strip() or result.stdout.split() != example['output'].split():
            raise ValueError('example failed: %s; expected=%r; actual=%r; stderr=%r' % (example['title_en'], example['output'], result.stdout, result.stderr))
    print('documentation examples: %d passed' % len(examples))
    overrides = json.loads(read('docs/word-reference/usage-overrides.json'))
    for name, source in overrides.items():
        if isinstance(source, dict):
            source = source['code']
        result = subprocess.run([str(sigma.resolve()), '-e', source + '\nBYE'], input='', capture_output=True, text=True, encoding='utf-8', timeout=15, cwd=ROOT)
        if result.returncode:
            raise ValueError('individual usage failed: %s: %r %r' % (name, result.stdout, result.stderr))
    print('individual runnable usage examples: %d passed' % len(overrides))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--sigma', type=Path, help='independently audit full-build runtime dictionaries')
    parser.add_argument('--record-reviewed-sources', action='store_true', help='record source fingerprints after reviewing Japanese translations')
    args = parser.parse_args()
    if args.check and args.record_reviewed_sources:
        parser.error('--check cannot record translation sources')
    try:
        entries, help_entries = inventory()
        localize(entries, args.record_reviewed_sources)
        attach_usages(entries)
        print('Japanese explanations, usage examples and cautions: %d complete' % len(entries))
        if args.sigma:
            audit_runtime(entries, args.sigma)
            audit_examples(args.sigma)
        documents = {'docs/WORD_REFERENCE.md': render(entries), 'docs/WORD_REFERENCE.ja.md': render(entries, True),
                     'docs/WORD_REFERENCE_GUIDE.md': render_guide(False), 'docs/WORD_REFERENCE_GUIDE.ja.md': render_guide(True)}
        errors = []
        for path, expected in documents.items():
            target = ROOT / path
            if args.check:
                if not target.exists() or target.read_text(encoding='utf-8') != expected:
                    errors.append(path + ' is missing or out of date')
            else:
                target.write_text(expected, encoding='utf-8', newline='\n')
        print('HELP descriptions: %d; reference entries: %d' % (len(help_entries), len(entries)))
        print('Namespaces: ' + ', '.join('%s=%d' % item for item in sorted(Counter(e['namespace'] for e in entries).items())))
        for error in errors:
            print(error, file=sys.stderr)
        return bool(errors)
    except (ValueError, KeyError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())

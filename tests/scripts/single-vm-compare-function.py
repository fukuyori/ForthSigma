"""Compare one function's machine code between two binaries, ignoring addresses.

usage: cmpfunc.py OBJDUMP BIN_A START_A SIZE_A BIN_B START_B SIZE_B
Prints instruction count, the number of differing normalized instructions, and the diffs.
"""
import re, subprocess, sys, difflib

def dis(objdump, binary, start, size):
    out = subprocess.check_output([objdump, '-d', '--no-show-raw-insn', f'--start-address={start}',
                                   f'--stop-address={start + size}', binary]).decode(errors='replace')
    insns = []
    for line in out.splitlines():
        m = re.match(r'^\s*([0-9a-f]+):\s+(.*)$', line)
        if not m:
            continue
        # Strip x86 comments ("# 0x...", hash then space) and arm64 comments ("// ...");
        # keep arm64 immediates such as "#0x10".
        text = re.sub(r'\s#\s.*$', '', m.group(2))
        text = text.split('//')[0].strip()
        text = re.sub(r'<[^>]*>', '<SYM>', text)
        text = re.sub(r'0x[0-9a-f]+', 'IMM', text)
        text = re.sub(r'\b[0-9a-f]{5,}\b', 'ADDR', text)
        text = re.sub(r'\s+', ' ', text)
        insns.append(text)
    return insns

objdump = sys.argv[1]
a = dis(objdump, sys.argv[2], int(sys.argv[3], 0), int(sys.argv[4], 0))
b = dis(objdump, sys.argv[5], int(sys.argv[6], 0), int(sys.argv[7], 0))
print(f'instructions: A={len(a)} B={len(b)}')
diff = [d for d in difflib.unified_diff(a, b, lineterm='', n=0) if not d.startswith(('---', '+++', '@@'))]
print(f'differing lines: {len(diff)}')
for d in diff[:40]:
    print('  ' + d)

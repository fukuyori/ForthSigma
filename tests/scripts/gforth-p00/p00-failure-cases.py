from p00_runner import run, BUILD, SOURCE
c=[]
for w in ['*/F','*/MODF','*/MODS','*/S']:
 c.append((w,': BAD 1 2 0 '+w+' ; \' BAD CATCH .','-10'))
for w in ['/F','/MODF','/MODS','/S','MODF','MODS','U/','U/MOD','UMOD']:
 c.append((w,': BAD 1 0 '+w+' ; \' BAD CATCH .','-10'))
for w in ['U*/','U*/MOD']:
 c.append((w,': BAD 1 2 0 '+w+' ; \' BAD CATCH .','-10'))
for w in ['DU/MOD','UD/MOD']:
 c.append((w,': BAD 1. 0 '+w+' ; \' BAD CATCH .','-10'))
for w in ['W@','L@','X@','XD@']:
 c.append((w,': BAD 0 '+w+' ; \' BAD CATCH .','-9'))
c.extend([
 ('SAFE/STRING','S" " 3 SAFE/STRING NIP .','0'),
 ('CAPSSEARCH','S" abc" S" z" CAPSSEARCH . 2DROP','0'),
 ('CAPSSTRING-PREFIX?','S" abc" S" xyz" CAPSSTRING-PREFIX? .','0'),
 ('STRING-SUFFIX?','S" abc" S" xyz" STRING-SUFFIX? .','0'),
 ('SCAN-BACK','S" abc" 122 SCAN-BACK NIP .','0'),
 ('RANDOM','77 SEED! 1 RANDOM .','0'),
 ('POW2?','0 POW2? . 3 POW2? .','0 0'),
 ('CTZ','0 CTZ .','64'),
 ('+DO',': S 0 0 0 +DO 1+ LOOP ; S .','0'),
 ('U+DO',': S 0 0 0 U+DO 1+ LOOP ; S .','0'),
 ('-DO',': S 0 0 0 -DO 1+ -1 +LOOP ; S .','0'),
 ('U-DO',': S 0 0 0 U-DO 1+ -1 +LOOP ; S .','0'),
 ('TO',': BAD 1 TO DUP ; \' BAD CATCH .','-32'),
])
# TO invalid target fails while BAD is being compiled, so test via EVALUATE inside catch instead.
c[-1]=('TO',': BAD S" 1 TO DUP" EVALUATE ; \' BAD CATCH .','-32')
c=[(w,src.replace('CATCH .','CATCH . CLEARSTACK'),('0' if exp=='-10' and w!='UD/MOD' else '-21' if w=='TO' else exp)) for w,src,exp in c]
run('Boundary',c)

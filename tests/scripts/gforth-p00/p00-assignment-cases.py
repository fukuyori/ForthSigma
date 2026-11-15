from p00_runner import run
c=[
('TO-float','1e FVALUE V 2e TO V V 2e F= .','-1'),
('TO-double','1. 2VALUE V 2. TO V V 2. D= .','-1'),
('TO-local',': S { W: a -- } 2 TO a a ; 1 S .','2'),
('TO-float-local',': S { F: a -- } 2e TO a a ; 1e S 2e F= .','-1'),
('TO-double-local',': S { D: a -- } 2. TO a a ; 1. S 2. D= .','-1'),
('TO-synonym','SYNONYM ASSIGN TO 1 VALUE V 2 ASSIGN V V .','2'),
('TO-synonym-postpone','SYNONYM ASSIGN TO 1 VALUE V : M POSTPONE ASSIGN ; IMMEDIATE : S 3 M V ; S V .','3'),
('TO-shadow',': TO 123 ; TO .','123'),
('TO-search-order',': S ONLY S" TO" FIND-NAME 0= . FORTH ; S','-1'),
('ACTION-OF-runtime',"DEFER D : A 7 ; : B 8 ; ' A IS D : GET ACTION-OF D ; ' B IS D GET EXECUTE .",'8'),
('+TO-float','1e FVALUE V 2e +TO V V 3e F= .','-1'),
('+TO-double','1. 2VALUE V 2. +TO V V 3. D= .','-1'),
('TO-missing',': BAD S" TO" EVALUATE ; \' BAD CATCH .','-16')]
run('Assignment',c)

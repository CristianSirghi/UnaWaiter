-- ===========================================================================
-- Generator: extrage definițiile formelor UnaWaiter dintr-o bază unde ele
-- EXISTĂ ȘI FUNCȚIONEAZĂ, și le emite ca apeluri `adp(...)` pentru
-- install_forme.sql.
-- ===========================================================================
-- Se rulează pe back-office-ul SURSĂ (de regulă testul, `sun@clouddev`):
--
--   sqlplus sun/sun@una.md:4024/clouddev.world @genereaza_forme.sql
--
-- Ieșirea se lipește în install_forme.sql, între antet și subsol. Fișierul ăla
-- e commis gata generat — asta e doar pentru regenerare, când formele se
-- modifică pe test și vrei să duci schimbarea mai departe.
--
-- DE CE UN GENERATOR și nu clonare din șabloane la instalare: un șablon poate
-- diferi între medii, iar o proprietate lipsă face grila read-only fără niciun
-- mesaj (exact ce s-a întâmplat cu EDITQUERY1/2/3 pe 2026-07-30). Extrase din
-- baza unde formele sunt validate, proprietățile ajung la destinație identice.
--
-- Presupuneri, verificate pe 2026-08-03 (dacă vreodată cad, generatorul trebuie
-- extins): niciun FVALUE (BLOB) și niciun DVALUE (dată) nenul, LVALUE sub 3900
-- de caractere, și niciun apostrof în valori — de aceea `q'[...]'` e suficient.
-- ===========================================================================

set lines 4000 pages 0 feed off head off trimspool on long 4000
set define off

select '  adp(' || case when obj_id = (select obj_id from a$adm where section='F_UWWAITERT')
                        then 'v_chel' else 'v_mese' end || ', '
    || 'q''[' || key || ']'', '
    || case when name    is null then 'null' else 'q''[' || name    || ']''' end || ', '
    || case when hint    is null then 'null' else 'q''[' || hint    || ']''' end || ', '
    || case when gr      is null then 'null' else 'q''[' || gr      || ']''' end || ', '
    || case when vtype   is null then 'null' else 'q''[' || vtype   || ']''' end || ', '
    || case when value0  is null then 'null' else 'q''[' || value0  || ']''' end || ', '
    || case when value1  is null then 'null' else 'q''[' || value1  || ']''' end || ', '
    || case when value2  is null then 'null' else 'q''[' || value2  || ']''' end || ', '
    || case when svalue  is null then 'null' else 'q''[' || svalue  || ']''' end || ', '
    || case when ivalue  is null then 'null' else to_char(ivalue) end || ', '
    || case when bvalue  is null then 'null' else 'q''[' || bvalue  || ']''' end || ', '
    || case when lvalue  is null then 'null' else 'q''[' || to_char(substr(lvalue,1,3900)) || ']''' end || ', '
    || case when attr    is null then 'null' else 'q''[' || attr    || ']''' end || ');'
from a$adp
where obj_id in (select obj_id from a$adm where section in ('F_UWWAITERT','F_UWPLAN'))
order by obj_id, key;

set define on

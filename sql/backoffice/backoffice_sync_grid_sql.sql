-- Sincronizeaza interogarile din CACHE-ul grilelor (A$LOB) cu definitia formei
-- (A$ADP).
--
-- DE CE E NEVOIE (descoperit 2026-07-30, pe pielea noastra):
-- XML-ul salvat de client in A$LOB nu contine doar coloanele grilei, ci si o
-- COPIE a interogarilor formei:
--     <ds ...><sql>…</sql><sqli>…</sqli><sqlu>…</sqlu><sqld>…</sqld><sqlr>…</sqlr></ds>
-- Iar clientul RULEAZA copia asta, nu ce scrie in A$ADP. Deci modifici
-- SQL_INSERT in definitie, repornesti clientul - si tot vechea varianta se
-- executa. Simptomul real care ne-a dus aici: "Not found field corresponding
-- parameter zone_code", desi parametrul fusese deja corectat in A$ADP.
--
-- Asta NUANTEAZA capcana #2 din forme.md ("definitia se citeste la pornirea
-- clientului"): e adevarat doar cat timp forma NU are inca un cache. Dupa ce
-- si-a salvat unul, cache-ul castiga.
--
-- ALTERNATIVA ar fi `delete from a$lob where obj_id = …`, dar atunci se pierd si
-- coloanele reparate si reapare grila fara capete (vezi forme/fix_grid_cols.sql).
-- De aceea sincronizam in loc sa stergem.
--
-- >>> RULEAZA-L CU FORMA INCHISA.
--
-- Nivelurile si prefixele lor:
--   grila 1 (gr01)  -> SQL, SQL_INSERT, SQL_UPDATE, SQL_DELETE, SQL_REFRESH
--   grila 2 (gr01a) -> XSQL, XSQL_INSERT, ...
--   grila 3 (gr01b) -> YSQL, YSQL_INSERT, ...

set define off
set serveroutput on size 100000

declare
  type t_map is table of varchar2(30) index by binary_integer;

  -- obj_id-urile NU mai sunt scrise de mana (era 1999, singur): se iau din
  -- a$adm dupa sectiunile noastre, deci scriptul acopera automat orice forma
  -- UnaWaiter, si cea de chelneri si cea de mese. Cand am adaugat coloana
  -- can_edit_tables in forma 1996, varianta hardcodata ar fi sincronizat tacut
  -- doar forma de mese si am fi cautat aiurea de ce 1996 ruleaza tot SQL-ul
  -- vechi - exact simptomul pentru care exista fisierul asta.
  v_obj  number;

  -- lob_name -> prefixul proprietatilor din A$ADP
  type t_grids is table of varchar2(10) index by varchar2(60);
  v_grids t_grids;
  v_lob   varchar2(60);

  v_txt   varchar2(32767);
  v_val   varchar2(32767);
  v_tag   varchar2(10);
  v_key   varchar2(40);
  v_a     number;
  v_b     number;
  v_chg   number;

  -- eticheta XML -> sufixul cheii din A$ADP
  v_tags  t_map;
  v_sufx  t_map;
begin
  v_tags(1) := 'sql';   v_sufx(1) := '';
  v_tags(2) := 'sqli';  v_sufx(2) := '_INSERT';
  v_tags(3) := 'sqlu';  v_sufx(3) := '_UPDATE';
  v_tags(4) := 'sqld';  v_sufx(4) := '_DELETE';
  v_tags(5) := 'sqlr';  v_sufx(5) := '_REFRESH';

  v_grids(':fmFS1c:gr01')  := 'SQL';
  v_grids(':fmFS1c:gr01a') := 'XSQL';
  v_grids(':fmFS1c:gr01b') := 'YSQL';

  for f in (select obj_id, name0 from a$adm
             where section in ('F_UWWAITERT','F_UWPLAN')
             order by obj_id) loop
  v_obj := f.obj_id;
  dbms_output.put_line(f.obj_id||'  '||f.name0);

  v_lob := v_grids.first;
  while v_lob is not null loop
    begin
      select utl_raw.cast_to_varchar2(dbms_lob.substr(lob_value, 30000, 1))
        into v_txt from a$lob where obj_id = v_obj and lob_name = v_lob;
    exception when no_data_found then
      dbms_output.put_line('  '||v_lob||': fara cache - se sare');
      v_lob := v_grids.next(v_lob); continue;
    end;

    v_chg := 0;
    for i in 1 .. v_tags.count loop
      v_tag := v_tags(i);
      v_key := v_grids(v_lob)||v_sufx(i);

      begin
        select svalue into v_val from a$adp where obj_id = v_obj and key = v_key;
      exception when no_data_found then v_val := null;
      end;

      -- Atingem doar etichetele care exista in cache SI au valoare in definitie.
      -- O proprietate goala se lasa cum e: nu stim daca clientul asteapta
      -- eticheta absenta sau goala, si nu e nevoie sa aflam aici.
      if v_val is not null then
        v_a := instr(v_txt, '<'||v_tag||'>');
        v_b := instr(v_txt, '</'||v_tag||'>');
        if v_a > 0 and v_b > v_a then
          if substr(v_txt, v_a + length(v_tag) + 2, v_b - v_a - length(v_tag) - 2) <> v_val then
            v_txt := substr(v_txt, 1, v_a + length(v_tag) + 1)
                     ||v_val
                     ||substr(v_txt, v_b);
            v_chg := v_chg + 1;
            dbms_output.put_line('  '||v_lob||' <'||v_tag||'> <- '||v_key);
          end if;
        end if;
      end if;
    end loop;

    if v_chg > 0 then
      update a$lob set lob_value = utl_raw.cast_to_raw(v_txt), time_stamp = sysdate
       where obj_id = v_obj and lob_name = v_lob;
    else
      dbms_output.put_line('  '||v_lob||': deja sincronizat');
    end if;

    v_lob := v_grids.next(v_lob);
  end loop;

  end loop;   -- forma urmatoare

  commit;
end;
/

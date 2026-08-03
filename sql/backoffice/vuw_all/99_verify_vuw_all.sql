-- ===========================================================================
-- VERIFICARE — sunt view-urile și triggerele din back-office pe loc?
-- ===========================================================================
-- READ-ONLY. Iese cu eroare dacă ceva lipsește.
--
--   @99_verify_vuw_all.sql 11
--   @99_verify_vuw_all.sql 11,13,17
--
-- Verifică inclusiv lucrul cel mai ușor de ratat: că fiecare view chiar poate fi
-- INTEROGAT. Un view peste un db link se creează fără nicio plângere chiar dacă
-- baza de la capăt e inaccesibilă — se află abia când managerul deschide forma.
-- ===========================================================================

set define on
set verify off
set serveroutput on size 1000000
set feedback off
whenever sqlerror exit failure

declare
  c_lista constant varchar2(400) := '&1';
  v_fail  number := 0;
  v_n     number;
  v_cod   number;

  procedure chk(p_ok boolean, p_ce varchar2, p_det varchar2 default null) is
    v_d varchar2(4000) := case when p_det is null then '' else '  (' || p_det || ')' end;
  begin
    if p_ok then
      dbms_output.put_line('  OK     ' || p_ce || v_d);
    else
      v_fail := v_fail + 1;
      dbms_output.put_line('  PICAT  ' || p_ce || v_d);
    end if;
  end;

  function e_valid(p_name varchar2, p_type varchar2) return boolean is
    n number;
  begin
    select count(*) into n from user_objects
     where object_name = p_name and object_type = p_type and status = 'VALID';
    return n > 0;
  end;

  -- Interogheaza efectiv view-ul. Un view peste db link se creeaza si daca baza
  -- de la capat e cazuta; abia SELECT-ul spune adevarul.
  function interogabil(p_view varchar2, p_cnt out number) return varchar2 is
  begin
    execute immediate 'select count(*) from ' || p_view into p_cnt;
    return null;
  exception
    when others then
      p_cnt := -1;
      return substr(sqlerrm, 1, 120);
  end;

  procedure verifica_view(p_view varchar2) is
    v_cnt number;
    v_err varchar2(200);
  begin
    chk(e_valid(upper(p_view), 'VIEW'), p_view || ' exista si e VALID');
    v_err := interogabil(p_view, v_cnt);
    chk(v_err is null, p_view || ' se poate interoga',
        case when v_err is null then v_cnt || ' randuri' else v_err end);
  end;

begin
  dbms_output.put_line(' ');
  dbms_output.put_line('===========================================================');
  dbms_output.put_line(' VERIFICARE back-office UnaWaiter — filiale: ' || c_lista);
  dbms_output.put_line(' schema ' || user || '   ' || to_char(sysdate, 'YYYY-MM-DD HH24:MI'));
  dbms_output.put_line('===========================================================');

  dbms_output.put_line(' ');
  dbms_output.put_line('--- View-uri ---------------------------------------------');
  verifica_view('vuw_waiters_all');
  verifica_view('vuw_zones_all');
  verifica_view('vuw_tables_all');
  verifica_view('vuw_locations');

  dbms_output.put_line(' ');
  dbms_output.put_line('--- Triggere INSTEAD OF ----------------------------------');
  -- Cea mai probabila cauza de lipsa: un CREATE OR REPLACE VIEW rulat fara
  -- recrearea trigger-ului. Se manifesta ca ORA-01733 la prima salvare din forma.
  for t in (select column_value nume from table(sys.odcivarchar2list(
              'TRG_VUW_WAITERS_ALL','TRG_VUW_ZONES_ALL','TRG_VUW_TABLES_ALL'))) loop
    select count(*) into v_n from user_triggers
     where trigger_name = t.nume and status = 'ENABLED' and trigger_type = 'INSTEAD OF';
    chk(v_n = 1, t.nume || ' — prezent si ENABLED');
  end loop;

  dbms_output.put_line(' ');
  dbms_output.put_line('--- Fiecare filiala ceruta apare in view-uri -------------');
  for r in (
    select trim(regexp_substr(c_lista, '[^,]+', 1, level)) buc
      from dual connect by level <= regexp_count(c_lista, ',') + 1
  ) loop
    if r.buc is null then continue; end if;
    v_cod := to_number(r.buc);

    select count(*) into v_n from ybmb_dif_cassa where cod_univ = v_cod and secondary = 0;
    chk(v_n = 1, 'filiala ' || v_cod || ' e in registrul ybmb_dif_cassa');

    begin
      execute immediate 'select count(*) from vuw_locations where cod_univ = :1'
        into v_n using v_cod;
      chk(v_n = 1, 'filiala ' || v_cod || ' apare in vuw_locations');
    exception
      when others then chk(false, 'filiala ' || v_cod || ' in vuw_locations', sqlerrm);
    end;
  end loop;

  dbms_output.put_line(' ');
  dbms_output.put_line('--- Formele ----------------------------------------------');
  select count(*) into v_n from a$adm where section = 'F_UWWAITERT';
  chk(v_n = 1, 'forma „Chelneri UnaWaiter" (F_UWWAITERT)');
  select count(*) into v_n from a$adm where section = 'F_UWPLAN';
  chk(v_n = 1, 'forma „Amplasare mese" (F_UWPLAN)');

  dbms_output.put_line(' ');
  dbms_output.put_line('===========================================================');
  if v_fail = 0 then
    dbms_output.put_line(' REZULTAT: TOTUL E PE LOC');
    dbms_output.put_line('===========================================================');
  else
    dbms_output.put_line(' REZULTAT: ' || v_fail || ' VERIFICARI PICATE');
    dbms_output.put_line('===========================================================');
    raise_application_error(-20091,
      'Verificare picata: ' || v_fail || ' probleme. Vezi lista de mai sus.');
  end if;
end;
/

set feedback on

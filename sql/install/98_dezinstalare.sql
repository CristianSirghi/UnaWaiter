-- ===========================================================================
-- DEZINSTALARE — șterge obiectele UnaWaiter de pe un front
-- ===========================================================================
--
--   sqlplus unirest/unirest@<gazda>:1521/xe @98_dezinstalare.sql DA-STERG
--
-- ⚠️ ȘTERGE DATE. Cele cinci tabele UW_* dispar cu tot conținutul: alocarea
-- chelnerilor la restaurant, PIN-urile lor, mesele, zonele și evidența bonurilor
-- fiscale emise din aplicație.
--
-- Argumentul `DA-STERG` e obligatoriu și există tocmai ca scriptul să nu poată fi
-- rulat din reflex sau dintr-un istoric de comenzi.
--
-- DE CE EXISTĂ: dacă instalarea pică la jumătate, rămân niște tabele create, iar
-- a doua încercare cade cu „name is already used by an existing object" — fără
-- asta n-ar fi nimic cu care să cureți înainte de o nouă rulare. Folosit și
-- pentru repetiția instalării pe test.
--
-- NU ATINGE NIMIC DIN UAMenu. `TMDB_COMENZ` (comenzile), meniul, chelnerii din
-- `VMS_UNIVERS`, tura din `TMDB_SOLD` — niciuna nu e obiect de-al nostru.
-- Comenzile deja trimise din aplicație rămân neatinse; se pierde doar evidența
-- NOASTRĂ despre bonurile fiscale (`uw_fiscal_receipts`).
--
-- FĂRĂ `PURGE`, intenționat: tabelele ajung în coșul Oracle (recycle bin), deci
-- mai există o plasă de siguranță câteva ore. Recuperare:
--   SELECT object_name, original_name, droptime FROM recyclebin;
--   FLASHBACK TABLE uw_waiters TO BEFORE DROP;
-- ===========================================================================

set define on
set verify off
set serveroutput on size 1000000
whenever sqlerror exit failure

declare
  c_confirm constant varchar2(30) := '&1';
  v_sters   number := 0;

  procedure sterge(p_tip varchar2, p_nume varchar2) is
  begin
    execute immediate 'DROP ' || p_tip || ' ' || p_nume ||
                      case when p_tip = 'TABLE' then ' CASCADE CONSTRAINTS' end;
    v_sters := v_sters + 1;
    dbms_output.put_line('  sters   ' || rpad(p_tip, 14) || p_nume);
  exception
    -- ORA-00942 tabela/view inexistent, ORA-04043 obiect inexistent:
    -- dezinstalarea trebuie sa mearga si dupa o instalare picata la jumatate.
    when others then
      if sqlcode in (-942, -4043) then
        dbms_output.put_line('  lipsea  ' || rpad(p_tip, 14) || p_nume);
      else
        raise;
      end if;
  end;

begin
  if c_confirm <> 'DA-STERG' then
    raise_application_error(-20095,
      'Confirmare lipsa. Ruleaza: @98_dezinstalare.sql DA-STERG');
  end if;

  dbms_output.put_line(' ');
  dbms_output.put_line('DEZINSTALARE UnaWaiter din schema ' || user ||
                       ' @ ' || sys_context('userenv','db_name'));
  dbms_output.put_line(' ');

  -- Ordinea conteaza: intai ce DEPINDE, apoi ce e depins.
  sterge('VIEW',         'vuw_tables');
  sterge('VIEW',         'vuw_zones');
  sterge('VIEW',         'vuw_waiters');

  sterge('PACKAGE',      'pg_mobile_web_waiter');

  -- CASCADE CONSTRAINTS scoate si cheia straina uw_tables -> uw_zones,
  -- altfel uw_zones n-ar putea fi stearsa cat timp exista mesele.
  sterge('TABLE',        'uw_tables');
  sterge('TABLE',        'uw_zones');
  sterge('TABLE',        'uw_waiters');
  sterge('TABLE',        'uw_fiscal_receipts');
  sterge('TABLE',        'uw_fiscal_incidents');

  dbms_output.put_line(' ');
  dbms_output.put_line('Gata: ' || v_sters || ' obiecte sterse.');
  dbms_output.put_line('Reinstalare: @00_install_front.sql <cod_univ>');
  dbms_output.put_line('Datele vechi (daca ai backup): sql/backup/restore_test_*.sql');
end;
/

-- Fara EXIT, sqlplus ramane la prompt dupa ce scriptul se termina, iar
-- install_front.bat/rularea automata atarna la nesfarsit (prins la repetitia
-- din 2026-08-03).
EXIT SUCCESS

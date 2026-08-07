-- ===========================================================================
-- UPGRADE formă — coloana „Poate edita mese" în „13. Chelneri UnaWaiter"
-- ===========================================================================
-- Pentru back-office-urile unde forma EXISTĂ deja. La o instalare nouă nu e
-- nevoie: `install_forme.sql` scrie deja interogările cu `can_edit_tables`.
--
--   cd sql/backoffice/forme
--   sqlplus sun/sun@//una.md:4024/clouddev.world @upgrade_2026-08-07_can_edit_tables.sql
--
-- `install_forme.sql` REFUZĂ să ruleze peste o formă existentă (ORA-20080), și
-- bine face — ar șterge și aranjarea coloanelor. De aceea upgrade-ul atinge doar
-- cele 4 interogări ale grilei de chelneri.
--
-- ⚠️ ORDINEA CONTEAZĂ, și tot fișierul ăsta e despre ea:
--   1. a$adp   — definiția formei
--   2. sync    — copia din a$lob, pe care clientul chiar o rulează (capcana #1
--                din backoffice_sync_grid_sql.sql: modifici definiția, repornești
--                clientul, și tot varianta veche se execută)
--   3. coloane — fix_grid_cols.sql, altfel coloana nouă nu apare în grilă
--
-- >>> RULEAZĂ-L CU FORMA ÎNCHISĂ, și repornește UniacCLNT.exe după.
--
-- IDEMPOTENT: rulat de două ori nu strică nimic (scrie aceleași valori).
--
-- ⚠️ Frontul trebuie să aibă DEJA coloana (`upgrade_2026-08-07_can_edit_tables.sql`
-- din sql/install), altfel `vuw_waiters_all` nu o are și forma cade la deschidere.
-- Verificarea de la final o prinde.
-- ===========================================================================

set define off
set serveroutput on size 100000
whenever sqlerror exit failure

declare
  v_obj number;
  v_n   number;

  -- Textele sunt IDENTICE cu cele din install_forme.sql. Dacă schimbi unul,
  -- schimbă-l în ambele: o instalare nouă citește de acolo, una existentă de
  -- aici, iar două forme care rulează SQL diferit e exact genul de divergență
  -- care se descoperă abia la client.
  c_sql     constant varchar2(1000) := 'select cod_univ, oficiant, clcoficiantt, pin, active, can_edit_tables from vuw_waiters_all where cod_univ = :cod_univ order by oficiant';
  c_insert  constant varchar2(1000) := 'insert into vuw_waiters_all (cod_univ, oficiant, pin, active, can_edit_tables) values (:cod_univ, :oficiant, :pin, :active, :can_edit_tables)';
  c_refresh constant varchar2(1000) := 'select cod_univ, oficiant, clcoficiantt, pin, active, can_edit_tables from vuw_waiters_all where cod_univ = :cod_univ and oficiant = :oficiant';
  c_update  constant varchar2(1000) := 'update vuw_waiters_all set pin = :pin, active = :active, can_edit_tables = :can_edit_tables where cod_univ = :cod_univ and oficiant = :oficiant';

  -- SVALUE **și** LVALUE: Configuratorul scrie SVALUE, clientul citește SVALUE,
  -- dar install_forme.sql le pune pe amândouă. Scrisă doar una, în bază pare
  -- corect și clientul rulează altceva (capcana #1 din forme.md).
  procedure pune(p_key varchar2, p_val varchar2) is
  begin
    update a$adp set svalue = p_val, lvalue = p_val
     where obj_id = v_obj and key = p_key;
    if sql%rowcount = 0 then
      raise_application_error(-20081,
        'Proprietatea '||p_key||' nu exista pe forma '||v_obj||
        ' - forma nu arata cum ne asteptam, oprim ca sa nu stricam altceva.');
    end if;
    dbms_output.put_line('  '||rpad(p_key, 14)||' actualizata');
  end;
begin
  select obj_id into v_obj from a$adm where section = 'F_UWWAITERT';

  dbms_output.put_line('Forma de chelneri: obj_id '||v_obj);
  pune('XSQL',         c_sql);
  pune('XSQL_INSERT',  c_insert);
  pune('XSQL_REFRESH', c_refresh);
  pune('XSQL_UPDATE',  c_update);
  commit;

  -- Frontul trebuie sa fi primit deja coloana. Verificat prin view-ul unificat,
  -- adica exact pe drumul pe care merge si forma.
  begin
    execute immediate 'select count(*) from (select can_edit_tables from vuw_waiters_all where 1=0)'
      into v_n;
    dbms_output.put_line('  vuw_waiters_all are can_edit_tables - OK');
  exception when others then
    raise_application_error(-20082,
      'vuw_waiters_all NU are coloana can_edit_tables. Ruleaza intai upgrade-ul '||
      'de pe front (sql/install/upgrade_2026-08-07_can_edit_tables.sql) si apoi '||
      'vuw_all/00_install_vuw_all.sql. ('||sqlerrm||')');
  end;
exception
  when no_data_found then
    raise_application_error(-20083,
      'Nu exista forma cu section = F_UWWAITERT in baza asta. '||
      'Instaleaz-o intai cu install_forme.sql.');
end;
/

prompt
prompt --- sincronizare cache-ul grilelor (a$lob <- a$adp):
@@../backoffice_sync_grid_sql.sql

prompt
prompt --- coloanele grilelor (adauga "Poate edita mese"):
@@fix_grid_cols.sql

prompt
prompt ===========================================================
prompt  Gata. REPORNESTE UniacCLNT.exe - definitia formei se
prompt  citeste la pornirea clientului, nu la deschiderea ferestrei.
prompt ===========================================================
prompt

exit success

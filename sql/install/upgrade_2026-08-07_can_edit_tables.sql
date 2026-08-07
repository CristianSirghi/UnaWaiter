-- ===========================================================================
-- UPGRADE — dreptul de a schimba mesele din aplicație (can_edit_tables)
-- ===========================================================================
-- Pentru bazele pe care UnaWaiter e DEJA instalat (frontul de test, și oricare
-- producție instalată înainte de 2026-08-07). Instalările NOI nu au nevoie de
-- el: `03_uw_waiters.sql` creează deja coloana.
--
--   cd sql/install
--   sqlplus foishor_riscani_unirest/...@una.md:4024/clouddev.world
--   SQL> @upgrade_2026-08-07_can_edit_tables.sql
--
-- ⚠️ Stă în ACELAȘI folder cu `07_`/`08_`/`09_`, nu într-un subfolder, tocmai
-- ca `@@` să le găsească. Încercarea cu `@@07_vuw_views.sql` dintr-un
-- subfolder `upgrade/` a eșuat cu SP2-0310 — iar SP2-0310 nu declanșează
-- `WHENEVER SQLERROR` (aceeași capcană ca la seed-ul lipsă din
-- `00_install_front.sql`), deci scriptul ar fi mers mai departe fără să
-- recompileze nimic. Aici a fost prins doar de verificarea de la final.
--
-- IDEMPOTENT: rulat de două ori, a doua oară nu face nimic și nu dă eroare.
-- Nu atinge niciun rând existent — coloana intră cu DEFAULT 0, adică „niciun
-- chelner nu poate schimba mesele", exact starea de dinainte.
--
-- ⚠️ DUPĂ ALTER trebuie RECOMPILATE view-ul și pachetul, altfel `vuw_waiters`
-- rămâne fără coloană (deci forma din back-office n-o vede) și pachetul e
-- INVALID — `log_in` referă `w.can_edit_tables`, care încă nu există în corpul
-- compilat. Scriptul le rulează singur, tocmai ca să nu rămână pe jumătate.
-- ===========================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET SQLBLANKLINES ON
SET FEEDBACK OFF
WHENEVER SQLERROR EXIT FAILURE

PROMPT
PROMPT --- 1/3  coloana can_edit_tables pe UW_WAITERS:

DECLARE
  v_n NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_n FROM user_tab_columns
   WHERE table_name = 'UW_WAITERS' AND column_name = 'CAN_EDIT_TABLES';

  IF v_n > 0 THEN
    DBMS_OUTPUT.PUT_LINE('  exista deja - nimic de facut');
  ELSE
    -- NOT NULL cu DEFAULT într-un singur ALTER: pe rândurile existente Oracle
    -- pune 0 fără să rescrie blocurile (default-uri "metadata-only" de la 11g),
    -- deci merge instant și pe un tabel cu multe rânduri.
    EXECUTE IMMEDIATE
      'ALTER TABLE uw_waiters ADD can_edit_tables NUMBER(1) DEFAULT 0 NOT NULL';
    DBMS_OUTPUT.PUT_LINE('  adaugata (toti chelnerii existenti raman cu 0)');
  END IF;

  SELECT COUNT(*) INTO v_n FROM user_constraints
   WHERE constraint_name = 'UW_WAITERS_EDIT_CK';
  IF v_n > 0 THEN
    DBMS_OUTPUT.PUT_LINE('  CHECK-ul exista deja');
  ELSE
    EXECUTE IMMEDIATE
      'ALTER TABLE uw_waiters ADD CONSTRAINT uw_waiters_edit_ck '||
      'CHECK (can_edit_tables IN (0,1))';
    DBMS_OUTPUT.PUT_LINE('  CHECK adaugat');
  END IF;
END;
/

PROMPT
PROMPT --- 2/3  view-urile VUW_* (vuw_waiters capata coloana):
@@07_vuw_views.sql

PROMPT
PROMPT --- 3/3  pachetul (log_in intoarce flagul, add_table/set_table_active noi):
@@08_pachet_spec.sql
SHOW ERRORS PACKAGE pg_mobile_web_waiter
@@09_pachet_body.sql
SHOW ERRORS PACKAGE BODY pg_mobile_web_waiter

-- SHOW ERRORS e obligatoriu: un pachet care nu compileaza NU produce SQLERROR,
-- sqlplus scrie doar "Warning: ... with compilation errors" si merge mai
-- departe. Blocul de mai jos e cel care chiar opreste.
DECLARE
  v_n NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_n FROM user_objects
   WHERE object_name = 'PG_MOBILE_WEB_WAITER' AND status = 'VALID';
  IF v_n < 2 THEN
    RAISE_APPLICATION_ERROR(-20093,
      'Pachetul nu e valid dupa upgrade (spec+body valide: '||v_n||' din 2). '||
      'Vezi erorile de mai sus.');
  END IF;
END;
/

PROMPT
PROMPT ===========================================================
PROMPT  Upgrade incheiat. Dreptul se da din forma "13. Chelneri
PROMPT  UnaWaiter" din back-office, coloana "Poate edita mese".
PROMPT  Nu uita si partea de back-office: 00_install_vuw_all.sql
PROMPT  (view + trigger) si install_forme/fix_grid_cols.
PROMPT ===========================================================
PROMPT

EXIT SUCCESS

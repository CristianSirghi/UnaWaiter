-- ===========================================================================
-- INSTALATORUL UnaWaiter pentru UN FRONT (baza unui restaurant)
-- ===========================================================================
-- Rulează toate scripturile în ordinea corectă, pe conexiunea curentă.
--
-- NU se rulează direct — folosește install_front.bat, care se ocupă de conexiune
-- și de log. Dacă totuși îl rulezi de mână:
--
--   sqlplus unirest/unirest@93.116.209.117:1521/xe
--   SQL> @00_install_front.sql 11
--
-- Argumentul e COD_UNIV — filiala din vms_univers (gr1='FL'). Determină ce seed
-- se rulează și pe ce filială se face verificarea.
--   11 MIRON COSTIN | 12 MEGAPOLIS | 13 COLUMNA | 16 ALECO RUSSO | 17 M. cel BATRIN
--
-- ---------------------------------------------------------------------------
-- ORDINEA NU E ARBITRARĂ:
--   tabele → SEED → chei străine → view-uri → pachet
-- Cheia străină mese→zone se pune peste rânduri deja inserate, deci trebuie să
-- vină DUPĂ seed, altfel cade cu ORA-02298. Vezi 06_chei_straine.sql.
-- ===========================================================================

DEFINE cod_univ = &1

WHENEVER SQLERROR EXIT FAILURE
WHENEVER OSERROR  EXIT FAILURE
SET ECHO OFF
SET FEEDBACK ON
SET SQLBLANKLINES ON
SET DEFINE ON
SET SERVEROUTPUT ON SIZE UNLIMITED

-- SQLBLANKLINES: corpul pachetului conține linii goale în interiorul blocurilor
-- PL/SQL. Fără asta, sqlplus taie comanda la prima linie goală și pachetul se
-- compilează trunchiat — sau, mai rău, rămâne tăcut cel vechi.
--
-- WHENEVER SQLERROR EXIT FAILURE e cea mai importantă linie din fișier: fără ea
-- sqlplus trece peste o eroare și continuă, iar la final ai crede că s-a
-- instalat, deși lipsește o tabelă din mijloc.

PROMPT
PROMPT ===========================================================
PROMPT  UnaWaiter - instalare pe front, filiala &cod_univ
PROMPT ===========================================================
PROMPT

PROMPT --- 01 uw_zones (structura):
@@01_uw_zones.sql

PROMPT --- 02 uw_tables (structura):
@@02_uw_tables.sql

PROMPT --- 03 uw_waiters:
@@03_uw_waiters.sql

PROMPT --- 04 uw_fiscal_receipts (cu RRN):
@@04_uw_fiscal_receipts.sql

PROMPT --- 05 uw_fiscal_incidents:
@@05_uw_fiscal_incidents.sql

PROMPT --- seed: zonele si mesele filialei &cod_univ:
@@seed/seed_&cod_univ..sql

-- ⚠️ SP2-0310 (fisier de seed inexistent) NU declanseaza WHENEVER SQLERROR:
-- sqlplus tipareste eroarea, MERGE MAI DEPARTE si iese cu cod 0. Verificat pe
-- 2026-08-04. Fara blocul asta, o filiala fara seed se instala fara zone si
-- fara mese, iar esecul aparea abia la 99_verify ca "zone definite: PICAT" -
-- din care nimeni nu deduce ca lipsea un fisier de la mijloc.
DECLARE
  v_zone NUMBER;
  v_mese NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_zone FROM uw_zones  WHERE cod_univ = &cod_univ;
  SELECT COUNT(*) INTO v_mese FROM uw_tables WHERE cod_univ = &cod_univ;
  IF v_zone = 0 OR v_mese = 0 THEN
    RAISE_APPLICATION_ERROR(-20092,
      'Lipseste sau e gol seed/seed_&cod_univ..sql (zone=' || v_zone ||
      ', mese=' || v_mese || '). Cere clientului numerele reale de mese si ' ||
      'impartirea pe zone, apoi scrie fisierul dupa modelul seed_11.sql.');
  END IF;
END;
/

PROMPT --- 06 chei straine (DUPA seed):
@@06_chei_straine.sql

PROMPT --- 07 view-uri VUW_*:
@@07_vuw_views.sql

PROMPT --- 08 pachet: specificatia:
@@08_pachet_spec.sql
SHOW ERRORS PACKAGE pg_mobile_web_waiter

PROMPT --- 09 pachet: corpul:
@@09_pachet_body.sql
SHOW ERRORS PACKAGE BODY pg_mobile_web_waiter

-- SHOW ERRORS e necesar pentru că un pachet care nu compilează NU produce
-- SQLERROR — sqlplus zice doar "Warning: Package Body created with compilation
-- errors" și merge mai departe. Verificarea de mai jos e cea care chiar oprește.

PROMPT
PROMPT --- verificare finala:
@@99_verify.sql &cod_univ

PROMPT
PROMPT ===========================================================
PROMPT  Instalare incheiata cu succes pentru filiala &cod_univ
PROMPT ===========================================================
PROMPT

-- Vezi nota din 98_dezinstalare.sql: fara EXIT, .bat-ul atarna.
EXIT SUCCESS

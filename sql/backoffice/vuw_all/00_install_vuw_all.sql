-- ===========================================================================
-- Back-office UnaWaiter — view-urile unificate + triggerele lor
-- ===========================================================================
--   sqlplus foishor/<parola>@una.md:4024/cloudbd.world @00_install_vuw_all.sql 11
--   sqlplus sun/sun@una.md:4024/clouddev.world        @00_install_vuw_all.sql 11
--
-- Argumentul e lista de filiale INSTALATE, separate prin virgulă, fără spații:
--   11          pilot doar la Rîșcani
--   11,13,17    toate trei
--
-- Se rulează și la prima instalare, și de fiecare dată când se adaugă un
-- restaurant. Nu e nimic de decomentat și nimic de editat — doar lista se
-- schimbă. Rularea repetată e sigură: toate obiectele sunt `CREATE OR REPLACE`.
--
-- ---------------------------------------------------------------------------
-- ORDINEA NU E NEGOCIABILĂ: view-uri, apoi TRIGGERE, în aceeași rulare.
-- `CREATE OR REPLACE VIEW` șterge trigger-ul INSTEAD OF. Dacă rulezi doar 01 și
-- te oprești, formele arată datele dar orice salvare cade cu ORA-01733 —
-- un mesaj din care nimeni nu deduce că lipsește un trigger.
-- ---------------------------------------------------------------------------
--
-- CE TREBUIE SĂ EXISTE ÎNAINTE:
--   * pe fiecare front din listă: tabelele UW_* și view-urile VUW_* (vezi
--     sql/install/) — altfel view-urile de aici se creează, dar nu se pot
--     interoga, iar 99_verify_vuw_all.sql o va spune;
--   * db link-urile din `ybmb_dif_cassa` (există deja, sunt ale UAMenu).
--
-- DUPĂ: formele — sql/backoffice/forme/install_forme.sql
-- ===========================================================================

whenever sqlerror exit failure
whenever oserror  exit failure
set echo off
set feedback on
set serveroutput on size 1000000

prompt
prompt ===========================================================
prompt  Back-office UnaWaiter — filiale: &1
prompt ===========================================================
prompt

prompt --- 01: view-urile unificate:
@@01_views.sql &1

prompt
prompt --- 02: triggerele INSTEAD OF (obligatoriu dupa 01):
@@02_triggers.sql

prompt
prompt --- verificare:
@@99_verify_vuw_all.sql &1

prompt
prompt ===========================================================
prompt  Gata. Urmeaza formele: ../forme/install_forme.sql
prompt ===========================================================
prompt

-- Fara EXIT, sqlplus ramane la prompt si .bat-ul pare blocat.
EXIT SUCCESS

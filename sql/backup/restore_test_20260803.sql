-- ===========================================================================
-- BACKUP al datelor UnaWaiter de pe frontul de TEST (clouddev)
-- Generat automat: 2026-08-03, inainte de repetitia instalarii.
-- ===========================================================================
-- Restaureaza CONTINUTUL celor 5 tabele UW_*. Structura si pachetul se refac
-- ruland instalatorul (sql/install/), deci ordinea de restaurare completa e:
--
--   1. install_front.bat  (sau 00_install_front.sql) - creeaza tot
--   2. fisierul asta                                 - pune datele vechi inapoi
--
-- Fisierul STERGE inainte de a insera, deci se poate rula si peste seed-ul nou:
-- rezultatul e exact starea de dinainte de repetitie.
--
-- NU contine TMDB_COMENZ si nici alte tabele UAMenu - repetitia nu le atinge.
-- ===========================================================================

set define off
whenever sqlerror exit failure

DELETE FROM uw_fiscal_incidents;
DELETE FROM uw_fiscal_receipts;
DELETE FROM uw_tables;
DELETE FROM uw_zones;
DELETE FROM uw_waiters;

-- ---------------------------------------------------------- uw_zones ---
INSERT INTO uw_zones (cod_univ, zone_code, name_ro, name_ru, name_en, display_order, active) VALUES (11, 'hall', 'Sala', 'Зал', 'Hall', 1, 1);
INSERT INTO uw_zones (cod_univ, zone_code, name_ro, name_ru, name_en, display_order, active) VALUES (11, 'terrace', 'Terasa', 'Терраса', 'Terrace', 2, 1);

-- --------------------------------------------------------- uw_tables ---
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 1, 'hall', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 2, 'hall', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 3, 'hall', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 4, 'hall', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 5, 'hall', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 6, 'hall', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 7, 'hall', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 8, 'hall', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 9, 'hall', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 10, 'hall', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 11, 'hall', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 12, 'hall', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 13, 'terrace', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 14, 'terrace', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 15, 'terrace', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 16, 'terrace', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 17, 'terrace', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 18, 'terrace', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 19, 'terrace', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 20, 'terrace', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 21, 'terrace', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 22, 'terrace', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 23, 'terrace', NULL, 1);
INSERT INTO uw_tables (cod_univ, table_no, zone, display_order, active) VALUES (11, 24, 'terrace', NULL, 1);

-- -------------------------------------------------------- uw_waiters ---
INSERT INTO uw_waiters (cod_univ, oficiant, pin, active) VALUES (11, 6102, '1111', 1);
INSERT INTO uw_waiters (cod_univ, oficiant, pin, active) VALUES (11, 6983, '1111', 1);
INSERT INTO uw_waiters (cod_univ, oficiant, pin, active) VALUES (11, 8840, '1111', 1);
INSERT INTO uw_waiters (cod_univ, oficiant, pin, active) VALUES (11, 9577, '1111', 1);

-- ------------------------------------------------ uw_fiscal_receipts ---
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382762, 'DOC-TEST-001', 1, 4, 8360, TO_DATE('2026-07-27 17:20:53', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382763, 'DOC-TEST-002', 2, 6, 8360, TO_DATE('2026-07-27 17:20:53', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382765, 'DOC-TEST-003', 2, 2, 8360, TO_DATE('2026-07-27 17:29:09', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382766, '2509', 1, 62, 6983, TO_DATE('2026-07-27 18:37:17', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382767, '2510', 2, 124, 6983, TO_DATE('2026-07-27 18:38:58', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382768, '2511', 2, 44, 6983, TO_DATE('2026-07-27 18:43:47', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382769, '2512', 2, 54, 6983, TO_DATE('2026-07-27 18:44:34', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382770, '2513', 2, 68, 6983, TO_DATE('2026-07-27 18:45:15', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382771, '2515', 2, 54, 6983, TO_DATE('2026-07-27 18:49:35', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382772, '2517', 1, 84, 6983, TO_DATE('2026-07-27 18:51:00', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382773, '2519', 1, 114, 6983, TO_DATE('2026-07-27 18:53:25', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382775, '2521', 1, 128, 6983, TO_DATE('2026-07-27 19:13:23', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382776, '2522', 2, 68, 6983, TO_DATE('2026-07-27 19:14:03', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382778, '2524', 2, 155, 6983, TO_DATE('2026-07-28 15:09:50', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382779, '2523', 1, 304, 6983, TO_DATE('2026-07-28 15:07:47', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382781, '2526', 2, 106, 6983, TO_DATE('2026-07-28 16:06:43', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382783, '2525', 1, 150, 6983, TO_DATE('2026-07-28 16:04:14', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382785, '2527', 1, 294, 6983, TO_DATE('2026-07-28 16:14:07', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382790, '2528', 1, 113, 6102, TO_DATE('2026-07-28 17:05:26', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382808, NULL, 1, 2, NULL, TO_DATE('2026-07-29 16:43:38', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382826, '2531', 1, 60, 6983, TO_DATE('2026-08-01 11:55:08', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382827, 'TEST-HAPPY-1', 1, 16, 8360, TO_DATE('2026-08-01 11:36:30', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382828, '2532', 2, 108, 6983, TO_DATE('2026-08-01 11:56:07', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382829, '2533', 1, 188, 6983, TO_DATE('2026-08-01 11:59:08', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382830, '2534', 1, 32, 6983, TO_DATE('2026-08-01 11:59:39', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382831, '2535', 1, 114, 6983, TO_DATE('2026-08-01 12:28:38', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382832, '2536', 1, 92, 6983, TO_DATE('2026-08-01 12:29:30', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382836, '2537', 1, 62, 6983, TO_DATE('2026-08-03 09:57:08', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382837, '2538', 1, 46, 6983, TO_DATE('2026-08-03 10:28:16', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382838, '2539', 1, 68, 6983, TO_DATE('2026-08-03 10:28:30', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382839, '2540', 2, 68, 6983, TO_DATE('2026-08-03 10:29:24', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382840, '2541', 1, 54, 6983, TO_DATE('2026-08-03 10:29:56', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382841, '2542', 1, 124, 6983, TO_DATE('2026-08-03 10:31:45', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382842, '2543', 1, 60, 6983, TO_DATE('2026-08-03 10:35:51', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382843, '2544', 2, 38, 6983, TO_DATE('2026-08-03 10:59:49', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382844, '2545', 2, 70, 6983, TO_DATE('2026-08-03 11:07:07', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382846, '2546', 1, 47, 6983, TO_DATE('2026-08-03 11:28:15', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382847, '2547', 1, 62, 6983, TO_DATE('2026-08-03 12:01:20', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382849, '2548', 1, 70, 6983, TO_DATE('2026-08-03 12:07:56', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382856, '2549', 1, 54, 6983, TO_DATE('2026-08-03 14:11:55', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382857, '2550', 1, 48, 6983, TO_DATE('2026-08-03 14:15:36', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382858, '2551', 1, 48, 6983, TO_DATE('2026-08-03 14:28:39', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382860, '2552', 1, 16, 6983, TO_DATE('2026-08-03 14:45:04', 'YYYY-MM-DD HH24:MI:SS'), NULL);
INSERT INTO uw_fiscal_receipts (nr_comand, document_number, pay_type, amount, oficiant, printed_at, rrn) VALUES (382862, '2553', 1, 16, 6983, TO_DATE('2026-08-03 14:54:07', 'YYYY-MM-DD HH24:MI:SS'), NULL);

COMMIT;

-- Verificare dupa restaurare (asteptat: 2 / 24 / 4 / 44 / 0):
--   SELECT (SELECT COUNT(*) FROM uw_zones)     zone,
--          (SELECT COUNT(*) FROM uw_tables)    mese,
--          (SELECT COUNT(*) FROM uw_waiters)   chelneri,
--          (SELECT COUNT(*) FROM uw_fiscal_receipts) bonuri,
--          (SELECT COUNT(*) FROM uw_fiscal_incidents) incidente FROM dual;

-- Fara EXIT, sqlplus ramane la prompt si .bat-ul pare blocat.
EXIT SUCCESS

-- ===========================================================================
-- 07 — View-urile de citire pentru formele din back-office
-- ===========================================================================
-- Se creează pe FIECARE front (baza restaurantului), acolo unde stau tabelele.
-- Forma din back-office le citește prin db link (`vuw_waiters@RISCANI.WORLD`),
-- dar SCRIE direct în tabelul de bază prin trigger-ul INSTEAD OF de acolo — un
-- view cu join-uri nu e actualizabil.
--
-- De ce nu stau tabelele central în back-office, cu replicare spre fronturi:
-- replicarea prin materialized view e ON DEMAND și în practică învechită cu
-- săptămâni (măsurat 2026-08-03: MVSLRPRM_CALCD ultimul refresh 01.07 pe Rîșcani,
-- 20.07 pe Columna, 02.08 pe M.cel Bătrîn). Pentru date de logare e inacceptabil —
-- un chelner și-ar seta PIN-ul și n-ar putea intra până la următorul refresh.
--
-- Denumirea coloanelor urmează convenția bazei, nu inventată de noi:
--   * coloană derivată = CLC + coloana-sursă + T  (ex. TMDB_COMENZ.CLCOFICIANTT)
--   * flag = IS… cu 'Y'/'N'                       (ex. VMS_UNIVERS.ISARHIV)
--   * view peste tabel = V + numele tabelului     (TMS_UNIVERS → VMS_UNIVERS)

CREATE OR REPLACE VIEW vuw_waiters AS
SELECT w.cod_univ,
       w.oficiant,
       w.pin,
       w.active,
       w.can_edit_tables,                          -- 1 = poate schimba mesele din app
       u.denumirea AS clcoficiantt,                -- nume live din POS
       f.denumirea AS clccod_univt,                -- denumirea filialei
       NVL2(w.pin, 'Y', 'N')    AS ispin,          -- Y = înrolat
       CASE WHEN EXISTS (SELECT 1 FROM vslrprm_calcd_r_502 p WHERE p.sc_munc = w.oficiant)
            THEN 'Y' ELSE 'N' END AS isangajat     -- N = a plecat din firmă
  FROM uw_waiters w
  LEFT JOIN vms_univers u ON u.cod = w.oficiant AND u.tip = 'O' AND u.gr1 = 'R'
  LEFT JOIN vms_univers f ON f.cod = w.cod_univ AND f.gr1 = 'FL';

-- ISANGAJAT există tocmai pentru că numele nu se copiază local: un chelner care a
-- plecat din firmă rămâne fără nume în listă, iar flagul spune de ce.

CREATE OR REPLACE VIEW vuw_zones AS
SELECT z.cod_univ,
       z.zone_code,
       z.name_ro,
       z.name_ru,
       z.name_en,
       z.display_order,
       z.active,
       f.denumirea AS clccod_univt,                  -- denumirea filialei
       (SELECT COUNT(*) FROM uw_tables t
         WHERE t.cod_univ = z.cod_univ AND t.zone = z.zone_code)
                   AS clcnrmese                      -- câte mese are zona
  FROM uw_zones z
  LEFT JOIN vms_univers f ON f.cod = z.cod_univ AND f.gr1 = 'FL';

-- CLCNRMESE e pentru forma din back-office: fără el, managerul ar afla că o zonă
-- nu se poate șterge abia din eroarea cheii străine.

CREATE OR REPLACE VIEW vuw_tables AS
SELECT t.cod_univ,
       t.table_no,
       t.zone,
       t.display_order,
       t.active,
       f.denumirea AS clccod_univt,
       z.name_ro   AS clczonet                       -- denumirea zonei
  FROM uw_tables t
  LEFT JOIN vms_univers f ON f.cod = t.cod_univ AND f.gr1 = 'FL'
  LEFT JOIN uw_zones z ON z.cod_univ = t.cod_univ AND z.zone_code = t.zone;

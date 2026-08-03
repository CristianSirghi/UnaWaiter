-- ===========================================================================
-- 02 — UW_TABLES: dicționarul de mese
-- ===========================================================================
-- STRUCTURĂ DOAR. Mesele concrete sunt în seed/seed_<NN>.sql.
--
-- UAMenu n-are NICIUN dicționar de mese: TMDB_COMENZ.DESK e un număr brut, fără
-- lookup nicăieri (căutat 2026-07-13 după %DESK%/%MASA%/%STOL%/%SALA%). Deci
-- tabelul ăsta e sursa de adevăr, nu o copie a ceva.
--
-- table_no e unic în cadrul unui restaurant, nu pe tot lanțul — de aceea cheia
-- primară e (cod_univ, table_no): două restaurante pot avea fiecare masa 5.

CREATE TABLE uw_tables (
    cod_univ      NUMBER NOT NULL,         -- filiala — vezi 01_uw_zones.sql
    table_no      NUMBER NOT NULL,         -- numărul mesei, unic în restaurant
    zone          VARCHAR2(20) NOT NULL,   -- cod de zonă — vezi uw_zones.zone_code
    display_order NUMBER,                  -- sortare în zonă; NULL = după table_no
    active        NUMBER(1) DEFAULT 1 NOT NULL,
    CONSTRAINT uw_tables_pk PRIMARY KEY (cod_univ, table_no),
    CONSTRAINT uw_tables_active_ck CHECK (active IN (0,1))
);

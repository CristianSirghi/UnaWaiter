-- Migrarea rulata pe TEST (foishor_riscani_unirest@clouddev) pe 2026-07-29.
-- Aduce uw_waiters/uw_tables de la "un singur restaurant implicit" la
-- "multi-restaurant", si adauga verificarile de PIN.
--
-- ATENTIE la rulare pe alta baza: valoarea 11 de mai jos e codul filialei
-- MIRON COSTIN. Inainte de rulare inlocuieste-o cu codul filialei bazei
-- respective (vms_univers cu gr1='FL'):
--     11 Miron Costin / 12 Megapolis / 13 Columna / 16 Aleco Russo / 17 M.cel Batrin
-- NU te baza pe TMS_INIT_PARAMS.GlobalDep pentru asta: pe 2026-07-29 era copiat
-- identic (13) pe toate cele 3 baze de productie, deci gresit pe doua din trei.

-- ---------- UW_WAITERS ----------
ALTER TABLE uw_waiters ADD (cod_univ NUMBER);
UPDATE uw_waiters SET cod_univ = 11;
COMMIT;
ALTER TABLE uw_waiters MODIFY (cod_univ NUMBER NOT NULL);

-- PIN: nullable (NULL = alocat restaurantului, neinrolat inca) + exact 4 cifre.
ALTER TABLE uw_waiters MODIFY (pin VARCHAR2(4) NULL);
ALTER TABLE uw_waiters ADD CONSTRAINT uw_waiters_pin_ck
  CHECK (pin IS NULL OR REGEXP_LIKE(pin, '^[0-9]{4}$'));

ALTER TABLE uw_waiters DROP PRIMARY KEY DROP INDEX;
ALTER TABLE uw_waiters ADD CONSTRAINT uw_waiters_pk PRIMARY KEY (cod_univ, oficiant);

-- ---------- UW_TABLES ----------
ALTER TABLE uw_tables ADD (cod_univ NUMBER);
UPDATE uw_tables SET cod_univ = 11;
COMMIT;
ALTER TABLE uw_tables MODIFY (cod_univ NUMBER NOT NULL);
ALTER TABLE uw_tables DROP PRIMARY KEY DROP INDEX;
ALTER TABLE uw_tables ADD CONSTRAINT uw_tables_pk PRIMARY KEY (cod_univ, table_no);

-- ---------- recreare cu ordinea corecta a coloanelor + scoaterea lui NAME ----------
-- ALTER TABLE ADD lipeste coloana noua la coada, deci dupa pasii de mai sus
-- ordinea ramane PIN, OFICIANT, ACTIVE, NAME, COD_UNIV. Oracle nu poate reordona
-- coloanele - se recreeaza tabelul. NAME iese: numele e al UAMenu, se citeste
-- live prin VUW_WAITERS.CLCOFICIANTT.
CREATE TABLE uw_waiters_new (
  cod_univ NUMBER    NOT NULL,
  oficiant NUMBER    NOT NULL,
  pin      VARCHAR2(4),
  active   NUMBER(1) DEFAULT 1 NOT NULL
);
INSERT INTO uw_waiters_new (cod_univ, oficiant, pin, active)
  SELECT cod_univ, oficiant, pin, active FROM uw_waiters;
COMMIT;
DROP TABLE uw_waiters PURGE;
RENAME uw_waiters_new TO uw_waiters;
ALTER TABLE uw_waiters ADD CONSTRAINT uw_waiters_pk PRIMARY KEY (cod_univ, oficiant);
ALTER TABLE uw_waiters ADD CONSTRAINT uw_waiters_pin_ck
  CHECK (pin IS NULL OR REGEXP_LIKE(pin, '^[0-9]{4}$'));

CREATE TABLE uw_tables_new (
  cod_univ      NUMBER       NOT NULL,
  table_no      NUMBER       NOT NULL,
  zone          VARCHAR2(20) NOT NULL,
  display_order NUMBER,
  active        NUMBER(1)    DEFAULT 1 NOT NULL
);
INSERT INTO uw_tables_new (cod_univ, table_no, zone, display_order, active)
  SELECT cod_univ, table_no, zone, display_order, active FROM uw_tables;
COMMIT;
DROP TABLE uw_tables PURGE;
RENAME uw_tables_new TO uw_tables;
ALTER TABLE uw_tables ADD CONSTRAINT uw_tables_pk PRIMARY KEY (cod_univ, table_no);

-- Pe o baza curata, sar peste tot fisierul asta: ruleaza direct uw_waiters.sql
-- si uw_tables.sql, care au deja forma finala.
--
-- Dupa asta: vuw_views.sql, apoi recompilarea pachetului
-- (pg_mobile_web_waiter_body.txt) - in ordinea asta.

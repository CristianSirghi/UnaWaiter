-- ===========================================================================
-- 06 — Cheia străină mese → zone, plus indexul ei
-- ===========================================================================
-- >>> RULEAZĂ ASTA DUPĂ SEED, NU ÎNAINTE. <<<
--
-- Cheia străină se adaugă peste rânduri deja existente în uw_tables. Dacă zonele
-- nu sunt încă inserate (sau dacă seed-ul de mese folosește un cod de zonă care
-- nu există), Oracle refuză cu ORA-02298 „parent keys not found". De aceea
-- orchestratorul rulează: tabele → seed → fișierul ăsta.
--
-- Cheia e pe (cod_univ, zone), nu doar pe zone: o zonă aparține unei filiale,
-- deci masa 5 de la Columna nu poate arăta spre zona „vip" de la Rîșcani.

ALTER TABLE uw_tables ADD CONSTRAINT uw_tables_zone_fk
  FOREIGN KEY (cod_univ, zone) REFERENCES uw_zones (cod_univ, zone_code);

-- Indexul NU e opțional: fără el, orice DELETE pe uw_zones ia lock de TABEL pe
-- uw_tables (comportamentul Oracle pentru chei străine neindexate) — adică
-- ștergerea unei zone din back-office ar bloca toate mesele restaurantului.
CREATE INDEX uw_tables_zone_ix ON uw_tables (cod_univ, zone);

-- Dacă asta cade cu ORA-02298, verifică ce coduri de zonă are seed-ul de mese
-- față de cel de zone:
--   SELECT DISTINCT cod_univ, zone FROM uw_tables
--   MINUS
--   SELECT cod_univ, zone_code FROM uw_zones;

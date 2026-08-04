-- ===========================================================================
-- SEED — filiala 11, MIRON COSTIN (Rîșcani), front 93.116.209.117/xe
-- ===========================================================================
--
-- MESELE VIN DIN COMENZI REALE, nu inventate: sunt exact numerele care au
-- comenzi în ultimele 60 de zile (măsurat 2026-08-03 pe frontul de producție).
--   * 1–28 și 31–35 au comenzi reale;
--   * 29 și 30 n-au niciuna, dar sunt incluse ca numerotarea să fie continuă
--     (vezi explicația de la mese, mai jos);
--   * 121, 147, 222, 2088 au câte O SINGURĂ comandă fiecare — greșeli de
--     tastare, nu mese. Lăsate afară.
--
-- ÎMPĂRȚIREA PE ZONE E O DECIZIE, NU O CONSTATARE. Baza nu știe ce masă e afară:
-- `TMDB_COMENZ.DESK` e un număr brut, fără niciun dicționar în UAMenu. Am
-- încercat și pe cale ocolită — terasa s-ar vedea ca sezon (mese pline vara,
-- goale iarna) — dar frontul are istoric doar din 1 iunie 2026, adică numai
-- vară. Deci împărțirea de mai jos e aleasă de Kristian pe 2026-08-03:
-- 15 mese în sală, restul pe terasă.
--
-- NU E DEFINITIVĂ ȘI NU CERE PROGRAMATOR. Mesele se mută între zone, se adaugă
-- și se șterg din forma „14. Amplasare mese" din back-office. Dacă împărțirea
-- iese greșită, managerul o corectează în câteva secunde.
--
-- ⚠️ Singura consecință a unei greșeli: închiderea terasei pe iarnă
-- (`active = 0` pe zonă) ascunde zona CU TOT CU MESELE EI. O masă de interior
-- nimerită pe terasă ar dispărea din aplicație în prima zi rece.
--
-- FĂRĂ DIACRITICE ROMÂNEȘTI, și nu din neglijență: NLS_CHARACTERSET al bazei e
-- CL8MSWIN1251 (chirilic), care n-are ă/ș/ț. Un 'Terasă' scris de aici se
-- salvează tăcut ca 'Terasa' (verificat cu DUMP pe 2026-07-30). Rusa merge
-- perfect. Așa e toată baza UAMenu — filiala 17 se cheamă "MIRCEA cel BATRIN".

-- ------------------------------------------------------------------ ZONELE ---
INSERT INTO uw_zones (cod_univ, zone_code, name_ro, name_ru, name_en, display_order)
  VALUES (11, 'hall', 'Sala', unistr('\0417\0430\043B'), 'Hall', 1);

INSERT INTO uw_zones (cod_univ, zone_code, name_ro, name_ru, name_en, display_order)
  VALUES (11, 'terrace', 'Terasa', unistr('\0422\0435\0440\0440\0430\0441\0430'), 'Terrace', 2);

-- ------------------------------------------------------------------- MESELE ---
-- Sala: 1–15
INSERT INTO uw_tables (cod_univ, zone, table_no)
SELECT 11, 'hall', LEVEL FROM dual CONNECT BY LEVEL <= 15;

-- Terasa: 16–35, fără întreruperi.
--
-- 29 și 30 n-au nicio comandă în ultimele 60 de zile, dar sunt INCLUSE
-- intenționat, ca numerotarea să fie continuă. Costul e zero: o masă care nu
-- există fizic pur și simplu nu e folosită de nimeni (așa e și masa 17, care e
-- în interval dar n-a prins nicio comandă).
--
-- ⚠️ Alternativa — să renumerotăm 31–35 în 29–33 ca să iasă continuu — ar fi
-- fost GREȘITĂ. Numerele nu sunt ale noastre: ajung scrise în TMDB_COMENZ.DESK
-- și sunt exact cele pe care le vede casierul în UAMenu. Masa 32 are deja 219
-- comenzi pe numărul 32. Renumerotată, chelnerul ar deschide „masa 29" în telefon
-- pentru o masă căreia tot restaurantul îi zice 32.
INSERT INTO uw_tables (cod_univ, zone, table_no)
SELECT 11, 'terrace', LEVEL + 15 FROM dual CONNECT BY LEVEL <= 20;

COMMIT;

-- Verificare rapidă după rulare (așteptat: hall 15, terrace 20, total 35):
--   SELECT zone, COUNT(*), MIN(table_no), MAX(table_no)
--     FROM uw_tables WHERE cod_univ = 11 GROUP BY zone;

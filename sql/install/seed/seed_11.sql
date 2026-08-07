-- ===========================================================================
-- SEED — filiala 11, MIRON COSTIN (Rîșcani), front 93.116.209.117/xe
-- ===========================================================================
-- Recalculat pe 2026-08-07, DOAR pe comenzile de după 1 iulie 2026.
--
-- DE CE DOAR DUPĂ 1 IULIE: restaurantul și-a renumerotat mesele atunci.
-- Măsurat pe frontul de producție, comenzi per masă pe luni:
--
--     masa      iunie   iulie   august
--     1–10          0   178–431  activ      ← apărute din nimic pe 1 iulie
--     11, 12      105/217  257/64  activ
--     13, 14      166/214       0       0   ← moarte după 30 iunie
--     15, 16       16/15        0       0
--     25             10        0       0
--     31–35    26–242         0       0   ← moarte după 30 iunie
--
-- Zece numere cu sute de comenzi în iunie au exact ZERO din 1 iulie, iar
-- alte zece au apărut din nimic în aceeași zi. Nu e sezonalitate, e o
-- renumerotare. Versiunea precedentă a fișierului măsura o fereastră de 60 de
-- zile, care le amesteca pe amândouă: rezultau 35 de mese, din care ~12 nu mai
-- există. De aici încolo se măsoară doar de la 1 iulie încoace.
--
-- MESELE REALE DE AZI, cu tot cu zilele în care au lucrat (38 zile posibile):
--     1–12    între 33 și 38 de zile fiecare — toate reale, toate în uz;
--     18, 19  3 și 2 comenzi în total — rare, dar REALE (vezi mai jos);
--     20–24   între 21 și 38 de zile;
--     26–28   25, 26, 26 comenzi; 29 doar una, pe 3 august;
--     25      zero din 1 iulie — inclusă pentru continuitate, vezi mai jos;
--     222, 2088  câte O comandă — greșeli de tastare, lăsate afară.
--
-- MESELE RARE (18, 19, 29) AU FOST VERIFICATE UNA CÂTE UNA, fiindcă 3 comenzi
-- lângă vecine cu 200–500 arată a greșeală de tastare. Nu sunt: toate cele 6
-- comenzi au `state = 3` (achitate) și sume normale (61–271 lei), iar masa 18 a
-- fost folosită în 3 zile diferite de 3 chelneri diferiți.
--
-- Criteriul care le desparte de 121/147/222/2088 NU e starea comenzii — și alea
-- sunt tot achitate, verificat. E repetarea: fiecare dintre cele patru are exact
-- O comandă, de la UN chelner, într-o SINGURĂ zi, pe un număr implauzibil ca
-- masă (2088). Masa 18 revine, la oameni diferiți, în zile diferite. Astea sunt
-- mese reale, doar rar folosite (colț prost, masă de trecere), deci rămân.
--
-- 13–17, 30, 31–35 NU sunt incluse: 13–16 și 31–35 au fost retrase la
-- renumerotare, iar 17 și 30 n-au avut nicio comandă niciodată. Golul 13–17
-- dintre cele două blocuri e intenționat păstrat gol.
--
-- ------------------------------------------------------------ ZONELE -------
-- ÎMPĂRȚIREA E O DECIZIE, DAR DE DATA ASTA E SPRIJINITĂ PE CEVA. Ce spun
-- datele (măsurat 2026-08-07, pe cele 38 de zile de după renumerotare):
--
--   * Sunt DOUĂ blocuri distincte, nu unul: 1–12 și 18–29, cu golul 13–17
--     între ele.
--   * Blocul 18–29 e SECUNDAR, folosit la vârf: ponderea lui urcă de la ~10%
--     dimineața (ora 10) la ~28% la prânz (ora 12). Asta e semnătura unui
--     spațiu care se deschide când se umple primul.
--
-- Ce NU spun datele — și e important să fie scris, nu presupus:
--
--   * NU spun care bloc e afară. Cele două blocuri se mișcă identic zi de zi
--     (raport ~5:1 în fiecare din cele 38 de zile, fără volatilitate). O terasă
--     ar fi trebuit să sară cu vremea. Aici nu sare.
--   * NU se pot deduce din chelneri: toți cei 8 servesc ambele blocuri, în
--     același raport (~82% / 18%). Nu există sectoare repartizate.
--
-- Deci „Sala = 1–12, Terasa = 18–29" e ALEGEREA NOASTRĂ, luată fiindcă blocul
-- secundar e cel mai probabil candidat pentru terasă. O singură întrebare pusă
-- pe loc la instalare o confirmă sau o răstoarnă: „mesele 18–29 sunt cele de
-- afară?". Dacă răspunsul e nu, se schimbă în forma „14. Amplasare mese", în
-- două minute, fără programator și fără APK nou.
--
-- ⚠️ Singura consecință a unei greșeli: închiderea terasei pe iarnă
-- (`active = 0` pe zonă) ascunde zona CU TOT CU MESELE EI. O masă de interior
-- nimerită pe terasă ar dispărea din aplicație în prima zi rece. Până atunci
-- însă greșeala se vede din prima zi de pilot — chelnerul știe la ce masă stă.
--
-- FĂRĂ DIACRITICE ROMÂNEȘTI în DATE, și nu din neglijență: NLS_CHARACTERSET al
-- bazei e CL8MSWIN1251 (chirilic), care n-are ă/ș/ț. Un 'Terasă' scris de aici
-- se salvează tăcut ca 'Terasa' (verificat cu DUMP pe 2026-07-30). Rusa merge
-- perfect. Așa e toată baza UAMenu — filiala 17 se cheamă "MIRCEA cel BATRIN".

-- ------------------------------------------------------------------ ZONELE ---
INSERT INTO uw_zones (cod_univ, zone_code, name_ro, name_ru, name_en, display_order)
  VALUES (11, 'hall', 'Sala', unistr('\0417\0430\043B'), 'Hall', 1);

INSERT INTO uw_zones (cod_univ, zone_code, name_ro, name_ru, name_en, display_order)
  VALUES (11, 'terrace', 'Terasa', unistr('\0422\0435\0440\0440\0430\0441\0430'), 'Terrace', 2);

-- ------------------------------------------------------------------- MESELE ---
-- Sala: 1–12. Toate cele 12 au comenzi în 33–38 din cele 38 de zile.
INSERT INTO uw_tables (cod_univ, zone, table_no)
SELECT 11, 'hall', LEVEL FROM dual CONNECT BY LEVEL <= 12;

-- Terasa: 18–29, fără întreruperi.
--
-- Masa 25 n-are nicio comandă din 1 iulie (avea 10 în iunie), dar e INCLUSĂ
-- ca numerotarea blocului să fie continuă. La fel 18 și 19, cu 3 și 2 comenzi
-- în total. Costul e zero: o masă pe care n-o folosește nimeni pur și simplu
-- stă în listă.
--
-- ⚠️ Alternativa — să le sărim și să renumerotăm 26–29 în 25–28 — ar fi
-- GREȘITĂ. Numerele nu sunt ale noastre: ajung scrise în TMDB_COMENZ.DESK și
-- sunt exact cele pe care le vede casierul în UAMenu. Masa 26 are deja 167 de
-- comenzi pe numărul 26. Renumerotată, chelnerul ar deschide „masa 25" în
-- telefon pentru o masă căreia tot restaurantul îi zice 26.
--
-- Golul 13–17 NU se umple din același motiv, invers: 13–16 au fost retrase de
-- restaurant pe 30 iunie. Reintroduse aici, ar apărea în telefon mese pe care
-- restaurantul le-a scos deja.
INSERT INTO uw_tables (cod_univ, zone, table_no)
SELECT 11, 'terrace', LEVEL + 17 FROM dual CONNECT BY LEVEL <= 12;

COMMIT;

-- Verificare rapidă după rulare (așteptat: hall 12 (1–12), terrace 12 (18–29)):
--   SELECT zone, COUNT(*), MIN(table_no), MAX(table_no)
--     FROM uw_tables WHERE cod_univ = 11 GROUP BY zone;

-- ===========================================================================
-- 01 — UW_ZONES: dicționarul de zone (sala, terasa, etaj 2, VIP…)
-- ===========================================================================
-- STRUCTURĂ DOAR. Zonele concrete ale restaurantului sunt în seed/seed_<NN>.sql,
-- pentru că diferă de la un restaurant la altul. Cheia străină dinspre uw_tables
-- se pune în 06_chei_straine.sql, DUPĂ seed — vezi explicația de acolo.
--
-- De ce un tabel separat și nu textul liber rămas în UW_TABLES.ZONE: aplicația
-- compara literal codurile în QML ("hall" / "terrace"), deci o zonă nouă
-- introdusă din back-office făcea mesele ei să DISPARĂ din aplicație, fără
-- eroare și fără urmă. Cu tabelul ăsta zonele devin date.
--
-- Denumirea se ține în 3 limbi (ro/ru/en) și se trimit TOATE la telefon, nu doar
-- limba curentă: lista de mese se încarcă o singură dată, iar comutarea limbii
-- din Setări trebuie să fie instantanee.

CREATE TABLE uw_zones (
    cod_univ      NUMBER       NOT NULL,   -- filiala — vms_univers.cod cu gr1='FL'
    zone_code     VARCHAR2(20) NOT NULL,   -- codul intern, cel scris în uw_tables.zone
    name_ro       VARCHAR2(60) NOT NULL,   -- denumirea afișată chelnerului
    name_ru       VARCHAR2(60),            -- NULL = se cade pe name_ro
    name_en       VARCHAR2(60),
    display_order NUMBER,                  -- ordinea zonelor în ecran; NULL = la coadă
    active        NUMBER(1) DEFAULT 1 NOT NULL,
    CONSTRAINT uw_zones_pk PRIMARY KEY (cod_univ, zone_code)
);

-- Codul e cheie tehnică, nu text pentru ochi: intră în cheile locale din telefon
-- (OrdersStore.keyFor = zone||'-'||table_no) și în harta de ocupare
-- (zone||'_'||desk). Litere mici, cifre și underscore — fără spații, diacritice
-- sau majuscule, care ar face cheile fragile la orice normalizare.
-- Scris cu LENGTH + TRANSLATE, NU cu REGEXP_LIKE. Doua motive, ambele reale:
--
-- 1) DEPENDENTA DE NLS. Sub un NLS_SORT lingvistic, potrivirea implicita a lui
--    REGEXP_LIKE devine CASE-INSENSITIVE - ca si cum ar fi dat parametrul 'i'.
--    Baza clientului are NLS_SORT=RUSSIAN, deci varianta cu regexp accepta
--    majuscule, exact ce spune comentariul de mai sus ca nu trebuie sa accepte.
--    Era un bug tacut, nu doar o problema de portabilitate.
--
--    Masurat pe 2026-08-04, pe baza lor:
--      NLS_SORT=RUSSIAN, implicit -> REGEXP_LIKE('Hall','^[a-z]...') = TRUE
--      NLS_SORT=RUSSIAN, cu 'c'   -> FALSE
--      NLS_SORT=BINARY,  implicit -> FALSE
--
--    Deci cu regexp existau doua reparatii corecte: parametrul 'c' explicit,
--    sau clasa POSIX [[:lower:]] in loc de interval. Ambele functioneaza; am
--    ales TRANSLATE pentru motivul 2 de mai jos.
--    (Multumiri DBA-ului clientului, care a aratat ca 'i' e mecanismul real -
--    prima explicatie pe care o scrisesem aici, cu ordinea lingvistica a
--    intervalului, era gresita.)
-- 2) PORTABILITATE. Standardul clientului pentru instalari noi si pentru
--    inlocuirea unei case stricate este Oracle 21c XE; cerinta lor explicita
--    este sa nu folosim regexp_* in constrangeri.
--
-- Cum functioneaza TRANSLATE aici: caracterele din al doilea argument care n-au
-- corespondent in al treilea sunt STERSE. Deci daca dupa stergerea tuturor
-- caracterelor permise nu mai ramane nimic (rezultat NULL), sirul continea doar
-- caractere permise. '#' e ancora: al treilea argument nu poate fi gol, iar '#'
-- nu e un caracter permis, deci nu poate masca o valoare invalida.
ALTER TABLE uw_zones ADD CONSTRAINT uw_zones_code_ck
  CHECK (LENGTH(zone_code) BETWEEN 1 AND 20
     AND TRANSLATE(SUBSTR(zone_code, 1, 1),
                   '#abcdefghijklmnopqrstuvwxyz', '#') IS NULL
     AND TRANSLATE(zone_code,
                   '#abcdefghijklmnopqrstuvwxyz0123456789_', '#') IS NULL);

-- 'takeaway' e REZERVAT: aplicația îl folosește ca zonă VIRTUALĂ pentru comenzile
-- la pachet (main.qml trimite zone:"takeaway", OrderPage.isTakeaway se uită după
-- el). O zonă reală cu același cod ar amesteca mesele cu comenzile la pachet.
ALTER TABLE uw_zones ADD CONSTRAINT uw_zones_reserved_ck
  CHECK (zone_code <> 'takeaway');

ALTER TABLE uw_zones ADD CONSTRAINT uw_zones_active_ck CHECK (active IN (0,1));

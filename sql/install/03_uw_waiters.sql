-- ===========================================================================
-- 03 — UW_WAITERS: cine are drept de logare, la ce restaurant
-- ===========================================================================
-- Un rând = "chelnerul X are drept de logare la restaurantul Y".
--
-- NU se seedează la instalare: se completează din forma „Chelneri UnaWaiter"
-- din back-office, sau prin auto-înrolare la prima logare (set_pin).
--
-- De ce tabel separat și nu direct vms_univers:
--   1) vms_univers n-are parolă per chelner (CACCESS e un cod de rol comun),
--      deci nu se poate autentifica nimeni pe baza lui;
--   2) vms_univers e replicat IDENTIC pe toate fronturile lanțului (verificat
--      2026-08-03: aceleași 1132 de operatori, aceiași 101 angajați curenți pe
--      Rîșcani/Columna/M.cel Bătrîn), deci nu spune la ce restaurant lucrează
--      cineva. Legătura aia e COD_UNIV de mai jos și NU EXISTĂ NICĂIERI ALTUNDEVA
--      în sistem.
--
-- Numele NU se ține aici: nu e data noastră, e a UAMenu. Se citește live din
-- vms_univers prin VUW_WAITERS (coloana CLCOFICIANTT), ca să coincidă mereu cu
-- POS-ul. O copie locală ar rămâne în urmă la orice redenumire.

CREATE TABLE uw_waiters (
    cod_univ  NUMBER NOT NULL,          -- filiala — vms_univers.cod cu gr1='FL'
                                        -- 11 Miron Costin, 12 Megapolis, 13 Columna,
                                        -- 16 Aleco Russo, 17 Mircea cel Batrin
    oficiant  NUMBER NOT NULL,          -- vms_univers.cod, tip='O' gr1='R'
                                        -- = TMDB_COMENZ.OFICIANT
    pin       VARCHAR2(4),              -- NULL = alocat restaurantului, neînrolat încă
    active    NUMBER(1) DEFAULT 1 NOT NULL,
    -- Dreptul de a adăuga/scoate mese DIN APLICAȚIE (add_table,
    -- set_table_active). DEFAULT 0: un chelner obișnuit nu-l are.
    --
    -- Nu e o restricție de dragul restricției. Lista de mese e ecranul pe care
    -- lucrează toată tura, iar o masă adăugată greșit rămâne acolo pentru toți —
    -- și n-are cine s-o cureţe, fiindcă nimeni de la restaurant nu deschide
    -- back-office-ul. Cu 24 de mese pe un ecran de telefon, zece intrări de
    -- prisos sunt o problemă reală de folosire, nu una de curățenie.
    --
    -- ⚠️ E o barieră împotriva GREȘELILOR, nu o măsură de securitate: `p_waiter`
    -- vine de la telefon, ca în toate funcțiile pachetului, deci cine trimite alt
    -- cod de oficiant trece de ea. O barieră reală ar cere PIN-ul la operație,
    -- ceea ce înseamnă ca aplicația să-l țină după login (acum nu-l ține).
    -- Scris aici ca să nu se presupună altceva citind coloana.
    can_edit_tables NUMBER(1) DEFAULT 0 NOT NULL,
    CONSTRAINT uw_waiters_pk PRIMARY KEY (cod_univ, oficiant),
    -- Exact 4 cifre. Scris cu LENGTH + TRANSLATE, nu cu REGEXP_LIKE: cerinta
    -- clientului e sa nu folosim regexp_* in constrangeri (standardul lor pentru
    -- instalari noi e Oracle 21c XE). Vezi explicatia detaliata din
    -- 01_uw_zones.sql, inclusiv capcana [a-z] dependenta de NLS_SORT.
    -- '#' e ancora: al treilea argument al lui TRANSLATE nu poate fi gol.
    CONSTRAINT uw_waiters_pin_ck CHECK (pin IS NULL
      OR (LENGTH(pin) = 4 AND TRANSLATE(pin, '#0123456789', '#') IS NULL)),
    CONSTRAINT uw_waiters_active_ck CHECK (active IN (0,1)),
    CONSTRAINT uw_waiters_edit_ck   CHECK (can_edit_tables IN (0,1))
);

-- PIN-ul e TEXT, nu număr: un PIN care începe cu 0 (ex. 0123) s-ar pierde ca număr.

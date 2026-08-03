-- ===========================================================================
-- 04 — UW_FISCAL_RECEIPTS: bonurile fiscale emise prin terminalul SmartOne
-- ===========================================================================
-- Leagă comanda de numărul de document fiscal întors de SmartOne, pentru audit
-- și re-tipărire.
--
-- nr_comand e PRIMARY KEY INTENȚIONAT: e ultima barieră împotriva dublei
-- fiscalizări, chiar dacă protecțiile din aplicație (pending_fiscal.json) au fost
-- ocolite — reinstalare, alt device, sau proces omorât de Android la mijlocul
-- plății. Un bon dublu înseamnă probleme fiscale reale, deci merită barieră și la
-- nivel de bază de date, nu doar în aplicație.
--
-- >>> Coloana RRN e INCLUSĂ aici. Pe test a fost adăugată separat, printr-un
-- >>> ALTER TABLE ulterior (uw_fiscal_receipts_add_rrn.sql), și e ușor de sărit
-- >>> la o instalare nouă — se descoperă abia la prima plată cu „RRN manual".

CREATE TABLE uw_fiscal_receipts (
    nr_comand       NUMBER PRIMARY KEY,        -- comanda achitată (TMDB_COMENZ.COD)
    document_number VARCHAR2(50),              -- numărul întors de SmartOne la /sale
    pay_type        NUMBER(2) NOT NULL,        -- 1 = Numerar, 2 = Card
    amount          NUMBER(12,2),              -- totalul comenzii la momentul achitării
    oficiant        NUMBER,                    -- chelnerul care a încasat (vms_univers.cod)
    printed_at      DATE DEFAULT SYSDATE NOT NULL,
    rrn             VARCHAR2(20)               -- referința bancară la plata „RRN Manual"
);

-- document_number rămâne NULLABLE intenționat: un NOT NULL ar face plata să eșueze
-- DUPĂ ce bonul fiscal a fost tipărit — cel mai prost moment posibil.
--
-- RRN e nullable și generos dimensionat din același motiv: doar una din cele trei
-- metode de plată îl produce, iar un CHECK pe exact 13 cifre ar respinge plata
-- după tipărire. Lungimea o impune aplicația, unde refuzul e gratuit (butonul de
-- confirmare stă inactiv până sunt 13 cifre).

-- Căutare după numărul documentului fiscal (reconciliere cu jurnalul SmartOne).
CREATE INDEX uw_fiscal_receipts_doc_idx ON uw_fiscal_receipts (document_number);

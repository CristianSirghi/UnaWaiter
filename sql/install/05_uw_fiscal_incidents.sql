-- ===========================================================================
-- 05 — UW_FISCAL_INCIDENTS: jurnalul de bonuri duble / comenzi închise aiurea
-- ===========================================================================
-- Scris de pg_mobile_web_waiter.log_fiscal_incident, în TRANZACȚIE AUTONOMĂ,
-- anume ca să supraviețuiască ROLLBACK-ului care însoțește eroarea ridicată
-- imediat după: fără asta, exact dovada incidentului ar dispărea odată cu el.
--
-- Cheia unică (nr_comand, document_number) NU e doar igienă — e mecanismul prin
-- care reluarea CONVERGE. Un bon dublu nu se poate repara din aplicație (e în
-- memoria fiscală a aparatului), deci dacă eroarea s-ar ridica la fiecare
-- reîncercare, chelnerul ar primi același dialog la nesfârșit, pe o problemă pe
-- care n-are cum s-o rezolve. Așa: prima dată se semnalează zgomotos
-- (DUP_VAL_ON_INDEX nu apare), apoi apelul trece.

CREATE TABLE uw_fiscal_incidents (
  nr_comand       NUMBER        NOT NULL,
  document_number VARCHAR2(50)  NOT NULL,
  kind            VARCHAR2(30)  NOT NULL,   -- SECOND_RECEIPT | CLOSED_ELSEWHERE
  note            VARCHAR2(400),
  detected_at     DATE          DEFAULT SYSDATE NOT NULL,
  CONSTRAINT uw_fiscal_incidents_uk UNIQUE (nr_comand, document_number)
);

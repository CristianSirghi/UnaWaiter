CREATE OR REPLACE PACKAGE pg_mobile_web_waiter AS

  -- Spune sesiunii la CE RESTAURANT lucreaza. Trebuie chemata de PHP imediat
  -- dupa conectare, la FIECARE cerere - conexiunea e persistenta (oci_pconnect),
  -- deci contextul supravietuieste intre cereri si o cerere pentru un restaurant
  -- ar mosteni altfel filiala ramasa de la cea precedenta.
  --
  -- p_cod_univ = codul filialei din vms_univers gr1='FL' (11 Miron Costin,
  -- 12 Megapolis, 13 Columna, 16 Aleco Russo, 17 M.cel Batrin).
  --
  -- Deleaga la unirest_util.global_dep, adica EXACT ce face clientul UAMenu la
  -- login (ucLogin.cpp).
  --
  -- ⚠️ CE NU FACE, desi codul ei sugereaza ca ar face (masurat pe productie
  -- 2026-08-07): global_dep incearca sa puna si lista de preturi si grupele de
  -- produse ale filialei, citindu-le din `vcorresp_params` dupa GlobalDep. La
  -- clientul asta mecanismul e MORT: singurele chei configurate acolo sunt
  -- GlobalDep 133 si 1557 -> codprice 1001/1002 si group1 1/2, dar comenzile
  -- reale au GlobalDep=16, iar in baza exista o SINGURA lista de preturi
  -- (codprice=1) si un singur group1 (=1). Deci niciun restaurant nu primeste
  -- preturi proprii pe drumul asta, si nici noi - ceea ce inseamna, pe partea
  -- buna, ca aplicatia NU poate afisa alte preturi decat casa.
  -- (global_dep are `if v_value is not null` pe fiecare context, deci o
  -- potrivire ratata lasa contextul neatins, nu il goleste.)
  --
  -- Tot din contextul asta isi ia triggerul TRG_ONCOMENZ valoarea pentru
  -- TMDB_COMENZ.NRSET. Coloana e insa un simplu PASAGER: cautata peste tot
  -- (triggerele frontului, cele 5 view-uri peste TMDB_COMENZ, PK_X_Z_REPORT,
  -- importul de vanzari YPKG_VINZFOISOR, si interogarile formelor din A$ADP),
  -- NU e folosita nicaieri intr-un filtru sau grupare. Atribuirea pe filiale se
  -- face dupa BAZA din care se citeste (db link-ul), nu dupa coloana asta. Deci
  -- comenzile noastre, stampilate cu filiala aleasa in aplicatie (11), difera de
  -- restul din aceeasi baza (16) fara nicio consecinta functionala.
  FUNCTION set_restaurant(p_cod_univ IN NUMBER) RETURN VARCHAR2;

  -- Autentificare: oficiant (COD operator POS, ales din lista get_waiters) +
  -- PIN de 4 cifre din uw_waiters. Chelnerul e valid doar daca e in lista
  -- reala (VSLRPRM_CALCD_R_502) SI are PIN-ul potrivit.
  FUNCTION log_in(p_oficiant IN NUMBER, p_pin IN VARCHAR2) RETURN VARCHAR2;

  -- Inrolare PIN (auto-inscriere la prima logare): seteaza PIN-ul unui chelner
  -- real care inca NU are unul. Refuza suprascrierea (pin_already_set) - doar
  -- reset_pin (manager) sterge un PIN existent.
  FUNCTION set_pin(p_oficiant IN NUMBER, p_pin IN VARCHAR2) RETURN VARCHAR2;

  -- Reset PIN (manager): sterge PIN-ul => chelnerul si-l pune din nou.
  FUNCTION reset_pin(p_oficiant IN NUMBER) RETURN VARCHAR2;

  FUNCTION get_waiters RETURN SYS_REFCURSOR;

  FUNCTION get_categories RETURN SYS_REFCURSOR;

  FUNCTION get_menu(p_category IN NUMBER) RETURN SYS_REFCURSOR;

  FUNCTION get_payment_types RETURN SYS_REFCURSOR;

  FUNCTION get_tables RETURN SYS_REFCURSOR;

  -- ---------------------------------------------------------------------------
  -- MESELE, EDITATE DIN APLICATIE
  --
  -- Amandoua cer ca `p_waiter` sa aiba uw_waiters.can_edit_tables = 1 la
  -- restaurantul curent, altfel intorc {"error":"not_allowed"}. Vezi comentariul
  -- de la coloana (03_uw_waiters.sql): e o bariera impotriva greselilor, nu una
  -- de securitate - p_waiter vine de la telefon.
  --
  -- Aceleasi reguli ca in forma din back-office (TRG_VUW_TABLES_ALL), fiindca
  -- cele doua cai scriu in acelasi tabel si n-au voie sa accepte lucruri
  -- diferite. Ce NU se poate din aplicatie, intentionat: crearea zonelor
  -- (codul intra in cheile locale din telefon si e imuabil) si renumerotarea
  -- unei mese existente. Amandoua raman in forma "14. Amplasare mese".
  -- ---------------------------------------------------------------------------

  -- Adauga masa `p_table_no` in zona `p_zone`.
  --
  -- Daca masa exista deja si e ACTIVA -> {"error":"table_exists","zone":"..."}.
  -- Daca exista dar e INACTIVA (scoasa mai devreme cu set_table_active), o
  -- REACTIVEAZA in zona ceruta acum si intoarce {"ok":1,"reactivated":1}.
  -- Fara ramura asta, o masa scoasa n-ar mai putea fi readusa din telefon:
  -- get_tables intoarce doar mesele active, deci ea nu se vede nicaieri in
  -- aplicatie, iar o incercare de a o adauga din nou ar cadea pe "exista deja".
  FUNCTION add_table(
    p_waiter   IN NUMBER,
    p_table_no IN NUMBER,
    p_zone     IN VARCHAR2
  ) RETURN VARCHAR2;

  -- Scoate (p_active = 0) sau readuce (1) o masa. NU sterge randul: numarul
  -- mesei e deja scris pe comenzile facute (TMDB_COMENZ.DESK), iar `active` e
  -- exact mecanismul cu care se inchide terasa pe iarna din back-office.
  --
  -- Refuza scoaterea unei mese cu comanda deschisa (state 1 sau 2) ->
  -- {"error":"table_busy"}: altfel masa ar disparea din ecran de sub chelnerul
  -- care lucreaza pe ea.
  FUNCTION set_table_active(
    p_waiter   IN NUMBER,
    p_table_no IN NUMBER,
    p_active   IN NUMBER
  ) RETURN VARCHAR2;

  FUNCTION get_open_orders(p_waiter IN NUMBER DEFAULT NULL) RETURN SYS_REFCURSOR;

  FUNCTION get_paid_orders(p_waiter IN NUMBER DEFAULT NULL) RETURN SYS_REFCURSOR;

  -- Zi/saptamana/luna curenta (state=3, achitate), pentru ProfilePage.
  FUNCTION get_waiter_stats(p_waiter IN NUMBER) RETURN SYS_REFCURSOR;

  FUNCTION get_order(p_nr_comand IN NUMBER) RETURN SYS_REFCURSOR;

  FUNCTION get_order_lines(p_nr_comand IN NUMBER) RETURN SYS_REFCURSOR;

  -- p_desk NULL = comanda LA PACHET (fara masa). Nu e un caz special inventat de
  -- noi: pe productie ~25% din comenzi (2156 din ultimele 60 de zile) au deja
  -- DESK NULL - sunt vanzarile de la casa. Coloana e nullable, iar triggerele
  -- (TRG_VMDB_COMENZ_RESTAURANT / TRG_ONCOMENZ) nu valideaza deloc desk-ul, deci
  -- comanda trece pe exact acelasi drum ca una cu masa. Verificat empiric pe
  -- test: comanda 382792 a iesit corect, cu totaluri si TVA calculate de Oracle,
  -- si a fost achitata din UAMenu fara nicio problema.
  --
  -- p_coment se scrie in TMDB_COMENZ.COMENT si se TIPARESTE pe bon (verificat pe
  -- bon real, apare sub linia de plata). Camp liber: pe productie e nefolosit
  -- (0 din 7493 comenzi in 90 de zile).
  -- Lasat NULL pe o comanda fara masa, pachetul pune singur marcajul "La pachet"
  -- (c_takeaway_mark din body) - aplicatia nu trebuie sa stie textul.
  --
  -- p_person e IGNORAT (vezi body): coloana in care ajungea, PERSON/BARMEN, e
  -- casierul turei, nu numarul de persoane. Ramane doar ca PHP-ul instalat sa
  -- nu crape; numarul de persoane traieste in aplicatie.
  FUNCTION create_order(
    p_waiter   IN NUMBER,
    p_desk     IN NUMBER,
    p_pay_type IN NUMBER   DEFAULT NULL,
    p_person   IN NUMBER   DEFAULT NULL,
    p_coment   IN VARCHAR2 DEFAULT NULL
  ) RETURN NUMBER;

  FUNCTION add_order_line(
    p_nr_comand    IN NUMBER,
    p_product	   IN NUMBER,
    p_qty	   IN NUMBER,
    p_parent_nrord IN NUMBER DEFAULT NULL,
    p_commentary   IN VARCHAR2 DEFAULT NULL
  ) RETURN NUMBER;

  -- p_desk NULL = comanda devine LA PACHET; o masa reala o scoate din pachet.
  -- In ambele sensuri se rescrie si marcajul din COMENT (vezi c_takeaway_mark
  -- in body) - fara asta, o comanda mutata de la pachet la masa ar tipari mai
  -- departe "La pachet" pe bonul fiscal al clientului.
  FUNCTION update_order_desk(
    p_nr_comand IN NUMBER,
    p_desk	IN NUMBER
  ) RETURN NUMBER;

  -- Anuleaza o comanda (state=4), doar daca inca nu a fost achitata
  -- (state 1 sau 2). Foloseste view-ul vmdb_comenz_restaurant, nu update
  -- direct pe tabel, ca sa treaca prin TRG_VMDB_COMENZ_RESTAURANT (aceleasi
  -- reguli ca la anularea din UAMenu, Ctrl+A).
  FUNCTION cancel_order(
    p_nr_comand IN NUMBER
  ) RETURN NUMBER;

  -- Inchide comanda ca achitata (state=3), replicand exact ce face casierul in
  -- UAMenu. p_pay_type: 1 = Numerar, 2 = Card. La numerar p_pay e suma primita
  -- de la client (poate depasi totalul - restul se da manual); la card e
  -- ignorata, suma mergand in SUMA_TERMINAL. p_doc_fiscal = numarul de document
  -- intors de SmartOne, salvat in uw_fiscal_receipts pentru audit/re-tiparire.
  --
  -- IDEMPOTENTA: o comanda deja achitata (state=3) NU produce eroare, ci
  -- succes. Bonul fiscal se emite INAINTE de acest apel, deci banii sunt deja
  -- incasati; daca reteaua pica intre bon si inchiderea comenzii, aplicatia
  -- trebuie sa poata relua apelul in siguranta.
  --
  -- Adauga in COMENT marcajul platii din aplicatie (vezi c_paid_mark din body),
  -- concatenat la ce era acolo. Pe bonul clientului NU apare - bonul e deja
  -- tiparit cand se ajunge aici.
  FUNCTION pay_order(
    p_nr_comand  IN NUMBER,
    p_pay_type   IN NUMBER,
    p_pay        IN NUMBER   DEFAULT NULL,
    p_doc_fiscal IN VARCHAR2 DEFAULT NULL,
    p_oficiant   IN NUMBER   DEFAULT NULL,
    -- Totalul TIPARIT pe bon. Optional: cat timp clientul nu-l trimite,
    -- verificarea de potrivire cu totalul comenzii doarme, deci apelurile
    -- vechi cu 5 argumente raman valabile.
    p_amount     IN NUMBER   DEFAULT NULL,
    -- Referinta tranzactiei bancare la "RRN Manual" (13 cifre, validate in
    -- aplicatie). Optional: celelalte metode de plata nu produc asa ceva.
    p_rrn        IN VARCHAR2 DEFAULT NULL
  ) RETURN NUMBER;

  -- get_update_info A FOST SCOASA DE AICI (2026-08-03) si mutata in PHP.
  --
  -- Citea URL-ul de auto-update din A$ADM/A$ADP$V cu prefixul de schema SUN
  -- HARDCODAT. Mergea pe test din coincidenta: acolo schema de configurare si
  -- schema aplicatiei sunt in ACEEASI baza. Pe productie sunt baze fizic
  -- diferite - frontul e la restaurant, configurarea in FOISHOR@cloudbd - iar
  -- fronturile n-au niciun db link. Deci nu doar ca valoarea nu se putea citi:
  -- PACHETUL INTREG nu compila (PLS-00201) si nu mai mergea NIMIC.
  --
  -- Acum o citeste PHP-ul, care e oricum conectat la back-office pentru
  -- registru, si CA proprietarul lui - deci fara niciun prefix de schema, cu
  -- acelasi cod in ambele medii. Vezi uwUpdateInfoFromBackOffice() din
  -- oracle_waiter.php si docs/migrare-productie §3.1.
  --
  -- Pachetul n-are astfel NICIO referinta in afara schemei aplicatiei.

END pg_mobile_web_waiter;

/

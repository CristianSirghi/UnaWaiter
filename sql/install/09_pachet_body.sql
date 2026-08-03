CREATE OR REPLACE PACKAGE BODY pg_mobile_web_waiter AS

  -- Marcajul comenzilor LA PACHET, scris in TMDB_COMENZ.COMENT. UAMenu n-are
  -- niciun tip de comanda "pachet", iar o comanda fara masa arata exact ca o
  -- vanzare de la casa - textul asta e singura diferenta vizibila, si se si
  -- tipareste pe bon.
  --
  -- Traieste AICI, nu in aplicatie: e o proprietate derivata din "n-are masa",
  -- deci trebuie aplicata identic la creare SI la mutarea masa<->pachet. Tinut
  -- intr-un singur loc, se schimba printr-o recompilare de pachet, fara build
  -- si redistribuire de APK.
  c_takeaway_mark CONSTANT VARCHAR2(20) := 'La pachet';

  -- Restaurantul (filiala) caruia ii apartine baza asta. UAMenu tine identitatea
  -- filialei in contextul de sesiune 'envunirest'.GlobalDep: clientul POS il pune
  -- la login din vms_pos_by_div (dupa numarul casei din cantina.ini), iar intr-o
  -- sesiune noua - cum e cea deschisa de PHP - valoarea vine din TMS_INIT_PARAMS.
  -- Acelasi context e citit si de triggerul TRG_ONCOMENZ, care stampileaza
  -- TMDB_COMENZ.NRSET, deci folosind-o ramanem consecventi cu POS-ul.
  --
  -- ATENTIE la mutarea pe productie: pe 2026-07-29 TMS_INIT_PARAMS era copiat
  -- identic pe toate cele 3 baze de productie (GlobalDep=13 Columna peste tot),
  -- deci gresit pentru Riscani si M.cel Batrin. Cand aplicatia va alege explicit
  -- restaurantul, codul filialei trebuie sa vina ca parametru de la client, iar
  -- functia asta ramane doar rezerva.
  FUNCTION current_cod_univ RETURN NUMBER IS
  BEGIN
    RETURN TO_NUMBER(SYS_CONTEXT('envunirest', 'GlobalDep'));
  EXCEPTION
    WHEN OTHERS THEN
      RETURN NULL;
  END current_cod_univ;

  -- Ridicata de functiile care intorc cursor si nu pot raporta eroarea in JSON.
  -- Mai bine o eroare zgomotoasa decat o lista goala sau, si mai rau, lista
  -- altui restaurant ramasa in conexiunea persistenta.
  PROCEDURE require_restaurant(p_filiala IN NUMBER) IS
  BEGIN
    IF p_filiala IS NULL THEN
      RAISE_APPLICATION_ERROR(-20010,
        'no_restaurant: set_restaurant nu a fost chemata pentru cererea asta');
    END IF;
  END require_restaurant;

  FUNCTION set_restaurant(p_cod_univ IN NUMBER) RETURN VARCHAR2 IS
    v_name VARCHAR2(160);
  BEGIN
    IF p_cod_univ IS NULL THEN
      RETURN '{"error":"no_restaurant"}';
    END IF;

    -- Filiala trebuie sa existe cu adevarat. Fara verificarea asta, un cod
    -- gresit ar trece mai departe si comenzile ar fi stampilate cu el.
    BEGIN
      SELECT denumirea INTO v_name
        FROM vms_univers
       WHERE cod = p_cod_univ AND gr1 = 'FL' AND tip = 'O';
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RETURN '{"error":"unknown_restaurant"}';
      WHEN TOO_MANY_ROWS THEN
        RETURN '{"error":"unknown_restaurant"}';
    END;

    unirest_util.global_dep(p_cod_univ);

    RETURN '{"ok":1,"cod_univ":' || p_cod_univ
        || ',"name":"' || REPLACE(REPLACE(v_name, '\', '\\'), '"', '\"') || '"}';
  END set_restaurant;

  -- Tura ("смена") deschisa la casa. TMDB_COMENZ.NRDOC leaga bonul de randul din
  -- TMDB_SOLD, iar clientul UAMenu o pune la login (UN$CANTINA.get_sold_nrdoc ->
  -- contextul 'rest_nrdoc'); intr-o sesiune de PHP nu avem contextul ala, deci o
  -- citim direct din tabela.
  --
  -- NU e cosmetica: importul vanzarilor in back-office (SUN.YPKG_VINZFOISOR.
  -- ins_casa, actiunea de umplere a documentului) face
  --   from ...tmdb_comenz m, ...tmdb_sold aa where aa.nrdoc = m.nrdoc
  -- deci o comanda cu NRDOC null nu se leaga de nicio tura si DISPARE complet din
  -- document, oricat de corecta ar fi altfel. La fel filtreaza si rapoartele X/Z
  -- (PK_X_Z_REPORT). Verificat 2026-07-29: pe test tura curenta e 20, pe cele 3
  -- productii 10 - deschise o data si nemaiinchise (prod: din 2016), de aceea
  -- MAX(nrdoc) e sigur si nu hardcodam nimic.
  FUNCTION current_nrdoc RETURN NUMBER IS
    v_nrdoc NUMBER;
  BEGIN
    SELECT MAX(nrdoc) INTO v_nrdoc FROM tmdb_sold;
    RETURN v_nrdoc;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN NULL;
  END current_nrdoc;

  -- Casierul turei, in forma in care il tine TMDB_COMENZ: coloana PERSON
  -- (BARMEN in view) NU e numarul de persoane, cum ii sugereaza numele - e
  -- codul de subdiviziune al casierului, `TMS_CASIR.DEP`:
  --   VMDB_COMENZ_RESTAURANT: (select denumirea from tms_casir where dep = barmen)
  -- Verificat 2026-07-29: pe productie TOATE cele 1270 de comenzi din ultimele
  -- 7 zile au person=3460 (Mariana), pe test toate cele 30 de comenzi UAMenu au
  -- 1500 (Admin) - adica exact `dep` al casierului care a deschis tura
  -- (TMDB_SOLD.CASIR_ID -> TMS_CASIR.COD -> DEP). De aici si formula de mai jos,
  -- care da singura valoarea corecta pe orice baza.
  --
  -- Conteaza in back-office: importul vanzarilor (SUN.YPKG_VINZFOISOR.ins_casa)
  -- citeste `m.person` ca `casir`, grupeaza pe el si il scrie in
  -- `vmdb_st201d.dtdep` - subdiviziunea de pe linia contabila. O valoare din
  -- afara TMS_CASIR strica atribuirea liniilor din document.
  FUNCTION current_barmen RETURN NUMBER IS
    v_dep   NUMBER;
    v_nrdoc NUMBER := current_nrdoc;   -- o functie privata nu poate fi chemata din SQL
  BEGIN
    SELECT c.dep INTO v_dep
      FROM tms_casir c
      JOIN tmdb_sold s ON s.casir_id = c.cod
     WHERE s.nrdoc = v_nrdoc;
    RETURN v_dep;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN NULL;
  END current_barmen;

  FUNCTION log_in(p_oficiant IN NUMBER, p_pin IN VARCHAR2) RETURN VARCHAR2 IS
    v_oficiant NUMBER;
    v_name     VARCHAR2(200);
    v_safe     VARCHAR2(200);
    v_filiala  NUMBER := current_cod_univ;
  BEGIN
    IF v_filiala IS NULL THEN
      RETURN '{"error":"no_restaurant"}';
    END IF;

    -- Trebuie sa fie chelner real (in lista de payroll) SI PIN-ul sa se
    -- potriveasca SI contul sa fie activ SI sa fie inrolat la restaurantul
    -- asta (un PIN de la alta filiala nu deschide usa aici).
    SELECT v.cod, v.denumirea
      INTO v_oficiant, v_name
      FROM vms_univers v
      JOIN uw_waiters w ON w.oficiant = v.cod
     WHERE v.cod = p_oficiant
       AND v.tip = 'O' AND v.gr1 = 'R'
       AND v.cod IN (SELECT sc_munc FROM VSLRPRM_CALCD_R_502)
       AND w.cod_univ = v_filiala
       AND w.pin = p_pin
       AND w.active = 1;

    v_safe := REPLACE(REPLACE(v_name, '\', '\\'), '"', '\"');
    RETURN '{"oficiant":' || v_oficiant
        || ',"name":"' || v_safe || '"}';
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN '{"error":"invalid_credentials"}';
  END log_in;

  FUNCTION set_pin(p_oficiant IN NUMBER, p_pin IN VARCHAR2) RETURN VARCHAR2 IS
    v_is_waiter NUMBER;
    v_has_pin   NUMBER;
    v_filiala   NUMBER := current_cod_univ;
  BEGIN
    -- Fara identitate de filiala n-avem unde inrola chelnerul.
    IF v_filiala IS NULL THEN
      RETURN '{"error":"no_restaurant"}';
    END IF;

    -- (a) trebuie sa fie chelner real, curent (in lista de payroll)
    SELECT COUNT(*) INTO v_is_waiter
      FROM vms_univers v
     WHERE v.cod = p_oficiant
       AND v.tip = 'O' AND v.gr1 = 'R'
       AND v.cod IN (SELECT sc_munc FROM VSLRPRM_CALCD_R_502);
    IF v_is_waiter = 0 THEN
      RETURN '{"error":"not_a_waiter"}';
    END IF;

    -- (b) PIN exact 4 cifre
    IF p_pin IS NULL OR NOT REGEXP_LIKE(p_pin, '^[0-9]{4}$') THEN
      RETURN '{"error":"invalid_pin_format"}';
    END IF;

    -- (c) refuza suprascrierea unui PIN existent (doar reset_pin il goleste).
    -- Un rand cu PIN NULL inseamna "apartine restaurantului, dar nu s-a inrolat
    -- inca" - ala se completeaza, nu se respinge.
    SELECT COUNT(*) INTO v_has_pin
      FROM uw_waiters
     WHERE cod_univ = v_filiala AND oficiant = p_oficiant AND pin IS NOT NULL;
    IF v_has_pin > 0 THEN
      RETURN '{"error":"pin_already_set"}';
    END IF;

    -- Numele NU se copiaza aici: nu e data noastra, se citeste live din
    -- vms_univers (vezi vuw_waiters.clcoficiantt). O copie ar putea ramane
    -- in urma daca POS-ul corecteaza numele.
    --
    -- Randul poate exista deja (pus de forma din back-office, cu PIN gol) sau
    -- nu (auto-inrolare la prima logare) - acopera ambele cazuri.
    UPDATE uw_waiters
       SET pin = p_pin, active = 1
     WHERE cod_univ = v_filiala AND oficiant = p_oficiant;
    IF SQL%ROWCOUNT = 0 THEN
      INSERT INTO uw_waiters (cod_univ, oficiant, pin, active)
      VALUES (v_filiala, p_oficiant, p_pin, 1);
    END IF;
    COMMIT;
    RETURN '{"ok":1}';
  END set_pin;

  FUNCTION reset_pin(p_oficiant IN NUMBER) RETURN VARCHAR2 IS
    v_filiala NUMBER := current_cod_univ;
  BEGIN
    -- Fara filiala am sterge PIN-ul chelnerului la TOATE restaurantele.
    IF v_filiala IS NULL THEN
      RETURN '{"error":"no_restaurant"}';
    END IF;

    -- Golim PIN-ul, NU stergem randul: apartenenta chelnerului la restaurant
    -- ramane (o gestioneaza forma din back-office), doar inrolarea se anuleaza.
    UPDATE uw_waiters
       SET pin = NULL
     WHERE oficiant = p_oficiant
       AND cod_univ = v_filiala;
    COMMIT;
    RETURN '{"ok":1}';
  END reset_pin;

  FUNCTION get_waiters RETURN SYS_REFCURSOR IS
    v_cursor  SYS_REFCURSOR;
    v_filiala NUMBER := current_cod_univ;
  BEGIN
    require_restaurant(v_filiala);

    -- Lista reala de chelneri = cei din payroll (VSLRPRM_CALCD_R_502),
    -- intersectata cu tip='O'/gr1='R' (curata intrarea stray TEST gr1='P').
    -- has_pin = 1 daca s-a inrolat LA RESTAURANTUL ASTA, 0 altfel - un PIN pus
    -- la alta filiala nu conteaza aici.
    --
    -- Lista ramane deocamdata toata lista de chelneri a lantului, nu doar cei
    -- deja alocati restaurantului, ca sa poata oricine sa se inroleze singur cat
    -- timp forma din back-office nu exista inca. Cand forma va fi sursa oficiala,
    -- aici se adauga si filtrul pe apartenenta (uw_waiters.cod_univ).
    OPEN v_cursor FOR
      SELECT v.cod,
             v.denumirea,
             (SELECT COUNT(*) FROM uw_waiters w
               WHERE w.oficiant = v.cod
                 AND w.cod_univ = v_filiala
                 AND w.pin IS NOT NULL) AS has_pin
      FROM vms_univers v
      WHERE v.tip = 'O' AND v.gr1 = 'R'
        AND v.cod IN (SELECT sc_munc FROM VSLRPRM_CALCD_R_502)
      ORDER BY v.denumirea;
    RETURN v_cursor;
  END get_waiters;

  FUNCTION get_categories RETURN SYS_REFCURSOR IS
    v_cursor SYS_REFCURSOR;
  BEGIN
    OPEN v_cursor FOR
      SELECT DISTINCT grp AS cod, grname AS denumirea
      FROM vms_bliuda
      WHERE grp IS NOT NULL
      ORDER BY grp;
    RETURN v_cursor;
  END get_categories;

  FUNCTION get_menu(p_category IN NUMBER) RETURN SYS_REFCURSOR IS
    v_cursor SYS_REFCURSOR;
  BEGIN
    OPEN v_cursor FOR
      SELECT cod, denumirea, um, grp, pret
      FROM vms_bliuda
      WHERE grp = NVL(p_category, grp) OR NVL(p_category, 0) = 0
      ORDER BY grp, cod;
    RETURN v_cursor;
  END get_menu;

  FUNCTION get_payment_types RETURN SYS_REFCURSOR IS
    v_cursor SYS_REFCURSOR;
  BEGIN
    OPEN v_cursor FOR
      SELECT cod1 AS cod, denumirea
      FROM vms_syss
      WHERE cod = 105 AND tip = 'T'
      ORDER BY cod1;
    RETURN v_cursor;
  END get_payment_types;

  FUNCTION get_tables RETURN SYS_REFCURSOR IS
    v_cursor  SYS_REFCURSOR;
    v_filiala NUMBER := current_cod_univ;
  BEGIN
    require_restaurant(v_filiala);

    -- Doar mesele restaurantului asta, cu zona lor din uw_zones.
    --
    -- Denumirea zonei pleaca in TOATE cele 3 limbi, nu doar in cea curenta:
    -- lista de mese se incarca o singura data, iar limba se schimba din Setari
    -- fara reincarcare - daca am trimite doar limba curenta, titlurile zonelor
    -- ar ramane in urma. Sunt cateva zone, nu costa nimic.
    --
    -- JOIN, nu LEFT JOIN: o masa fara zona valida n-are unde sa fie desenata.
    -- Cheia straina uw_tables_zone_fk garanteaza oricum ca nu exista.
    -- z.active = 1 => inchiderea unei zone (terasa iarna) ascunde si mesele ei.
    OPEN v_cursor FOR
      SELECT t.zone,
             t.table_no,
             z.name_ro       AS zone_ro,
             z.name_ru       AS zone_ru,
             z.name_en       AS zone_en,
             z.display_order AS zone_order
      FROM uw_tables t
      JOIN uw_zones z ON z.cod_univ = t.cod_univ AND z.zone_code = t.zone
      WHERE t.active = 1
        AND z.active = 1
        AND t.cod_univ = v_filiala
      ORDER BY NVL(z.display_order, 999), z.zone_code,
               NVL(t.display_order, t.table_no), t.table_no;
    RETURN v_cursor;
  END get_tables;

  FUNCTION get_open_orders(p_waiter IN NUMBER DEFAULT NULL) RETURN SYS_REFCURSOR IS
    v_cursor SYS_REFCURSOR;
  BEGIN
    OPEN v_cursor FOR
      -- Fara BARMEN: e casierul turei, nu numarul de persoane (vezi
      -- current_barmen). Numarul de persoane traieste doar in aplicatie.
      SELECT o.nr_comand, o.desk, o.oficiant, o.clcoficiantt,
	     TO_CHAR(o.data_comand, 'HH24:MI') AS order_time, o.clccostt, o.state,
	     (SELECT LISTAGG(d.clcbliudat || ' x' || TRIM(TO_CHAR(d.cant)), ', ')
		     WITHIN GROUP (ORDER BY d.nrord)
		FROM vmdb_comenzd d
	       WHERE d.nr_comand = o.nr_comand) AS preview
	FROM vmdb_comenz_restaurant o
       WHERE o.state IN (1, 2)
	 AND (p_waiter IS NULL OR o.oficiant = p_waiter)
       ORDER BY o.data_comand DESC;
    RETURN v_cursor;
  END get_open_orders;

  -- Coloanele NOI (doc_fiscal, tipplata, data1, suma_terminal) sunt ADAUGATE la
  -- coada, iar cele vechi isi pastreaza numele: PHP-ul trece coloanele generic,
  -- deci un client mai vechi nu vede nicio diferenta.
  --
  -- LEFT JOIN, nu INNER: comenzile achitate LA CASA nu au rand in
  -- uw_fiscal_receipts (tabela e doar a noastra) si trebuie sa apara in lista la
  -- fel ca celelalte - doar ca fara numar de bon, deci fara retiparire.
  FUNCTION get_paid_orders(p_waiter IN NUMBER DEFAULT NULL) RETURN SYS_REFCURSOR IS
    v_cursor SYS_REFCURSOR;
  BEGIN
    OPEN v_cursor FOR
      SELECT c.nr_comand, c.desk, c.oficiant, c.clcoficiantt, c.data_comand,
             c.clccostt, c.pay, c.state,
             c.tipplata, c.clctipplatat, c.suma_terminal,
             -- Ora PLATII, nu a deschiderii comenzii: pay_order pune data1 la
             -- inchidere, iar in lista de bonuri asta cauti.
             c.data1,
             r.document_number AS doc_fiscal
      FROM vmdb_comenz_restaurant c
      LEFT JOIN uw_fiscal_receipts r ON r.nr_comand = c.nr_comand
      WHERE c.state = 3
	AND c.data_comand >= TRUNC(SYSDATE)
	AND (p_waiter IS NULL OR c.oficiant = p_waiter)
      ORDER BY c.data_comand DESC;
    RETURN v_cursor;
  END get_paid_orders;

  FUNCTION get_waiter_stats(p_waiter IN NUMBER) RETURN SYS_REFCURSOR IS
    v_cursor SYS_REFCURSOR;
  BEGIN
    OPEN v_cursor FOR
      SELECT
	COUNT(CASE WHEN data_comand >= TRUNC(SYSDATE) THEN 1 END) AS day_count,
	COUNT(CASE WHEN data_comand >= TRUNC(SYSDATE, 'IW') THEN 1 END) AS week_count,
	COUNT(CASE WHEN data_comand >= TRUNC(SYSDATE, 'MM') THEN 1 END) AS month_count
      FROM vmdb_comenz_restaurant
      WHERE state = 3
	AND oficiant = p_waiter
	AND data_comand >= TRUNC(SYSDATE) - 40;
    RETURN v_cursor;
  END get_waiter_stats;

  FUNCTION get_order(p_nr_comand IN NUMBER) RETURN SYS_REFCURSOR IS
    v_cursor SYS_REFCURSOR;
  BEGIN
    OPEN v_cursor FOR
      SELECT nr_comand, desk, oficiant, clcoficiantt, tipplata, clctipplatat,
	     state, data_comand, clccostt, pay, coment
      FROM vmdb_comenz_restaurant
      WHERE nr_comand = p_nr_comand;
    RETURN v_cursor;
  END get_order;

  FUNCTION get_order_lines(p_nr_comand IN NUMBER) RETURN SYS_REFCURSOR IS
    v_cursor SYS_REFCURSOR;
  BEGIN
    OPEN v_cursor FOR
      -- codtva = litera de TVA a produsului (o pune trigger-ul INSTEAD OF al
      -- view-ului, copiata din vms_univers). E exact codul asteptat de SmartOne,
      -- se mapeaza 1:1 fara traducere.
      --
      -- ⚠️ NU adauga aici o coloana cu COTA din Unirest_Util.vat_percent_by_letter.
      -- S-a incercat pe 2026-08-03 (ideea era buna: o constanta fiscala n-are ce
      -- cauta hardcodata in APK) si s-a RETRAS inainte de compilare, pentru ca
      -- functia aia intoarce 10 pentru litera C -- valoare contrazisa de tot
      -- restul:
      --   * aparatul fiscal SmartOne tipareste 6% (dovedit: aplicatia a trimis
      --     10.00%, pe bon a iesit 6%);
      --   * UAMenu inregistreaza 6% (TVA_C, pe 8426 din 8426 comenzi platite de
      --     pe productie, si pe comenzile inca deschise).
      -- Singurul loc care spune 10 e chiar functia asta -- prin ea, si
      -- imprimanta Tremol de la casa tipareste 10%, adica UAMenu contabilizeaza
      -- la 6% dar tipareste 10%. E o contradictie a LOR, de ridicat la
      -- Sandu/Daniela, nu de propagat la noi.
      --
      -- O valoare gresita luata din baza e mai rea decat una corecta din cod:
      -- arata autoritara. C++ stie deja sa citeasca o coloana `TVA_PRC` daca
      -- apare (vezi smartoneclient.cpp) -- deci cand exista o sursa in care se
      -- poate avea incredere, se adauga aici si merge de la sine.
      SELECT nrord, bliuda, clcbliudat, clcumt, cant, t,
	     clcprett, clcsumat, parent_nrord, commentary, codtva
      FROM vmdb_comenzd
      WHERE nr_comand = p_nr_comand
      ORDER BY nrord;
    RETURN v_cursor;
  END get_order_lines;

  -- p_person e IGNORAT si pastrat doar pentru compatibilitate: parametrul a fost
  -- adaugat cand credeam ca PERSON = numarul de persoane. Nu e (vezi
  -- current_barmen), iar numarul de persoane nu se mai scrie in Oracle - traieste
  -- doar in aplicatie. Ramane in semnatura ca PHP-ul deja instalat sa nu crape;
  -- se scoate cand se curata si backend-ul.
  FUNCTION create_order(
    p_waiter   IN NUMBER,
    p_desk     IN NUMBER,
    p_pay_type IN NUMBER   DEFAULT NULL,
    p_person   IN NUMBER   DEFAULT NULL,
    p_coment   IN VARCHAR2 DEFAULT NULL
  ) RETURN NUMBER IS
    v_nr_comand   NUMBER;
    v_lock_handle VARCHAR2(128);   -- ramane NULL la comenzile la pachet
    v_lock_result NUMBER;
    v_cnt	  NUMBER;
    v_nrdoc	  NUMBER := current_nrdoc;
    v_barmen	  NUMBER := current_barmen;
  BEGIN
    -- Blocarea si verificarea de unicitate au sens DOAR pentru o masa reala: doi
    -- chelneri nu pot deschide doua comenzi pe masa 5, dar pot avea oricate
    -- comenzi la pachet in acelasi timp.
    --
    -- Le sarim EXPLICIT cand p_desk e NULL, nu implicit: altfel numele lock-ului
    -- ar iesi 'UW_DESK_LOCK_' (concatenare cu NULL) - adica UN SINGUR lock global
    -- pe care s-ar serializa toate comenzile la pachet din tot restaurantul - iar
    -- 'WHERE desk = p_desk' cu NULL nu intoarce niciodata niciun rand, deci
    -- verificarea de mai jos ar fi inerta din accident. Ambele ar "merge" la
    -- test si ar fi gresite ca intentie.
    IF p_desk IS NOT NULL THEN
      DBMS_LOCK.ALLOCATE_UNIQUE('UW_DESK_LOCK_' || p_desk, v_lock_handle);
      v_lock_result := DBMS_LOCK.REQUEST(
	lockhandle	    => v_lock_handle,
	lockmode	    => DBMS_LOCK.X_MODE,
	timeout 	    => 5,
	release_on_commit   => TRUE
      );
      IF v_lock_result NOT IN (0, 4) THEN
	RAISE_APPLICATION_ERROR(-20060, 'Table is busy, try again.');
      END IF;
    END IF;

    BEGIN
      IF p_desk IS NOT NULL THEN
	SELECT COUNT(*) INTO v_cnt
	  FROM vmdb_comenz_restaurant
	 WHERE desk = p_desk AND state IN (1, 2);

	IF v_cnt > 0 THEN
	  RAISE_APPLICATION_ERROR(-20061, 'Table already has an open order.');
	END IF;
      END IF;

      -- Fara masa si fara comentariu explicit => marcajul de pachet il pune
      -- pachetul, nu aplicatia (vezi c_takeaway_mark).
      --
      -- NRDOC se pune LA CREARE, ca la clientul UAMenu, nu doar la plata: comanda
      -- poate fi achitata si de la casa, si atunci pay_order-ul nostru nu mai
      -- trece pe-acolo ca s-o repare (vezi current_nrdoc).
      INSERT INTO vmdb_comenz_restaurant (nr_comand, data_comand, doc_type, oficiant, desk, state, tipplata, barmen, coment, nrdoc)
      VALUES (NULL, SYSDATE, 1, p_waiter, p_desk, 1, p_pay_type, v_barmen,
	      NVL(p_coment, CASE WHEN p_desk IS NULL THEN c_takeaway_mark END),
	      v_nrdoc);

      SELECT comenz.currval INTO v_nr_comand FROM dual;

      COMMIT;
    EXCEPTION
      WHEN OTHERS THEN
	ROLLBACK;
	IF v_lock_handle IS NOT NULL THEN
	  v_lock_result := DBMS_LOCK.RELEASE(v_lock_handle);
	END IF;
	RAISE;
    END;

    IF v_lock_handle IS NOT NULL THEN
      v_lock_result := DBMS_LOCK.RELEASE(v_lock_handle);
    END IF;
    RETURN v_nr_comand;
  END create_order;

  FUNCTION add_order_line(
    p_nr_comand    IN NUMBER,
    p_product	   IN NUMBER,
    p_qty	   IN NUMBER,
    p_parent_nrord IN NUMBER DEFAULT NULL,
    p_commentary   IN VARCHAR2 DEFAULT NULL
  ) RETURN NUMBER IS
    v_t     NUMBER;
    v_nrord NUMBER;
  BEGIN
    SELECT NVL(MAX(t), -1) + 1 INTO v_t
    FROM vmdb_comenzd
    WHERE nr_comand = p_nr_comand AND bliuda = p_product;

    INSERT INTO vmdb_comenzd (nr_comand, bliuda, cant, t, parent_nrord, commentary)
    VALUES (p_nr_comand, p_product, p_qty, v_t, p_parent_nrord, p_commentary);

    SELECT nrord INTO v_nrord
    FROM vmdb_comenzd
    WHERE nr_comand = p_nr_comand AND bliuda = p_product AND t = v_t;

    RETURN v_nrord;
  END add_order_line;

  FUNCTION update_order_desk(
    p_nr_comand IN NUMBER,
    p_desk	IN NUMBER
  ) RETURN NUMBER IS
    v_cnt NUMBER;
  BEGIN
    -- p_desk NULL = comanda devine LA PACHET (clientul de la masa cere sa i se
    -- impacheteze). Nu exista masa cu care sa se ciocneasca, deci verificarea
    -- de mai jos se sare EXPLICIT - cu NULL n-ar intoarce oricum niciun rand,
    -- dar atunci ar fi inerta din accident, nu din intentie.
    IF p_desk IS NOT NULL THEN
      SELECT COUNT(*) INTO v_cnt
	FROM vmdb_comenz_restaurant
       WHERE desk = p_desk
	 AND state IN (1, 2)
	 AND nr_comand != p_nr_comand;

      IF v_cnt > 0 THEN
	RAISE_APPLICATION_ERROR(-20050, 'Table already has another open order.');
      END IF;
    END IF;

    -- Marcajul de pachet urmeaza masa, in ambele sensuri:
    --   fara masa  -> il punem (comanda a devenit la pachet)
    --   cu masa    -> il stergem, ALTFEL BONUL FISCAL AL UNEI COMENZI DE LA
    --                 MASA I-AR IESI CLIENTULUI CU "La pachet" TIPARIT PE EL.
    -- Stergem doar exact textul nostru: un comentariu real, scris de cineva in
    -- UAMenu, nu are voie sa dispara pentru ca s-a mutat comanda.
    UPDATE vmdb_comenz_restaurant
       SET desk   = p_desk,
	   coment = CASE
		      WHEN p_desk IS NULL	     THEN c_takeaway_mark
		      WHEN coment = c_takeaway_mark THEN NULL
		      ELSE coment
		    END
     WHERE nr_comand = p_nr_comand;

    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20051, 'Order not found.');
    END IF;

    RETURN p_desk;
  END update_order_desk;

  FUNCTION cancel_order(
    p_nr_comand IN NUMBER
  ) RETURN NUMBER IS
    v_state NUMBER;
  BEGIN
    SELECT state INTO v_state
      FROM vmdb_comenz_restaurant
     WHERE nr_comand = p_nr_comand;

    IF v_state NOT IN (1, 2) THEN
      RAISE_APPLICATION_ERROR(-20052, 'Order can no longer be cancelled (state=' || v_state || ').');
    END IF;

    UPDATE vmdb_comenz_restaurant
       SET state = 4
     WHERE nr_comand = p_nr_comand;

    RETURN p_nr_comand;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20051, 'Order not found.');
  END cancel_order;

  -- Jurnal de incidente fiscale. Scris in TRANZACTIE AUTONOMA, anume ca sa
  -- supravietuiasca ROLLBACK-ului care insoteste eroarea ridicata imediat dupa:
  -- fara asta, exact dovada incidentului ar disparea odata cu el.
  --
  -- Serveste si drept memorie a ce am semnalat deja. O comanda cu bon dublu nu
  -- se poate repara din aplicatie (bonul e in memoria fiscala a aparatului),
  -- deci daca am ridica eroarea la FIECARE reluare, chelnerul ar primi acelasi
  -- dialog la nesfarsit, pe o problema pe care n-are cum s-o rezolve. Asa:
  -- prima data se semnaleaza zgomotos, apoi apelul trece si reluarea converge.
  PROCEDURE log_fiscal_incident(
    p_nr_comand IN NUMBER,
    p_doc       IN VARCHAR2,
    p_kind      IN VARCHAR2,
    p_note      IN VARCHAR2,
    p_first     OUT BOOLEAN
  ) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO uw_fiscal_incidents(nr_comand, document_number, kind, note)
    VALUES (p_nr_comand, p_doc, p_kind, SUBSTR(p_note, 1, 400));
    COMMIT;
    p_first := TRUE;
  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      -- Deja semnalat pentru aceeasi comanda si acelasi document.
      ROLLBACK;
      p_first := FALSE;
  END log_fiscal_incident;

  FUNCTION pay_order(
    p_nr_comand  IN NUMBER,
    p_pay_type   IN NUMBER,
    p_pay        IN NUMBER   DEFAULT NULL,
    p_doc_fiscal IN VARCHAR2 DEFAULT NULL,
    p_oficiant   IN NUMBER   DEFAULT NULL,
    p_amount     IN NUMBER   DEFAULT NULL,
    p_rrn        IN VARCHAR2 DEFAULT NULL
  ) RETURN NUMBER IS
    v_state       NUMBER;
    v_cost        NUMBER;
    v_nrdoc       NUMBER;
    v_lock_handle VARCHAR2(128);
    v_lock_result NUMBER;
    v_doc_known   uw_fiscal_receipts.document_number%TYPE;
    v_has_receipt NUMBER;
    v_first       BOOLEAN;
  BEGIN
    IF p_pay_type NOT IN (1, 2) THEN
      RAISE_APPLICATION_ERROR(-20054,
        'Unsupported payment type (' || p_pay_type || ').');
    END IF;

    -- Serializam pe COMANDA, ca la create_order pe masa. Fara blocaj, doua
    -- dispozitive care achita simultan aceeasi comanda citeau amandoua state=1
    -- si treceau amandoua mai departe - iar verificarile de mai jos, oricat de
    -- stricte, s-ar fi facut pe o stare deja invechita.
    DBMS_LOCK.ALLOCATE_UNIQUE('UW_PAY_LOCK_' || p_nr_comand, v_lock_handle);
    v_lock_result := DBMS_LOCK.REQUEST(
      lockhandle        => v_lock_handle,
      lockmode          => DBMS_LOCK.X_MODE,
      timeout           => 5,
      release_on_commit => TRUE
    );
    IF v_lock_result NOT IN (0, 4) THEN
      RAISE_APPLICATION_ERROR(-20062,
        'Order is being paid on another device, try again.');
    END IF;

    BEGIN
      SELECT state, NVL(clccostt, 0) INTO v_state, v_cost
        FROM vmdb_comenz_restaurant
       WHERE nr_comand = p_nr_comand;

      -- Bonul e document legal: daca suma tiparita nu e suma comenzii, comanda
      -- s-a schimbat intre citirea liniilor si plata. Mai bine oprim decat sa
      -- inregistram tacut un bon care nu corespunde comenzii.
      -- Parametru OPTIONAL: cat timp clientul nu-l trimite, verificarea doarme,
      -- deci apelurile vechi cu 5 argumente raman valabile.
      IF p_amount IS NOT NULL AND ABS(p_amount - v_cost) > 0.005 THEN
        RAISE_APPLICATION_ERROR(-20057,
          'Receipt total (' || p_amount || ') does not match order total (' ||
          v_cost || ').');
      END IF;

      BEGIN
        SELECT document_number INTO v_doc_known
          FROM uw_fiscal_receipts
         WHERE nr_comand = p_nr_comand;
        v_has_receipt := 1;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          v_has_receipt := 0;
          v_doc_known   := NULL;
      END;

      -- DUBLA FISCALIZARE, cazul 1: avem deja un bon inregistrat, dar vine ALT
      -- numar de document. Discriminatorul e chiar numarul: o reluare legitima
      -- retrimite mereu ACELASI numar (clientul il tine in pending_fiscal.json),
      -- deci unul diferit inseamna un al doilea bon emis pe aceeasi comanda.
      -- Vechiul "MERGE ... WHEN NOT MATCHED" il ignora tacut - adica PK-ul de pe
      -- nr_comand nu bara nimic, doar evita ORA-00001.
      IF v_has_receipt = 1
         AND p_doc_fiscal IS NOT NULL
         AND v_doc_known IS NOT NULL
         AND p_doc_fiscal <> v_doc_known THEN
        log_fiscal_incident(p_nr_comand, p_doc_fiscal, 'SECOND_RECEIPT',
          'Order already had receipt ' || v_doc_known, v_first);
        IF v_first THEN
          RAISE_APPLICATION_ERROR(-20055,
            'Order already has fiscal receipt ' || v_doc_known ||
            '; a second one (' || p_doc_fiscal || ') was issued.');
        END IF;
      END IF;

      IF v_state IN (1, 2) THEN
        -- Plasa de siguranta pentru comenzile create inainte ca NRDOC sa fie pus
        -- la creare (vezi create_order): daca lipseste, il luam din tura curenta.
        v_nrdoc := current_nrdoc;

        -- Modelul real de plata din UAMenu, verificat pe productie:
        --   numerar (1) -> PAY = suma primita de la client (poate depasi
        --                  totalul; restul se da manual), SUMA_TERMINAL NULL
        --   card    (2) -> PAY = 0, SUMA_TERMINAL = totalul comenzii
        -- Inversarea lor ar strica rapoartele UAMenu si ar cadea in validarea
        -- "nu ajung bani pentru achitare" din TRG_VMDB_COMENZ_RESTAURANT.
        -- DATA1 = data tranzactiei ("Дата транз" in UAMenu). Fara ea comanda
        -- arata incompleta si lipseste din rapoartele pe interval orar.
        IF p_pay_type = 1 THEN
          UPDATE vmdb_comenz_restaurant
             SET state = 3, tipplata = 1, pay = NVL(p_pay, v_cost),
                 cek = 1, nrdoc = NVL(nrdoc, v_nrdoc), data1 = SYSDATE
           WHERE nr_comand = p_nr_comand;
        ELSE
          UPDATE vmdb_comenz_restaurant
             SET state = 3, tipplata = 2, pay = 0, suma_terminal = v_cost,
                 cek = 1, nrdoc = NVL(nrdoc, v_nrdoc), data1 = SYSDATE
           WHERE nr_comand = p_nr_comand;
        END IF;

        IF SQL%ROWCOUNT = 0 THEN
          RAISE_APPLICATION_ERROR(-20051, 'Order not found.');
        END IF;

      ELSIF v_state = 3 THEN
        -- Deja achitata. O RELUARE legitima are intotdeauna randul ei de bon,
        -- pus de apelul care a reusit inaintea ei. Daca randul LIPSESTE dar noi
        -- venim cu un document, inseamna ca altcineva (casa sau alt dispozitiv)
        -- a inchis comanda intre emiterea bonului nostru si apelul asta - adica
        -- s-au emis doua bonuri. Cazul NU e teoretic: pe baza de test 19 din 20
        -- de comenzi achitate n-au rand de bon, fiind inchise de la casa.
        IF v_has_receipt = 0 AND p_doc_fiscal IS NOT NULL THEN
          log_fiscal_incident(p_nr_comand, p_doc_fiscal, 'CLOSED_ELSEWHERE',
            'Order was already state=3 without a receipt row', v_first);
          IF v_first THEN
            RAISE_APPLICATION_ERROR(-20056,
              'Order was already closed by someone else; the receipt (' ||
              p_doc_fiscal || ') issued here is a second one.');
          END IF;
        END IF;
      ELSE
        RAISE_APPLICATION_ERROR(-20053,
          'Order can no longer be paid (state=' || v_state || ').');
      END IF;

      -- MERGE, nu INSERT: la o reluare randul exista deja, iar PK-ul pe
      -- nr_comand ar arunca ORA-00001 si ar transforma o reluare corecta
      -- intr-o eroare. Detectarea bonului dublu s-a facut mai sus - aici a
      -- ramas doar idempotenta, care era si intentia initiala.
      MERGE INTO uw_fiscal_receipts r
      USING (SELECT p_nr_comand AS nr_comand FROM dual) s
         ON (r.nr_comand = s.nr_comand)
      WHEN MATCHED THEN
        -- Completam documentul si RRN-ul daca randul a fost scris fara ele; nu
        -- le suprascriem niciodata cu altele (ar sterge urma primei plati).
        UPDATE SET r.document_number = NVL(r.document_number, p_doc_fiscal),
                   r.rrn             = NVL(r.rrn, p_rrn)
      WHEN NOT MATCHED THEN
        INSERT (nr_comand, document_number, pay_type, amount, oficiant, rrn)
        VALUES (p_nr_comand, p_doc_fiscal, p_pay_type, v_cost, p_oficiant, p_rrn);

      COMMIT;
    EXCEPTION
      WHEN OTHERS THEN
        ROLLBACK;
        IF v_lock_handle IS NOT NULL THEN
          v_lock_result := DBMS_LOCK.RELEASE(v_lock_handle);
        END IF;
        RAISE;
    END;

    IF v_lock_handle IS NOT NULL THEN
      v_lock_result := DBMS_LOCK.RELEASE(v_lock_handle);
    END IF;
    RETURN p_nr_comand;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      ROLLBACK;
      IF v_lock_handle IS NOT NULL THEN
        v_lock_result := DBMS_LOCK.RELEASE(v_lock_handle);
      END IF;
      RAISE_APPLICATION_ERROR(-20051, 'Order not found.');
  END pay_order;

  -- get_update_info a fost scoasa de aici pe 2026-08-03 - vezi explicatia din
  -- specificatie. Era singura referinta a pachetului in afara schemei
  -- aplicatiei, si singurul motiv pentru care pachetul nu putea fi instalat pe
  -- fronturile de productie.

END pg_mobile_web_waiter;

/

-- ===========================================================================
-- VERIFICARE — e instalat UnaWaiter corect pe frontul ăsta?
-- ===========================================================================
-- READ-ONLY. Nu creează, nu modifică și nu șterge nimic. Se poate rula oricând,
-- inclusiv pe o bază unde nu e instalat nimic — atunci raportează frumos ce
-- lipsește, în loc să crape.
--
--   sqlplus unirest/unirest@93.116.209.117:1521/xe
--   SQL> @99_verify.sql 11
--
-- Iese cu eroare (deci și install_front.bat eșuează) dacă vreo verificare pică.
--
-- Tot ce atinge tabelele NOASTRE trece prin EXECUTE IMMEDIATE, intenționat: pe o
-- bază curată un `SELECT ... FROM uw_zones` scris direct ar face blocul întreg să
-- nu compileze (PLS-00201), și în loc de raport ai primi o singură eroare seacă.
-- ===========================================================================

DEFINE cod_univ = &1

SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF
SET FEEDBACK OFF
WHENEVER SQLERROR EXIT FAILURE

DECLARE
  v_filiala NUMBER := &cod_univ;
  v_fail    NUMBER := 0;
  v_warn    NUMBER := 0;
  v_n       NUMBER;
  v_s       VARCHAR2(4000);

  PROCEDURE titlu(p_t VARCHAR2) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(' ');
    DBMS_OUTPUT.PUT_LINE('--- ' || p_t || ' ' || RPAD('-', 60 - LENGTH(p_t), '-'));
  END;

  -- NVL2 e functie SQL, nu exista in PL/SQL pur (PLS-00201) - de aceea CASE.
  PROCEDURE chk(p_ok BOOLEAN, p_ce VARCHAR2, p_detaliu VARCHAR2 DEFAULT NULL) IS
    v_d VARCHAR2(4000) := CASE WHEN p_detaliu IS NULL THEN '' ELSE '  (' || p_detaliu || ')' END;
  BEGIN
    IF p_ok THEN
      DBMS_OUTPUT.PUT_LINE('  OK     ' || p_ce || v_d);
    ELSE
      v_fail := v_fail + 1;
      DBMS_OUTPUT.PUT_LINE('  PICAT  ' || p_ce || v_d);
    END IF;
  END;

  PROCEDURE avert(p_ce VARCHAR2) IS
  BEGIN
    v_warn := v_warn + 1;
    DBMS_OUTPUT.PUT_LINE('  ATENTIE ' || p_ce);
  END;

  FUNCTION exista(p_name VARCHAR2, p_type VARCHAR2 DEFAULT NULL) RETURN BOOLEAN IS
    n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO n FROM user_objects
     WHERE object_name = p_name
       AND (p_type IS NULL OR object_type = p_type);
    RETURN n > 0;
  END;

  FUNCTION e_valid(p_name VARCHAR2, p_type VARCHAR2) RETURN BOOLEAN IS
    n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO n FROM user_objects
     WHERE object_name = p_name AND object_type = p_type AND status = 'VALID';
    RETURN n > 0;
  END;

  -- Numără rânduri într-un tabel care s-ar putea să nu existe încă.
  -- -1 = interogarea n-a putut rula (de regulă: tabelul lipsește).
  FUNCTION nr_randuri(p_sql VARCHAR2) RETURN NUMBER IS
    n NUMBER;
  BEGIN
    EXECUTE IMMEDIATE p_sql INTO n;
    RETURN n;
  EXCEPTION
    WHEN OTHERS THEN RETURN -1;
  END;

  -- Ca raportul să spună „tabelul lipseste", nu „-1 zone".
  FUNCTION cat(p_n NUMBER, p_unitate VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    IF p_n = -1 THEN
      RETURN 'tabelul lipseste';
    END IF;
    RETURN p_n || ' ' || p_unitate;
  END;

BEGIN
  DBMS_OUTPUT.PUT_LINE(' ');
  DBMS_OUTPUT.PUT_LINE('===========================================================');
  DBMS_OUTPUT.PUT_LINE(' VERIFICARE UnaWaiter — filiala ' || v_filiala);
  DBMS_OUTPUT.PUT_LINE(' schema ' || USER || ' @ ' || SYS_CONTEXT('userenv','db_name') ||
                       '   ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI'));
  DBMS_OUTPUT.PUT_LINE('===========================================================');

  -- =========================================================== structura ===
  titlu('Tabelele noastre');
  chk(exista('UW_ZONES','TABLE'),            'UW_ZONES');
  chk(exista('UW_TABLES','TABLE'),           'UW_TABLES');
  chk(exista('UW_WAITERS','TABLE'),          'UW_WAITERS');
  chk(exista('UW_FISCAL_RECEIPTS','TABLE'),  'UW_FISCAL_RECEIPTS');
  chk(exista('UW_FISCAL_INCIDENTS','TABLE'), 'UW_FISCAL_INCIDENTS');

  SELECT COUNT(*) INTO v_n FROM user_tab_columns
   WHERE table_name = 'UW_FISCAL_RECEIPTS' AND column_name = 'RRN';
  chk(v_n = 1, 'coloana RRN pe UW_FISCAL_RECEIPTS',
      'fara ea, plata "RRN manual" cade dupa tiparirea bonului');

  titlu('Constrangeri si indecsi');
  SELECT COUNT(*) INTO v_n FROM user_constraints
   WHERE constraint_name = 'UW_TABLES_ZONE_FK' AND constraint_type = 'R';
  chk(v_n = 1, 'cheia straina UW_TABLES_ZONE_FK');

  chk(exista('UW_TABLES_ZONE_IX','INDEX'), 'indexul UW_TABLES_ZONE_IX',
      'fara el, un DELETE pe zone ia lock de tabel pe mese');

  SELECT COUNT(*) INTO v_n FROM user_constraints
   WHERE constraint_name IN ('UW_ZONES_RESERVED_CK','UW_ZONES_CODE_CK','UW_WAITERS_PIN_CK');
  chk(v_n = 3, 'cele 3 CHECK-uri de validare', 'gasite ' || v_n || ' din 3');

  titlu('View-uri');
  chk(e_valid('VUW_WAITERS','VIEW'), 'VUW_WAITERS valid');
  chk(e_valid('VUW_ZONES','VIEW'),   'VUW_ZONES valid');
  chk(e_valid('VUW_TABLES','VIEW'),  'VUW_TABLES valid');

  titlu('Pachetul');
  chk(e_valid('PG_MOBILE_WEB_WAITER','PACKAGE'),      'specificatia — VALID');
  chk(e_valid('PG_MOBILE_WEB_WAITER','PACKAGE BODY'), 'corpul — VALID');

  IF exista('PG_MOBILE_WEB_WAITER','PACKAGE BODY')
     AND NOT e_valid('PG_MOBILE_WEB_WAITER','PACKAGE BODY') THEN
    DBMS_OUTPUT.PUT_LINE('         >>> ruleaza: SHOW ERRORS PACKAGE BODY pg_mobile_web_waiter');
  END IF;

  -- Referinta la schema de configurare: pe test e SUN, in ACEEASI baza. Pe
  -- productie schema aia NU EXISTA pe front, deci corpul nu compileaza.
  SELECT COUNT(*) INTO v_n FROM user_source
   WHERE name = 'PG_MOBILE_WEB_WAITER' AND type = 'PACKAGE BODY'
     AND UPPER(text) LIKE '%FROM SUN.A$ADM%';
  IF v_n > 0 THEN
    SELECT COUNT(*) INTO v_n FROM all_objects WHERE owner = 'SUN';
    IF v_n = 0 THEN
      chk(FALSE, 'get_update_info refera SUN.A$ADM, dar schema SUN nu exista aici',
          'vezi docs/migrare-productie §3.1');
    END IF;
  END IF;

  -- =============================================================== date ===
  titlu('Datele filialei ' || v_filiala);

  v_n := nr_randuri('SELECT COUNT(*) FROM uw_zones WHERE cod_univ = ' || v_filiala);
  chk(v_n > 0, 'zone definite', cat(v_n, 'zone'));

  v_n := nr_randuri('SELECT COUNT(*) FROM uw_tables WHERE cod_univ = ' || v_filiala);
  chk(v_n > 0, 'mese definite', cat(v_n, 'mese'));

  v_n := nr_randuri('SELECT COUNT(*) FROM uw_tables t WHERE t.cod_univ = ' || v_filiala ||
                    ' AND NOT EXISTS (SELECT 1 FROM uw_zones z WHERE z.cod_univ = t.cod_univ' ||
                    ' AND z.zone_code = t.zone)');
  chk(v_n = 0, 'nicio masa fara zona valida', cat(v_n, 'orfane'));

  v_n := nr_randuri('SELECT COUNT(*) FROM uw_zones WHERE cod_univ = ' || v_filiala ||
                    ' AND active = 1');
  IF v_n = 0 THEN
    avert('toate zonele filialei sunt inactive — aplicatia n-ar arata nicio masa');
  END IF;

  v_n := nr_randuri('SELECT COUNT(*) FROM uw_waiters WHERE cod_univ = ' || v_filiala);
  IF v_n = 0 THEN
    avert('niciun chelner alocat filialei — se aloca din forma din back-office, ' ||
          'sau prin auto-inrolare la prima logare');
  ELSIF v_n > 0 THEN
    DBMS_OUTPUT.PUT_LINE('  info   ' || v_n || ' chelneri alocati filialei');
  END IF;

  -- ============================================ dependinte din UAMenu ===
  titlu('Dependinte UAMenu (trebuie sa existe deja pe front)');
  chk(e_valid('UNIREST_UTIL','PACKAGE BODY'), 'UNIREST_UTIL — VALID');

  SELECT COUNT(*) INTO v_n FROM user_procedures
   WHERE object_name = 'UNIREST_UTIL' AND procedure_name = 'GLOBAL_DEP';
  chk(v_n > 0, 'unirest_util.global_dep', 'seteaza filiala sesiunii');

  SELECT COUNT(*) INTO v_n FROM user_procedures
   WHERE object_name = 'UNIREST_UTIL' AND procedure_name = 'VAT_PERCENT_BY_LETTER';
  chk(v_n > 0, 'unirest_util.vat_percent_by_letter', 'cota TVA pentru bonul fiscal');

  chk(exista('VMDB_COMENZ_RESTAURANT'), 'VMDB_COMENZ_RESTAURANT');
  chk(exista('VMDB_COMENZD'),           'VMDB_COMENZD');
  chk(exista('VMS_UNIVERS'),            'VMS_UNIVERS');
  chk(exista('VMS_BLIUDA'),             'VMS_BLIUDA (meniul)');
  chk(exista('VMS_SYSS'),               'VMS_SYSS (tipuri de plata)');
  chk(exista('VSLRPRM_CALCD_R_502'),    'VSLRPRM_CALCD_R_502 (lista de personal)');
  chk(exista('TMDB_SOLD','TABLE'),      'TMDB_SOLD (tura)');
  chk(exista('TMS_CASIR','TABLE'),      'TMS_CASIR (casieri)');
  chk(exista('COMENZ','SEQUENCE'),      'secventa COMENZ');

  SELECT COUNT(*) INTO v_n FROM all_objects
   WHERE object_name = 'DBMS_LOCK' AND object_type = 'PACKAGE';
  chk(v_n > 0, 'DBMS_LOCK accesibil', 'serializarea meselor si a platilor');

  -- ================================================== mediul de sesiune ===
  titlu('Mediul de sesiune');
  v_s := SYS_CONTEXT('envunirest','kadr_doljn_r_502');
  chk(v_s IS NOT NULL, 'contextul kadr_doljn_r_502 (pus de TRG_ON_LOGON)',
      NVL(v_s, 'NESETAT — lista de chelneri ar iesi goala'));

  v_n := nr_randuri('SELECT COUNT(*) FROM vslrprm_calcd_r_502');
  chk(v_n > 0, 'lista de personal intoarce randuri', v_n || ' angajati');

  v_n := nr_randuri('SELECT COUNT(*) FROM vms_univers WHERE cod = ' || v_filiala ||
                    ' AND gr1 = ''FL'' AND tip = ''O''');
  chk(v_n = 1, 'filiala ' || v_filiala || ' exista in vms_univers (gr1=FL)');

  v_n := nr_randuri('SELECT NVL(MAX(nrdoc),-1) FROM tmdb_sold');
  chk(v_n > 0, 'exista o tura deschisa (MAX(nrdoc) din TMDB_SOLD)',
      'nrdoc = ' || v_n || '; fara ea comenzile nu ajung in documentul din Back');

  -- ======================================== proba functionala, read-only ===
  IF e_valid('PG_MOBILE_WEB_WAITER','PACKAGE BODY') THEN
    titlu('Proba functionala (read-only)');

    BEGIN
      EXECUTE IMMEDIATE
        'BEGIN :r := pg_mobile_web_waiter.set_restaurant(:c); END;'
        USING OUT v_s, IN v_filiala;
      chk(INSTR(v_s, '"ok"') > 0, 'set_restaurant(' || v_filiala || ')', v_s);
    EXCEPTION
      WHEN OTHERS THEN chk(FALSE, 'set_restaurant', SQLERRM);
    END;

    DECLARE
      c        SYS_REFCURSOR;
      v_zone   VARCHAR2(20);
      v_tno    NUMBER;
      v_ro     VARCHAR2(60);
      v_ru     VARCHAR2(60);
      v_en     VARCHAR2(60);
      v_ord    NUMBER;
      v_cnt    NUMBER := 0;
    BEGIN
      EXECUTE IMMEDIATE 'BEGIN :c := pg_mobile_web_waiter.get_tables; END;' USING OUT c;
      LOOP
        FETCH c INTO v_zone, v_tno, v_ro, v_ru, v_en, v_ord;
        EXIT WHEN c%NOTFOUND;
        v_cnt := v_cnt + 1;
      END LOOP;
      CLOSE c;
      chk(v_cnt > 0, 'get_tables intoarce mese', v_cnt || ' mese vizibile in aplicatie');
    EXCEPTION
      WHEN OTHERS THEN chk(FALSE, 'get_tables', SQLERRM);
    END;

    DECLARE
      c       SYS_REFCURSOR;
      v_cod   NUMBER;
      v_den   VARCHAR2(200);
      v_pin   NUMBER;
      v_cnt   NUMBER := 0;
    BEGIN
      EXECUTE IMMEDIATE 'BEGIN :c := pg_mobile_web_waiter.get_waiters; END;' USING OUT c;
      LOOP
        FETCH c INTO v_cod, v_den, v_pin;
        EXIT WHEN c%NOTFOUND;
        v_cnt := v_cnt + 1;
      END LOOP;
      CLOSE c;
      chk(v_cnt > 0, 'get_waiters intoarce chelneri', v_cnt || ' nume in ecranul de login');
    EXCEPTION
      WHEN OTHERS THEN chk(FALSE, 'get_waiters', SQLERRM);
    END;

    DECLARE
      c       SYS_REFCURSOR;
      v_cod   NUMBER;
      v_den   VARCHAR2(200);
      v_cnt   NUMBER := 0;
    BEGIN
      EXECUTE IMMEDIATE 'BEGIN :c := pg_mobile_web_waiter.get_categories; END;' USING OUT c;
      LOOP
        FETCH c INTO v_cod, v_den;
        EXIT WHEN c%NOTFOUND;
        v_cnt := v_cnt + 1;
      END LOOP;
      CLOSE c;
      chk(v_cnt > 0, 'get_categories intoarce meniul', v_cnt || ' categorii');
    EXCEPTION
      WHEN OTHERS THEN chk(FALSE, 'get_categories', SQLERRM);
    END;
  END IF;

  -- ============================================================ concluzie ===
  DBMS_OUTPUT.PUT_LINE(' ');
  DBMS_OUTPUT.PUT_LINE('===========================================================');
  IF v_fail = 0 THEN
    DBMS_OUTPUT.PUT_LINE(' REZULTAT: TOTUL E PE LOC' ||
                         CASE WHEN v_warn > 0 THEN '  (' || v_warn || ' atentionari)' END);
    DBMS_OUTPUT.PUT_LINE('===========================================================');
  ELSE
    DBMS_OUTPUT.PUT_LINE(' REZULTAT: ' || v_fail || ' VERIFICARI PICATE');
    DBMS_OUTPUT.PUT_LINE('===========================================================');
    RAISE_APPLICATION_ERROR(-20090,
      'Verificare picata: ' || v_fail || ' probleme. Vezi lista de mai sus.');
  END IF;
END;
/

SET FEEDBACK ON

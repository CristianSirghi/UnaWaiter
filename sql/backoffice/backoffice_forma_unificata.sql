-- ############################################################################
-- ##  ISTORIC — NU RULA PE PRODUCTIE                                        ##
-- ##                                                                        ##
-- ##  Fisierul asta a fost scris pentru TEST si are obj_id HARDCODATE        ##
-- ##  (1996/1997/1998/1999, sabloane 1867/1868). Pe productie aceleasi       ##
-- ##  numere sunt ALTE obiecte, reale: salarizare, rapoarte, actiuni.        ##
-- ##  Scriptul de chelneri face `update a$adp` si `delete from a$lob` direct ##
-- ##  pe 1996, fara nicio verificare - ar corupe un obiect de pontaj.        ##
-- ##                                                                        ##
-- ##  FOLOSESTE:  sql/backoffice/forme/install_forme.sql                     ##
-- ##  (portabil, fara obj_id scrise de mana, cu garda)                       ##
-- ##                                                                        ##
-- ##  Pastrat aici doar ca urma a felului in care au fost construite         ##
-- ##  formele pe test.                              -- 2026-08-03            ##
-- ############################################################################

-- Forma UNIFICATA pe 3 niveluri, ceruta de Daniela pe 2026-07-30:
--     locatia  ->  zonele ei  ->  mesele zonei
--
-- Avantajul real, nu de stil: managerul nu mai tasteaza `cod_univ` si nici codul
-- zonei - se mostenesc din randul selectat mai sus. Astea erau singurele campuri
-- unde o greseala de tastare muta mese la alt restaurant.
--
-- Validata pe TEST pe 2026-07-30. A INLOCUIT formele separate 1997 "Zone" si
-- 1998 "Mese", sterse dupa aceea (se pot recrea oricand din
-- backoffice_forme_zone_mese.sql).
--
-- Confirmat empiric la rulare - niciun alt formular din instalare nu are
-- XSQL/YSQL completate, deci n-a existat exemplu de copiat:
--   * legarea grilei-copil de randul selectat se face prin bind normal
--     (`:cod_univ`, `:zone_code`);
--   * EDITQUERY1/2/3 CHIAR corespund celor trei niveluri: cu EDITQUERY1 = 0,
--     grila de locatii devine needitabila;
--   * la INSERT/UPDATE parametrii se leaga de campurile PROPRIEI grile, nu ale
--     parintelui (vezi nota de la YSQL_INSERT).
--
-- Nivelul de sus e READ-ONLY intentionat: restaurantele vin din registrul
-- ybmb_dif_cassa, nu se creeaza de aici.
--
-- >>> DUPA orice modificare a unei interogari de aici, ruleaza si
-- >>> backoffice_sync_grid_sql.sql - altfel clientul continua sa execute
-- >>> varianta veche, din cache-ul A$LOB.

set define off
set serveroutput on size 100000

declare
  c_src   constant number := 1997;   -- clonam forma de Zone, deja validata
  c_new   constant number := 1999;
  c_ycfg  constant number := 1867;   -- singura forma care ARE cheile YSQL*
  c_mdet  constant number := 1868;   -- "Furnizori": forma cu 3 niveluri care merge
  v_n     number;

  procedure memo(p_key varchar2, p_val varchar2) is
  begin
    update a$adp set svalue = p_val, lvalue = to_clob(p_val)
     where obj_id = c_new and key = p_key;
    if sql%rowcount = 0 then
      raise_application_error(-20099, 'Proprietatea '||p_key||' lipseste la nodul '||c_new);
    end if;
  end;

  procedure flag(p_key varchar2, p_val varchar2) is
  begin
    update a$adp set bvalue = p_val where obj_id = c_new and key = p_key;
    if sql%rowcount = 0 then
      raise_application_error(-20099, 'Flagul '||p_key||' lipseste la nodul '||c_new);
    end if;
  end;

  procedure num(p_key varchar2, p_val number) is
  begin
    update a$adp set ivalue = p_val where obj_id = c_new and key = p_key;
  end;
begin
  select count(*) into v_n from a$adm where obj_id = c_new;
  if v_n > 0 then
    raise_application_error(-20098, 'Nodul '||c_new||' exista deja - vezi Dezfacere.');
  end if;

  -- ---------------------------------------------------------------- clonare
  insert into a$adm (obj_id, sys_id, obj_type, obj_subtype, link_id, parent_id,
                     template_id, name0, name1, name2, section, nrord,
                     date_begin, date_final, modified)
  select c_new, sys_id, obj_type, obj_subtype, link_id, parent_id, template_id,
         '14. Amplasare mese', '14. Amplasare mese', '14. Размещение столов',
         'F_UWPLAN', c_new, date_begin, date_final, sysdate
    from a$adm where obj_id = c_src;

  insert into a$adp (obj_id, key, name, hint, gr, vtype, value0, value1, value2,
                     svalue, ivalue, bvalue, dvalue, lvalue, attr, fvalue)
  select c_new, key, name, hint, gr, vtype, value0, value1, value2,
         svalue, ivalue, bvalue, dvalue, lvalue, attr, fvalue
    from a$adp where obj_id = c_src;

  -- Formele noastre au fost clonate dintr-una cu UN SINGUR nivel, deci le
  -- lipsesc atat cheile nivelului 3 (YSQL*), cat si cele de structura
  -- (FORMUSESUBDETAIL, MASTERSIZE2...). Le aducem GOALE din formele care le au:
  --   1867 - singura cu YSQL* definite
  --   1868 "Furnizori" - forma cu 3 niveluri care chiar merge
  insert into a$adp (obj_id, key, name, hint, gr, vtype, value0, value1, value2,
                     svalue, ivalue, bvalue, dvalue, lvalue, attr, fvalue)
  select c_new, key, name, hint, gr, vtype, null, null, null,
         null, null, null, null, null, attr, null
    from a$adp
   where obj_id = c_ycfg
     and key like 'Y%'
     and key not in (select key from a$adp where obj_id = c_new);

  insert into a$adp (obj_id, key, name, hint, gr, vtype, value0, value1, value2,
                     svalue, ivalue, bvalue, dvalue, lvalue, attr, fvalue)
  select c_new, key, name, hint, gr, vtype, null, null, null,
         null, null, null, null, null, attr, null
    from a$adp
   where obj_id = c_mdet
     and (key like 'FORMUSE%' or key = 'MASTERSIZE2')
     and key not in (select key from a$adp where obj_id = c_new);

  -- ------------------------------------------------------------- denumirea
  -- CAPTION e VTYPE='C': valoarea reala sta in VALUE1/VALUE2, iar SVALUE/LVALUE
  -- se lasa GOALE - exact ce face Configuratorul (capcana #5).
  -- Denumirea din arborele Configuratorului e alta: A$ADM.NAME0/1/2, pusa mai sus.
  update a$adp set value1 = '14. Amplasare mese', value2 = '14. Размещение столов',
                   svalue = null, lvalue = null
   where obj_id = c_new and key = 'CAPTION';

  -- --------------------------------------------- NIVEL 1: locatia (read-only)
  memo('SQL', 'select cod_univ, clcdenumirea, clcnrzone from vuw_locations order by cod_univ');
  memo('SQL_INSERT',  null);
  memo('SQL_UPDATE',  null);
  memo('SQL_DELETE',  null);
  memo('SQL_REFRESH', null);
  flag('EDITQUERY1', '0');   -- ipoteza: nivelul 1 devine needitabil

  -- ------------------------------------------------- NIVEL 2: zonele locatiei
  -- `:cod_univ` ar trebui sa vina din randul selectat in grila de sus.
  memo('XSQL',
    'select cod_univ, zone_code, name_ro, name_ru, name_en, display_order, active, clcnrmese'
    ||' from vuw_zones_all where cod_univ = :cod_univ'
    ||' order by nvl(display_order,999), zone_code');
  memo('XSQL_INSERT',
    'insert into vuw_zones_all (cod_univ, zone_code, name_ro, name_ru, name_en, display_order, active)'
    ||' values (:cod_univ, :zone_code, :name_ro, :name_ru, :name_en, :display_order, :active)');
  memo('XSQL_UPDATE',
    'update vuw_zones_all set name_ro = :name_ro, name_ru = :name_ru, name_en = :name_en,'
    ||' display_order = :display_order, active = :active'
    ||' where cod_univ = :cod_univ and zone_code = :zone_code');
  memo('XSQL_DELETE',
    'delete from vuw_zones_all where cod_univ = :cod_univ and zone_code = :zone_code');
  memo('XSQL_REFRESH',
    'select cod_univ, zone_code, name_ro, name_ru, name_en, display_order, active, clcnrmese'
    ||' from vuw_zones_all where cod_univ = :cod_univ and zone_code = :zone_code');

  -- -------------------------------------------------- NIVEL 3: mesele zonei
  memo('YSQL',
    'select cod_univ, table_no, zone, display_order, active'
    ||' from vuw_tables_all where cod_univ = :cod_univ and zone = :zone_code'
    ||' order by nvl(display_order, table_no), table_no');
  -- ATENTIE la numele parametrilor: la SELECT (YSQL de mai sus) se leaga de
  -- randul din grila-PARINTE, deci `:zone_code` e corect acolo. La INSERT/UPDATE
  -- se leaga de campurile PROPRIEI grile, unde coloana se numeste `zone`.
  -- Amestecate, clientul da "Not found field corresponding parameter zone_code".
  memo('YSQL_INSERT',
    'insert into vuw_tables_all (cod_univ, table_no, zone, display_order, active)'
    ||' values (:cod_univ, :table_no, :zone, :display_order, :active)');
  memo('YSQL_UPDATE',
    'update vuw_tables_all set display_order = :display_order, active = :active'
    ||' where cod_univ = :cod_univ and table_no = :table_no');
  memo('YSQL_DELETE',
    'delete from vuw_tables_all where cod_univ = :cod_univ and table_no = :table_no');
  memo('YSQL_REFRESH',
    'select cod_univ, table_no, zone, display_order, active'
    ||' from vuw_tables_all where cod_univ = :cod_univ and table_no = :table_no');

  -- CLCZONET nu mai apare la nivelul 3: zona se vede in grila de deasupra.
  -- La fel, `zone` ramane in SELECT doar ca sa fie ce trimite XSQL_INSERT.

  -- ----------------------------------------------------------- structura UI
  flag('FORMUSEDETAIL',    '1');
  flag('FORMUSESUBDETAIL', '1');
  flag('FORMNOGRID',       '0');
  num('MASTERSIZE',  200);
  num('MASTERSIZE2', 190);

  commit;
  dbms_output.put_line('Forma '||c_new||' "14. Amplasare mese" creata (3 niveluri).');
  dbms_output.put_line('REPORNESTE UniacCLNT.exe. Formele 1997/1998 sunt neatinse.');
exception
  when others then
    rollback;
    raise;
end;
/

-- ---------------------------------------------------------------------------
-- Dezfacere (daca experimentul nu iese)
-- ---------------------------------------------------------------------------
-- delete from a$lob where obj_id = 1999;
-- delete from a$adp where obj_id = 1999;
-- delete from a$adm where obj_id = 1999;
-- commit;

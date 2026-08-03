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

-- Formele "14. Zone UnaWaiter" si "15. Mese UnaWaiter" din back-office.
--
-- Se ruleaza in schema de back-office (test: SUN@clouddev), DUPA
-- backoffice_uw_all.sql - formele scriu prin view-urile si triggerele de acolo.
--
-- De ce prin SQL si nu din Configurator (docs/back-office/forme.md recomanda
-- unealta): aici CLONAM nodul 1996, care e deja validat si functional. Copierea
-- rand-cu-rand din A$ADP ia si proprietatile care NU sunt in catalogul A$ADS -
-- mai ales EDITQUERY1/2/3, fara de care grila iese read-only si nu se vede de ce.
-- Tastate de mana, exact alea se pierd.
--
-- Nodurile pot fi verificate/ajustate normal din Configurator dupa rulare.
--
-- >>> CAPCANA #1 (forme.md): proprietatile Memo stau in A$ADP.SVALUE **si**
-- >>> LVALUE. Configuratorul scrie SVALUE, clientul citeste SVALUE. Scriem
-- >>> mereu in amandoua, identic - de aia fiecare update de mai jos atinge si
-- >>> svalue, si lvalue.
-- >>> CAPCANA #2: dupa rulare, REPORNESTE UniacCLNT.exe. Definitia formelor se
-- >>> citeste la pornirea clientului, nu la deschiderea ferestrei.
-- >>> CAPCANA #4: deschide formele DUPA ce SQL-ul e scris. O forma deschisa
-- >>> peste o interogare goala isi salveaza o grila fara coloane in A$LOB.

set define off
set serveroutput on size 100000

declare
  c_src    constant number := 1996;    -- "13. Chelneri UnaWaiter", nodul-sablon
  c_zone   constant number := 1997;
  c_tables constant number := 1998;
  v_n      number;

  -- Scrie o proprietate Memo in ambele coloane. Vezi capcana #1.
  procedure memo(p_obj number, p_key varchar2, p_val varchar2) is
  begin
    update a$adp set svalue = p_val, lvalue = to_clob(p_val)
     where obj_id = p_obj and key = p_key;
    if sql%rowcount = 0 then
      raise_application_error(-20099, 'Proprietatea '||p_key||' lipseste la nodul '||p_obj);
    end if;
  end;

  -- CAPTION are VTYPE='C' - denumire MULTILINGVA, tinuta in VALUE1 (ro) si
  -- VALUE2 (ru). Clientul citeste VALUE1, NU svalue.
  --
  -- Dovada, masurata pe 2026-07-30: in tot back-office-ul sunt 42 de proprietati
  -- cu vtype='C'; toate 42 au VALUE1, si doar 3 au SVALUE (exact formele
  -- UnaWaiter). Scrisa doar in svalue, denumirea ramane cea clonata si TOATE
  -- formele apar in meniu cu acelasi nume - exact ce s-a intamplat prima data.
  --
  -- Atentie: nici A$ADM.NAME0/1/2 nu sunt de ajuns singure. Erau puse corect
  -- (14./15.) si meniul tot arata "13. Chelneri UnaWaiter" de trei ori.
  -- Doar VALUE1/VALUE2, cu SVALUE/LVALUE golite: exact ce face Configuratorul
  -- cand editezi Caption din interfata (verificat 2026-07-30).
  procedure caption(p_obj number, p_ro varchar2, p_ru varchar2) is
  begin
    update a$adp set value1 = p_ro, value2 = p_ru,
                     svalue = null, lvalue = null
     where obj_id = p_obj and key = 'CAPTION';
    if sql%rowcount = 0 then
      raise_application_error(-20099, 'Proprietatea CAPTION lipseste la nodul '||p_obj);
    end if;
  end;

  -- Clonarea propriu-zisa: nodul din arbore + TOATE proprietatile lui.
  procedure clone(p_new number, p_ro varchar2, p_ru varchar2, p_section varchar2) is
  begin
    insert into a$adm (obj_id, sys_id, obj_type, obj_subtype, link_id, parent_id,
                       template_id, name0, name1, name2, section, nrord,
                       date_begin, date_final, modified)
    select p_new, sys_id, obj_type, obj_subtype, link_id, parent_id,
           template_id, p_ro, p_ro, p_ru, p_section, p_new,
           date_begin, date_final, sysdate
      from a$adm where obj_id = c_src;

    insert into a$adp (obj_id, key, name, hint, gr, vtype,
                       value0, value1, value2, svalue, ivalue, bvalue,
                       dvalue, lvalue, attr, fvalue)
    select p_new, key, name, hint, gr, vtype,
           value0, value1, value2, svalue, ivalue, bvalue,
           dvalue, lvalue, attr, fvalue
      from a$adp where obj_id = c_src;
  end;
begin
  -- Refuzam sa rescriem peste noduri existente: un al doilea rulaj ar dubla
  -- proprietatile si forma ar deveni imprevizibila.
  select count(*) into v_n from a$adm where obj_id in (c_zone, c_tables);
  if v_n > 0 then
    raise_application_error(-20098,
      'Nodurile '||c_zone||'/'||c_tables||' exista deja - sterge-le intai (vezi sectiunea Dezfacere).');
  end if;

  -- ---------------------------------------------------------------- 14. ZONE
  clone(c_zone, '14. Zone UnaWaiter', '14. Зоны UnaWaiter', 'F_UWZONES');

  caption(c_zone, '14. Zone UnaWaiter', '14. Зоны UnaWaiter');
  memo(c_zone, 'SQL',
    'select cod_univ, zone_code, name_ro, name_ru, name_en, display_order, active, clcnrmese'
    ||' from vuw_zones_all order by cod_univ, nvl(display_order,999), zone_code');
  memo(c_zone, 'SQL_INSERT',
    'insert into vuw_zones_all (cod_univ, zone_code, name_ro, name_ru, name_en, display_order, active)'
    ||' values (:cod_univ, :zone_code, :name_ro, :name_ru, :name_en, :display_order, :active)');
  -- ZONE_CODE nu apare in SET: e cheia, iar triggerul respinge schimbarea lui
  -- (e referit de mese si de comenzile salvate deja in telefoane).
  memo(c_zone, 'SQL_UPDATE',
    'update vuw_zones_all set name_ro = :name_ro, name_ru = :name_ru, name_en = :name_en,'
    ||' display_order = :display_order, active = :active'
    ||' where cod_univ = :cod_univ and zone_code = :zone_code');
  memo(c_zone, 'SQL_DELETE',
    'delete from vuw_zones_all where cod_univ = :cod_univ and zone_code = :zone_code');
  -- Re-citirea randului dupa salvare. Fara ea, coloanele CALCULATE (CLCNRMESE)
  -- raman goale in grila pana la un refresh manual: clientul afiseaza ce a
  -- tastat managerul, iar ele se nasc in view, nu la tastatura.
  memo(c_zone, 'SQL_REFRESH',
    'select cod_univ, zone_code, name_ro, name_ru, name_en, display_order, active, clcnrmese'
    ||' from vuw_zones_all where cod_univ = :cod_univ and zone_code = :zone_code');

  -- ---------------------------------------------------------------- 15. MESE
  clone(c_tables, '15. Mese UnaWaiter', '15. Столы UnaWaiter', 'F_UWTABLES');

  caption(c_tables, '15. Mese UnaWaiter', '15. Столы UnaWaiter');
  memo(c_tables, 'SQL',
    'select cod_univ, table_no, zone, clczonet, display_order, active'
    ||' from vuw_tables_all order by cod_univ, table_no');
  memo(c_tables, 'SQL_INSERT',
    'insert into vuw_tables_all (cod_univ, table_no, zone, display_order, active)'
    ||' values (:cod_univ, :table_no, :zone, :display_order, :active)');
  -- TABLE_NO nu apare in SET: e scris in TMDB_COMENZ.DESK pe comenzile deja
  -- facute, deci schimbarea lui ar rupe legatura cu istoricul (trigger -20043).
  memo(c_tables, 'SQL_UPDATE',
    'update vuw_tables_all set zone = :zone, display_order = :display_order, active = :active'
    ||' where cod_univ = :cod_univ and table_no = :table_no');
  memo(c_tables, 'SQL_DELETE',
    'delete from vuw_tables_all where cod_univ = :cod_univ and table_no = :table_no');
  -- Idem: CLCZONET (denumirea zonei) se completeaza abia dupa re-citire.
  memo(c_tables, 'SQL_REFRESH',
    'select cod_univ, table_no, zone, clczonet, display_order, active'
    ||' from vuw_tables_all where cod_univ = :cod_univ and table_no = :table_no');

  commit;
  dbms_output.put_line('Formele '||c_zone||' (Zone) si '||c_tables||' (Mese) au fost create.');
  dbms_output.put_line('REPORNESTE UniacCLNT.exe ca sa le vezi in meniu.');
exception
  when others then
    rollback;
    raise;
end;
/

-- ---------------------------------------------------------------------------
-- Dezfacere
-- ---------------------------------------------------------------------------
-- delete from a$lob where obj_id in (1997, 1998);
-- delete from a$adp where obj_id in (1997, 1998);
-- delete from a$adm where obj_id in (1997, 1998);
-- commit;

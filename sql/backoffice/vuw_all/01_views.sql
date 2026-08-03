-- ===========================================================================
-- 01 — View-urile unificate VUW_*_ALL, generate din lista de restaurante
-- ===========================================================================
--   @01_views.sql 11          doar Rîșcani
--   @01_views.sql 11,13,17    toate trei
--
-- Nu se rulează singur — vezi 00_install_vuw_all.sql, care îl leagă de
-- recrearea triggerelor.
--
-- ---------------------------------------------------------------------------
-- DE CE GENERAT ȘI NU SCRIS DE MÂNĂ
--
-- Varianta precedentă (`backoffice_uw_all.sql`) avea branșele scrise și
-- COMENTATE:
--     select 11 cod_univ, ... from vuw_waiters@RISCANI.WORLD
--     -- union all select 13, ... from vuw_zones@CENTRU.WORLD    <-- typo real
--     -- union all select 17, ... from vuw_zones@MBATRIN.WORLD
-- Trei view-uri × trei branșe = nouă linii de decomentat corect, cu numele
-- link-ului și lista de coloane potrivite fiecărui view. Copy-paste-ul dintre
-- ele chiar a produs deja o greșeală (branșele lui `vuw_waiters_all` citeau
-- `vuw_zones`) — inofensivă doar fiindcă erau comentate.
--
-- Aici scrii o listă de coduri și atât. Numele link-ului vine din registrul
-- `ybmb_dif_cassa`, la fel ca la triggere, deci cele două părți nu pot ajunge
-- să arate spre baze diferite.
--
-- ---------------------------------------------------------------------------
-- LIMITARE CUNOSCUTĂ, acceptată conștient
--
-- `UNION ALL` peste db link-uri înseamnă că, dacă frontul unui restaurant e
-- căzut, formele nu se deschid DELOC — nici pentru celelalte. Nu e ascuns sub
-- preș: alternativa (funcție pipelined cu tratare de eroare pe fiecare branșă)
-- adaugă o cale de execuție nouă pentru un ecran folosit rar, la schimbări de
-- mese sau la înrolarea unui chelner. Dacă devine supărător în practică, ăsta e
-- drumul.
-- ===========================================================================

set define on
set verify off
set serveroutput on size 1000000
whenever sqlerror exit failure

declare
  c_lista constant varchar2(400) := '&1';

  v_cod   number;
  v_link  varchar2(128);
  v_n     number;
  v_cate  number := 0;

  v_w     clob := 'create or replace view vuw_waiters_all as' || chr(10);
  v_z     clob := 'create or replace view vuw_zones_all as'   || chr(10);
  v_t     clob := 'create or replace view vuw_tables_all as'  || chr(10);
  v_loc   clob;
  v_coduri varchar2(400);
  v_pre   varchar2(20);
begin
  for r in (
    select trim(regexp_substr(c_lista, '[^,]+', 1, level)) buc
      from dual
   connect by level <= regexp_count(c_lista, ',') + 1
  ) loop
    if r.buc is null then
      continue;
    end if;

    begin
      v_cod := to_number(r.buc);
    exception
      when others then
        raise_application_error(-20070,
          '"'||r.buc||'" nu e un cod de filiala. Asteptat: 11 sau 11,13,17');
    end;

    -- Link-ul vine din registru, NU din fisier: aceeasi sursa pe care o
    -- folosesc si triggerele, deci citirea si scrierea nu pot diverge.
    begin
      select db_link into v_link
        from ybmb_dif_cassa
       where cod_univ = v_cod and secondary = 0;
    exception
      when no_data_found then
        raise_application_error(-20071,
          'Filiala '||v_cod||' nu e in ybmb_dif_cassa (sau are secondary <> 0).');
      when too_many_rows then
        raise_application_error(-20072,
          'Filiala '||v_cod||' apare de mai multe ori in ybmb_dif_cassa cu secondary = 0.');
    end;

    -- Link-ul trebuie sa existe si sa fie rezolvabil, altfel view-ul se creeaza
    -- si abia forma cade cu ORA-02019 in fata managerului.
    select count(*) into v_n from all_db_links where upper(db_link) = upper(v_link);
    if v_n = 0 then
      raise_application_error(-20073,
        'Filiala '||v_cod||': db link-ul "'||v_link||'" din registru nu exista in baza asta.');
    end if;

    v_pre  := case when v_cate = 0 then '       ' else 'union all ' end;
    v_cate := v_cate + 1;
    v_coduri := v_coduri || case when v_coduri is null then '' else ',' end || v_cod;

    v_w := v_w || v_pre || 'select ' || v_cod || ' cod_univ, oficiant, clcoficiantt, pin, active'
                || ' from vuw_waiters@' || v_link || chr(10);

    v_z := v_z || v_pre || 'select ' || v_cod || ' cod_univ, zone_code, name_ro, name_ru, name_en,'
                || ' display_order, active, clcnrmese'
                || ' from vuw_zones@' || v_link || chr(10);

    v_t := v_t || v_pre || 'select ' || v_cod || ' cod_univ, table_no, zone, clczonet,'
                || ' display_order, active'
                || ' from vuw_tables@' || v_link || chr(10);

    dbms_output.put_line('  filiala ' || v_cod || '  ->  ' || v_link);
  end loop;

  if v_cate = 0 then
    raise_application_error(-20074, 'Lista de filiale e goala.');
  end if;

  execute immediate v_w;
  execute immediate v_z;
  execute immediate v_t;

  -- Nivelul „locatie" al formelor. Restrans la ACELEASI filiale: altfel, pe
  -- productie, managerul ar vedea in forma toate cele 5 din registru - inclusiv
  -- Megapolis si Aleco Russo, care n-au nici macar db link - si ar da peste
  -- ecrane goale fara sa inteleaga de ce.
  v_loc :=
    'create or replace view vuw_locations as' || chr(10) ||
    'select d.cod_univ,' || chr(10) ||
    '       u.denumirea as clcdenumirea,' || chr(10) ||
    '       (select count(*) from vuw_zones_all z   where z.cod_univ = d.cod_univ) as clcnrzone,' || chr(10) ||
    '       (select count(*) from vuw_waiters_all w where w.cod_univ = d.cod_univ) as clcnrchelneri' || chr(10) ||
    '  from ybmb_dif_cassa d' || chr(10) ||
    '  left join tms_univers u on u.cod = d.cod_univ and u.gr1 = ''FL''' || chr(10) ||
    ' where d.secondary = 0' || chr(10) ||
    '   and d.cod_univ in (' || v_coduri || ')';
  execute immediate v_loc;

  dbms_output.put_line(' ');
  dbms_output.put_line('View-uri create pentru ' || v_cate || ' filiala/filiale: ' || v_coduri);
  dbms_output.put_line('ATENTIE: triggerele INSTEAD OF au fost STERSE de CREATE OR REPLACE VIEW.');
  dbms_output.put_line('Ruleaza acum 02_triggers.sql (00_install_vuw_all.sql o face singur).');
end;
/

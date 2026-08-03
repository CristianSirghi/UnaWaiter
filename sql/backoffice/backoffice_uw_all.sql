-- ############################################################################
-- ##  INLOCUIT de sql/backoffice/vuw_all/00_install_vuw_all.sql              ##
-- ##                                                                        ##
-- ##  Fisierul asta are branselele pentru filialele 13 si 17 scrise si       ##
-- ##  COMENTATE - noua linii de decomentat corect, fiecare cu alt db link    ##
-- ##  si alta lista de coloane. Copy-paste-ul a produs deja o greseala:      ##
-- ##  branselele comentate ale lui vuw_waiters_all citesc `vuw_zones`.       ##
-- ##                                                                        ##
-- ##  Instalatorul nou GENEREAZA view-urile dintr-o lista de filiale si      ##
-- ##  recreeaza triggerele in aceeasi rulare (CREATE OR REPLACE VIEW le      ##
-- ##  sterge). Se ruleaza:  @00_install_vuw_all.sql 11                       ##
-- ##                                                                        ##
-- ##  Pastrat ca istoric si ca sursa a triggerelor.  -- 2026-08-03           ##
-- ############################################################################

-- Obiectele din BACK-OFFICE care alimenteaza formele UnaWaiter.
--
-- Se ruleaza in schema de back-office (test: SUN@clouddev, productie:
-- FOISHOR@cloudbd), NU pe fronturi. Tabelele reale stau pe fronturi; aici sunt
-- doar view-uri unificate peste db link-uri, ca managerul sa vada toate
-- restaurantele intr-un singur ecran.
--
-- Scrierea NU merge direct in view (union all nu e actualizabil): fiecare view
-- are un trigger INSTEAD OF care ia db link-ul din registrul ybmb_dif_cassa dupa
-- cod_univ. Deci un restaurant nou nu cere cod nou aici - doar un rand in
-- registru si linia union all decomentata.
--
-- >>> CAPCANA (docs/back-office/forme.md #3): CREATE OR REPLACE VIEW STERGE
-- >>> trigger-ul INSTEAD OF. Dupa orice modificare de view, RECREEAZA trigger-ul,
-- >>> altfel scrierile din forma cad cu ORA-01733 / ORA-01779 / ORA-01752.
-- >>> De aceea fisierul asta tine fiecare view lipit de trigger-ul lui.
--
-- >>> Pe TEST doar RISCANI.WORLD e rezolvabil; CENTRU.WORLD si MBATRIN.WORLD dau
-- >>> ORA-12154 din clouddev. Liniile lor sunt scrise si comentate - se
-- >>> decomenteaza la mutarea pe productie.
--
-- >>> Validarile sunt REPETATE aici, desi exista in pachetul de pe front: forma
-- >>> scrie direct in tabel prin trigger-ul asta, ocolind complet pachetul.

-- ===========================================================================
-- 1. CHELNERI  (forma obj_id 1996 - "13. Chelneri UnaWaiter")
-- ===========================================================================
-- Creat 2026-07-29 direct in baza; recuperat aici in fisier pe 2026-07-30, ca sa
-- existe si in git, nu doar in DB.

create or replace view vuw_waiters_all as
select 11 cod_univ, oficiant, clcoficiantt, pin, active from vuw_waiters@RISCANI.WORLD
-- union all select 13, oficiant, clcoficiantt, pin, active from vuw_waiters@CENTRU.WORLD
-- union all select 17, oficiant, clcoficiantt, pin, active from vuw_waiters@MBATRIN.WORLD
;

create or replace trigger trg_vuw_waiters_all
instead of insert or update or delete on vuw_waiters_all
declare
  v_link varchar2(128);
  v_cod  number := nvl(:new.cod_univ, :old.cod_univ);
  v_n    number;
begin
  begin
    select db_link into v_link from ybmb_dif_cassa where cod_univ = v_cod and secondary = 0;
  exception when no_data_found then
    raise_application_error(-20020, 'Filiala '||v_cod||' nu e in registrul ybmb_dif_cassa');
  end;

  if inserting or updating then
    if :new.pin is not null and not regexp_like(:new.pin, '^[0-9]{4}$') then
      raise_application_error(-20021, 'PIN-ul trebuie sa aiba exact 4 cifre (sau sa fie gol)');
    end if;
  end if;

  if inserting then
    execute immediate
      'select count(*) from vms_univers@'||v_link||' where cod = :1 and tip = ''O'' and gr1 = ''R'''
      into v_n using :new.oficiant;
    if v_n = 0 then
      raise_application_error(-20022, 'Codul '||:new.oficiant||' nu e chelner la filiala '||v_cod);
    end if;
    execute immediate
      'insert into uw_waiters@'||v_link||' (cod_univ, oficiant, pin, active) values (:1,:2,:3,:4)'
      using v_cod, :new.oficiant, :new.pin, nvl(:new.active,1);
  elsif updating then
    execute immediate
      'update uw_waiters@'||v_link||' set pin = :1, active = :2 where cod_univ = :3 and oficiant = :4'
      using :new.pin, nvl(:new.active,1), v_cod, :new.oficiant;
  else
    execute immediate
      'delete from uw_waiters@'||v_link||' where cod_univ = :1 and oficiant = :2'
      using v_cod, :old.oficiant;
  end if;
end;
/

-- ===========================================================================
-- 2. ZONE  (forma noua - "14. Zone UnaWaiter")
-- ===========================================================================
-- Zonele trebuie sa fie prima forma din pereche: o masa nu se poate adauga intr-o
-- zona care nu exista (cheia straina uw_tables_zone_fk de pe front).

create or replace view vuw_zones_all as
select 11 cod_univ, zone_code, name_ro, name_ru, name_en, display_order, active, clcnrmese
  from vuw_zones@RISCANI.WORLD
-- union all select 13, zone_code, name_ro, name_ru, name_en, display_order, active, clcnrmese from vuw_zones@CENTRU.WORLD
-- union all select 17, zone_code, name_ro, name_ru, name_en, display_order, active, clcnrmese from vuw_zones@MBATRIN.WORLD
;

create or replace trigger trg_vuw_zones_all
instead of insert or update or delete on vuw_zones_all
declare
  v_link varchar2(128);
  v_cod  number := nvl(:new.cod_univ, :old.cod_univ);
  v_n    number;
begin
  begin
    select db_link into v_link from ybmb_dif_cassa where cod_univ = v_cod and secondary = 0;
  exception when no_data_found then
    raise_application_error(-20030, 'Filiala '||v_cod||' nu e in registrul ybmb_dif_cassa');
  end;

  if inserting then
    -- Codul intra in cheile locale din telefon, deci forma lui nu e cosmetica.
    if not regexp_like(:new.zone_code, '^[a-z][a-z0-9_]{0,19}$') then
      raise_application_error(-20031,
        'Codul zonei: litere mici, cifre si _, incepand cu o litera (ex: hall, etaj2, vip)');
    end if;
    -- 'takeaway' e zona virtuala a comenzilor la pachet in aplicatie.
    if :new.zone_code = 'takeaway' then
      raise_application_error(-20032, 'Codul "takeaway" e rezervat comenzilor la pachet');
    end if;
    if :new.name_ro is null then
      raise_application_error(-20033, 'Denumirea in romana e obligatorie');
    end if;

    execute immediate
      'insert into uw_zones@'||v_link||
      ' (cod_univ, zone_code, name_ro, name_ru, name_en, display_order, active)'||
      ' values (:1,:2,:3,:4,:5,:6,:7)'
      using v_cod, :new.zone_code, :new.name_ro, :new.name_ru, :new.name_en,
            :new.display_order, nvl(:new.active,1);

  elsif updating then
    -- ZONE_CODE nu se modifica: e referit de uw_tables si de comenzile deja
    -- salvate in telefoane. Redenumirea se face pe name_*, nu pe cod.
    if :new.zone_code <> :old.zone_code then
      raise_application_error(-20034,
        'Codul zonei nu se poate schimba (e folosit de mese). Sterge zona si creeaz-o din nou.');
    end if;
    if :new.name_ro is null then
      raise_application_error(-20033, 'Denumirea in romana e obligatorie');
    end if;

    execute immediate
      'update uw_zones@'||v_link||
      ' set name_ro = :1, name_ru = :2, name_en = :3, display_order = :4, active = :5'||
      ' where cod_univ = :6 and zone_code = :7'
      using :new.name_ro, :new.name_ru, :new.name_en, :new.display_order,
            nvl(:new.active,1), v_cod, :new.zone_code;

  else
    -- Fara verificarea asta, managerul ar primi ORA-02292 (cheie straina) prin
    -- execute immediate - un mesaj din care nu intelege ca zona are inca mese.
    execute immediate
      'select count(*) from uw_tables@'||v_link||' where cod_univ = :1 and zone = :2'
      into v_n using v_cod, :old.zone_code;
    if v_n > 0 then
      raise_application_error(-20035,
        'Zona are inca '||v_n||' mese. Muta-le sau sterge-le intai.');
    end if;

    execute immediate
      'delete from uw_zones@'||v_link||' where cod_univ = :1 and zone_code = :2'
      using v_cod, :old.zone_code;
  end if;
end;
/

-- ===========================================================================
-- 3. MESE  (forma noua - "15. Mese UnaWaiter")
-- ===========================================================================

create or replace view vuw_tables_all as
select 11 cod_univ, table_no, zone, clczonet, display_order, active
  from vuw_tables@RISCANI.WORLD
-- union all select 13, table_no, zone, clczonet, display_order, active from vuw_tables@CENTRU.WORLD
-- union all select 17, table_no, zone, clczonet, display_order, active from vuw_tables@MBATRIN.WORLD
;

create or replace trigger trg_vuw_tables_all
instead of insert or update or delete on vuw_tables_all
declare
  v_link varchar2(128);
  v_cod  number := nvl(:new.cod_univ, :old.cod_univ);
  v_n    number;
begin
  begin
    select db_link into v_link from ybmb_dif_cassa where cod_univ = v_cod and secondary = 0;
  exception when no_data_found then
    raise_application_error(-20040, 'Filiala '||v_cod||' nu e in registrul ybmb_dif_cassa');
  end;

  if inserting or updating then
    -- DESK din TMDB_COMENZ e numeric; o masa 0 sau negativa n-ar putea fi
    -- deosebita de "comanda fara masa" (la pachet).
    if :new.table_no is null or :new.table_no <= 0
       or :new.table_no <> trunc(:new.table_no) then
      raise_application_error(-20041, 'Numarul mesei trebuie sa fie un intreg pozitiv');
    end if;

    -- Cheia straina de pe front ar prinde-o oricum, dar cu ORA-02291.
    execute immediate
      'select count(*) from uw_zones@'||v_link||' where cod_univ = :1 and zone_code = :2'
      into v_n using v_cod, :new.zone;
    if v_n = 0 then
      raise_application_error(-20042,
        'Zona "'||:new.zone||'" nu exista la filiala '||v_cod||'. Creeaz-o intai in "Zone UnaWaiter".');
    end if;
  end if;

  if inserting then
    execute immediate
      'insert into uw_tables@'||v_link||
      ' (cod_univ, table_no, zone, display_order, active) values (:1,:2,:3,:4,:5)'
      using v_cod, :new.table_no, :new.zone, :new.display_order, nvl(:new.active,1);

  elsif updating then
    -- TABLE_NO e cheia mesei si ajunge in TMDB_COMENZ.DESK al comenzilor deja
    -- trimise; schimbarea lui ar rupe legatura cu comenzile din istoric.
    if :new.table_no <> :old.table_no then
      raise_application_error(-20043,
        'Numarul mesei nu se poate schimba (e scris pe comenzile deja facute). Sterge masa si creeaz-o din nou.');
    end if;
    execute immediate
      'update uw_tables@'||v_link||
      ' set zone = :1, display_order = :2, active = :3 where cod_univ = :4 and table_no = :5'
      using :new.zone, :new.display_order, nvl(:new.active,1), v_cod, :new.table_no;

  else
    execute immediate
      'delete from uw_tables@'||v_link||' where cod_univ = :1 and table_no = :2'
      using v_cod, :old.table_no;
  end if;
end;
/

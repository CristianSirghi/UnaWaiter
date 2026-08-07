-- ===========================================================================
-- 02 — Triggerele INSTEAD OF ale view-urilor VUW_*_ALL
-- ===========================================================================
-- Se rulează ÎNTOTDEAUNA imediat după 01_views.sql.
--
-- >>> CAPCANA, deja plătită o dată: `CREATE OR REPLACE VIEW` ȘTERGE trigger-ul
-- >>> INSTEAD OF al view-ului. Fără recreare, scrierile din formă cad cu
-- >>> ORA-01733 / ORA-01779 / ORA-01752 — mesaje din care nimeni nu ghicește că
-- >>> lipsește un trigger. De aceea orchestratorul (00) le rulează lipite.
--
-- Triggerele sunt COMPLET GENERICE: nu conțin niciun cod de filială și niciun
-- nume de db link. Îl caută la fiecare scriere în `ybmb_dif_cassa` după
-- `cod_univ`, cu `execute immediate`. Un restaurant nou nu cere cod nou aici —
-- doar un rând în registru și rularea lui 01 cu lista actualizată.
--
-- Validările sunt REPETATE aici, deși există și în pachetul de pe front: forma
-- din back-office scrie direct în tabel prin trigger-ul ăsta, ocolind complet
-- pachetul.
--
-- Extras din baza de test pe 2026-08-03, unde sunt validate (15/15 verificări).
-- ===========================================================================

create or replace trigger trg_vuw_waiters_all
instead of insert or update or delete on vuw_waiters_all
declare
  v_link varchar2(128);
  v_cod  number := nvl(:new.cod_univ, :old.cod_univ);
  v_n	 number;
begin
  begin
    select db_link into v_link from ybmb_dif_cassa where cod_univ = v_cod and secondary = 0;
  exception when no_data_found then
    raise_application_error(-20020, 'Filiala '||v_cod||' nu e in registrul ybmb_dif_cassa');
  end;

  if inserting or updating then
    -- LENGTH + TRANSLATE, nu regexp: aceeasi forma ca in constrangerea de pe
    -- uw_waiters, ca validarea din forma si cea din tabela sa nu se contrazica.
    if :new.pin is not null
       and not (length(:new.pin) = 4 and translate(:new.pin, '#0123456789', '#') is null) then
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
    -- Duplicatul se prinde AICI, nu de cheia primara: altfel managerul primeste
    -- "нарушено ограничение уникальности (....UW_WAITERS_PK)", corect dar de
    -- neinteles. Ramura de UPDATE avea deja verificari citibile; la INSERT lipseau.
    execute immediate
      'select count(*) from uw_waiters@'||v_link||' where cod_univ = :1 and oficiant = :2'
      into v_n using v_cod, :new.oficiant;
    if v_n > 0 then
      raise_application_error(-20023,
	'Chelnerul '||:new.oficiant||' e deja adaugat la filiala '||v_cod);
    end if;
    -- can_edit_tables cu NVL 0: un chelner adaugat fara sa se bifeze nimic NU
    -- primeste dreptul de a schimba mesele. Implicitul trebuie sa fie cel
    -- inofensiv, nu cel comod.
    execute immediate
      'insert into uw_waiters@'||v_link||
      ' (cod_univ, oficiant, pin, active, can_edit_tables) values (:1,:2,:3,:4,:5)'
      using v_cod, :new.oficiant, :new.pin, nvl(:new.active,1),
            nvl(:new.can_edit_tables,0);
  elsif updating then
    execute immediate
      'update uw_waiters@'||v_link||
      ' set pin = :1, active = :2, can_edit_tables = :3'||
      ' where cod_univ = :4 and oficiant = :5'
      using :new.pin, nvl(:new.active,1), nvl(:new.can_edit_tables,0),
            v_cod, :new.oficiant;
  else
    execute immediate
      'delete from uw_waiters@'||v_link||' where cod_univ = :1 and oficiant = :2'
      using v_cod, :old.oficiant;
  end if;
end;
/

create or replace trigger trg_vuw_zones_all
instead of insert or update or delete on vuw_zones_all
declare
  v_link varchar2(128);
  v_cod  number := nvl(:new.cod_univ, :old.cod_univ);
  v_n	 number;
begin
  begin
    select db_link into v_link from ybmb_dif_cassa where cod_univ = v_cod and secondary = 0;
  exception when no_data_found then
    raise_application_error(-20030, 'Filiala '||v_cod||' nu e in registrul ybmb_dif_cassa');
  end;

  if inserting then
    -- Codul intra in cheile locale din telefon, deci forma lui nu e cosmetica.
    --
    -- LENGTH + TRANSLATE, nu regexp, si asta NU e doar stil: sub un NLS_SORT
    -- lingvistic potrivirea implicita a lui REGEXP_LIKE devine CASE-INSENSITIVE
    -- (ca si cum ar fi dat 'i'), iar baza are NLS_SORT=RUSSIAN - deci
    -- `regexp_like('Hall','^[a-z]...')` intoarce TRUE. Forma ar fi acceptat
    -- 'Hall', iar insertul de pe front ar fi picat cu ORA-02290 pe constrangerea
    -- uw_zones_code_ck: eroare bruta, in loc de mesajul citibil de mai jos.
    -- Expresia e identica cu cea din 01_uw_zones.sql - vezi acolo masuratorile.
    if not (length(:new.zone_code) between 1 and 20
            and translate(substr(:new.zone_code, 1, 1),
                          '#abcdefghijklmnopqrstuvwxyz', '#') is null
            and translate(:new.zone_code,
                          '#abcdefghijklmnopqrstuvwxyz0123456789_', '#') is null) then
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
    -- Duplicat prins aici, nu de cheia primara (vezi nota de la chelneri).
    execute immediate
      'select count(*) from uw_zones@'||v_link||' where cod_univ = :1 and zone_code = :2'
      into v_n using v_cod, :new.zone_code;
    if v_n > 0 then
      raise_application_error(-20036,
	'Zona "'||:new.zone_code||'" exista deja la filiala '||v_cod);
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

create or replace trigger trg_vuw_tables_all
instead of insert or update or delete on vuw_tables_all
declare
  v_link varchar2(128);
  v_cod  number := nvl(:new.cod_univ, :old.cod_univ);
  v_n	 number;
  v_zona varchar2(20);
begin
  begin
    select db_link into v_link from ybmb_dif_cassa where cod_univ = v_cod and secondary = 0;
  exception when no_data_found then
    raise_application_error(-20040, 'Filiala '||v_cod||' nu e in registrul ybmb_dif_cassa');
  end;

  if inserting or updating then
    if :new.table_no is null or :new.table_no <= 0
       or :new.table_no <> trunc(:new.table_no) then
      raise_application_error(-20041, 'Numarul mesei trebuie sa fie un intreg pozitiv');
    end if;
    execute immediate
      'select count(*) from uw_zones@'||v_link||' where cod_univ = :1 and zone_code = :2'
      into v_n using v_cod, :new.zone;
    if v_n = 0 then
      raise_application_error(-20042,
	'Zona "'||:new.zone||'" nu exista la filiala '||v_cod||'. Creeaz-o intai in lista de zone.');
    end if;
  end if;

  if inserting then
    -- Cheia primara e (cod_univ, table_no), deci o masa nu poate exista de doua
    -- ori la acelasi restaurant NICI MACAR in zone diferite - iar asta nu e
    -- evident din formular, unde zona se vede si numarul pare "al zonei".
    -- Fara verificarea de aici iesea "нарушено ограничение уникальности
    -- (....UW_TABLES_PK)": corect, dar managerul nu are ce face cu el.
    -- Spunem si ZONA in care e deja, ca sa aiba unde sa se uite.
    execute immediate
      'select max(zone) from uw_tables@'||v_link||' where cod_univ = :1 and table_no = :2'
      into v_zona using v_cod, :new.table_no;
    if v_zona is not null then
      raise_application_error(-20045,
	'Masa '||:new.table_no||' exista deja la filiala '||v_cod||
	', in zona "'||v_zona||'". Un numar de masa e unic pe tot restaurantul.');
    end if;

    execute immediate
      'insert into uw_tables@'||v_link||
      ' (cod_univ, table_no, zone, display_order, active) values (:1,:2,:3,:4,:5)'
      using v_cod, :new.table_no, :new.zone, :new.display_order, nvl(:new.active,1);

  elsif updating then
    -- RENUMEROTAREA e permisa (forma o trimite cu :OLD_table_no in WHERE), dar
    -- numai daca masa nu e in uz: numarul ajunge scris pe comenzi (TMDB_COMENZ.DESK),
    -- iar o masa cu comanda deschisa si-ar pierde legatura cu ea sub mana chelnerului.
    if :new.table_no <> :old.table_no then
      execute immediate
	'select count(*) from tmdb_comenz@'||v_link||' where desk = :1 and state in (1,2)'
	into v_n using :old.table_no;
      if v_n > 0 then
	raise_application_error(-20043,
	  'Masa '||:old.table_no||' are o comanda deschisa - inchide-o intai, apoi renumeroteaza.');
      end if;
      execute immediate
	'select count(*) from uw_tables@'||v_link||' where cod_univ = :1 and table_no = :2'
	into v_n using v_cod, :new.table_no;
      if v_n > 0 then
	raise_application_error(-20044,
	  'Masa '||:new.table_no||' exista deja la filiala '||v_cod);
      end if;
    end if;

    execute immediate
      'update uw_tables@'||v_link||
      ' set table_no = :1, zone = :2, display_order = :3, active = :4'||
      ' where cod_univ = :5 and table_no = :6'
      using :new.table_no, :new.zone, :new.display_order, nvl(:new.active,1),
	    v_cod, :old.table_no;

  else
    execute immediate
      'delete from uw_tables@'||v_link||' where cod_univ = :1 and table_no = :2'
      using v_cod, :old.table_no;
  end if;
end;
/


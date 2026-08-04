-- ===========================================================================
-- Formele UnaWaiter din back-office — instalare pe ORICE mediu/client
-- ===========================================================================
--   * „13. Chelneri UnaWaiter"  (F_UWWAITERT) — locația -> chelnerii ei
--   * „14. Amplasare mese"      (F_UWPLAN)    — locația -> zonele -> mesele
--
-- Se rulează pe schema de back-office: `sun` pe test, `foishor` pe producție.
--
-- ---------------------------------------------------------------------------
-- DE CE EXISTĂ FIȘIERUL ĂSTA (și de ce NU se folosesc scripturile vechi)
--
-- `backoffice_forma_chelneri.sql` și `backoffice_forma_unificata.sql` au fost
-- scrise pentru test, cu `obj_id` HARDCODATE: 1996, 1997, 1999, plus șabloanele
-- 1867/1868. Pe producție aceleași numere sunt ALTE obiecte, reale (verificat
-- 2026-08-03):
--     1991 = SALARIU TARIFAR (tabel de pontaj)
--     1996 = acțiunea „Перезаполнить дни/часы из табеля"
--     1997 = TOTAL:900          1998 = raport DG1P26
--     1999 = acțiunea „Заполннение данных"
-- iar 1867/1868 nu există deloc. Scriptul vechi de chelneri face
-- `update a$adp` și `delete from a$lob` DIRECT pe 1996, fără nicio verificare —
-- rulat pe producție, ar fi corupt un obiect de salarizare.
--
-- Aici nu mai există niciun `obj_id` scris de mână:
--   * părintele se caută după SECTION = 'CLASSIF' („10. Справочники");
--   * `obj_id`-urile noi se iau ca MAX(obj_id)+1 și +2, deci coliziunea e
--     imposibilă prin construcție;
--   * dacă formele există deja (după SECTION), scriptul refuză să ruleze.
--
-- Definițiile sunt EXTRASE DIN BAZA DE TEST, unde formele sunt validate, nu
-- reconstruite prin clonare din șabloane — un șablon poate diferi între medii,
-- iar o proprietate lipsă face grila read-only fără niciun mesaj.
-- Regenerare (dacă formele se modifică pe test): generatorul e in istoricul git,
-- `sql/backoffice/forme/genereaza_forme.sql`, scos din arbore pe 2026-08-04.
--
-- ---------------------------------------------------------------------------
-- DUPĂ RULARE:
--   1. repornește `UniacCLNT.exe`;
--   2. deschide fiecare formă și ÎNCHIDE-O o dată — prima deschidere e cea care
--      generează coloanele grilelor (capcana #4 din docs/back-office/forme.md);
--   3. rulează `fix_grid_cols.sql` (alături, în același folder) pentru
--      titlurile coloanelor. NU e opțional: fără el grilele apar fără capete.
--
-- Formele au nevoie de `VUW_WAITERS_ALL`, `VUW_ZONES_ALL`, `VUW_TABLES_ALL` și
-- `VUW_LOCATIONS` — deci `../vuw_all/00_install_vuw_all.sql` se rulează ÎNAINTE.
-- ===========================================================================

set define off
set serveroutput on size 1000000
whenever sqlerror exit failure

declare
  -- Sirurile CHIRILICE sunt scrise cu UNISTR, nu direct, ca fisierul sa ramana
  -- pur ASCII. Motivul, ridicat de DBA-ul clientului pe 2026-08-04: scripturile
  -- se ruleaza cu sqlplus pe masini a caror codificare n-o controlam, iar un sir
  -- chirilic scris literal si citit cu alt NLS_LANG se transforma TACUT in
  -- altceva. Aici nu e cosmetic: c_grp e numele grupului de proprietati pe care
  -- il asteapta Configuratorul - o valoare gresita face ca proprietatile formei
  -- sa nu mai fie gasite, fara niciun mesaj de eroare.
  --
  -- Escape-urile sunt generate din sirurile reale, nu scrise de mana, si
  -- verificate pe baza de test: unistr-ul zonelor coincide cu ce e deja scris
  -- corect in uw_zones.name_ru.
  c_grp      constant varchar2(30) := unistr('\041E\0431\0449\0430\044F');
  c_cap_chel constant varchar2(60) :=
    unistr('13. \041E\0444\0438\0446\0438\0430\043D\0442\044B UnaWaiter');
  c_cap_mese constant varchar2(60) :=
    unistr('14. \0420\0430\0437\043C\0435\0449\0435\043D\0438\0435 \0441\0442\043E\043B\043E\0432');
  v_parent number;
  v_chel   number;
  v_mese   number;
  v_n      number;

  procedure adm(p_obj number, p_parent number, p_section varchar2,
                p_ro varchar2, p_ru varchar2) is
  begin
    insert into a$adm (obj_id, sys_id, obj_type, obj_subtype, link_id, parent_id,
                       template_id, name0, name1, name2, section, nrord,
                       date_begin, date_final, modified)
    values (p_obj, null, 4, 0, null, p_parent,
            null, p_ro, p_ro, p_ru, p_section, p_obj,
            null, null, sysdate);
  end;

  procedure adp(p_obj number, p_key varchar2, p_name varchar2, p_hint varchar2,
                p_gr varchar2, p_vtype varchar2, p_value0 varchar2,
                p_value1 varchar2, p_value2 varchar2, p_svalue varchar2,
                p_ivalue number, p_bvalue varchar2, p_lvalue varchar2,
                p_attr varchar2) is
  begin
    insert into a$adp (obj_id, key, name, hint, gr, vtype, value0, value1,
                       value2, svalue, ivalue, bvalue, dvalue, lvalue, attr)
    values (p_obj, p_key, p_name, p_hint, p_gr, p_vtype, p_value0, p_value1,
            p_value2, p_svalue, p_ivalue, p_bvalue, null, p_lvalue, p_attr);
  end;

begin
  -- ----------------------------------------------------------------- gărzi ---
  select count(*) into v_n from a$adm where section in ('F_UWWAITERT','F_UWPLAN');
  if v_n > 0 then
    raise_application_error(-20080,
      'Formele UnaWaiter exista deja in baza asta ('||v_n||' noduri cu SECTION '||
      'F_UWWAITERT/F_UWPLAN). Sterge-le intai daca vrei sa le reinstalezi.');
  end if;

  begin
    select obj_id into v_parent from a$adm where section = 'CLASSIF';
  exception
    when no_data_found then
      raise_application_error(-20081,
        'Nu gasesc meniul de dictionare (SECTION = ''CLASSIF''). '||
        'Verifica pe ce baza rulezi.');
    when too_many_rows then
      raise_application_error(-20082,
        'Exista mai multe noduri cu SECTION = ''CLASSIF'' - alege manual parintele.');
  end;

  -- obj_id-uri noi, imposibil de ciocnit cu ceva existent
  select max(obj_id) into v_n from a$adm;
  v_chel := v_n + 1;
  v_mese := v_n + 2;

  dbms_output.put_line('Parinte (SECTION = CLASSIF): obj_id = '||v_parent);
  dbms_output.put_line('Chelneri UnaWaiter       : obj_id = '||v_chel);
  dbms_output.put_line('Amplasare mese           : obj_id = '||v_mese);

  -- ------------------------------------------------------------- nodurile ---
  adm(v_chel, v_parent, 'F_UWWAITERT', '13. Chelneri UnaWaiter', c_cap_chel);
  adm(v_mese, v_parent, 'F_UWPLAN',    '14. Amplasare mese',     c_cap_mese);

  -- ------------------------------------------------------- proprietatile ---
  adp(v_chel, q'[ACTIVE]', q'[Active]', null, c_grp, q'[B]', null, null, null, null, null, q'[1]', null, null);
  adp(v_chel, q'[CAPTION]', q'[Caption]', null, c_grp, q'[C]', null, q'[13. Chelneri UnaWaiter]', c_cap_chel, q'[13. Chelneri UnaWaiter]', null, null, null, null);
  adp(v_chel, q'[CODGRP]', q'[codgrp]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[CODPRICE]', q'[codprice]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[DATECAPTION1]', q'[DateCaption1]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[DATECAPTION2]', q'[DateCaption2]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[DATECOUNT]', q'[DateCount]', null, c_grp, q'[I]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[DATEOFFSET1]', q'[DateOffset1]', null, c_grp, q'[I]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[DATEOFFSET2]', q'[DateOffset2]', null, c_grp, q'[I]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[DATEPREFIX]', q'[DatePrefix]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[DLL FORMNAME]', q'[DLL FormName]', null, c_grp, q'[S]', null, null, null, q'[FSal1p01]', null, null, null, null);
  adp(v_chel, q'[DLL ID]', q'[DLL ID]', null, c_grp, q'[I]', null, null, null, null, 8101, null, null, null);
  adp(v_chel, q'[DOCSYSFID1]', q'[DocSYSFID1]', null, c_grp, q'[I]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[DOCSYSFID2]', q'[DocSYSFID2]', null, c_grp, q'[I]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[EDITQUERY1]', q'[EditQuery1]', null, c_grp, q'[B]', null, null, null, null, null, q'[0]', null, null);
  adp(v_chel, q'[EDITQUERY2]', q'[EditQuery2]', null, c_grp, q'[B]', null, null, null, null, null, q'[1]', null, null);
  adp(v_chel, q'[EDITQUERY3]', q'[EditQuery3]', null, c_grp, q'[B]', null, null, null, null, null, q'[1]', null, null);
  adp(v_chel, q'[FORMNOGRID]', q'[FormNoGrid]', null, c_grp, q'[B]', null, null, null, null, null, q'[0]', null, null);
  adp(v_chel, q'[FORMUSEDETAIL]', q'[FormUseDetail]', null, c_grp, q'[B]', null, null, null, null, null, q'[1]', null, null);
  adp(v_chel, q'[GROUP1]', q'[group1]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[LISTDOCS]', q'[ListDocs]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[MASTERSIZE]', q'[MasterSize]', null, c_grp, q'[I]', null, null, null, null, 200, null, null, null);
  adp(v_chel, q'[PRICECODGRP]', q'[PriceCodGrp]', null, c_grp, q'[I]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[SAGI_ORDERBY]', q'[Sagi_OrderBy]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[SAGIQUERY]', q'[SagiQuery]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[SAGITABLE]', q'[SagiTable]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[SAGIWHERE]', q'[SagiWhere]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[SQL]', q'[SQL]', null, c_grp, q'[M]', null, null, null, q'[select cod_univ, clcdenumirea, clcnrchelneri from vuw_locations order by cod_univ]', null, null, q'[select cod_univ, clcdenumirea, clcnrchelneri from vuw_locations order by cod_univ]', null);
  adp(v_chel, q'[SQL_DELETE]', q'[SQL_Delete]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[SQL_INSERT]', q'[SQL_Insert]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[SQL_REFRESH]', q'[SQL_Refresh]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[SQLSCRIPT]', q'[SQLscript]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[SQL_UPDATE]', q'[SQL_Update]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[SUBMASTER]', q'[SubMaster]', null, c_grp, q'[B]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[UNIVTREECLASS]', q'[UnivTreeClass]', null, c_grp, q'[I]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[XSAGI_ORDERBY]', q'[XSagi_OrderBy]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[XSAGIQUERY]', q'[XSagiQuery]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[XSAGITABLE]', q'[XSagiTable]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[XSAGIWHERE]', q'[XSagiWhere]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[XSQL]', q'[XSQL]', null, c_grp, q'[M]', null, null, null, q'[select cod_univ, oficiant, clcoficiantt, pin, active from vuw_waiters_all where cod_univ = :cod_univ order by oficiant]', null, null, q'[select cod_univ, oficiant, clcoficiantt, pin, active from vuw_waiters_all where cod_univ = :cod_univ order by oficiant]', null);
  adp(v_chel, q'[XSQL_DELETE]', q'[XSQL_Delete]', null, c_grp, q'[M]', null, null, null, q'[delete from vuw_waiters_all where cod_univ = :cod_univ and oficiant = :oficiant]', null, null, q'[delete from vuw_waiters_all where cod_univ = :cod_univ and oficiant = :oficiant]', null);
  adp(v_chel, q'[XSQL_INSERT]', q'[XSQL_Insert]', null, c_grp, q'[M]', null, null, null, q'[insert into vuw_waiters_all (cod_univ, oficiant, pin, active) values (:cod_univ, :oficiant, :pin, :active)]', null, null, q'[insert into vuw_waiters_all (cod_univ, oficiant, pin, active) values (:cod_univ, :oficiant, :pin, :active)]', null);
  adp(v_chel, q'[XSQL_REFRESH]', q'[XSQL_Refresh]', null, c_grp, q'[M]', null, null, null, q'[select cod_univ, oficiant, clcoficiantt, pin, active from vuw_waiters_all where cod_univ = :cod_univ and oficiant = :oficiant]', null, null, q'[select cod_univ, oficiant, clcoficiantt, pin, active from vuw_waiters_all where cod_univ = :cod_univ and oficiant = :oficiant]', null);
  adp(v_chel, q'[XSQL_UPDATE]', q'[XSQL_Update]', null, c_grp, q'[M]', null, null, null, q'[update vuw_waiters_all set pin = :pin, active = :active where cod_univ = :cod_univ and oficiant = :oficiant]', null, null, q'[update vuw_waiters_all set pin = :pin, active = :active where cod_univ = :cod_univ and oficiant = :oficiant]', null);
  adp(v_chel, q'[XTT1]', q'[XTT1]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_chel, q'[XTT2]', q'[XTT2]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[ACTIVE]', q'[Active]', null, c_grp, q'[B]', null, null, null, null, null, q'[1]', null, null);
  adp(v_mese, q'[CAPTION]', q'[Caption]', null, c_grp, q'[C]', null, q'[14. Amplasare mese]', c_cap_mese, null, null, null, null, null);
  adp(v_mese, q'[CODGRP]', q'[codgrp]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[CODPRICE]', q'[codprice]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[DATECAPTION1]', q'[DateCaption1]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[DATECAPTION2]', q'[DateCaption2]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[DATECOUNT]', q'[DateCount]', null, c_grp, q'[I]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[DATEOFFSET1]', q'[DateOffset1]', null, c_grp, q'[I]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[DATEOFFSET2]', q'[DateOffset2]', null, c_grp, q'[I]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[DATEPREFIX]', q'[DatePrefix]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[DLL FORMNAME]', q'[DLL FormName]', null, c_grp, q'[S]', null, null, null, q'[FSal1p01]', null, null, null, null);
  adp(v_mese, q'[DLL ID]', q'[DLL ID]', null, c_grp, q'[I]', null, null, null, null, 8101, null, null, null);
  adp(v_mese, q'[DOCSYSFID1]', q'[DocSYSFID1]', null, c_grp, q'[I]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[DOCSYSFID2]', q'[DocSYSFID2]', null, c_grp, q'[I]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[EDITQUERY1]', q'[EditQuery1]', null, c_grp, q'[B]', null, null, null, null, null, q'[0]', null, null);
  adp(v_mese, q'[EDITQUERY2]', q'[EditQuery2]', null, c_grp, q'[B]', null, null, null, null, null, q'[1]', null, null);
  adp(v_mese, q'[EDITQUERY3]', q'[EditQuery3]', null, c_grp, q'[B]', null, null, null, null, null, q'[1]', null, null);
  adp(v_mese, q'[FORMNOGRID]', q'[FormNoGrid]', null, c_grp, q'[B]', null, null, null, null, null, q'[0]', null, null);
  adp(v_mese, q'[FORMUSEDETAIL]', q'[FormUseDetail]', null, c_grp, q'[B]', null, null, null, null, null, q'[1]', null, null);
  adp(v_mese, q'[FORMUSEDETAIL2]', q'[FormUseDetail2]', q'[3 grids (1<-2; 1<-3)]', c_grp, q'[B]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[FORMUSESUBDETAIL]', q'[FormUseSubDetail]', q'[3 grids (1<-2; 1<-3)]', c_grp, q'[B]', null, null, null, null, null, q'[1]', null, null);
  adp(v_mese, q'[FORMUSETAB1DETAIL]', q'[FormUseTab1Detail]', null, c_grp, q'[B]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[FORMUSETAB1SUBDETAIL]', q'[FormUseTab1SubDetail]', null, c_grp, q'[B]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[FORMUSETAB2DETAIL]', q'[FormUseTab2Detail]', q'[2 grids]', c_grp, q'[B]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[FORMUSETAB2DETAIL2]', q'[FormUseTab2Detail2]', q'[3 grids (1<-2; 1<-3)]', c_grp, q'[B]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[FORMUSETAB2SUBDETAIL]', q'[FormUseTab2SubDetail]', q'[3 grids (1<-2<-3)]', c_grp, q'[B]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[FORMUSETAB3DETAIL]', q'[FormUseTab3Detail]', null, c_grp, q'[B]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[GROUP1]', q'[group1]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[LISTDOCS]', q'[ListDocs]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[MASTERSIZE]', q'[MasterSize]', null, c_grp, q'[I]', null, null, null, null, 200, null, null, null);
  adp(v_mese, q'[MASTERSIZE2]', q'[MasterSize2]', q'[<0 means vertical]', c_grp, q'[I]', null, null, null, null, 190, null, null, null);
  adp(v_mese, q'[PRICECODGRP]', q'[PriceCodGrp]', null, c_grp, q'[I]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[SAGI_ORDERBY]', q'[Sagi_OrderBy]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[SAGIQUERY]', q'[SagiQuery]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[SAGITABLE]', q'[SagiTable]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[SAGIWHERE]', q'[SagiWhere]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[SQL]', q'[SQL]', null, c_grp, q'[M]', null, null, null, q'[select cod_univ, clcdenumirea, clcnrzone from vuw_locations order by cod_univ]', null, null, q'[select cod_univ, clcdenumirea, clcnrzone from vuw_locations order by cod_univ]', null);
  adp(v_mese, q'[SQL_DELETE]', q'[SQL_Delete]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[SQL_INSERT]', q'[SQL_Insert]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[SQL_REFRESH]', q'[SQL_Refresh]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[SQLSCRIPT]', q'[SQLscript]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[SQL_UPDATE]', q'[SQL_Update]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[SUBMASTER]', q'[SubMaster]', null, c_grp, q'[B]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[UNIVTREECLASS]', q'[UnivTreeClass]', null, c_grp, q'[I]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[XSAGI_ORDERBY]', q'[XSagi_OrderBy]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[XSAGIQUERY]', q'[XSagiQuery]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[XSAGITABLE]', q'[XSagiTable]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[XSAGIWHERE]', q'[XSagiWhere]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[XSQL]', q'[XSQL]', null, c_grp, q'[M]', null, null, null, q'[select cod_univ, zone_code, name_ro, name_ru, name_en, display_order, active, clcnrmese from vuw_zones_all where cod_univ = :cod_univ order by nvl(display_order,999), zone_code]', null, null, q'[select cod_univ, zone_code, name_ro, name_ru, name_en, display_order, active, clcnrmese from vuw_zones_all where cod_univ = :cod_univ order by nvl(display_order,999), zone_code]', null);
  adp(v_mese, q'[XSQL_DELETE]', q'[XSQL_Delete]', null, c_grp, q'[M]', null, null, null, q'[delete from vuw_zones_all where cod_univ = :cod_univ and zone_code = :zone_code]', null, null, q'[delete from vuw_zones_all where cod_univ = :cod_univ and zone_code = :zone_code]', null);
  adp(v_mese, q'[XSQL_INSERT]', q'[XSQL_Insert]', null, c_grp, q'[M]', null, null, null, q'[insert into vuw_zones_all (cod_univ, zone_code, name_ro, name_ru, name_en, display_order, active) values (:cod_univ, :zone_code, :name_ro, :name_ru, :name_en, :display_order, :active)]', null, null, q'[insert into vuw_zones_all (cod_univ, zone_code, name_ro, name_ru, name_en, display_order, active) values (:cod_univ, :zone_code, :name_ro, :name_ru, :name_en, :display_order, :active)]', null);
  adp(v_mese, q'[XSQL_REFRESH]', q'[XSQL_Refresh]', null, c_grp, q'[M]', null, null, null, q'[select cod_univ, zone_code, name_ro, name_ru, name_en, display_order, active, clcnrmese from vuw_zones_all where cod_univ = :cod_univ and zone_code = :zone_code]', null, null, q'[select cod_univ, zone_code, name_ro, name_ru, name_en, display_order, active, clcnrmese from vuw_zones_all where cod_univ = :cod_univ and zone_code = :zone_code]', null);
  adp(v_mese, q'[XSQL_UPDATE]', q'[XSQL_Update]', null, c_grp, q'[M]', null, null, null, q'[update vuw_zones_all set name_ro = :name_ro, name_ru = :name_ru, name_en = :name_en, display_order = :display_order, active = :active where cod_univ = :cod_univ and zone_code = :zone_code]', null, null, q'[update vuw_zones_all set name_ro = :name_ro, name_ru = :name_ru, name_en = :name_en, display_order = :display_order, active = :active where cod_univ = :cod_univ and zone_code = :zone_code]', null);
  adp(v_mese, q'[XTT1]', q'[XTT1]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[XTT2]', q'[XTT2]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[YSAGI_ORDERBY]', q'[YSagi_OrderBy]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[YSAGIQUERY]', q'[YSagiQuery]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[YSAGITABLE]', q'[YSagiTable]', null, c_grp, q'[S]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[YSAGIWHERE]', q'[YSagiWhere]', null, c_grp, q'[M]', null, null, null, null, null, null, null, null);
  adp(v_mese, q'[YSQL]', q'[YSQL]', null, c_grp, q'[M]', null, null, null, q'[select cod_univ, table_no, zone, display_order, active from vuw_tables_all where cod_univ = :cod_univ and zone = :zone_code order by nvl(display_order, table_no), table_no]', null, null, q'[select cod_univ, table_no, zone, display_order, active from vuw_tables_all where cod_univ = :cod_univ and zone = :zone_code order by nvl(display_order, table_no), table_no]', null);
  adp(v_mese, q'[YSQL_DELETE]', q'[YSQL_Delete]', null, c_grp, q'[M]', null, null, null, q'[delete from vuw_tables_all where cod_univ = :cod_univ and table_no = :table_no]', null, null, q'[delete from vuw_tables_all where cod_univ = :cod_univ and table_no = :table_no]', null);
  adp(v_mese, q'[YSQL_INSERT]', q'[YSQL_Insert]', null, c_grp, q'[M]', null, null, null, q'[insert into vuw_tables_all (cod_univ, table_no, zone, display_order, active) values (:cod_univ, :table_no, :zone, :display_order, :active)]', null, null, q'[insert into vuw_tables_all (cod_univ, table_no, zone, display_order, active) values (:cod_univ, :table_no, :zone, :display_order, :active)]', null);
  adp(v_mese, q'[YSQL_REFRESH]', q'[YSQL_Refresh]', null, c_grp, q'[M]', null, null, null, q'[select cod_univ, table_no, zone, display_order, active from vuw_tables_all where cod_univ = :cod_univ and table_no = :table_no]', null, null, q'[select cod_univ, table_no, zone, display_order, active from vuw_tables_all where cod_univ = :cod_univ and table_no = :table_no]', null);
  adp(v_mese, q'[YSQL_UPDATE]', q'[YSQL_Update]', null, c_grp, q'[M]', null, null, null, q'[update vuw_tables_all set table_no = :table_no, display_order = :display_order, active = :active where cod_univ = :cod_univ and table_no = :OLD_table_no]', null, null, q'[update vuw_tables_all set table_no = :table_no, display_order = :display_order, active = :active where cod_univ = :cod_univ and table_no = :OLD_table_no]', null);

  -- Cache-ul XML din A$LOB contine o COPIE a interogarilor, iar clientul le
  -- ruleaza pe ELE, nu pe A$ADP. La o instalare noua n-are ce sa existe, dar
  -- stergerea e ieftina si scuteste o depanare lunga daca formele sunt reinstalate.
  delete from a$lob where obj_id in (v_chel, v_mese);

  commit;
  dbms_output.put_line(' ');
  dbms_output.put_line('Gata. Reporneste UniacCLNT.exe, deschide fiecare forma si');
  dbms_output.put_line('INCHIDE-O o data, apoi ruleaza fix_grid_cols.sql.');
exception
  when others then
    rollback;
    raise;
end;
/

set define on

-- Fara EXIT, sqlplus ramane la prompt si .bat-ul pare blocat.
EXIT SUCCESS

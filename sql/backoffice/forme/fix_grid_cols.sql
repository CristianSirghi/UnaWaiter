-- Repara listele de coloane pe care clientul le salveaza GOALE pentru formele
-- UnaWaiter din back-office.
--
-- SIMPTOM: forma se deschide cu numarul corect de randuri, dar fara capete de
-- coloana - grila iese ingusta si aparent goala.
--
-- CAUZA (masurata pe 2026-07-30, nu presupusa): la INCHIDEREA formei clientul
-- scrie in A$LOB, pentru FIECARE grila a ei, un XML care contine lista de
-- coloane sub forma:
--     <cols><col field=""/></cols>
-- adica o coloana cu numele gol. La urmatoarea deschidere se increde in ea.
-- Sters rândul, forma isi regenereaza coloanele din interogare si merge - dar la
-- urmatoarea inchidere il rescrie identic de gresit. Deci STERGEREA NU E O
-- REPARATIE, e doar un ragaz. Reparatia care tine e sa-i scrii tu o lista
-- adevarata: odata ce cache-ul contine coloane cu nume, clientul le
-- reserializeaza corect si nu mai revine (verificat peste mai multe cicluri
-- deschide/inchide).
--
-- DE CE NOI SI NIMENI ALTCINEVA: formele UnaWaiter sunt singurele din instalare
-- construite pe FSal1p01 + proprietatea SQL. Celelalte 1699 de aranjari salvate
-- erau din 2019, in formatul binar Delphi (SDBG/TPF0TColumnsWrapper).
--
-- ATRIBUTELE lui <col> NU sunt ghicite: sunt citite din binarul clientului,
-- D:\Unisim\UNA.md-201208-5.77.0.11\Asagi.bpl, unde tabela de tokeni e text:
--     cols col field visible false color width font align readonly true
--     hcolor bstyle caption halign hfont list
--
-- >>> RULEAZA-L CU FORMA INCHISA. Clientul tine aranjarea in memorie si o
-- >>> rescrie cand inchizi o forma.

set define off
set serveroutput on size 100000

declare
  -- Cheia e 'obj_id|lob_name' - o forma cu master-detail are mai multe grile:
  -- gr01 = nivelul 1, gr01a = nivelul 2, gr01b = nivelul 3.
  --
  -- Fiecare coloana: "CAMP|titlu|latime|readonly|ascuns", separate prin ';'.
  -- readonly / ascuns: pune orice text (ex. 'x') ca sa le activezi.
  type t_spec is table of varchar2(4000) index by varchar2(60);
  v_spec t_spec;
  v_key  varchar2(60);
  v_txt  varchar2(32767);
  v_new  varchar2(32767);
  v_repl varchar2(4000);
  v_a    number;
  v_b    number;
  v_obj  number;
  v_lob  varchar2(60);

  function cols_xml(p_list varchar2) return varchar2 is
    v_out  varchar2(4000) := '<cols>';
    v_rest varchar2(4000) := p_list||';';
    v_item varchar2(300);
    function part(p_s varchar2, p_n number) return varchar2 is
      v_s varchar2(400) := p_s||'|||||';
      v_i number;
    begin
      for j in 1 .. p_n - 1 loop
        v_i := instr(v_s, '|');
        v_s := substr(v_s, v_i + 1);
      end loop;
      return substr(v_s, 1, instr(v_s, '|') - 1);
    end;
  begin
    while instr(v_rest, ';') > 0 loop
      v_item := trim(substr(v_rest, 1, instr(v_rest, ';') - 1));
      v_rest := substr(v_rest, instr(v_rest, ';') + 1);
      if v_item is not null then
        v_out := v_out||'<col field="'||part(v_item,1)||'"';
        if part(v_item,2) is not null then v_out := v_out||' caption="'||part(v_item,2)||'"'; end if;
        if part(v_item,3) is not null then v_out := v_out||' width="'||part(v_item,3)||'"';     end if;
        if part(v_item,4) is not null then v_out := v_out||' readonly="true"';                  end if;
        if part(v_item,5) is not null then v_out := v_out||' visible="false"';                  end if;
        v_out := v_out||'/>';
      end if;
    end loop;
    return v_out||'</cols>';
  end;
begin
  -- Titlurile sunt FARA diacritice romanesti: continutul se scrie prin
  -- utl_raw.cast_to_raw, deci trece prin setul de caractere al bazei
  -- (CL8MSWIN1251), care nu are a-breve / s-sedila / t-sedila.

  -- ---------------- 13. Chelneri UnaWaiter, 2 grile ----------------
  v_spec('1996|:fmFS1c:gr01') :=
      'COD_UNIV|Cod|50|ro;'
    ||'CLCDENUMIREA|Restaurant|240|ro;'
    ||'CLCNRCHELNERI|Nr. chelneri|90|ro';

  -- CAN_EDIT_TABLES = dreptul de a adauga/scoate mese DIN APLICATIE. 0 implicit;
  -- se pune doar administratorului sau chelnerului senior de tura. Titlul e
  -- lung intentionat: "Editeaza" singur nu spune CE editeaza, iar coloana e
  -- langa "Activ", cu care s-ar confunda usor.
  v_spec('1996|:fmFS1c:gr01a') :=
      'COD_UNIV|||ro|ascuns;'
    ||'OFICIANT|Cod chelner|100;'
    ||'CLCOFICIANTT|Nume|240|ro;'
    ||'PIN|PIN|70;'
    ||'ACTIVE|Activ|60;'
    ||'CAN_EDIT_TABLES|Poate edita mese|120';

  -- Formele separate 1997 "Zone" si 1998 "Mese" au fost sterse pe 2026-07-30,
  -- inlocuite de forma unificata de mai jos. Specificatiile lor nu mai sunt aici.

  -- ---------------- 14. Amplasare mese, 3 grile ----------------
  -- In grilele 2 si 3, COD_UNIV si ZONE sunt ASCUNSE: valorile lor se vad deja
  -- in grila de deasupra si se completeaza automat la adaugare. Raman in
  -- interogare fiindca INSERT-ul le trimite mai departe.
  v_spec('1999|:fmFS1c:gr01') :=
      'COD_UNIV|Cod|50|ro;'
    ||'CLCDENUMIREA|Restaurant|240|ro;'
    ||'CLCNRZONE|Nr. zone|70|ro';

  v_spec('1999|:fmFS1c:gr01a') :=
      'COD_UNIV|||ro|ascuns;'
    ||'ZONE_CODE|Cod zona|100;'
    ||'NAME_RO|Denumire (ro)|160;'
    ||'NAME_RU|Denumire (ru)|160;'
    ||'NAME_EN|Denumire (en)|160;'
    ||'DISPLAY_ORDER|Ordine|70;'
    ||'ACTIVE|Activ|60;'
    ||'CLCNRMESE|Nr. mese|70|ro';

  v_spec('1999|:fmFS1c:gr01b') :=
      'COD_UNIV|||ro|ascuns;'
    ||'TABLE_NO|Nr. masa|90;'
    ||'ZONE|||ro|ascuns;'
    ||'DISPLAY_ORDER|Ordine|70;'
    ||'ACTIVE|Activ|60';

  -- ---------------------------------------------------------------
  v_key := v_spec.first;
  while v_key is not null loop
    v_obj := to_number(substr(v_key, 1, instr(v_key,'|') - 1));
    v_lob := substr(v_key, instr(v_key,'|') + 1);

    begin
      select utl_raw.cast_to_varchar2(dbms_lob.substr(lob_value, 30000, 1))
        into v_txt from a$lob where obj_id = v_obj and lob_name = v_lob;
    exception when no_data_found then
      dbms_output.put_line('  '||v_key||': fara rand in A$LOB - se sare');
      v_key := v_spec.next(v_key);
      continue;
    end;

    -- Inlocuim ORICE segment <cols>...</cols>, ca scriptul sa poata fi rulat
    -- din nou dupa ce clientul a rescris lista.
    v_a := instr(v_txt, '<cols>');
    v_b := instr(v_txt, '</cols>');
    if v_a = 0 or v_b = 0 or v_b < v_a then
      dbms_output.put_line('  '||v_key||': fara segment <cols> - se lasa neatins');
      v_key := v_spec.next(v_key);
      continue;
    end if;

    v_repl := cols_xml(v_spec(v_key));
    v_new  := substr(v_txt, 1, v_a - 1)||v_repl||substr(v_txt, v_b + length('</cols>'));

    update a$lob set lob_value = utl_raw.cast_to_raw(v_new), time_stamp = sysdate
     where obj_id = v_obj and lob_name = v_lob;

    dbms_output.put_line('  '||v_key||': reparat ('||length(v_repl)||' caractere)');
    v_key := v_spec.next(v_key);
  end loop;

  commit;
end;
/

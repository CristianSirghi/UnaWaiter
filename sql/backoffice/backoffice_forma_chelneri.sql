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

-- Trece forma "13. Chelneri UnaWaiter" (obj_id 1996) pe DOUA niveluri:
--     locatia  ->  chelnerii ei
--
-- Acelasi tipar ca "14. Amplasare mese" - vezi backoffice_forma_unificata.sql,
-- unde sunt explicate mecanismul si capcanele lui.
--
-- Motivul: pana acum `cod_univ` se tasta de mana la fiecare chelner adaugat.
-- Era ultima ramasita din vremea cand exista un singur restaurant, si singurul
-- loc unde o greseala de tastare aloca omul la alta filiala.
--
-- Forma 1996 are DEJA cheile XSQL* si FORMUSEDETAIL (mostenite din sablon), deci
-- nu trebuie importat nimic din alte forme.
--
-- >>> ORDINEA DE RULARE (invatata pe 2026-07-30):
-- >>>   1. acest fisier (schimba definitia si STERGE cache-ul din A$LOB)
-- >>>   2. reporneste UniacCLNT.exe, deschide forma, INCHIDE-O o data
-- >>>      -> clientul isi creeaza cache-ul pentru ambele grile
-- >>>   3. backoffice_fix_grid_cols.sql - pune titlurile coloanelor
-- >>>
-- >>> Pasul 1 sterge cache-ul intentionat: XML-ul din A$LOB contine o copie a
-- >>> interogarilor si clientul o ruleaza PE EA. Lasat pe loc, forma ar ramane
-- >>> cu un singur nivel oricat ai reporni.

set define off
set serveroutput on size 100000

declare
  c_obj constant number := 1996;

  procedure memo(p_key varchar2, p_val varchar2) is
  begin
    update a$adp set svalue = p_val, lvalue = to_clob(p_val)
     where obj_id = c_obj and key = p_key;
    if sql%rowcount = 0 then
      raise_application_error(-20099, 'Proprietatea '||p_key||' lipseste la nodul '||c_obj);
    end if;
  end;

  procedure flag(p_key varchar2, p_val varchar2) is
  begin
    update a$adp set bvalue = p_val where obj_id = c_obj and key = p_key;
    if sql%rowcount = 0 then
      raise_application_error(-20099, 'Flagul '||p_key||' lipseste la nodul '||c_obj);
    end if;
  end;
begin
  -- ------------------------------------------- NIVEL 1: locatia (read-only)
  -- Restaurantele vin din registrul ybmb_dif_cassa, nu se creeaza de aici.
  memo('SQL', 'select cod_univ, clcdenumirea, clcnrchelneri from vuw_locations order by cod_univ');
  memo('SQL_INSERT',  null);
  memo('SQL_UPDATE',  null);
  memo('SQL_DELETE',  null);
  memo('SQL_REFRESH', null);
  flag('EDITQUERY1', '0');

  -- ------------------------------------------ NIVEL 2: chelnerii filialei
  -- La SELECT, `:cod_univ` vine din randul selectat in grila de sus.
  memo('XSQL',
    'select cod_univ, oficiant, clcoficiantt, pin, active'
    ||' from vuw_waiters_all where cod_univ = :cod_univ order by oficiant');
  -- La INSERT/UPDATE/DELETE parametrii se leaga de campurile PROPRIEI grile -
  -- `cod_univ` e in lista de mai sus, deci se completeaza automat din parinte.
  memo('XSQL_INSERT',
    'insert into vuw_waiters_all (cod_univ, oficiant, pin, active)'
    ||' values (:cod_univ, :oficiant, :pin, :active)');
  memo('XSQL_UPDATE',
    'update vuw_waiters_all set pin = :pin, active = :active'
    ||' where cod_univ = :cod_univ and oficiant = :oficiant');
  memo('XSQL_DELETE',
    'delete from vuw_waiters_all where cod_univ = :cod_univ and oficiant = :oficiant');
  -- Numele vine din VMS_UNIVERS, nu de la tastatura: fara re-citire ar ramane
  -- gol pana la un refresh manual, si nu s-ar vedea daca s-a nimerit codul bun.
  memo('XSQL_REFRESH',
    'select cod_univ, oficiant, clcoficiantt, pin, active'
    ||' from vuw_waiters_all where cod_univ = :cod_univ and oficiant = :oficiant');

  flag('FORMUSEDETAIL', '1');
  update a$adp set ivalue = 200 where obj_id = c_obj and key = 'MASTERSIZE';

  -- Cache-ul vechi ar continua sa ruleze forma cu un singur nivel.
  delete from a$lob where obj_id = c_obj;

  commit;
  dbms_output.put_line('Forma 1996 trecuta pe 2 niveluri; cache-ul A$LOB sters.');
  dbms_output.put_line('Reporneste clientul, deschide forma si INCHIDE-O o data,');
  dbms_output.put_line('apoi ruleaza backoffice_fix_grid_cols.sql pentru titluri.');
exception
  when others then
    rollback;
    raise;
end;
/

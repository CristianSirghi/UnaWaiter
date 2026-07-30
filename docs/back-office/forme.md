# Cum se face o formă nouă în back-office

Formele din back-office (`Forme → …`) **nu sunt cod Delphi scris per formă**. Sunt
definite integral în metadate, într-o bază de date, și pot fi create fără să
recompilezi nimic și fără echipa producătorului.

Dovedit pe 2026-07-29 construind de la zero forma „Chelneri UnaWaiter", care
citește și scrie date reale.

---

## Unealta: Configurator

```
D:\Unisim\UNA.md-201208-5.77.0.11\uniConf.exe
```

E în același folder cu clientul de back-office (`UniacCLNT.exe`). Se conectează la
schema de back-office și editează exact tabelele de mai jos, cu interfață.

**Folosește-l pe el, nu `INSERT`-uri de mână.** Se poate și cu SQL (așa a fost
descoperit mecanismul), dar unealta pune singură cheile corecte și e ce știe și
echipa clientului.

Metoda uzuală: **selectezi o formă existentă → click dreapta → `Create new node`
→ `Add node`** (sibling, nu subnode) → modifici proprietățile. Copiezi o formă
care merge, în loc s-o construiești pe hârtie albă.

### Clonarea prin SQL, când ai deja o formă validată

Dacă pleci de la o formă care **funcționează**, clonarea prin SQL e mai sigură
decât retastarea în Configurator — copiază și proprietățile care nu apar în
catalogul `A$ADS` și pe care altfel le scapi:

```sql
insert into a$adm (obj_id, sys_id, obj_type, obj_subtype, link_id, parent_id,
                   template_id, name0, name1, name2, section, nrord, ...)
select <id_nou>, sys_id, obj_type, obj_subtype, link_id, parent_id,
       template_id, '<ro>', '<ro>', '<ru>', '<SECTION>', <id_nou>, ...
  from a$adm where obj_id = <id_sursa>;

insert into a$adp (obj_id, key, name, hint, gr, vtype, value0, value1, value2,
                   svalue, ivalue, bvalue, dvalue, lvalue, attr, fvalue)
select <id_nou>, key, name, hint, gr, vtype, value0, value1, value2,
       svalue, ivalue, bvalue, dvalue, lvalue, attr, fvalue
  from a$adp where obj_id = <id_sursa>;
```

Apoi schimbi doar `CAPTION` și cele patru `SQL*` — **în `SVALUE` și `LVALUE`
deodată** (capcana #1). `NRORD` = `OBJ_ID` e convenția casei.

Verificarea de final, care arată dacă ai atins din greșeală altceva:

```sql
select nvl(a.key,b.key) from (select * from a$adp where obj_id=<sursa>) a
  full outer join (select * from a$adp where obj_id=<nou>) b on a.key=b.key
 where nvl(a.svalue,'~')<>nvl(b.svalue,'~')
    or nvl(a.bvalue,'~')<>nvl(b.bvalue,'~')
    or nvl(a.ivalue,-1)<>nvl(b.ivalue,-1);
```

> ⚠️ `EDITQUERY1/2/3` au `VTYPE='B'`, deci valoarea lor stă în **`BVALUE`** ('1'),
> nu în `SVALUE`. Dacă te uiți doar la `SVALUE`, par goale și crezi că lipsesc.

---

## Unde stau metadatele

| tabelă | ce ține |
|---|---|
| `A$ADM` | nodul din arbore: tip, părinte, denumire în 3 limbi, `SECTION` |
| `A$ADP` | proprietățile lui: `key` + valoare |
| `A$ADS` | catalogul proprietăților disponibile per tip de obiect |
| `A$LOB` | aranjarea coloanelor din grilă + șabloane FastReport |

`A$ADM.OBJ_TYPE`: **1** Documents, **2** Journals, **3** Reports, **4 Forms**,
**5** Univ lists, **6** Settings, **7** Users.

Valoarea unei proprietăți stă în coloana potrivită tipului ei:
`S`→`SVALUE`, `I`→`IVALUE`, `B`→`BVALUE` ('1'/'0'), `M`→`SVALUE` **și/sau** `LVALUE`
(vezi capcana #1), **`C`→`VALUE0`/`VALUE1`/`VALUE2`** — text pe limbi
(— / ro / ru), vezi capcana #5.

---

## Proprietățile care contează pentru o formă de dicționar

```
Active            true
Caption           denumirea ferestrei
DLL FormName      FSal1p01          ← forma generică
DLL ID            8101
EditQuery1/2/3    true              ← FĂRĂ ele grila e read-only
FormNoGrid        false
MasterSize        310
SQL               select ...        ← ce se afișează
SQL_Insert        insert ...
SQL_Update        update ...
SQL_Delete        delete ...
```

Parametrii se scriu `:nume_coloana`, cu litere mici, la fel ca numele coloanei.

> `EditQuery1/2/3` **nu apar în catalogul `A$ADS`** — catalogul nu e exhaustiv.
> Se copiază dintr-o formă existentă care permite editarea.

---

## Datele sunt pe front, forma rulează în back

Forma rulează în baza de back-office, dar tabelele aplicației sunt pe fronturile
restaurantelor. Deci se ajunge la ele **prin db link**:

```sql
select ... from vuw_waiters@RISCANI.WORLD     -- citire
update uw_waiters@RISCANI.WORLD set ...       -- scriere
```

Citește dintr-un view (aduce nume, denumiri de filiale) și scrie în tabelul de
bază — un view cu join-uri nu e actualizabil (`ORA-01779`), chiar dacă
`ALL_UPDATABLE_COLUMNS` zice optimist `YES`.

### O formă pentru toate restaurantele

Cu link-ul scris în `SQL`, o formă acoperă un singur restaurant. Ca să le vezi pe
toate într-un ecran: **un view care le unește + un trigger `INSTEAD OF` care
rutează scrierea**, ambele în back-office.

```sql
create or replace view vuw_waiters_all as
select 11 cod_univ, oficiant, clcoficiantt, pin, active from vuw_waiters@RISCANI.WORLD
union all select 13, oficiant, clcoficiantt, pin, active from vuw_waiters@CENTRU.WORLD
union all select 17, oficiant, clcoficiantt, pin, active from vuw_waiters@MBATRIN.WORLD;
```

Trigger-ul **nu conține link-uri** — le citește din registru
(`YBMB_DIF_CASSA`), deci un restaurant nou nu cere cod nou:

```sql
select db_link into v_link from ybmb_dif_cassa
 where cod_univ = nvl(:new.cod_univ, :old.cod_univ) and secondary = 0;

execute immediate 'update uw_waiters@'||v_link||' set pin=:1 where ...' using ...;
```

Forma trimite atunci doar la view, fără niciun `@LINK` în ea.

> **Pune validările în trigger.** Forma scrie direct în tabel, ocolind pachetele
> PL/SQL ale aplicației, deci verificările lor (format PIN, „chelnerul există")
> trebuie repetate acolo. Altfel un cod tastat greșit creează date fantomă.

---

## Cele cinci capcane

Simptomele lor seamănă cu probleme de cache sau de drepturi, dar nu sunt.

### 1. Proprietățile Memo stau în DOUĂ coloane

`SQL`, `SQL_Insert` etc. pot exista simultan în `A$ADP.SVALUE` (text scurt) și
`A$ADP.LVALUE` (CLOB). **Configuratorul scrie în `SVALUE`, iar clientul citește
`SVALUE`.**

Dacă modifici doar `LVALUE` — reacția naturală când vezi `vtype='M'` — în bază
arată corect, dar clientul rulează în continuare varianta veche. Poți pierde o oră
crezând că e cache.

**Scrie întotdeauna în ambele, identic.** Peste 255 de caractere încape doar în
`LVALUE`.

### 2. Definiția se citește la pornire — dar cache-ul din `A$LOB` o bate

Nu la deschiderea ferestrei. După orice modificare de proprietăți, **repornește
`UniacCLNT.exe`** — nu e de ajuns să închizi și să redeschizi forma.

**Și nici repornirea nu e de ajuns, dacă forma și-a salvat deja un cache.**
XML-ul din `A$LOB` nu ține doar coloanele grilei, ci și o **copie a
interogărilor**, iar clientul **o rulează pe ea**, nu pe `A$ADP`:

```xml
<ds …><sql>…</sql><sqli>…</sqli><sqlu>…</sqlu><sqld>…</sqld><sqlr>…</sqlr></ds>
```

Simptomul: corectezi `SQL_INSERT`, repornești clientul, și tot vechea variantă se
execută — cu o eroare care arată ca o problemă de definiție, deși definiția e
corectă.

Cache-ul trebuie sincronizat, nu șters (ștergerea readuce capcana #4):

```sql
-- înlocuiește conținutul dintre <sqli> și </sqli> cu valoarea din A$ADP
```

Corespondența etichetă ↔ proprietate, pe niveluri:

| grilă | `<sql>` | `<sqli>` | `<sqlu>` | `<sqld>` | `<sqlr>` |
|---|---|---|---|---|---|
| `gr01` (nivel 1) | `SQL` | `SQL_INSERT` | `SQL_UPDATE` | `SQL_DELETE` | `SQL_REFRESH` |
| `gr01a` (nivel 2) | `XSQL` | `XSQL_INSERT` | … | … | … |
| `gr01b` (nivel 3) | `YSQL` | `YSQL_INSERT` | … | … | … |

### 3. `CREATE OR REPLACE VIEW` șterge trigger-ul `INSTEAD OF`

Oracle aruncă trigger-ele odată cu view-ul înlocuit. După orice modificare a
view-ului, **recreează trigger-ul**, altfel scrierile cad cu `ORA-01733` /
`ORA-01779` / `ORA-01752`, adică „view neactualizabil".

Tot aici: **nu pune `CAST(...)` pe coloanele view-ului** — devine coloană virtuală
și `INSERT` devine imposibil.

### 4. Forma apare fără coloane

Clientul salvează aranjarea grilei în `A$LOB` la închiderea formei. Dacă în acel
moment grila n-avea coloane (SQL gol, interogare cu eroare), salvează o aranjare
goală — și de atunci forma pare stricată, deși datele și SQL-ul sunt intacte.

```sql
DELETE FROM a$lob WHERE obj_id = <id-ul formei>;
COMMIT;
```

Clientul regenerează coloanele din interogare la următoarea deschidere.

**S-a și întâmplat**, pe 2026-07-30: forma „13. Chelneri UnaWaiter" arăta trei
rânduri complet goale. Datele erau intacte (chiar trei chelneri în
`VUW_WAITERS_ALL`) — doar coloanele lipseau. În `A$LOB` era salvat literal:

```xml
<cols><col field=""/></cols>
```

cu `TIME_STAMP` fix la închiderea formei din seara precedentă. Așa se recunoaște:
**numărul de rânduri e corect, dar nu se vede niciun cap de coloană.**
Diagnostic rapid, care găsește toate formele afectate dintr-o dată:

```sql
select obj_id, lob_name, time_stamp from a$lob
 where utl_raw.cast_to_varchar2(dbms_lob.substr(lob_value,200,1)) like '%<col field=""/>%';
```

**⚠️ Ștergerea rândului NU e o reparație — e un răgaz.** Forma se redeschide
corect, dar la următoarea închidere clientul rescrie exact aceeași listă goală.
Reparația care ține e să-i scrii tu o listă adevărată: odată ce cache-ul conține
coloane cu nume, clientul le reserializează corect și nu mai revine.

Formatul e XML, iar vocabularul lui **nu trebuie ghicit** — e stocat ca text în
`Asagi.bpl` (același folder cu clientul):

```
cols col field visible false color width font align readonly true
hcolor bstyle caption halign hfont list
```

Deci: `field` = coloana din interogare, `caption` = capul de coloană,
`width` = lățimea în pixeli, `readonly`, `visible`, `align`/`halign`.
**Fără `caption` grila arată datele corect, dar cu antet gol** — ușor de
confundat cu o formă stricată.

```xml
<cols><col field="COD_UNIV" caption="Filiala" width="60"/>
      <col field="CLCZONET" caption="Zona" width="150" readonly="true"/></cols>
```

Restul XML-ului (`<ds …><sql>…</sql><sqli>…</sqli>…`) e o copie a definiției
formei — se lasă neatins. Rulează reparația cu **clientul închis**: ține
aranjarea în memorie și o rescrie când închizi *o formă* (ieșirea din program,
în schimb, n-a rescris nimic).

> Se lovește doar cine construiește forme pe `FSal1p01` + proprietatea `SQL`.
> La Foișor, formele UnaWaiter erau primele de acest fel din toată instalarea —
> celelalte 1699 de aranjări salvate erau din 2019, în formatul binar Delphi
> (`SDBG`/`TPF0TColumnsWrapper`).

---

### Coloanele calculate rămân goale după salvare — `SQL_REFRESH`

Nu e o capcană, e o proprietate pe care e ușor s-o ratezi. După un INSERT sau
UPDATE, clientul afișează **ce a tastat operatorul**. Coloanele care se nasc în
view (`CLC…`: un nume adus prin join, un contor) rămân goale până la un refresh
manual.

`SQL_REFRESH` îi spune cum să re-citească **un singur rând**, după cheia lui:

```sql
select cod_univ, table_no, zone, clczonet, display_order, active
  from vuw_tables_all where cod_univ = :cod_univ and table_no = :table_no
```

Merită și ca verificare, nu doar cosmetic: tastezi codul unui om și îi vezi pe
loc numele — dacă apare altcineva, ai greșit codul, și afli imediat.

> **Ordinea corectă de lucru:** scrie întâi `SQL`-ul în Configurator, abia apoi
> deschide forma în client. Și ține forma **închisă** cât timp se modifică
> view-ul sau trigger-ul.

---

### 5. `CAPTION` e multilingv — și nu stă în `SVALUE`

`CAPTION` are `VTYPE='C'`: denumirea reală stă în **`VALUE1`** (ro) și **`VALUE2`**
(ru). Clientul citește `VALUE1`. Scris doar în `SVALUE`, textul nou nu apare
nicăieri — și dacă ai clonat o formă, **toate formele apar în meniu cu numele
formei-sursă**.

Măsurat pe 2026-07-30: din 42 de proprietăți `vtype='C'` din tot back-office-ul,
**toate 42 au `VALUE1`** și doar 3 au `SVALUE`. `SVALUE` nu e convenția casei —
confirmat și direct: când editezi `Caption` din Configurator, el scrie
`VALUE1`/`VALUE2` și **golește** `SVALUE`/`LVALUE`.

> Atenție, sunt **două** denumiri diferite, în tabele diferite:
> `A$ADP.CAPTION` → titlul ferestrei și eticheta din meniul back-office;
> `A$ADM.NAME0/1/2` → eticheta nodului din arborele **Configuratorului**.
> Configuratorul o editează doar pe prima. A doua se schimbă din `A$ADM`.

```sql
update a$adp set value1 = '14. Zone UnaWaiter',
                 value2 = '14. Зоны UnaWaiter'
 where obj_id = 1997 and key = 'CAPTION';
```

> ⚠️ **`A$ADM.NAME0/1/2` nu sunt de ajuns singure.** Erau puse corect (`14.`,
> `15.`), și meniul tot afișa „13. Chelneri UnaWaiter" de trei ori. Eticheta din
> meniu urmează `CAPTION`. Pune-le pe amândouă, consecvent.

---

## Forme pe mai multe niveluri (master → detail → subdetail)

O formă poate afișa trei grile legate — de exemplu **locația → zonele ei →
mesele zonei**. Avantajul nu e estetic: cheile părintelui (`cod_univ`, codul
zonei) **nu se mai tastează**, se moștenesc din rândul selectat mai sus. Exact
acolo se produc greșelile care mută date la alt restaurant.

```
FORMUSEDETAIL     true      MASTERSIZE   200     ← înălțimea grilei 1
FORMUSESUBDETAIL  true      MASTERSIZE2  190     ← înălțimea grilei 2
EDITQUERY1/2/3    editarea pe cele trei niveluri
```

Nivelurile 2 și 3 se descriu cu prefixele `X…` și `Y…` (`XSQL`, `XSQL_INSERT`,
`YSQL`, …). Filtrarea după părinte se scrie ca bind normal:

```sql
-- XSQL: zonele locației selectate
select … from vuw_zones_all where cod_univ = :cod_univ
-- YSQL: mesele zonei selectate
select … from vuw_tables_all where cod_univ = :cod_univ and zone = :zone_code
```

> ⚠️ **Parametrii se leagă din surse DIFERITE, după operație** — regula care
> costă cel mai mult timp dacă n-o știi:
>
> | operație | `:parametru` se caută în |
> |---|---|
> | `SELECT` (`XSQL`/`YSQL`) | rândul din grila **părinte** |
> | `INSERT` / `UPDATE` / `DELETE` | câmpurile **propriei** grile |
>
> De aceea `:zone_code` e corect în `YSQL` (vine din grila de zone), dar în
> `YSQL_INSERT` trebuie `:zone` — numele coloanei din grila de mese. Amestecate,
> clientul dă **„Not found field corresponding parameter zone_code"**.

Coloanele-cheie moștenite (`COD_UNIV`, `ZONE`) se pot ascunde din grilele de jos
cu `visible="false"` — se completează automat la adăugare și se văd oricum mai
sus. Rămân în `SELECT`, fiindcă `INSERT`-ul le trimite mai departe.

Formele cu un singur nivel **nu au** cheile `Y…` și nici `FORMUSESUBDETAIL` în
`A$ADP` — la clonare trebuie aduse (goale) dintr-o formă care le are, altfel
`UPDATE`-ul pe ele nu găsește rândul.

---

## Dezfacere

Tot ce ține de o formă e sub `obj_id`-ul ei:

```sql
DELETE FROM a$lob WHERE obj_id = <id>;
DELETE FROM a$adp WHERE obj_id = <id>;
DELETE FROM a$adm WHERE obj_id = <id>;
COMMIT;
```

---

## Convenții ale casei

- denumirea se pune în `A$ADM.NAME0/NAME1/NAME2` (ro / ro / ru) **și** în
  `CAPTION` (`VALUE1`/`VALUE2`). Eticheta din meniu o ia din `CAPTION` — vezi
  capcana #5
- în meniurile de dicționare, denumirile sunt prefixate numeric: `11.`, `12.`, `13.`
- codurile `SECTION` proprii (`F_CLIENTT`, `F_BARCODES`, `F_UWWAITERS`) sunt doar
  etichete — nu sunt tratate în codul Delphi. Excepție: `FORMUNIV` și `FORMSYSS`,
  care chiar sunt speciale în `unFSal1.bpl`.

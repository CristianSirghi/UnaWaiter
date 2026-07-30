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
(vezi capcana #1).

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

## Cele patru capcane

Toate ne-au lovit în aceeași seară, fiecare o dată. Simptomele lor seamănă cu
probleme de cache sau de drepturi, dar nu sunt.

### 1. Proprietățile Memo stau în DOUĂ coloane

`SQL`, `SQL_Insert` etc. pot exista simultan în `A$ADP.SVALUE` (text scurt) și
`A$ADP.LVALUE` (CLOB). **Configuratorul scrie în `SVALUE`, iar clientul citește
`SVALUE`.**

Dacă modifici doar `LVALUE` — reacția naturală când vezi `vtype='M'` — în bază
arată corect, dar clientul rulează în continuare varianta veche. Poți pierde o oră
crezând că e cache.

**Scrie întotdeauna în ambele, identic.** Peste 255 de caractere încape doar în
`LVALUE`.

### 2. Definiția formei se citește la pornirea clientului

Nu la deschiderea ferestrei. După orice modificare de proprietăți, **repornește
`UniacCLNT.exe`** — nu e de ajuns să închizi și să redeschizi forma.

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

> **Ordinea corectă de lucru:** scrie întâi `SQL`-ul în Configurator, abia apoi
> deschide forma în client. Și ține forma **închisă** cât timp se modifică
> view-ul sau trigger-ul.

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

- denumirea din meniu se pune în `A$ADM.NAME0/NAME1/NAME2` (ro / ro / ru), nu doar
  în `Caption`
- în meniurile de dicționare, denumirile sunt prefixate numeric: `11.`, `12.`, `13.`
- codurile `SECTION` proprii (`F_CLIENTT`, `F_BARCODES`, `F_UWWAITERS`) sunt doar
  etichete — nu sunt tratate în codul Delphi. Excepție: `FORMUNIV` și `FORMSYSS`,
  care chiar sunt speciale în `unFSal1.bpl`.

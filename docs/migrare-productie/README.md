# Mutarea UnaWaiter pe producție — ce trebuie făcut, în ce ordine

Documentul ăsta e rezultatul unei verificări complete făcute pe **2026-08-03**, pe
toate cele cinci baze implicate (frontul de test, back-office-ul de test, cele trei
fronturi de producție și back-office-ul de producție), plus pe backendul PHP live.

**Fiecare afirmație de aici a fost verificată cu o interogare sau cu o cerere HTTP
reală, nu presupusă.** Unde ceva n-a putut fi verificat de la distanță, scrie
explicit în [§7](#7-ce-nu-s-a-putut-verifica-de-aici).

Context complementar: [`../back-office/README.md`](../back-office/README.md)
(topologia platformei), [`../back-office/forme.md`](../back-office/forme.md)
(cum se fac formele), [`../auto-update/DEPLOY-PRODUCTIE.md`](../auto-update/DEPLOY-PRODUCTIE.md),
[`../smartone-fiscal/README.md`](../smartone-fiscal/README.md).

---

## 0. Rezumat

**Ce e gata:** tot stratul Oracle și PHP funcționează end-to-end pe test. Toate
prerechizitele tehnice există pe producție — drepturi, set de caractere, spațiu,
pachetele UAMenu de care depindem. Nu e nimic de negociat cu infrastructura.

**Ce blochează:** patru lucruri, dintre care **unul ar strica producția dacă
rulăm scripturile așa cum sunt** (§3.2). Niciunul nu e greu; toate trebuie
rezolvate înainte de prima instalare.

**Ce nu se poate ști de aici:** nimic din partea SmartOne n-a rulat vreodată pe un
terminal real, iar maparea restaurant ↔ front nu se poate confirma din baze (§6.1).

---

## 1. De ce producția NU e „la fel ca testul, cu alt IP"

Asta e diferența din care decurg aproape toate problemele:

```
TEST — o singură bază, două scheme
┌──────────────── clouddev.world (una.md:4024) ─────────────────┐
│  SUN                          FOISHOR_RISCANI_UNIREST         │
│  ├── A$ADM / A$ADP$V   ──GRANT SELECT──►  pg_mobile_web_waiter │
│  ├── VUW_*_ALL + forme                    UW_* + VUW_*         │
│  └── ybmb_dif_cassa                       TMDB_COMENZ          │
└───────────────────────────────────────────────────────────────┘
        ▲ pachetul poate citi configurarea direct, cu un simplu GRANT


PRODUCȚIE — patru baze, pe patru mașini
┌── cloudbd.world (una.md:4024) ──┐
│  FOISHOR                        │   back-office
│  ├── A$ADM / A$ADP$V            │
│  ├── VUW_*_ALL + forme          │
│  └── ybmb_dif_cassa             │
└─────────────┬───────────────────┘
              │ db link ── DOAR în sensul ăsta ──►
              ▼            (fronturile n-au NICIUN db link: verificat, 0)
   ┌──────────┼──────────────────┐
   ▼          ▼                  ▼
 93.116.209.117  185.247.159.33  95.65.21.122      ← baze XE separate,
 filiala 11      filiala 13      filiala 17          fizic la restaurante
 MIRON COSTIN    COLUMNA         M. cel BĂTRÎN
```

Pe test, schema de configurare și schema aplicației sunt **în aceeași bază**, deci
un `GRANT` rezolvă totul. Pe producție sunt **baze diferite, fără legătură dinspre
front spre back**. De aici blocantul #1.

### Maparea restaurantelor (din `ybmb_dif_cassa` pe `FOISHOR@cloudbd`)

| cod_univ | denumire | db link | gazdă |
|---|---|---|---|
| 11 | MIRON COSTIN | `riscani.world` | `93.116.209.117/xe` |
| 13 | COLUMNA | `centru.world` | `185.247.159.33/xe` |
| 17 | MIRCEA cel BĂTRÎN | `mbatrin.world` | `95.65.21.122/xe` |
| 12 | MEGAPOLIS MALL | `megapolis.world` | — **fără db link** |
| 16 | ALECO RUSSO | `arusso.world` | — **fără db link** |

12 și 16 sunt în registru dar n-au link, deci `get_restaurants` le sare automat
(verificat: interogarea PHP-ului întoarce exact 3 rânduri). Corect — la ele nu ne
putem conecta oricum.

---

## 2. Inventarul complet de instalat

### 2.1 Pe FIECARE dintre cele 3 fronturi de producție

Conexiune: `unirest/unirest@<gazdă>:1521/xe`

| # | Obiect | Script sursă |
|---|---|---|
| 1 | `UW_ZONES` + check-uri + seed | `sql/uw_zones.sql` |
| 2 | `UW_TABLES` + PK + seed | `sql/uw_tables.sql` |
| 3 | `UW_TABLES_ZONE_FK` + `UW_TABLES_ZONE_IX` | `sql/uw_zones.sql` (partea finală) |
| 4 | `UW_WAITERS` + PK + check PIN | `sql/uw_waiters.sql` |
| 5 | `UW_FISCAL_RECEIPTS` + index doc | `sql/uw_fiscal_receipts.sql` |
| 6 | coloana `RRN` pe tabela de mai sus | `sql/uw_fiscal_receipts_add_rrn.sql` |
| 7 | `UW_FISCAL_INCIDENTS` + UK | `sql/uw_fiscal_incidents.sql` |
| 8 | `VUW_WAITERS`, `VUW_ZONES`, `VUW_TABLES` | `sql/vuw_views.sql` |
| 9 | `PG_MOBILE_WEB_WAITER` spec | `sql/pg_mobile_web_waiter_spec.sql` |
| 10 | `PG_MOBILE_WEB_WAITER` body | `sql/pg_mobile_web_waiter_body.sql` |

> ⚠️ Scripturile trăiesc pe `C:\Users\user\Desktop\foishor_test\sql\`, **nu în git**.
> Înainte de orice, copiază-le în repo — altfel instalarea pe producție depinde de
> un desktop.

> ⚠️ `uw_fiscal_receipts.sql` **nu** conține coloana `RRN`; e într-un script separat
> (pasul 6). E ușor de sărit și se descoperă abia la prima plată cu RRN manual.

> ⚠️ `pg_mobile_web_waiter_body.txt` (varianta `.txt` de pe Desktop) e **veche**.
> Sursa bună e `.sql`. Fișierul n-are `/` la final — se compilează cu
> `set sqlblanklines on` și un `/` adăugat, altfel sqlplus nu-l trimite deloc și
> pachetul rămâne tăcut cel vechi.

### 2.2 Pe back-office-ul de producție (`foishor/foi26shor@una.md:4024/cloudbd.world`)

| # | Obiect | Observație |
|---|---|---|
| 1 | `VUW_WAITERS_ALL` + `TRG_VUW_WAITERS_ALL` | cu **toate 3** branșele (vezi §3.3) |
| 2 | `VUW_ZONES_ALL` + `TRG_VUW_ZONES_ALL` | idem |
| 3 | `VUW_TABLES_ALL` + `TRG_VUW_TABLES_ALL` | idem |
| 4 | `VUW_LOCATIONS` | generic, se ia ca atare |
| 5 | Forma „Chelneri UnaWaiter" | **obj_id NOU** (vezi §3.2) |
| 6 | Forma „Amplasare mese" | **obj_id NOU** (vezi §3.2) |
| 7 | Secțiunea `WEB_WAITER` cu `AUTOUPDATE_LINK` | doar dacă rămânem pe varianta Oracle a auto-update-ului (vezi §3.1) |

Sursă: `sql/backoffice_uw_all.sql` (view-uri + triggere),
`sql/backoffice_forma_chelneri.sql` și `sql/backoffice_forma_unificata.sql` (forme).

### 2.3 PHP

- se urcă `foisor_prod.php` în `/var/www/html/um/una_waiter/` (acum dă 404 —
  corect, nu trebuie urcat înainte de Oracle);
- `oracle_waiter.php` e comun ambelor medii, deja deployat și actualizat;
- **directorul trebuie să fie scriibil de Apache** (vezi §3.4).

### 2.4 Aplicație

- `qml/app/AppSettings.qml:41` are hardcodat endpoint-ul de **test**
  (`http://una.md:3323/um/una_waiter/foisor.php`). Pentru APK-ul de producție,
  ori se schimbă în `foisor_prod.php`, ori se re-activează ecranul Administrare
  (ascuns cu `visible: false` în `SettingsPage`).
- `src/core/appversion.h` e la `1.0`, la fel ca `version.json` de pe server —
  de bumpat la lansare. Regula de numerotare: **maxim `.9` pe segment**
  (`1.9` → `2.0`, niciodată `1.10`).

---

## 3. Cele patru blocante

### 3.1 ✅ REZOLVAT 2026-08-03 — `get_update_info` nu putea compila pe producție

**Soluția aplicată (opțiunea 1 de mai jos):** citirea s-a mutat în PHP
(`uwUpdateInfoFromBackOffice()` din `oracle_waiter.php`), iar funcția a fost scoasă
din pachet. PHP-ul e oricum conectat la back-office pentru registru, și **ca
proprietarul lui** (`sun` pe test, `foishor` pe producție) — deci `A$ADM` se rezolvă
în schema proprie, fără niciun prefix, cu același cod în ambele medii. Verificat:
interogarea rulează pe amândouă back-office-urile.

Comanda a fost mutată și în lista celor care nu cer restaurant: valoarea e una
singură pentru tot clientul, deci verificarea de versiune merge acum **și când baza
unui restaurant e căzută** — exact situația în care ai putea avea nevoie să împingi
o versiune nouă.

Pachetul recompilat pe test: **VALID, zero referințe `SUN.`**.

⚠️ **Ordinea de deploy e INVERSĂ față de regula obișnuită.** Aici scoatem o
dependență, nu adăugăm una: se urcă **întâi PHP-ul**, apoi se compilează Oracle.
Între cele două, `get_update_info` întoarce `PLS-00302`. Nu blochează pe nimeni —
`main.qml` tratează eșecul tăcut la pornire (`onRequestFailed`), iar chelnerul poate
lucra normal; doar ecranul de Actualizare arată eroare dacă e deschis manual.

Descrierea problemei, păstrată pentru context:

---

**Problema care era**

Corpul funcției referă `SUN.A$ADM` și `SUN.A$ADP$V` cu prefix de schemă hardcodat
(o singură apariție reală, la **linia 786** din body; celelalte 3 apariții ale lui
`SUN.` sunt comentarii).

Verificat pe toate 3 fronturile: `select count(*) from all_objects where owner='SUN'`
→ **0**. Nu e o problemă de nume de schemă. Pe producție configurarea stă în
`FOISHOR@cloudbd`, care e **altă bază**, iar fronturile n-au niciun db link
(`user_db_links` → 0 pe toate 3). Deci un `GRANT` e imposibil.

Dacă rămâne așa, `CREATE PACKAGE BODY` iese **INVALID** și **nu merge nimic**, nu
doar auto-update-ul.

**Opțiuni, în ordinea preferinței:**

1. **Mută citirea în PHP.** `oracle_waiter.php` are deja o conexiune la back-office
   (o folosește pentru registru) — de acolo `A$ADM`/`A$ADP$V` sunt la îndemână.
   Comanda `get_update_info` devine un `case` care citește direct, iar funcția
   Oracle dispare. Zero configurare nouă pe fronturi.
2. **Tabelă locală `uw_settings(key, value)`** pe fiecare front, cu `AUTOUPDATE_LINK`.
   Simplu, dar înseamnă trei locuri de întreținut în loc de unul.
3. Db link front → cloudbd. **Nerecomandat**: deschide o dependență nouă în sensul
   greșit, exact ce evită arhitectura actuală.

### 3.2 ✅ REZOLVAT 2026-08-03 — scripturile formelor ar fi stricat producția

**Soluția:** un instalator nou, portabil — [`../../sql/backoffice/forme/`](../../sql/backoffice/forme/).
Niciun `obj_id` scris de mână: părintele se caută după `SECTION = 'CLASSIF'`,
`obj_id`-urile noi se iau ca `MAX(obj_id)+1` și `+2` (coliziune imposibilă prin
construcție), iar dacă formele există deja scriptul refuză cu `ORA-20080`.

Definițiile — toate cele 110 proprietăți — sunt **extrase din baza de test**, unde
formele sunt validate, nu reconstruite prin clonare din șabloane: un șablon poate
diferi între medii, iar o proprietate lipsă face grila read-only fără niciun mesaj.

Verificat: probă completă pe test cu `rollback` (110 inserturi curate, zero urme),
garda refuză corect, iar `A$ADM.SECTION` e `UNIQUE` — deci și dacă cineva ocolește
garda, baza respinge instalarea dublă. Pe producție formele vor primi **2136** și
**2137**.

Scripturile vechi rămân în `sql/backoffice/` ca istoric. **Nu le rula pe producție.**

Descrierea problemei, păstrată pentru context:

---

**Problema care era**

`obj_id`-urile pe care le folosim sunt **toate ocupate de obiecte reale** pe
`FOISHOR@cloudbd`:

| obj_id | la noi, pe test | pe PRODUCȚIE |
|---|---|---|
| 1991 | secțiunea `WEB_WAITER` | SALARIU TARIFAR (tabel de pontaj) |
| 1996 | „13. Chelneri UnaWaiter" | acțiune „Перезаполнить дни/часы из табеля" |
| 1997 | formă ștearsă | `TOTAL:900` |
| 1998 | formă ștearsă | raport `DG1P26 49-Reports` |
| 1999 | „14. Amplasare mese" | acțiune „Заполннение данных" |

**`backoffice_forma_chelneri.sql` face `update a$adp ... where obj_id = 1996` și
`delete from a$lob where obj_id = 1996` fără nicio verificare.** Pe producție ar
corupe un obiect real de salarizare. `backoffice_forma_unificata.sql` are gardă
(`-20098` dacă nodul există), deci acela eșuează curat — dar tot nu face ce trebuie.

În plus:
- șabloanele de clonare **1867 și 1868 nu există deloc** pe producție;
- singurul nod cu chei `YSQL*` (necesare formei pe 3 niveluri) e **1889 „Баркоды"**;
- nodul-părinte 1854 e altceva pe prod („Action:0"), nu meniul de dicționare;
- `MAX(obj_id)` pe producție = **2135**.

**De făcut:** parametrizează ambele scripturi (obj_id sursă, obj_id nou, părinte),
alege ID-uri **≥ 2136**, identifică pe producție meniul-părinte real și un șablon
cu `YSQL*`. Nu rula niciunul înainte de asta.

### 3.3 ✅ REZOLVAT 2026-08-03 — view-urile din back-office erau mono-filială

**Soluția:** [`../../sql/backoffice/vuw_all/`](../../sql/backoffice/vuw_all/) —
view-urile se **generează** dintr-o listă de filiale, iar triggerele se recreează
în aceeași rulare:

```bash
sqlplus foishor/<parola>@una.md:4024/cloudbd.world @00_install_vuw_all.sql 11
```

Nu mai e nimic de decomentat. Numele link-ului vine din `ybmb_dif_cassa` — același
registru pe care îl folosesc triggerele — deci citirea și scrierea nu pot ajunge să
arate spre baze diferite. Adăugarea Columnei mai târziu = aceeași comandă cu
`11,13`.

`VUW_LOCATIONS` e restrâns la aceleași filiale, deci la pilot forma arată **un
singur restaurant**, nu toate cele 5 din registru (dintre care 2 n-au nici db link).

Verificat pe test: instalare completă 15/15 OK; filială inexistentă și cod invalid
refuzate curat; `11,13,17` pică cu `ORA-12154` **fără să atingă view-urile
existente**, iar testul a rămas intact după.

⚠️ **Descoperit cu ocazia asta:** Oracle rezolvă db link-ul deja la
`CREATE OR REPLACE VIEW`, nu doar la `SELECT`. Deci un restaurant al cărui front e
căzut **nu poate fi nici măcar instalat** în view-uri în acel moment — nu doar
interogat. Consecință practică: instalarea celui de-al doilea și al treilea
restaurant cere ca fronturile lor să fie pornite.

Descrierea problemei, păstrată pentru context:

---

**Problema care era**

Toate trei `VUW_*_ALL` sunt, pe test:

```sql
select 11 cod_univ, ... from vuw_waiters@RISCANI.WORLD
-- union all select 13, ... from vuw_zones@CENTRU.WORLD
-- union all select 17, ... from vuw_zones@MBATRIN.WORLD
```

Branșele pentru 13 și 17 sunt scrise și comentate. Pe producție se decomentează.

**Vestea bună:** partea de **scriere** e deja complet generică. Triggerele
`INSTEAD OF` își iau db link-ul **dinamic** din `ybmb_dif_cassa` după `cod_univ`
(`execute immediate 'insert into uw_waiters@'||v_link||' ...'`). Un restaurant nou
nu cere cod nou — doar un rând în registru și o linie decomentată.

> ⚠️ `CREATE OR REPLACE VIEW` **șterge trigger-ul `INSTEAD OF`**. După orice
> modificare de view, recreează trigger-ul, altfel scrierile din formă cad cu
> `ORA-01733` / `ORA-01779` / `ORA-01752`. De aceea `backoffice_uw_all.sql` ține
> fiecare view lipit de trigger-ul lui — păstrează structura asta.

> ⚠️ `UNION ALL` peste 3 fronturi înseamnă că **dacă un restaurant e căzut, formele
> nu se deschid deloc**, nici pentru celelalte două. De acceptat conștient, sau de
> înfășurat fiecare branșă în ceva tolerant la erori.

### 3.4 ⚠️ PARȚIAL REZOLVAT 2026-08-03 — partea de cod e făcută, partea de server nu

**Ce s-a făcut în PHP:**

- **Cache și log separate pe medii.** `registry-test.json` / `registry-prod.json`,
  `php-error-test.log` / `php-error-prod.log`, prin `$env_key` din fișierul subțire.
  Cu cădere pe amprenta conexiunii la back-office dacă lipsește — deliberat, ca un
  motor nou urcat peste un fișier subțire vechi să nu rupă backendul.
- **`$uw_data_dir`**, opțional, pentru a muta ambele fișiere în afara rădăcinii web.
- **`.htaccess`** care refuză `.json` și `.log` — plasă de rezervă, funcționează
  doar dacă `AllowOverride` e activ.
- **`ping` raportează starea discului**: `{"status":"ok","env":"test",
  "dataDir":"writable|READONLY","registry":"cached 42s|absent"}`. Doar cuvinte de
  stare, niciodată căi de fișier — endpoint-ul n-are autentificare.

**De ce contează separarea, concret:** o cerere de producție scrie în cache
`{11 → 93.116.209.117/xe, 13, 17}`; în următoarele 5 minute (TTL) o cerere de test
găsește cache-ul proaspăt, îl ia ca atare, și telefonul de test se conectează cu
`unirest/unirest` la **baza reală a restaurantului**. Azi nu se întâmplă doar
fiindcă nu se scrie nimic pe disc — un accident, nu o protecție. **Se activează
exact în clipa în care se repară drepturile.**

**Ce rămâne de făcut pe server (Kristian):**

1. dă drept de scriere utilizatorului Apache — de preferat pe un director nou din
   afara rădăcinii web (ex. `/var/lib/unawaiter`), apoi decomentează
   `$uw_data_dir` în fișierele subțiri;
2. urcă `oracle_waiter.php`, `foisor.php` și `.htaccess`;
3. verifică:

```bash
curl 'http://una.md:3323/um/una_waiter/foisor.php?cmd=ping'
```

trebuie să răspundă cu `"dataDir":"writable"`, iar la al doilea apel
`"registry":"cached …s"`. Și:

```bash
curl -o /dev/null -w "%{http_code}\n" 'http://una.md:3323/um/una_waiter/registry-test.json'
```

trebuie să dea **403 sau 404, niciodată 200**.

Descrierea problemei, păstrată pentru context:

---

**Problema care era**

Verificat pe test: `registry.json` → **404**, `php-error.log` → **404**, deși
fișierele `.php` din același director se servesc normal (200) și `.json` se servește
în altă parte pe același Apache (`/f/c/una_waiter/version.json` → 200).

Nu e ipoteză. Pe test, registrul întoarce **5 filiale**, din care 4 au gazdă alias
TNS netraductibilă → `uwUsableRestaurants()` scrie **4 linii de `error_log()` la
fiecare cerere**. Dacă directorul ar fi scriibil, fișierul ar avea zeci de mii de
linii. Nu există.

Consecințe, ambele importante pe producție:

1. **Nu există niciun diagnostic pe server.** Orice eșec de conectare la un
   restaurant, orice `set_restaurant` picat, orice eroare de `oci_execute` se pierde
   în tăcere. La prima problemă din sală n-o să avem de unde afla ce s-a întâmplat.
2. **Cache-ul registrului nu funcționează**, deci **fiecare cerere deschide o
   conexiune nouă la back-office**. Exact scenariul pe care cache-ul îl prevenea: o
   problemă la Chișinău oprește un restaurant care are Oracle-ul lui sănătos la doi
   metri de chelner. (Măsurat: `ping` = 13 ms, `get_restaurants` = 81 ms constant la
   3 apeluri consecutive — cu cache activ, al doilea ar fi fost ~15 ms.)

**De făcut:** dă drept de scriere userului Apache pe
`/var/www/html/um/una_waiter/`, apoi verifică prin WinSCP că `registry.json` apare
și că `php-error.log` crește. Și pune **ambele** în afara rădăcinii web sau
blochează-le din Apache — `registry.json` conține gazdele și utilizatorii bazelor
de producție, iar convenția e user = parolă.

---

## 4. Ordinea de instalare

> **Regula de aur: întâi Oracle, apoi PHP, apoi APK.** Pe 2026-07-28 backendul de
> test a fost rupt câteva minute exact pentru că s-a urcat PHP-ul înaintea
> pachetului (`PLS-00306`: PHP-ul trimitea un parametru care încă nu exista).

### Pasul 0 — pregătire (înainte de a atinge producția)

- [ ] Copiază scripturile `sql/*` de pe Desktop în repo și comite-le.
- [x] ~~Rezolvă §3.1 (`get_update_info`)~~ — **făcut 2026-08-03.** Citirea s-a mutat
      în PHP, funcția a fost scoasă din pachet, iar pachetul recompilat VALID pe
      test. Pachetul n-are acum nicio referință în afara schemei aplicației.
      **Mai trebuie doar urcat `oracle_waiter.php`** — până atunci `get_update_info`
      întoarce eroare pe test (tratată tăcut la pornire, vezi mai jos).
- [ ] Parametrizează scripturile de forme (§3.2). Nu le rula pe producție înainte.
- [ ] Ia de la client numerele reale de mese și zonele fiecărui restaurant (§5).

### Pasul 1 — fronturile (×3, unul câte unul)

Pentru fiecare din `93.116.209.117`, `185.247.159.33`, `95.65.21.122`:

```bash
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
sqlplus "unirest/unirest@93.116.209.117:1521/xe"
```

Ordinea contează:

1. `uw_zones.sql` — **seed-ul trebuie să fie ÎNAINTE de cheia străină**, altfel
   `ORA-02298` pe mesele existente.
2. `uw_tables.sql` — cu numerele reale ale restaurantului, nu cu seed-ul de exemplu.
3. cheia străină + indexul din `uw_zones.sql` (fără index, orice `DELETE` pe zone ia
   lock de tabel pe mese).
4. `uw_waiters.sql`
5. `uw_fiscal_receipts.sql`, apoi `uw_fiscal_receipts_add_rrn.sql`
6. `uw_fiscal_incidents.sql`
7. `vuw_views.sql`
8. `pg_mobile_web_waiter_spec.sql`, apoi `..._body.sql`
9. `show errors` — pachetul trebuie să fie **VALID**. Dacă nu e, oprește-te aici.

### Pasul 2 — back-office-ul de producție

1. `backoffice_uw_all.sql`, cu cele 3 branșe active (§3.3).
2. Formele, cu `obj_id` noi (§3.2).
3. Repornește `UniacCLNT.exe` și deschide fiecare formă — **prima deschidere
   generează coloanele**, vezi capcana #4 din `../back-office/forme.md`.

### Pasul 3 — PHP

1. Dă drepturile de scriere pe director (§3.4).
2. Urcă `foisor_prod.php` prin WinSCP.
3. Verifică imediat: `curl 'http://una.md:3323/um/una_waiter/foisor_prod.php?cmd=get_restaurants'`
   → trebuie să întoarcă exact cele 3 filiale (11, 13, 17).

### Pasul 4 — APK

1. Schimbă `serverUrl` (sau re-activează Administrare).
2. Bumpează versiunea.
3. Urcă APK-ul + `version.json` pe server.

---

## 5. Datele de seed — ce arată realitatea de pe producție

Numerele de masă folosite efectiv în ultimele 60 de zile. **De confirmat cu
Daniela/Sandu înainte de seed** — cifrele astea arată ce s-a tastat, nu neapărat
ce mese există.

**Filiala 11 (Miron Costin)** — 36 numere distincte: `1–35` continuu, plus
`121, 147, 222, 2088` (evident greșeli de tastare, o comandă fiecare).

**Filiala 13 (Columna)** — numerotare **pe grupe, probabil câte o zonă**:
`11–16`, `21–26`, `31–35`. Plus `1` și `3` (1 și 3 comenzi) și o coadă lungă de
valori cu câte o singură comandă (`103–909`, `1003`, `2001–2005`). Grupele sugerează
**3 zone**, nu 2 — de confirmat.

**Filiala 17 (Mircea cel Bătrîn)** — `1–24` continuu, plus **`desk = 0` folosit de
15 ori**, plus `88, 146, 187, 222` cu câte o comandă.

> ⚠️ `desk = 0` e respins de PHP: `createOrder()` folosește `empty($desk)`, iar în
> PHP `empty(0)` e `true` → „Missing desk parameter". Dacă masa 0 e reală la Mircea,
> nu va putea fi folosită din aplicație.

**Comenzi fără masă** (vânzări de la casă, normale în UAMenu): 1775 la Columna și
1089 la Mircea în 60 de zile. Modelul nostru „La pachet" e compatibil cu ele.

**`COMENT` e liber pe toate 3** (0 comenzi cu comentariu în 90 de zile), deci
marcajul „La pachet" nu suprascrie nimic.

---

## 6. Riscuri cunoscute și decizii deschise

### 6.1 Frontul nu știe ce restaurant e — doar registrul știe

| front | registrul zice | `GlobalDep` implicit (din `TRG_ON_LOGON`) | ce scrie UAMenu pe comenzi (`NRSET`) |
|---|---|---|---|
| 93.116.209.117 | 11 | **13** | **16** |
| 185.247.159.33 | 13 | **13** | **16** |
| 95.65.21.122 | 17 | **13** | **16** |

Trei numere diferite pentru același front. Valoarea implicită e 13 peste tot (același
trigger clonat), iar UAMenu pune 16 peste tot la login. **Singura autoritate e
`ybmb_dif_cassa`** — exact ce folosește PHP-ul nostru, deci rutarea e corectă.

Dar consecința e că **nimic de pe front nu poate contrazice o intrare greșită în
registru**. Dacă `riscani.world` ar arăta spre alt restaurant, n-am afla din baze.
**De confirmat verbal cu clientul înainte de prima comandă reală.**

`set_restaurant` va scrie `NRSET` = filiala aleasă (11/13/17), diferit de 16-ul
UAMenu. Am căutat toți consumatorii de `NRSET` — în tot PL/SQL-ul de producție și în
toate definițiile de view-uri — și **nu filtrează nimeni pe el**; apare doar ca
purtare de coloană. Deci e inofensiv azi. Dacă cineva face vreodată un raport pe
`NRSET`, comenzile noastre ies din el.

### 6.2 Lista de chelneri: 101 nume la fiecare restaurant

`get_waiters` nu filtrează pe `cod_univ` — întoarce tot payroll-ul
(`VSLRPRM_CALCD_R_502`), care e **identic pe toate fronturile: 101 chelneri**.

> ⚠️ **Corectat 2026-08-03, descoperit rulând `99_verify.sql`:** pe test,
> `VSLRPRM_CALCD_R_502` **nu e vederea reală**, ci un înlocuitor scris de mână care
> întoarce tot din `vms_univers`:
> ```sql
> SELECT cod sc_munc, 1 DEP_SECTIA, 10 KADR_DOLJN_R_502
>   FROM vms_univers WHERE tip='O' AND gr1 IN ('R','P','S') AND isarhiv IS NULL
> ```
> De aceea `get_waiters` întoarce **743 de nume pe test** și **101 pe producție**.
> Comportamentul listei de chelneri **nu se poate valida pe test** — orice concluzie
> despre ea trebuie măsurată pe producție. Asta corectează și presupunerea mai veche
> că „lista de personal filtrează ~41 de intrări de test": cifra aia a fost măsurată
> pe înlocuitor, nu pe mecanismul real.

Mai mult, `set_pin` verifică doar „e chelner real", nu „aparține restaurantului
ăstuia" — deci **oricine din cei 101 se poate auto-înrola la orice filială**. Dacă
înrolarea trebuie controlată, poarta e forma din back-office, iar `set_pin` ar trebui
să ceară un rând preexistent în `uw_waiters`.

### 6.3 Dicționarele de pe producție sunt vechi, și inegal

`MVSLRPRM_CALCD` (lista de chelneri), `MVMS_UNIVERS` și `MVPR1D_PERPRLIST` (meniul și
prețurile) sunt materialized views cu refresh **ON DEMAND / manual**:

| filiala | ultimul refresh | vechime la 2026-08-03 |
|---|---|---|
| 11 Miron Costin | 2026-07-01 | **33 zile** |
| 13 Columna | 2026-07-20 | 14 zile |
| 17 M. cel Bătrîn | 2026-08-02 | 1 zi |

**Un chelner angajat în iulie pur și simplu nu poate intra în aplicație la Miron
Costin** — nu apare în `get_waiters`, iar mesajul pe care-l primește e
„date greșite". Meniul e la fel de vechi, dar acolo e consistent cu UAMenu, deci nu
produce diferență între app și casă.

De spus clientului: **înainte de lansare, refresh la dicționarele fiecărui restaurant.**

### 6.4 TVA — decis: cotele rămân în cod, C = 6%

> Secțiunea asta a fost **rescrisă pe 2026-08-03**. Prima ei versiune spunea
> „C = 10%, cota ar trebui să vină din Oracle" — luat dintr-o notiță mai veche, nu
> din cod. Între timp întrebarea fusese lămurită și decizia inversată (commit
> `1bfe769` „TVA hardocat in cod"). Autoritatea e
> [`../smartone-fiscal/README.md`](../smartone-fiscal/README.md), nu documentul ăsta.

Starea de acum, verificată în cod și în bază:

- `taxForCode()` din `smartoneclient.cpp`: **A=20, B=8, C=6**, formulă **inclusivă**
  (prețurile UAMenu au TVA-ul inclus, deci taxa e `sumă × r/(1+r)`).
- În Oracle **NU există** coloana `TVA_PRC`. A fost încercată și **retrasă înainte
  de compilare** — motivul e scris ca avertisment chiar în corpul pachetului, la
  `get_order_lines`, ca să nu fie reintrodusă din bune intenții.
- Motivul retragerii: `Unirest_Util.vat_percent_by_letter` întoarce **10** pentru
  litera C, valoare contrazisă de tot restul — aparatul SmartOne tipărește **6%**
  (dovedit: aplicația a trimis 10.00%, pe bon a ieșit 6%), iar UAMenu înregistrează
  **6%** (`TVA_C`, pe 8426 din 8426 comenzi de producție).
- C++ preferă totuși cota din backend dacă vreodată apare o coloană `TVA_PRC` —
  deci când există o sursă în care se poate avea încredere, se adaugă în Oracle și
  merge de la sine, fără build de APK.

**Ce rămâne pentru client (Sandu/Daniela), și nu e problema noastră:** imprimanta
**Tremol** de la casă tipărește **10%** pentru aceeași literă, prin `Unirest_Util`
și pachetul `BON`. Adică același restaurant emite bonuri cu **6% din aplicație** și
cu **10% de la casă**, pe același produs — iar UAMenu contabilizează la 6% dar
tipărește 10%. E o contradicție a lor, de ridicat înainte de lansare, nu de
propagat la noi.

### 6.5 UAMenu are coloane native de RRN, pe care nu le folosim

`TMDB_COMENZ` are `TERM_RRN VARCHAR2(32)`, `TERM_RRN_MANUAL NUMBER`,
`TERM_OP_STATUS`, `TERM_RCODE` — **expuse chiar în `VMDB_COMENZ_RESTAURANT`**, prin
care scriem, și trecute de trigger atât pe INSERT cât și pe UPDATE (liniile 143/150).
Pe producție sunt **nefolosite: 0 din 4350 de plăți cu card în 90 de zile**.

Noi ținem RRN-ul doar în `uw_fiscal_receipts.rrn`, deci e invizibil în UAMenu și în
Back. `pay_order` face deja acel UPDATE — ar costa un singur `term_rrn = p_rrn` în
plus. (`TERM_RRN` e text; `TERM_RRN_MANUAL` e NUMBER și ar pierde zerourile din față.)

### 6.6 Lucruri mici, dar reale

- **`update_order_desk` n-are `DBMS_LOCK`**, deși `create_order` are
  (`UW_DESK_LOCK_<desk>`) și `pay_order` are (`UW_PAY_LOCK_<nr>`). Verificarea
  „masa are deja comandă" se face fără serializare → două mutări simultane pe
  aceeași masă, sau o mutare simultană cu o creare, pot trece amândouă. E exact
  clasa de bug închisă la `create_order` pe 2026-07-20, rămasă deschisă aici.
- **`cancel_order`, `update_order_desk` și `add_order_line` nu fac `COMMIT`** (spre
  deosebire de `create_order` și `pay_order`). Merg pentru că `oci_execute()` comite
  implicit — dar depind de o valoare implicită din PHP, nu de o intenție scrisă.
- **`add_order_line`** calculează `t` cu `MAX(t)+1` și apoi recitește rândul; două
  adăugări simultane ale aceluiași produs pe aceeași comandă ar da `ORA-01422`.
  Puțin probabil (blocarea mesei previne asta), dar există.
- **`-20057` (suma de pe bon ≠ totalul comenzii) nu converge**, spre deosebire de
  `-20055`/`-20056` care se sting prin `uw_fiscal_incidents`. Bonul e deja tipărit,
  `pending_fiscal.json` rămâne, clientul reia la fiecare pornire → comandă blocată
  permanent. Se întâmplă dacă cineva modifică comanda de la casă între citirea
  liniilor și plată.
- **Erorile fiscale nu sunt traduse.** În QML sunt mapate doar
  `ORA-20050/20060/20061`. Pentru `20053/20054/20055/20056/20057/20062` chelnerul
  vede textul Oracle brut.
- **Endpoint-ul n-are nicio autentificare.** `log_in` există, dar `create_order`,
  `cancel_order` și `pay_order` nu verifică nicio sesiune. Cine știe URL-ul poate
  închide comenzi ca achitate în restaurantul real.
- **`get_open_orders` n-are filtru de dată** (`state IN (1,2)`), deci o comandă veche
  rămasă deschisă ar bloca masa la nesfârșit. Momentan curat pe toate 3 fronturile
  (0 comenzi mai vechi de 2 zile) — **de reverificat în ziua mutării**.

---

## 7. Ce NU s-a putut verifica de aici

- **Nimic din partea SmartOne.** Canalele `127.0.0.1:8080` (fiscal) și `:8888`
  (card POS) n-au rulat niciodată pe un terminal real din acest proiect — nici
  sondele de disponibilitate, nici emiterea, nici tipărirea, nici plata cu cardul.
  S-a verificat doar payload-ul (test dedicat, 25 verificări) și UI-ul.
- **Cota legală de TVA pentru C** — răspuns de la client.
- **Dacă maparea din registru e actuală** — doar clientul știe (§6.1).
- **Dacă directorul de pe server e scriibil** și ce versiune de PHP rulează — se văd
  doar prin WinSCP / pe server.
- **Comportamentul formelor după instalare pe producție** — se validează abia la
  repornirea `UniacCLNT.exe`.
- **Fluxul complet pe producție**, evident.

---

## Anexă — prerechizite verificate pe cele 3 fronturi de producție

Toate îndeplinite, pe toate trei:

| verificare | rezultat |
|---|---|
| `CREATE TABLE / VIEW / TRIGGER / SYNONYM` | direct |
| `CREATE PROCEDURE` (pentru pachet) | **nu direct** — prin rolul `RESOURCE` |
| `UNLIMITED TABLESPACE` | da |
| `EXECUTE` pe `DBMS_LOCK` | da |
| set de caractere | `CL8MSWIN1251` — identic cu testul și cu ce folosește PHP-ul |
| `NLS_NUMERIC_CHARACTERS` | `.` — deci `p_amount` trimis ca șir se leagă corect |
| versiune | prod = 11g **XE** 11.2.0.2 / test = 11g EE 11.2.0.4 → zero risc de sintaxă 12c |
| spațiu (XE are limită de 11 GB) | 504 / 311 / 320 MB folosiți |
| secvența `COMENZ` | sincronă (`last_number` = `MAX(cod)`+1) |
| `check_summa_oplaty` | **FALSE** pe toate 3, ca pe test → validarea „nu ajung bani" e inactivă |
| atribute `envunirest` | 122, aceleași valori ca pe test |
| dependențele pachetului | toate prezente și `VALID` (`UNIREST_UTIL` cu `global_dep` **și** `vat_percent_by_letter`, `VMDB_COMENZ_RESTAURANT`, `VMDB_COMENZD`, `VMS_UNIVERS`, `VSLRPRM_CALCD_R_502`, `TMS_CASIR`, `TMDB_SOLD`, secvența `COMENZ`) |
| `MAX(nrdoc)` din `TMDB_SOLD` | 10 pe toate 3, stabil |
| comenzi vechi rămase deschise | 0 pe toate 3 |

**Dependență ascunsă:** `VSLRPRM_CALCD_R_502` filtrează pe
`sys_context('envunirest','kadr_doljn_r_502')`, setat de `TRG_ON_LOGON` (ENABLED pe
prod, valoare 10). Dacă trigger-ul nu rulează pentru sesiunea PHP pe vreun front,
lista de chelneri iese goală și **nimeni nu se poate loga**, fără niciun mesaj care
să explice de ce.

# Instalatorul UnaWaiter pentru un front

Instalează stratul Oracle al UnaWaiter pe baza unui restaurant, într-o singură
comandă, oprindu-se la prima eroare. Planul complet al mutării pe producție e în
[`../../docs/migrare-productie/README.md`](../../docs/migrare-productie/README.md).

```bat
install_front.bat 93.116.209.117 11
```

Verificare, oricând, fără să schimbe nimic:

```bat
verify_front.bat "unirest/unirest@93.116.209.117:1521/xe" 11
verify_front.bat "foishor_riscani_unirest/foishor_riscani_unirest@una.md:4024/clouddev.world" 11
```

---

## Stare: gata de rulat pe producție (2026-08-03)

Cele două lucruri care blocau instalarea sunt rezolvate:

**Pachetul compilează acum și pe producție.** `get_update_info` referea
`SUN.A$ADM` cu prefix de schemă hardcodat, iar schema `SUN` nu există pe
fronturi (`all_objects where owner='SUN'` → 0 pe toate trei) — deci corpul
pachetului n-ar fi compilat DELOC, nu doar auto-update-ul. Funcția a fost mutată
în PHP, care e oricum conectat la back-office. Pachetul n-are acum nicio
referință în afara schemei aplicației. `99_verify.sql` verifică și asta.

**Mesele pentru filiala 11 sunt stabilite.** `seed/seed_11.sql` conține 24 de
mese — **Sala 1–12, Terasa 18–29**, două blocuri continue. Recalculat pe
2026-08-07 **doar pe comenzile de după 1 iulie 2026**: restaurantul și-a
renumerotat mesele atunci, iar versiunea precedentă (35 de mese, Sala 1–15 /
Terasa 16–35) măsura o fereastră care amesteca vechea și noua numerotare, deci
conținea ~12 mese care nu mai există.

Mesele fără comenzi din interiorul blocurilor (18, 19, 25) sunt incluse ca să nu
existe salt în numerotare; golul 13–17 dintre blocuri e păstrat gol, fiindcă
13–16 au fost retrase de restaurant. Greșelile de tastare (121, 147, 222, 2088 —
câte o comandă fiecare) sunt lăsate afară.

Împărțirea pe zone e alegerea noastră: datele arată două blocuri distincte și că
18–29 e cel secundar (folosit la vârf), dar **nu** pot spune care e afară. Se
confirmă cu o întrebare pusă la instalare. Nu e definitivă — mesele se mută între
zone din forma „14. Amplasare mese", fără programator și fără APK nou.

---

## Ce conține

| Fișier | Ce face |
|---|---|
| `00_install_front.sql` | orchestratorul — rulează restul în ordinea corectă |
| `01_uw_zones.sql` | tabelul de zone + CHECK-urile (fără date) |
| `02_uw_tables.sql` | tabelul de mese (fără date) |
| `03_uw_waiters.sql` | cine are drept de logare, la ce restaurant |
| `04_uw_fiscal_receipts.sql` | bonurile fiscale — **cu coloana `RRN` inclusă** |
| `05_uw_fiscal_incidents.sql` | jurnalul de bonuri duble |
| `seed/seed_<NN>.sql` | zonele și mesele unui restaurant anume |
| `06_chei_straine.sql` | cheia străină mese→zone + indexul ei |
| `07_vuw_views.sql` | `VUW_WAITERS`, `VUW_ZONES`, `VUW_TABLES` |
| `08_pachet_spec.sql` | specificația `PG_MOBILE_WEB_WAITER` |
| `09_pachet_body.sql` | corpul pachetului |
| `99_verify.sql` | verifică totul; iese cu eroare dacă ceva lipsește |
| `install_front.bat` | conexiune + log + confirmare |
| `verify_front.bat` | doar verificarea, read-only |
| `upgrade_2026-08-07_can_edit_tables.sql` | **doar pentru baze deja instalate** — vezi mai jos |

### Upgrade-uri pentru baze deja instalate

Fișierele numerotate creează de la zero, deci nu se pot rula peste o bază unde
UnaWaiter e deja instalat. Pentru astea există fișiere `upgrade_<data>_<ce>.sql`,
idempotente (rulate de două ori nu strică nimic) și care recompilează singure ce
depinde de schimbare.

**`upgrade_2026-08-07_can_edit_tables.sql`** — coloana `uw_waiters.can_edit_tables`,
dreptul de a adăuga/scoate mese **din aplicație**. Rulat pe frontul de test
2026-08-07. Perechea lui din back-office e
`sql/backoffice/forme/upgrade_2026-08-07_can_edit_tables.sql`, și **ordinea contează**:
întâi frontul, apoi `vuw_all/00_install_vuw_all.sql`, apoi forma. Upgrade-ul de
formă verifică singur că frontul a fost făcut și se oprește cu mesaj clar dacă nu.

Stau în același folder cu `07_`/`08_`/`09_`, nu într-un subfolder, fiindcă le
cheamă cu `@@`. Dintr-un subfolder, `@@../07_…` a dat `SP2-0310` — iar `SP2-0310`
**nu** declanșează `WHENEVER SQLERROR`, deci scriptul mergea mai departe fără să
recompileze nimic (aceeași capcană ca la seed-ul lipsă din `00_install_front.sql`).

## De ce e împărțit așa

**Structura separată de date.** Fișierele numerotate sunt identice pe toate
fronturile; ce diferă de la un restaurant la altul stă în `seed/`. Amestecate,
scriptul ar trebui editat înainte de fiecare rulare — adică exact greșeala pe care
un instalator ar trebui s-o prevină.

**Seed-ul între tabele și cheia străină.** Cheia străină mese→zone se adaugă peste
rânduri deja inserate. Pusă înainte de seed, cade cu `ORA-02298`. De aceea ordinea
e: tabele → seed → chei străine → view-uri → pachet.

**`WHENEVER SQLERROR EXIT FAILURE`** e prima linie executabilă din orchestrator.
Fără ea, sqlplus trece peste o eroare și continuă, iar la final ai crede că s-a
instalat, deși lipsește o tabelă din mijloc.

**`SET SQLBLANKLINES ON`** — corpul pachetului conține linii goale în interiorul
blocurilor PL/SQL. Fără asta, sqlplus taie comanda la prima linie goală.

**`SHOW ERRORS` după pachet** — un pachet care nu compilează *nu* produce
`SQLERROR`. sqlplus zice doar „Warning: Package Body created with compilation
errors" și merge liniștit mai departe. `99_verify.sql` e cel care chiar oprește.

## Ce face `99_verify.sql`

Read-only, se poate rula pe orice bază, inclusiv pe una unde nu e instalat nimic —
atunci raportează frumos ce lipsește, în loc să crape. Verifică:

- cele 5 tabele, coloana `RRN`, cheia străină, indexul, cele 3 CHECK-uri;
- cele 3 view-uri și pachetul (spec + body), **și dacă sunt `VALID`**;
- dacă `get_update_info` referă `SUN.A$ADM` pe o bază unde schema `SUN` nu există;
- zonele și mesele filialei, plus dacă vreo masă a rămas fără zonă;
- toate dependențele din UAMenu (`UNIREST_UTIL` cu `global_dep` **și**
  `vat_percent_by_letter`, `VMDB_COMENZ_RESTAURANT`, `VSLRPRM_CALCD_R_502`,
  secvența `COMENZ`, `DBMS_LOCK`…);
- contextul `kadr_doljn_r_502` (pus de `TRG_ON_LOGON`) — fără el lista de chelneri
  iese goală și nimeni nu se poate loga;
- că există o tură deschisă în `TMDB_SOLD` — fără `NRDOC`, comenzile nu ajung în
  documentul din Back;
- **probă funcțională**, chemând efectiv `set_restaurant`, `get_tables`,
  `get_waiters` și `get_categories`.

Toate interogările pe tabelele noastre trec prin `EXECUTE IMMEDIATE`, intenționat:
pe o bază curată, un `SELECT ... FROM uw_zones` scris direct ar face blocul întreg
să nu compileze, și în loc de raport ai primi o singură eroare seacă.

### Rezultatele rulării de pe 2026-08-03

| bază | rezultat |
|---|---|
| TEST (`clouddev`) | totul OK, ieșire 0 |
| PRODUCȚIE filiala 11 | 17 verificări picate (tot ce e al nostru lipsește), **toate dependențele UAMenu OK**, ieșire 1 |

## Mici abateri față de ce e instalat pe test

Ambele deliberate, ambele inofensive:

- `uw_tables` primește `CHECK (active IN (0,1))` — `uw_zones` îl avea, `uw_tables` nu;
- `RRN` e în `CREATE TABLE`, nu într-un `ALTER TABLE` separat rulat ulterior.

## Un lucru important despre ce se poate valida pe test

Pe test, `VSLRPRM_CALCD_R_502` **nu e vederea reală** — e un înlocuitor scris de
mână care întoarce pur și simplu tot din `vms_univers`:

```sql
SELECT cod sc_munc, 1 DEP_SECTIA, 10 KADR_DOLJN_R_502
  FROM vms_univers WHERE tip='O' AND gr1 IN ('R','P','S') AND isarhiv IS NULL
```

Pe producție e vederea adevărată, peste modulul de personal, filtrată pe funcție.
De aceea `get_waiters` întoarce **743 de nume pe test** și **101 pe producție**.

Concluzia practică: comportamentul listei de chelneri **nu se poate valida pe
test**. Orice concluzie despre ea trebuie măsurată pe producție.

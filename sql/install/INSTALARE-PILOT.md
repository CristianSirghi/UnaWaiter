# UnaWaiter — instalare pilot pe producție (MIRON COSTIN)

Document de însoțire pentru cine rulează scripturile. Nu presupune cunoașterea
proiectului.

## Structura pachetului

```
INSTALARE-PILOT.md        ← documentul ăsta, citește-l primul
INSTALL-RU.md               același document în rusă (+ glosar de mesaje)
install/                  ← pasul 1: baza restaurantului
  install_front.bat         orchestratorul (rulează 00…99 în ordine)
  verify_front.bat          verificare, nu schimbă nimic
  98_dezinstalare.sql       curățare, dacă e nevoie de o a doua încercare
  seed/seed_11.sql          mesele și zonele filialei 11
backoffice/
  vuw_all/                ← pasul 2: view-urile și triggerele
  forme/                  ← pasul 3: cele două forme din Configurator
```

Fiecare folder are propriul `README.md` cu detalii tehnice. Comenzile de mai jos
se rulează **din folderul respectiv**.

---

## Ce instalează pachetul ăsta

UnaWaiter e o aplicație Android pentru chelneri: preiau comanda la masă, o trimit
la bucătărie și, opțional, o achită cu bon fiscal. Comenzile ajung în UAMenu ca
orice altă comandă — aplicația nu e un sistem paralel.

Scripturile adaugă în Oracle stratul de care are nevoie aplicația: cinci tabele
proprii, trei view-uri, un pachet PL/SQL pe baza restaurantului, plus câteva
view-uri și două forme în back-office.

## Domeniul acestei livrări

**Doar filiala 11 — MIRON COSTIN (Rîșcani), `93.116.209.117/xe`.**

Columna și Mircea cel Bătrîn **nu** pot fi instalate încă: ne lipsesc numerele
reale de mese și împărțirea lor pe zone (vezi ultima secțiune). Dacă instalarea e
pornită totuși pentru ele, se oprește singură cu `ORA-20092` și un mesaj care
explică ce lipsește — nu lasă o instalare pe jumătate.

## Ce garantăm

**Nu se modifică niciun obiect existent.** Toate obiectele noi au prefixul `UW_`
sau `VUW_`. Comenzile se scriu prin `VMDB_COMENZ_RESTAURANT`, exact calea folosită
de UAMenu, cu triggerele lui — nu direct în tabele. UAMenu funcționează în paralel,
neatins.

**Instalarea se oprește la prima eroare** (`WHENEVER SQLERROR EXIT FAILURE`) și
scrie un log complet în `log\install_<cod_univ>_<data>.log`.

**Există dezinstalare completă**, dacă e nevoie de o a doua încercare:

```bat
sqlplus unirest/unirest@93.116.209.117:1521/xe @98_dezinstalare.sql DA-STERG
```

Argumentul `DA-STERG` e obligatoriu, tocmai ca scriptul să nu poată fi rulat din
reflex. Șterge doar obiectele noastre; nu atinge comenzile, meniul, chelnerii din
`VMS_UNIVERS` sau tura din `TMDB_SOLD`.

## Înainte de a începe

Prerechizitele au fost verificate pe toate cele trei baze de producție (drepturi,
set de caractere `CL8MSWIN1251`, spațiu, `DBMS_LOCK`, pachetele UAMenu de care
depindem) — nu e nimic de pregătit.

Un singur lucru **recomandat**: refresh la dicționarele frontului (lista de
personal și meniul). Sunt materialized views cu refresh manual, iar la Miron Costin
ultimul e din 1 iulie. Un chelner angajat după acea dată nu apare în aplicație și
nu se poate loga, fără niciun mesaj care să explice de ce.

Fișierele `.bat` își setează singure `NLS_LANG` (`AMERICAN_AMERICA.AL32UTF8`). La
pașii rulați direct din `sqlplus` — 2 și 3, pe back-office — setați-l în consolă
înainte, altfel diacriticele și chirilicele din denumiri ies stricate.

## Pașii, în ordine

### 1. Baza restaurantului

```bat
install_front.bat 93.116.209.117 11
```

Rulează în ordine: tabele → seed (zone și mese) → chei străine → view-uri → pachet
→ verificare. Ordinea nu e arbitrară: cheia străină mese→zone se pune peste rânduri
deja inserate, deci trebuie să vină după seed.

Mesele instalate: **35 — Sala 1–15, Terasa 16–35**. Numerele vin din comenzile
reale ale restaurantului. Împărțirea pe zone nu e definitivă și **nu cere
programator**: se schimbă din forma „Amplasare mese" din back-office.

La final trebuie să scrie `REZULTAT: TOTUL E PE LOC`.

### 2. Back-office — view-urile și triggerele

```bat
sqlplus foishor/<parola>@una.md:4024/cloudbd.world @00_install_vuw_all.sql 11
```

Argumentul e lista filialelor instalate. La pilot: `11`. Când se adaugă Columna și
Mircea, aceeași comandă cu `11,13,17`.

> ⚠️ **Nu rula `01_views.sql` singur.** `CREATE OR REPLACE VIEW` șterge trigger-ul
> `INSTEAD OF`, iar fără el formele afișează datele dar orice salvare cade cu
> `ORA-01733` — un mesaj din care nu se deduce că lipsește un trigger. Scriptul
> `00_` le rulează pe amândouă în aceeași trecere; folosiți-l pe el.

> ⚠️ **Frontul trebuie să fie pornit** în momentul rulării. Oracle rezolvă db
> link-ul chiar la crearea view-ului, nu la interogare.

### 3. Back-office — formele

```bat
sqlplus foishor/<parola>@una.md:4024/cloudbd.world @install_forme.sql
```

Creează „Chelneri UnaWaiter" și „Amplasare mese". `obj_id`-urile se aleg automat
(`MAX+1`), deci nu pot intra în coliziune cu obiecte existente, iar dacă formele
există deja scriptul refuză cu `ORA-20080` în loc să suprascrie ceva.

**După instalare: repornire `UniacCLNT.exe` și deschiderea fiecărei forme** —
prima deschidere generează coloanele grilei.

### 4. Partea de aplicație și server

PHP-ul și APK-ul le facem noi. Nu sunt în pachetul ăsta.

## Verificare, oricând

Nu schimbă nimic, se poate rula de câte ori e nevoie:

```bat
verify_front.bat "unirest/unirest@93.116.209.117:1521/xe" 11
```

Verifică tabelele, indexul pe zone, validitatea pachetului, accesul la `DBMS_LOCK`,
și chiar cheamă funcțiile aplicației ca să confirme că întorc mese și meniu.

## Dacă ceva pică

Trimiteți-ne fișierul din `log\`. Conține totul: comanda, eroarea și pasul la care
s-a oprit. Erorile noastre au coduri proprii cu mesaj explicit — `ORA-20090`
(verificare picată), `ORA-20092` (lipsește seed-ul filialei), `ORA-20080` (formele
există deja).

## Ce ne trebuie de la voi pentru Columna și Mircea cel Bătrîn

Pentru fiecare din cele două restaurante:

1. **Numerele reale de mese.** Din comenzi se văd niște tipare, dar sunt
   presupuneri, nu certitudini: la Columna numerotarea pare pe grupe (`11–16`,
   `21–26`, `31–35`), la Mircea `1–24`. Apar și numere folosite o singură dată
   (`121`, `222`, `2088`), care arată a greșeli de tastare — dar confirmați voi.
2. **Împărțirea pe zone** (sală, terasă, etaj…). Baza nu știe ce masă e afară:
   `DESK` e un număr brut, fără dicționar în UAMenu. Grupele de la Columna
   sugerează **3 zone**, nu 2 — de confirmat.
3. **La Mircea, masa `0`** apare în 15 comenzi. Dacă e o masă reală, spuneți-ne:
   momentan nu poate fi folosită din aplicație.

Cu datele astea scriem fișierul de seed al fiecărei filiale (după modelul
`seed/seed_11.sql`) și instalarea decurge identic.

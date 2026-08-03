# Formele UnaWaiter din back-office

Două forme în Configurator, prin care managerul administrează chelnerii și
amplasarea meselor, pentru toate restaurantele, dintr-un singur ecran:

| formă | `SECTION` | ce face |
|---|---|---|
| 13. Chelneri UnaWaiter | `F_UWWAITERT` | locația → chelnerii ei (alocare + PIN) |
| 14. Amplasare mese | `F_UWPLAN` | locația → zonele ei → mesele zonei |

Câștigul real: `cod_univ` și codul zonei **nu se mai tastează** — se moștenesc din
rândul selectat mai sus. Erau singurele câmpuri unde o greșeală muta mese sau
chelneri la alt restaurant.

## Instalare

```bash
sqlplus foishor/<parola>@una.md:4024/cloudbd.world @install_forme.sql
```

**Înainte:** `../backoffice_uw_all.sql` — formele citesc din `VUW_WAITERS_ALL`,
`VUW_ZONES_ALL`, `VUW_TABLES_ALL` și `VUW_LOCATIONS`.

**După:**
1. repornește `UniacCLNT.exe`;
2. deschide fiecare formă și **închide-o o dată** — prima deschidere generează
   coloanele grilelor (capcana #4 din [`../../../docs/back-office/forme.md`](../../../docs/back-office/forme.md));
3. rulează `../backoffice_fix_grid_cols.sql` pentru titlurile coloanelor.

## De ce fișierul ăsta și nu scripturile vechi

`backoffice_forma_chelneri.sql` și `backoffice_forma_unificata.sql` (rămase în
directorul părinte, ca istoric) au fost scrise pentru test, cu `obj_id`
**hardcodate**. Pe producție aceleași numere sunt alte obiecte, reale — verificat
2026-08-03 pe `foishor@cloudbd`:

| obj_id | pe test (al nostru) | pe PRODUCȚIE |
|---|---|---|
| 1991 | secțiunea `WEB_WAITER` | SALARIU TARIFAR (tabel de pontaj) |
| 1996 | „13. Chelneri UnaWaiter" | acțiune „Перезаполнить дни/часы из табеля" |
| 1997 | formă ștearsă | `TOTAL:900` |
| 1998 | formă ștearsă | raport `DG1P26 49-Reports` |
| 1999 | „14. Amplasare mese" | acțiune „Заполннение данных" |

Șabloanele 1867/1868 nu există deloc acolo, iar nodul-părinte 1854 e altceva.
**`backoffice_forma_chelneri.sql` face `update a$adp` și `delete from a$lob`
direct pe 1996, fără nicio verificare** — rulat pe producție, ar fi corupt un
obiect de salarizare.

Aici nu mai există niciun `obj_id` scris de mână:

- **părintele** se caută după `SECTION = 'CLASSIF'` („10. Справочники") — pe test
  e 1854, pe producție 1876, iar scriptul nu trebuie să știe;
- **`obj_id`-urile noi** se iau ca `MAX(obj_id)+1` și `+2`, deci coliziunea e
  imposibilă prin construcție;
- dacă formele există deja (căutate după `SECTION`), scriptul **refuză** cu
  `ORA-20080` în loc să suprascrie ceva.

## De ce definițiile sunt extrase, nu clonate

`install_forme.sql` conține toate cele 110 proprietăți (46 + 64) ca apeluri
explicite, extrase din baza de test unde formele sunt validate. Alternativa —
clonarea unui șablon la instalare — depinde de faptul că șablonul e identic în
ambele medii. Nu e o presupunere care merită făcută: o proprietate lipsă face
grila **read-only fără niciun mesaj**, exact ce s-a întâmplat cu `EDITQUERY1/2/3`
pe 2026-07-30.

Regenerare, dacă formele se modifică pe test: `genereaza_forme.sql`.

## Ce s-a verificat (2026-08-03)

- **Probă completă pe test, cu `rollback`**: cele 2 rânduri din `A$ADM` și toate
  cele 110 din `A$ADP` se inserează fără nicio eroare; numărătorile înainte/după
  identice (`a$adm=1737`, `a$adp=32444`), zero urme rămase.
- **Garda funcționează**: rulat pe test, unde formele există, refuză cu
  `ORA-20080` și nu atinge nimic.
- **`A$ADM.SECTION` e UNIQUE** (`A$ADM$UQ`) — deci și dacă cineva ocolește garda,
  baza însăși respinge o a doua instalare cu `ORA-00001`. Descoperit tocmai
  fiindcă proba a fost rulată cu garda dezactivată.
- Producția are aceeași structură ca testul, decalată: `CLASSIF` 1854 → **1876**,
  `F_BARCODES` 1867 → **1889**, `F_CLIENTT` 1868 → **1890**. `MAX(obj_id)` = 2135,
  deci formele vor primi 2136 și 2137.

## Ce NU s-a putut verifica de aici

Cum arată formele **după instalare pe producție** — se vede abia la repornirea
`UniacCLNT.exe` și la prima deschidere a fiecărei forme.

# Back-office UNA.md — cum funcționează, de fapt

Documentul ăsta descrie sistemul în care trăiește UnaWaiter: unde stau datele,
cine le replică unde, și cum se leagă restaurantele între ele. **Nu e specific
Foișorului** — platforma (UNA.md / UN4, produs Unisim) e aceeași la majoritatea
clienților, doar schemele diferă.

Aflat empiric pe 2026-07-29, prin explorarea bazelor de test și producție. Fiecare
afirmație de aici a fost verificată cu o interogare, nu presupusă.

---

## Cele două straturi

```
        BACK-OFFICE  (contabilitate, dicționare, forme)
        ├── PRODUCȚIE:  schema FOISHOR  pe  cloudbd  (una.md:4024)
        └── TEST:       schema SUN      pe  clouddev (una.md:4024)
                    │
                    │  replicare prin MATERIALIZED VIEW (manuală!)
                    ▼
   ┌────────────────┼────────────────┐
   ▼                ▼                ▼
 FRONT              FRONT            FRONT          ← câte o bază per restaurant
 Miron Costin       Columna          M. cel Bătrîn
 93.116.209.117     185.247.159.33   95.65.21.122
 user/parolă: unirest/unirest, serviciu xe
```

`cloudbd` e **multi-client**: zeci de firme, fiecare cu schema ei
(FOISHOR, FARMACO, SINFORM, AUROMEX…), fiecare cu propriul `TMS_UNIVERS`,
propriile forme și propriul registru. O schemă nu vede datele alteia.

**Fronturile** sunt bazele locale ale restaurantelor, cu care vorbește POS-ul
UAMenu. Acolo stau comenzile (`TMDB_COMENZ`), și tot acolo scrie și UnaWaiter.

---

## Registrul de restaurante

Tabela **`YBMB_DIF_CASSA`** din back-office spune ce restaurante există și cum se
ajunge la ele. Rezolvată în cod prin
`YBMB_PK_DIF_CASSA.get_db_link_by_nr_group()` / `get_shema_by_nr_group()`.

| coloană | ce e |
|---|---|
| `COD_UNIV` | codul filialei — cheia de restaurant în tot sistemul |
| `DB_LINK` | link-ul spre frontul ei |
| `SHEMA` | schema de pe front |
| `SECONDARY` | 0 = baza principală (`unirest`), 1 = personal |
| `OFF_LINE`, `SERVER_ID`, `MULTI_DEP` | stări/marcaje |

Denumirea filialei se ia din `TMS_UNIVERS` cu `GR1='FL'`:

```
11 MIRON COSTIN      13 COLUMNA        17 MIRCEA cel BATRIN
12 MEGAPOLIS MALL    16 ALECO RUSSO    ← în registru, dar FĂRĂ db link
```

### Cum se conectează un serviciu extern (ex. PHP-ul nostru)

O singură conexiune scrisă manual — cea la back-office — restul se deduce:

```sql
select d.cod_univ, u.denumirea, l.username, l.host
  from ybmb_dif_cassa d
  left join tms_univers u on u.cod = d.cod_univ
  join all_db_links l on upper(l.db_link) = upper(d.db_link)
 where d.secondary = 0 and l.host is not null
```

- **`user` = `parolă`** pe fronturi — convenția UAMenu (`unirest/unirest`).
  Back-office-ul NU o respectă, de aia rămâne scris manual.
- ⚠️ Ia **`l.username` din link**, nu `d.shema`: pe test diferă.
- ⚠️ `ALL_DB_LINKS` **nu expune parola** (și `SYS.LINK$` e inaccesibil) — de aia
  te bazezi pe convenția user=parolă.
- ⚠️ `host` e uneori alias TNS (`clouddev`), nu `adresă/serviciu` — trebuie tradus
  sau restaurantul se sare.

---

## Replicarea dicționarelor — și de ce întârzie

Fronturile nu au dicționare proprii. Le primesc din back-office prin
**materialized views**:

```sql
-- MVMS_UNIVERS pe front:
select ... from FOISHOR.tms_univers@FOISHOR.WORLD where ...
```

Peste MV stă un view local (`VMS_UNIVERS`), pe care-l citește toată lumea.
De aia **nu se poate insera un chelner direct pe front** — `ORA-01732`.

> ⚠️ **Refresh-ul e MANUAL.** Se face din back-office, `Forme → 08. Товары →
> 03. Обновить справочники на кассах`, care cheamă
> `vvs_cassa_util.refresh_mviews(p_shop_id)`.
>
> Măsurat pe 2026-07-29: Miron Costin **01.07**, Columna **20.07**,
> M. cel Bătrîn **08.06**. Un chelner angajat azi nu apare în POS până nu apasă
> cineva butonul. E o problemă de operare, nu de cod.

Un chelner nou apare astfel: ordin de angajare în back-office → rând în
`TSLRPRM_CALCD` cu funcția de chelner (cod **10**) → `TMS_UNIVERS` cu `tip='O'`,
`gr1='R'` → **refresh** → abia acum e vizibil la restaurant.

---

## Identitatea filialei pe o comandă

`TMDB_COMENZ.NRSET` e scris de triggerul `TRG_ONCOMENZ`:

```sql
:new.nrset := Scx('GlobalDep');     -- Scx(p) = sys_context('envunirest', p)
```

Contextul se pune la login-ul clientului UAMenu (`UN$CANTINA`):

```sql
select div_id into v_div from vms_pos_by_div where pos_number = <CassaDatecsNrLogic din cantina.ini>;
Envunirest.set_env_unirest('GlobalDep', v_div);
```

…sau direct, dacă `GlobalDep` e scris în `cantina.ini` (`ucLogin.cpp`).

**Într-o sesiune nouă** (cum e cea a unui backend) valoarea vine din
`TMS_INIT_PARAMS`. Pentru a o seta explicit:

```sql
begin unirest_util.global_dep(<cod_univ>); end;
```

Asta setează și lista de prețuri și grupele de produse ale filialei, deci e
apelul corect, nu un `set_context` de mână.

> ⚠️ **Constatare, 2026-07-29:** `TMS_INIT_PARAMS` e copiat identic pe toate cele
> 3 producții (`GlobalDep=13`, `ServerID=131`), iar comenzile reale ies toate cu
> `NRSET=16`, fiindcă terminalele rulează cu `pos_number=161`. Practic nicio
> comandă din sistem nu poartă filiala ei reală. Orice serviciu care scrie comenzi
> ar trebui să-și seteze filiala explicit, nu s-o moștenească.

---

## Setul de caractere: fără diacritice românești

`NLS_CHARACTERSET` e **`CL8MSWIN1251`** (cirilic Windows-1251) — verificat pe
2026-07-30. Pagina asta de cod **nu conține** `ă`, `â`, `î`, `ș`, `ț`.

Un `INSERT` cu diacritice nu dă eroare: se salvează **tăcut** fără ele.

```sql
-- scris:  'Terasă'
select dump(name_ro,16) from uw_zones where zone_code='terrace';
--> Len=6: 54,65,72,61,73,61   ("Terasa")
```

Așa e toată baza, nu doar datele noastre: produsele sunt `Blinie cu brinza`,
`smintina`, iar filiala 17 e `MIRCEA cel BATRIN`. Deci **scrie fără diacritice
de la bun început** — altfel textul din cod nu va corespunde cu ce e în bază, iar
căutările după el nu vor găsi nimic.

Rusa merge perfect (chirilica *este* conținutul paginii de cod).
`NLS_NCHAR_CHARACTERSET` e `AL16UTF16`, deci `NVARCHAR2` ar suporta diacriticele —
dar atunci coloana aia ar arăta altfel decât tot restul sistemului.

⚠️ Setează `NLS_LANG=AMERICAN_AMERICA.AL32UTF8` în client, altfel chirilica se
citește ca mojibake.

---

## Ce e unde — tabel de orientare

| vrei să… | te uiți în |
|---|---|
| ce restaurante există și cum ajungi la ele | `YBMB_DIF_CASSA` (back) |
| denumirea unei filiale | `TMS_UNIVERS` / `VMS_UNIVERS`, `GR1='FL'` |
| chelneri și alte persoane | `VMS_UNIVERS`, `tip='O'`, `gr1='R'` |
| cine e angajat acum, pe ce funcție | `VSLRPRM_CALCD` / `_R_502` (funcția 10 = chelner) |
| comenzi | `TMDB_COMENZ` + `TMDB_COMENZD` (pe front) |
| meniu și prețuri | `VMS_BLIUDA`, `VTPR1D_PERPRLIST` |
| tipuri de plată | `VMS_SYSS` cu `cod=105 AND tip='T'` |
| definițiile formelor din back | `A$ADM` / `A$ADP` — vezi [`forme.md`](forme.md) |

---

## Legături

- [`forme.md`](forme.md) — cum se creează o formă nouă în back-office
- [`../auto-update/README.md`](../auto-update/README.md) — folosește `A$ADM` pentru setări

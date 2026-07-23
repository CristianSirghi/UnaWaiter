# Deploy auto-update pe PRODUCȚIE — checklist

Pe TEST totul e deja configurat (vezi [`README.md`](README.md)). Acest document e
pașii de replicat pe **producție**. Producția e o bază de date fizic separată
(`Foishor_Productie`, on-premise la restaurant), NU `clouddev`.

> ⚠️ **Nu am (Claude) acces la producție** — nu am credențialele pentru
> `Foishor_Productie`. Pașii SQL de mai jos trebuie rulați de o persoană cu acces la
> schemele de producție.

---

## Ce e diferit TEST → PRODUCȚIE

| Element | TEST | PRODUCȚIE |
|---|---|---|
| Baza de date | `clouddev.world` @ `una.md:4024` | `Foishor_Productie` (on-premise, la restaurant) — **de confirmat** connect string |
| Schema de configurare (ține `A$ADM`) | `SUN` | **de confirmat** (schema Configurator-ului de producție) |
| Schema aplicației (ține pachetul) | `FOISHOR_RISCANI_UNIREST` | **de confirmat** (ex. `UNIREST` pe front-ul real — vezi nota de mai jos) |
| Backend PHP | `Desktop\foishor_test\backend\` | locația de producție a `oracle_waiter.php` |
| URL `version.json` + APK | `http://una.md:3323/f/c/una_waiter/...` | poate rămâne același sau altul — se pune în Configurator |

> **Notă despre schema front-ului real:** front-ul de producție Foișor/Rîșcani
> conectează ca `UNIREST` (host `93.116.209.117`, db-link `RISCANI.WORLD` din
> back-office-ul `cloudbd`). Numele exact al schemei aplicației pe producție trebuie
> confirmat înainte de deploy — de asta e marcat "de confirmat" peste tot mai jos.

---

## ⚠️ CAPCANA #1 — referința de schemă hardcodată în pachet

În funcția `pg_mobile_web_waiter.get_update_info`, tabelele de configurare sunt
referite cu **prefix de schemă explicit**:

```sql
SELECT P.VALUE INTO v_url
  FROM SUN.A$ADM A, SUN.A$ADP$V P    -- <── "SUN." e valabil DOAR pe TEST
 WHERE ...
```

Pe producție, schema de configurare **NU se numește `SUN`**. La deploy trebuie
înlocuit `SUN.` cu numele schemei de configurare de producție (sau, mai curat,
creat un synonym — vezi opțiunea B mai jos).

- **Opțiunea A (rapidă):** editezi body-ul pachetului pe producție și înlocuiești
  ambele `SUN.` cu `<SCHEMA_CONFIG_PROD>.` înainte de compilare.
- **Opțiunea B (mai curată, recomandată pentru viitor):** creezi două synonym-uri în
  schema aplicației și lași pachetul să refere `A$ADM` / `A$ADP$V` fără prefix:
  ```sql
  -- rulat în schema APLICAȚIEI, pe producție:
  CREATE OR REPLACE SYNONYM A$ADM   FOR <SCHEMA_CONFIG_PROD>.A$ADM;
  CREATE OR REPLACE SYNONYM A$ADP$V FOR <SCHEMA_CONFIG_PROD>.A$ADP$V;
  ```
  Apoi în pachet folosești doar `A$ADM` / `A$ADP$V` (fără `SUN.`). Avantaj: același
  cod de pachet merge pe orice mediu, doar synonym-ul diferă.

---

## Pasul 1 — Configurator: secțiunea `WEB_WAITER` + cheia `AUTOUPDATE_LINK`

Deschide Configurator-ul conectat la **schema de configurare de producție**. Adaugă,
în "System settings", o secțiune nouă și o proprietate în ea:

- Secțiune nouă: **`WEB_WAITER`**
- Proprietate: **Name** `AUTOUPDATE_LINK`, **Type** `String`, **Value** = URL-ul de
  producție către `version.json` (ex. `http://una.md:3323/f/c/una_waiter/version.json`).

Se poate face **manual din UI-ul Configurator** (recomandat pe producție), sau prin
SQL echivalent celui rulat pe test:

```sql
-- rulat ca SCHEMA DE CONFIGURARE, pe producție
DECLARE
  v_obj_id A$ADM.OBJ_ID%TYPE;
BEGIN
  INSERT INTO A$ADM (OBJ_TYPE, OBJ_SUBTYPE, PARENT_ID, NAME0, SECTION)
  VALUES (6, 0, 1, 'WEB_WAITER', 'WEB_WAITER')       -- OBJ_ID se ia din secvența A$ADM$SQ
  RETURNING OBJ_ID INTO v_obj_id;

  INSERT INTO A$ADP$V (OBJ_ID, NAME, GR, VTYPE, VALUE)
  VALUES (v_obj_id, 'AUTOUPDATE_LINK', 'Общая', 'S',
          'http://una.md:3323/f/c/una_waiter/version.json');
  COMMIT;
END;
/
```

**Cum funcționează** (verificat pe test, prin trigger-ele `A$ADM$TR` / `A$ADP$V$TR`):
- `A$ADM` cu `OBJ_TYPE=6, OBJ_SUBTYPE=0, PARENT_ID=1` = o secțiune nouă în "System
  settings". `OBJ_ID` se generează singur din secvența `A$ADM$SQ`.
- La `INSERT` în view-ul `A$ADP$V`, trigger-ul de bază derivă automat `KEY := UPPER(NAME)`,
  `GR` implicit, `VTYPE` implicit `'S'` (String). E suficient `NAME` + `VALUE`.

Verificare:
```sql
SELECT SECTION, KEY, TYPENAME, VALUE FROM A$ADP$V WHERE SECTION='WEB_WAITER';
-- aștept: WEB_WAITER | AUTOUPDATE_LINK | String | http://.../version.json
```

## Pasul 2 — GRANT read-only către schema aplicației

```sql
-- rulat ca SCHEMA DE CONFIGURARE, pe producție
GRANT SELECT ON A$ADM   TO <SCHEMA_APLICATIE_PROD>;
GRANT SELECT ON A$ADP$V TO <SCHEMA_APLICATIE_PROD>;
```

(Dacă mergi pe Opțiunea B cu synonym, tot ai nevoie de aceste grant-uri.)

## Pasul 3 — Funcția `get_update_info` în pachetul aplicației

În schema aplicației de producție, pachetul `PG_MOBILE_WEB_WAITER` trebuie să conțină
funcția `get_update_info`. Adaugă în **spec**:

```sql
FUNCTION get_update_info RETURN VARCHAR2;
```

Și în **body** (atenție la CAPCANA #1 — prefixul de schemă):

```sql
FUNCTION get_update_info RETURN VARCHAR2 IS
  v_url VARCHAR2(500);
BEGIN
  SELECT P.VALUE INTO v_url
    FROM <SCHEMA_CONFIG_PROD>.A$ADM A, <SCHEMA_CONFIG_PROD>.A$ADP$V P
   WHERE P.OBJ_ID = A.OBJ_ID
     AND A.SECTION = 'WEB_WAITER'
     AND P.KEY = 'AUTOUPDATE_LINK';

  RETURN '{"url":"' || REPLACE(v_url, '"', '\"') || '"}';
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RETURN '{"url":""}';
END get_update_info;
```

(Cu Opțiunea B / synonym: scoți `<SCHEMA_CONFIG_PROD>.` și lași doar `A$ADM` / `A$ADP$V`.)

Verificare — pachetul trebuie să rămână `VALID` și funcția să întoarcă URL-ul:
```sql
SELECT object_type, status FROM user_objects WHERE object_name='PG_MOBILE_WEB_WAITER';
-- aștept: PACKAGE VALID, PACKAGE BODY VALID

SELECT pg_mobile_web_waiter.get_update_info FROM dual;
-- aștept: {"url":"http://.../version.json"}
```

## Pasul 4 — Backend PHP de producție

În `oracle_waiter.php` de producție (versiunea aceea specifică deployment-ului),
verifică/adaugă:

Case în switch:
```php
case 'get_update_info':
    $result = callGetUpdateInfo();
    break;
```

Funcția:
```php
function callGetUpdateInfo() {
    global $olink;
    return callScalarJsonFunction(
        $olink,
        "BEGIN :result := pg_mobile_web_waiter.get_update_info; END;",
        array()
    );
}
```

(`callScalarJsonFunction` există deja — e folosit și de `logIn()`.)

## Pasul 5 — Hosting: `version.json` + APK

Urcă pe serverul web, la URL-ul pe care l-ai pus în `AUTOUPDATE_LINK` (Pasul 1):
- `version.json` — cu `version` = versiunea nouă, `url` = link direct către APK.
- APK-ul de producție propriu-zis (build release).

Vezi [`RELEASE-VERSIUNE-NOUA.md`](RELEASE-VERSIUNE-NOUA.md) pentru fluxul recurent.

## Pasul 6 — Clientul (APK-ul de producție)

Aplicația nu are nimic hardcodat specific test/producție pentru update — URL-ul vine
din backend. Singurul lucru: câmpul **"Server"** din Administrare trebuie să pointeze
la backend-ul PHP de producție (ca orice altă comandă). Restul (adresa `version.json`)
vine automat prin `get_update_info`.

---

## Verificare finală end-to-end (pe producție)

1. Deschizi aplicația → Setări → Actualizări → "Check for updates".
2. Dacă `version.json` are o `version` mai mare decât cea instalată → apare dialogul
   "New version available".
3. "Download" → descarcă APK-ul → Android cere confirmarea instalării.

Dacă la pasul 1 primești eroare de rețea: verifică pe rând — backend-ul răspunde la
`?cmd=get_update_info`? funcția Oracle întoarce URL corect? `version.json` e accesibil
de pe telefon la acel URL?

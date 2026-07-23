# Auto-update UnaWaiter — prezentare generală

Aplicația nu trece prin Google Play. Ca să nu reinstalăm manual APK-ul pe fiecare
telefon de chelner la fiecare bugfix, aplicația verifică singură dacă există o
versiune mai nouă pe server și o descarcă + instalează la cerere.

Modelul e copiat 1:1 din **MMOffline** (`D:\MMOffline`), unde acest mecanism
rulează deja în producție. Vezi acolo `Networking/UpdateManager.*` și
`android/src/com/unaorders/app/UpdateHelper.java` pentru originalul.

> ⚠️ **Tot ce e descris aici e configurat momentan pe TEST.** Pentru replicarea pe
> producție vezi [`DEPLOY-PRODUCTIE.md`](DEPLOY-PRODUCTIE.md). Pentru publicarea unei
> versiuni noi (după ce infrastructura există), vezi
> [`RELEASE-VERSIUNE-NOUA.md`](RELEASE-VERSIUNE-NOUA.md).

---

## Lanțul complet (cine pe cine cheamă)

```
UpdatePage.qml  (Setări → Actualizări)
   │  butonul "Check for updates"
   ▼
dataService.loadUpdateInfo()            [C++: src/core/dataservice.cpp]
   │  GET  ?cmd=get_update_info
   ▼
oracle_waiter.php  → callGetUpdateInfo()  [PHP backend]
   │  BEGIN :result := pg_mobile_web_waiter.get_update_info; END;
   ▼
pg_mobile_web_waiter.get_update_info    [Oracle, schema APP]
   │  SELECT ... FROM <SCHEMA_CONFIG>.A$ADM / A$ADP$V
   │  WHERE SECTION='WEB_WAITER' AND KEY='AUTOUPDATE_LINK'
   ▼
întoarce { "url": "http://.../version.json" }
   │
   ▼
appUpdateManager.checkForUpdate(url)    [C++: src/core/updatemanager.cpp]
   │  GET version.json → { version, url(apk), notes }
   │  compară `version` cu versiunea instalată (numeric, pe segmente)
   ▼
dacă e mai nouă → dialog "New version available"
   │  utilizatorul apasă "Download"
   ▼
appUpdateManager.downloadAndInstall()
   │  (doar Android) JNI → UpdateHelper.startUpdate(...)
   ▼
UpdateHelper.java  → Android DownloadManager descarcă APK-ul
   │  la final lansează automat ecranul de instalare Android
   ▼
utilizatorul confirmă instalarea
```

**De ce în doi pași** (întâi URL-ul din backend, apoi `version.json`)? Pentru că
`appUpdateManager` (C++) nu vorbește direct cu backend-ul nostru PHP — la fel ca
orice altă cerere, URL-ul de verificare vine prin `dataService`. Așa, linkul către
`version.json` e configurabil per-client din Configurator, fără să rebuilduim
aplicația.

---

## Piesele și unde trăiește fiecare

### 1. Client (Qt/C++/QML) — repo `D:\UnaWaiter`

| Fișier | Rol |
|---|---|
| `src/core/appversion.h` | **Sursa unică a versiunii** (`const char VERSION[]`). `UnaWaiter.pro` o citește ca să completeze `versionName`/`versionCode` în manifest. Se bumpuiește DOAR aici. |
| `src/core/updatemanager.h` / `.cpp` | `UpdateManager` — descarcă `version.json`, compară versiuni, pornește download+install pe Android. Portat din MMOffline. |
| `android/src/org/qtproject/UnaWaiter/UpdateHelper.java` | Cod nativ Android: descarcă APK-ul prin `DownloadManager`, lansează instalarea. |
| `android/AndroidManifest.xml` | Permisiunea `REQUEST_INSTALL_PACKAGES` + placeholder-ele `%%INSERT_VERSION_NAME%%` / `%%INSERT_VERSION_CODE%%` (completate de qmake). |
| `UnaWaiter.pro` | `QT += androidextras` (în scope-ul `android {}`) + parsarea versiunii din `appversion.h` + `UpdateHelper.java` în `DISTFILES`. |
| `src/core/dataservice.h` / `.cpp` | Comanda `loadUpdateInfo()` → `get_update_info`; helper nou `getObject()`; proprietatea `updateInfoUrl`. |
| `src/main.cpp` | Expune `appUpdateManager` în QML. |
| `qml/pages/UpdatePage.qml` | Pagina "Actualizări" (versiune instalată, buton verificare, progres, dialoguri). |
| `qml/pages/SettingsPage.qml` | Rândul "Updates" care deschide pagina (semnalul `updateRequested`). |
| `qml/main.qml` | `updatePageComponent` + push din `settingsPageComponent`. |
| `resources/qml.qrc` | Înregistrarea `UpdatePage.qml` (+ bump `build rev` ca rcc-ul să nu rămână vechi). |

### 2. Backend (PHP) — NU e în repo

Fișier: `oracle_waiter.php` (pe TEST: `C:\Users\user\Desktop\foishor_test\backend\oracle_waiter.php`).

- `case 'get_update_info':` în switch → `callGetUpdateInfo()`
- `callGetUpdateInfo()` apelează `pg_mobile_web_waiter.get_update_info` prin
  `callScalarJsonFunction` (același tipar ca `logIn()`).

### 3. Oracle — NU e în repo

- **Funcția** `pg_mobile_web_waiter.get_update_info` (spec + body) — adăugată aditiv
  în pachetul existent, restul funcțiilor neatinse. Citește setarea din schema de
  configurare prin `A$ADM` / `A$ADP$V`.
- **GRANT-ul** `SELECT` pe `A$ADM` și `A$ADP$V`, de la schema de configurare către
  schema aplicației (citire cross-schema).

### 4. Configurator (setarea) — NU e în repo

- Secțiunea **`WEB_WAITER`** în "System settings", cheia **`AUTOUPDATE_LINK`** (tip
  String) = URL-ul către `version.json`. Stocată în `A$ADM` / `A$ADP$V` ale schemei
  de configurare.

### 5. Hosting (server web) — NU e în repo

- `version.json` — fișier JSON: `{ "version": "...", "url": "...apk", "notes": "..." }`
- Fișierul APK propriu-zis.

---

## Formatul `version.json`

```json
{
  "version": "0.2",
  "url": "http://una.md:3323/f/c/una_waiter/unawaiter.apk",
  "notes": "Descriere scurtă a modificărilor."
}
```

- `version` — comparat **numeric pe segmente** cu versiunea instalată (`1.10 > 1.9`,
  nu lexicografic). Dacă e mai mare → se oferă update.
- `url` — link direct către APK-ul de descărcat.
- `notes` — text afișat în dialogul de confirmare (poate fi gol).

---

## Ce e configurat pe TEST (referință)

| Element | Valoare pe TEST |
|---|---|
| Bază de date | `clouddev.world` @ `una.md:4024` |
| Schema de **configurare** (ține `A$ADM`) | `SUN` (login `sun`/`sun`) |
| Schema **aplicației** (ține pachetul + comenzile) | `FOISHOR_RISCANI_UNIREST` |
| Secțiune / cheie Configurator | `WEB_WAITER` / `AUTOUPDATE_LINK` |
| `A$ADM.OBJ_ID` al secțiunii `WEB_WAITER` | `1991` (generat de secvența `A$ADM$SQ`) |
| Valoarea `AUTOUPDATE_LINK` | `http://una.md:3323/f/c/una_waiter/version.json` |
| Backend PHP | `Desktop\foishor_test\backend\oracle_waiter.php` |
| Versiune instalată curentă (`appversion.h`) | `0.1` |

> Pe **producție** toate acestea diferă (altă bază de date fizică — `Foishor_Productie`,
> pe teren, la restaurant — alte scheme, altă locație PHP). Vezi
> [`DEPLOY-PRODUCTIE.md`](DEPLOY-PRODUCTIE.md).

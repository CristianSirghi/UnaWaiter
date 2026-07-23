# Publicarea unei versiuni noi

După ce infrastructura de auto-update există (vezi [`DEPLOY-PRODUCTIE.md`](DEPLOY-PRODUCTIE.md)),
publicarea unei versiuni noi e un flux scurt și repetabil. Nu mai umbli prin telefoane —
urci APK-ul + `version.json`, iar aplicațiile se actualizează singure la următoarea
verificare.

---

## Pașii

### 1. Bumpuiește versiunea — DOAR într-un loc

Editează `src/core/appversion.h`:

```cpp
const char VERSION[] = "0.2";   // <── crește față de versiunea publicată anterior
```

- `UnaWaiter.pro` citește această linie și completează automat `versionName` /
  `versionCode` în `AndroidManifest.xml` la build. **Nu edita manual manifestul.**
- `versionCode` se derivă scoțând ne-cifrele din versiune (ex. `0.2` → `02` → `2`).
  De aceea versiunile trebuie să crească monoton (`0.2`, `0.3`, ... `1.0`, `1.1`).

> ⚠️ După editarea `appversion.h`, în Qt Creator rulează **Run qmake** înainte de
> build (versiunea se citește la faza qmake, nu la compilare).

### 2. Build APK release în Qt Creator

- Kit Android (`Android_Qt_5_15_2_Clang_Multi_Abi`).
- Build în modul **Release**.
- APK-ul rezultă în `...\android-build\build\outputs\apk\...`.

> Dacă ai schimbat doar `.qml` (nu `.pro`/`.qrc`), amintește-ți gotcha-ul cunoscut:
> uneori rcc-ul NU se regenerează → bumpuiește `<!-- build rev N -->` în
> `resources/qml.qrc` sau fă Rebuild, ca telefonul să nu ruleze QML vechi.

### 3. Redenumește / pregătește APK-ul

Numele fișierului APK trebuie să corespundă cu `url`-ul din `version.json`. Convenție:
`unawaiter.apk` sau `unawaiter_<versiune>.apk` (dacă vrei istoric al versiunilor pe server).

### 4. Urcă pe server

La locația din `AUTOUPDATE_LINK` (Configurator):
- **APK-ul** — la URL-ul care va fi în câmpul `url` din `version.json`.
- **`version.json`** — actualizat:

```json
{
  "version": "0.2",
  "url": "http://una.md:3323/f/c/una_waiter/unawaiter.apk",
  "notes": "Ce s-a schimbat în această versiune (afișat utilizatorului)."
}
```

> `version` din `version.json` trebuie să fie **identică** cu cea din `appversion.h`
> a build-ului pe care tocmai l-ai urcat. Dacă `version.json` spune `0.2` dar APK-ul
> e tot `0.1`, aplicația va reintra în bucla "update disponibil" după instalare.

### 5. Verifică

Pe un telefon cu versiunea veche: Setări → Actualizări → "Check for updates" →
trebuie să apară "New version available: 0.2" → "Download" → instalare.

---

## Checklist rapid

- [ ] `appversion.h` — versiune crescută
- [ ] Run qmake în Qt Creator
- [ ] Build Release (kit Android)
- [ ] (dacă doar QML modificat) bump `build rev` în `qml.qrc`
- [ ] APK urcat pe server la URL-ul corect
- [ ] `version.json` actualizat (`version` = cea din `appversion.h`, `url` = APK-ul urcat)
- [ ] Testat pe un telefon: Check → Download → Install

---

## Note

- **Versiunea din `version.json` vs. cea instalată** se compară numeric pe segmente
  (`1.10 > 1.9`, nu lexicografic — vezi `UpdateManager::isRemoteNewer`). Deci `0.10`
  e mai mare decât `0.9`.
- **Rollback:** dacă o versiune are probleme, publici alta cu număr mai mare care
  conține fix-ul. Nu "cobori" versiunea în `version.json` — aplicațiile deja
  actualizate n-ar mai vedea-o ca update. Mereu înainte, niciodată înapoi.
- **`notes`** apare în dialogul de confirmare — folosește-l ca schimbări scurte,
  citibile de chelner ("corecție la achitare", etc.).

# UnaWaiter

Aplicație Android pentru chelneri — preluarea comenzilor la masă și trimiterea lor către bucătărie și către sistemul POS (UAMenu).

## Despre proiect

Chelnerul introduce comanda pe terminal (produse, cantități), o trimite la bucătărie și în front-ul de casă. Poate și **încasa masa direct**: se emite bonul fiscal pe terminalul SmartOne, iar comanda se închide în UAMenu ca achitată. Integrarea cu baza de date Oracle a UAMenu se face printr-un strat intermediar PHP.

## Tehnologii

- **Qt 5.15 / QML** — interfața și logica aplicației
- **Android** — platforma țintă
- **PHP + Oracle** — backend

## Structura proiectului

- `src/` — cod C++ (main, servicii)
- `qml/` — interfața (pagini, componente, temă)
- `resources/` — resurse Qt (`qml.qrc`)
- `android/` — configurare build Android

## Build

Deschide `UnaWaiter.pro` în Qt Creator (Qt 5.15.2) și rulează pe kit-ul Desktop sau Android.

## Documentație

- [`docs/smartone-fiscal/`](docs/smartone-fiscal/README.md) — achitarea din aplicație și emiterea bonului fiscal pe terminalul SmartOne: lanțul complet, modelul de bani din UAMenu, recuperarea după cădere și pașii de mutare pe producție.
- [`docs/auto-update/`](docs/auto-update/README.md) — mecanismul de auto-update (verificare versiune + download/install APK fără Play Store). Conține prezentarea generală, checklist-ul de deploy pe producție și fluxul de publicare a unei versiuni noi.
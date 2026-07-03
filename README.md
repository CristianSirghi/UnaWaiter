# UnaWaiter

Aplicație Android pentru chelneri — preluarea comenzilor la masă și trimiterea lor către bucătărie și către sistemul POS (UAMenu).

## Despre proiect

Chelnerul introduce comanda pe telefon (produse, cantități), o trimite la bucătărie (imprimantă de rețea) și în front-ul de casă, unde se face achitarea. Integrarea cu baza de date Oracle a UAMenu se face printr-un strat intermediar PHP.

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
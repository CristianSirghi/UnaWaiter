# Back-office: view-urile unificate `VUW_*_ALL`

Peste tabelele `UW_*` care stau pe fronturi (câte o bază per restaurant),
back-office-ul are trei view-uri unificate, ca managerul să vadă toate
restaurantele într-un singur ecran:

| view | citește | scrie prin |
|---|---|---|
| `VUW_WAITERS_ALL` | `vuw_waiters@<link>` | `TRG_VUW_WAITERS_ALL` |
| `VUW_ZONES_ALL` | `vuw_zones@<link>` | `TRG_VUW_ZONES_ALL` |
| `VUW_TABLES_ALL` | `vuw_tables@<link>` | `TRG_VUW_TABLES_ALL` |
| `VUW_LOCATIONS` | `ybmb_dif_cassa` + `tms_univers` | — (read-only) |

`UNION ALL` nu e actualizabil, deci scrierea trece prin trigger-e `INSTEAD OF`.

## Rulare

```bash
sqlplus foishor/<parola>@una.md:4024/cloudbd.world @00_install_vuw_all.sql 11
sqlplus foishor/<parola>@una.md:4024/cloudbd.world @00_install_vuw_all.sql 11,13,17
```

Argumentul e lista de filiale **instalate**. Se rulează și la prima instalare, și
de fiecare dată când se adaugă un restaurant — nu e nimic de decomentat, doar
lista se schimbă. Rularea repetată e sigură (totul e `CREATE OR REPLACE`).

**Înainte:** `sql/install/` pe fiecare front din listă.
**După:** `../forme/install_forme.sql`.

## Cele două lucruri care contează

**1. Citirea e generată, scrierea era deja generică.** Triggerele nu conțin niciun
cod de filială și niciun nume de link — îl caută la fiecare scriere în
`ybmb_dif_cassa`. View-urile, în schimb, erau scrise de mână, cu branșele pentru
13 și 17 **comentate**: trei view-uri × trei branșe = nouă linii de decomentat
corect, fiecare cu alt link și altă listă de coloane. Copy-paste-ul chiar
produsese deja o greșeală — branșele comentate ale lui `vuw_waiters_all` citeau
`vuw_zones`. Inofensivă doar pentru că erau comentate. Acum ambele părți iau
link-ul din același registru, deci nu pot ajunge să arate spre baze diferite.

**2. `CREATE OR REPLACE VIEW` ȘTERGE trigger-ul `INSTEAD OF`.** De aceea `00` le
rulează lipite, iar `99` verifică explicit că toate trei sunt `ENABLED`. Dacă
rulezi doar `01` și te oprești, formele arată datele dar orice salvare cade cu
`ORA-01733` — un mesaj din care nimeni nu deduce că lipsește un trigger.

## `VUW_LOCATIONS` e restrâns la filialele instalate

Nivelul „locație" al formelor. Restrâns **intenționat** la aceleași filiale ca
view-urile: altfel, pe producție, managerul ar vedea toate cele 5 din registru —
inclusiv Megapolis și Aleco Russo, care n-au nici măcar db link — și ar da peste
ecrane goale fără să înțeleagă de ce. La pilotul de la Rîșcani, forma arată exact
un restaurant.

## Limitare cunoscută: un front căzut oprește tot

`UNION ALL` peste db link-uri înseamnă că, dacă frontul unui restaurant e
inaccesibil, **formele nu se deschid deloc — nici pentru celelalte restaurante**.

Mai mult, verificat pe 2026-08-03: Oracle rezolvă link-ul deja la
`CREATE OR REPLACE VIEW`, nu doar la `SELECT`. Deci **nu poți nici măcar instala**
view-urile pentru un restaurant al cărui front e căzut în acel moment — încercarea
pe test cu `11,13,17` a picat cu `ORA-12154` la primul view.

Partea bună: eșecul e **curat și atomic** — a picat înainte să înlocuiască ceva,
iar view-urile vechi au rămas neatinse (verificat imediat după: toate 15
verificări OK).

Alternativa, dacă devine supărător în practică: o funcție pipelined cu tratare de
eroare pe fiecare branșă, care întoarce restaurantele accesibile și le sare pe
celelalte. N-am făcut-o — adaugă o cale de execuție nouă pentru un ecran folosit
rar (schimbări de mese, înrolarea unui chelner), iar acum comportamentul e cel
puțin **onest**: pică vizibil, nu arată tăcut date parțiale.

## Ce s-a verificat (2026-08-03, pe test)

| test | rezultat |
|---|---|
| instalare completă pentru filiala 11 | 15/15 verificări OK, ieșire 0 |
| filială inexistentă (`99`) | refuz curat, `ORA-20071` |
| text în loc de cod (`abc`) | refuz curat, `ORA-20070` |
| multi-filială `11,13,17` pe test | `ORA-12154` (13 și 17 au link-uri nerezolvabile din `clouddev`) — **fără să atingă view-urile existente** |
| starea testului după eșec | neschimbată, toate verificările OK |

Cazul multi-filială **nu s-a putut valida cu succes** de aici: din back-office-ul
de test, link-urile spre Columna și M. cel Bătrîn nu se rezolvă. Se validează abia
pe producție, când al doilea restaurant primește tabelele `UW_*`.

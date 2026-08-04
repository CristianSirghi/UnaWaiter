# Achitare + bon fiscal SmartOne — prezentare generală

Chelnerul poate încasa masa direct din aplicație: se emite bonul fiscal pe
terminalul SmartOne, iar comanda se închide în UAMenu ca achitată. Înainte,
aplicația doar *reflecta* starea de plată — încasarea se făcea exclusiv la casă.

Integrarea e portată din **UNARetail** (`D:\UNARetail\uaMobi`), unde rulează deja
în producție. Documentul de referință pentru protocol e
`uaMobi/widgets/VanzariBranch/SMARTONE_CONTRACT.md` — de citit înainte de orice
modificare aici, conține invariantele de bani învățate din bug-uri reale.

> ⚠️ **Configurat momentan pe TEST** (`clouddev`). Vezi secțiunea
> [Mutarea pe producție](#mutarea-pe-producție).

---

## Constrângerea care a decis arhitectura

Bridge-urile SmartOne sunt aplicații externe instalate **pe terminal** și ascultă
doar pe `127.0.0.1`:

| Canal | Adresă | Rol |
|---|---|---|
| Fiscal | `127.0.0.1:8080` | emitere + tipărire bon |
| Card POS | `127.0.0.1:8888` | aplicația băncii |

Adresele sunt hardcodate în `smartoneclient.cpp` — nu din lene, ci pentru că nu
sunt servicii de rețea. **Un telefon obișnuit nu le poate atinge**, deci
UnaWaiter trebuie să ruleze chiar pe terminalul SmartOne.

`.aar`-ul SmartOne (`PosSdkXzy1.2.3.0.aar`) **nu e necesar**: tot fluxul fiscal
merge prin HTTP. Ar trebui adăugat doar dacă vrem și print *non*-fiscal
(bon de bucătărie).

---

## Lanțul complet (cine pe cine cheamă)

```
OrderPage.qml  →  butonul hamburger  →  OrderActionSheet  →  "Achită"
   │  startPayment(): RE-CITEȘTE liniile din Oracle (get_order_lines)
   │  — comanda putea fi schimbată de pe alt terminal, iar bonul
   │    nu are voie să difere de comandă
   ▼
PaymentSheet.qml   Numerar / Card POS integrat / Card terminal separat
   │  paymentController.payCash|payCardPos|payCardManual(...)
   ▼
PaymentController          [C++: src/core/paymentcontroller.cpp]
   │  salvează pending_fiscal.json  ← PUNCT DE RECUPERARE
   │  (card POS: întâi 8888/sale, aplicația trece în fundal)
   ▼
SmartOneClient             [C++: src/core/smartoneclient.cpp]
   │  GET  8080/check-shift   (+ 8080/open-shift dacă e închisă)
   │  POST 8080/sale          → data.document_number  ← DOCUMENT COMIS
   │  POST 8080/print_check   → tipărirea propriu-zisă
   ▼
dataService.payOrder(...)  [C++: src/core/dataservice.cpp]
   │  POST ?cmd=pay_order
   ▼
oracle_waiter.php → payOrder()
   │  BEGIN :result := pg_mobile_web_waiter.pay_order(...); END;
   ▼
pg_mobile_web_waiter.pay_order   [Oracle]
   │  STATE=3, PAY_TYPE, PAY / SUMA_TERMINAL, CEK=1, NRDOC, DATA1
   │  + rând în uw_fiscal_receipts (nr_comand ↔ document fiscal)
   ▼
paymentSucceeded → confirmarea, apoi ecranul se închide și masa se eliberează
```

Din momentul apăsării pe „Achită" până la confirmare, tot ecranul e acoperit de
`PaymentProgressOverlay` — vezi [Ce vede chelnerul](#ce-vede-chelnerul).

### De ce fiscal ÎNTÂI, Oracle DUPĂ

Bonul e artefactul legal și e protejat de duplicare (SmartOne răspunde `409` la
un document deja existent). Închiderea comenzii e contabilitate internă, care se
poate relua în siguranță. Invers, comanda ar dispărea din listă ca „achitată"
fără ca clientul să aibă bon.

---

## Ce vede chelnerul

Lanțul de mai sus durează realist 4–8 secunde la numerar (și mult mai mult la
card, unde se așteaptă un om). Înainte, singurul semn era textul butonului de
jos — „Se achită…" — pentru patru operațiuni diferite: terminal de card,
memorie fiscală, imprimantă, Oracle. Când se blochează, **contează foarte mult
care din ele**, pentru că fiecare cere altceva de la chelner.

`PaymentProgressOverlay` acoperă tot ecranul cât ține plata și arată pașii, cu
o imprimantă desenată în centru care scoate hârtie **doar în timpul tipăririi
reale**:

| Pas | Bifat de |
|---|---|
| Confirmă pe terminalul de card *(doar la POS integrat)* | `cardConfirmed` |
| Se emite bonul fiscal | `receiptIssued` (document comis) |
| Se tipărește bonul | `receiptPrinted` |
| Se închide comanda | `orderClosed` (`pay_order` a răspuns) |

**Ultimii doi pași nu sunt o secvență.** Amândoi pornesc când documentul e comis
și se termină independent, pe drumuri diferite (imprimanta locală vs. Oracle
prin internet) — de-aceea `PaymentController` expune o stare per pas în loc de o
singură „fază curentă", care ar fi trebuit să mintă despre unul din ei.

La final, o confirmare cu numărul bonului și — la numerar cu rest — **restul de
dat, în cel mai vizibil bloc de pe ecran**. Până acum restul apărea doar în
dialogul de dinaintea plății, adică fix înainte să fie nevoie de el. Confirmarea
se închide singură după ~2,8s; **dacă e rest de dat, așteaptă apăsarea**, ca suma
să fie citită.

Overlay-ul e un `Popup` pe `Overlay.overlay`, nu un strat în pagină, deci
acoperă și antetul. Împreună cu opritorul din `requestBack()`, asta închide o
gaură reală: back-ul în timpul plății scotea pagina de sub `paymentSucceeded`
(ascultat DOAR în OrderPage), iar `OrdersStore.removeOrder` nu se mai chema —
masa rămânea ocupată local deși comanda era închisă în Oracle.

Desenul e din `Rectangle`-uri simple, fără `Canvas` sau `QtQuick.Shapes`: pe
build-ul ăsta (Qt 5.15.2, Android) acelea s-au dovedit nesigure, iar o animație
de așteptare e ultimul loc unde vrei un ecran negru.

---

## Modelul de bani din UAMenu (verificat pe producție)

Replicat exact de `pay_order`. Inversarea ar strica rapoartele UAMenu și ar cădea
în validarea „nu ajung bani pentru achitare" din `TRG_VMDB_COMENZ_RESTAURANT`:

| Plată | `PAY_TYPE` | `PAY` | `SUMA_TERMINAL` |
|---|---|---|---|
| Numerar | 1 | suma primită de la client (poate depăși totalul) | NULL |
| Card | 2 | 0 | totalul comenzii |

Plus, la orice achitare: `CEK=1`, `DATA1=SYSDATE` (data tranzacției, pe care
UAMenu o afișează ca „Дата транз"), și `NRDOC`.

**`NRDOC` nu e o constantă** — pe test e 20, pe producție 10. `pay_order` îl
moștenește de la ultima comandă închisă din aceeași bază, în loc să-l hardcodeze.
*De confirmat cu Daniela/Sandu dacă se schimbă la deschiderea unei ture noi.*

## TVA — citește tot înainte să schimbi o cotă

`VMDB_COMENZD.CODTVA` folosește exact literele așteptate de SmartOne, deci nu e
nevoie de traducere.

Cotele trimise (`taxForCode`): **A=20, B=8, C=6**. Prețurile au TVA-ul **INCLUS**,
deci taxa e `sumă × r/(1+r)`, nu `sumă × r` — aici nu există niciun dezacord,
aceeași formulă e peste tot.

### ⚠️ Ce tipărește bonul NU depinde de valorile astea

Aparatul fiscal SmartOne are **propriul tabel de taxe** și îl folosește pe al
lui. Dovedit, nu dedus: cu aplicația trimițând `C = 10.00%` — vizibil în log —
bonul a ieșit tipărit cu **6%**.

```
[SmartOne][TVA] cod=C litera=C cota=10.00% sursa=rezerva-din-cod suma=4800 bani tva=436 bani
```
```bash
adb logcat -s UnaWaiter:* | grep "SmartOne..TVA"
```

Linia asta rămâne permanent în `buildSalePayload`. Fără ea, singurul mod de a ști
ce declarăm pe un bon fiscal e să ghicim — iar ghicitul a costat trei schimbări
de cotă într-o zi.

Valorile de mai sus sunt deci ce **declarăm**, nu ce se tipărește. Tocmai
de-aceea trebuie să fie corecte: `C = 6%` e ce tipărește aparatul **și** ce
înregistrează UAMenu în Oracle (`TVA_C` = 6% din brut pe 8426 din 8426 comenzi
achitate de producție, și pe comenzile încă deschise).

### ⚠️ Contradicția clientului: două aparate, două cote

Imprimanta fiscală **Tremol** de la casă tipărește pentru aceeași literă **10%**,
pentru că UAMenu îi trimite `Unirest_Util.vat_percent_by_letter('C') = 10` prin
pachetul `BON`. Adică **același restaurant emite bonuri cu 6% (din aplicație) și
cu 10% (de la casă), pe același produs** — iar UAMenu contabilizează la 6% dar
tipărește 10%.

Cele două aparate sunt programate diferit. **De ridicat la Sandu/Daniela**:
rapoartele X/Z ale celor două nu au cum să se reconcilieze. Întrebarea concretă:
*„de ce bonul de la casă scrie 10% dacă aceeași comandă e înregistrată în bază cu
6%?"*

> **Nu lua cota din `Unirest_Util.vat_percent_by_letter`.** Pare sursa oficială,
> dar întoarce 10 — valoarea contrazisă și de aparat, și de contabilitate. S-a
> încercat pe 2026-08-03 (coloana `TVA_PRC` în `get_order_lines`) și s-a retras
> înainte de compilare. O valoare greșită luată din bază e mai rea decât una
> corectă din cod, pentru că arată autoritară.
>
> C++ știe deja să citească `TVA_PRC` dacă apare — deci când există o sursă de
> încredere, se adaugă doar coloana și merge de la sine.

`CODTVA` ajunge pe linie **fără ca `add_order_line` să-l scrie** — îl completează
trigger-ul `INSTEAD OF` al view-ului, copiindu-l din `vms_univers`. Verificat pe
liniile comenzilor create de aplicație: coincide cu produsul, mereu.

---

## Numărul de document (`nextPayId`) — singura setare care cere reglaj

`docNumber` trimis la `8080/sale` e un **contor intern**, mic și crescător,
persistat în `QSettings` (`fiscal/nextPayId`) și avansat doar după ce documentul
a fost comis.

> **Nu folosi numărul comenzii.** S-a încercat (părea o cheie de idempotență
> gratuită) și terminalul refuză: `Invalid docNumber '382766'`. Aparatul
> validează numărul față de propria secvență, iar numerele de comandă Oracle au
> 6 cifre.

Idempotența nu se pierde: `payId` e salvat în `pending_fiscal.json`, deci o
reluare după cădere retrimite exact același număr → `409` în loc de un al doilea bon.

### ⚠️ Trei numere diferite — nu le confunda

Verificat pe test, 2026-08-04, pe aceeași plată:

| Număr | De unde | Exemplu | Bun la |
|---|---|---|---|
| `docNumber` trimis la `/sale` | contorul nostru (`fiscal/nextPayId`) | mic | idempotență la reluare |
| `data.document_number` din răspuns | memoria fiscală a aparatului | `2555` | `/print_check`, `uw_fiscal_receipts` |
| ce se tipărește pe hârtie | numerotarea proprie a aparatului | `BON # 24` | ce vede clientul |

Al treilea **nu apare nicăieri în contractul SmartOne** și nu-l primim în niciun
răspuns — deci nu-l putem lega programatic de o comandă.

De-aceea marcajul scris de `pay_order` în `COMENT` e doar `'Achitat prin
SmartOne'`, **fără număr**: prima versiune punea `document_number` acolo, iar în
UAMenu ieșea „bon 2555" lângă o hârtie pe care scria „BON # 24" — adică sugera o
neconcordanță care nu exista.

Se editează din **Setări → Admin → „Terminal fiscal"**. E nevoie de reglaj când:

- se instalează pe un terminal care are deja documente emise;
- se reinstalează aplicația / se șterg datele (contorul revine la 1, iar
  terminalul ar putea răspunde „document deja existent").

---

## Recuperarea după cădere

În timpul plății cu cardul aplicația trece în fundal, iar Android o poate omorî.
`pending_fiscal.json` (scris **atomic**, temp + rename) e singura urmă că s-au
luat bani. La revenirea în prim-plan sau la pornire:

| Stare în fișier | Ce facem |
|---|---|
| fază „card", fără document | reinterogăm `8888/check` |
| document comis, Oracle neînchis | doar `pay_order` (NU retrimitem `/sale`) |
| nu știm dacă bonul s-a emis | retrimitem `/sale` cu **același** `docNumber` |

La retrimitere, un `409` înseamnă „era deja emis ȘI tipărit" → curățăm **tăcut**,
fără retipărire. Altfel ar ieși un al doilea bon pe hârtie — exact falsul-pozitiv
reclamat de client în UNARetail.

**Fișierul se șterge într-un singur loc**, doar după confirmarea pozitivă a
tipăririi (`onPrintSuccessful`).

---

## Protecții împotriva dublei fiscalizări

Trei niveluri, independente:

1. `pay_order` refuză o comandă care nu e în stare 1 sau 2 (`ORA-20053`);
2. `uw_fiscal_receipts.nr_comand` e **PRIMARY KEY** — o a doua încercare pe
   aceeași comandă eșuează la nivel de bază, chiar dacă protecțiile din aplicație
   au fost ocolite (reinstalare, alt device, proces omorât);
3. după ce SmartOne a întors `document_number`, o eroare de tipărire se rezolvă
   prin **retipărire**, niciodată prin reemitere.

Achitarea e blocată și cât timp există modificări netrimise — bonul trebuie să
corespundă comenzii.

---

## Fișiere

| Fișier | Rol |
|---|---|
| `src/core/smartoneclient.{h,cpp}` | HTTP către 8080/8888; `buildSalePayload()` e pur și testabil |
| `src/core/paymentcontroller.{h,cpp}` | mașina de stări, expusă în QML ca `paymentController` |
| `src/core/pendingfiscalstore.{h,cpp}` | recuperarea pe disc |
| `qml/components/controls/PaymentSheet.qml` | alegerea metodei + suma primită/rest |
| `qml/components/controls/PaymentProgressOverlay.qml` | pașii plății + confirmarea cu restul |
| `qml/components/controls/PrinterAnimation.qml` | imprimanta desenată (hârtie + zimți) |
| `qml/components/controls/OrderActionSheet.qml` | meniul hamburger (Achită / Șterge) |
| `sql/uw_fiscal_receipts.sql` *(la Kristian, în `Desktop\foishor_test\sql\`)* | tabelul de bonuri |

---

## Mutarea pe producție

1. **Oracle**: creează `uw_fiscal_receipts` și compilează `pay_order` +
   `get_order_lines` (cu `codtva`) pe baza de producție.
2. **PHP**: urcă `oracle_waiter.php` (funcția `payOrder` + `case 'pay_order'`).
3. **Verifică `NRDOC`** — pe producție era 10; funcția îl moștenește singură, dar
   merită confirmat pe primele comenzi.
4. **Setează `nextPayId`** din AdminPage, peste ultimul document emis pe terminal.
5. Testează pe o masă reală, cu sumă mică, și confirmă în UAMenu că apare
   „Заказ закрыт / Bon tiparit" cu tipul de plată corect.

Vezi și [`unawaiter-prod-migration-pending`] din notele de proiect.

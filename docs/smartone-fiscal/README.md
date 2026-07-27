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
paymentSucceeded → ecranul se închide, masa se eliberează
```

### De ce fiscal ÎNTÂI, Oracle DUPĂ

Bonul e artefactul legal și e protejat de duplicare (SmartOne răspunde `409` la
un document deja existent). Închiderea comenzii e contabilitate internă, care se
poate relua în siguranță. Invers, comanda ar dispărea din listă ca „achitată"
fără ca clientul să aibă bon.

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

**TVA se mapează 1:1**: `VMDB_COMENZD.CODTVA` folosește exact literele așteptate
de SmartOne (`A`=20%, `C`=8%). Fără traducere.

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

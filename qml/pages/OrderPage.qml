import QtQuick 2.15
import "../theme"
import "../app"
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "../components/controls" as Components
import "../components/icons" as Icons
import "../app/Format.js" as Format

Page {
    id: root

    property string zone: ""
    property int tableNumber: 0

    // ---- Meniu real (din backend, via dataService) ----
    // Structura pe categorii: [{ cat, grp, items: [{ name, unit, price, cod }] }].
    // Construită din dataService.categories + dataService.menu (vezi buildMenuData).
    // Produsele NU au încă `addons` — modelul de adaosuri (PARENT_NRORD) se face
    // într-un pas separat; până atunci UI-ul de adaosuri rămâne inactiv de la sine
    // (hasAddons devine false când produsul n-are câmpul `addons`).
    property var menuData: []
    // Produsele indexate după COD (vms_bliuda.cod), NU după nume - cheia
    // folosită peste tot în starea comenzii. Numele nu e unic: pe baza de test
    // "Varza" există cu cod 2157 ȘI 2614, ambele în grupa 2 (la fel
    // "Inghetata", "Servicii de livrare"). Cu indexare după nume, harta
    // nume→cod păstra ultimul cod citit, deci un tap pe rândul unui produs
    // trimitea la bucătărie CELĂLALT produs cu același nume. În plus, numele
    // se schimbă în timp (vmdb_comenzd.clcbliudat e un instantaneu de la
    // momentul comenzii: "Calmar uscat" în linii vs "Calmari uscati" în meniu
    // azi, pentru același cod 2132), deci o comandă existentă nu se putea
    // reconcilia cu meniul curent. Codul e stabil: get_menu îl întoarce ca
    // COD, get_order_lines ca BLIUDA, iar add_order_line îl primește ca
    // p_product - aceeași valoare pe tot lanțul.
    // Formă: { cod: { name, unit, price, cod } } (aceleași obiecte ca menuData).
    property var productByCode: ({})
    // Nume→cod, folosit EXCLUSIV la migrarea comenzilor locale vechi salvate
    // pe nume (vezi migrateLegacyQty). Ambiguu prin natura lui - de-aceea nu
    // are voie să fie folosit nicăieri altundeva.
    property var codeOfName: ({})
    // true după ce meniul a fost încărcat și structurat; până atunci arătăm "se încarcă".
    property bool menuReady: false
    property string loadError: ""

    property int currentCategory: 0
    // Căutare: cât timp e activă, tab-urile de categorii sunt ascunse și
    // productsModel arată rezultate din toate categoriile (nu doar cea curentă).
    property bool searchActive: false
    property string searchQuery: ""
    property bool summaryExpanded: false
    readonly property int summaryMaxRows: 5
    // true dacă masa are deja o comandă trimisă (deschisă din TablesPage) — arată butonul de ștergere.
    property bool isEditing: false
    // Masa/zona comenzii existente în OrdersStore, înainte de orice schimbare
    // făcută cu ChangeTablePicker — submitOrder mută pe (zone, tableNumber) la
    // trimitere, iar deleteOrder trebuie să șteargă tot de aici (nu de la noua
    // masă, care încă n-a fost scrisă în store).
    property string originalZone: ""
    property int originalTableNumber: 0

    // Cantități per produs (cheie = COD, persistă la schimbarea categoriei).
    property var qtyStore: ({})
    // Adaosuri alese, grupate pe produsul-părinte: { codProdus: { numeAdaos: cantitate } }.
    property var addonStore: ({})
    property int orderCount: 0
    property real orderTotal: 0
    // Numărul de oaspeți la masă (minim 1), ales de chelner și salvat cu comanda.
    property int guestCount: 1
    // Plafon: butonul "+" nu avea nicio limită, deci un deget ținut apăsat pe
    // el scria sute de clienți la masă în Oracle (PERSON pe comandă). 99 e
    // peste orice masă reală, dar oprește nonsensul.
    readonly property int maxGuests: 99

    // Stare trimitere reală către Oracle (create_order + add_order_line).
    property bool sending: false
    property string sendError: ""

    // Stare anulare comandă (cancel_order) - separată de `sending`, ca
    // trimiterea și ștergerea să nu se poată amesteca.
    property bool deleting: false
    property string deleteError: ""

    // ---- Achitare (bon fiscal SmartOne + închiderea comenzii în Oracle) ----
    // `paying` ține ecranul blocat de la apăsarea butonului până când comanda
    // e chiar închisă; e separată de `sending`/`deleting` din același motiv
    // pentru care și acelea sunt separate între ele.
    property bool paying: false
    // Oracle a confirmat închiderea (pay_order). Tipărirea e un pas distinct,
    // care poate veni înainte sau după - vezi finishPaymentIfDone().
    property bool orderClosedByPayment: false
    // Așteptăm liniile cerute special pentru bon (nu cele de la deschiderea
    // ecranului) - vezi startPayment().
    property bool awaitingPayLines: false
    property string payError: ""
    property string reprintDoc: ""

    // Dialog, nu banner (vezi sendErrorDialog mai jos în fișier), deschis
    // EXPLICIT de-aici - nu dintr-un onSendErrorChanged.
    //
    // Cu handler-ul pe semnalul de schimbare, a doua oară când apărea exact
    // aceeași eroare (ex. apeși "Trimite", masa e luată de Ion, OK, apeși din
    // nou) proprietatea primea aceeași valoare, deci nu se emitea niciun
    // semnal și dialogul nu se mai deschidea - butonul părea pur și simplu
    // mort. Un apel direct se re-declanșează de fiecare dată.
    function showSendError(message) {
        root.sendError = message
        sendErrorDialog.open()
    }

    function showDeleteError(message) {
        root.deleteError = message
        deleteErrorDialog.open()
    }

    function showPayError(message) {
        root.paying = false
        root.payError = message
        payErrorDialog.open()
    }

    // Totalul REAL al comenzii, calculat din liniile Oracle - nu din starea
    // locală. Bonul fiscal e document legal: trebuie să corespundă exact cu ce
    // e în comandă, chiar dacă ecranul ar fi rămas în urmă.
    function oracleLinesTotal(lines) {
        var t = 0
        for (var i = 0; i < lines.length; ++i)
            t += parseFloat(lines[i].CLCSUMAT)
        return isNaN(t) ? 0 : t
    }

    // Reîncarcă liniile din Oracle CHIAR ÎNAINTE de achitare: de când e deschis
    // ecranul, comanda ar fi putut fi modificată de pe alt terminal, iar un bon
    // care nu corespunde comenzii e o problemă fiscală, nu una de afișare.
    function startPayment() {
        if (root.sentNrComand <= 0 || root.paying)
            return
        root.awaitingOrderLines = true
        root.awaitingPayLines = true
        dataService.loadOrderLines(String(root.sentNrComand))
    }

    function openPaymentSheet(lines) {
        var total = root.oracleLinesTotal(lines)
        if (total <= 0) {
            root.showPayError(qsTr("This order has nothing to pay for."))
            return
        }
        paymentSheet.openWith(total)
    }

    function pay(method, received) {
        var lines = dataService.orderLines
        var total = root.oracleLinesTotal(lines)
        if (total <= 0) {
            root.showPayError(qsTr("This order has nothing to pay for."))
            return
        }

        root.paying = true
        root.orderClosedByPayment = false

        var oficiant = String(AppSettings.waiterOficiant)
        if (method === "cardPos")
            paymentController.payCardPos(root.sentNrComand, lines, total, AppSettings.waiterName, oficiant)
        else if (method === "cardManual")
            paymentController.payCardManual(root.sentNrComand, lines, total, AppSettings.waiterName, oficiant)
        else
            paymentController.payCash(root.sentNrComand, lines, total, received, AppSettings.waiterName, oficiant)
    }

    // Ecranul se închide DOAR după ce comanda e chiar închisă în Oracle. Bonul
    // poate fi deja tipărit, dar cât timp comanda e deschisă masa rămâne
    // ocupată - a ne întoarce la listă spunând "gata" ar fi o minciună.
    function finishPaymentIfDone() {
        if (!root.orderClosedByPayment)
            return
        root.paying = false
        OrdersStore.removeOrder(root.originalZone, root.originalTableNumber)
        root.done()
    }

    // Numărul real de comandă (nr_comand) din Oracle pentru masa curentă, când
    // se editează o comandă deja trimisă - 0 dacă e o comandă nouă sau dacă
    // masa are doar o copie locală veche (dinainte ca acest tracking să existe).
    property int sentNrComand: 0
    // Numărul de clienți deja confirmat în Oracle - dacă root.guestCount
    // diferă de asta la trimitere, înseamnă că a fost schimbat în acest
    // ecran și trebuie trimis prin update_guest_count.
    property int sentGuestCount: 1
    // Cantitățile deja confirmate în Oracle (per COD de produs) - pragul sub care
    // butonul "-" nu poate coborî, pentru că nu avem cum să ștergem o linie
    // deja trimisă la bucătărie din acest ecran (add_order_line doar adaugă).
    property var sentQtyStore: ({})
    // Așteptăm get_order_lines la deschiderea unei comenzi existente cu
    // nr_comand cunoscut - până sosește, produsele rămân needitabile ca să nu
    // pornim de la un prag greșit.
    property bool awaitingOrderLines: false
    property string linesLoadError: ""

    // Zonă reală per masă + "zonă_masă" → { waiter, orderNo } pentru orice
    // masă cu comandă deschisă în Oracle (toți chelnerii, indiferent de
    // telefon) - același tipar ca SelectTablePage, dat mai departe la
    // ChangeTablePicker ca să arate acolo cine ocupă efectiv masa, nu doar
    // un dreptunghi estompat fără nume.
    property var pickerDeskZone: ({})
    property var occupiedByDesk: ({})
    property var lastOccupancyRows: null

    // Numerele reale de masă per zonă, date mai departe la ChangeTablePicker -
    // aceeași sursă (uw_tables) ca SelectTablePage, ca picker-ul să nu mai
    // presupună 1..10 (mese peste 10 inaccesibile, mese inexistente oferite).
    property var pickerHallTables: []
    property var pickerTerraceTables: []

    // Semnalăm către main.qml că am terminat (trimis sau șters) — el ne readuce
    // la lista de mese, indiferent câte pagini sunt pe stivă.
    signal done()

    // Există modificări făcute aici și netrimise încă în Oracle?
    //
    // Comparăm cu ce e deja confirmat (sentQtyStore / sentGuestCount / masa
    // originală), nu cu zero: la editarea unei comenzi existente, produsele
    // deja trimise la bucătărie NU sunt modificări nesalvate.
    //
    // Funcție, nu proprietate legată: qtyStore e un `var` mutat pe loc, deci un
    // binding pe el nu s-ar reevalua niciodată. O evaluăm la momentul apăsării.
    function hasUnsavedChanges() {
        // O trimitere/anulare/achitare în curs se termină singură
        // (finishSubmit/done/finishPaymentIfDone) - nu mai e nimic de salvat
        // sau de pierdut, deci nici de confirmat la ieșire.
        if (root.sending || root.deleting || root.paying)
            return false

        if (!root.isEditing)
            return root.orderCount > 0

        if (root.guestCount !== root.sentGuestCount)
            return true
        if (root.zone !== root.originalZone || root.tableNumber !== root.originalTableNumber)
            return true

        for (var code in root.qtyStore) {
            var sent = root.sentQtyStore[code] ? root.sentQtyStore[code] : 0
            if (root.qtyStore[code] !== sent)
                return true
        }
        return false
    }

    // Punct unic de ieșire din pagină: îl folosesc ȘI butonul de back din
    // antet, ȘI butonul fizic Android (main.qml caută funcția asta pe pagina
    // curentă). Fără el, back-ul de sistem ocolea confirmarea și comanda în
    // lucru se pierdea tăcut - chelnerul adăuga 10 produse, atingea back din
    // reflex și rămânea cu ecranul gol, fără nicio întrebare.
    function requestBack() {
        // `visible`, nu `opened`: `opened` e încă fals cât rulează animația de
        // deschidere, deci un back rapid de două ori ar redeschide dialogul.
        if (discardDialog.visible)
            return
        if (root.hasUnsavedChanges())
            discardDialog.open()
        else
            root.StackView.view.pop()
    }

    function buildPickerDeskZone(rows) {
        var map = {}
        var hall = []
        var terrace = []
        for (var i = 0; i < rows.length; ++i) {
            var no = parseInt(rows[i].TABLE_NO)
            map[no] = rows[i].ZONE
            if (rows[i].ZONE === "hall")
                hall.push(no)
            else if (rows[i].ZONE === "terrace")
                terrace.push(no)
        }
        root.pickerDeskZone = map
        root.pickerHallTables = hall
        root.pickerTerraceTables = terrace
        if (root.lastOccupancyRows !== null)
            root.buildOccupiedTables(root.lastOccupancyRows)
    }

    function buildOccupiedTables(rows) {
        root.lastOccupancyRows = rows
        var map = {}
        for (var i = 0; i < rows.length; ++i) {
            var r = rows[i]
            var hasDesk = r.DESK !== undefined && r.DESK !== null && String(r.DESK).trim() !== ""
            if (!hasDesk) continue
            var deskNo = parseInt(r.DESK)
            if (deskNo <= 0) continue
            var zone = root.pickerDeskZone[deskNo] ? root.pickerDeskZone[deskNo] : "hall"
            map[zone + "_" + deskNo] = {
                waiter: r.CLCOFICIANTT ? String(r.CLCOFICIANTT).trim() : "",
                orderNo: r.NR_COMAND !== undefined && r.NR_COMAND !== null ? String(r.NR_COMAND) : ""
            }
        }
        root.occupiedByDesk = map
    }

    // "zone" e un cod intern ("hall"/"terrace"), nu textul afișat — așa
    // rămâne corect indiferent de limba curentă a interfeței.
    function zoneLabel() {
        return zone === "terrace" ? qsTr("Terrace") : qsTr("Hall")
    }

    // Câte adaosuri (bucăți) sunt alese pentru un produs — pentru marcajul din rând.
    function addonCountFor(code) {
        var group = addonStore[code]
        if (!group) return 0
        var n = 0
        for (var a in group) n += group[a]
        return n
    }

    // Rândul afișat pentru un produs din meniu - aceeași formă în lista de
    // categorie și în rezultatele căutării.
    function productRow(p) {
        return {
            code: p.cod,
            name: p.name,
            unit: p.unit,
            price: p.price,
            qty: root.qtyStore[p.cod] ? root.qtyStore[p.cod] : 0,
            hasAddons: p.addons !== undefined && p.addons.length > 0,
            addonCount: root.addonCountFor(p.cod)
        }
    }

    function populateCategory(i) {
        productsModel.clear()
        if (!menuData || i < 0 || i >= menuData.length)
            return
        var items = menuData[i].items
        for (var k = 0; k < items.length; ++k)
            productsModel.append(root.productRow(items[k]))
    }

    // Căutare peste tot meniul (toate categoriile), nu doar cea selectată —
    // meniul complet e deja în memorie (menuData), deci nu cerem nimic nou.
    function applySearch(query) {
        productsModel.clear()
        var q = query.toLowerCase()
        if (!menuData) return
        for (var ci = 0; ci < menuData.length; ++ci) {
            var items = menuData[ci].items
            for (var k = 0; k < items.length; ++k) {
                var it = items[k]
                if (it.name.toLowerCase().indexOf(q) === -1) continue
                productsModel.append(root.productRow(it))
            }
        }
    }

    // Ascunde tastatura de căutare (dacă e deschisă). Chemat când chelnerul
    // derulează lista sau apasă "+" la un produs - în ambele cazuri a terminat
    // de tastat, iar tastatura doar ocupă ecranul. Ascunderea câmpului nu
    // închide singură tastatura pe Android: îi luăm explicit focusul și cerem
    // input panel-ului să dispară.
    function dismissSearchKeyboard() {
        if (root.searchActive && searchField.activeFocus) {
            searchField.focus = false
            Qt.inputMethod.hide()
        }
    }

    // Recalculează numărul de produse și totalul (părinți + adaosuri) din stări.
    // Mai robust decât actualizarea incrementală, mai ales cu adaosuri legate de produs.
    //
    // Parcurge qtyStore, NU meniul: un produs comandat care nu se mai regăsește
    // în meniul curent trebuie să intre oricum în total. Înainte, parcurgând
    // meniul, o astfel de linie era sărită tăcut - chelnerul vedea un total mai
    // mic decât ce era efectiv pe comandă în Oracle. Prețul unor asemenea
    // produse vine din chiar răspunsul get_order_lines (vezi applyServerLines).
    function recomputeTotals() {
        var count = 0
        var total = 0
        for (var code in qtyStore) {
            var pq = qtyStore[code]
            if (pq <= 0) continue
            var p = productByCode[code]
            count += pq
            total += pq * (p ? p.price : 0)
            if (p && p.addons) {
                for (var ai = 0; ai < p.addons.length; ++ai) {
                    var a = p.addons[ai]
                    var aq = (addonStore[code] && addonStore[code][a.name]) ? addonStore[code][a.name] : 0
                    total += aq * a.price
                }
            }
        }
        orderCount = count
        orderTotal = total
    }

    // Reconstruiește lista pentru panoul "Comandă curentă": fiecare produs urmat de
    // adaosurile lui (rânduri-copil, marcate cu isAddon pentru indentare).
    // Ordinea urmează meniul (categorie, apoi produs), ca rezumatul să nu se
    // rearanjeze aleatoriu. Produsele comandate care nu mai sunt în meniu vin
    // la final, în loc să dispară din listă cum se întâmpla înainte.
    function rebuildSelectedModel() {
        selectedModel.clear()
        var shown = ({})

        for (var ci = 0; ci < menuData.length; ++ci) {
            var items = menuData[ci].items
            for (var ii = 0; ii < items.length; ++ii) {
                root.appendSelectedRows(items[ii].cod)
                shown[items[ii].cod] = true
            }
        }

        for (var code in qtyStore) {
            if (!shown[code])
                root.appendSelectedRows(code)
        }
    }

    // Rândul unui produs în rezumat, urmat de rândurile-copil ale adaosurilor lui.
    function appendSelectedRows(code) {
        var pq = qtyStore[code] ? qtyStore[code] : 0
        if (pq <= 0)
            return

        var p = productByCode[code]
        var price = p ? p.price : 0
        selectedModel.append({
            isAddon: false, parentCode: 0, code: parseInt(code),
            name: p ? p.name : qsTr("Product %1").arg(code),
            qty: pq, lineTotal: pq * price
        })

        if (!p || !p.addons)
            return
        for (var ai = 0; ai < p.addons.length; ++ai) {
            var a = p.addons[ai]
            var aq = (addonStore[code] && addonStore[code][a.name]) ? addonStore[code][a.name] : 0
            if (aq > 0)
                selectedModel.append({
                    isAddon: true, parentCode: parseInt(code), code: 0,
                    name: a.name, qty: aq, lineTotal: aq * a.price
                })
        }
    }

    // Actualizează marcajul de adaosuri dintr-un rând de produs (dacă e vizibil acum).
    function refreshRowAddonCount(code) {
        for (var i = 0; i < productsModel.count; ++i) {
            if (productsModel.get(i).code === code) {
                productsModel.setProperty(i, "addonCount", addonCountFor(code))
                break
            }
        }
    }

    // Cantitatea minimă permisă pentru un produs - ce a fost deja confirmat în
    // Oracle, dacă edităm o comandă reală (sub asta, "-" n-are ce face, vezi
    // sentQtyStore mai sus).
    function floorFor(code) {
        return (root.sentNrComand > 0 && root.sentQtyStore[code]) ? root.sentQtyStore[code] : 0
    }

    // Modifică cantitatea unui produs. La 0, îi eliminăm și adaosurile.
    function adjustQty(code, delta) {
        var oldQty = qtyStore[code] ? qtyStore[code] : 0
        var newQty = oldQty + delta
        var floor = root.floorFor(code)
        if (newQty < floor) newQty = floor
        if (newQty < 0) newQty = 0
        if (newQty === oldQty) return

        qtyStore[code] = newQty
        if (newQty === 0 && addonStore[code])
            delete addonStore[code]

        for (var i = 0; i < productsModel.count; ++i) {
            if (productsModel.get(i).code === code) {
                productsModel.setProperty(i, "qty", newQty)
                productsModel.setProperty(i, "addonCount", addonCountFor(code))
                break
            }
        }

        recomputeTotals()
        rebuildSelectedModel()
    }

    // Construiește lista de adaosuri a unui produs (cu cantitățile curente) pentru AddonSheet.
    function addonListFor(code) {
        var list = []
        var p = productByCode[code]
        if (!p || !p.addons)
            return list
        for (var ai = 0; ai < p.addons.length; ++ai) {
            var a = p.addons[ai]
            var cur = (addonStore[code] && addonStore[code][a.name])
                ? addonStore[code][a.name] : 0
            list.push({ name: a.name, price: a.price, qty: cur })
        }
        return list
    }

    // Modifică cantitatea unui adaos legat de un produs (necesită produsul-părinte prezent).
    function adjustAddon(parentCode, addonName, delta) {
        if ((qtyStore[parentCode] ? qtyStore[parentCode] : 0) <= 0) return
        if (!addonStore[parentCode]) addonStore[parentCode] = {}

        var oldQty = addonStore[parentCode][addonName] ? addonStore[parentCode][addonName] : 0
        var newQty = oldQty + delta
        if (newQty < 0) newQty = 0
        if (newQty === oldQty) return

        addonStore[parentCode][addonName] = newQty

        refreshRowAddonCount(parentCode)
        recomputeTotals()
        rebuildSelectedModel()
    }

    // Liniile de trimis la add_order_lines: doar produsele-părinte (cod +
    // cantitate). Adaosurile nu sunt încă populate în menuData (vezi comentariul
    // de la `menuData` mai sus), deci nu apar aici - de adăugat submit-ul în doi
    // timpi (parentNrord din răspunsul liniilor-părinte) când vin și adaosurile.
    // Cheia din qtyStore E codul trimis (p_product), deci nu mai există niciun
    // pas nume→cod care să poată alege alt produs cu același nume.
    function buildOrderLines() {
        var lines = []
        for (var code in root.qtyStore) {
            var qty = root.qtyStore[code]
            var c = parseInt(code)
            if (qty > 0 && !isNaN(c) && c > 0)
                lines.push({ product: c, qty: qty })
        }
        return lines
    }

    // Liniile de trimis la add_order_lines când actualizăm o comandă deja
    // trimisă: doar diferența față de ce e deja confirmat în Oracle
    // (sentQtyStore) - add_order_line adaugă mereu o linie nouă (alt slot T),
    // nu suprascrie cantitatea unei linii existente, deci trimitem delta, nu
    // cantitatea totală.
    function buildDeltaLines() {
        var lines = []
        for (var code in root.qtyStore) {
            var qty = root.qtyStore[code]
            var floor = root.sentQtyStore[code] ? root.sentQtyStore[code] : 0
            var delta = qty - floor
            var c = parseInt(code)
            if (delta > 0 && !isNaN(c) && c > 0)
                lines.push({ product: c, qty: delta })
        }
        return lines
    }

    // Păstrează comanda în OrdersStore (cache local, citit de TablesPage pentru
    // gardarea "editable") și închide pagina. Folosit atât după o trimitere/
    // actualizare reală reușită, cât și pentru editarea comenzilor locale vechi
    // fără nr_comand cunoscut (vezi submitOrder).
    function finishSubmit() {
        // Ce e în qtyStore chiar acum devine noul prag (sentQtyStore) - corect
        // atât după o creare/trimitere reușită, cât și după o editare
        // local-only (fallback fără nr_comand cunoscut).
        root.sentQtyStore = JSON.parse(JSON.stringify(root.qtyStore))
        OrdersStore.submitOrder(
            root.zone,
            root.tableNumber,
            root.qtyStore,
            root.addonStore,
            root.guestCount,
            root.sentNrComand,
            AppSettings.waiterOficiant
        )
        root.done()
    }

    // Trimite liniile noi (delta) pentru comanda curentă, dacă există, altfel
    // termină direct - pasul comun de după creare/mutare cu succes.
    function sendDeltaOrFinish() {
        var deltaLines = root.buildDeltaLines()
        if (deltaLines.length === 0) {
            root.sending = false
            root.finishSubmit()
            return
        }
        dataService.addOrderLines(String(root.sentNrComand), deltaLines)
    }

    // create_order poate fi respinsă de backend (pg_mobile_web_waiter,
    // blocare DBMS_LOCK pe numărul mesei) dacă alt chelner tocmai a creat o
    // comandă pe aceeași masă chiar înainte de check-ul local de mai jos -
    // arătăm același mesaj prietenos ca la acel check, nu textul brut Oracle
    // (ORA-20061/ORA-20060).
    function friendlyCreateOrderError(error) {
        if (error.indexOf("ORA-20061") !== -1)
            return qsTr("Table %1 was just taken by someone else - pick another table.").arg(root.tableNumber)
        if (error.indexOf("ORA-20060") !== -1)
            return qsTr("Couldn't create the order right now - please try again.")
        return error
    }

    // Traduce eroarea brută Oracle de la update_order_desk (ex. stiva
    // ORA-06512 pe zeci de linii) într-un mesaj clar pentru chelner - vezi
    // și friendlyCreateOrderError mai sus.
    function friendlyUpdateOrderDeskError(error) {
        if (error.indexOf("ORA-20050") !== -1)
            return qsTr("Table %1 already has another open order - pick another table.").arg(root.tableNumber)
        return qsTr("Couldn't move the order right now - please try again.")
    }

    function submitOrder() {
        if (root.sending)
            return

        var tableChanged = root.isEditing
            && (root.zone !== root.originalZone || root.tableNumber !== root.originalTableNumber)
        var guestCountChanged = root.isEditing && root.sentNrComand > 0
            && root.guestCount !== root.sentGuestCount

        if (root.isEditing && root.sentNrComand > 0) {
            // Comandă reală, cunoscută - orice schimbare merge direct în
            // Oracle; cache-ul local (OrdersStore) se actualizează abia după
            // ce Oracle confirmă, ca să nu rămână niciodată în urma realității
            // (exact ce producea "Not editable here yet" înainte: masa se
            // muta doar local, DESK-ul real rămânea neschimbat). Ordinea nu
            // contează funcțional (fiecare pas e independent) - guestCount
            // primul doar ca să respectăm ordinea firească a formularului.
            root.sendError = ""
            root.sending = true
            if (guestCountChanged) {
                dataService.updateGuestCount(String(root.sentNrComand), String(root.guestCount))
            } else if (tableChanged) {
                dataService.updateOrderDesk(String(root.sentNrComand), String(root.tableNumber))
            } else {
                root.sendDeltaOrFinish()
            }
            return
        }

        if (root.isEditing) {
            // Nu avem numărul real de comandă (comandă locală veche, dinainte
            // de acest tracking) - rămâne doar local, ca înainte.
            if (tableChanged) {
                var moved = OrdersStore.moveOrder(root.originalZone, root.originalTableNumber,
                                                   root.zone, root.tableNumber)
                if (!moved)
                    return
                root.originalZone = root.zone
                root.originalTableNumber = root.tableNumber
            }
            root.finishSubmit()
            return
        }

        // Ultima barieră înainte de create_order: SelectTablePage deja a blocat
        // mesele ocupate la alegere, dar dacă masa a fost luată de altcineva
        // exact cât ai completat comanda, tot nu trimitem un al doilea
        // create_order pe aceeași masă - vezi discuția despre comenzile duble
        // de pe Masa 8. Citim tableOccupancy (toți chelnerii), NU openOrders -
        // acela e filtrat de TablesPage pe "Ale mele"/"Toate" și ar rata
        // mesele luate de alți chelneri când "Ale mele" era tab-ul activ.
        var openRows = dataService.tableOccupancy
        for (var oi = 0; oi < openRows.length; ++oi) {
            var orow = openRows[oi]
            var hasDesk = orow.DESK !== undefined && orow.DESK !== null && String(orow.DESK).trim() !== ""
            if (!hasDesk || parseInt(orow.DESK) !== root.tableNumber)
                continue
            var owner = orow.CLCOFICIANTT ? String(orow.CLCOFICIANTT).trim() : ""
            root.showSendError(owner
                ? qsTr("Table %1 was just taken by %2 - pick another table.").arg(root.tableNumber).arg(owner)
                : qsTr("Table %1 was just taken by someone else - pick another table.").arg(root.tableNumber))
            return
        }

        root.sendError = ""
        root.sending = true
        dataService.createOrder(AppSettings.waiterOficiant, root.tableNumber, "", root.guestCount)
    }

    // Comanda salvată e mereu la masa originală — o mutăm doar la trimitere
    // (submitOrder), nu la simpla selecție în picker; ștergerea trebuie să
    // acționeze pe aceeași masă.
    function deleteOrder() {
        if (root.sentNrComand > 0) {
            // Anulăm mai întâi în Oracle (STATE=4) — altfel comanda rămâne
            // deschisă acolo dar dispare din cache-ul local, și la
            // următoarea apăsare pe masă apare dialogul "Încă nu se poate
            // edita aici" (marcată editable:false, pare pornită de pe alt
            // dispozitiv). Golim cache-ul local DOAR după ce Oracle confirmă.
            root.deleteError = ""
            root.deleting = true
            dataService.cancelOrder(String(root.sentNrComand))
        } else {
            // Comandă locală veche, fără nr_comand real reținut (dinainte ca
            // acest tracking să existe) - nu avem ce anula în Oracle.
            OrdersStore.removeOrder(root.isEditing ? root.originalZone : root.zone,
                                     root.isEditing ? root.originalTableNumber : root.tableNumber)
            root.done()
        }
    }

    function buildMenuData(cats, items) {
        var byGrp = ({})
        var byCode = ({})
        var nameMap = ({})

        for (var i = 0; i < items.length; ++i) {
            var it = items[i]
            var grp = parseInt(it.GRP)
            var cod = parseInt(it.COD)
            if (isNaN(cod))
                continue
            var nm = it.DENUMIREA ? String(it.DENUMIREA) : ""
            var prod = {
                name: nm,
                unit: it.UM ? it.UM : "",
                price: parseFloat(it.PRET),
                cod: cod
            }
            if (!byGrp[grp])
                byGrp[grp] = []
            byGrp[grp].push(prod)
            byCode[cod] = prod
            nameMap[nm] = cod
        }

        var built = []
        for (var c = 0; c < cats.length; ++c) {
            var ccod = parseInt(cats[c].COD)
            var list = byGrp[ccod]
            if (!list || list.length === 0)
                continue
            built.push({ cat: cats[c].DENUMIREA, grp: ccod, items: list })
        }

        root.menuData = built
        root.productByCode = byCode
        root.codeOfName = nameMap
    }

    // Reîncearcă încărcarea meniului după o eroare (butonul din overlay) - fără
    // asta, un blip de rețea la deschiderea mesei lăsa ecranul blocat pe
    // "Couldn't load the menu" până ieșeai și intrai din nou.
    function reloadMenu() {
        root.loadError = ""
        dataService.loadCategories()
        dataService.loadMenu(0)
    }

    // Idem pentru liniile comenzii existente. Fără nr_comand n-avem ce cere -
    // nu forțăm awaitingOrderLines, altfel overlay-ul ar rămâne blocat la
    // nesfârșit, fără niciun răspuns care să-l închidă.
    function reloadOrderLines() {
        if (root.sentNrComand <= 0)
            return
        root.linesLoadError = ""
        root.awaitingOrderLines = true
        dataService.loadOrderLines(String(root.sentNrComand))
    }

    // Construim meniul o singură dată, când AMBELE surse au sosit
    // (categorii + produse vin prin semnale separate).
    function tryBuildMenu() {
        if (root.menuReady)
            return
        var cats = dataService.categories
        var items = dataService.menu
        if (cats.length === 0 || items.length === 0)
            return

        buildMenuData(cats, items)
        root.menuReady = true
        root.setupAfterMenu()
    }

    // Rulează după ce meniul e gata: reîncarcă o comandă existentă și
    // populează categoria curentă. Dacă știm nr_comand-ul real, produsele
    // pornesc de la Oracle (get_order_lines), nu de la cache-ul local, care
    // poate fi depășit (ex. comandă achitată direct din UAMenu).
    function setupAfterMenu() {
        var existing = OrdersStore ? OrdersStore.itemsFor(root.zone, root.tableNumber) : ({})
        var hasExisting = false
        for (var name in existing) { hasExisting = true; break }

        if (hasExisting) {
            root.isEditing = true
            root.originalZone = root.zone
            root.originalTableNumber = root.tableNumber
            root.guestCount = OrdersStore.guestsFor(root.zone, root.tableNumber)
            root.sentGuestCount = root.guestCount

            root.addonStore = root.migrateLegacyAddons(
                OrdersStore.addonsFor(root.zone, root.tableNumber))

            var nrComand = OrdersStore.nrComandFor(root.zone, root.tableNumber)
            if (nrComand > 0) {
                root.sentNrComand = nrComand
                root.awaitingOrderLines = true
                dataService.loadOrderLines(String(nrComand))
            } else {
                // Comandă locală veche, fără nr_comand reținut - păstrăm
                // comportamentul dinainte (doar cache local, fără sincronizare).
                root.qtyStore = root.migrateLegacyQty(existing)
                // Ce era deja salvat local e punctul de plecare, nu o
                // modificare - altfel hasUnsavedChanges() ar da true imediat
                // la deschidere și back-ul ar cere confirmare degeaba.
                // (floorFor rămâne 0 aici: e păzit de sentNrComand > 0.)
                root.sentQtyStore = JSON.parse(JSON.stringify(root.qtyStore))
                recomputeTotals()
            }
        }

        if (root.currentCategory >= root.menuData.length)
            root.currentCategory = 0
        populateCategory(currentCategory)
        rebuildSelectedModel()
    }

    // Comenzile locale salvate ÎNAINTE de trecerea pe cod aveau numele
    // produsului drept cheie. Le convertim o singură dată, la deschidere. Ce nu
    // se mai regăsește în meniu se pierde - best-effort intenționat: un cod
    // ghicit ar însemna alt produs trimis la bucătărie. Contează doar pentru
    // comenzile locale fără nr_comand; cele reale sunt oricum rescrise din
    // Oracle de applyServerLines de mai jos.
    function migrateLegacyQty(map) {
        var out = ({})
        for (var key in map) {
            var code = root.codeForStoredKey(key)
            if (code !== undefined)
                out[code] = map[key]
        }
        return out
    }

    function migrateLegacyAddons(map) {
        var out = ({})
        for (var key in map) {
            var code = root.codeForStoredKey(key)
            if (code === undefined)
                continue
            out[code] = ({})
            for (var an in map[key])
                out[code][an] = map[key][an]
        }
        return out
    }

    // O cheie salvată e fie deja un cod (format nou), fie un nume de produs
    // (format vechi). Numele de produse nu sunt numere întregi, deci testul
    // e lipsit de ambiguitate în practică.
    function codeForStoredKey(key) {
        var asCode = parseInt(key)
        if (!isNaN(asCode) && String(asCode) === String(key))
            return asCode
        return root.codeOfName[key]
    }

    // Rulează când sosesc liniile reale ale comenzii (get_order_lines) -
    // devin noul prag (sentQtyStore) și punctul de plecare pentru editare,
    // înlocuind orice presupunere locală anterioară.
    //
    // Cheia e BLIUDA (codul), nu CLCBLIUDAT (numele): numele din linie e un
    // instantaneu de la momentul comenzii și poate să nu mai corespundă
    // meniului de azi - pe test, codul 2132 e "Calmar uscat" în linii vechi și
    // "Calmari uscati" în meniu. Pe nume, o astfel de linie nu se regăsea în
    // meniu, deci dispărea din rezumat și din total.
    function applyServerLines(rows) {
        var qty = {}
        for (var i = 0; i < rows.length; ++i) {
            var r = rows[i]
            var code = parseInt(r.BLIUDA)
            if (isNaN(code) || code <= 0) continue
            var q = parseFloat(r.CANT)
            if (isNaN(q)) continue
            qty[code] = (qty[code] ? qty[code] : 0) + q

            // Produs care chiar nu mai e în meniul curent: îl înregistrăm din
            // însuși răspunsul Oracle, ca linia să rămână vizibilă și numărată.
            // clcbliudat/clcprett sunt numele și prețul de pe bon.
            if (!root.productByCode[code]) {
                var pr = parseFloat(r.CLCPRETT)
                root.productByCode[code] = {
                    name: r.CLCBLIUDAT ? String(r.CLCBLIUDAT).trim()
                                       : qsTr("Product %1").arg(code),
                    unit: r.CLCUMT ? String(r.CLCUMT).trim() : "",
                    price: isNaN(pr) ? 0 : pr,
                    cod: code
                }
            }
        }
        root.sentQtyStore = qty
        root.qtyStore = JSON.parse(JSON.stringify(qty))
        recomputeTotals()
        rebuildSelectedModel()
        populateCategory(root.currentCategory)
    }

    Connections {
        target: dataService

        function onMenuChanged() { root.tryBuildMenu() }
        function onCategoriesChanged() { root.tryBuildMenu() }
        function onTablesChanged() { root.buildPickerDeskZone(dataService.tables) }
        function onTableOccupancyChanged() { root.buildOccupiedTables(dataService.tableOccupancy) }

        // Liniile reale ale comenzii editate (cerute din setupAfterMenu)
        // tocmai au sosit - devin noul prag/punct de plecare.
        function onOrderLinesChanged() {
            if (root.awaitingOrderLines) {
                root.awaitingOrderLines = false
                root.applyServerLines(dataService.orderLines)
            }
            // Cererea făcută de startPayment(): acum știm exact ce se achită.
            if (root.awaitingPayLines) {
                root.awaitingPayLines = false
                root.openPaymentSheet(dataService.orderLines)
            }
        }

        // create_order a reușit - adăugăm liniile (produsele-părinte). Dacă
        // dintr-un motiv oarecare nu-i nicio linie de trimis, terminăm direct
        // (nu ar trebui să se-ntâmple, butonul de trimitere e activ doar cu
        // orderCount > 0).
        function onOrderCreated(nrComand) {
            if (!root.sending)
                return
            root.sentNrComand = nrComand
            root.sentGuestCount = root.guestCount
            var lines = root.buildOrderLines()
            if (lines.length === 0) {
                root.sending = false
                root.finishSubmit()
                return
            }
            dataService.addOrderLines(String(nrComand), lines)
        }

        function onOrderLinesAdded(nrComand, lines) {
            if (!root.sending)
                return
            root.sentNrComand = nrComand
            root.sending = false
            root.finishSubmit()
        }

        // Masa reală (DESK) tocmai s-a schimbat cu succes în Oracle - abia
        // acum e sigur să mutăm și cache-ul local, altfel el ar putea rămâne
        // pe masa nouă chiar dacă Oracle respinsese mutarea (bonul deja
        // printat, sau masa țintă are altă comandă deschisă).
        function onOrderDeskUpdated(nrComand, desk) {
            if (!root.sending)
                return
            OrdersStore.removeOrder(root.zone, root.tableNumber)
            OrdersStore.moveOrder(root.originalZone, root.originalTableNumber,
                                   root.zone, root.tableNumber)
            root.originalZone = root.zone
            root.originalTableNumber = root.tableNumber
            root.sendDeltaOrFinish()
        }

        // update_guest_count a reușit - primul pas al unei actualizări (vezi
        // submitOrder), continuăm cu mutarea mesei (dacă s-a schimbat și ea)
        // sau direct cu liniile de produse.
        function onOrderGuestCountUpdated(nrComand, guestCount) {
            if (!root.sending)
                return
            root.sentGuestCount = guestCount
            if (root.zone !== root.originalZone || root.tableNumber !== root.originalTableNumber)
                dataService.updateOrderDesk(String(root.sentNrComand), String(root.tableNumber))
            else
                root.sendDeltaOrFinish()
        }

        // cancel_order a reușit — abia acum e sigur să golim cache-ul local
        // (vezi comentariul din deleteOrder despre comenzile "orfane").
        function onOrderCancelled(nrComand) {
            if (!root.deleting)
                return
            root.deleting = false
            OrdersStore.removeOrder(root.isEditing ? root.originalZone : root.zone,
                                     root.isEditing ? root.originalTableNumber : root.tableNumber)
            root.done()
        }

        function onRequestFailed(command, error) {
            if (command === "get_menu" || command === "get_categories") {
                root.loadError = error
                return
            }
            if (command === "get_order_lines" && (root.awaitingOrderLines || root.awaitingPayLines)) {
                root.awaitingOrderLines = false
                // Fără asta, o cerere eșuată chiar înainte de achitare ar lăsa
                // steagul ridicat: dialogul de plată n-ar mai apărea niciodată,
                // iar butonul ar părea mort.
                if (root.awaitingPayLines) {
                    root.awaitingPayLines = false
                    root.showPayError(qsTr("Couldn't read the order before paying: %1").arg(error))
                    return
                }
                root.linesLoadError = error
                return
            }
            if (root.sending && (command === "create_order" || command === "add_order_lines" || command === "update_order_desk" || command === "update_guest_count")) {
                root.sending = false
                if (command === "create_order") {
                    root.showSendError(root.friendlyCreateOrderError(error))
                } else if (command === "update_order_desk") {
                    // Mesajul se compune ÎNAINTE de reset: el numește masa
                    // ȚINTĂ ("Masa %1 are deja altă comandă"), deci are nevoie
                    // de root.tableNumber așa cum l-a ales chelnerul.
                    var deskError = root.friendlyUpdateOrderDeskError(error)
                    // Abia apoi revenim la masa reală - mutarea a fost respinsă
                    // de Oracle, deci afișarea trebuie să rămână pe cea
                    // originală, nu pe ținta neconfirmată din ChangeTablePicker.
                    root.zone = root.originalZone
                    root.tableNumber = root.originalTableNumber
                    root.showSendError(deskError)
                } else {
                    root.showSendError(error)
                }
                return
            }
            if (root.deleting && command === "cancel_order") {
                root.deleting = false
                root.showDeleteError(error)
            }
            // "pay_order" lipsește intenționat: eșecurile lui sunt tratate de
            // paymentController (care le reia de câteva ori) și ajung aici prin
            // paymentFailed. Tratate și pe acest canal, ar apărea două dialoguri
            // pentru aceeași problemă, dintre care unul cu text brut Oracle.
        }
    }

    // Rezultatul achitării. Controller-ul face toată orchestrarea (bon fiscal,
    // apoi închiderea comenzii); ecranul doar reacționează.
    Connections {
        target: paymentController

        function onPaymentSucceeded(nrComand) {
            if (nrComand !== root.sentNrComand)
                return
            root.orderClosedByPayment = true
            root.finishPaymentIfDone()
        }

        function onPaymentFailed(reason) {
            root.showPayError(reason)
        }

        // Vânzarea E finalizată, doar hârtia a lipsit. Oferim RETIPĂRIREA, nu
        // reluarea plății: o a doua emitere ar scoate un al doilea bon fiscal.
        function onPrintNeedsReprint(documentNumber, reason) {
            root.reprintDoc = documentNumber
            root.payError = reason
            reprintDialog.open()
        }

        function onPrintConfirmed() {
            root.finishPaymentIfDone()
        }
    }

    Component.onCompleted: {
        // Cerem tot meniul dintr-o dată (categorie 0 = tot), plus dicționarul
        // de categorii. tryBuildMenu le îmbină când amândouă sosesc.
        dataService.loadCategories()
        dataService.loadMenu(0)
        dataService.loadTables()
        dataService.loadTableOccupancy()
    }

    background: Rectangle {
        color: Theme.background
    }

    // ---------- Header ----------
    header: Rectangle {
        color: Theme.surface
        height: 60

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 16

            Components.BackButton {
                color: Theme.textPrimary
                onClicked: root.requestBack()
            }

            Item { Layout.preferredWidth: 8 }

            ColumnLayout {
                spacing: 0

                // Numele mesei e apăsabil (deschide ChangeTablePicker) mereu —
                // fie că trimiți o comandă nouă, fie că editezi una deja
                // trimisă pe masa greșită. Fără indiciu vizual (culoare/iconiță)
                // la cerere — doar textul simplu, ca înainte.
                Item {
                    implicitWidth: tableNameLabel.implicitWidth
                    implicitHeight: tableNameLabel.implicitHeight

                    Label {
                        id: tableNameLabel
                        text: qsTr("Table %1").arg(root.tableNumber)
                        font.pixelSize: 18 * Theme.fontScale
                        font.bold: true
                        color: Theme.textPrimary
                    }

                    Components.TouchArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        veilRadius: 8
                        // Qt.callLater, nu apel direct: deschiderea acestui
                        // Popup imediat după ce alt Popup modal (ex.
                        // sendErrorDialog) tocmai s-a închis poate lăsa
                        // sheet-ul "deschis" dar invizibil (focus/overlay
                        // rămas de la popup-ul anterior) - amânăm o
                        // iterație de event loop ca să se termine curățenia.
                        onClicked: Qt.callLater(tablePicker.openWith, root.zone, root.tableNumber)
                    }
                }

                Label {
                    text: root.zoneLabel()
                    font.pixelSize: 12 * Theme.fontScale
                    color: Theme.textSecondary
                }
            }

            Item { Layout.fillWidth: true }

            Label {
                text: qsTr("%1 MDL").arg(Format.amount(root.orderTotal))
                font.pixelSize: 18 * Theme.fontScale
                font.bold: true
                color: Theme.primary
            }
        }
    }

    // ---------- Conținut ----------
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Chips de categorii + lupă. Cât timp cauți, bara de căutare ia locul
        // tab-urilor (nu avem loc pentru amândouă) — căutarea acoperă tot
        // meniul, nu doar categoria curentă, ca să nu mai trebuiască ghicit
        // în ce categorie e produsul.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 56

            ListView {
                id: categoryList
                visible: !root.searchActive
                anchors.left: parent.left
                anchors.right: searchButton.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                height: 36
                orientation: ListView.Horizontal
                spacing: 8
                leftMargin: 16
                clip: true
                model: root.menuData

                delegate: Rectangle {
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    height: 36
                    width: catLabel.implicitWidth + 32
                    radius: 18
                    color: index === root.currentCategory ? Theme.primary : Theme.surface
                    border.width: 1
                    border.color: index === root.currentCategory ? Theme.primary : Theme.border

                    Label {
                        id: catLabel
                        anchors.centerIn: parent
                        text: modelData.cat
                        font.pixelSize: 14 * Theme.fontScale
                        color: index === root.currentCategory ? "white" : Theme.textPrimary
                    }

                    Components.TouchArea {
                        anchors.fill: parent
                        onClicked: {
                            root.currentCategory = index
                            root.populateCategory(index)
                            // Schimbarea grupei = alt context; pliem rezumatul.
                            root.summaryExpanded = false
                        }
                    }
                }
            }

            Rectangle {
                id: searchButton
                visible: !root.searchActive
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 36; height: 36; radius: 18
                color: Theme.keyBackground

                Icons.IconSearch {
                    anchors.centerIn: parent
                    color: Theme.textSecondary
                }

                Components.TouchArea {
                    anchors.fill: parent
                    onClicked: {
                        root.searchActive = true
                        searchField.forceActiveFocus()
                        // Deschidem căutarea = alt context; pliem rezumatul.
                        root.summaryExpanded = false
                    }
                }
            }

            Rectangle {
                visible: root.searchActive
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                height: 36
                radius: 18
                color: Theme.surface
                border.width: 1
                border.color: Theme.primary

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 8

                    Icons.IconSearch {
                        Layout.alignment: Qt.AlignVCenter
                        color: Theme.textSecondary
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        font.pixelSize: 14 * Theme.fontScale
                        color: Theme.textPrimary
                        placeholderText: qsTr("Search products…")
                        placeholderTextColor: Theme.textSecondary
                        selectByMouse: true
                        background: null
                        topPadding: 0
                        bottomPadding: 0
                        onTextChanged: {
                            root.searchQuery = text
                            searchDebounce.restart()
                        }

                        // Rescanarea întregului meniu la fiecare literă tastată e
                        // inutilă pentru un meniu mare - amânăm căutarea propriu-zisă
                        // până când utilizatorul se oprește din tastat 150ms.
                        Timer {
                            id: searchDebounce
                            interval: 150
                            onTriggered: {
                                if (searchField.text.trim() === "")
                                    root.populateCategory(root.currentCategory)
                                else
                                    root.applySearch(searchField.text)
                            }
                        }
                    }

                    Item {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter

                        Icons.IconClose {
                            anchors.centerIn: parent
                            color: Theme.textSecondary
                        }

                        Components.TouchArea {
                            anchors.fill: parent
                            circular: true
                            onClicked: {
                                searchDebounce.stop()
                                searchField.text = ""
                                root.searchActive = false
                                root.searchQuery = ""
                                root.populateCategory(root.currentCategory)
                                // Ascunderea câmpului nu închide singură tastatura pe Android -
                                // trebuie să-i luăm explicit focusul și să cerem input panel-ului să dispară.
                                searchField.focus = false
                                Qt.inputMethod.hide()
                            }
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        // Lista de produse (+ mesaj când căutarea nu găsește niciun produs)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Stare goală: căutare activă, cu text tastat, dar zero rezultate -
            // ca să știe chelnerul clar că produsul nu există în meniu.
            Label {
                anchors.centerIn: parent
                width: parent.width - 48
                visible: root.searchActive && root.searchQuery.trim() !== "" && productsModel.count === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: qsTr("No product found for “%1”.").arg(root.searchQuery.trim())
                font.pixelSize: 15 * Theme.fontScale
                color: Theme.textSecondary
            }

        ListView {
            anchors.fill: parent
            clip: true
            model: ListModel { id: productsModel }

            // Când chelnerul începe să deruleze lista (ca să vadă mai multe
            // produse), ascundem tastatura ȘI pliem rezumatul "Comandă curentă"
            // - amândouă eliberează ecranul pentru răsfoit. onMovementStarted
            // prinde atât tragerea cu degetul, cât și flick-ul.
            onMovementStarted: {
                root.dismissSearchKeyboard()
                root.summaryExpanded = false
            }

            delegate: Rectangle {
                width: ListView.view.width
                // Înălțimea derivă din conținutul rândului (nume pe 1 sau 2 rânduri),
                // cu un minim pentru rândurile scurte. Important: lățimea curge
                // dinspre rând spre RowLayout (left+right ancorate), iar înălțimea
                // curge invers (din implicitHeight) — fără buclă, ca să se așeze
                // corect din prima, nu abia după un +/−.
                height: Math.max(66, rowLayout.implicitHeight + 20)
                color: Theme.surface

                RowLayout {
                    id: rowLayout
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    spacing: 12

                    ColumnLayout {
                        id: infoColumn
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2
                        // Numele se încadrează pe max 2 rânduri, ca butoanele +/−
                        // să nu fie împinse afară de produsele cu nume lung.
                        Label {
                            text: name
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.pixelSize: 15 * Theme.fontScale
                            color: Theme.textPrimary
                        }
                        Label {
                            text: qsTr("%1  ·  %2 MDL").arg(unit).arg(Format.amount(price))
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: 12 * Theme.fontScale
                            color: Theme.textSecondary
                        }

                        // Link "Adaosuri" — apare doar la produsele cu adaosuri, după ce
                        // au fost adăugate. Arată câte adaosuri sunt alese.
                        Rectangle {
                            visible: qty > 0 && hasAddons
                            Layout.topMargin: 2
                            implicitWidth: addonLink.implicitWidth + 20
                            implicitHeight: addonLink.implicitHeight + 8
                            radius: height / 2
                            color: addonCount > 0 ? Theme.primary : "transparent"
                            border.width: 1
                            border.color: Theme.primary

                            Label {
                                id: addonLink
                                anchors.centerIn: parent
                                text: addonCount > 0
                                    ? qsTr("Add-ons · %1").arg(addonCount)
                                    : qsTr("Add-ons")
                                font.pixelSize: 12 * Theme.fontScale
                                font.bold: true
                                color: addonCount > 0 ? "white" : Theme.primary
                            }

                            Components.TouchArea {
                                anchors.fill: parent
                                onClicked: addonSheet.openWith(code, name, root.addonListFor(code))
                            }
                        }
                    }

                    // Cantitatea curentă (dacă > 0) + controale
                    Label {
                        visible: qty > 0
                        text: qty
                        font.pixelSize: 15 * Theme.fontScale
                        font.bold: true
                        color: Theme.textPrimary
                        Layout.preferredWidth: 22
                        Layout.alignment: Qt.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // Buton minus (doar când există cantitate; estompat/inactiv
                    // dacă am ajuns la ce e deja trimis în Oracle - nu putem
                    // șterge o linie deja trimisă din acest ecran).
                    Rectangle {
                        visible: qty > 0
                        Layout.alignment: Qt.AlignVCenter
                        width: 34; height: 34; radius: 17
                        color: Theme.keyBackground
                        opacity: qty > root.floorFor(code) ? 1 : 0.35
                        Icons.IconMinus {
                            anchors.centerIn: parent
                            color: Theme.textPrimary
                        }
                        Components.TouchArea {
                            anchors.fill: parent
                            enabled: qty > root.floorFor(code)
                            onClicked: root.adjustQty(code, -1)
                        }
                    }

                    // Buton plus
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        width: 34; height: 34; radius: 17
                        color: Theme.primary
                        Icons.IconPlus {
                            anchors.centerIn: parent
                            color: "white"
                        }
                        Components.TouchArea {
                            anchors.fill: parent
                            onClicked: {
                                // Am găsit produsul și l-am adăugat - ascundem
                                // tastatura (dacă mai era deschisă din căutare)
                                // și deschidem rezumatul "Comandă curentă", ca
                                // chelnerul să vadă pe loc ce a adăugat.
                                root.dismissSearchKeyboard()
                                root.adjustQty(code, 1)
                                root.summaryExpanded = true
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Theme.border
                }
            }
        }
        }

        // Panou "Comandă curentă" — rezumatul produselor deja selectate, ca
        // chelnerul să poată revedea comanda cu clientul înainte de trimitere.
        Rectangle {
            id: summaryPanel
            Layout.fillWidth: true
            Layout.preferredHeight: root.summaryExpanded
                ? 48 + Math.min(selectedModel.count, root.summaryMaxRows) * 44
                : 48
            color: Theme.surface
            clip: true

            Behavior on Layout.preferredHeight { NumberAnimation { duration: 120 } }

            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.border }

            ListModel { id: selectedModel }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 10

                        // Selector oaspeți (butoane proprii, minim 1).
                        RowLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 6

                            Icons.IconPerson {
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                color: Theme.textSecondary
                            }

                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: Theme.keyBackground
                                opacity: root.guestCount > 1 ? 1 : 0.4
                                Icons.IconMinus { anchors.centerIn: parent; color: Theme.textPrimary }
                                Components.TouchArea {
                                    anchors.fill: parent
                                    onClicked: if (root.guestCount > 1) root.guestCount -= 1
                                }
                            }

                            Label {
                                text: root.guestCount
                                Layout.preferredWidth: 16
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: 15 * Theme.fontScale
                                font.bold: true
                                color: Theme.textPrimary
                            }

                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: Theme.primary
                                // Estompat la plafon, exact ca "−" la minim -
                                // altfel butonul pare stricat, nu limitat.
                                opacity: root.guestCount < root.maxGuests ? 1 : 0.4
                                Icons.IconPlus { anchors.centerIn: parent; color: "white" }
                                Components.TouchArea {
                                    anchors.fill: parent
                                    enabled: root.guestCount < root.maxGuests
                                    onClicked: root.guestCount += 1
                                }
                            }
                        }

                        // Zonă de extindere (rezumat produse) — MouseArea proprie,
                        // separată de butoanele de oaspeți ca să nu se suprapună.
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            RowLayout {
                                anchors.fill: parent
                                spacing: 8

                                Label {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignRight
                                    text: root.orderCount > 0
                                        ? qsTr("%1 products selected").arg(root.orderCount)
                                        : qsTr("No products selected")
                                    font.pixelSize: 14 * Theme.fontScale
                                    font.bold: true
                                    color: Theme.textPrimary
                                    elide: Text.ElideRight
                                }

                                Icons.IconChevron {
                                    Layout.alignment: Qt.AlignVCenter
                                    color: Theme.textSecondary
                                    expanded: root.summaryExpanded
                                }
                            }

                            Components.TouchArea {
                                anchors.fill: parent
                                enabled: root.orderCount > 0
                                onClicked: root.summaryExpanded = !root.summaryExpanded
                            }
                        }
                    }
                }

                ListView {
                    visible: root.summaryExpanded
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(selectedModel.count, root.summaryMaxRows) * 44
                    clip: true
                    model: selectedModel

                    // Ca la lista de produse: la derularea rezumatului comenzii
                    // ascundem tastatura (dacă mai era deschisă din căutare).
                    onMovementStarted: root.dismissSearchKeyboard()

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 44
                        color: Theme.surface

                        RowLayout {
                            anchors.fill: parent
                            // Adaosurile sunt indentate față de produsul-părinte.
                            anchors.leftMargin: isAddon ? 32 : 16
                            anchors.rightMargin: 16
                            spacing: 8

                            // Marcaj vizual pentru adaos (liniuță).
                            Label {
                                visible: isAddon
                                text: "+"
                                font.pixelSize: 14 * Theme.fontScale
                                color: Theme.textSecondary
                            }

                            Label {
                                text: name
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: (isAddon ? 13 : 14) * Theme.fontScale
                                color: isAddon ? Theme.textSecondary : Theme.textPrimary
                            }

                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: Theme.keyBackground
                                opacity: (isAddon || qty > root.floorFor(code)) ? 1 : 0.35
                                Icons.IconMinus { anchors.centerIn: parent; color: Theme.textPrimary }
                                Components.TouchArea {
                                    anchors.fill: parent
                                    enabled: isAddon || qty > root.floorFor(code)
                                    onClicked: isAddon ? root.adjustAddon(parentCode, name, -1) : root.adjustQty(code, -1)
                                }
                            }

                            Label {
                                text: qty
                                Layout.preferredWidth: 18
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: 14 * Theme.fontScale
                                color: Theme.textPrimary
                            }

                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: Theme.primary
                                Icons.IconPlus { anchors.centerIn: parent; color: "white" }
                                Components.TouchArea {
                                    anchors.fill: parent
                                    onClicked: isAddon ? root.adjustAddon(parentCode, name, 1) : root.adjustQty(code, 1)
                                }
                            }

                            Label {
                                text: qsTr("%1 MDL").arg(Format.amount(lineTotal))
                                horizontalAlignment: Text.AlignRight
                                font.pixelSize: 14 * Theme.fontScale
                                font.bold: !isAddon
                                color: isAddon ? Theme.textSecondary : Theme.textPrimary
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: Theme.border
                        }
                    }
                }
            }
        }


        // Bara de jos — ștergere (doar la editare) + trimite comanda
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            color: Theme.surface

            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.border }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                // Meniul comenzii (achitare / ștergere). Înainte era direct un
                // buton de ștergere; odată cu achitarea sunt două acțiuni, iar
                // cea distructivă nu mai merită locul cel mai la îndemână.
                Rectangle {
                    visible: root.isEditing
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    radius: 24
                    color: "transparent"
                    opacity: (root.deleting || root.paying) ? 0.5 : 1
                    border.width: 1.5
                    border.color: Theme.border

                    Icons.IconHamburger {
                        anchors.centerIn: parent
                        color: Theme.textPrimary
                    }

                    Components.TouchArea {
                        anchors.fill: parent
                        enabled: !root.deleting && !root.paying
                        onClicked: actionSheet.open()
                    }
                }

                // Butonul principal — trimite comanda.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: 24
                    color: (root.orderCount > 0 && !root.sending && !root.paying) ? Theme.primary : Theme.border

                    Label {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: root.paying
                            ? qsTr("Paying…")
                            : root.sending
                            ? qsTr("Sending…")
                            : (root.orderCount > 0
                                ? (root.isEditing
                                    ? qsTr("Update order · %1 · %2 MDL").arg(root.orderCount).arg(Format.amount(root.orderTotal))
                                    : qsTr("Send order · %1 · %2 MDL").arg(root.orderCount).arg(Format.amount(root.orderTotal)))
                                : qsTr("Add products"))
                        font.pixelSize: 15 * Theme.fontScale
                        font.bold: true
                        color: (root.orderCount > 0 && !root.sending && !root.paying) ? "white" : Theme.textSecondary
                        // Textul lung se micșorează ca să încapă în buton, în loc să iasă pe margini.
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 10
                        elide: Text.ElideRight
                    }

                    Components.TouchArea {
                        anchors.fill: parent
                        enabled: root.orderCount > 0 && !root.sending && !root.paying
                        onClicked: root.submitOrder()
                    }
                }
            }
        }
    }

    // Stare de încărcare / eroare peste zona de conținut, până sosește meniul.
    Components.LoadingOverlay {
        anchors.fill: parent
        loading: !root.menuReady && root.loadError === ""
        errorText: (!root.menuReady && root.loadError !== "")
            ? qsTr("Couldn't load the menu:\n%1").arg(root.loadError)
            : ""
        loadingText: qsTr("Loading menu…")
        retryText: qsTr("Retry")
        onRetryRequested: root.reloadMenu()
    }

    // Stare de încărcare / eroare pentru liniile reale ale comenzii editate
    // (get_order_lines) - separată de starea meniului de mai sus. Blocant:
    // vezi comentariul din LoadingOverlay despre produsele adăugate care se
    // pierdeau când răspunsul sosea peste ele.
    Components.LoadingOverlay {
        anchors.fill: parent
        loading: root.menuReady && root.awaitingOrderLines
        errorText: (root.menuReady && root.linesLoadError !== "")
            ? qsTr("Couldn't load the existing order:\n%1").arg(root.linesLoadError)
            : ""
        loadingText: qsTr("Loading order…")
        retryText: qsTr("Retry")
        onRetryRequested: root.reloadOrderLines()
    }

    Components.ConfirmDialog {
        id: deleteDialog
        title: qsTr("Delete order?")
        // Ștergerea acționează mereu pe masa originală (vezi deleteOrder), nu
        // pe o selecție nesalvată din ChangeTablePicker — mesajul trebuie să
        // reflecte aceeași masă.
        message: qsTr("The order for %1 will be removed.").arg(
            qsTr("Table %1").arg(root.isEditing ? root.originalTableNumber : root.tableNumber))
        confirmText: qsTr("Delete")
        destructive: true
        onConfirmed: root.deleteOrder()
    }

    // Eroare la trimiterea reală a comenzii (create_order/add_order_lines/
    // update_order_desk) - dialog, nu banner inline, ca să nu fie ratată
    // (schimbă complet ce trebuie să facă chelnerul, ex. alege altă masă).
    // Confirmare la părăsirea unei comenzi cu modificări netrimise (vezi
    // requestBack). Ștergerea unei comenzi cerea confirmare, dar abandonarea
    // uneia în lucru nu - deși pierde exact aceleași produse.
    Components.ConfirmDialog {
        id: discardDialog
        title: root.isEditing ? qsTr("Discard the changes?") : qsTr("Discard the order?")
        message: root.isEditing
            ? qsTr("The changes made here haven't been sent. If you leave now, they are lost.")
            : qsTr("The products added here haven't been sent. If you leave now, they are lost.")
        confirmText: qsTr("Leave")
        cancelText: qsTr("Stay")
        destructive: true
        onConfirmed: root.StackView.view.pop()
    }

    Components.ConfirmDialog {
        id: sendErrorDialog
        title: qsTr("Couldn't send the order")
        message: root.sendError
        confirmText: qsTr("OK")
        infoOnly: true
    }

    Components.ConfirmDialog {
        id: payErrorDialog
        title: qsTr("Payment failed")
        message: root.payError
        confirmText: qsTr("OK")
        infoOnly: true
    }

    // Bonul e emis (banii sunt încasați), dar nu a ieșit pe hârtie. Singura
    // acțiune corectă e retipărirea aceluiași document - de-aceea nu există
    // aici nicio variantă de "reia plata".
    Components.ConfirmDialog {
        id: reprintDialog
        title: qsTr("Receipt not printed")
        message: qsTr("The payment went through, but the receipt didn't print: %1").arg(root.payError)
        confirmText: qsTr("Print again")
        cancelText: qsTr("Skip")
        onConfirmed: paymentController.reprint()
        // Chiar dacă renunță la hârtie, vânzarea rămâne finalizată - nu are
        // rost să ținem ecranul deschis pe o comandă deja închisă.
        onCancelled: root.finishPaymentIfDone()
    }

    Components.OrderActionSheet {
        id: actionSheet
        canPay: root.sentNrComand > 0 && !root.hasUnsavedChanges()
        payBlockedReason: root.sentNrComand <= 0
            ? qsTr("This order isn't in the system yet.")
            : qsTr("Send the changes first - the receipt must match the order.")
        onPayRequested: root.startPayment()
        onDeleteRequested: deleteDialog.open()
    }

    Components.PaymentSheet {
        id: paymentSheet
        onPayRequested: root.pay(method, received)
    }

    Components.ConfirmDialog {
        id: deleteErrorDialog
        title: qsTr("Couldn't delete the order")
        message: root.deleteError
        confirmText: qsTr("OK")
        infoOnly: true
    }

    // Sheet de jos pentru alegerea adaosurilor unui produs (vezi components/AddonSheet.qml).
    Components.AddonSheet {
        id: addonSheet
        onAddonAdjusted: root.adjustAddon(addonSheet.productCode, addonName, delta)
    }

    // Sheet de jos pentru mutarea comenzii pe altă masă/zonă (vezi
    // components/ChangeTablePicker.qml) — doar afișare/selecție locală;
    // mutarea reală în OrdersStore are loc abia la "Actualizează comanda".
    Components.ChangeTablePicker {
        id: tablePicker
        occupiedByDesk: root.occupiedByDesk
        hallTables: root.pickerHallTables
        terraceTables: root.pickerTerraceTables
        onTableSelected: function(zone, tableNumber) {
            root.zone = zone
            root.tableNumber = tableNumber
        }
    }
}

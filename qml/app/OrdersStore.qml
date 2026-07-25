pragma Singleton
import QtQuick 2.15
import Qt.labs.settings 1.0

// Comenzile active pe ACEST dispozitiv (singleton global, accesat ca
// `OrdersStore.submitOrder(...)` — import "../app"). Va fi înlocuit cu
// apeluri reale către Oracle (via PHP) — până atunci, "Trimite comanda"
// scrie aici, iar TablesPage citește de aici (inclusiv marcajul "editable"
// care spune dacă masa poate fi editată pe acest telefon).
//
// Persistat pe disc (nu doar în memorie): fără asta, orice repornire a
// aplicației - rebuild/redeploy, crash, sau Android omorând procesul în
// fundal (frecvent) - pierde marcajul "am creat-o eu" pentru toate mesele
// deschise, iar chelnerul vede fals "Această comandă a fost începută pe alt
// dispozitiv" pentru propriile lui comenzi, pe propriul lui telefon.
QtObject {
    id: root

    // Doar un index căutat după cheie (indexForKey) - nu alimentează nicio
    // listă afișată. Ține strictul necesar per masă deschisă pe acest telefon:
    // cheia, zona, numărul mesei, proprietarul și numărul de oaspeți.
    property ListModel ordersModel: ListModel {}

    // Produsele comandate per masă: { tableKey: { codProdus: cantitate } },
    // separat de ordersModel ca să putem reîncărca o comandă existentă în
    // OrderPage la editare. Cheia interioară e COD-ul (vms_bliuda.cod), nu
    // numele - vezi productByCode din OrderPage.qml pentru motiv. Intrările
    // salvate în formatul vechi (pe nume) sunt convertite la deschidere, de
    // OrderPage.migrateLegacyQty.
    property var itemsByKey: ({})
    // Adaosurile per masă: { tableKey: { codProdus: { numeAdaos: cantitate } } }.
    property var addonsByKey: ({})
    // Numărul real de comandă din Oracle (nr_comand) per masă - 0/absent dacă
    // masa are doar o comandă locală veche, dinainte ca acest tracking să
    // existe. Permite lui OrderPage să reîncarce liniile reale (get_order_lines)
    // și să trimită doar diferența la o actualizare, în loc să rămână local-only.
    property var nrComandByKey: ({})

    // Stare serializată (JSON) a tot ce e mai sus - vezi persist()/restoreState().
    property string _persistedJson: ""

    property var _persist: Settings {
        property alias ordersJson: root._persistedJson

        category: "OrdersStore"
    }

    Component.onCompleted: root.restoreState()

    // Adună starea curentă într-un singur string JSON, salvat prin Settings.
    //
    // Se salvează DOAR câmpurile chiar citite de cineva: cheia mesei, zona,
    // numărul mesei, proprietarul și numărul de oaspeți. Tot ce ținea aici
    // înainte despre aspectul cardului (tableName, orderTime, waiterName,
    // orderNo, preview, total, active) era mort: TablesPage își construiește
    // fiecare card exclusiv din răspunsul Oracle (get_open_orders), nu de-aici.
    // Erau date duplicate care se învecheau tăcut față de server.
    function serializeState() {
        var entries = []
        for (var i = 0; i < ordersModel.count; ++i) {
            var e = ordersModel.get(i)
            entries.push({
                tableKey: e.tableKey,
                zone: e.zone,
                tableNumber: e.tableNumber,
                waiterOficiant: e.waiterOficiant,
                guestCount: e.guestCount
            })
        }
        return JSON.stringify({
            entries: entries,
            itemsByKey: itemsByKey,
            addonsByKey: addonsByKey,
            nrComandByKey: nrComandByKey
        })
    }

    // Scrie starea curentă pe disc - apelat după fiecare mutație (submitOrder,
    // removeOrder, pruneMissing, moveOrder), ca nicio schimbare să nu se
    // piardă la o repornire a aplicației.
    function persist() {
        root._persistedJson = root.serializeState()
    }

    // Reface starea salvată la pornirea aplicației (Component.onCompleted).
    function restoreState() {
        if (root._persistedJson === "")
            return
        var state
        try {
            state = JSON.parse(root._persistedJson)
        } catch (e) {
            return
        }
        if (!state)
            return
        root.itemsByKey = state.itemsByKey || ({})
        root.addonsByKey = state.addonsByKey || ({})
        root.nrComandByKey = state.nrComandByKey || ({})
        ordersModel.clear()
        var entries = state.entries || []
        for (var i = 0; i < entries.length; ++i) {
            var e = entries[i]
            // Citim câmp cu câmp, nu `append(e)` direct: o stare salvată de o
            // versiune mai veche a aplicației mai are și câmpurile scoase între
            // timp, iar un append cu ele ar readuce roluri moarte în model.
            // Așa, formatul vechi se citește fără nicio migrare explicită.
            ordersModel.append({
                tableKey: e.tableKey,
                zone: e.zone,
                tableNumber: e.tableNumber,
                // Intrări salvate înainte ca proprietarul să fie reținut: le dăm
                // 0 = "necunoscut", tratat în isEditableBy ca editabil de
                // oricine, ca o actualizare a aplicației să nu blocheze
                // comenzile deja deschise.
                waiterOficiant: e.waiterOficiant !== undefined ? e.waiterOficiant : 0,
                guestCount: e.guestCount !== undefined ? e.guestCount : 1
            })
        }
    }

    function keyFor(zone, tableNumber) {
        return zone + "-" + tableNumber
    }

    function indexForKey(key) {
        for (var i = 0; i < ordersModel.count; ++i) {
            if (ordersModel.get(i).tableKey === key)
                return i
        }
        return -1
    }

    // Produsele salvate pentru o masă (obiect gol dacă nu există comandă deschisă).
    function itemsFor(zone, tableNumber) {
        var key = keyFor(zone, tableNumber)
        return itemsByKey[key] ? itemsByKey[key] : ({})
    }

    // Numărul de oaspeți salvat pentru o masă (1 dacă nu există comandă deschisă).
    function guestsFor(zone, tableNumber) {
        var idx = indexForKey(keyFor(zone, tableNumber))
        return idx >= 0 ? ordersModel.get(idx).guestCount : 1
    }

    // Adaosurile salvate pentru o masă (obiect gol dacă nu există comandă deschisă).
    function addonsFor(zone, tableNumber) {
        var key = keyFor(zone, tableNumber)
        return addonsByKey[key] ? addonsByKey[key] : ({})
    }

    // Numărul real de comandă (nr_comand) salvat pentru o masă - 0 dacă nu-l știm.
    function nrComandFor(zone, tableNumber) {
        var key = keyFor(zone, tableNumber)
        return nrComandByKey[key] ? nrComandByKey[key] : 0
    }

    // Reține (sau înlocuiește) comanda deschisă pentru o masă.
    //
    // nrComand = numărul real din Oracle, dacă e cunoscut la acest punct
    // (0 = necunoscut, caz în care păstrăm ce era deja reținut, ca să nu-l
    // pierdem). waiterOficiant = codul chelnerului care deține comanda pe acest
    // telefon (vezi isEditableBy).
    //
    // Ordinea intrărilor nu contează: nimic nu afișează `ordersModel`, e doar
    // un index căutat după cheie (indexForKey). Înainte exista o inserție
    // ordonată pe zonă, ca antetele de secțiune din TablesPage să iasă bine -
    // dar TablesPage își sortează singur propria listă, construită din
    // răspunsul Oracle, deci sortarea de-aici nu ajungea niciodată pe ecran.
    function submitOrder(zone, tableNumber, itemsMap, addonMap, guestCount, nrComand, waiterOficiant) {
        var key = keyFor(zone, tableNumber)
        var idx = indexForKey(key)

        itemsByKey[key] = itemsMap
        addonsByKey[key] = addonMap
        if (nrComand)
            nrComandByKey[key] = nrComand

        var entry = {
            tableKey: key,
            zone: zone,
            tableNumber: tableNumber,
            waiterOficiant: waiterOficiant ? waiterOficiant : 0,
            guestCount: guestCount
        }

        if (idx >= 0)
            ordersModel.set(idx, entry)
        else
            ordersModel.append(entry)

        root.persist()
    }

    function removeOrder(zone, tableNumber) {
        var key = keyFor(zone, tableNumber)
        var idx = indexForKey(key)
        if (idx >= 0)
            ordersModel.remove(idx)
        delete itemsByKey[key]
        delete addonsByKey[key]
        delete nrComandByKey[key]
        root.persist()
    }

    // Curăță mesele salvate local a căror comandă nu mai e printre comenzile
    // deschise reale din Oracle (get_open_orders) — cazul tipic e o comandă
    // achitată direct din UAMenu, fără nicio acțiune în acest device. Fără
    // asta, OrderPage ar crede la următoarea deschidere a mesei că editează
    // comanda veche (dispărută deja) și ar reîncărca produsele ei stale.
    // openKeys = lista de tableKey-uri active acum, construită de TablesPage
    // din rândurile primite la fiecare refresh.
    //
    // ownerOficiant = chelnerul pe care e FILTRATĂ acea listă (0 = listă
    // nefiltrată, toți chelnerii). Fără el, un refresh pe "Ale mele" ștergea
    // și comenzile altui chelner care a folosit acest telefon: ele nu apar
    // niciodată în răspunsul filtrat pe altcineva, deci păreau dispărute din
    // Oracle. Rezultatul era exact bug-ul pentru care a fost persistat
    // store-ul - Ion dă telefonul lui Vasile, Vasile se loghează, iar la
    // re-logarea lui Ion propriile lui mese apar "începute pe alt dispozitiv".
    function pruneMissing(openKeys, ownerOficiant) {
        var changed = false
        for (var key in itemsByKey) {
            if (openKeys.indexOf(key) !== -1)
                continue

            var idx = indexForKey(key)

            // Lista filtrată nu spune nimic despre comenzile altcuiva - le
            // lăsăm intacte. owner 0 = intrare veche, fără proprietar reținut:
            // tratată ca "a oricui", la fel ca în isEditableBy.
            if (ownerOficiant) {
                var owner = idx >= 0 ? ordersModel.get(idx).waiterOficiant : 0
                if (owner && owner !== ownerOficiant)
                    continue
            }

            if (idx >= 0)
                ordersModel.remove(idx)
            delete itemsByKey[key]
            delete addonsByKey[key]
            delete nrComandByKey[key]
            changed = true
        }
        if (changed)
            root.persist()
    }

    // True dacă masa dată are deja o comandă activă — folosit la schimbarea
    // mesei unei comenzi (ChangeTablePicker), ca să nu suprascriem din
    // greșeală o altă comandă deschisă. Intenționat indiferent de proprietar:
    // o masă ocupată de altcineva e la fel de ocupată.
    function hasOrder(zone, tableNumber) {
        return indexForKey(keyFor(zone, tableNumber)) >= 0
    }

    // True dacă masa are o comandă locală pe care chelnerul dat o poate edita
    // pe ACEST telefon.
    //
    // Deconectarea nu golește acest cache (și nici n-ar trebui: dacă același
    // chelner se reloghează, trebuie să-și regăsească mesele editabile - exact
    // motivul pentru care starea e persistată). Dar fără verificarea de
    // proprietar, un al doilea chelner care se loga pe același telefon găsea
    // comenzile primului marcate "editable" și le putea deschide și modifica.
    //
    // oficiant 0 reținut = intrare veche, dinainte de acest tracking: rămâne
    // editabilă ca înainte (vezi restoreState).
    function isEditableBy(zone, tableNumber, oficiant) {
        var idx = indexForKey(keyFor(zone, tableNumber))
        if (idx < 0)
            return false
        var owner = ordersModel.get(idx).waiterOficiant
        if (!owner)
            return true
        return owner === oficiant
    }

    // Mută o comandă deschisă pe altă masă/zonă (chelnerul a trimis din
    // greșeală pe masa greșită), păstrând numărul comenzii, produsele și
    // adaosurile. Întoarce false (fără nicio schimbare) dacă masa țintă are
    // deja o comandă activă.
    function moveOrder(fromZone, fromTableNumber, toZone, toTableNumber) {
        var fromKey = keyFor(fromZone, fromTableNumber)
        var toKey = keyFor(toZone, toTableNumber)
        if (fromKey === toKey)
            return true

        if (indexForKey(toKey) >= 0)
            return false

        var fromIdx = indexForKey(fromKey)
        if (fromIdx < 0)
            return false

        var src = ordersModel.get(fromIdx)
        var entry = {
            tableKey: toKey,
            zone: toZone,
            tableNumber: toTableNumber,
            waiterOficiant: src.waiterOficiant,
            guestCount: src.guestCount
        }

        itemsByKey[toKey] = itemsByKey[fromKey]
        addonsByKey[toKey] = addonsByKey[fromKey]
        if (nrComandByKey[fromKey])
            nrComandByKey[toKey] = nrComandByKey[fromKey]
        delete itemsByKey[fromKey]
        delete addonsByKey[fromKey]
        delete nrComandByKey[fromKey]

        ordersModel.remove(fromIdx)
        ordersModel.append(entry)
        root.persist()
        return true
    }
}

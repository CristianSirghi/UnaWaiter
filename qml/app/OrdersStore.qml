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

    property ListModel ordersModel: ListModel {}
    property int nextOrderNo: 441

    // Produsele comandate per masă (cheie = tableKey), separat de ordersModel
    // ca să putem reîncărca o comandă existentă în OrderPage la editare.
    property var itemsByKey: ({})
    // Adaosurile per masă: { tableKey: { numeProdus: { numeAdaos: cantitate } } }.
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
    function serializeState() {
        var entries = []
        for (var i = 0; i < ordersModel.count; ++i) {
            var e = ordersModel.get(i)
            entries.push({
                tableKey: e.tableKey, zone: e.zone, tableNumber: e.tableNumber,
                tableName: e.tableName, active: e.active, orderTime: e.orderTime,
                waiterName: e.waiterName, orderNo: e.orderNo, preview: e.preview,
                guestCount: e.guestCount, total: e.total
            })
        }
        return JSON.stringify({
            entries: entries,
            itemsByKey: itemsByKey,
            addonsByKey: addonsByKey,
            nrComandByKey: nrComandByKey,
            nextOrderNo: nextOrderNo
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
        root.nextOrderNo = state.nextOrderNo || root.nextOrderNo
        ordersModel.clear()
        var entries = state.entries || []
        for (var i = 0; i < entries.length; ++i)
            ordersModel.append(entries[i])
    }

    function keyFor(zone, tableNumber) {
        return zone + "-" + tableNumber
    }

    // Ordinea zonelor în listă: sala înaintea terasei. Ține comenzile grupate
    // pe zonă, ca antetele de secțiune din TablesPage să nu se repete.
    function zoneRank(zone) {
        return zone === "terrace" ? 1 : 0
    }

    function indexForKey(key) {
        for (var i = 0; i < ordersModel.count; ++i) {
            if (ordersModel.get(i).tableKey === key)
                return i
        }
        return -1
    }

    function buildPreview(itemsMap) {
        var parts = []
        for (var name in itemsMap) {
            if (itemsMap[name] > 0)
                parts.push(name + " x" + itemsMap[name])
        }
        return parts.join(", ")
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

    // Trimite (sau înlocuiește) comanda deschisă pentru o masă. Întoarce numărul comenzii
    // (păstrat neschimbat dacă se editează o comandă deja trimisă).
    // nrComand = numărul real din Oracle, dacă e cunoscut la acest punct (0 = necunoscut,
    // caz în care păstrăm ce era deja reținut, ca să nu-l pierdem).
    function submitOrder(zone, tableNumber, tableName, waiterName, itemsMap, addonMap, guestCount, total, nrComand) {
        var key = keyFor(zone, tableNumber)
        var idx = indexForKey(key)
        var orderNo = idx >= 0 ? ordersModel.get(idx).orderNo : ("#" + nextOrderNo)
        if (idx < 0)
            nextOrderNo += 1

        itemsByKey[key] = itemsMap
        addonsByKey[key] = addonMap
        if (nrComand)
            nrComandByKey[key] = nrComand

        var entry = {
            tableKey: key,
            zone: zone,
            tableNumber: tableNumber,
            tableName: tableName,
            active: true,
            orderTime: Qt.formatTime(new Date(), "hh:mm"),
            waiterName: waiterName,
            orderNo: orderNo,
            preview: buildPreview(itemsMap),
            guestCount: guestCount,
            total: total
        }

        if (idx >= 0) {
            ordersModel.set(idx, entry)
        } else {
            // Inserăm după celelalte comenzi din aceeași zonă, înaintea zonei următoare.
            var pos = ordersModel.count
            for (var j = 0; j < ordersModel.count; ++j) {
                if (zoneRank(ordersModel.get(j).zone) > zoneRank(zone)) {
                    pos = j
                    break
                }
            }
            ordersModel.insert(pos, entry)
        }

        root.persist()
        return orderNo
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
    function pruneMissing(openKeys) {
        var changed = false
        for (var key in itemsByKey) {
            if (openKeys.indexOf(key) === -1) {
                var idx = indexForKey(key)
                if (idx >= 0)
                    ordersModel.remove(idx)
                delete itemsByKey[key]
                delete addonsByKey[key]
                delete nrComandByKey[key]
                changed = true
            }
        }
        if (changed)
            root.persist()
    }

    // True dacă masa dată are deja o comandă activă — folosit la schimbarea
    // mesei unei comenzi (ChangeTablePicker), ca să nu suprascriem din
    // greșeală o altă comandă deschisă.
    function hasOrder(zone, tableNumber) {
        return indexForKey(keyFor(zone, tableNumber)) >= 0
    }

    // Mută o comandă deschisă pe altă masă/zonă (chelnerul a trimis din
    // greșeală pe masa greșită), păstrând numărul comenzii, produsele și
    // adaosurile. Întoarce false (fără nicio schimbare) dacă masa țintă are
    // deja o comandă activă.
    function moveOrder(fromZone, fromTableNumber, toZone, toTableNumber, toTableName) {
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
            tableName: toTableName,
            active: src.active,
            orderTime: src.orderTime,
            waiterName: src.waiterName,
            orderNo: src.orderNo,
            preview: src.preview,
            guestCount: src.guestCount,
            total: src.total
        }

        itemsByKey[toKey] = itemsByKey[fromKey]
        addonsByKey[toKey] = addonsByKey[fromKey]
        if (nrComandByKey[fromKey])
            nrComandByKey[toKey] = nrComandByKey[fromKey]
        delete itemsByKey[fromKey]
        delete addonsByKey[fromKey]
        delete nrComandByKey[fromKey]

        ordersModel.remove(fromIdx)

        var pos = ordersModel.count
        for (var j = 0; j < ordersModel.count; ++j) {
            if (zoneRank(ordersModel.get(j).zone) > zoneRank(toZone)) {
                pos = j
                break
            }
        }
        ordersModel.insert(pos, entry)
        root.persist()
        return true
    }
}

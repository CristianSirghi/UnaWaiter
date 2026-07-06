import QtQuick 2.15

// Comenzile active, ținute în memorie cât timp rulează aplicația.
// Va fi înlocuit cu apeluri reale către Oracle (via PHP) — până atunci,
// "Trimite comanda" scrie aici, iar TablesPage citește de aici.
QtObject {
    id: root

    property ListModel ordersModel: ListModel {}
    property int nextOrderNo: 441

    // Produsele comandate per masă (cheie = tableKey), separat de ordersModel
    // ca să putem reîncărca o comandă existentă în OrderPage la editare.
    property var itemsByKey: ({})
    // Adaosurile per masă: { tableKey: { numeProdus: { numeAdaos: cantitate } } }.
    property var addonsByKey: ({})

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

    // Trimite (sau înlocuiește) comanda deschisă pentru o masă. Întoarce numărul comenzii
    // (păstrat neschimbat dacă se editează o comandă deja trimisă).
    function submitOrder(zone, tableNumber, tableName, waiterName, itemsMap, addonMap, guestCount, total) {
        var key = keyFor(zone, tableNumber)
        var idx = indexForKey(key)
        var orderNo = idx >= 0 ? ordersModel.get(idx).orderNo : ("#" + nextOrderNo)
        if (idx < 0)
            nextOrderNo += 1

        itemsByKey[key] = itemsMap
        addonsByKey[key] = addonMap

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

        return orderNo
    }

    function removeOrder(zone, tableNumber) {
        var key = keyFor(zone, tableNumber)
        var idx = indexForKey(key)
        if (idx >= 0)
            ordersModel.remove(idx)
        delete itemsByKey[key]
        delete addonsByKey[key]
    }
}

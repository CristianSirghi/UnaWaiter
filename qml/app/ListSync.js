.pragma library

// Sincronizează un ListModel cu o listă nouă de rânduri, PĂSTRÂND poziția de
// derulare a listei.
//
// Tiparul de dinainte era `model.clear()` urmat de `append()` pentru fiecare
// rând: la fiecare poll (25s) sau la fiecare revenire pe pagină, ListView-ul
// își pierdea conținutul și sărea înapoi la început. Cu multe mese deschise,
// chelnerul care derula lista era aruncat sus la fiecare ciclu.
//
// Aici actualizăm pe loc: rândurile neschimbate nu sunt atinse deloc, cele
// mutate sunt mutate, iar structura se modifică doar cât e strict nevoie -
// deci contentY rămâne valid.
//
// keyField = numele câmpului care identifică unic un rând (ex. "tableKey").

function sync(model, items, keyField) {
    // 1. Scoate rândurile care nu mai există în noua listă (de la coadă spre
    //    început, ca indicii rămași să nu se deplaseze sub noi).
    var wanted = ({})
    for (var i = 0; i < items.length; ++i)
        wanted[items[i][keyField]] = true

    for (var m = model.count - 1; m >= 0; --m) {
        if (!wanted[model.get(m)[keyField]])
            model.remove(m)
    }

    // 2. Aliniază pozițiile rămase cu ordinea nouă.
    for (var j = 0; j < items.length; ++j) {
        var key = items[j][keyField]

        if (j < model.count && model.get(j)[keyField] === key) {
            if (!_sameRow(model.get(j), items[j]))
                model.set(j, items[j])
            continue
        }

        // Rândul există, dar mai jos (ordinea s-a schimbat) - îl mutăm în loc
        // să-l inserăm din nou, altfel l-am duplica.
        var at = _indexOf(model, keyField, key, j)
        if (at >= 0) {
            model.move(at, j, 1)
            if (!_sameRow(model.get(j), items[j]))
                model.set(j, items[j])
        } else {
            model.insert(j, items[j])
        }
    }
}

function _indexOf(model, keyField, key, from) {
    for (var i = from; i < model.count; ++i) {
        if (model.get(i)[keyField] === key)
            return i
    }
    return -1
}

// Rândurile identice sunt lăsate neatinse: un `set()` inutil ar re-evalua
// binding-urile din delegate la fiecare poll, degeaba.
function _sameRow(row, item) {
    for (var k in item) {
        if (row[k] !== item[k])
            return false
    }
    return true
}

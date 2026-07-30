.pragma library

// Zonele de amplasare a meselor, derivate din răspunsul `get_tables`.
//
// Înainte, codurile de zonă erau scrise literal în trei fișiere
// (SelectTablePage, ChangeTablePicker, OrderPage.zoneLabel):
//     if (r.ZONE === "hall") ... else if (r.ZONE === "terrace") ...
// Orice zonă adăugată din back-office ("Etaj 2", "VIP") nu apărea nicăieri, iar
// mesele ei dispăreau tăcut din aplicație. Acum zonele vin din `uw_zones` și
// singurul loc care le înțelege e fișierul ăsta.
//
// Denumirea sosește în toate cele trei limbi odată, deci comutarea limbii din
// Setări nu cere o nouă cerere spre server.

// Valorile din Oracle ajung aici prin JSON: o coloană goală poate veni ca null,
// ca undefined sau lipsind de tot. Le aducem pe toate la șirul gol, ca `label`
// să poată decide cu o simplă comparație dacă are sau nu o traducere.
function text(v) {
    return (v === undefined || v === null) ? "" : String(v)
}

// Rândurile de la get_tables → listă de zone:
//     [ { code, nameRo, nameRu, nameEn, tables: [1,2,3] }, ... ]
//
// ORDINEA e cea din SQL (`uw_zones.display_order`, apoi mesele), nu una
// recalculată aici: ordinea zonelor pe ecran e o decizie a restaurantului, luată
// din back-office. De aceea zonele se adaugă în ordinea primei apariții.
function build(rows) {
    if (!rows)
        return []

    var order = []
    var byCode = {}

    for (var i = 0; i < rows.length; ++i) {
        var r = rows[i]
        var code = (r.ZONE !== undefined && r.ZONE !== null) ? String(r.ZONE) : ""
        if (code === "")
            continue

        var no = parseInt(r.TABLE_NO)
        if (isNaN(no))
            continue

        if (byCode[code] === undefined) {
            byCode[code] = {
                code: code,
                nameRo: text(r.ZONE_RO),
                nameRu: text(r.ZONE_RU),
                nameEn: text(r.ZONE_EN),
                tables: []
            }
            order.push(code)
        }
        byCode[code].tables.push(no)
    }

    var out = []
    for (var j = 0; j < order.length; ++j)
        out.push(byCode[order[j]])
    return out
}

// Masă → cod de zonă. Necesar fiindcă `get_open_orders` întoarce doar DESK-ul
// (un număr brut din TMDB_COMENZ), fără zonă.
function deskZones(rows) {
    var map = {}
    if (!rows)
        return map
    for (var i = 0; i < rows.length; ++i) {
        var no = parseInt(rows[i].TABLE_NO)
        if (!isNaN(no))
            map[no] = String(rows[i].ZONE)
    }
    return map
}

function find(zones, code) {
    if (!zones)
        return null
    for (var i = 0; i < zones.length; ++i) {
        if (zones[i].code === code)
            return zones[i]
    }
    return null
}

// Denumirea afișată. Dacă traducerea cerută lipsește în bază se cade pe română,
// iar în ultimă instanță pe cod - un titlu tehnic e mai bun decât o zonă fără
// nume, în care chelnerul n-ar ști ce mese vede.
function label(zone, language) {
    if (!zone)
        return ""

    var name = ""
    if (language === "ru")
        name = zone.nameRu
    else if (language === "en")
        name = zone.nameEn
    else
        name = zone.nameRo

    if (name !== "")
        return name
    if (zone.nameRo !== "")
        return zone.nameRo
    return zone.code
}

function labelFor(zones, code, language) {
    return label(find(zones, code), language)
}

// Zona pe care cade o masă necunoscută (un DESK din Oracle care nu mai e în
// dicționar). Prima zonă, nu "hall": codul ăla poate să nu existe la
// restaurantul curent.
function fallbackCode(zones) {
    return (zones && zones.length > 0) ? zones[0].code : ""
}

.pragma library

// Formatarea sumelor, într-un singur loc. Aceleași două funcții erau scrise de
// mână în patru fișiere (TablesPage.fmtTotal, AchitatePage.fmtTotal,
// OrderPage.fmt, AddonSheet.fmt) - o schimbare de separator zecimal sau de
// monedă trebuia făcută în toate patru.

// 12.5 -> "12,50". Acceptă și un șir ("12.5"), fiindcă valorile din Oracle vin
// uneori ca text prin JSON.
function amount(v) {
    var n = parseFloat(v)
    if (isNaN(n))
        return "0,00"
    return n.toFixed(2).replace(".", ",")
}

// 12.5 -> "12,50 MDL". Pentru o valoare lipsă sau nenumerică întoarce "—":
// un total gol e mai sincer decât un "0,00 MDL" care arată ca o comandă
// gratuită.
function money(v) {
    var n = parseFloat(v)
    if (isNaN(n))
        return "—"
    return n.toFixed(2).replace(".", ",") + " MDL"
}

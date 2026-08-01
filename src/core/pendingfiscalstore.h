#ifndef PENDINGFISCALSTORE_H
#define PENDINGFISCALSTORE_H

#include <QString>
#include <QVariantList>

// Starea unei plăți în curs, salvată pe disc ÎNAINTE de a atinge terminalul
// fiscal. Nu e o optimizare, ci o necesitate: în timpul plății cu cardul
// aplicația trece în fundal (app-ul băncii vine în față) și Android o poate
// omorî complet. La repornire, fișierul e singura urmă că s-au luat bani.
//
// Regula de aur (SMARTONE_CONTRACT.md, invarianta #1): fișierul se șterge DOAR
// după confirmarea pozitivă a tipăririi. Dacă `documentNumber` e completat,
// documentul e DEJA COMIS în memoria fiscală - la recuperare se RE-TIPĂREȘTE,
// niciodată nu se re-emite (ar ieși bon fiscal dublu).
struct PendingFiscal
{
    int nrComand = -1;
    int payId = -1;
    QString payType;         // "C" = numerar, "V" = card
    double total = 0.0;
    double paid = 0.0;       // cât a dat clientul (numerar)
    double change = 0.0;     // rest
    // Numărul de document întors de SmartOne la /sale. Gol până răspunde.
    QString documentNumber;
    // "card"   = așteptăm confirmarea POS (8888/check) înainte de partea fiscală
    // "fiscal" = emiterea/tipărirea bonului
    QString phase;
    QString timestamp;
    QVariantList lines;      // liniile comenzii (din get_order_lines)
    // Cine încasa. Se salvează pentru că o recuperare are loc de obicei după
    // repornirea aplicației, când nu mai știm nimic din sesiunea anterioară -
    // iar închiderea comenzii în Oracle are nevoie de chelner.
    QString oficiant;
    QString employeeName;
    // Referința tranzacției bancare la plata "RRN Manual" (13 cifre). Se
    // persistă odată cu restul: la metoda asta aplicația nu vorbește cu niciun
    // terminal, deci RRN-ul tastat de chelner e SINGURA urmă că plata a avut
    // loc - dacă s-ar pierde la o repornire, n-ar mai putea fi recuperat.
    QString rrn;
    // Comanda a fost deja închisă în Oracle (pay_order a reușit). Ne ferește să
    // reapelăm pay_order la o recuperare care are nevoie doar de re-tipărire.
    bool oraclePaid = false;

    bool isValid() const { return nrComand > 0 && !lines.isEmpty(); }
    bool isCommitted() const { return !documentNumber.trimmed().isEmpty(); }
    bool isCardPhase() const { return phase == QLatin1String("card"); }
};

class PendingFiscalStore
{
public:
    static QString filePath();
    // Scriere ATOMICĂ (temp + rename, invarianta #3): un fișier scris pe
    // jumătate, dacă procesul moare exact atunci, ar fi mai rău decât unul
    // lipsă - la pornire l-am citi ca JSON invalid și am pierde tranzacția.
    static bool save(const PendingFiscal &data);
    static bool load(PendingFiscal &out);
    static bool exists();
    static void remove();
};

#endif // PENDINGFISCALSTORE_H

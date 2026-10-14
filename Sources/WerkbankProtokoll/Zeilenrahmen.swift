// Zeilenweises JSON ueber eine Leitung -- dieselbe Bauart wie der Steuerkanal
// des Kerns (app/src/main/control.ts) und der Mantel-Socket (mantel.ts).
//
// Der Rahmen sammelt Bytes und gibt vollstaendige Zeilen ohne das
// abschliessende Zeilenende heraus. Er schneidet an BYTES, nicht an Zeichen:
// ein mehrbytiges UTF-8-Zeichen, das auf eine Chunk-Grenze faellt, bleibt so
// heil, weil erst die fertige Zeile dekodiert wird (derselbe Befund wie in
// bin/awb-ctl: ein Rahmenzeichen auf der Chunk-Grenze wurde dort zum
// Ersatzzeichen, bevor der StringDecoder kam).
//
// Linear in der Bytezahl: die Suche nach dem Zeilenende setzt dort fort, wo
// der letzte Aufruf aufgehoert hat (eine lange Zeile in vielen Chunks wird
// nicht jedes Mal ab Pufferanfang durchsucht), und der verbrauchte Anfang
// wird je Aufruf nur einmal entfernt statt einmal je Zeile. Beides war
// quadratisch und hielt die Werkbank.app im Leerlauf bei ~60 % CPU (09.10.).
import Foundation

public struct Zeilenrahmen: Sendable {
    private var puffer = Data()
    /// So viele Bytes am Pufferanfang sind schon durchsucht und enthalten kein Zeilenende.
    private var geprueft = 0

    public init() {}

    /// Nimmt neue Bytes auf und liefert alle Zeilen, die damit vollstaendig sind.
    public mutating func aufnehmen(_ bytes: Data) -> [Data] {
        puffer.append(bytes)
        var zeilen: [Data] = []
        let verbraucht: Int = puffer.withUnsafeBytes { (roh: UnsafeRawBufferPointer) -> Int in
            guard let basis = roh.baseAddress else { return 0 }
            let ende = roh.count
            var anfang = 0
            var suche = geprueft
            while suche < ende, let treffer = memchr(basis + suche, 0x0A, ende - suche) {
                let nl = basis.distance(to: UnsafeRawPointer(treffer))
                if nl > anfang { zeilen.append(Data(bytes: basis + anfang, count: nl - anfang)) }
                anfang = nl + 1
                suche = anfang
            }
            return anfang
        }
        if verbraucht == puffer.count {
            puffer = Data()
        } else if verbraucht > 0 {
            puffer = puffer.subdata(in: (puffer.startIndex + verbraucht)..<puffer.endIndex)
        }
        geprueft = puffer.count
        return zeilen
    }

    /// Was noch ohne Zeilenende im Puffer liegt (fuer Tests und Diagnose).
    public var rest: Data { puffer }
}

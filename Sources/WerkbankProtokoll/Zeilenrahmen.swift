// Zeilenweises JSON ueber eine Leitung -- dieselbe Bauart wie der Steuerkanal
// des Kerns (app/src/main/control.ts) und der Mantel-Socket (mantel.ts).
//
// Der Rahmen sammelt Bytes und gibt vollstaendige Zeilen ohne das
// abschliessende Zeilenende heraus. Er schneidet an BYTES, nicht an Zeichen:
// ein mehrbytiges UTF-8-Zeichen, das auf eine Chunk-Grenze faellt, bleibt so
// heil, weil erst die fertige Zeile dekodiert wird (derselbe Befund wie in
// bin/awb-ctl: ein Rahmenzeichen auf der Chunk-Grenze wurde dort zum
// Ersatzzeichen, bevor der StringDecoder kam).
import Foundation

public struct Zeilenrahmen: Sendable {
    private var puffer = Data()

    public init() {}

    /// Nimmt neue Bytes auf und liefert alle Zeilen, die damit vollstaendig sind.
    public mutating func aufnehmen(_ bytes: Data) -> [Data] {
        puffer.append(bytes)
        var zeilen: [Data] = []
        while let nl = puffer.firstIndex(of: 0x0A) {
            let zeile = puffer.subdata(in: puffer.startIndex..<nl)
            puffer.removeSubrange(puffer.startIndex...nl)
            if !zeile.isEmpty { zeilen.append(zeile) }
        }
        return zeilen
    }

    /// Was noch ohne Zeilenende im Puffer liegt (fuer Tests und Diagnose).
    public var rest: Data { puffer }
}

// Der Dateibaum des Editor-Blatts (Auftrag 3.4): aus der FLACHEN Liste, die
// `awb:editor-list-files` liefert (Pfade relativ zum Projektordner, mit "/"
// getrennt, Ausschlussliste schon angewandt), wird hier ein Baum.
//
// WARUM DIE RECHNUNG HIER LIEGT UND NICHT IN DER ANSICHT: sie ist reine
// Zeichenarbeit ohne AppKit, und damit die einzige Stelle des Blatts, die
// `swift test` ohne Fenster pruefen kann. Die Ansicht (Werkbank/Dateibaum.swift)
// zeichnet nur, was hier entsteht.
//
// Der Kern schickt Dateien, keine Ordner: ein Ordner entsteht hier aus den
// Pfadteilen seiner Dateien. Ein Ordner ohne Datei darin gibt es deshalb nicht
// -- genauso wie im Schnelloeffner der Electron-Fassung, der dieselbe Liste liest.
import Foundation

/// Ein Knoten des Baums. `pfad` ist der projektrelative Pfad und zugleich die
/// Kennung (er ist im Baum eindeutig); die Wurzel selbst kommt nie vor.
public struct BaumKnoten: Identifiable, Equatable, Sendable {
    public let pfad: String
    public let name: String
    public let ordner: Bool
    public var kinder: [BaumKnoten]

    public var id: String { pfad }

    public init(pfad: String, name: String, ordner: Bool, kinder: [BaumKnoten] = []) {
        self.pfad = pfad; self.name = name; self.ordner = ordner; self.kinder = kinder
    }
}

/// Eine Zeile des aufgeklappten Baums, wie sie auf dem Schirm steht.
public struct BaumZeile: Identifiable, Equatable, Sendable {
    public let pfad: String
    public let name: String
    public let ordner: Bool
    public let tiefe: Int
    public let offen: Bool

    public var id: String { pfad }

    public init(pfad: String, name: String, ordner: Bool, tiefe: Int, offen: Bool) {
        self.pfad = pfad; self.name = name; self.ordner = ordner; self.tiefe = tiefe; self.offen = offen
    }
}

public enum Dateibaum {
    /// Baut den Baum aus den relativen Pfaden. Ordner stehen vor Dateien, beide
    /// alphabetisch ohne Ruecksicht auf Gross- und Kleinschreibung -- die
    /// Reihenfolge, in der der Finder und jeder Editor dieses Hauses sortieren.
    public static func bauen(_ pfade: [String]) -> [BaumKnoten] {
        // Zwischenform: je Ordnerpfad die Namen seiner Kinder, getrennt nach Art.
        var ordner: [String: Set<String>] = [:]
        var dateien: [String: Set<String>] = [:]
        for roh in pfade {
            let p = roh.trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { continue }
            let teile = p.split(separator: "/").map(String.init)
            guard !teile.isEmpty else { continue }
            var eltern = ""
            for (i, teil) in teile.enumerated() {
                let voll = eltern.isEmpty ? teil : eltern + "/" + teil
                if i == teile.count - 1 {
                    dateien[eltern, default: []].insert(teil)
                } else {
                    ordner[eltern, default: []].insert(teil)
                }
                eltern = voll
            }
        }
        func kinder(_ eltern: String) -> [BaumKnoten] {
            let voll = { (name: String) in eltern.isEmpty ? name : eltern + "/" + name }
            let o = (ordner[eltern] ?? []).sorted(by: vergleich).map {
                BaumKnoten(pfad: voll($0), name: $0, ordner: true, kinder: kinder(voll($0)))
            }
            let d = (dateien[eltern] ?? []).sorted(by: vergleich).map {
                BaumKnoten(pfad: voll($0), name: $0, ordner: false)
            }
            return o + d
        }
        return kinder("")
    }

    /// Die sichtbaren Zeilen: die Wurzel immer, ein Unterordner nur, solange
    /// sein Pfad in `offen` steht.
    public static func zeilen(_ knoten: [BaumKnoten], offen: Set<String>, tiefe: Int = 0) -> [BaumZeile] {
        var raus: [BaumZeile] = []
        for k in knoten {
            let auf = k.ordner && offen.contains(k.pfad)
            raus.append(BaumZeile(pfad: k.pfad, name: k.name, ordner: k.ordner, tiefe: tiefe, offen: auf))
            if auf { raus += zeilen(k.kinder, offen: offen, tiefe: tiefe + 1) }
        }
        return raus
    }

    /// Der Filter des Suchfeldes: alle Pfade, die die Buchstaben des Musters in
    /// dieser Reihenfolge enthalten (wie der Schnelloeffner der Electron-Fassung,
    /// `fuzzyScore`). Ein leeres Muster laesst alles stehen.
    public static func filtern(_ pfade: [String], _ muster: String) -> [String] {
        let m = muster.trimmingCharacters(in: .whitespaces).lowercased()
        guard !m.isEmpty else { return pfade }
        return pfade.filter { passt($0.lowercased(), m) }
    }

    /// Alle Ordnerpfade eines Baums -- der Zustand „alles aufgeklappt“, den ein
    /// gefilterter Baum braucht, damit die Treffer wirklich zu sehen sind.
    public static func alleOrdner(_ knoten: [BaumKnoten]) -> Set<String> {
        var raus: Set<String> = []
        for k in knoten where k.ordner {
            raus.insert(k.pfad)
            raus.formUnion(alleOrdner(k.kinder))
        }
        return raus
    }

    private static func passt(_ ziel: String, _ muster: String) -> Bool {
        var i = ziel.startIndex
        for c in muster {
            guard let treffer = ziel[i...].firstIndex(of: c) else { return false }
            i = ziel.index(after: treffer)
        }
        return true
    }

    private static func vergleich(_ a: String, _ b: String) -> Bool {
        let r = a.compare(b, options: [.caseInsensitive, .numeric])
        return r == .orderedSame ? a < b : r == .orderedAscending
    }
}

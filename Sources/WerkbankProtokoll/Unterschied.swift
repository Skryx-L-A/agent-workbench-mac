// DER UNTERSCHIED ZWEIER FASSUNGEN ALS TEXT (Auftrag 3.5, 06.09.2026).
//
// Der zweite Klick auf einen Aenderungs-Eintrag der Aktivitaet zeigt in der
// Electron-Fassung Monacos Diff-Editor: zwei Spalten nebeneinander. Der Mantel
// hat EINEN Editor mit mehreren Tabs (Entscheidung aus 3.4: ein zweiter
// NSTextView waere ein zweiter TextKit-Baum und ein zweiter Faerber, 76 MB je
// Baustein, `mac/PLAN-EDITOR.md`). Also steht der Unterschied hier als
// vereinheitlichter Text -- dieselbe Auskunft, in der Form, die zu einem
// Editor passt, und in der Form, die jeder aus `git diff` kennt.
//
// Rein: Zeilen hinein, Zeilen hinaus, kein Dateisystem. Unter `swift test`.
import Foundation

public enum Unterschied {
    /// Ab wievielen Zeilen je Seite nicht mehr Zeile fuer Zeile verglichen wird.
    /// Die laengste gemeinsame Folge kostet Laenge mal Laenge; bei 4000 Zeilen
    /// je Seite waeren das 16 Millionen Felder. Daruber steht die ehrliche
    /// Zusammenfassung statt einer Sanduhr.
    public static let grenze = 4000

    /// Wieviele unveraenderte Zeilen um jede Aenderung stehen bleiben.
    public static let umgebung = 3

    /// Der vereinheitlichte Unterschied, wie `diff -u` ihn schreibt.
    /// `alt`/`neu` sind die Ueberschriften der beiden Seiten.
    public static func vereinheitlicht(alt: String, neu: String, altName: String = "vorher", neuName: String = "nachher") -> String {
        let a = zeilen(alt)
        let b = zeilen(neu)
        if a == b { return "--- \(altName)\n+++ \(neuName)\n\nKein Unterschied." }
        if a.count > grenze || b.count > grenze {
            return "--- \(altName)\n+++ \(neuName)\n\n"
                + "Zu groß für einen zeilenweisen Vergleich (\(a.count) gegen \(b.count) Zeilen, Grenze \(grenze)).\n"
                + "Beide Fassungen liegen im Editor; der Unterschied steht hier nicht."
        }
        let schritte = folge(a, b)
        var raus = ["--- \(altName)", "+++ \(neuName)"]
        raus.append(contentsOf: bloecke(schritte, a: a, b: b))
        return raus.joined(separator: "\n")
    }

    /// Ein Schritt des Vergleichs: eine Zeile bleibt, faellt weg oder kommt dazu.
    public enum Schritt: Sendable, Equatable {
        case gleich(Int, Int)
        case weg(Int)
        case neu(Int)
    }

    /// Die Schrittfolge von `a` nach `b` ueber die laengste gemeinsame Folge.
    /// Gleicher Anfang und gleiches Ende werden vorher abgeschnitten -- eine
    /// Aenderung in der Mitte einer langen Datei kostet dann fast nichts.
    public static func folge(_ a: [String], _ b: [String]) -> [Schritt] {
        var vorne = 0
        while vorne < a.count, vorne < b.count, a[vorne] == b[vorne] { vorne += 1 }
        var hinten = 0
        while hinten < a.count - vorne, hinten < b.count - vorne,
              a[a.count - 1 - hinten] == b[b.count - 1 - hinten] { hinten += 1 }
        let ax = Array(a[vorne..<(a.count - hinten)])
        let bx = Array(b[vorne..<(b.count - hinten)])

        var raus: [Schritt] = (0..<vorne).map { .gleich($0, $0) }
        raus.append(contentsOf: mitte(ax, bx, versatzA: vorne, versatzB: vorne))
        for i in 0..<hinten {
            raus.append(.gleich(a.count - hinten + i, b.count - hinten + i))
        }
        return raus
    }

    private static func mitte(_ a: [String], _ b: [String], versatzA: Int, versatzB: Int) -> [Schritt] {
        if a.isEmpty { return (0..<b.count).map { .neu(versatzB + $0) } }
        if b.isEmpty { return (0..<a.count).map { .weg(versatzA + $0) } }
        // Die Tabelle der laengsten gemeinsamen Folge.
        var tabelle = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                tabelle[i][j] = a[i] == b[j] ? tabelle[i + 1][j + 1] + 1 : max(tabelle[i + 1][j], tabelle[i][j + 1])
            }
        }
        var raus: [Schritt] = []
        var i = 0
        var j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                raus.append(.gleich(versatzA + i, versatzB + j))
                i += 1
                j += 1
            } else if tabelle[i + 1][j] >= tabelle[i][j + 1] {
                raus.append(.weg(versatzA + i))
                i += 1
            } else {
                raus.append(.neu(versatzB + j))
                j += 1
            }
        }
        while i < a.count { raus.append(.weg(versatzA + i)); i += 1 }
        while j < b.count { raus.append(.neu(versatzB + j)); j += 1 }
        return raus
    }

    /// Die Bloecke mit ihren `@@`-Koepfen -- nur, was sich geaendert hat, plus
    /// `umgebung` Zeilen darum.
    private static func bloecke(_ schritte: [Schritt], a: [String], b: [String]) -> [String] {
        // Welche Schritte gehoeren zu einem Block: jede Aenderung samt Umgebung.
        var behalten = [Bool](repeating: false, count: schritte.count)
        for (k, s) in schritte.enumerated() where s != gleichHier(s) {
            let von = max(0, k - umgebung)
            let bis = min(schritte.count - 1, k + umgebung)
            for x in von...bis { behalten[x] = true }
        }
        var raus: [String] = []
        var k = 0
        while k < schritte.count {
            guard behalten[k] else { k += 1; continue }
            var ende = k
            while ende + 1 < schritte.count, behalten[ende + 1] { ende += 1 }
            raus.append("")
            raus.append(kopf(schritte, von: k, bis: ende))
            for x in k...ende {
                switch schritte[x] {
                case .gleich(let ia, _): raus.append(" " + a[ia])
                case .weg(let ia): raus.append("-" + a[ia])
                case .neu(let ib): raus.append("+" + b[ib])
                }
            }
            k = ende + 1
        }
        return raus
    }

    /// `.gleich` bleibt `.gleich`, alles andere wird ungleich sich selbst --
    /// der billigste Weg, „ist das eine Aenderung?" zu fragen, ohne ein
    /// zweites Muster zu schreiben.
    private static func gleichHier(_ s: Schritt) -> Schritt {
        if case .gleich = s { return s }
        return .weg(-1)
    }

    private static func kopf(_ schritte: [Schritt], von: Int, bis: Int) -> String {
        var aVon = -1, aAnzahl = 0, bVon = -1, bAnzahl = 0
        for x in von...bis {
            switch schritte[x] {
            case .gleich(let ia, let ib):
                if aVon < 0 { aVon = ia }
                if bVon < 0 { bVon = ib }
                aAnzahl += 1
                bAnzahl += 1
            case .weg(let ia):
                if aVon < 0 { aVon = ia }
                aAnzahl += 1
            case .neu(let ib):
                if bVon < 0 { bVon = ib }
                bAnzahl += 1
            }
        }
        return "@@ -\(max(1, aVon + 1)),\(aAnzahl) +\(max(1, bVon + 1)),\(bAnzahl) @@"
    }

    /// Zeilen ohne den leeren Rest hinter einem abschliessenden Zeilenumbruch.
    public static func zeilen(_ text: String) -> [String] {
        var z = text.components(separatedBy: "\n")
        if z.last == "" { z.removeLast() }
        return z
    }
}

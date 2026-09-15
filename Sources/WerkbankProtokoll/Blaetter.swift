// DIE NUTZLASTEN DER DREI BLAETTER (Auftraege 3.5 und 3.6, 06.09.2026):
// Ordner, Aktivitaet, Protokolle, dazu die Suche und die Ergebnismeldung.
//
// Jede Struktur traegt genau die Felder, die der Kern schickt
// (`app/src/main/main.ts`: `ordnerLesen`, `aktivitaetLesen`, `sucheLesen`,
// `protokollListe`, `ErgebnisWaechter`) -- kein Feld mehr, keines anders
// benannt. Fremder Text (Dateinamen, Commit-Botschaften, Worker-Namen) steht
// in der Ansicht immer in `Text(String)`, nie als LocalizedStringKey.
import Foundation

/// Ein Eintrag der Ordneransicht (`EintragInfo` in main/folder.ts).
public struct OrdnerEintrag: Codable, Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let isDir: Bool
    public let size: Int
    public let mtimeMs: Double

    public init(name: String, path: String, isDir: Bool, size: Int, mtimeMs: Double) {
        self.name = name
        self.path = path
        self.isDir = isDir
        self.size = size
        self.mtimeMs = mtimeMs
    }
}

/// Die Antwort auf `ordner-liste` (`awb:ordner`).
public struct OrdnerNutzlast: Codable, Sendable, Equatable {
    public let root: String
    public let entries: [OrdnerEintrag]

    public init(root: String = "", entries: [OrdnerEintrag] = []) {
        self.root = root
        self.entries = entries
    }
}

/// Ein Treffer der Inhaltssuche (`Treffer` in main/suche.ts).
public struct Suchtreffer: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(pfad):\(zeile)" }
    public let pfad: String
    public let zeile: Int
    public let text: String

    public init(pfad: String, zeile: Int, text: String) {
        self.pfad = pfad
        self.zeile = zeile
        self.text = text
    }
}

/// Die Antwort auf `suche-lesen` (`awb:suche`). `treffer == nil` heisst: es
/// gibt kein Suchwerkzeug auf dieser Maschine -- nicht „nichts gefunden".
public struct SucheNutzlast: Codable, Sendable, Equatable {
    public let root: String
    public let query: String
    public let treffer: [Suchtreffer]?

    public init(root: String = "", query: String = "", treffer: [Suchtreffer]? = []) {
        self.root = root
        self.query = query
        self.treffer = treffer
    }
}

/// Ein Eintrag der Aktivitaetsliste (`AktivitaetEintrag` in main/aktivitaet.ts).
public struct AktivitaetEintrag: Codable, Sendable, Equatable, Identifiable {
    public var id: String { pfad }
    public let typ: String
    public let wer: String
    public let wannMs: Double
    public let pfad: String
    public let groesse: Int
    public let kommentar: String
    public let sessionId: String

    public init(typ: String, wer: String, wannMs: Double, pfad: String, groesse: Int, kommentar: String, sessionId: String) {
        self.typ = typ
        self.wer = wer
        self.wannMs = wannMs
        self.pfad = pfad
        self.groesse = groesse
        self.kommentar = kommentar
        self.sessionId = sessionId
    }

    public var aenderung: Bool { typ == "aenderung" }

    /// Der Dateiname ohne seinen Ordner -- das, was in der Zeile steht.
    public var name: String { pfad.split(separator: "/").last.map(String.init) ?? pfad }

    /// „gerade eben", „vor 5 Minuten", „vor 3 Stunden", „vor 2 Tagen"
    /// (`seitHer` in renderer/aktivitaet-view.ts, dieselben Schwellen).
    public func seitHer(jetztMs: Double = Date().timeIntervalSince1970 * 1000) -> String {
        let min = max(0, Int(((jetztMs - wannMs) / 60000).rounded()))
        if min < 1 { return "gerade eben" }
        if min < 60 { return "vor \(min) Minuten" }
        let std = min / 60
        if std < 24 { return "vor \(std) Stunden" }
        return "vor \(std / 24) Tagen"
    }
}

/// Die Antwort auf `aktivitaet-lesen` (`awb:aktivitaet`).
public struct AktivitaetNutzlast: Codable, Sendable, Equatable {
    public let entries: [AktivitaetEintrag]

    public init(entries: [AktivitaetEintrag] = []) {
        self.entries = entries
    }
}

/// Ein Eintrag der Protokoll-Liste (`ProtokollEintrag` in main/protokolle.ts).
/// Die Liste selbst steht in den Einstellungen (`logPaths`), nicht im Code.
public struct ProtokollEintrag: Codable, Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let label: String
    public let path: String
    public let exists: Bool
    public let size: Int
    public let mtimeMs: Double

    public init(label: String, path: String, exists: Bool, size: Int, mtimeMs: Double) {
        self.label = label
        self.path = path
        self.exists = exists
        self.size = size
        self.mtimeMs = mtimeMs
    }
}

/// Die Meldung einer fertigen Ergebnisdatei (`awb:ergebnis`, main/results.ts).
public struct ErgebnisNutzlast: Codable, Sendable, Equatable {
    public let name: String
    public let path: String

    public init(name: String = "", path: String = "") {
        self.name = name
        self.path = path
    }
}

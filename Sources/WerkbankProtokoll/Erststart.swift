// Der gefuehrte erste Start (Auftrag 3.8): die REGEL und die Nutzlast, ohne
// Fenster.
//
// Die Regel ist die woertliche Uebertragung von `app/src/erststart/ablauf.ts`
// -- vier Schritte in fester Reihenfolge, jeder ueberspringbar, und die
// Einstellungen werden GENAU EINMAL geschrieben, beim Abschluss. Sie steht hier
// und nicht im Blatt, aus demselben Grund wie dort: welcher Schritt als
// naechstes kommt und was ein Ueberspringen bedeutet, ist Logik und gehoert
// unter `swift test`; das Blatt haelt nur den Zustand und zeichnet ihn.
//
// Die Nutzlast ist `awb:erststart-daten` -- eine Projektion der
// Einstellungsdaten, deren Typen (AnmeldeSicht, KontextAntwort) schon in
// Einstellungen.swift stehen und hier wiederverwendet werden. Eine zweite
// Kopie gaebe es sonst fuer dieselbe Auskunft.
import Foundation

/// Die vier Schritte, in ihrer festen Reihenfolge (`SCHRITTE` in ablauf.ts).
public enum ErststartSchritt: String, Sendable, CaseIterable {
    case maschine, harness, modell, fertig
}

/// Welche Antwort auf welchen Einstellungs-Schluessel geht (`SCHLUESSEL`).
/// Vier Schluessel bei drei Fragen: der dritte Schritt liefert zwei Antworten,
/// weil ein oertliches Modell auch sein Kontextfenster waehlen laesst.
public enum ErststartAntwort: String, Sendable, CaseIterable {
    case maschine, harness, modell, kontext

    public var schluessel: String {
        switch self {
        case .maschine: return "defaultWorkerMachine"
        case .harness: return "orchestratorHarness"
        case .modell: return "orchestratorModel"
        case .kontext: return "orchestratorKontext"
        }
    }
}

/// Der Schluessel, der den Weg als erledigt markiert -- einmal, beim Abschluss.
public let ERSTSTART_ERLEDIGT_SCHLUESSEL = "erststartErledigt"

/// Eine Schreibung fuer `awb:erststart-setzen`.
public struct ErststartSchreibung: Sendable, Equatable {
    public let schluessel: String
    /// Entweder eine Kennung, eine Tokenzahl oder das `true` des Abschlusses.
    public let wert: ErststartWert
    public init(schluessel: String, wert: ErststartWert) { self.schluessel = schluessel; self.wert = wert }
}

public enum ErststartWert: Sendable, Equatable {
    case text(String)
    case zahl(Int)
    case ja

    /// Der Wert, wie er als JSON-Argument an den Kern geht.
    public var alsArgument: Any {
        switch self {
        case .text(let t): return t
        case .zahl(let n): return n
        case .ja: return true
        }
    }

    /// Der Wert, wie ihn der Abschlusssatz nennt (`fertig.eintrag.*`).
    public var alsText: String {
        switch self {
        case .text(let t): return t
        case .zahl(let n): return String(n)
        case .ja: return "true"
        }
    }
}

/// Der Ablauf als reiner Wert: wo er steht, was schon geantwortet ist, ob er zu Ende ist.
public struct ErststartAblauf: Sendable, Equatable {
    public private(set) var index: Int
    public private(set) var antworten: [ErststartAntwort: ErststartWert]
    public private(set) var abgeschlossen: Bool

    public init() { index = 0; antworten = [:]; abgeschlossen = false }

    /// Der Schritt, der jetzt dran ist. Nach dem Abschluss bleibt es `fertig`.
    public var schritt: ErststartSchritt {
        ErststartSchritt.allCases[min(index, ErststartSchritt.allCases.count - 1)]
    }

    public var istLetzterSchritt: Bool { schritt == .fertig }

    /// Eine Antwort setzen und weitergehen; auf `fertig` abschliessen.
    public mutating func weiter(_ antwort: String) -> [ErststartSchreibung] {
        fortschritt(antwort)
    }

    /// Den Schritt OHNE Antwort ueberspringen; die bestehende Vorgabe bleibt stehen.
    public mutating func ueberspringen() -> [ErststartSchreibung] {
        fortschritt(nil)
    }

    /// Das gewaehlte Kontextfenster festhalten -- die zweite Antwort des dritten
    /// Schritts. `0` nimmt sie wieder zurueck (erst ein oertliches Modell
    /// gewaehlt, dann doch eines aus der Cloud).
    public mutating func mitKontext(_ tokens: Int) {
        guard !abgeschlossen else { return }
        if tokens > 0 { antworten[.kontext] = .zahl(tokens) } else { antworten[.kontext] = nil }
    }

    /// Die Antworten in der Reihenfolge der Schritte -- fuer den Abschlusssatz.
    public var eintraege: [(ErststartAntwort, ErststartWert)] {
        ErststartAntwort.allCases.compactMap { a in antworten[a].map { (a, $0) } }
    }

    private mutating func fortschritt(_ antwort: String?) -> [ErststartSchreibung] {
        // Nach dem Abschluss ist jeder weitere Aufruf ein Nichts-Tun: ein
        // zweiter Klick auf „Fertig“ schreibt nicht ein zweites Mal.
        if abgeschlossen { return [] }
        if schritt == .fertig {
            var schreibungen = eintraege.map { ErststartSchreibung(schluessel: $0.0.schluessel, wert: $0.1) }
            schreibungen.append(ErststartSchreibung(schluessel: ERSTSTART_ERLEDIGT_SCHLUESSEL, wert: .ja))
            abgeschlossen = true
            return schreibungen
        }
        if let a = antwort, let name = ErststartAntwort(rawValue: schritt.rawValue) {
            antworten[name] = .text(a)
        }
        index += 1
        return []
    }
}

// MARK: Die Nutzlast (`awb:erststart-daten`)

/// Ein Harness, wie der erste Start ihn anbietet.
public struct ErststartHarness: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let startbar: Bool
    init(_ j: JSONWert) {
        id = j["id"].text ?? ""
        label = j["label"].text ?? (j["id"].text ?? "")
        startbar = j["startbar"].bool ?? false
    }
}

/// Ein Orchestrator-Modell; `lokal` entscheidet, ob die Kontextfrage erscheint.
public struct ErststartModell: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let harness: String
    public let lokal: Bool
    init(_ j: JSONWert) {
        id = j["id"].text ?? ""
        label = j["label"].text ?? (j["id"].text ?? "")
        harness = j["harness"].text ?? ""
        lokal = j["lokal"].bool ?? false
    }
}

public struct ErststartDaten: Sendable, Equatable {
    public let machine: String
    public let maschinen: [String]
    public let sprache: String
    /// Ist der Weg schon einmal zu Ende gegangen worden? Danach geht das Blatt
    /// nie wieder von selbst auf (main.ts, `erststartErledigt`).
    public let erledigt: Bool
    public let harnesses: [ErststartHarness]
    public let orchestratorModelle: [ErststartModell]
    public let anmeldung: [String: AnmeldeSicht]
    /// Was gesetzt ist, und was ohne eigene Wahl gilt -- die Vorbelegung der Chips.
    public let settings: [String: String]
    public let vorgaben: [String: String]

    public init(json j: JSONWert) {
        machine = j["machine"].text ?? ""
        maschinen = j["maschinen"].texte
        sprache = j["sprache"].text ?? "en"
        erledigt = j["erledigt"].bool ?? false
        harnesses = (j["harnesses"].liste ?? []).map(ErststartHarness.init)
        orchestratorModelle = (j["orchestratorModelle"].liste ?? []).map(ErststartModell.init)
        anmeldung = (j["anmeldung"].objekt ?? [:]).mapValues(AnmeldeSicht.init)
        settings = (j["settings"].objekt ?? [:]).mapValues { $0.text ?? "" }
        vorgaben = (j["vorgaben"].objekt ?? [:]).mapValues { $0.text ?? "" }
    }

    /// Die Vorbelegung eines Feldes: das Gesetzte, sonst die Vorgabe.
    public func vorbelegung(_ schluessel: String) -> String {
        let gesetzt = settings[schluessel] ?? ""
        return gesetzt.isEmpty ? (vorgaben[schluessel] ?? "") : gesetzt
    }

    /// Die Modelle des gewaehlten Programms (erststart.ts `schrittModell`).
    public func modelle(fuer harness: String) -> [ErststartModell] {
        orchestratorModelle.filter { $0.harness == harness }
    }
}

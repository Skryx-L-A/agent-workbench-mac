// Die Nutzlasten des Sitzungsfensters (Auftrag 2.7): was `awb:sitz-daten`
// und `awb:sitz-wahl-daten` liefern, gelesen wie `EinstellungenDaten` -- ueber
// JSONWert, damit ein fehlendes Feld leer bleibt statt den Leser zu werfen.
// Die Feldnamen sind die von `sitzungsfenster.ts` (SitzungsZeile,
// SitzungsDaten) und `main.ts` (`awb:sitz-wahl-daten`).
import Foundation

/// Eine bekannte Sitzung, so wie die Liste sie zeigt (`SitzungsZeile` in sitzungsfenster.ts).
public struct SitzungsZeileDaten: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let dir: String
    public let machine: String
    public let harness: String
    public let model: String
    public let state: String
    public let startet: Bool
    public let startFehler: Bool
    public let lastActive: String
    /// Darf fortgesetzt werden -- die Antwort von `darfWiederherstellen` im Kern.
    public let fortsetzbar: Bool
    /// Der Satz fuer den Menschen: bei einer fortsetzbaren Zeile, was mit der
    /// Unterhaltung geschieht (revive.ts), sonst der Grund, warum nicht.
    public let grund: String
    /// 'resumed' oder 'fresh' bei einer fortsetzbaren Zeile, sonst leer.
    public let unterhaltung: String

    init(_ j: JSONWert) {
        id = j["id"].text ?? ""
        name = j["name"].text ?? ""
        dir = j["dir"].text ?? ""
        machine = j["machine"].text ?? ""
        harness = j["harness"].text ?? ""
        model = j["model"].text ?? ""
        state = j["state"].text ?? ""
        startet = j["startet"].bool ?? false
        startFehler = j["startFehler"].bool ?? false
        lastActive = j["lastActive"].text ?? ""
        fortsetzbar = j["fortsetzbar"].bool ?? false
        grund = j["grund"].text ?? ""
        unterhaltung = j["unterhaltung"].text ?? ""
    }

    /// Der Name des Projekts: der letzte Teil des Pfades.
    public var ordnerName: String {
        let teile = dir.split(separator: "/").filter { !$0.isEmpty }
        return teile.last.map(String.init) ?? dir
    }

    /// Laeuft gerade ein Pane, den man beenden koennte ('running' oder 'attention')?
    public var laeuftGerade: Bool { state == "running" || state == "attention" }

    /// Die Suche wie `zeilePasstSuche` (filter.ts): Name, Ordner oder Maschine.
    public func passt(suche: String) -> Bool {
        let n = suche.trimmingCharacters(in: .whitespaces).lowercased()
        if n.isEmpty { return true }
        return name.lowercased().contains(n) || dir.lowercased().contains(n) || machine.lowercased().contains(n)
    }
}

/// Eine Gruppe der Liste: ein Projektordner auf einer Maschine (`gruppiere` in sitzung.ts).
public struct SitzungsGruppe: Sendable, Equatable, Identifiable {
    public var id: String { schluessel }
    /// `"<maschine> <ordner>"` -- derselbe Schluessel wie `data-gruppe` der Electron-Fassung.
    public let schluessel: String
    public let dir: String
    public let machine: String
    public var zeilen: [SitzungsZeileDaten]
}

/// `awb:sitz-daten`: die Sitzungen FLACH, absteigend nach letzter Aktivitaet, mit Maschine und Sprache.
public struct SitzungsDaten: Sendable, Equatable {
    public let machine: String
    public let sprache: String
    public let remoteMachines: [String]
    public let sitzungen: [SitzungsZeileDaten]

    public init(json j: JSONWert) {
        machine = j["machine"].text ?? ""
        sprache = j["sprache"].text ?? "en"
        remoteMachines = j["remoteMachines"].texte
        sitzungen = (j["sitzungen"].liste ?? []).map(SitzungsZeileDaten.init)
    }

    public static func lesen(_ daten: Data) -> SitzungsDaten { SitzungsDaten(json: JSONWert.lesen(daten)) }

    /// Die Gruppen in der Reihenfolge ihrer JUENGSTEN Sitzung -- die Liste
    /// kommt sortiert herein, eine geordnete Sammlung behaelt das (sitzung.ts).
    public static func gruppieren(_ zeilen: [SitzungsZeileDaten]) -> [SitzungsGruppe] {
        var gruppen: [SitzungsGruppe] = []
        var index: [String: Int] = [:]
        for z in zeilen {
            let s = "\(z.machine) \(z.dir)"
            if let i = index[s] {
                gruppen[i].zeilen.append(z)
            } else {
                index[s] = gruppen.count
                gruppen.append(SitzungsGruppe(schluessel: s, dir: z.dir, machine: z.machine, zeilen: [z]))
            }
        }
        return gruppen
    }
}

/// Ein Programm zur Wahl (`awb:sitz-wahl-daten`, `harnesses`).
public struct WahlHarness: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    /// Das Programm ist auf dieser Maschine installiert.
    public let binaer: Bool
    init(_ j: JSONWert) { id = j["id"].text ?? ""; label = j["label"].text ?? ""; binaer = j["binaer"].bool ?? false }
}

/// Ein Modell zur Wahl (`awb:sitz-wahl-daten`, `modelle`).
public struct WahlModell: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let harness: String
    public let harnessLabel: String
    public let lokal: Bool
    public let startbar: Bool
    /// Der Deckel der Auslieferung (`maxEffort` der Registry), leer ohne Angabe.
    public let deckelRegistry: String
    init(_ j: JSONWert) {
        id = j["id"].text ?? ""; label = j["label"].text ?? ""; harness = j["harness"].text ?? ""
        harnessLabel = j["harnessLabel"].text ?? ""; lokal = j["lokal"].bool ?? false; startbar = j["startbar"].bool ?? false
        deckelRegistry = j["deckelRegistry"].text ?? ""
    }
}

/// Was in den Einstellungen steht -- die Vorbelegung der Wahl.
public struct WahlEinstellung: Sendable, Equatable {
    public let harness: String
    public let model: String
    public let effort: String
    public let kontext: Int
    init(_ j: JSONWert) {
        harness = j["harness"].text ?? ""; model = j["model"].text ?? ""
        effort = j["effort"].text ?? ""; kontext = j["kontext"].int ?? 0
    }
}

/// `awb:sitz-wahl-daten`: Programme, Modelle, Stufen je Programm, Deckel je Modell, Vorbelegung.
public struct WahlDaten: Sendable, Equatable {
    public let harnesses: [WahlHarness]
    public let modelle: [WahlModell]
    public let harnessStufen: [String: [String]]
    /// Der Deckel je Modell, wie `wb-state models cap` ihn nennt -- nur fuer die beiden gewaehlten Modelle.
    public let deckel: [String: DeckelSicht]
    /// Die gesetzten Deckel aus der Einstellungsdatei (Modell -> Deckel).
    public let effortCaps: [String: EffortCap]
    public let einstellung: WahlEinstellung

    public init(json j: JSONWert) {
        harnesses = (j["harnesses"].liste ?? []).map(WahlHarness.init)
        modelle = (j["modelle"].liste ?? []).map(WahlModell.init)
        harnessStufen = (j["harnessStufen"].objekt ?? [:]).compactMapValues { $0.liste == nil ? nil : $0.texte }
        deckel = (j["deckel"].objekt ?? [:]).mapValues(DeckelSicht.init)
        effortCaps = (j["effortCaps"].objekt ?? [:]).mapValues(EffortCap.init)
        einstellung = WahlEinstellung(j["einstellung"])
    }

    public static func lesen(_ daten: Data) -> WahlDaten { WahlDaten(json: JSONWert.lesen(daten)) }

    public func modelle(fuer harness: String) -> [WahlModell] { modelle.filter { $0.harness == harness } }
    public func stufen(fuer harness: String) -> [String] { harnessStufen[harness] ?? [] }

    /// Der Deckel eines Modells samt Quelle -- dieselben drei Quellen wie die
    /// Modelle-Seite: die Antwort des Werkzeugs, wenn es gefragt wurde; sonst
    /// der gesetzte Deckel aus der Datei; sonst die Auslieferung. Nil ohne Deckel.
    public func deckel(fuer modell: String) -> (cap: String, quelle: String)? {
        if let d = deckel[modell], !d.cap.isEmpty { return (d.cap, d.quelle) }
        if let e = effortCaps[modell], !e.cap.isEmpty { return (e.cap, "einstellung") }
        if let m = modelle.first(where: { $0.id == modell }), !m.deckelRegistry.isEmpty { return (m.deckelRegistry, "registry") }
        return nil
    }
}

/// Die Wahl fuer genau diese eine Sitzung (`SitzungsWahl` in main.ts). Ein
/// leeres Feld erzeugt keinen Schalter; dann gilt, was in den Einstellungen steht.
public struct SitzungsWahl: Sendable, Equatable {
    public var harness = ""
    public var model = ""
    public var effort = ""
    public var kontext = 0

    public init(harness: String = "", model: String = "", effort: String = "", kontext: Int = 0) {
        self.harness = harness; self.model = model; self.effort = effort; self.kontext = kontext
    }

    /// Die Flaggen, die beim Start wirklich mitgehen -- wortwoertlich, wie `wahlFlaggen` in sitzung.ts.
    public func flaggen(lokal: Bool, stufen: [String]) -> [String] {
        var f: [String] = []
        if !harness.isEmpty { f += ["--harness", harness] }
        if !model.isEmpty { f += ["--model", model] }
        if !effort.isEmpty, stufen.contains(effort) { f += ["--effort", effort] }
        if lokal, kontext > 0 { f += ["--kontext", String(kontext)] }
        return f
    }

    /// Das JSON-Objekt fuer `awb:sitz-neu-wahl`.
    public var fuerJSON: [String: Any] {
        ["harness": harness, "model": model, "effort": effort, "kontext": kontext]
    }
}

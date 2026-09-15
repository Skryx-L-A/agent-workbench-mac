// Die Nutzlasten des Einstellungsfensters (Auftrag 2.6): was `awb:ein-daten`
// liefert (app/src/main/einstellungsfenster.ts, `EinstellungsDaten`), die
// Texttabelle aus `awb:ein-texte` (app/src/einstellungen/texte.ts) und die
// Kontextstufen aus `awb:kontext-stufen`.
//
// Die Einstellungsdaten kommen als EIN grosses Objekt mit gut dreissig
// Feldern, und zwei davon (`settings`, `vorgaben`) sind freie Woerterbuecher,
// deren Werte jede JSON-Form haben. Deshalb wird hier nicht ueber Codable
// in feste Typen gezwungen, sondern erst in einen freien JSON-Wert gelesen
// und daraus nachsichtig aufgebaut: ein Feld, das der Kern eines Tages
// dazuerfindet, laesst den Mantel nicht abstuerzen, ein fehlendes bleibt
// leer. Die Feldnamen sind die des Kerns, unveraendert.
import Foundation

// MARK: Ein freier JSON-Wert

public enum JSONWert: Sendable, Equatable {
    case null
    case bool(Bool)
    case zahl(Double)
    case text(String)
    case liste([JSONWert])
    case objekt([String: JSONWert])

    /// Aus einem Foundation-Objekt (JSONSerialization).
    public init(_ any: Any?) {
        switch any {
        case nil, is NSNull: self = .null
        case let n as NSNumber:
            // NSNumber traegt Bool UND Zahl, und `as Bool` spraeche auch bei
            // einer 1 an (gemessen: [1,"a"] wurde zu [true,"a"]). Also zuerst
            // die Zahl, und darin der Typ des CoreFoundation-Objekts.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) } else { self = .zahl(n.doubleValue) }
        case let b as Bool: self = .bool(b)
        case let s as String: self = .text(s)
        case let a as [Any]: self = .liste(a.map { JSONWert($0) })
        case let d as [String: Any]: self = .objekt(d.mapValues { JSONWert($0) })
        default: self = .null
        }
    }

    public static func lesen(_ daten: Data) -> JSONWert {
        JSONWert(try? JSONSerialization.jsonObject(with: daten, options: [.fragmentsAllowed]))
    }

    /// Zurueck in ein Foundation-Objekt, so wie es ueber den Socket geht.
    public var fuerJSON: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .zahl(let z): return z == z.rounded() && abs(z) < 1e15 ? Int(z) as Any : z as Any
        case .text(let s): return s
        case .liste(let l): return l.map(\.fuerJSON)
        case .objekt(let o): return o.mapValues(\.fuerJSON)
        }
    }

    public var istNull: Bool { if case .null = self { return true } else { return false } }
    public var bool: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    public var zahl: Double? { if case .zahl(let z) = self { return z } else { return nil } }
    public var int: Int? { zahl.map { Int($0) } }
    public var text: String? { if case .text(let s) = self { return s } else { return nil } }
    public var liste: [JSONWert]? { if case .liste(let l) = self { return l } else { return nil } }
    public var objekt: [String: JSONWert]? { if case .objekt(let o) = self { return o } else { return nil } }
    public subscript(_ schluessel: String) -> JSONWert { objekt?[schluessel] ?? .null }
    public var texte: [String] { liste?.compactMap(\.text) ?? [] }

    /// Ein Wert als Zeichenkette, wie er in einem Feld steht: Zahl ohne
    /// Nachkommastellen, wenn sie ganz ist; Bool als true/false; Rest als JSON.
    public var zeichenkette: String {
        switch self {
        case .null: return ""
        case .bool(let b): return b ? "true" : "false"
        case .zahl(let z): return z == z.rounded() && abs(z) < 1e15 ? String(Int(z)) : String(z)
        case .text(let s): return s
        case .liste, .objekt:
            guard let d = try? JSONSerialization.data(withJSONObject: fuerJSON, options: [.sortedKeys]) else { return "" }
            return String(decoding: d, as: UTF8.self)
        }
    }
}

// MARK: Die Texttabelle (`awb:ein-texte`)

/// Die Beschriftungen des Fensters in der eingestellten Sprache -- dieselbe
/// Tabelle wie `texte.ts`, ueber den Kern geholt. `t()` ersetzt Platzhalter
/// `{name}` nach derselben Regel: ein fehlender Wert bleibt sichtbar stehen,
/// ein fehlender Schluessel meldet sich als `[fehlender Text: …]`.
public struct Texte: Sendable, Equatable {
    public let sprache: String
    public let tabelle: [String: String]

    public init(sprache: String = "en", tabelle: [String: String] = [:]) {
        self.sprache = sprache
        self.tabelle = tabelle
    }

    public init(json: JSONWert) {
        sprache = json["sprache"].text ?? "en"
        var t: [String: String] = [:]
        for (k, v) in json["tabelle"].objekt ?? [:] { if let s = v.text { t[k] = s } }
        tabelle = t
    }

    public var leer: Bool { tabelle.isEmpty }

    public func t(_ schluessel: String, _ werte: [String: String] = [:]) -> String {
        guard let roh = tabelle[schluessel] else { return "[fehlender Text: \(schluessel)]" }
        return Self.einsetzen(roh, werte)
    }

    /// Wie `t()`, nur ohne Fehlermarke: ein fehlender Schluessel heisst „kein Text".
    public func tOpt(_ schluessel: String, _ werte: [String: String] = [:]) -> String {
        guard let roh = tabelle[schluessel] else { return "" }
        return Self.einsetzen(roh, werte)
    }

    public func hat(_ schluessel: String) -> Bool { tabelle[schluessel] != nil }

    static func einsetzen(_ roh: String, _ werte: [String: String]) -> String {
        guard !werte.isEmpty, roh.contains("{") else { return roh }
        var aus = roh
        for (k, v) in werte { aus = aus.replacingOccurrences(of: "{\(k)}", with: v) }
        return aus
    }
}

// MARK: Die Einstellungsdaten (`awb:ein-daten`)

public struct HarnessSicht: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let modelle: Int
    public let binaer: Bool
    public let orchestratorDefaultModel: String
    init(_ j: JSONWert) {
        id = j["id"].text ?? ""; label = j["label"].text ?? id
        modelle = j["modelle"].int ?? 0; binaer = j["binaer"].bool ?? false
        orchestratorDefaultModel = j["orchestratorDefaultModel"].text ?? ""
    }
}

public struct VorhersageWegSicht: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let bauart: String
    public let modell: String
    public let herkunft: String
    init(_ j: JSONWert) {
        id = j["id"].text ?? ""; label = j["label"].text ?? id; bauart = j["bauart"].text ?? ""
        modell = j["modell"].text ?? ""; herkunft = j["herkunft"].text ?? ""
    }
}

public struct VorhersageSicht: Sendable, Equatable {
    public let bauart: String
    public let modell: String
    public let herkunft: String
    public let wegVorgabe: String
    public let wege: [VorhersageWegSicht]
    init(_ j: JSONWert) {
        bauart = j["bauart"].text ?? ""; modell = j["modell"].text ?? ""; herkunft = j["herkunft"].text ?? ""
        wegVorgabe = j["wegVorgabe"].text ?? ""
        wege = (j["wege"].liste ?? []).map(VorhersageWegSicht.init)
    }
}

public struct ModellSicht: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let harness: String
    public let harnessLabel: String
    public let rollen: [String]
    public let efforts: [String]
    public let effortFaehig: Bool
    public let kontext: Int
    public let lokal: Bool
    public let startbar: Bool
    public let deckelRegistry: String
    public let vorhersage: VorhersageSicht?
    init(_ j: JSONWert) {
        id = j["id"].text ?? ""; label = j["label"].text ?? id
        harness = j["harness"].text ?? ""; harnessLabel = j["harnessLabel"].text ?? harness
        rollen = j["rollen"].texte; efforts = j["efforts"].texte
        effortFaehig = j["effortFaehig"].bool ?? false; kontext = j["kontext"].int ?? 0
        lokal = j["lokal"].bool ?? false; startbar = j["startbar"].bool ?? false
        deckelRegistry = j["deckelRegistry"].text ?? ""
        vorhersage = j["vorhersage"].objekt == nil ? nil : VorhersageSicht(j["vorhersage"])
    }
}

public struct AskMuster: Sendable, Equatable {
    public let befehl: String
    public let unterbefehl: String
    public let muster: String
    public let grund: String
    public let aus: Bool
    public let roh: JSONWert
    init(_ j: JSONWert) {
        befehl = j["befehl"].text ?? ""; unterbefehl = j["unterbefehl"].text ?? ""
        muster = j["muster"].text ?? ""; grund = j["grund"].text ?? ""; aus = j["aus"].bool ?? false
        roh = j
    }
    public var bezeichnung: String { [befehl, unterbefehl].filter { !$0.isEmpty }.joined(separator: " ") }
    /// Derselbe Eintrag mit umgelegtem Schalter -- `aus` faellt weg, wenn er an ist (wie einstellungen.ts).
    public func mit(aus neu: Bool) -> JSONWert {
        var o = roh.objekt ?? [:]
        if neu { o["aus"] = .bool(true) } else { o["aus"] = nil }
        return .objekt(o)
    }
}

public struct GuardZeile: Sendable, Equatable, Identifiable {
    public let id: String
    public let an: Bool
    public let rolle: String
    public let seit: String
    public let grund: String
    init(_ j: JSONWert) {
        id = j["id"].text ?? ""; an = j["an"].bool ?? false; rolle = j["rolle"].text ?? ""
        seit = j["seit"].text ?? ""; grund = j["grund"].text ?? ""
    }
}

public struct WacheRolle: Sendable, Equatable {
    public let an: Bool
    public let mahnenAb: Int
    public let eingreifen: Bool
    public let notbremseAb: Int?
    public init(an: Bool, mahnenAb: Int, eingreifen: Bool, notbremseAb: Int?) {
        self.an = an; self.mahnenAb = mahnenAb; self.eingreifen = eingreifen; self.notbremseAb = notbremseAb
    }
    init(_ j: JSONWert) {
        an = j["an"].bool ?? true; mahnenAb = j["mahnenAb"].int ?? 75
        eingreifen = j["eingreifen"].bool ?? true; notbremseAb = j["notbremseAb"].int
    }
}

public struct DeckelSicht: Sendable, Equatable {
    public let model: String
    public let cap: String
    public let quelle: String
    public let grund: String
    public let registry: String
    public let efforts: [String]
    init(_ j: JSONWert) {
        model = j["model"].text ?? ""; cap = j["cap"].text ?? ""; quelle = j["quelle"].text ?? ""
        grund = j["grund"].text ?? ""; registry = j["registry"].text ?? ""; efforts = j["efforts"].texte
    }
}

public struct EffortCap: Sendable, Equatable {
    public let cap: String
    public let grund: String
    public let gesetzt: String
    init(_ j: JSONWert) { cap = j["cap"].text ?? ""; grund = j["grund"].text ?? ""; gesetzt = j["gesetzt"].text ?? "" }
}

public struct AnmeldeSicht: Sendable, Equatable {
    public let stand: String
    public let grund: String
    init(_ j: JSONWert) { stand = j["stand"].text ?? "unbekannt"; grund = j["grund"].text ?? "" }
}

public struct AnbieterSicht: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    /// schluessel | abo | lokal
    public let art: String
    /// ja | nein | unbekannt
    public let stand: String
    init(_ j: JSONWert) {
        id = j["id"].text ?? ""; label = j["label"].text ?? id; art = j["art"].text ?? ""; stand = j["stand"].text ?? "unbekannt"
    }
}

public struct ChatQuelle: Sendable, Equatable {
    public let via: String
    public let grund: String
    public let live: Bool
    public let zeigtNicht: [String]
    public let probe: String
    init(_ j: JSONWert) {
        via = j["via"].text ?? ""; grund = j["grund"].text ?? ""; live = j["live"].bool ?? false
        zeigtNicht = j["zeigtNicht"].texte; probe = j["probe"].text ?? ""
    }
}

public struct MeldeSicht: Sendable, Equatable {
    public let an: Bool
    public let ereignisse: [String]
    public let wege: [String]
    public let handyUrl: String
    public let tonDatei: String
    public let limitSchwelle: Int
    init(_ j: JSONWert) {
        an = j["an"].bool ?? false; ereignisse = j["ereignisse"].texte; wege = j["wege"].texte
        handyUrl = j["handyUrl"].text ?? ""; tonDatei = j["tonDatei"].text ?? ""; limitSchwelle = j["limitSchwelle"].int ?? 85
    }
    /// Der ganze Block als JSON, mit Aenderungen -- geschrieben wird immer der ganze Block (einstellungen.ts).
    public func mit(an: Bool? = nil, ereignisse: [String]? = nil, wege: [String]? = nil,
                    handyUrl: String? = nil, tonDatei: String? = nil, limitSchwelle: Int? = nil) -> JSONWert {
        .objekt([
            "an": .bool(an ?? self.an),
            "ereignisse": .liste((ereignisse ?? self.ereignisse).map(JSONWert.text)),
            "wege": .liste((wege ?? self.wege).map(JSONWert.text)),
            "handyUrl": .text(handyUrl ?? self.handyUrl),
            "tonDatei": .text(tonDatei ?? self.tonDatei),
            "limitSchwelle": .zahl(Double(limitSchwelle ?? self.limitSchwelle)),
        ])
    }
}

public struct HookZeile: Sendable, Equatable, Identifiable {
    public var id: String { name + "·" + ereignis }
    public let name: String
    public let ereignis: String
    public let lehntAb: Bool
    init(_ j: JSONWert) { name = j["name"].text ?? ""; ereignis = j["ereignis"].text ?? ""; lehntAb = j["lehntAb"].bool ?? false }
}

public struct PfadZeile: Sendable, Equatable, Identifiable {
    public var id: String { label }
    public let label: String
    public let wert: String
}

/// Alles, was das Fenster zeichnet -- `EinstellungsDaten` aus einstellungsfenster.ts.
public struct EinstellungenDaten: Sendable, Equatable {
    public let settings: [String: JSONWert]
    public let vorgaben: [String: JSONWert]
    public let showStopped: Bool
    public let sort: String
    public let machine: String
    public let harnesses: [HarnessSicht]
    public let orchestratorModelle: [ModellSicht]
    public let workerModelle: [ModellSicht]
    public let maschinen: [String]
    public let maschinenPausiert: [String]
    public let askMuster: [AskMuster]
    public let guards: [GuardZeile]
    public let wache: [String: WacheRolle]
    public let deckel: [String: DeckelSicht]
    /// Je Harness die Stufen; fehlt der Harness, blieb die Frage unbeantwortet („nicht ermittelt").
    public let harnessStufen: [String: [String]]
    public let effortCaps: [String: EffortCap]
    public let ausschlussOrdner: [String]
    public let ausschlussMuster: [String]
    public let protokolle: [PfadZeile]
    public let pfade: [PfadZeile]
    public let anmeldung: [String: AnmeldeSicht]
    public let anbieter: [AnbieterSicht]
    public let chatQuellen: [String: ChatQuelle]
    public let chatAnsicht: [String: Bool]
    public let chatAnsichtVorgabeOrchestrator: Bool
    public let chatAnsichtVorgabeWorker: Bool
    public let meldungen: MeldeSicht
    public let meldeEreignisse: [String]
    public let meldeWege: [String]
    public let ollamaEndpunkt: String
    public let sprache: String
    public let thema: String
    public let zustandsfarben: [String: String]
    public let hooks: [HookZeile]

    public init(json j: JSONWert) {
        settings = j["settings"].objekt ?? [:]
        vorgaben = j["vorgaben"].objekt ?? [:]
        showStopped = j["ui"]["showStopped"].bool ?? false
        sort = j["ui"]["sort"].text ?? "recent"
        machine = j["machine"].text ?? ""
        harnesses = (j["harnesses"].liste ?? []).map(HarnessSicht.init)
        orchestratorModelle = (j["orchestratorModelle"].liste ?? []).map(ModellSicht.init)
        workerModelle = (j["workerModelle"].liste ?? []).map(ModellSicht.init)
        maschinen = j["maschinen"].texte
        maschinenPausiert = j["maschinenPausiert"].texte
        askMuster = (j["askMuster"].liste ?? []).map(AskMuster.init)
        guards = (j["guards"].liste ?? []).map(GuardZeile.init)
        wache = (j["wache"].objekt ?? [:]).mapValues(WacheRolle.init)
        deckel = (j["deckel"].objekt ?? [:]).mapValues(DeckelSicht.init)
        harnessStufen = (j["harnessStufen"].objekt ?? [:]).compactMapValues { $0.liste == nil ? nil : $0.texte }
        effortCaps = (j["effortCaps"].objekt ?? [:]).mapValues(EffortCap.init)
        ausschlussOrdner = j["ausschluss"]["ordner"].texte
        ausschlussMuster = j["ausschluss"]["muster"].texte
        protokolle = (j["protokolle"].liste ?? []).map { PfadZeile(label: $0["label"].text ?? "", wert: $0["path"].text ?? "") }
        pfade = (j["pfade"].liste ?? []).map { PfadZeile(label: $0["label"].text ?? "", wert: $0["wert"].text ?? "") }
        anmeldung = (j["anmeldung"].objekt ?? [:]).mapValues(AnmeldeSicht.init)
        anbieter = (j["anbieter"].liste ?? []).map(AnbieterSicht.init)
        chatQuellen = (j["chatQuellen"].objekt ?? [:]).mapValues(ChatQuelle.init)
        chatAnsicht = (j["chatAnsicht"].objekt ?? [:]).compactMapValues(\.bool)
        chatAnsichtVorgabeOrchestrator = j["chatAnsichtVorgabe"]["orchestrator"].bool ?? false
        chatAnsichtVorgabeWorker = j["chatAnsichtVorgabe"]["worker"].bool ?? false
        meldungen = MeldeSicht(j["meldungen"])
        meldeEreignisse = j["meldeEreignisse"].texte
        meldeWege = j["meldeWege"].texte
        ollamaEndpunkt = j["ollamaEndpunkt"].text ?? ""
        sprache = j["sprache"].text ?? "en"
        thema = j["thema"].text ?? "system"
        zustandsfarben = (j["zustandsfarben"].objekt ?? [:]).compactMapValues(\.text)
        hooks = (j["hooks"].liste ?? []).map(HookZeile.init)
    }

    public static func lesen(_ daten: Data) -> EinstellungenDaten { EinstellungenDaten(json: JSONWert.lesen(daten)) }

    /// Eine Einstellung als Zeichenkette, sonst die Vorgabe, sonst leer.
    public func text(_ schluessel: String, _ sonst: String = "") -> String {
        settings[schluessel]?.text ?? vorgaben[schluessel]?.text ?? sonst
    }
    public func zahl(_ schluessel: String, _ sonst: Int) -> Int {
        settings[schluessel]?.int ?? vorgaben[schluessel]?.int ?? sonst
    }
    public func bool(_ schluessel: String, _ sonst: Bool) -> Bool {
        settings[schluessel]?.bool ?? sonst
    }
    /// Steht der Wert auf der Vorgabe (oder fehlt er)? -- fuer das Rueckstell-Zeichen.
    public func stehtAufVorgabe(_ schluessel: String) -> Bool {
        guard let jetzt = settings[schluessel], !jetzt.istNull else { return true }
        guard let v = vorgaben[schluessel] else { return true }
        return jetzt == v
    }
    /// Was von der Auslieferung abweicht, sortiert -- die Grundlage der Programm-Seite.
    public var abweichungen: [String] {
        vorgaben.keys.filter { k in
            guard let s = settings[k], !s.istNull else { return false }
            return s != vorgaben[k]
        }.sorted()
    }
}

// MARK: Kontextstufen (`awb:kontext-stufen`)

public struct KontextStufe: Sendable, Equatable, Identifiable {
    public var id: Int { tokens }
    public let tokens: Int
    public let label: String
    public let bedarfGib: Double
    public let passt: Bool
    public let hinweis: String
    init(_ j: JSONWert) {
        tokens = j["tokens"].int ?? 0; label = j["label"].text ?? ""; bedarfGib = j["bedarfGib"].zahl ?? 0
        passt = j["passt"].bool ?? false; hinweis = j["hinweis"].text ?? ""
    }
}

public struct KontextSicht: Sendable, Equatable {
    public let modell: String
    public let freiMib: Double
    public let gewichteGb: Double
    public let vorgabe: Int
    public let empfehlung: Int
    public let stufen: [KontextStufe]
    init(_ j: JSONWert) {
        modell = j["modell"].text ?? ""; freiMib = j["freiMib"].zahl ?? 0; gewichteGb = j["gewichteGb"].zahl ?? 0
        vorgabe = j["vorgabe"].int ?? 0; empfehlung = j["empfehlung"].int ?? 0
        stufen = (j["stufen"].liste ?? []).map(KontextStufe.init)
    }
}

/// Die Antwort von `awb:kontext-stufen`: entweder die Sicht oder der Grund, warum nicht.
public enum KontextAntwort: Sendable, Equatable {
    case sicht(KontextSicht)
    case fehler(String)

    public static func lesen(_ daten: Data?) -> KontextAntwort {
        guard let d = daten else { return .fehler("keine Antwort") }
        let j = JSONWert.lesen(d)
        if j["ok"].bool == true { return .sicht(KontextSicht(j["sicht"])) }
        return .fehler(j["fehler"].text ?? "unbekannter Fehler")
    }
}

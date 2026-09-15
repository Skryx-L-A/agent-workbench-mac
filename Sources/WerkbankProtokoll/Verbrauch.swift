// Die Verbrauchsseite (Auftrag 3.8): die Nutzlast von `awb:verbrauch-daten`
// und die Abschnitte, die daraus werden -- ohne Fenster, unter `swift test`.
//
// ES WIRD HIER NICHT GERECHNET, was `wb-budget` schon gerechnet hat. Dieselbe
// Auflage wie in verbrauchsfenster.ts: die eine Wahrheit ueber den Verbrauch
// ist das Werkzeug; diese Datei liest sein Ergebnis, filtert es und ordnet es
// zu Abschnitten. Was hier an Arithmetik steht -- Summen, Anteile, der
// Unterschied zweier Zeitraeume --, ist die woertliche Uebertragung von
// `app/src/verbrauch/rechnen.ts` und wird gegen dieselben Faelle geprueft.
//
// EIN ABSCHNITT IST EINE TABELLE, kein Diagramm. Wo die Electron-Fassung ein
// SVG zeichnet (Tagesverlauf, Kontingentbalken, Limitkurve), traegt eine Zeile
// hier ihren `anteil` -- das Fenster macht daraus einen Balken aus einer
// Capsule, dieselbe Form wie die Wochenzeile im Statusfuss (2.5). Der Grund ist
// derselbe wie dort: `ProgressView` und `Grid` zeichnen im ImageRenderer nicht,
// und ein Balken, den kein Belegbild zeigt, ist fuer eine kopflose Pruefung
// nicht da.
import Foundation

// MARK: Die Nutzlast

/// Die sieben Zahlen, die jede Zeile traegt (`Werte` in rechnen.ts).
public struct VerbrauchWerte: Sendable, Equatable {
    public var input: Double
    public var output: Double
    public var cacheWrite: Double
    public var cacheRead: Double
    public var reasoning: Double
    public var nachrichten: Double
    /// input + output + cache_write. Cache-Lesen bleibt draussen.
    public var ohneCacheRead: Double

    public init(input: Double = 0, output: Double = 0, cacheWrite: Double = 0, cacheRead: Double = 0,
                reasoning: Double = 0, nachrichten: Double = 0, ohneCacheRead: Double = 0) {
        self.input = input; self.output = output; self.cacheWrite = cacheWrite; self.cacheRead = cacheRead
        self.reasoning = reasoning; self.nachrichten = nachrichten; self.ohneCacheRead = ohneCacheRead
    }

    init(_ j: JSONWert) {
        input = j["input"].zahl ?? 0
        output = j["output"].zahl ?? 0
        cacheWrite = j["cache_write"].zahl ?? 0
        cacheRead = j["cache_read"].zahl ?? 0
        reasoning = j["reasoning"].zahl ?? 0
        nachrichten = j["nachrichten"].zahl ?? 0
        ohneCacheRead = j["ohne_cache_read"].zahl ?? (input + output + cacheWrite)
    }

    /// Der Wert eines Feldes unter seinem Namen aus der Tabelle (`summe.<feld>`).
    public func feld(_ name: String) -> Double {
        switch name {
        case "input": return input
        case "output": return output
        case "cache_write": return cacheWrite
        case "cache_read": return cacheRead
        case "reasoning": return reasoning
        case "nachrichten": return nachrichten
        default: return ohneCacheRead
        }
    }

    /// Summe ueber mehrere Zeilen (`summiere`): `ohne_cache_read` wird neu
    /// gebildet, nie aufaddiert.
    public static func summe(_ zeilen: [VerbrauchWerte]) -> VerbrauchWerte {
        var s = VerbrauchWerte()
        for z in zeilen {
            s.input += z.input; s.output += z.output; s.cacheWrite += z.cacheWrite
            s.cacheRead += z.cacheRead; s.reasoning += z.reasoning; s.nachrichten += z.nachrichten
        }
        s.ohneCacheRead = s.input + s.output + s.cacheWrite
        return s
    }
}

/// Wie gut die Rate eines Modells ist (`Tempo`).
public struct VerbrauchTempo: Sendable, Equatable {
    public let wert: Double?
    /// gemessen | naeherung | unbekannt
    public let art: String
    /// Der Satz von wb-budget selbst -- Messergebnis, nicht Beschriftung.
    public let grund: String
    public let sekunden: Double?
    init(_ j: JSONWert) {
        wert = j["wert"].zahl
        art = j["art"].text ?? "unbekannt"
        grund = j["grund"].text ?? ""
        sekunden = j["sekunden"].zahl
    }
}

/// Was ein Modell gekostet haette oder gekostet hat (`Preis`).
public struct VerbrauchPreis: Sendable, Equatable {
    public let usd: Double?
    /// abo-aequivalent | katalogpreis | harness-angabe | kein-preis
    public let art: String
    public let quelle: String
    /// true = dieser Betrag wurde NIE abgebucht (Abo oder oertliches Modell).
    public let nieAbgebucht: Bool?
    init(_ j: JSONWert) {
        usd = j["usd"].zahl
        art = j["art"].text ?? ""
        quelle = j["quelle"].text ?? ""
        nieAbgebucht = j["nie_abgebucht"].bool
    }
}

public struct VerbrauchModellZeile: Sendable, Equatable {
    public let harness: String
    public let modell: String
    public let werte: VerbrauchWerte
    public let tempo: VerbrauchTempo
    public let preis: VerbrauchPreis
    /// Copilots eigene Abrechnungseinheit, nur wo sie mitgeschrieben wird.
    public let aiu: Double
    init(_ j: JSONWert) {
        harness = j["harness"].text ?? ""
        modell = j["modell"].text ?? ""
        werte = VerbrauchWerte(j)
        tempo = VerbrauchTempo(j["tempo"])
        preis = VerbrauchPreis(j["preis"])
        aiu = j["aiu"].zahl ?? 0
    }
}

public struct VerbrauchHarnessZeile: Sendable, Equatable {
    public let harness: String
    public let werte: VerbrauchWerte
    init(_ j: JSONWert) { harness = j["harness"].text ?? ""; werte = VerbrauchWerte(j) }
}

public struct VerbrauchSitzungZeile: Sendable, Equatable {
    public let harness: String
    public let sitzung: String
    public let worker: String
    public let ordner: String
    public let modelle: [String]
    public let von: String
    public let bis: String
    public let werte: VerbrauchWerte
    init(_ j: JSONWert) {
        harness = j["harness"].text ?? ""; sitzung = j["sitzung"].text ?? ""
        worker = j["worker"].text ?? ""; ordner = j["ordner"].text ?? ""
        modelle = j["modelle"].texte
        von = j["von"].text ?? ""; bis = j["bis"].text ?? ""
        werte = VerbrauchWerte(j)
    }
}

public struct VerbrauchTagZeile: Sendable, Equatable {
    public let tag: String
    public let harness: String
    public let modell: String
    public let werte: VerbrauchWerte
    init(_ j: JSONWert) {
        tag = j["tag"].text ?? ""; harness = j["harness"].text ?? ""; modell = j["modell"].text ?? ""
        werte = VerbrauchWerte(j)
    }
}

public struct VerbrauchQuelle: Sendable, Equatable {
    public let harness: String
    public let pfad: String
    /// gelesen | leer | fehlt | unlesbar
    public let zustand: String
    public let nachrichten: Double
    public let hinweis: String
    init(_ j: JSONWert) {
        harness = j["harness"].text ?? ""; pfad = j["pfad"].text ?? ""
        zustand = j["zustand"].text ?? ""; nachrichten = j["nachrichten"].zahl ?? 0
        hinweis = j["hinweis"].text ?? ""
    }
}

public struct VerbrauchLuecke: Sendable, Equatable {
    public let harness: String
    public let grund: String
    init(_ j: JSONWert) { harness = j["harness"].text ?? ""; grund = j["grund"].text ?? "" }
}

public struct VerbrauchLimitPunkt: Sendable, Equatable {
    public let ts: String
    public let fuenfStunden: Double?
    public let siebenTage: Double?
    public let fuenfStundenZurueck: String
    public let siebenTageZurueck: String
    init(_ j: JSONWert) {
        ts = j["ts"].text ?? ""
        fuenfStunden = j["five_hour_pct"].zahl
        siebenTage = j["seven_day_pct"].zahl
        fuenfStundenZurueck = j["five_hour_resets_at"].text ?? ""
        siebenTageZurueck = j["seven_day_resets_at"].text ?? ""
    }
}

/// Das Kontingent eines Harness, wie `wb-kontingent` es meldet.
public struct VerbrauchKontingent: Sendable, Equatable, Identifiable {
    public var id: String { harness }
    public let harness: String
    /// keins | zaehler | … -- leer und `keins` heissen beide „hat keines".
    public let art: String
    public let einheit: String
    /// Nur was WIRKLICH als Zahl ankommt; `null` wird nie zu 0 (Befund 03.09.).
    public let verbraucht: Double?
    public let grenze: Double?
    public let rest: String
    public let faelltZurueckAm: String
    public let erschoepft: Bool
    public let hinweis: String

    init(id: String, _ j: JSONWert) {
        harness = id
        let k = j["kontingent"]
        art = k["art"].text ?? ""
        einheit = k["einheit"].text ?? ""
        verbraucht = k["verbraucht"].zahl
        grenze = k["grenze"].zahl
        rest = k["rest"].zeichenkette
        faelltZurueckAm = k["faellt_zurueck_am"].text ?? ""
        erschoepft = j["erschoepft"].bool ?? false
        hinweis = j["hinweis"].text ?? ""
    }

    /// Steht ein Stand da, aus dem sich ein Balken bilden laesst?
    public var hatStand: Bool { verbraucht != nil && art != "keins" && !art.isEmpty }
    public var hatGrenze: Bool { (grenze ?? 0) > 0 }
}

public struct VerbrauchDaten: Sendable, Equatable {
    public let erzeugt: String
    public let von: String
    public let bis: String
    public let tage: Double
    public let gesamt: VerbrauchWerte
    public let jeHarness: [VerbrauchHarnessZeile]
    public let jeModell: [VerbrauchModellZeile]
    public let jeSitzung: [VerbrauchSitzungZeile]
    public let jeTag: [VerbrauchTagZeile]
    public let limits: [VerbrauchLimitPunkt]
    public let kontingente: [VerbrauchKontingent]
    /// Der Grund, wenn `wb-kontingent` gar nichts sagen konnte.
    public let kontingentFehler: String
    public let quellen: [VerbrauchQuelle]
    public let luecken: [VerbrauchLuecke]

    public init(json j: JSONWert) {
        erzeugt = j["erzeugt"].text ?? ""
        von = j["fenster"]["von"].text ?? ""
        bis = j["fenster"]["bis"].text ?? ""
        tage = j["fenster"]["tage"].zahl ?? 0
        gesamt = VerbrauchWerte(j["gesamt"])
        jeHarness = (j["je_harness"].liste ?? []).map(VerbrauchHarnessZeile.init)
        jeModell = (j["je_modell"].liste ?? []).map(VerbrauchModellZeile.init)
        jeSitzung = (j["je_sitzung"].liste ?? []).map(VerbrauchSitzungZeile.init)
        jeTag = (j["je_tag"].liste ?? []).map(VerbrauchTagZeile.init)
        limits = (j["limits"].liste ?? []).map(VerbrauchLimitPunkt.init)
        let h = j["kontingent"]["harnesses"].objekt ?? [:]
        kontingente = h.keys.sorted().map { VerbrauchKontingent(id: $0, h[$0]!) }
        kontingentFehler = j["kontingent"]["fehler"].text ?? ""
        quellen = (j["quellen"].liste ?? []).map(VerbrauchQuelle.init)
        luecken = (j["luecken"].liste ?? []).map(VerbrauchLuecke.init)
    }
}

/// Die Antwort von `awb:verbrauch-daten`: entweder Daten oder ein Grund.
public enum VerbrauchAntwort: Sendable, Equatable {
    case daten(VerbrauchDaten)
    case fehler(String)

    public static func lesen(_ roh: Data?) -> VerbrauchAntwort {
        guard let roh else { return .fehler("keine Antwort") }
        let j = JSONWert.lesen(roh)
        if j["ok"].bool == true { return .daten(VerbrauchDaten(json: j["daten"])) }
        return .fehler(j["fehler"].text ?? "unbekannter Grund")
    }
}

// MARK: Filter und Zahlen

/// Die Einschraenkung der Seite. Leer heisst ALLE -- eine leere Auswahl ist
/// keine Einschraenkung, nie „keine".
public struct VerbrauchAuswahl: Sendable, Equatable {
    public var harness: [String] = []
    public var modell: [String] = []
    public init() {}

    func trifft(_ auswahl: [String], _ wert: String) -> Bool {
        auswahl.isEmpty || auswahl.contains(wert)
    }

    public func modelle(_ zeilen: [VerbrauchModellZeile]) -> [VerbrauchModellZeile] {
        zeilen.filter { trifft(harness, $0.harness) && trifft(modell, $0.modell) }
    }

    public func tage(_ zeilen: [VerbrauchTagZeile]) -> [VerbrauchTagZeile] {
        zeilen.filter { trifft(harness, $0.harness) && trifft(modell, $0.modell) }
    }

    /// Eine Sitzung faehrt oft mehrere Modelle; sie zaehlt mit, sobald EINES der
    /// gewaehlten dabei ist. Ihre Zahlen bleiben die der ganzen Sitzung --
    /// `teilweise` sagt es weiter, statt Genauigkeit vorzutaeuschen.
    public func sitzungen(_ zeilen: [VerbrauchSitzungZeile]) -> [VerbrauchSitzungZeile] {
        zeilen.filter { z in
            trifft(harness, z.harness) && (modell.isEmpty || z.modelle.contains { modell.contains($0) })
        }
    }

    public func teilweise(_ zeilen: [VerbrauchSitzungZeile]) -> Bool {
        guard !modell.isEmpty else { return false }
        return zeilen.contains { z in z.modelle.contains { !modell.contains($0) } }
    }

    public mutating func umschalten(harness id: String) {
        if let i = harness.firstIndex(of: id) { harness.remove(at: i) } else { harness.append(id) }
    }

    public mutating func umschalten(modell id: String) {
        if let i = modell.firstIndex(of: id) { modell.remove(at: i) } else { modell.append(id) }
    }
}

/// Zahlen so, wie ein Mensch sie liest -- dieselben Regeln wie rechnen.ts.
public enum VerbrauchZahlen {
    /// Kurzform fuer enge Stellen: „14,4 Mrd." statt 14448108175.
    public static func kompakt(_ n: Double) -> String {
        let z = abs(n)
        // Immer eine Nachkommastelle, auch bei „6,0k": ohne sie saehe die
        // Kurzform aus wie eine genaue Zahl (rechnen.ts, `toFixed(1)`).
        if z >= 1_000_000_000 { return "\(komma(n / 1_000_000_000, 1, minimum: 1)) Mrd." }
        if z >= 1_000_000 { return "\(komma(n / 1_000_000, 1, minimum: 1)) Mio." }
        if z >= 1_000 { return "\(komma(n / 1_000, 1, minimum: 1))k" }
        return String(Int(n.rounded()))
    }

    /// Die volle Zahl mit Punkten, fuer Tabellen und Titel.
    public static func zahl(_ n: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "de_DE")
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: n.rounded())) ?? String(Int(n.rounded()))
    }

    /// Ein Betrag traegt IMMER zwei Nachkommastellen: „1,5 USD" liest sich wie
    /// eine gerundete Zahl, „1,50 USD" wie ein Preis (rechnen.ts, `usd`).
    public static func usd(_ n: Double) -> String { "\(komma(n, 2, minimum: 2)) USD" }

    public static func prozent(_ n: Double) -> String {
        let gerundet = (n * 10).rounded() / 10
        return gerundet == gerundet.rounded() ? "\(Int(gerundet)) %" : "\(komma(gerundet, 1)) %"
    }

    /// Ein Kontingentstand ohne Nenner: die Stellen richten sich nach der Groesse
    /// der Zahl -- 2,6888 Credits sind auf Hundertstel eine Aussage, auf
    /// Zehntausendstel eine Behauptung ueber die Quelle.
    public static func kontingent(_ v: Double) -> String {
        let stellen = abs(v) >= 100 ? 0 : abs(v) >= 10 ? 1 : 2
        return komma(v, stellen)
    }

    /// Ein Zeitpunkt, wie ihn ein Mensch liest -- Ortszeit, weil er auf eine Uhr sieht.
    public static func zeitpunkt(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter.datum(iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: d)
    }

    static func komma(_ n: Double, _ stellen: Int, minimum: Int = 0) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "de_DE")
        f.minimumFractionDigits = minimum
        f.maximumFractionDigits = stellen
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }
}

extension ISO8601DateFormatter {
    /// Mit UND ohne Sekundenbruchteile -- wb-budget schreibt beides. Je Aufruf
    /// ein eigener Leser: ein `static let` waere geteilter, veraenderlicher
    /// Zustand ueber Aktoren hinweg, und ISO8601DateFormatter ist nicht Sendable.
    static func datum(_ iso: String) -> Date? {
        let mit = ISO8601DateFormatter()
        mit.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = mit.date(from: iso) { return d }
        let ohne = ISO8601DateFormatter()
        ohne.formatOptions = [.withInternetDateTime]
        return ohne.date(from: iso)
    }
}

// MARK: Der Unterschied zweier Zeitraeume

public struct VerbrauchsVergleichZeile: Sendable, Equatable, Identifiable {
    public var id: String { schluessel }
    public let schluessel: String
    public let jetzt: Double
    public let vorher: Double
    public let differenz: Double
    /// nil, wenn vorher 0 war -- ein Prozentwert waere dort eine Division durch null.
    public let prozent: Double?
    /// mehr | weniger | gleich
    public let richtung: String

    init(_ schluessel: String, _ jetzt: Double, _ vorher: Double) {
        self.schluessel = schluessel
        self.jetzt = jetzt
        self.vorher = vorher
        differenz = jetzt - vorher
        prozent = vorher == 0 ? nil : (jetzt - vorher) / vorher * 100
        richtung = jetzt > vorher ? "mehr" : (jetzt < vorher ? "weniger" : "gleich")
    }
}

public enum VerbrauchVergleich {
    /// Die Summen zweier Zeitraeume Posten fuer Posten nebeneinander.
    public static func werte(_ jetzt: VerbrauchWerte, _ vorher: VerbrauchWerte) -> [VerbrauchsVergleichZeile] {
        ["ohne_cache_read", "input", "output", "cache_write", "cache_read", "nachrichten"]
            .map { VerbrauchsVergleichZeile($0, jetzt.feld($0), vorher.feld($0)) }
    }

    /// Dasselbe je Harness. Einer, der nur in EINEM Zeitraum vorkommt, steht
    /// trotzdem da -- mit 0 auf der anderen Seite.
    public static func harnesses(_ jetzt: [VerbrauchHarnessZeile], _ vorher: [VerbrauchHarnessZeile]) -> [VerbrauchsVergleichZeile] {
        var a: [String: Double] = [:], b: [String: Double] = [:]
        for z in jetzt { a[z.harness] = z.werte.ohneCacheRead }
        for z in vorher { b[z.harness] = z.werte.ohneCacheRead }
        return Set(a.keys).union(b.keys).sorted()
            .map { VerbrauchsVergleichZeile($0, a[$0] ?? 0, b[$0] ?? 0) }
            .sorted { abs($0.differenz) > abs($1.differenz) }
    }

    /// Der gleich LANGE Zeitraum unmittelbar davor -- nicht „die Woche davor":
    /// wer drei Tage ansieht, vergleicht mit den drei Tagen davor.
    public static func vorherigerZeitraum(von: String, bis: String) -> (von: String, bis: String)? {
        guard let a = ISO8601DateFormatter.datum(von), let b = ISO8601DateFormatter.datum(bis), b > a else { return nil }
        let dauer = b.timeIntervalSince(a)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return (f.string(from: a.addingTimeInterval(-dauer)), f.string(from: a))
    }
}

// MARK: Die Abschnitte

public struct VerbrauchZeile: Sendable, Equatable, Identifiable {
    public let id: String
    public let zellen: [String]
    /// Ein Satz unter der Zeile -- der Grund einer Naeherung, der Hinweis einer
    /// Quelle. Er ist Messergebnis und wird nicht uebersetzt.
    public let hinweis: String
    /// 0…1, wo die Electron-Fassung einen Balken zeichnet; sonst nil.
    public let anteil: Double?
    /// Eine zweite Marke auf demselben Balken (der erlaubte Anteil der Woche).
    public let marke: Double?

    public init(id: String, zellen: [String], hinweis: String = "", anteil: Double? = nil, marke: Double? = nil) {
        self.id = id; self.zellen = zellen; self.hinweis = hinweis; self.anteil = anteil; self.marke = marke
    }
}

public struct VerbrauchAbschnitt: Sendable, Equatable, Identifiable {
    public let id: String
    public let titel: String
    /// Der Satz ueber der Tabelle -- Beschriftung, keine Messung.
    public let hinweis: String
    public let kopf: [String]
    public let zeilen: [VerbrauchZeile]
    /// Was unter der Tabelle steht (Summen, „weitere N nicht gezeigt").
    public let fuss: String

    public init(id: String, titel: String, hinweis: String = "", kopf: [String] = [],
                zeilen: [VerbrauchZeile] = [], fuss: String = "") {
        self.id = id; self.titel = titel; self.hinweis = hinweis; self.kopf = kopf
        self.zeilen = zeilen; self.fuss = fuss
    }
}

/// Wieviel des Wochenkontingents verbraucht und erlaubt ist -- dieselbe Zahl,
/// die der Statusfuss zeigt. Sie kommt aus `awb:model` und wird hier NICHT ein
/// zweites Mal gerechnet (Entscheidung 3.8).
public struct VerbrauchWoche: Sendable, Equatable {
    public let verbraucht: Double
    public let erlaubt: Double
    public let tag: Int
    public init(verbraucht: Double, erlaubt: Double, tag: Int) {
        self.verbraucht = verbraucht; self.erlaubt = erlaubt; self.tag = tag
    }
}

public enum VerbrauchSeiten {
    /// Wieviele Sitzungszeilen die Tabelle zeigt, bevor sie zaehlt statt aufzulisten.
    public static let sitzungsGrenze = 40

    /// Die Abschnitte in der Reihenfolge der Electron-Fassung (verbrauch.ts
    /// `zeichne`): Kontingente zuerst -- „wieviel darf ich heute noch" ist die
    /// Frage, wegen der diese Seite aufgeht.
    public static func abschnitte(daten d: VerbrauchDaten, auswahl a: VerbrauchAuswahl, texte t: Texte,
                                  woche: VerbrauchWoche?, vergleich: VerbrauchDaten? = nil) -> [VerbrauchAbschnitt] {
        let modelle = a.modelle(d.jeModell)
        let gesamt = VerbrauchWerte.summe(modelle.map(\.werte))
        var raus: [VerbrauchAbschnitt] = [
            kontingente(d, t, woche),
            summen(gesamt, t),
            tage(a.tage(d.jeTag), t),
            harnesses(modelle, t),
            modelleAbschnitt(modelle, t),
            tempo(modelle, t),
            kosten(modelle, t),
            limit(d, t),
            sitzungen(a, d.jeSitzung, t),
        ]
        if let v = vergleich { raus.append(vergleichAbschnitt(d, v, gesamt, t)) }
        raus.append(luecken(d, t))
        raus.append(quellen(d, t))
        return raus
    }

    static func kontingente(_ d: VerbrauchDaten, _ t: Texte, _ woche: VerbrauchWoche?) -> VerbrauchAbschnitt {
        var zeilen: [VerbrauchZeile] = []
        if let w = woche {
            let luft = w.erlaubt - w.verbraucht
            let fuss = "\(t.t("wochen.erlaubt")) \(VerbrauchZahlen.prozent(w.erlaubt)) · "
                + (luft >= 0 ? t.t("wochen.luft", ["0": VerbrauchZahlen.zahl(luft)])
                             : t.t("wochen.darueber", ["0": VerbrauchZahlen.zahl(abs(luft))]))
            zeilen.append(VerbrauchZeile(
                id: "woche", zellen: [t.t("limit.7d"), VerbrauchZahlen.prozent(w.verbraucht), t.t("wochen.tag", ["0": String(w.tag)])],
                hinweis: fuss, anteil: w.verbraucht / 100, marke: w.erlaubt / 100))
        }
        var ohne: [String] = []
        var ohneStand: [String] = []
        for k in d.kontingente {
            guard k.hatStand, let v = k.verbraucht else {
                // Zwei verschiedene Aussagen: „hat kein Kontingent" und „hat
                // eines, aber niemand kann seinen Stand lesen".
                let satz = k.hinweis.isEmpty ? t.t("kontingent.keins") : k.hinweis
                if k.art == "keins" || k.art.isEmpty { ohne.append("\(k.harness): \(satz)") }
                else { ohneStand.append("\(k.harness): \(satz)") }
                continue
            }
            var rechts: [String] = []
            if !k.rest.isEmpty { rechts.append("\(t.t("kontingent.rest")) \(k.rest)") }
            if !k.faelltZurueckAm.isEmpty {
                rechts.append(t.t("kontingent.zurueck", ["0": VerbrauchZahlen.zeitpunkt(k.faelltZurueckAm)]))
            }
            let anteil = k.hatGrenze ? v / (k.grenze ?? 1) : nil
            let wert = k.hatGrenze ? VerbrauchZahlen.prozent(v / (k.grenze ?? 1) * 100) : VerbrauchZahlen.kontingent(v)
            // Steht ein Prozentwert da, sagt die Einheit, WOVON; steht der rohe
            // Wert da, fehlt ohne sie jeder Bezug.
            let bedeutung = k.erschoepft ? t.t("kontingent.erschoepft")
                : (k.hatGrenze ? k.einheit : [k.einheit, t.t("kontingent.verbraucht")].filter { !$0.isEmpty }.joined(separator: " "))
            zeilen.append(VerbrauchZeile(id: "kontingent:\(k.harness)", zellen: [k.harness, wert, rechts.joined(separator: " · ")],
                                         hinweis: bedeutung, anteil: anteil))
        }
        var fuss: [String] = []
        if d.kontingente.isEmpty {
            fuss.append(t.t("kontingent.fehlt", ["0": d.kontingentFehler.isEmpty ? t.t("kontingent.werkzeug.fehlt") : d.kontingentFehler]))
        }
        if woche == nil { fuss.append(t.t("wochen.fehlt")) }
        if !ohneStand.isEmpty { fuss.append("\(t.t("kontingent.ohnestand")): \(ohneStand.joined(separator: " · "))") }
        if !ohne.isEmpty { fuss.append("\(t.t("kontingent.keins")): \(ohne.joined(separator: " · "))") }
        return VerbrauchAbschnitt(id: "kontingent", titel: t.t("kontingent.titel"),
                                  kopf: [], zeilen: zeilen, fuss: fuss.joined(separator: "\n"))
    }

    static func summen(_ w: VerbrauchWerte, _ t: Texte) -> VerbrauchAbschnitt {
        let felder = ["ohne_cache_read", "input", "output", "cache_write", "cache_read", "reasoning", "nachrichten"]
        let zeilen = felder.map { f in
            VerbrauchZeile(id: "summe:\(f)", zellen: [t.t("summe.\(f)"), VerbrauchZahlen.zahl(w.feld(f))])
        }
        return VerbrauchAbschnitt(id: "summe", titel: t.t("summe.titel"), hinweis: t.t("summe.gesamt.hinweis"),
                                  kopf: [], zeilen: zeilen)
    }

    static func tage(_ zeilen: [VerbrauchTagZeile], _ t: Texte) -> VerbrauchAbschnitt {
        guard !zeilen.isEmpty else {
            return VerbrauchAbschnitt(id: "tage", titel: t.t("tage.titel"), hinweis: t.t("tage.leer"))
        }
        var proTag: [String: VerbrauchWerte] = [:]
        for z in zeilen {
            proTag[z.tag] = VerbrauchWerte.summe([proTag[z.tag] ?? VerbrauchWerte(), z.werte])
        }
        let hoechst = proTag.values.map(\.ohneCacheRead).max() ?? 0
        let ausgabe = proTag.keys.sorted().map { tag -> VerbrauchZeile in
            let w = proTag[tag]!
            return VerbrauchZeile(id: "tag:\(tag)", zellen: [tag, VerbrauchZahlen.zahl(w.ohneCacheRead), VerbrauchZahlen.kompakt(w.cacheRead)],
                                  anteil: hoechst > 0 ? w.ohneCacheRead / hoechst : 0)
        }
        return VerbrauchAbschnitt(id: "tage", titel: t.t("tage.titel"), hinweis: t.t("tage.hinweis"),
                                  kopf: ["Tag", t.t("summe.gesamt"), t.t("summe.cache_read")], zeilen: ausgabe)
    }

    static func harnesses(_ modelle: [VerbrauchModellZeile], _ t: Texte) -> VerbrauchAbschnitt {
        var pro: [String: VerbrauchWerte] = [:]
        for m in modelle { pro[m.harness] = VerbrauchWerte.summe([pro[m.harness] ?? VerbrauchWerte(), m.werte]) }
        let zeilen = pro.keys.sorted { (pro[$0]?.ohneCacheRead ?? 0) > (pro[$1]?.ohneCacheRead ?? 0) }.map { h -> VerbrauchZeile in
            let w = pro[h]!
            return VerbrauchZeile(id: "harness:\(h)", zellen: [h, VerbrauchZahlen.zahl(w.ohneCacheRead),
                                                               VerbrauchZahlen.zahl(w.input), VerbrauchZahlen.zahl(w.output),
                                                               VerbrauchZahlen.zahl(w.nachrichten)])
        }
        return VerbrauchAbschnitt(id: "harness", titel: t.t("harness.titel"),
                                  kopf: [t.t("harness.spalte"), t.t("summe.gesamt"), t.t("summe.input"), t.t("summe.output"), t.t("summe.nachrichten")],
                                  zeilen: zeilen, fuss: zeilen.isEmpty ? t.t("leer") : "")
    }

    static func modelleAbschnitt(_ modelle: [VerbrauchModellZeile], _ t: Texte) -> VerbrauchAbschnitt {
        let zeilen = modelle.sorted { $0.werte.ohneCacheRead > $1.werte.ohneCacheRead }.map { m in
            VerbrauchZeile(id: "modell:\(m.harness)/\(m.modell)",
                           zellen: ["\(m.harness) · \(m.modell)", VerbrauchZahlen.zahl(m.werte.ohneCacheRead),
                                    VerbrauchZahlen.zahl(m.werte.input), VerbrauchZahlen.zahl(m.werte.output),
                                    VerbrauchZahlen.kompakt(m.werte.cacheRead)])
        }
        return VerbrauchAbschnitt(id: "modell", titel: t.t("modell.titel"),
                                  kopf: [t.t("modell.spalte"), t.t("summe.gesamt"), t.t("summe.input"), t.t("summe.output"), t.t("summe.cache_read")],
                                  zeilen: zeilen, fuss: zeilen.isEmpty ? t.t("leer") : "")
    }

    static func tempo(_ modelle: [VerbrauchModellZeile], _ t: Texte) -> VerbrauchAbschnitt {
        let mit = modelle.filter { $0.tempo.wert != nil }.sorted { ($0.tempo.wert ?? 0) > ($1.tempo.wert ?? 0) }
        let warnung = t.t("tempo.warnung", ["0": t.t("tempo.zeichen.naeherung")])
        guard !mit.isEmpty else {
            return VerbrauchAbschnitt(id: "tempo", titel: t.t("tempo.titel"), hinweis: warnung, fuss: t.t("leer"))
        }
        let zeilen = mit.map { m -> VerbrauchZeile in
            let zeichen = m.tempo.art == "naeherung" ? t.t("tempo.zeichen.naeherung") : ""
            let wert = "\(zeichen)\(VerbrauchZahlen.komma(m.tempo.wert ?? 0, 1))"
            let grundlage = m.tempo.sekunden.map { t.t("tempo.grundlage", ["0": VerbrauchZahlen.zahl($0)]) } ?? ""
            return VerbrauchZeile(id: "tempo:\(m.harness)/\(m.modell)",
                                  zellen: ["\(m.harness) · \(m.modell)", wert, t.t("tempo.\(m.tempo.art)")],
                                  hinweis: [m.tempo.grund, grundlage].filter { !$0.isEmpty }.joined(separator: " · "))
        }
        return VerbrauchAbschnitt(id: "tempo", titel: t.t("tempo.titel"), hinweis: warnung,
                                  kopf: [t.t("modell.spalte"), t.t("tempo.spalte"), t.t("kosten.art")], zeilen: zeilen)
    }

    static func kosten(_ modelle: [VerbrauchModellZeile], _ t: Texte) -> VerbrauchAbschnitt {
        var aequivalent = 0.0, katalog = 0.0, aiu = 0.0
        var ohnePreis: [String] = []
        var zeilen: [VerbrauchZeile] = []
        for m in modelle {
            aiu += m.aiu
            guard let usd = m.preis.usd else {
                if m.werte.ohneCacheRead > 0 { ohnePreis.append("\(m.harness)/\(m.modell)") }
                continue
            }
            if m.preis.art == "kein-preis" {
                if m.werte.ohneCacheRead > 0 && usd == 0 && m.preis.nieAbgebucht != true { ohnePreis.append("\(m.harness)/\(m.modell)") }
                continue
            }
            if m.preis.nieAbgebucht == true { aequivalent += usd } else { katalog += usd }
            zeilen.append(VerbrauchZeile(id: "kosten:\(m.harness)/\(m.modell)",
                                         zellen: ["\(m.harness) · \(m.modell)", VerbrauchZahlen.usd(usd), t.t("kosten.art.\(m.preis.art)")],
                                         hinweis: m.preis.nieAbgebucht == true ? t.t("kosten.nie_abgebucht") : m.preis.quelle))
        }
        var fuss: [String] = []
        if aequivalent > 0 { fuss.append("\(t.t("kosten.summe.aequivalent")): \(VerbrauchZahlen.usd(aequivalent))") }
        if katalog > 0 { fuss.append("\(t.t("kosten.summe.katalog")): \(VerbrauchZahlen.usd(katalog))") }
        if aiu > 0 { fuss.append("\(t.t("kosten.aiu")): \(VerbrauchZahlen.kontingent(aiu))") }
        if !ohnePreis.isEmpty { fuss.append("\(t.t("kosten.ohne")): \(ohnePreis.sorted().joined(separator: ", "))") }
        return VerbrauchAbschnitt(id: "kosten", titel: t.t("kosten.titel"), hinweis: t.t("kosten.zwei"),
                                  kopf: [t.t("modell.spalte"), t.t("kosten.usd"), t.t("kosten.art")],
                                  zeilen: zeilen, fuss: fuss.joined(separator: "\n"))
    }

    static func limit(_ d: VerbrauchDaten, _ t: Texte) -> VerbrauchAbschnitt {
        guard let letzter = d.limits.last else {
            return VerbrauchAbschnitt(id: "limit", titel: t.t("limit.titel"), hinweis: t.t("limit.leer"), fuss: t.t("limit.quelle"))
        }
        var zeilen: [VerbrauchZeile] = []
        for (feld, name, wert, zurueck) in [
            ("5h", t.t("limit.5h"), letzter.fuenfStunden, letzter.fuenfStundenZurueck),
            ("7d", t.t("limit.7d"), letzter.siebenTage, letzter.siebenTageZurueck),
        ] {
            guard let w = wert else { continue }
            var rechts: [String] = [t.t("limit.stand", ["0": VerbrauchZahlen.zeitpunkt(letzter.ts)])]
            if !zurueck.isEmpty {
                rechts.append(t.t("limit.reset.naechster", ["0": VerbrauchZahlen.zeitpunkt(zurueck)]))
            }
            zeilen.append(VerbrauchZeile(id: "limit:\(feld)", zellen: [name, VerbrauchZahlen.prozent(w), rechts.joined(separator: " · ")],
                                         anteil: w / 100))
        }
        // Ein Ruecksetzpunkt ist ein Sprung nach unten: wo der Stand faellt, war
        // das Fenster zu Ende. Die Zahl ersetzt die Kurve der Electron-Fassung.
        var ruecksetzer = 0
        var vorher: Double?
        for p in d.limits {
            if let w = p.siebenTage, let v = vorher, w < v { ruecksetzer += 1 }
            vorher = p.siebenTage ?? vorher
        }
        let fuss = [t.t("limit.reset.anzahl", ["0": String(ruecksetzer)]), t.t("limit.quelle")].joined(separator: "\n")
        return VerbrauchAbschnitt(id: "limit", titel: t.t("limit.titel"), kopf: [], zeilen: zeilen, fuss: fuss)
    }

    static func sitzungen(_ a: VerbrauchAuswahl, _ alle: [VerbrauchSitzungZeile], _ t: Texte) -> VerbrauchAbschnitt {
        let gefiltert = a.sitzungen(alle).sorted { $0.werte.ohneCacheRead > $1.werte.ohneCacheRead }
        let gezeigt = Array(gefiltert.prefix(sitzungsGrenze))
        let zeilen = gezeigt.map { s in
            VerbrauchZeile(id: "sitzung:\(s.sitzung)/\(s.worker)",
                           zellen: [s.sitzung, s.worker.isEmpty ? t.t("sitzung.ohne_worker") : s.worker,
                                    s.ordner, VerbrauchZahlen.zahl(s.werte.ohneCacheRead),
                                    "\(VerbrauchZahlen.zeitpunkt(s.von)) – \(VerbrauchZahlen.zeitpunkt(s.bis))"])
        }
        var fuss: [String] = []
        if gefiltert.count > gezeigt.count {
            fuss.append(t.t("sitzung.mehr", ["0": String(gefiltert.count - gezeigt.count)]))
        }
        if a.teilweise(gefiltert) { fuss.append(t.t("filter.aktiv")) }
        return VerbrauchAbschnitt(id: "sitzung", titel: t.t("sitzung.titel"),
                                  kopf: [t.t("sitzung.spalte"), t.t("sitzung.worker"), t.t("sitzung.ordner"),
                                         t.t("summe.gesamt"), t.t("sitzung.zeitraum")],
                                  zeilen: zeilen, fuss: fuss.joined(separator: "\n"))
    }

    static func vergleichAbschnitt(_ d: VerbrauchDaten, _ vorher: VerbrauchDaten,
                                   _ gesamt: VerbrauchWerte, _ t: Texte) -> VerbrauchAbschnitt {
        func zeile(_ v: VerbrauchsVergleichZeile, _ name: String, _ id: String) -> VerbrauchZeile {
            let zeichen = t.t("zeichen.\(v.richtung == "mehr" ? "mehr" : (v.richtung == "weniger" ? "weniger" : "gleich"))")
            let anteil = v.prozent.map { VerbrauchZahlen.prozent($0) } ?? t.t("vergleich.kein_vorher")
            return VerbrauchZeile(id: id, zellen: [name, VerbrauchZahlen.zahl(v.jetzt), VerbrauchZahlen.zahl(v.vorher),
                                                   "\(zeichen) \(VerbrauchZahlen.zahl(abs(v.differenz)))", anteil])
        }
        var zeilen = VerbrauchVergleich.werte(gesamt, vorher.gesamt).map { zeile($0, t.t("summe.\($0.schluessel)"), "vergleich:\($0.schluessel)") }
        zeilen += VerbrauchVergleich.harnesses(d.jeHarness, vorher.jeHarness).map { zeile($0, $0.schluessel, "vergleich-harness:\($0.schluessel)") }
        return VerbrauchAbschnitt(id: "vergleich", titel: t.t("vergleich.titel"),
                                  kopf: ["", t.t("vergleich.jetzt"), t.t("vergleich.vorher"), t.t("vergleich.differenz"), "%"],
                                  zeilen: zeilen,
                                  fuss: "\(VerbrauchZahlen.zeitpunkt(vorher.von)) – \(VerbrauchZahlen.zeitpunkt(vorher.bis))")
    }

    static func luecken(_ d: VerbrauchDaten, _ t: Texte) -> VerbrauchAbschnitt {
        let zeilen = d.luecken.map { VerbrauchZeile(id: "luecke:\($0.harness)", zellen: [$0.harness, $0.grund]) }
        return VerbrauchAbschnitt(id: "luecke", titel: t.t("luecke.titel"),
                                  hinweis: zeilen.isEmpty ? "" : t.t("luecke.einleitung"),
                                  kopf: zeilen.isEmpty ? [] : [t.t("luecke.spalte"), t.t("luecke.grund")], zeilen: zeilen)
    }

    static func quellen(_ d: VerbrauchDaten, _ t: Texte) -> VerbrauchAbschnitt {
        let zeilen = d.quellen.map { q in
            VerbrauchZeile(id: "quelle:\(q.harness)/\(q.pfad)",
                           zellen: [t.t("zeichen.\(q.zustand)"), q.harness, q.pfad,
                                    t.t("quelle.zustand.\(q.zustand)"),
                                    t.t("quelle.nachrichten", ["0": VerbrauchZahlen.zahl(q.nachrichten)])],
                           hinweis: q.hinweis)
        }
        return VerbrauchAbschnitt(id: "quelle", titel: t.t("quelle.titel"),
                                  kopf: ["", t.t("harness.spalte"), t.t("quelle.spalte"), "", ""], zeilen: zeilen)
    }

    /// Die Chips der Harness-Zeile: was ueberhaupt etwas verbraucht hat.
    public static func harnessListe(_ modelle: [VerbrauchModellZeile]) -> [(id: String, tokens: Double)] {
        var pro: [String: Double] = [:]
        for m in modelle { pro[m.harness, default: 0] += m.werte.ohneCacheRead }
        return pro.keys.sorted { pro[$0]! > pro[$1]! }.map { ($0, pro[$0]!) }
    }

    /// Die Chips der Modell-Zeile, eingeschraenkt auf die gewaehlten Harnesses.
    public static func modellListe(_ modelle: [VerbrauchModellZeile], _ a: VerbrauchAuswahl) -> [(id: String, tokens: Double)] {
        var pro: [String: Double] = [:]
        for m in modelle where a.harness.isEmpty || a.harness.contains(m.harness) {
            pro[m.modell, default: 0] += m.werte.ohneCacheRead
        }
        return pro.keys.sorted { pro[$0]! > pro[$1]! }.map { ($0, pro[$0]!) }
    }
}

// Die Chat-Sitzung, so wie der Kern sie hergibt (Auftrag 3.1 und 3.2,
// mac/PLAN.md): der Stand aus `awb:chat-stand-neu` und `awb:chat-daten`
// (main/chatbuehne.ts `ChatStandNachricht`), die Bloecke aus
// chat/sdkstrom.ts, und die reinen Rechnungen darum herum -- das Zusammen-
// fuehren der Teilstaende (nur das Geaenderte reist, Befund B1 vom 12.08.),
// die Vervollstaendigung im Eingabefeld (chatbuehne/vervollstaendigung.ts) und
// der kleine Markdown-Leser (chat/markdown.ts).
//
// ALLES HIER IST REIN: kein Fenster, kein Kern, kein Prozess. Deshalb liegt es
// in der Protokollschicht und laeuft unter `swift test` -- die Ansicht
// (Werkbank/ChatBuehne.swift) kann es nur noch falsch zeichnen, nicht mehr
// falsch entscheiden. Die Feldnamen sind die des Kerns, unveraendert: es gibt
// EINE Logik und zwei Oberflaechen (mac/PROTOKOLL.md).
//
// FREMDER TEXT BLEIBT TEXT (freigabenmarkup, 05.09.): der Markdown-Leser
// erzeugt AttributedStrings mit Praesentationsabsichten (fett, kursiv, Code),
// nie Markup und nie einen Link -- eine Beschriftung `[x](y)` wird zu `x`,
// wie in der Electron-Fassung („Links als Text“).
import Foundation

// MARK: - Die Bloecke (chat/sdkstrom.ts)

/// Eine Textzeile des Menschen (`mensch`), des Programms (`agent`), sein
/// Denken (`denken`) oder eine Zeile des Systems (`system`).
public struct ChatTextBlock: Sendable, Equatable {
    public let art: String
    public let id: String
    public let rev: Int
    public let text: String
    /// Laeuft der Text gerade noch ein?
    public let offen: Bool
    public init(art: String, id: String, rev: Int = 0, text: String, offen: Bool = false) {
        self.art = art; self.id = id; self.rev = rev; self.text = text; self.offen = offen
    }
}

/// Ein Werkzeugaufruf: Titelzeile „Bash — <description>“, darunter EIN und AUS.
public struct ChatWerkzeugBlock: Sendable, Equatable {
    public let id: String
    public let rev: Int
    public let name: String
    public let beschreibung: String
    public let ein: String
    public let einVoll: String
    public let aus: String
    public let fehler: Bool
    public let laeuft: Bool
    public init(id: String, rev: Int = 0, name: String, beschreibung: String = "", ein: String = "", einVoll: String = "", aus: String = "", fehler: Bool = false, laeuft: Bool = false) {
        self.id = id; self.rev = rev; self.name = name; self.beschreibung = beschreibung; self.ein = ein; self.einVoll = einVoll; self.aus = aus; self.fehler = fehler; self.laeuft = laeuft
    }
}

/// Eine Freigabefrage des Prozesses -- sie BRAUCHT eine Antwort.
public struct ChatFreigabeBlock: Sendable, Equatable {
    public let id: String
    public let rev: Int
    public let anfrageId: String
    public let name: String
    public let beschreibung: String
    public let ein: String
    public let einVoll: String
    public let offen: Bool
    /// '' | erlaubt | abgelehnt | zurueckgezogen
    public let entschieden: String
    /// Ohne Kennung keine Knoepfe (Befund B7).
    public let defekt: Bool
    public init(id: String, rev: Int = 0, anfrageId: String, name: String, beschreibung: String = "", ein: String = "", einVoll: String = "", offen: Bool = true, entschieden: String = "", defekt: Bool = false) {
        self.id = id; self.rev = rev; self.anfrageId = anfrageId; self.name = name; self.beschreibung = beschreibung; self.ein = ein; self.einVoll = einVoll; self.offen = offen; self.entschieden = entschieden; self.defekt = defekt
    }
}

public enum ChatBlock: Sendable, Equatable, Identifiable {
    case text(ChatTextBlock)
    case werkzeug(ChatWerkzeugBlock)
    case freigabe(ChatFreigabeBlock)

    public var id: String {
        switch self {
        case .text(let b): return b.id
        case .werkzeug(let b): return b.id
        case .freigabe(let b): return b.id
        }
    }

    public var rev: Int {
        switch self {
        case .text(let b): return b.rev
        case .werkzeug(let b): return b.rev
        case .freigabe(let b): return b.rev
        }
    }

    /// mensch | agent | denken | system | werkzeug | freigabe
    public var art: String {
        switch self {
        case .text(let b): return b.art
        case .werkzeug: return "werkzeug"
        case .freigabe: return "freigabe"
        }
    }

    /// Aus einem JSON-Objekt des Kerns; nil, wenn `art` oder `id` fehlt.
    public static func lesen(_ o: [String: Any]) -> ChatBlock? {
        guard let art = o["art"] as? String, let id = o["id"] as? String else { return nil }
        let rev = o["rev"] as? Int ?? 0
        func s(_ k: String) -> String { o[k] as? String ?? "" }
        func b(_ k: String) -> Bool { o[k] as? Bool ?? false }
        switch art {
        case "werkzeug":
            return .werkzeug(ChatWerkzeugBlock(id: id, rev: rev, name: s("name"), beschreibung: s("beschreibung"), ein: s("ein"), einVoll: s("einVoll"), aus: s("aus"), fehler: b("fehler"), laeuft: b("laeuft")))
        case "freigabe":
            return .freigabe(ChatFreigabeBlock(id: id, rev: rev, anfrageId: s("anfrageId"), name: s("name"), beschreibung: s("beschreibung"), ein: s("ein"), einVoll: s("einVoll"), offen: b("offen"), entschieden: s("entschieden"), defekt: b("defekt")))
        case "mensch", "agent", "denken", "system":
            return .text(ChatTextBlock(art: art, id: id, rev: rev, text: s("text"), offen: b("offen")))
        default:
            return nil
        }
    }
}

/// Ein Slash-Befehl des Harness (aus der Antwort auf den Handschlag).
public struct Slashbefehl: Sendable, Equatable {
    public let name: String
    public let beschreibung: String
    public let argumente: String
    public init(name: String, beschreibung: String = "", argumente: String = "") {
        self.name = name; self.beschreibung = beschreibung; self.argumente = argumente
    }
    static func lesen(_ o: [String: Any]) -> Slashbefehl? {
        guard let name = o["name"] as? String, !name.isEmpty else { return nil }
        return Slashbefehl(name: name, beschreibung: o["beschreibung"] as? String ?? "", argumente: o["argumente"] as? String ?? "")
    }
}

/// Der Kopf des Gespraechs -- alles ausser den Bloecken (sdkstrom.ts `Gespraech`).
public struct ChatKopf: Sendable, Equatable {
    public var sessionId = ""
    public var modell = ""
    public var ordner = ""
    public var modus = ""
    public var arbeitet = false
    public var wartetAufFreigabe = false
    public var tokens = 0
    public var kontext = 0
    public var kosten: Double = -1
    public var fehler = ""
    public var initGesehen = false
    public var takt = 0
    public var modi: [String] = []
    public var modusFehler = ""
    public init() {}

    static func lesen(_ o: [String: Any]) -> ChatKopf {
        var k = ChatKopf()
        k.sessionId = o["sessionId"] as? String ?? ""
        k.modell = o["modell"] as? String ?? ""
        k.ordner = o["ordner"] as? String ?? ""
        k.modus = o["modus"] as? String ?? ""
        k.arbeitet = o["arbeitet"] as? Bool ?? false
        k.wartetAufFreigabe = o["wartetAufFreigabe"] as? Bool ?? false
        k.tokens = o["tokens"] as? Int ?? 0
        k.kontext = o["kontext"] as? Int ?? 0
        k.kosten = (o["kosten"] as? NSNumber)?.doubleValue ?? -1
        k.fehler = o["fehler"] as? String ?? ""
        k.initGesehen = o["initGesehen"] as? Bool ?? false
        k.takt = o["takt"] as? Int ?? 0
        k.modi = (o["modi"] as? [Any])?.compactMap { $0 as? String } ?? []
        k.modusFehler = o["modusFehler"] as? String ?? ""
        return k
    }
}

/// Die Statusleiste unter dem Gespraech (chatbuehne.ts `ChatStatus`): dieselben
/// Groessen wie die Zeile unter einer Terminal-Sitzung.
public struct ChatStatus: Sendable, Equatable {
    public var ordner = ""
    public var zweig = ""
    public var modell = ""
    public var tokens = 0
    public var fenster = 0
    public var kosten: Double = -1
    public var fuenfStunden: Double = -1
    public var siebenTage: Double = -1
    public var zurueck = ""
    public init() {}

    static func lesen(_ o: [String: Any]) -> ChatStatus {
        var s = ChatStatus()
        s.ordner = o["ordner"] as? String ?? ""
        s.zweig = o["zweig"] as? String ?? ""
        s.modell = o["modell"] as? String ?? ""
        s.tokens = o["tokens"] as? Int ?? 0
        s.fenster = o["fenster"] as? Int ?? 0
        s.kosten = (o["kosten"] as? NSNumber)?.doubleValue ?? -1
        s.fuenfStunden = (o["fuenfStunden"] as? NSNumber)?.doubleValue ?? -1
        s.siebenTage = (o["siebenTage"] as? NSNumber)?.doubleValue ?? -1
        s.zurueck = o["zurueck"] as? String ?? ""
        return s
    }

    /// Eine Zahl kurz: 46k, 1.0M -- wie in der Statuszeile des Terminals.
    public static func kompakt(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return "\(Int((Double(n) / 1_000).rounded()))k" }
        return String(n)
    }

    /// Die Farbstufe einer Prozentzahl -- dieselben Schwellen wie im Terminal
    /// (statusline-command.sh `col_pct`): ab 60 gelb, ab 85 rot.
    public static func stufe(_ prozent: Double) -> String {
        if prozent >= 85 { return "aus" }
        if prozent >= 60 { return "will" }
        return "ruhig"
    }

    /// Der Anteil des belegten Kontexts (0…1), oder nil ohne Fenstergroesse.
    public var kontextAnteil: Double? {
        guard tokens > 0, fenster > 0 else { return nil }
        return Double(tokens) / Double(fenster)
    }
}

/// `awb:chat-stand-neu` und die Antwort auf `awb:chat-daten` (chatbuehne.ts
/// `ChatStandNachricht`): der Kopf immer, die Bloecke nur, soweit geaendert.
public struct ChatStandNachricht: Sendable, Equatable {
    public let id: String
    public let kopf: ChatKopf
    /// Nur, wenn sie NEU sind; nil heisst: unveraendert.
    public let befehle: [Slashbefehl]?
    public let geaendert: [ChatBlock]
    public let ordnung: [String]
    public let seit: Int
    public let sprache: String
    public let laeuft: Bool
    public let neustartMoeglich: Bool
    public let status: ChatStatus?

    public init(id: String, kopf: ChatKopf = ChatKopf(), befehle: [Slashbefehl]? = nil, geaendert: [ChatBlock] = [], ordnung: [String] = [], seit: Int = 0, sprache: String = "de", laeuft: Bool = true, neustartMoeglich: Bool = false, status: ChatStatus? = nil) {
        self.id = id; self.kopf = kopf; self.befehle = befehle; self.geaendert = geaendert; self.ordnung = ordnung; self.seit = seit; self.sprache = sprache; self.laeuft = laeuft; self.neustartMoeglich = neustartMoeglich; self.status = status
    }

    /// Aus der JSON-Zeile des Kerns (Ereignis oder `value` der Antwort). nil ohne `id`.
    public static func lesen(_ zeile: Data) -> ChatStandNachricht? {
        guard let o = try? JSONSerialization.jsonObject(with: zeile) as? [String: Any] else { return nil }
        return lesen(o)
    }

    public static func lesen(_ o: [String: Any]) -> ChatStandNachricht? {
        guard let id = o["id"] as? String, !id.isEmpty else { return nil }
        let kopf = ChatKopf.lesen(o["kopf"] as? [String: Any] ?? [:])
        let befehle = (o["befehle"] as? [Any]).map { $0.compactMap { ($0 as? [String: Any]).flatMap(Slashbefehl.lesen) } }
        let geaendert = (o["geaendert"] as? [Any] ?? []).compactMap { ($0 as? [String: Any]).flatMap(ChatBlock.lesen) }
        let ordnung = (o["ordnung"] as? [Any] ?? []).compactMap { $0 as? String }
        let status = (o["status"] as? [String: Any]).map(ChatStatus.lesen)
        return ChatStandNachricht(id: id, kopf: kopf, befehle: befehle, geaendert: geaendert, ordnung: ordnung,
                                  seit: o["seit"] as? Int ?? 0, sprache: o["sprache"] as? String ?? "de",
                                  laeuft: o["laeuft"] as? Bool ?? true, neustartMoeglich: o["neustartMoeglich"] as? Bool ?? false, status: status)
    }
}

// MARK: - Der Verlauf: Teilstaende zusammenfuehren (Befund B1)

/// Das Gespraech, wie die Ansicht es haelt: die Bloecke in Ordnung, je Kennung
/// die letzte Fassung. `anwenden` nimmt einen Stand auf -- was hereinkam,
/// ersetzt seine Fassung; was nicht mehr in `ordnung` steht, ist weg; die
/// Reihenfolge ist die der Ordnung. Genau `Chatansicht.zeichne` (ansicht.ts),
/// ohne DOM.
public struct ChatVerlauf: Sendable, Equatable {
    public private(set) var bloecke: [ChatBlock] = []
    private var nachId: [String: ChatBlock] = [:]
    public private(set) var kopf = ChatKopf()
    public private(set) var befehle: [Slashbefehl] = []
    public private(set) var laeuft = true
    public private(set) var neustartMoeglich = false
    public private(set) var sprache = "de"
    public private(set) var status = ChatStatus()
    /// Wie viele Staende aufgenommen wurden.
    public private(set) var staende = 0

    public init() {}

    /// Nimmt einen Stand auf. Gibt die Kennungen zurueck, deren Fassung sich
    /// wirklich geaendert hat (fuer die Messung und das Neuzeichnen).
    @discardableResult
    public mutating func anwenden(_ n: ChatStandNachricht) -> [String] {
        staende += 1
        kopf = n.kopf
        if let b = n.befehle { befehle = b }
        laeuft = n.laeuft
        neustartMoeglich = n.neustartMoeglich
        sprache = n.sprache
        if let s = n.status { status = s }
        var geaendert: [String] = []
        for b in n.geaendert {
            if nachId[b.id] != b { geaendert.append(b.id) }
            nachId[b.id] = b
        }
        let bekannt = Set(n.ordnung)
        for id in nachId.keys where !bekannt.contains(id) { nachId[id] = nil }
        bloecke = n.ordnung.compactMap { nachId[$0] }
        return geaendert
    }

    /// Der Zustand, wie der Kopf ihn nennt (ansicht.ts `zeichneKopf`).
    public var zustand: String {
        if !laeuft { return "beendet" }
        if kopf.wartetAufFreigabe { return "freigabe" }
        if kopf.arbeitet { return "arbeitet" }
        return "wartet"
    }

    /// Steht der Halt-Knopf: nur, solange wirklich etwas laeuft.
    public var haltMoeglich: Bool { laeuft && kopf.arbeitet && !kopf.wartetAufFreigabe }

    /// Der naechste Freigabemodus in der Liste des Harness (ansicht.ts `modusWeiter`).
    public var naechsterModus: String? {
        guard !kopf.modi.isEmpty else { return nil }
        let i = kopf.modi.firstIndex(of: kopf.modus) ?? -1
        return kopf.modi[(i + 1) % kopf.modi.count]
    }
}

// MARK: - Die Vervollstaendigung (chatbuehne/vervollstaendigung.ts)

public enum Vervollart: String, Sendable { case befehl, datei }

/// Was an der Schreibmarke steht -- nil, wenn nichts vorzuschlagen ist.
public struct ChatAusloeser: Sendable, Equatable {
    public let art: Vervollart
    /// Das Getippte hinter dem Auslosezeichen bis zur SCHREIBMARKE.
    public let muster: String
    /// Die Stelle des Auslosezeichens (UTF-16-Offset) -- von hier an wird ersetzt.
    public let von: Int
    /// Bis zum WORTENDE, nicht zur Marke (Reviewbefund 8).
    public let bis: Int
}

/// Ein Eintrag der `@`-Liste, wie main/chatdateien.ts ihn liefert.
public struct Dateivorschlag: Sendable, Equatable {
    public let pfad: String
    public let ordner: Bool
    public init(pfad: String, ordner: Bool) { self.pfad = pfad; self.ordner = ordner }
}

/// Ein Eintrag, wie die Liste ihn zeigt.
public struct Vorschlag: Sendable, Equatable, Identifiable {
    public var id: String { wert }
    public let wert: String
    public let satz: String
    public let ordner: Bool
    public init(wert: String, satz: String = "", ordner: Bool = false) { self.wert = wert; self.satz = satz; self.ordner = ordner }
}

public enum ChatVervollstaendigung {
    private static func istLeer(_ c: Character) -> Bool { c.isWhitespace || c.isNewline }

    /// DIE REGELN (vervollstaendigung.ts `ausloeser`): `/` nur als ERSTES
    /// Zeichen des Feldes; `@` ueberall, aber nur am Wortanfang; ein
    /// Leerzeichen im Muster beendet beide. Die Stellen sind UTF-16-Offsets,
    /// wie NSTextView sie fuehrt.
    public static func ausloeser(_ text: String, marke: Int) -> ChatAusloeser? {
        let z = Array(text.utf16).map { Character(UnicodeScalar($0) ?? " ") }
        let hier = max(0, min(marke, z.count))
        var ende = hier
        while ende < z.count && !istLeer(z[ende]) { ende += 1 }
        if z.first == "/" {
            let muster = String(z[1..<hier])
            if hier >= 1 && !muster.contains(where: istLeer) { return ChatAusloeser(art: .befehl, muster: muster, von: 0, bis: ende) }
        }
        var i = hier - 1
        while i >= 0 {
            let c = z[i]
            if istLeer(c) { return nil }
            if c != "@" { i -= 1; continue }
            let davor: Character? = i == 0 ? nil : z[i - 1]
            if let d = davor, !istLeer(d) { return nil }
            return ChatAusloeser(art: .datei, muster: String(z[(i + 1)..<hier]), von: i, bis: ende)
        }
        return nil
    }

    /// Den Vorschlag einsetzen: neuer Text UND neue Marke (vervollstaendigung.ts `einsetzen`).
    public static func einsetzen(_ text: String, _ a: ChatAusloeser, wahl: String, ordner: Bool = false) -> (text: String, marke: Int) {
        let ns = text as NSString
        let kopf = a.art == .befehl ? "/" : "@"
        let rest = ns.substring(from: min(a.bis, ns.length))
        let schwanz = ordner ? "/" : (rest.first.map(istLeer) == true ? "" : " ")
        let neu = kopf + wahl + schwanz
        let vorne = ns.substring(to: min(a.von, ns.length))
        return (vorne + neu + rest, (vorne as NSString).length + (neu as NSString).length)
    }

    /// Die Befehlsliste filtern: was so ANFAENGT vor dem, was es nur enthaelt;
    /// innerhalb einer Stufe alphabetisch.
    public static func filtereBefehle(_ liste: [Slashbefehl], _ muster: String, hoechstens: Int = 12) -> [Slashbefehl] {
        let m = muster.trimmingCharacters(in: .whitespaces).lowercased()
        if m.isEmpty { return Array(liste.prefix(hoechstens)) }
        var treffer: [(Slashbefehl, Int)] = []
        for e in liste {
            let n = e.name.lowercased()
            if n.hasPrefix(m) { treffer.append((e, 0)) } else if n.contains(m) { treffer.append((e, 1)) }
        }
        treffer.sort { a, b in a.1 != b.1 ? a.1 < b.1 : a.0.name.localizedCompare(b.0.name) == .orderedAscending }
        return treffer.prefix(hoechstens).map(\.0)
    }

    /// Die Dateiliste filtern, drei Stufen: Dateiname beginnt so, Pfad beginnt
    /// so, kommt irgendwo vor; kuerzere Pfade zuerst.
    public static func filtereDateien(_ liste: [Dateivorschlag], _ muster: String, hoechstens: Int = 12) -> [Dateivorschlag] {
        let m = muster.trimmingCharacters(in: .whitespaces).lowercased()
        if m.isEmpty { return Array(liste.prefix(hoechstens)) }
        var treffer: [(Dateivorschlag, Int)] = []
        for v in liste {
            let pfad = v.pfad.lowercased()
            let name = pfad.split(separator: "/").last.map(String.init) ?? pfad
            if name.hasPrefix(m) { treffer.append((v, 0)) } else if pfad.hasPrefix(m) { treffer.append((v, 1)) } else if pfad.contains(m) { treffer.append((v, 2)) }
        }
        treffer.sort { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            if a.0.pfad.count != b.0.pfad.count { return a.0.pfad.count < b.0.pfad.count }
            return a.0.pfad.localizedCompare(b.0.pfad) == .orderedAscending
        }
        return treffer.prefix(hoechstens).map(\.0)
    }
}

// MARK: - Der kleine Markdown-Leser (chat/markdown.ts)

/// Was der Leser aus einem Text macht: Bloecke, jeder mit fertig ausgezeichnetem Text.
public enum MarkdownBlock: Sendable, Equatable {
    case absatz(AttributedString)
    case ueberschrift(Int, AttributedString)
    case code(String)
    case liste(geordnet: Bool, [AttributedString])
    case zitat(AttributedString)
    case tabelle(kopf: [AttributedString], zeilen: [[AttributedString]])
}

public enum ChatMarkdown {
    /// DIE EINE ABFRAGE. Nullbytes fliegen vorsorglich raus (dieselbe Vorsicht
    /// wie `kuerzen()` in chat/leser.ts).
    public static func bloecke(_ text: String) -> [MarkdownBlock] {
        let zeilen = text.replacingOccurrences(of: "\u{0}", with: "").components(separatedBy: "\n")
        var raus: [MarkdownBlock] = []
        var i = 0
        while i < zeilen.count {
            let zeile = zeilen[i]
            if zeile.trimmingCharacters(in: .whitespaces).isEmpty { i += 1; continue }

            // Der Zaun MUSS jede Zeile treffen, die mit ``` beginnt (Reviewer-
            // Befund B1, 12.08.), unabhaengig vom Info-String; der Absatz-Zweig
            // bricht bei GENAU demselben Muster ab.
            if istZaun(zeile) {
                var inhalt: [String] = []
                i += 1
                while i < zeilen.count && !istZaunEnde(zeilen[i]) { inhalt.append(zeilen[i]); i += 1 }
                i += 1
                raus.append(.code(inhalt.joined(separator: "\n")))
                continue
            }

            if let (ebene, rest) = ueberschrift(zeile) {
                raus.append(.ueberschrift(ebene, inline(rest)))
                i += 1
                continue
            }

            if istTabellenkopf(zeilen, i) {
                let kopf = tabellenZellen(zeile).map(inline)
                i += 2
                var daten: [[AttributedString]] = []
                while i < zeilen.count, !zeilen[i].trimmingCharacters(in: .whitespaces).isEmpty, zeilen[i].contains("|") {
                    daten.append(tabellenZellen(zeilen[i]).map(inline))
                    i += 1
                }
                raus.append(.tabelle(kopf: kopf, zeilen: daten))
                continue
            }

            if zeile.hasPrefix(">") {
                var inhalt: [String] = []
                while i < zeilen.count && zeilen[i].hasPrefix(">") {
                    var z = String(zeilen[i].dropFirst())
                    if z.hasPrefix(" ") { z.removeFirst() }
                    inhalt.append(z)
                    i += 1
                }
                raus.append(.zitat(inline(inhalt.joined(separator: "\n"))))
                continue
            }

            if let (geordnet, _) = listenzeile(zeile) {
                var punkte: [AttributedString] = []
                while i < zeilen.count, let (g, rest) = listenzeile(zeilen[i]), g == geordnet {
                    punkte.append(inline(rest))
                    i += 1
                }
                raus.append(.liste(geordnet: geordnet, punkte))
                continue
            }

            var absatz: [String] = []
            while i < zeilen.count {
                let z = zeilen[i]
                if z.trimmingCharacters(in: .whitespaces).isEmpty || istZaun(z) || ueberschrift(z) != nil || z.hasPrefix(">") || listenzeile(z) != nil || istTabellenkopf(zeilen, i) { break }
                absatz.append(z)
                i += 1
            }
            raus.append(.absatz(inline(absatz.joined(separator: "\n"))))
        }
        return raus
    }

    private static func istZaun(_ z: String) -> Bool {
        var s = Substring(z)
        var n = 0
        while s.first == " " && n < 3 { s = s.dropFirst(); n += 1 }
        return s.hasPrefix("```")
    }

    private static func istZaunEnde(_ z: String) -> Bool {
        var s = Substring(z)
        var n = 0
        while s.first == " " && n < 3 { s = s.dropFirst(); n += 1 }
        guard s.hasPrefix("```") else { return false }
        return s.dropFirst(3).allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func ueberschrift(_ z: String) -> (Int, String)? {
        var n = 0
        var s = Substring(z)
        while s.first == "#" && n < 6 { s = s.dropFirst(); n += 1 }
        guard n > 0, s.first == " " || s.first == "\t" else { return nil }
        return (n, s.trimmingCharacters(in: .whitespaces))
    }

    /// `- x`, `* x`, `+ x` oder `1. x`; gibt zurueck, ob geordnet, und den Text.
    private static func listenzeile(_ z: String) -> (Bool, String)? {
        let s = z.drop(while: { $0 == " " || $0 == "\t" })
        if let c = s.first, c == "-" || c == "*" || c == "+" {
            let rest = s.dropFirst()
            guard let r = rest.first, r == " " || r == "\t" else { return nil }
            return (false, String(rest.drop(while: { $0 == " " || $0 == "\t" })))
        }
        let ziffern = s.prefix(while: { $0.isNumber })
        guard !ziffern.isEmpty else { return nil }
        var rest = s.dropFirst(ziffern.count)
        guard rest.first == "." else { return nil }
        rest = rest.dropFirst()
        guard let r = rest.first, r == " " || r == "\t" else { return nil }
        return (true, String(rest.drop(while: { $0 == " " || $0 == "\t" })))
    }

    /// Ist diese Zeile die Trennzeile einer Tabelle (`---|:--:|--:`)?
    private static func istTrennzeile(_ zeile: String) -> Bool {
        var z = zeile.trimmingCharacters(in: .whitespaces)
        guard z.contains("|") else { return false }
        if z.hasPrefix("|") { z.removeFirst() }
        if z.hasSuffix("|") { z.removeLast() }
        let zellen = z.split(separator: "|", omittingEmptySubsequences: false)
        guard zellen.count >= 2 else { return false }
        return zellen.allSatisfy { zelle in
            var s = Substring(zelle.trimmingCharacters(in: .whitespaces))
            if s.first == ":" { s = s.dropFirst() }
            if s.last == ":" { s = s.dropLast() }
            return !s.isEmpty && s.allSatisfy { $0 == "-" }
        }
    }

    private static func istTabellenkopf(_ zeilen: [String], _ i: Int) -> Bool {
        zeilen[i].contains("|") && i + 1 < zeilen.count && istTrennzeile(zeilen[i + 1])
    }

    private static func tabellenZellen(_ zeile: String) -> [String] {
        var z = zeile.trimmingCharacters(in: .whitespaces)
        if z.hasPrefix("|") { z.removeFirst() }
        if z.hasSuffix("|") { z.removeLast() }
        return z.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// INLINE: Code zuerst herausgeloest (sein Inhalt bleibt vor Fett und
    /// Kursiv geschuetzt), dann fett vor kursiv, Links als Text. Erzeugt
    /// AttributedString mit `inlinePresentationIntent` -- nie Markup.
    public static func inline(_ text: String) -> AttributedString {
        var raus = AttributedString()
        var rest = Substring(text)
        while let anfang = rest.firstIndex(of: "`") {
            let danach = rest.index(after: anfang)
            // Ohne schliessenden Backtick (oder leer dazwischen) bleibt der
            // Rest Text -- ein einzelner Backtick ist keine Auszeichnung.
            guard let ende = rest[danach...].firstIndex(of: "`"), ende > danach else { break }
            raus += formatiert(String(rest[rest.startIndex..<anfang]))
            var code = AttributedString(String(rest[danach..<ende]))
            code.inlinePresentationIntent = .code
            raus += code
            rest = rest[rest.index(after: ende)...]
        }
        raus += formatiert(String(rest))
        return raus
    }

    /// Fett (`**x**`, `__x__`), kursiv (`*x*`, `_x_` an Wortgrenzen), Links als
    /// Text -- sequentiell, ohne Verschachtelung (wie markdown.ts `inline`).
    private static func formatiert(_ s: String) -> AttributedString {
        let ohneLinks = linksAlsText(s)
        let z = Array(ohneLinks)
        var raus = AttributedString()
        var puffer = ""
        var i = 0
        func spuelen() { if !puffer.isEmpty { raus += AttributedString(puffer); puffer = "" } }
        func istWort(_ c: Character?) -> Bool { c?.isLetter == true || c?.isNumber == true }
        while i < z.count {
            let c = z[i]
            if (c == "*" || c == "_"), i + 1 < z.count, z[i + 1] == c {
                // Fett: **…** oder __…__, ohne das Zeichen darin.
                if let ende = schliessend(z, ab: i + 2, marke: c, doppelt: true) {
                    spuelen()
                    var fett = AttributedString(String(z[(i + 2)..<ende]))
                    fett.inlinePresentationIntent = .stronglyEmphasized
                    raus += fett
                    i = ende + 2
                    continue
                }
            }
            if c == "*" || c == "_" {
                let wortDavor = c == "_" && i > 0 && istWort(z[i - 1])
                if !wortDavor, let ende = schliessend(z, ab: i + 1, marke: c, doppelt: false) {
                    let wortDanach = c == "_" && ende + 1 < z.count && istWort(z[ende + 1])
                    if !wortDanach {
                        spuelen()
                        var kursiv = AttributedString(String(z[(i + 1)..<ende]))
                        kursiv.inlinePresentationIntent = .emphasized
                        raus += kursiv
                        i = ende + 1
                        continue
                    }
                }
            }
            puffer.append(c)
            i += 1
        }
        spuelen()
        return raus
    }

    /// Die schliessende Marke ab `ab`, mit mindestens einem Zeichen dazwischen
    /// und ohne die Marke selbst darin (`[^*]+`).
    private static func schliessend(_ z: [Character], ab: Int, marke: Character, doppelt: Bool) -> Int? {
        var j = ab
        while j < z.count {
            if z[j] == marke {
                if doppelt {
                    if j + 1 < z.count, z[j + 1] == marke, j > ab { return j }
                    return nil
                }
                return j > ab ? j : nil
            }
            j += 1
        }
        return nil
    }

    /// `[Beschriftung](Ziel)` wird zur Beschriftung -- kein Anker, kein Ziel.
    /// Das Ziel darf eine Klammerebene enthalten (Befund B9).
    private static func linksAlsText(_ s: String) -> String {
        guard s.contains("](") else { return s }
        var raus = ""
        var rest = Substring(s)
        while let auf = rest.firstIndex(of: "[") {
            guard let zu = rest[auf...].firstIndex(of: "]"), rest.index(after: zu) < rest.endIndex, rest[rest.index(after: zu)] == "(" else {
                raus += rest[rest.startIndex...auf]
                rest = rest[rest.index(after: auf)...]
                continue
            }
            // Das Ziel: bis zur passenden schliessenden Klammer, eine Ebene tief.
            var tiefe = 0
            var j = rest.index(after: zu)
            var ende: Substring.Index? = nil
            while j < rest.endIndex {
                if rest[j] == "(" { tiefe += 1 } else if rest[j] == ")" { tiefe -= 1; if tiefe == 0 { ende = j; break } }
                if tiefe > 2 { break }
                j = rest.index(after: j)
            }
            guard let e = ende else {
                raus += rest[rest.startIndex...auf]
                rest = rest[rest.index(after: auf)...]
                continue
            }
            raus += rest[rest.startIndex..<auf]
            raus += rest[rest.index(after: auf)..<zu]
            rest = rest[rest.index(after: e)...]
        }
        raus += rest
        return raus
    }

    /// Der reine Text der Bloecke -- fuer Auskunft und Suche (kein Markup).
    public static func klartext(_ bloecke: [MarkdownBlock]) -> String {
        bloecke.map { b -> String in
            switch b {
            case .absatz(let a), .zitat(let a): return String(a.characters)
            case .ueberschrift(_, let a): return String(a.characters)
            case .code(let c): return c
            case .liste(_, let punkte): return punkte.map { String($0.characters) }.joined(separator: "\n")
            case .tabelle(let kopf, let zeilen): return ([kopf] + zeilen).map { $0.map { String($0.characters) }.joined(separator: " | ") }.joined(separator: "\n")
            }
        }.joined(separator: "\n")
    }
}

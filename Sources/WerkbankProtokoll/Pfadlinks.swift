// ANKLICKBARE PFADE, DIE REINE HAELFTE (Auftrag 3.6, 06.09.2026).
//
// Wortgetreue Uebertragung von `app/src/chat/pfadlinks.ts` (05.09.2026): aus
// einem ROHEN Text herauslesen, was wie ein Pfad aussieht -- absolut, mit
// Tilde, relativ, mit Zeilenangabe, in Backticks oder nackt im Satz. Ob es den
// Pfad wirklich gibt, weiss allein der Kern (`awb:chat-pfade`, main/chatpfade.ts,
// `fs.stat` gegen das Arbeitsverzeichnis der Sitzung und gegen `~`).
//
// EINE Erkennung fuer BEIDE Stellen, an denen ein Pfad anklickbar ist: die
// Nachricht im Gespraech und die Zeile im Terminal. Im Gespraech laeuft sie
// ueber den ganzen Text einer Nachricht, im Terminal ueber die eine Zeile unter
// dem Zeiger (`stelleBeiSpalte`) -- dieselben Muster, dieselben Ausnahmen.
//
// Die Versaetze sind ZEICHENVERSAETZE (`Character`), nicht UTF-16-Einheiten:
// eine Terminalzelle ist ein Zeichen, und die Ansicht schneidet ihre
// Textstuecke ebenfalls nach Zeichen.
import Foundation

/// Eine Fundstelle im Text: wo sie steht und was dort wortwoertlich steht.
public struct PfadStelle: Sendable, Equatable {
    public let von: Int
    public let bis: Int
    public let wortlaut: String

    public init(von: Int, bis: Int, wortlaut: String) {
        self.von = von
        self.bis = bis
        self.wortlaut = wortlaut
    }
}

/// Ein Kandidat, zerlegt: der Pfadteil und die freiwillige Zeilenangabe.
public struct PfadKandidat: Sendable, Equatable {
    public let wortlaut: String
    public let pfad: String
    public let zeile: Int
    public let spalte: Int
}

/// Ein Pfad, den der Kern wirklich gefunden hat (`awb:chat-pfade`).
public struct PfadTreffer: Sendable, Equatable {
    public let kandidat: String
    public let abs: String
    public let art: String
    public let zeile: Int
    public let spalte: Int

    public init(kandidat: String, abs: String, art: String, zeile: Int, spalte: Int) {
        self.kandidat = kandidat
        self.abs = abs
        self.art = art
        self.zeile = zeile
        self.spalte = spalte
    }

    public var ordner: Bool { art == "ordner" }
}

public enum Pfadlinks {
    /// Mehr Kandidaten je Nachricht werden nicht geprueft -- ein `stat` je
    /// Kandidat, und eine Nachricht mit tausend Pfaden ist ein Protokolldump,
    /// kein Gespraech (dieselbe Zahl wie in pfadlinks.ts).
    public static let hoechstzahlKandidaten = 200

    /// Ein Namensteil: Buchstaben, Ziffern und die Zeichen, die in Dateinamen
    /// ueblich sind -- auch ein fuehrender Punkt (`.env`). Kein Leerzeichen,
    /// keine Anfuehrungszeichen, keine Klammern.
    private static let teil = "[\\p{L}\\p{N}_.@+%=\\-]+"

    /// Das Muster, in dieser Reihenfolge:
    ///   1. absolut oder mit Tilde: `/a/b`, `~/a/b`;
    ///   2. relativ mit mindestens einem Schraegstrich: `shell/tests/x.sh`, `./x`.
    ///      Der letzte Namensteil steht als `(?:TEIL)?` da, NICHT als `TEIL?`:
    ///      letzteres haengt das Fragezeichen an das `+` von TEIL und macht ein
    ///      LAZY `+?` daraus, das genau ein Zeichen nimmt. Die TypeScript-Fassung
    ///      hatte genau das, und `./bin/bauen` wurde dort zu `./bin/b` -- also
    ///      nie anklickbar. Am 06.09.2026 beim Uebertragen gemessen und in
    ///      BEIDEN Fassungen behoben (`app/src/chat/pfadlinks.ts`);
    ///   3. ein nackter Dateiname mit Endung: `renderer.ts`, `README.md`.
    /// Dahinter freiwillig `:Zeile` oder `:Zeile:Spalte`.
    ///
    /// Der Blick zurueck haelt eine URL draussen: in `https://a.de/x` steht vor
    /// dem ersten `/` ein Doppelpunkt und vor `a.de/x` ein Schraegstrich. Ein
    /// npm-Name (`@scope/paket`) oder eine Fassungsnummer mit Buchstaben
    /// (`v2.0`) fallen dagegen herein -- gewollt billig, wie Punkt 3: der Kern
    /// sieht nach, und was es nicht gibt, bleibt Text.
    private static let muster: NSRegularExpression = {
        let p = "(?<![\\p{L}\\p{N}_/.~:@\\-])("
            + "(?:~?/(?:\(teil)/)*\(teil)/?)"
            + "|(?:\\.{1,2}/(?:\(teil)/)*(?:\(teil))?/?)"
            + "|(?:\(teil)(?:/\(teil))+/?)"
            + "|(?:[\\p{L}\\p{N}_.@+%=\\-]+\\.[A-Za-z0-9]{1,8})"
            + ")(?::([0-9]{1,7})(?::([0-9]{1,5}))?)?"
        // Das Muster ist fest verdrahtet und uebersetzt; scheitert es, faellt
        // die Erkennung aus, statt den Prozess zu beenden.
        return (try? NSRegularExpression(pattern: p)) ?? NSRegularExpression()
    }()

    /// Satzzeichen, die am Ende eines Kandidaten noch zum Satz gehoeren.
    private static let satzende: NSRegularExpression? =
        try? NSRegularExpression(pattern: "[.,;:!?'\"`)\\]}>]+$")

    /// Alle Fundstellen mit ihrer Lage im Text, in der Reihenfolge des Auftretens.
    public static func stellen(_ text: String) -> [PfadStelle] {
        guard !text.isEmpty, muster.pattern.count > 0 else { return [] }
        let ns = text as NSString
        var raus: [PfadStelle] = []
        for m in muster.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard m.range(at: 1).location != NSNotFound else { continue }
            var pfad = ns.substring(with: m.range(at: 1))
            let zeile = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
            let spalte = m.range(at: 3).location == NSNotFound ? "" : ns.substring(with: m.range(at: 3))
            // Ein Punkt am Satzende gehoert zum Satz: `renderer.ts.` -> `renderer.ts`.
            // Nur ohne Zeilenangabe -- bei `x.ts:12.` steht der Punkt hinter der Zahl.
            if zeile.isEmpty, let s = satzende {
                pfad = s.stringByReplacingMatches(in: pfad, range: NSRange(location: 0, length: (pfad as NSString).length), withTemplate: "")
            }
            if pfad.isEmpty || pfad == "/" || pfad == "~/" || pfad == "./" || pfad == "../" { continue }
            // Ein nackter Name mit Endung, der wie eine Versionsnummer aussieht
            // (`v2.0`, `1.5`), ist kein Pfad.
            if !pfad.contains("/"), let erstes = pfad.first, erstes.isNumber,
               pfad.allSatisfy({ $0.isNumber || $0 == "." }) { continue }
            var wortlaut = pfad
            if !zeile.isEmpty {
                wortlaut += ":\(zeile)"
                if !spalte.isEmpty { wortlaut += ":\(spalte)" }
            }
            // Von UTF-16 auf Zeichen: die Terminalzelle und die Textansicht
            // rechnen in Zeichen.
            let von = zeichenversatz(ns, m.range.location)
            raus.append(PfadStelle(von: von, bis: von + wortlaut.count, wortlaut: wortlaut))
        }
        return raus
    }

    /// Alle Stellen, die wie ein Pfad aussehen, jede genau einmal, hoechstens
    /// `hoechstzahlKandidaten`.
    public static func kandidaten(_ text: String) -> [String] {
        var raus: [String] = []
        var gesehen = Set<String>()
        for s in stellen(text) {
            if gesehen.contains(s.wortlaut) { continue }
            gesehen.insert(s.wortlaut)
            raus.append(s.wortlaut)
            if raus.count >= hoechstzahlKandidaten { break }
        }
        return raus
    }

    /// Zerlegt einen Wortlaut wie `a/b.ts:12:4` in Pfad, Zeile und Spalte.
    public static func zerlegen(_ wortlaut: String) -> PfadKandidat {
        let teile = wortlaut.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard teile.count > 1 else { return PfadKandidat(wortlaut: wortlaut, pfad: wortlaut, zeile: 0, spalte: 0) }
        // Von hinten: hoechstens zwei Zahlen; alles davor ist der Pfad (ein
        // Windows-Laufwerk kommt hier nicht vor, ein Doppelpunkt im Namen schon).
        var pfadteile = teile
        var zeile = 0
        var spalte = 0
        if let letzte = pfadteile.last, let n = Int(letzte), pfadteile.count > 1 {
            pfadteile.removeLast()
            if let vorletzte = pfadteile.last, let m = Int(vorletzte), pfadteile.count > 1 {
                pfadteile.removeLast()
                zeile = m
                spalte = n
            } else {
                zeile = n
            }
        }
        return PfadKandidat(wortlaut: wortlaut, pfad: pfadteile.joined(separator: ":"), zeile: zeile, spalte: spalte)
    }

    /// Die Fundstelle, die die Spalte `spalte` (nullbasiert) ueberdeckt -- der
    /// Klick im Terminal: eine Zeile, ein Zeiger, ein Pfad oder keiner.
    public static func stelleBeiSpalte(_ zeile: String, spalte: Int) -> PfadStelle? {
        stellen(zeile).first { spalte >= $0.von && spalte < $0.bis }
    }

    /// `/Users/jemand/…` und `/home/jemand/…` werden zu `~/…` (kurzpfad.ts).
    public static func kurzerPfad(_ pfad: String) -> String {
        for stamm in ["/Users/", "/home/"] {
            guard pfad.hasPrefix(stamm) else { continue }
            let rest = pfad.dropFirst(stamm.count)
            guard let schnitt = rest.firstIndex(of: "/") else { return rest.isEmpty ? pfad : "~" }
            return "~" + rest[schnitt...]
        }
        return pfad
    }

    private static func zeichenversatz(_ ns: NSString, _ utf16: Int) -> Int {
        guard utf16 > 0 else { return 0 }
        return ns.substring(to: utf16).count
    }
}

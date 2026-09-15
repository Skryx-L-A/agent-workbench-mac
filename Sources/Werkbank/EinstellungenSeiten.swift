// Die sieben Seiten der Einstellungen (Auftrag 2.6) -- als DATEN, nicht als
// Views: jede Seite ist eine Liste von Gruppen, jede Gruppe eine Liste von
// Feldern, jedes Einstellungsfeld traegt die drei Ebenen der Electron-Fassung (Name,
// Wirkungszeile, Infotext; app/src/einstellungen/einstellungen.ts, Vorgabe
// „fuer jeden") und sein Bedienelement als Art mit Wert und Handlung.
//
// WARUM DATEN. Drei Leser brauchen dieselbe Seite: das Fenster (SwiftUI,
// Einstellungen.swift), der Belegzeichner fuer kopflose Bilder (ohne
// AppKit-Steuerelemente) und der Steuerkanal (`awbmac-ctl einstellungen-klick
// <kennung>`), der ein Einstellungsfeld ueber seine Kennung bedient und liest, wie die
// Electron-Suite es ueber CSS-Auswahlen tut. Eine Fassung der Seite, drei
// Darstellungen -- statt dreimal derselben Logik.
//
// Inhalt und Wortlaut sind die der Electron-Fassung: dieselben Schluessel,
// dieselben Werte, derselbe Deckel je Modell (aus `awb:ein-daten`, nie aus dem
// Gedaechtnis), dieselbe Texttabelle (ueber `awb:ein-texte` vom Kern, keine
// zweite Kopie). Die Kennungen der Felder sind die `id`s der Electron-Fassung
// (`showStopped`, `muster-0`, `guard-secrets`, `wacheOrchAn` …), damit eine
// Suite beide Fassungen gleich liest.
//
// ZWEI SCHREIBWEGE, beide die des Kerns: `awb:ein-setzen` (wb-state settings
// set) fuer alles aus settings.json, `awb:ein-werkzeug` fuer Guard, Wache,
// Deckel und den Erlaubnismodus -- die tragen Grund und Menschen-Nachweis.
// `echt` sagt, ob ein Mensch im Fenster geklickt hat: wahr nur fuer eine
// Handlung aus der sichtbaren Oberflaeche, nie fuer den Steuerkanal und nie
// kopflos (dieselbe Regel wie in Freigaben.swift, 2.4).
import AppKit
import Foundation
import Observation
import WerkbankProtokoll

// MARK: Das Feldmodell

struct Option: Identifiable, Sendable {
    var id: String { wert }
    let wert: String
    let label: String
    var titel: String? = nil
    var gesperrt = false
    /// Markiert, nicht gesperrt: eine Stufe ueber dem Deckel (einstellungen.ts `ueberDeckel`).
    var ueberDeckel = false
}

/// Eine Zeile in einer Liste (Guards, Muster, Maschinen, Hooks, Ereignisse):
/// Schalter vorn, Titel, Grund, rechts Knoepfe oder Code.
@MainActor
struct Zeile: Identifiable {
    let id: String
    var schalter: Einstellungsfeld? = nil
    var titel = ""
    var grund = ""
    var code = ""
    var marke = ""
    var rechts: [Einstellungsfeld] = []
    var abgeschaltet = false
    /// Ein Klartext unter der Zeile (Maschinen: „wie viel peer traegt …").
    var unten = ""
    /// Die Antwortzeile rechts (Maschine pruefen), mit Farbe: "", "gut", "schlecht".
    var antwort = ""
    var antwortArt = ""
}

@MainActor
enum Zelle {
    case text(String, sekundaer: Bool = false, titel: String = "")
    /// Zwei Zeilen: Beschriftung, darunter der Rohwert.
    case zwei(String, String)
    case feld(Einstellungsfeld)
    case felder([Einstellungsfeld])
}

@MainActor
struct TabellenZeile: Identifiable {
    let id: String
    var zellen: [Zelle]
    var warnung = false
}

struct KontextDarstellung {
    let stufen: [KontextStufe]
    let wert: Int
    let empfehlung: Int
    let fuss: String
    let fussWarnt: Bool
}

@MainActor
indirect enum FeldArt {
    /// Haken -- Toggle. `setzen(an, echt)`.
    case schalter(an: Bool, setzen: (Bool, Bool) -> Void)
    /// Zahl mit Stepper. `setzen(n, echt)`; ausserhalb von min/max wird nichts geschrieben.
    case zahl(wert: Int, min: Int, max: Int, einheit: String, setzen: (Int, Bool) -> Void)
    /// Eine Zeile Text, geschrieben beim Verlassen des Felds.
    case text(wert: String, platzhalter: String, setzen: (String, Bool) -> Void)
    /// Ein lokales Eingabefeld (Anlegen-Zeilen, Schluessel, Sicherung) -- der Wert lebt in `eingaben[id]`.
    case eingabe(platzhalter: String, geheim: Bool, mehrzeilig: Bool)
    /// Eine Wahl: bis sechs Eintraege als Segmentleiste, darueber als Aufklappmenue (wie einstellungen.ts).
    case wahl(wert: String, optionen: [Option], setzen: (String, Bool) -> Void)
    case knopf(titel: String, warnend: Bool, hervorgehoben: Bool, klick: (Bool) -> Void)
    case klartext(String)
    /// Der eine Satz, der die Deckel-Gruppe traegt: fett + Rest.
    case leitsatz(fett: String, rest: String)
    case zeilen([Zeile], leer: String)
    /// Entfernbare Eintraege (Ausschlussordner, -muster).
    case chips(werte: [String], leer: String, weg: (String) -> Void)
    /// Die Modellwahl: Filterzeile, Suche, Liste mit dem Gewaehlten oben.
    case modelle(schluessel: String, gewaehlt: String, zeigen: [ModellSicht], filter: [Option], filterWahl: String, suche: String, keinTreffer: String, waehlen: (String) -> Void)
    case kontext(KontextDarstellung)
    case tabelle(kopf: [String], zeilen: [TabellenZeile], leer: String)
    case farben([(zustand: String, label: String, hex: String)], setzen: (String, String) -> Void)
    /// Mehrere Felder nebeneinander (eine Anlegen-Zeile: Eingaben und Knopf).
    case reihe([Einstellungsfeld])
    /// Mehrere Felder untereinander (Haken plus Klartext; Stufenwahl plus Deckelzeile).
    case stapel([Einstellungsfeld])
}

/// Ein Einstellungsfeld: Kennung, die drei Ebenen, das Bedienelement. Als Klasse, damit
/// der Index des Steuerkanals dieselbe Instanz haelt wie die Seite.
@MainActor
final class Einstellungsfeld: Identifiable {
    let id: String
    var name = ""
    var wirkung = ""
    var info = ""
    var etikett = ""
    var wartet = false
    /// Der Einstellungsschluessel, wenn das Einstellungsfeld ein Rueckstell-Zeichen traegt.
    var schluessel: String?
    var breit = false
    /// Eine Wahl immer als Aufklappmenue zeichnen, auch unter sieben Eintraegen (die Deckel-Tabelle: ein <select> je Zeile).
    var menue = false
    var art: FeldArt

    init(_ id: String, _ art: FeldArt) {
        self.id = id
        self.art = art
    }

    /// Alle Felder darunter (Zeilen-Schalter, Knoepfe rechts, Tabellenzellen, Reihen, Stapel).
    var kinder: [Einstellungsfeld] {
        switch art {
        case .zeilen(let z, _):
            return z.flatMap { ($0.schalter.map { [$0] } ?? []) + $0.rechts }
        case .tabelle(_, let zeilen, _):
            return zeilen.flatMap { $0.zellen.flatMap { z -> [Einstellungsfeld] in
                switch z { case .feld(let f): return [f]; case .felder(let fs): return fs; default: return [] }
            } }
        case .reihe(let f), .stapel(let f): return f
        default: return []
        }
    }

    /// Der Wert als Zeichenkette -- fuer `zustand` des Steuerkanals.
    var wert: String {
        switch art {
        case .schalter(let an, _): return an ? "true" : "false"
        case .zahl(let w, _, _, _, _): return String(w)
        case .text(let w, _, _): return w
        case .wahl(let w, _, _): return w
        case .modelle(_, let g, _, _, _, _, _, _): return g
        case .kontext(let k): return String(k.wert)
        default: return ""
        }
    }

    var gehakt: Bool { if case .schalter(let an, _) = art { return an } else { return false } }

    /// Der sichtbare Text des Feldes (wie `innerText`), mit Name und Wirkung.
    func text(_ zustand: EinstellungenZustand) -> String {
        var teile: [String] = []
        if !name.isEmpty { teile.append(name) }
        if !etikett.isEmpty { teile.append(etikett) }
        teile.append(contentsOf: steuerText(zustand))
        if !wirkung.isEmpty { teile.append(wirkung) }
        return teile.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Nur das Bedienelement, ohne die drei Ebenen.
    func steuerText(_ zustand: EinstellungenZustand) -> [String] {
        switch art {
        case .schalter(let an, _): return [an ? zustand.texte.t("wort.an") : zustand.texte.t("wort.aus")]
        case .zahl(let w, _, _, let e, _): return ["\(w) \(e)"]
        case .text(let w, let p, _): return [w.isEmpty ? p : w]
        case .eingabe(let p, let geheim, _):
            let w = zustand.eingaben[id] ?? ""
            return [geheim ? p : (w.isEmpty ? p : w)]
        case .wahl(_, let o, _): return o.map(\.label)
        case .knopf(let t, _, _, _): return [t]
        case .klartext(let t): return [t]
        case .leitsatz(let f, let r): return [f + r]
        case .zeilen(let z, let leer):
            if z.isEmpty { return [leer] }
            return z.flatMap { zeile -> [String] in
                var t: [String] = []
                if let s = zeile.schalter { t.append(contentsOf: s.steuerText(zustand)) }
                t.append(contentsOf: [zeile.titel, zeile.grund, zeile.code, zeile.marke, zeile.antwort, zeile.unten])
                t.append(contentsOf: zeile.rechts.flatMap { $0.steuerText(zustand) })
                return t
            }
        case .chips(let w, let leer, _): return w.isEmpty ? [leer] : w
        case .modelle(_, _, let zeigen, let filter, _, _, let keinTreffer, _):
            var t = filter.map(\.label)
            if zeigen.isEmpty { t.append(keinTreffer) }
            for m in zeigen { t.append(contentsOf: [m.label, m.id, m.harnessLabel]); if !m.startbar { t.append(zustand.texte.t("wort.nichtStartbar", ["maschine": zustand.daten?.machine ?? ""])) } }
            return t
        case .kontext(let k): return k.stufen.map { "\($0.label) \($0.tokens) \($0.hinweis)" } + [k.fuss]
        case .tabelle(let kopf, let zeilen, let leer):
            if zeilen.isEmpty { return kopf + [leer] }
            return kopf + zeilen.flatMap { $0.text(zustand) }
        case .farben(let f, _): return f.map { "\($0.label) \($0.hex)" }
        case .reihe(let f), .stapel(let f): return f.flatMap { $0.steuerText(zustand) }
        }
    }
}

extension TabellenZeile {
    func text(_ zustand: EinstellungenZustand) -> [String] {
        zellen.flatMap { z -> [String] in
            switch z {
            case .text(let t, _, _): return [t]
            case .zwei(let a, let b): return [a, b]
            case .feld(let f): return f.steuerText(zustand)
            case .felder(let fs): return fs.flatMap { $0.steuerText(zustand) }
            }
        }
    }
}

@MainActor
struct Gruppe: Identifiable {
    let id: String
    var titel: String
    var vorsicht = false
    var felder: [Einstellungsfeld] = []
}

@MainActor
struct Seite: Identifiable {
    let id: String
    let titel: String
    let wofuer: String
    let unterzeile: String
    let symbol: String
    var gruppen: [Gruppe] = []
}

/// Die Rueckfrage der dritten Klasse (einstellungen.ts `frage()`): der Satz
/// nennt die Folge, der Knopf das Tun; mit Grund, wo das Werkzeug einen verlangt.
struct Rueckfrage {
    let text: String
    let tun: String
    let mitGrund: Bool
    var grund = ""
    var hinweis = ""
    let ja: @MainActor (String, Bool) -> Void
}

// MARK: Der Zustand

/// Alles, was das Fenster haelt: die Daten des Kerns, die Texte, die gebauten
/// Seiten, die Fusszeile, die offene Rueckfrage, das offene Infozeichen, die
/// lokalen Eingaben. Neu gebaut wird nur bei einem neuen Datenstand (der Kern
/// schickt `awb:ein-daten-neu` bei jedem Schreibvorgang, auch ohne Aenderung
/// -- Befund 9 der Electron-Fassung, 15.08.: ein offenes Aufklappmenue
/// schnappte zu). `zeichnungen` zaehlt die echten Neubauten.
@MainActor
@Observable
final class EinstellungenZustand {
    let kern: KernVerbindung
    /// Kopflos: keine Sheets, keine Zwischenablage, `echt` nie wahr.
    let kopflos: Bool

    private(set) var daten: EinstellungenDaten?
    private(set) var texte = Texte()
    var seite = "sitzung"
    private(set) var seiten: [Seite] = []
    private(set) var zeichnungen = 0
    /// Die Fusszeile: was zuletzt geschrieben wurde, wortwoertlich, mit Art ("", "gut", "fehler").
    private(set) var status = ""
    private(set) var statusArt = ""
    /// Wie viele Schreibvorgaenge gerade beim Kern liegen -- der Steuerkanal
    /// wartet darauf, damit eine Suite die Fusszeile NACH der Antwort liest.
    private(set) var offeneSchreibvorgaenge = 0
    /// Welches Infozeichen offen ist (Kennung; leer = keins).
    var offenesInfo = ""
    var rueckfrage: Rueckfrage?
    /// Der Weg zum gefuehrten ersten Start des MANTELS (Auftrag 3.8). Bis dahin
    /// ging der Knopf auf der Seite „Programm“ ueber `erststart-zeigen` an den
    /// Kern und damit in dessen Electron-Fenster -- im Mantelbetrieb gibt es das
    /// nicht mehr (4.1). `echt` entscheidet wie ueberall: ein Skript-Klick baut
    /// nur, ein Mensch bekommt das Sheet.
    var erststartZeigen: ((_ echt: Bool) -> Void)?
    /// Lokale Eingaben, die nicht sofort geschrieben werden (Anlegen-Zeilen, Schluessel, Sicherung, Suche).
    var eingaben: [String: String] = [:]
    private(set) var schluesselStand: [String: Bool] = [:]
    private(set) var kontextStand: [String: KontextAntwort] = [:]
    private(set) var filterStand: [String: String] = [:]
    private(set) var maschinenAntwort: [String: (ok: Bool, text: String)] = [:]
    /// Der Testknopf der Meldungen: nil = nichts, .null = laeuft, sonst die Antwort.
    private(set) var meldungTest: JSONWert?
    /// Das Fenster stellt die Rueckfrage sichtbar (NSAlert-Sheet); kopflos bleibt sie Zustand.
    @ObservationIgnored var aufRueckfrage: ((Rueckfrage) -> Void)?
    /// Die Seiten sind neu gebaut -- das Fenster misst daraufhin die
    /// Seitenleiste nach (Einstellungen.swift, `leisteAnpassen`). Erst hier
    /// stehen die Seitennamen fest: sie kommen mit den Texten vom Kern, und in
    /// welcher Sprache, weiss beim Bauen des Fensters noch niemand.
    @ObservationIgnored var aufSeitenNeu: (() -> Void)?
    /// WAS DIE TABELLEN DER OFFENEN SEITE BEKOMMEN HABEN (08.09.2026): je
    /// Tabelle ihre Ueberschriften und die Breite, die ihr das Fenster
    /// zugeteilt hat. Gemessen beim Auslegen (`TabellenAnsicht`), deshalb
    /// ausserhalb der Beobachtung -- ein Schreiben hier darf keinen Neubau
    /// ausloesen.
    @ObservationIgnored var tabellenmass: [String: (kopf: [String], breite: CGFloat)] = [:]
    /// WAS DIE FLIESSTEXTE DER OFFENEN SEITE BEKOMMEN HABEN (08.09.2026): je
    /// Text seine Schrift und die Groesse, in der er wirklich steht. Aus
    /// derselben Not wie `tabellenmass`: ob ein Text gekuerzt ist, steht nicht
    /// im Text -- gekuerzt wird beim Zeichnen.
    @ObservationIgnored var textmass: [String: (text: String, stil: NSFont.TextStyle, breite: CGFloat, hoehe: CGFloat)] = [:]
    @ObservationIgnored private var kontextLaeuft: Set<String> = []
    @ObservationIgnored private var index: [String: Einstellungsfeld] = [:]
    @ObservationIgnored private var zeilenIndex: [String: TabellenZeile] = [:]
    @ObservationIgnored private var letzteZeile: Data?

    init(kern: KernVerbindung, kopflos: Bool) {
        self.kern = kern
        self.kopflos = kopflos
    }

    // MARK: Laden

    /// Daten, Texte und Schluesselstand vom Kern holen -- beim Oeffnen.
    func laden() async {
        let t = await kern.invoke("awb:ein-texte")
        if let w = t.wertJSON { texte = Texte(json: JSONWert.lesen(w)) }
        let d = await kern.invoke("awb:ein-daten")
        if let w = d.wertJSON { datenAngekommen(w) }
        await schluesselStatusLaden()
    }

    /// Ein neuer Stand vom Kern (`awb:ein-daten-neu` oder die Antwort auf `awb:ein-daten`).
    /// Derselbe Stand baut nicht neu.
    func datenAngekommen(_ zeile: Data) {
        let neu = EinstellungenDaten.lesen(zeile)
        if let alt = daten, alt == neu { return }
        let spracheAlt = daten?.sprache
        daten = neu
        // Die Kontextstufen messen freien Speicher -- ein alter Wert unter einer frischen Seite waere eine Behauptung ueber jetzt.
        kontextStand = [:]
        if spracheAlt != nil, spracheAlt != neu.sprache {
            Task { @MainActor in
                let t = await kern.invoke("awb:ein-texte")
                if let w = t.wertJSON { texte = Texte(json: JSONWert.lesen(w)); neuBauen() }
            }
        }
        neuBauen()
    }

    func schluesselStatusLaden() async {
        let a = await kern.invoke("awb:ein-schluessel-status")
        var neu: [String: Bool] = [:]
        if let w = a.wertJSON { for (k, v) in JSONWert.lesen(w).objekt ?? [:] { neu[k] = v.bool ?? false } }
        if neu != schluesselStand { schluesselStand = neu; neuBauen() }
    }

    func kontextHolen(_ modellId: String) {
        guard !modellId.isEmpty, !kontextLaeuft.contains(modellId), kontextStand[modellId] == nil else { return }
        kontextLaeuft.insert(modellId)
        Task { @MainActor in
            let a = await kern.invoke("awb:kontext-stufen", [modellId])
            kontextStand[modellId] = KontextAntwort.lesen(a.wertJSON)
            kontextLaeuft.remove(modellId)
            neuBauen()
        }
    }

    // MARK: Schreiben -- die Wege des Kerns

    func melde(_ text: String, _ art: String = "") {
        status = text
        statusArt = art
    }

    /// `wb-state settings set` ueber den Kern. Der Kern schickt danach `awb:ein-daten-neu`.
    func setze(_ schluessel: String, _ wert: JSONWert) async {
        melde(texte.t("satz.schreibe", ["schluessel": schluessel]))
        offeneSchreibvorgaenge += 1
        let a = await kern.invoke("awb:ein-setzen", [schluessel, wert.fuerJSON])
        offeneSchreibvorgaenge -= 1
        antwortMelden(a)
    }

    /// Warten, bis kein Schreibvorgang mehr offen ist (hoechstens `sekunden`) -- fuer den Steuerkanal.
    func schreibvorgaengeAbwarten(sekunden: Double = 4) async {
        let bis = Date().addingTimeInterval(sekunden)
        while offeneSchreibvorgaenge > 0, Date() < bis {
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    /// Guard, Wache, Deckel, Erlaubnismodus: ein eigener Weg mit Menschen-Nachweis.
    func werkzeug(_ nachricht: [String: Any], echt: Bool) async {
        melde("\(nachricht["command"] as? String ?? "") …")
        offeneSchreibvorgaenge += 1
        let a = await kern.invoke("awb:ein-werkzeug", [nachricht, echt && !kopflos])
        offeneSchreibvorgaenge -= 1
        antwortMelden(a)
    }

    func setzeUi(_ schluessel: String, _ wert: Any) async {
        offeneSchreibvorgaenge += 1
        _ = await kern.invoke("awb:ein-ui", [schluessel, wert])
        offeneSchreibvorgaenge -= 1
        let w = (try? JSONSerialization.data(withJSONObject: wert, options: [.fragmentsAllowed])).map { String(decoding: $0, as: UTF8.self) } ?? "\(wert)"
        melde(texte.t("satz.oberflaeche", ["schluessel": schluessel, "wert": w]), "gut")
    }

    private func antwortMelden(_ a: KernAntwort) {
        let j = a.wertJSON.map(JSONWert.lesen) ?? .null
        let ok = j["ok"].bool ?? false
        let aufruf = j["aufruf"].text ?? ""
        let ausgabe = j["ausgabe"].text ?? a.fehler ?? ""
        melde(ok ? "\(aufruf) — \(ausgabe)" : texte.t("satz.fehler", ["aufruf": aufruf, "ausgabe": ausgabe]), ok ? "gut" : "fehler")
    }

    /// Die Rueckfrage stellen. Sichtbar als Sheet (Einstellungen.swift), kopflos als Zustand,
    /// den `awbmac-ctl einstellungen-klick rueckfrageJa|rueckfrageNein` beantwortet.
    func frage(_ text: String, tun: String, mitGrund: Bool = false, ja: @escaping @MainActor (String, Bool) -> Void) {
        let r = Rueckfrage(text: text, tun: tun, mitGrund: mitGrund, ja: ja)
        rueckfrage = r
        if !kopflos { aufRueckfrage?(r) }
    }

    /// Ja oder Nein auf die offene Rueckfrage. `echt`: ein Mensch hat im Sheet geklickt.
    @discardableResult
    func rueckfrageBeantworten(ja: Bool, grund: String? = nil, echt: Bool) -> Bool {
        guard var r = rueckfrage else { return false }
        if let g = grund { r.grund = g }
        guard ja else { rueckfrage = nil; return true }
        let g = r.grund.trimmingCharacters(in: .whitespaces)
        if r.mitGrund, g.isEmpty {
            // Leer heisst: nicht tun -- das Werkzeug lehnte es ohnehin ab; hier sieht man es vorher.
            r.hinweis = texte.t("satz.ohneGrundNichts")
            rueckfrage = r
            return true
        }
        rueckfrage = nil
        r.ja(g, echt && !kopflos)
        return true
    }

    func schluesselSpeichern(_ anbieter: AnbieterSicht) {
        let kennung = "schluessel-\(anbieter.id)"
        let wert = eingaben[kennung] ?? ""
        // Geloescht wird SOFORT, gleich ob der Aufruf glueckt: der Klartext steht nie laenger als bis zum Klick.
        eingaben[kennung] = ""
        guard !wert.trimmingCharacters(in: .whitespaces).isEmpty else { melde(texte.t("satz.schluesselLeer"), "fehler"); return }
        melde(texte.t("satz.schreibe", ["schluessel": anbieter.id]))
        Task { @MainActor in
            let a = await kern.invoke("awb:ein-schluessel-setzen", [anbieter.id, wert])
            let ok = a.wertJSON.map { JSONWert.lesen($0)["ok"].bool ?? false } ?? false
            melde(ok ? texte.t("satz.schluesselGespeichert", ["anbieter": anbieter.label]) : texte.t("satz.schluesselFehler"), ok ? "gut" : "fehler")
            await schluesselStatusLaden()
        }
    }

    func maschinePruefen(_ name: String) {
        maschinenAntwort[name] = (false, texte.t("wort.frage"))
        neuBauen()
        Task { @MainActor in
            let a = await kern.invoke("awb:ein-maschine-pruefen", [name])
            let j = a.wertJSON.map(JSONWert.lesen) ?? .null
            let ok = j["ok"].bool ?? false
            let ausgabe = j["ausgabe"].text ?? a.fehler ?? ""
            maschinenAntwort[name] = (ok, ok ? texte.t("wort.erreichbar") : texte.t("wort.nichtErreichbar", ["grund": ausgabe]))
            melde("ssh \(name): \(ausgabe)", ok ? "gut" : "fehler")
            neuBauen()
        }
    }

    /// ECHTER Versand -- eine wirkliche Meldung ueber die gewaehlten Wege.
    func meldungTesten() {
        meldungTest = .null
        neuBauen()
        Task { @MainActor in
            let a = await kern.invoke("awb:ein-meldung-testen")
            meldungTest = a.wertJSON.map(JSONWert.lesen) ?? .objekt(["an": .bool(false)])
            neuBauen()
        }
    }

    // MARK: Der Steuerkanal: lesen und bedienen ueber Kennungen

    var seitenNamen: [String] { seiten.map(\.id) }
    var aktuelleSeite: Seite? { seiten.first { $0.id == seite } }

    func feld(_ kennung: String) -> Einstellungsfeld? { index[kennung] }

    /// Der Text der offenen Seite, wie `innerText` des Stapels.
    func seitenText() -> String {
        guard let s = aktuelleSeite else { return "" }
        var t = [s.titel, s.unterzeile]
        for g in s.gruppen { t.append(g.titel); for f in g.felder { t.append(f.text(self)) } }
        return t.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Jedes Einstellungsfeld mit seinen drei Ebenen -- ueber ALLE Seiten (die Zusage „fuer jeden").
    func felderAuskunft() -> [[String: Any]] {
        seiten.flatMap { $0.gruppen.flatMap { $0.felder } }
            .filter { !$0.name.isEmpty }
            .map { ["id": $0.id, "name": $0.name, "wirkung": $0.wirkung, "info": $0.info, "wert": $0.wert, "seite": seiteVon($0)] }
    }

    /// Jede Tabelle der offenen Seite: was ihre Ueberschriften brauchen und was
    /// ihre Spalten bekommen haben. `eng` nennt die Ueberschriften, deren Spalte
    /// schmaler ist als ihr Text -- eine davon ist der Befund „Auf dieser Ma…"
    /// vom 08.09.2026, und leer ist die Liste die Zusage dagegen.
    func tabellenAuskunft() -> [[String: Any]] {
        tabellenmass.keys.sorted().compactMap { id in
            guard let m = tabellenmass[id], !m.kopf.isEmpty, m.breite > 0 else { return nil }
            let noetig = TabellenAnsicht.noetig(m.kopf)
            let breiten = Spaltenraster.breiten(noetig: noetig, gesamt: m.breite)
            let eng = zip(m.kopf, zip(noetig, breiten)).filter { $0.1.0 > $0.1.1 + 0.5 }.map { $0.0 }
            return ["id": id, "kopf": m.kopf, "breite": Int(m.breite.rounded()),
                    "noetig": noetig.map { Int($0.rounded()) }, "spalten": breiten.map { Int($0.rounded()) },
                    "eng": eng]
        }
    }

    /// Jeder gemessene Fliesstext der offenen Seite. `gekuerzt` ist wahr, wenn
    /// er mehr Breite braucht, als er bekommen hat, und trotzdem in einer Zeile
    /// steht -- dann endet er im Fenster mit drei Punkten. Genau das war der
    /// Befund vom 08.09.2026 („welche Denkstufen e…"), und leer ist die Liste
    /// die Zusage dagegen.
    func textAuskunft() -> [[String: Any]] {
        textmass.keys.sorted().compactMap { id in
            guard let m = textmass[id], m.breite > 0, !m.text.isEmpty else { return nil }
            let f = NSFont.preferredFont(forTextStyle: m.stil)
            let einzeilig = ceil(NSAttributedString(string: m.text, attributes: [.font: f]).size().width)
            let zeile = ceil(NSAttributedString(string: "Hg", attributes: [.font: f]).size().height)
            return ["id": id, "text": m.text, "breite": Int(m.breite.rounded()), "hoehe": Int(m.hoehe.rounded()),
                    "einzeilig": Int(einzeilig), "zeile": Int(zeile),
                    "gekuerzt": einzeilig > m.breite + 0.5 && m.hoehe < zeile * 1.5]
        }
    }

    private func seiteVon(_ f: Einstellungsfeld) -> String {
        seiten.first { $0.gruppen.contains { $0.felder.contains { $0 === f } } }?.id ?? ""
    }

    func infoAuskunft() -> [String: Any] {
        guard !offenesInfo.isEmpty, let f = index[offenesInfo] else { return ["feld": "", "text": "", "sichtbar": false] }
        return ["feld": f.id, "text": f.info, "sichtbar": true]
    }

    /// Ein Bedienelement lesen, ohne es anzufassen (wie `__awbEin.zustand`).
    func zustandAuskunft(_ kennung: String) -> [String: Any] {
        if let f = index[kennung] {
            var a: [String: Any] = ["da": true, "gehakt": f.gehakt, "wert": f.wert, "text": f.text(self), "zeichnungen": zeichnungen]
            if case .wahl(_, let optionen, _) = f.art { a["optionen"] = optionen.map { ["wert": $0.wert, "label": $0.label] } }
            return a
        }
        if let z = zeilenIndex[kennung] {
            return ["da": true, "gehakt": false, "wert": "", "text": z.text(self).filter { !$0.isEmpty }.joined(separator: " "), "zeichnungen": zeichnungen]
        }
        return ["da": false, "gehakt": false, "wert": "", "text": "", "zeichnungen": zeichnungen]
    }

    /// Ein Bedienelement ausloesen -- ohne Menschen-Merkmal (`echt` = false).
    /// Kennungen: `<feld>` (Haken umlegen, Knopf druecken), `<feld>:<wert>` (eine
    /// Wahl treffen), `zurueck:<schluessel>`, `info:<feld>`, `filter:<schluessel>:<harness>`,
    /// `modell:<schluessel>:<id>`, `kontext:<tokens>`, `weg:<feld>:<eintrag>`,
    /// `rueckfrageJa`, `rueckfrageNein`, `seite:<name>`.
    func klick(_ kennung: String) -> Bool {
        switch kennung {
        case "rueckfrageJa": return rueckfrageBeantworten(ja: true, echt: false)
        case "rueckfrageNein": return rueckfrageBeantworten(ja: false, echt: false)
        default: break
        }
        if kennung.hasPrefix("seite:") { return seiteWaehlen(String(kennung.dropFirst(6))) }
        if kennung.hasPrefix("info:") {
            let id = String(kennung.dropFirst(5))
            guard index[id] != nil else { return false }
            offenesInfo = offenesInfo == id ? "" : id
            return true
        }
        if kennung.hasPrefix("zurueck:") {
            let s = String(kennung.dropFirst(8))
            guard let d = daten, let v = d.vorgaben[s], !d.stehtAufVorgabe(s) else { return false }
            Task { await setze(s, v) }
            return true
        }
        if kennung.hasPrefix("filter:") {
            let teile = kennung.dropFirst(7).split(separator: ":", maxSplits: 1).map(String.init)
            guard teile.count == 2 else { return false }
            filterStand[teile[0]] = teile[1]
            neuBauen()
            return true
        }
        if kennung.hasPrefix("modell:") {
            let teile = kennung.dropFirst(7).split(separator: ":", maxSplits: 1).map(String.init)
            guard teile.count == 2, let f = index[teile[0]], case .modelle(_, _, _, _, _, _, _, let waehlen) = f.art else { return false }
            waehlen(teile[1])
            return true
        }
        if kennung.hasPrefix("kontext:") {
            guard let n = Int(kennung.dropFirst(8)), let f = index["orchestratorKontext"], case .kontext(let k) = f.art,
                  k.stufen.contains(where: { $0.tokens == n }) else { return false }
            Task { await setze("orchestratorKontext", .zahl(Double(n))) }
            return true
        }
        if kennung.hasPrefix("weg:") {
            let teile = kennung.dropFirst(4).split(separator: ":", maxSplits: 1).map(String.init)
            guard teile.count == 2, let f = index[teile[0]], case .chips(let werte, _, let weg) = f.art, werte.contains(teile[1]) else { return false }
            weg(teile[1])
            return true
        }
        if let f = index[kennung] {
            switch f.art {
            case .schalter(let an, let setzen): setzen(!an, false); return true
            case .knopf(_, _, _, let klick): klick(false); return true
            default: return false
            }
        }
        // `<feld>:<wert>` -- eine Wahl treffen, wie ein Klick auf das Segment.
        if let doppel = kennung.lastIndex(of: ":") {
            let id = String(kennung[..<doppel]), wert = String(kennung[kennung.index(after: doppel)...])
            if let f = index[id], case .wahl(_, let optionen, let setzen) = f.art, let o = optionen.first(where: { $0.wert == wert }), !o.gesperrt {
                setzen(wert, false)
                return true
            }
        }
        return false
    }

    /// In ein Einstellungsfeld schreiben, wie ein Mensch tippt und das Einstellungsfeld verlaesst.
    func eingabe(_ kennung: String, _ wert: String) -> Bool {
        if kennung == "rueckfrageGrund" {
            guard var r = rueckfrage else { return false }
            r.grund = wert; r.hinweis = ""; rueckfrage = r
            return true
        }
        if kennung.hasPrefix("suche:") {
            eingaben[kennung] = wert
            neuBauen()
            return true
        }
        guard let f = index[kennung] else { return false }
        switch f.art {
        case .text(_, _, let setzen): setzen(wert.trimmingCharacters(in: .whitespaces), false); return true
        case .zahl(_, let min, let max, _, let setzen):
            guard let n = Int(wert.trimmingCharacters(in: .whitespaces)) else { return false }
            guard n >= min, n <= max else { melde(texte.t("satz.fehler", ["aufruf": kennung, "ausgabe": "\(n) ∉ [\(min), \(max)]"]), "fehler"); return true }
            setzen(n, false); return true
        case .wahl(_, let optionen, let setzen):
            guard optionen.contains(where: { $0.wert == wert && !$0.gesperrt }) else { return false }
            setzen(wert, false); return true
        case .eingabe: eingaben[kennung] = wert; return true
        case .farben(let f, let setzen):
            guard let z = f.first(where: { "farbe-\($0.zustand)" == kennung }) else { return false }
            setzen(z.zustand, wert); return true
        default: return false
        }
    }

    @discardableResult
    func seiteWaehlen(_ name: String) -> Bool {
        guard seiten.contains(where: { $0.id == name }) else { return false }
        // Die Masse gehoeren zur alten Seite -- und NUR zu ihr: dieselbe Seite
        // noch einmal zu waehlen darf sie nicht wegwerfen, sonst raeumt jede
        // Abfrage die Messung weg, auf die sie gerade wartet (gemessen 08.09.
        // unter Last: `tabellen` blieb leer, solange danach gefragt wurde).
        if seite != name { tabellenmass = [:]; textmass = [:] }
        seite = name
        offenesInfo = ""
        return true
    }

    // MARK: Der Neubau

    func neuBauen() {
        guard let d = daten, !texte.leer else { return }
        zeichnungen += 1
        offenesInfo = ""
        let b = SeitenBauer(zustand: self, d: d, t: texte)
        seiten = b.alle()
        // Die alten Masse gehoeren zu den alten Seiten -- eine andere Sprache
        // bringt andere Ueberschriften und andere Saetze mit.
        tabellenmass = [:]
        textmass = [:]
        index = [:]
        zeilenIndex = [:]
        for s in seiten { for g in s.gruppen { for f in g.felder { eintragen(f) } } }
        aufSeitenNeu?()
    }

    private func eintragen(_ f: Einstellungsfeld) {
        index[f.id] = f
        if case .tabelle(_, let zeilen, _) = f.art { for z in zeilen { zeilenIndex[z.id] = z } }
        for k in f.kinder { eintragen(k) }
    }
}

// MARK: Die Seitenbauer -- Inhalt und Wortlaut der Electron-Fassung

@MainActor
struct SeitenBauer {
    unowned let zustand: EinstellungenZustand
    let d: EinstellungenDaten
    let t: Texte

    func alle() -> [Seite] {
        [sitzung(), erlaubnisse(), harnesses(), maschinen(), aufsicht(), aussehen(), programm()]
    }

    // --- Bausteine -------------------------------------------------------

    private func seite(_ name: String, symbol: String, _ gruppen: [Gruppe]) -> Seite {
        Seite(id: name, titel: t.t("seite.\(name).titel"), wofuer: t.t("seite.\(name).wofuer"),
              unterzeile: t.t("seite.\(name).unterzeile"), symbol: symbol, gruppen: gruppen)
    }

    /// Ein Einstellungsfeld mit den drei Ebenen aus der Texttabelle (`feld.<kennung>.*`).
    private func feld(_ kennung: String, _ art: FeldArt, schluessel: String? = nil, wartet: Bool = false,
                      breit: Bool = false, werte: [String: String] = [:], id: String? = nil) -> Einstellungsfeld {
        let f = Einstellungsfeld(id ?? kennung, art)
        f.name = t.t("feld.\(kennung).name", werte)
        f.wirkung = t.t("feld.\(kennung).wirkung", werte)
        f.info = t.t("feld.\(kennung).info", werte)
        f.etikett = t.tOpt("feld.\(kennung).etikett", werte)
        f.wartet = wartet
        f.schluessel = schluessel
        f.breit = breit
        return f
    }

    private func schalter(_ id: String, _ an: Bool, _ setzen: @escaping @MainActor (Bool, Bool) -> Void) -> Einstellungsfeld {
        Einstellungsfeld(id, .schalter(an: an, setzen: setzen))
    }

    private func knopf(_ id: String, _ titel: String, warnend: Bool = false, hervorgehoben: Bool = false, _ klick: @escaping @MainActor (Bool) -> Void) -> Einstellungsfeld {
        Einstellungsfeld(id, .knopf(titel: titel, warnend: warnend, hervorgehoben: hervorgehoben, klick: klick))
    }

    private func klartext(_ id: String, _ text: String) -> Einstellungsfeld { Einstellungsfeld(id, .klartext(text)) }

    private func eingabe(_ id: String, _ platzhalter: String, geheim: Bool = false) -> Einstellungsfeld {
        Einstellungsfeld(id, .eingabe(platzhalter: platzhalter, geheim: geheim, mehrzeilig: false))
    }

    private func setze(_ schluessel: String, _ wert: JSONWert) {
        Task { await zustand.setze(schluessel, wert) }
    }

    private func werkzeug(_ nachricht: [String: Any], _ echt: Bool) {
        Task { await zustand.werkzeug(nachricht, echt: echt) }
    }

    private func setzeUi(_ schluessel: String, _ wert: Any) {
        Task { await zustand.setzeUi(schluessel, wert) }
    }

    private func wahl(_ id: String, _ wert: String, _ optionen: [Option], _ setzen: @escaping @MainActor (String, Bool) -> Void) -> Einstellungsfeld {
        Einstellungsfeld(id, .wahl(wert: wert, optionen: optionen, setzen: setzen))
    }

    /// Der Wert einer Einstellung kurz, wie `kurzWert` in einstellungen.ts.
    func kurzWert(_ v: JSONWert?) -> String {
        guard let v = v else { return "" }
        switch v {
        case .liste(let l):
            if l.isEmpty { return t.t("wort.leereListe") }
            return l.count == 1 ? t.t("wort.einEintrag") : t.t("wort.mehrereEintraege", ["anzahl": String(l.count)])
        case .bool(let b): return b ? t.t("wort.an") : t.t("wort.aus")
        case .objekt(let o):
            if o.isEmpty { return t.t("wort.nichtsGesetzt") }
            let eintraege = o.sorted { $0.key < $1.key }
            let stueck = eintraege.prefix(3).map { (k, w) -> String in
                guard let inner = w.objekt else { return "\(k)=\(w.zeichenkette)" }
                let teile = inner.sorted { $0.key < $1.key }.filter { !["grund", "seit", "gesetzt"].contains($0.key) }.prefix(3).map { "\($0.key)=\($0.value.zeichenkette)" }
                return teile.isEmpty ? k : "\(k) (\(teile.joined(separator: ", ")))"
            }
            return eintraege.count > 3 ? "\(stueck.joined(separator: " · ")) … (\(eintraege.count))" : stueck.joined(separator: " · ")
        default: return v.zeichenkette
        }
    }

    /// Eine Wertspalte der Abweichungstabelle: Beschriftung vorn, Rohwert dahinter.
    private func wertZelle(_ schluessel: String, _ v: JSONWert?) -> Zelle {
        let roh = kurzWert(v)
        let label = v?.text.map { t.tOpt("wort.\(schluessel).\($0)") } ?? ""
        if label.isEmpty || label == roh { return .text(roh) }
        return .zwei(label, roh)
    }

    // --- Seite 1: Sitzung --------------------------------------------------

    func sitzung() -> Seite {
        let harness = d.text("orchestratorHarness", "claude")
        var g1 = Gruppe(id: "sitzung.start", titel: t.t("gruppe.sitzung.start"))
        g1.felder.append(feld("orchestratorHarness", .wahl(
            wert: harness,
            optionen: d.harnesses.map { h in
                Option(wert: h.id, label: "\(h.label) \(h.modelle)\(h.binaer ? "" : " · \(t.t("wort.fehltHier"))")",
                       titel: h.binaer ? nil : t.t("wort.nichtStartbar", ["maschine": d.machine]))
            },
            setzen: { w, _ in
                let modell = d.harnesses.first(where: { $0.id == w })?.orchestratorDefaultModel ?? ""
                Task {
                    await self.zustand.setze("orchestratorHarness", .text(w))
                    if !modell.isEmpty {
                        await self.zustand.setze("orchestratorModel", .text(modell))
                    }
                }
            }),
            schluessel: "orchestratorHarness", wartet: true, werte: ["maschine": d.machine]))

        let eigene = d.orchestratorModelle.filter { $0.harness == harness }
        let gewaehlt = d.text("orchestratorModel")
        if eigene.isEmpty {
            let f = Einstellungsfeld("orchestratorModel", .klartext(t.t("satz.keinModellFuerProgramm", ["harness": harness])))
            f.name = t.t("feld.orchestratorModel.leerName"); f.wirkung = t.t("feld.orchestratorModel.leerWirkung")
            f.info = t.t("feld.orchestratorModel.leerInfo"); f.schluessel = "orchestratorModel"; f.breit = true
            g1.felder.append(f)
        } else {
            g1.felder.append(modellwahl("orchestratorModel", eigene, gewaehlt, werte: ["anzahl": String(eigene.count)]) { id in
                self.setze("orchestratorModel", .text(id))
            })
        }
        let orchModell = d.orchestratorModelle.first { $0.id == gewaehlt }
        g1.felder.append(stufenwahl("orchestratorEffort", orchModell, d.deckel[gewaehlt],
                                    d.deckel[gewaehlt]?.efforts ?? d.harnessStufen[orchModell?.harness ?? ""] ?? [],
                                    d.text("orchestratorEffort", "xhigh")))
        if let k = kontextwahl(orchModell) { g1.felder.append(k) }
        g1.felder.append(feld("newSessionDefaultDir", .text(
            wert: d.text("newSessionDefaultDir"), platzhalter: t.t("platzhalter.startordner"),
            setzen: { w, _ in self.setze("newSessionDefaultDir", .text(w)) }), schluessel: "newSessionDefaultDir", wartet: true))

        var g2 = Gruppe(id: "sitzung.leiste", titel: t.t("gruppe.sitzung.leiste"))
        g2.felder.append(feld("showStopped", .schalter(an: d.showStopped, setzen: { an, _ in self.setzeUi("showStopped", an) })))
        g2.felder.append(feld("sort", .wahl(wert: d.sort, optionen: ["recent", "folder", "name"].map { Option(wert: $0, label: t.t("wort.sort.\($0)")) },
                                            setzen: { w, _ in self.setzeUi("sort", w) })))

        var g3 = Gruppe(id: "sitzung.schliessen", titel: t.t("gruppe.sitzung.schliessen"))
        // `== true`: die Vorgabe ist AUS, ein fehlender Schluessel zeigt denselben Haken wie die Vorgabe.
        g3.felder.append(feld("closeSessionOnWindowClose", .schalter(an: d.bool("closeSessionOnWindowClose", false),
                                                                     setzen: { an, _ in self.setze("closeSessionOnWindowClose", .bool(an)) }),
                              schluessel: "closeSessionOnWindowClose"))
        return seite("sitzung", symbol: "terminal", [g1, g2, g3])
    }

    /// Erst der Harness (Filterzeile mit Zahl), dann das Modell; das Gewaehlte steht immer oben.
    private func modellwahl(_ schluessel: String, _ modelle: [ModellSicht], _ gewaehlt: String, werte: [String: String],
                            _ auf: @escaping @MainActor (String) -> Void) -> Einstellungsfeld {
        let filter = zustand.filterStand[schluessel] ?? "alle"
        let suche = (zustand.eingaben["suche:\(schluessel)"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        var proHarness: [(String, Int)] = []
        for m in modelle {
            if let i = proHarness.firstIndex(where: { $0.0 == m.harness }) { proHarness[i].1 += 1 } else { proHarness.append((m.harness, 1)) }
        }
        var chips: [Option] = []
        if proHarness.count >= 2 {
            chips.append(Option(wert: "alle", label: t.t("wort.alleModelle", ["anzahl": String(modelle.count)])))
            for (h, n) in proHarness.sorted(by: { $0.1 > $1.1 }) {
                chips.append(Option(wert: h, label: "\(modelle.first { $0.harness == h }?.harnessLabel ?? h) \(n)"))
            }
        }
        let passt = { (m: ModellSicht) -> Bool in
            (filter == "alle" || m.harness == filter)
                && (suche.isEmpty || m.label.lowercased().contains(suche) || m.id.lowercased().contains(suche))
        }
        let treffer = modelle.filter { $0.id != gewaehlt && passt($0) }
        let das = modelle.first { $0.id == gewaehlt }
        let zeigen = das.map { [$0] + treffer } ?? treffer
        return feld(schluessel, .modelle(schluessel: schluessel, gewaehlt: gewaehlt, zeigen: zeigen, filter: chips, filterWahl: filter,
                                         suche: zustand.eingaben["suche:\(schluessel)"] ?? "", keinTreffer: t.t("satz.keinTreffer"), waehlen: auf),
                    schluessel: schluessel, wartet: true, breit: true, werte: werte)
    }

    /// Die STUFE ist die Wahl eines Menschen, der DECKEL eine Selbstbindung des
    /// Orchestrators: nichts ist gesperrt, ueber dem Deckel steht eine Markierung.
    private func stufenwahl(_ schluessel: String, _ modell: ModellSicht?, _ deckel: DeckelSicht?, _ stufen: [String], _ wert: String) -> Einstellungsfeld {
        if stufen.isEmpty {
            return feld(schluessel, .klartext(modell.map { t.t("satz.stufenKeineWahl", ["harness": $0.harnessLabel]) } ?? t.t("satz.stufenErstModell")),
                        schluessel: schluessel, wartet: true, breit: true)
        }
        let deckelStufe = deckel?.cap ?? modell?.deckelRegistry ?? ""
        let grenze = deckelStufe.isEmpty ? -1 : (stufen.firstIndex(of: deckelStufe) ?? -1)
        let w = wahl(schluessel, wert, stufen.enumerated().map { i, s in
            Option(wert: s, label: s, titel: grenze >= 0 && i > grenze ? t.t("satz.deckelUeber", ["deckel": deckelStufe]) : nil,
                   ueberDeckel: grenze >= 0 && i > grenze)
        }) { s, _ in self.setze(schluessel, .text(s)) }
        var zeile: String
        if !deckelStufe.isEmpty {
            let quelle = deckel?.quelle == "einstellung" ? t.t("wort.vonDir") : t.t("wort.ausAuslieferung")
            zeile = t.t("satz.deckelDieses") + "\(deckelStufe) (\(quelle))" + t.t("satz.deckelGilt")
            if grenze >= 0, grenze < stufen.count - 1 { zeile += t.t("satz.deckelDarueber", ["stufen": stufen[(grenze + 1)...].joined(separator: ", ")]) }
            if let g = deckel?.grund, !g.isEmpty { zeile += "\n" + t.t("satz.deckelGrund", ["grund": g]) }
        } else {
            zeile = t.t("satz.deckelKeiner")
        }
        return feld(schluessel, .stapel([w, klartext("\(schluessel)-deckelzeile", zeile)]), schluessel: schluessel, wartet: true, breit: true)
    }

    /// Das Kontextfenster: nur bei einem lokalen Modell, jede Stufe waehlbar (Vorgabe des Nutzers),
    /// was nicht ermittelt werden konnte, wird gesagt.
    private func kontextwahl(_ modell: ModellSicht?) -> Einstellungsfeld? {
        guard let m = modell, m.lokal else { return nil }
        let werte = ["modell": m.label]
        guard let antwort = zustand.kontextStand[m.id] else {
            zustand.kontextHolen(m.id)
            return feld("orchestratorKontext", .klartext(t.t("satz.kontextWirdErmittelt")), schluessel: "orchestratorKontext", wartet: true, breit: true, werte: werte)
        }
        switch antwort {
        case .fehler(let grund):
            return feld("orchestratorKontext", .klartext(t.t("satz.kontextNichtErmittelt", ["grund": grund])), schluessel: "orchestratorKontext", wartet: true, breit: true, werte: werte)
        case .sicht(let s):
            let gesetzt = d.settings["orchestratorKontext"]?.int ?? 0
            let wert = gesetzt > 0 ? gesetzt : s.vorgabe
            let gewaehlte = s.stufen.first { $0.tokens == wert }
            let fuss: String
            var warnt = false
            if gewaehlte == nil {
                fuss = t.t("satz.kontextFremderWert", ["tokens": String(wert)]); warnt = true
            } else if let g = gewaehlte, !g.passt, !g.hinweis.isEmpty {
                fuss = g.hinweis; warnt = true
            } else {
                fuss = t.t("satz.kontextSpeicher", ["frei": String(format: "%.1f", s.freiMib / 1024), "gewichte": String(format: "%.1f", s.gewichteGb)])
            }
            return feld("orchestratorKontext", .kontext(KontextDarstellung(stufen: s.stufen, wert: wert, empfehlung: s.empfehlung, fuss: fuss, fussWarnt: warnt)),
                        schluessel: "orchestratorKontext", wartet: true, breit: true, werte: werte)
        }
    }

    // --- Seite 2: Erlaubnisse -----------------------------------------------

    func erlaubnisse() -> Seite {
        var v = Gruppe(id: "erlaubnisse.vorsicht", titel: t.t("gruppe.erlaubnisse.vorsicht"), vorsicht: true)
        v.felder.append(feld("workerSkipPermissions", .schalter(an: d.settings["workerSkipPermissions"]?.bool != false, setzen: { an, _ in
            if !an { self.setze("workerSkipPermissions", .bool(false)); return }
            self.zustand.frage(self.t.t("frage.skipAn.text"), tun: self.t.t("frage.skipAn.tun")) { _, _ in self.setze("workerSkipPermissions", .bool(true)) }
        }), schluessel: "workerSkipPermissions", wartet: true))
        v.felder.append(feld("workerWorktrees", .schalter(an: d.settings["workerWorktrees"]?.bool != false, setzen: { an, _ in
            self.setze("workerWorktrees", .bool(an))
        }), schluessel: "workerWorktrees", wartet: true))
        // Ohne `schluessel` -- wie Guard, Wache, Deckel: ein Rueckstell-Zeichen liefe ueber
        // den ungesicherten Weg, der das Anheben immer ablehnt.
        let modi = ["acceptEdits", "auto", "bypassPermissions", "manual", "dontAsk", "plan"]
        let modus = d.text("orchestratorPermissionMode", "bypassPermissions")
        v.felder.append(feld("orchestratorPermissionMode", .wahl(wert: modus, optionen: modi.map { Option(wert: $0, label: t.t("wort.permissionMode.\($0)"), titel: $0) }, setzen: { w, echt in
            if w == modus { return }
            if w != "bypassPermissions" { self.werkzeug(["command": "permission-mode-set", "value": w], echt); return }
            self.zustand.frage(self.t.t("frage.permissionModeAn.text"), tun: self.t.t("frage.permissionModeAn.tun"), mitGrund: true) { grund, echtJa in
                self.werkzeug(["command": "permission-mode-set", "value": w, "grund": grund], echtJa)
            }
        }), wartet: true, breit: true))

        var g1 = Gruppe(id: "erlaubnisse.guards", titel: t.t("gruppe.erlaubnisse.guards"))
        let guardZeilen: [Zeile] = d.guards.map { g in
            let name = t.t("guard.\(g.id).name"), wirkung = t.t("guard.\(g.id).wirkung")
            var z = Zeile(id: "guard:\(g.id)")
            z.schalter = schalter("guard-\(g.id)", g.an) { an, echt in
                if an { self.werkzeug(["command": "guard-set", "guard": g.id, "an": true], echt); return }
                self.zustand.frage(self.t.t("frage.guardAus.text", ["name": name, "wirkung": wirkung]), tun: self.t.t("frage.guardAus.tun"), mitGrund: true) { grund, echtJa in
                    self.werkzeug(["command": "guard-set", "guard": g.id, "an": false, "grund": grund], echtJa)
                }
            }
            z.schalter?.info = t.t("guard.\(g.id).info")
            z.titel = name
            z.grund = g.an ? wirkung
                : ((!g.rolle.isEmpty && g.rolle != "alle") ? t.t("satz.abgeschaltetFuer", ["rolle": g.rolle]) : t.t("satz.abgeschaltet"))
                    + (g.seit.isEmpty ? "" : t.t("satz.seit", ["datum": String(g.seit.prefix(10))]))
                    + (g.grund.isEmpty ? "" : ": \(g.grund)")
            z.abgeschaltet = !g.an
            return z
        }
        let guards = feld("guards", .zeilen(guardZeilen, leer: t.t("satz.keineGuards")), breit: true, id: "guardListe")
        g1.felder.append(guards)

        var g2 = Gruppe(id: "erlaubnisse.rueckfragen", titel: t.t("gruppe.erlaubnisse.rueckfragen"))
        let musterZeilen: [Zeile] = d.askMuster.enumerated().map { i, m in
            var z = Zeile(id: "muster:\(i)")
            let neuMit = { (an: Bool) -> JSONWert in
                .liste(self.d.askMuster.enumerated().map { j, x in j == i ? x.mit(aus: !an) : x.mit(aus: x.aus) })
            }
            z.schalter = schalter("muster-\(i)", !m.aus) { an, _ in
                if an { self.setze("askPatterns", neuMit(true)); return }
                self.zustand.frage(self.t.t("frage.musterAus.text", ["name": m.bezeichnung, "grund": m.grund]), tun: self.t.t("frage.musterAus.tun")) { _, _ in
                    self.setze("askPatterns", neuMit(false))
                }
            }
            z.titel = m.bezeichnung; z.grund = m.grund; z.code = m.muster; z.abgeschaltet = m.aus
            z.rechts = [knopf("musterWeg-\(i)", t.t("wort.entfernen"), warnend: true) { _ in
                self.zustand.frage(self.t.t("frage.musterWeg.text", ["name": m.bezeichnung]), tun: self.t.t("frage.musterWeg.tun")) { _, _ in
                    self.setze("askPatterns", .liste(self.d.askMuster.enumerated().filter { $0.offset != i }.map { $0.element.mit(aus: $0.element.aus) }))
                }
            }]
            return z
        }
        let musterListe = Einstellungsfeld("musterListe", .zeilen(musterZeilen, leer: t.t("satz.keineMuster")))
        let anlegen = Einstellungsfeld("musterAnlegen", .reihe([
            eingabe("musterBefehl", t.t("platzhalter.musterBefehl")),
            eingabe("musterUnterbefehl", t.t("platzhalter.musterUnterbefehl")),
            eingabe("musterGrund", t.t("platzhalter.musterGrund")),
            knopf("musterHinzufuegen", t.t("wort.hinzufuegen")) { _ in
                let befehl = (self.zustand.eingaben["musterBefehl"] ?? "").trimmingCharacters(in: .whitespaces)
                guard !befehl.isEmpty else { self.zustand.melde(self.t.t("satz.musterOhneBefehl"), "fehler"); return }
                var neu: [String: JSONWert] = ["befehl": .text(befehl)]
                let grund = (self.zustand.eingaben["musterGrund"] ?? "").trimmingCharacters(in: .whitespaces)
                neu["grund"] = .text(grund.isEmpty ? self.t.t("satz.musterVonHand") : grund)
                let unter = (self.zustand.eingaben["musterUnterbefehl"] ?? "").trimmingCharacters(in: .whitespaces)
                if !unter.isEmpty { neu["unterbefehl"] = .text(unter) }
                self.zustand.eingaben["musterBefehl"] = ""; self.zustand.eingaben["musterUnterbefehl"] = ""; self.zustand.eingaben["musterGrund"] = ""
                self.setze("askPatterns", .liste(self.d.askMuster.map { $0.mit(aus: $0.aus) } + [.objekt(neu)]))
            },
        ]))
        g2.felder.append(feld("askPatterns", .stapel([musterListe, anlegen]), schluessel: "askPatterns", breit: true))

        var g3 = Gruppe(id: "erlaubnisse.geheimnisse", titel: t.t("gruppe.erlaubnisse.geheimnisse"))
        let chipListe = { (werte: [String], id: String, schluessel: String, was: String) -> Einstellungsfeld in
            let chips = Einstellungsfeld(id, .chips(werte: werte, leer: self.t.t("wort.leerListe")) { w in
                let neu = werte.filter { $0 != w }
                if neu.isEmpty {
                    self.zustand.frage(self.t.t("frage.listeLeer.text", ["was": was]), tun: self.t.t("frage.listeLeer.tun")) { _, _ in self.setze(schluessel, .liste([])) }
                    return
                }
                self.setze(schluessel, .liste(neu.map(JSONWert.text)))
            })
            let anlegen = Einstellungsfeld("\(id)Anlegen", .reihe([
                self.eingabe("\(id)Neu", was),
                self.knopf("\(id)Hinzufuegen", self.t.t("wort.hinzufuegen")) { _ in
                    let w = (self.zustand.eingaben["\(id)Neu"] ?? "").trimmingCharacters(in: .whitespaces)
                    guard !w.isEmpty, !werte.contains(w) else { return }
                    self.zustand.eingaben["\(id)Neu"] = ""
                    self.setze(schluessel, .liste((werte + [w]).map(JSONWert.text)))
                },
            ]))
            return self.feld(schluessel, .stapel([chips, anlegen]), schluessel: schluessel, breit: true, id: "\(id)Einstellungsfeld")
        }
        g3.felder.append(chipListe(d.ausschlussOrdner, "secretExcludeDirs", "secretExcludeDirs", t.t("platzhalter.ordner")))
        g3.felder.append(chipListe(d.ausschlussMuster, "secretExcludePatterns", "secretExcludePatterns", t.t("platzhalter.dateimuster")))

        // Werkzeuge und MCP-Server: nur Anzeige -- was ein Agent bekommt, steht in fremden Konfigurationen.
        var g4 = Gruppe(id: "erlaubnisse.werkzeuge", titel: t.t("gruppe.erlaubnisse.werkzeuge"))
        let hookZeilen: [Zeile] = d.hooks.map { h in
            var z = Zeile(id: "hook:\(h.name)"); z.titel = h.name; z.grund = h.ereignis; z.marke = h.lehntAb ? "lehnt ab" : ""; return z
        }
        g4.felder.append(feld("werkzeuge", .stapel([
            Einstellungsfeld("hookListe", .zeilen(hookZeilen, leer: t.t("satz.werkzeugeOhneHooks"))),
            klartext("werkzeugeMcp", t.t("satz.werkzeugeMcp")),
        ]), breit: true))
        return seite("erlaubnisse", symbol: "checkmark.shield", [v, g1, g2, g3, g4])
    }

    // --- Seite 3: Programme und Modelle -------------------------------------

    func harnesses() -> Seite {
        var g1 = Gruppe(id: "harnesses.programme", titel: t.t("gruppe.harnesses.programme"))
        let kopf = [t.t("spalte.programm"), t.t("spalte.hier"), t.t("spalte.anmeldung"), t.t("spalte.stufen"), t.t("spalte.modelle"), t.t("spalte.chat")]
        let zeilen: [TabellenZeile] = d.harnesses.map { h in
            let stufen = d.harnessStufen[h.id]
            var zellen: [Zelle] = [.text(h.label)]
            zellen.append(.text(h.binaer ? t.t("wort.startbar") : t.t("wort.nichtStartbar", ["maschine": d.machine]), sekundaer: !h.binaer))
            let an = d.anmeldung[h.id]
            zellen.append(.text(an?.stand == "ja" ? t.t("wort.angemeldet") : an?.stand == "nein" ? t.t("wort.nichtAngemeldet") : t.t("wort.anmeldungUnbekannt"),
                                sekundaer: an?.stand != "ja", titel: an?.grund ?? ""))
            zellen.append(.text(stufen == nil ? t.t("wort.stufenNichtErmittelt") : (stufen!.isEmpty ? t.t("wort.keineStufen") : stufen!.joined(separator: " ")), sekundaer: true))
            zellen.append(.text(String(h.modelle)))
            let quelle = d.chatQuellen[h.id]
            if let q = quelle, !q.via.isEmpty, !q.probe.isEmpty {
                let s = schalter("chat-\(h.id)", d.chatAnsicht[h.id] == true) { an, _ in
                    var neu = self.d.chatAnsicht.mapValues(JSONWert.bool); neu[h.id] = .bool(an)
                    self.setze("chatAnsicht", .objekt(neu))
                }
                let wie = klartext("chat-\(h.id)-wie", q.live ? t.t("satz.chatKannLive") : t.t("satz.chatKannNichtLive"))
                if !q.zeigtNicht.isEmpty { wie.info = t.t("satz.chatZeigtNicht", ["liste": q.zeigtNicht.joined(separator: ", ")]) }
                zellen.append(.felder([s, wie]))
            } else {
                zellen.append(.text((quelle != nil && !quelle!.via.isEmpty && quelle!.probe.isEmpty) ? t.t("satz.chatOhneMessung") : (quelle?.grund.isEmpty == false ? quelle!.grund : t.t("satz.chatKannNicht")), sekundaer: true))
            }
            return TabellenZeile(id: "harness:\(h.id)", zellen: zellen, warnung: !h.binaer)
        }
        g1.felder.append(feld("harnessTabelle", .tabelle(kopf: kopf, zeilen: zeilen, leer: ""), breit: true))
        g1.felder.append(feld("chatAnsicht", .klartext(t.t("satz.chatKannNicht")), schluessel: "chatAnsicht", wartet: true, breit: true))
        g1.felder.append(feld("workerTransport", .wahl(wert: d.text("workerTransport", "tmux"), optionen: [Option(wert: "tmux", label: "tmux"), Option(wert: "pty", label: "pty")],
                                                       setzen: { w, _ in self.setze("workerTransport", .text(w)) }), schluessel: "workerTransport", wartet: true))

        var g2 = Gruppe(id: "harnesses.lokal", titel: t.t("gruppe.harnesses.lokal"))
        g2.felder.append(feld("ollamaEndpoint", .stapel([
            Einstellungsfeld("ollamaEndpoint", .text(wert: d.ollamaEndpunkt, platzhalter: t.t("platzhalter.ollama"), setzen: { w, _ in self.setze("ollamaEndpoint", .text(w)) })),
            klartext("ollamaHinweis", t.t("satz.ollamaNochNichtVerdrahtet")),
        ]), schluessel: "ollamaEndpoint", wartet: true, breit: true, id: "ollamaEndpointFeld"))
        g2.felder.append(feld("modelDiscoveryAuto", .schalter(an: d.settings["modelDiscoveryAuto"]?.bool != false, setzen: { an, _ in self.setze("modelDiscoveryAuto", .bool(an)) }),
                              schluessel: "modelDiscoveryAuto"))
        // Multi-Token-Vorhersage: An/Aus je Rolle; das Modell dahinter ist Anzeige aus der Registry.
        let orchModellId = d.text("orchestratorModel")
        var orchTeile: [Einstellungsfeld] = [Einstellungsfeld("orchestratorVorhersage", .schalter(an: d.bool("orchestratorVorhersage", false), setzen: { an, _ in self.setze("orchestratorVorhersage", .bool(an)) }))]
        if let wege = vorhersageWegWahl(d.orchestratorModelle, orchModellId, d.text("orchestratorVorhersageWeg")) {
            orchTeile.append(wege)
        } else {
            orchTeile.append(klartext("orchestratorVorhersageAnzeige", vorhersageAnzeige(d.orchestratorModelle, orchModellId)))
        }
        g2.felder.append(feld("orchestratorVorhersage", .stapel(orchTeile), schluessel: "orchestratorVorhersage", breit: true, id: "orchestratorVorhersageFeld"))
        g2.felder.append(feld("workerVorhersage", .stapel([
            Einstellungsfeld("workerVorhersage", .schalter(an: d.bool("workerVorhersage", false), setzen: { an, _ in self.setze("workerVorhersage", .bool(an)) })),
            klartext("workerVorhersageAnzeige", vorhersageAnzeige(d.workerModelle, d.text("workerModel"))),
        ]), schluessel: "workerVorhersage", breit: true, id: "workerVorhersageFeld"))

        var g3 = Gruppe(id: "harnesses.schluessel", titel: t.t("gruppe.harnesses.schluessel"))
        let aKopf = [t.t("spalte.anbieter"), t.t("spalte.zugang"), t.t("spalte.eingabe")]
        let aZeilen: [TabellenZeile] = d.anbieter.map { p in
            let imBund = p.art == "schluessel" && zustand.schluesselStand[p.id] == true
            let stand = imBund ? "ja" : p.stand
            let wort = p.art == "lokal" ? t.t("wort.zugangLokal") : stand == "ja" ? t.t("wort.zugangDa")
                : stand == "nein" ? (p.art == "abo" ? t.t("wort.zugangAbo") : t.t("wort.zugangFehlt")) : t.t("wort.zugangUnbekannt")
            var zellen: [Zelle] = [.text(p.label), .text(wort, sekundaer: stand != "ja")]
            if p.art == "schluessel" {
                zellen.append(.felder([
                    eingabe("schluessel-\(p.id)", t.t("platzhalter.schluesselEingabe"), geheim: true),
                    knopf("schluesselSpeichern-\(p.id)", t.t("wort.speichern")) { _ in self.zustand.schluesselSpeichern(p) },
                ]))
            } else {
                zellen.append(.text(""))
            }
            return TabellenZeile(id: "anbieter:\(p.id)", zellen: zellen)
        }
        g3.felder.append(feld("anbieter", .tabelle(kopf: aKopf, zeilen: aZeilen, leer: ""), breit: true))

        var g4 = Gruppe(id: "harnesses.deckel", titel: t.t("gruppe.harnesses.deckel"))
        g4.felder.append(Einstellungsfeld("deckelLeitsatz", .leitsatz(fett: t.t("satz.deckelLeitsatzFett"), rest: t.t("satz.deckelLeitsatz"))))
        var alle = d.orchestratorModelle
        for m in d.workerModelle where !alle.contains(where: { $0.id == m.id }) { alle.append(m) }
        alle.sort { $0.harness == $1.harness ? $0.label < $1.label : $0.harness < $1.harness }
        let suche = (zustand.eingaben["suche:deckel"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let treffer = alle.filter { suche.isEmpty || $0.label.lowercased().contains(suche) || $0.id.lowercased().contains(suche) }
        let dKopf = [t.t("spalte.modell"), t.t("spalte.programm"), t.t("spalte.deckel"), t.t("spalte.herkunft"), t.t("spalte.grund")]
        let dZeilen: [TabellenZeile] = treffer.prefix(60).map { m in
            let gesetzt = d.effortCaps[m.id]
            let quelle = gesetzt != nil ? "einstellung" : (m.deckelRegistry.isEmpty ? "-" : "registry")
            let stufen = d.harnessStufen[m.harness]
            var zellen: [Zelle] = [.zwei(m.label, m.id), .text(m.harnessLabel, sekundaer: true)]
            if stufen == nil {
                zellen.append(.text(t.t("wort.stufenNichtErmittelt"), sekundaer: true))
            } else if stufen!.isEmpty {
                zellen.append(.text(t.t("wort.keineStufen"), sekundaer: true))
            } else {
                var optionen = [Option(wert: "", label: t.t("satz.deckelAuslieferungWahl", ["deckel": m.deckelRegistry.isEmpty ? t.t("wort.ohne") : m.deckelRegistry]))]
                optionen += stufen!.map { Option(wert: $0, label: $0) }
                // Immer ein Aufklappmenue, wie das <select> der Tabelle -- ueber die Segmentgrenze hinweg.
                let wahlFeld = Einstellungsfeld("deckel:\(m.id)", .wahl(wert: gesetzt?.cap ?? "", optionen: optionen, setzen: { stufe, echt in
                    if stufe.isEmpty { self.werkzeug(["command": "effort-cap", "model": m.id], echt); return }
                    self.zustand.frage(self.t.t("frage.deckel.text", ["modell": m.label, "stufe": stufe]), tun: self.t.t("frage.deckel.tun"), mitGrund: true) { grund, echtJa in
                        self.werkzeug(["command": "effort-cap", "model": m.id, "stufe": stufe, "grund": grund], echtJa)
                    }
                }))
                wahlFeld.menue = true
                zellen.append(.feld(wahlFeld))
            }
            zellen.append(.text(quelle == "einstellung" ? t.t("wort.vonDirAm", ["datum": String((gesetzt?.gesetzt ?? "").prefix(10))]) : quelle, sekundaer: gesetzt == nil))
            zellen.append(.text(gesetzt?.grund ?? "", sekundaer: true))
            return TabellenZeile(id: "deckelzeile:\(m.id)", zellen: zellen)
        }
        var deckelTeile: [Einstellungsfeld] = [eingabe("suche:deckel", t.t("platzhalter.suche")), Einstellungsfeld("deckelTabelle", .tabelle(kopf: dKopf, zeilen: dZeilen, leer: t.t("satz.keinTrefferSuche")))]
        if treffer.count > 60 { deckelTeile.append(klartext("deckelZuViele", t.t("satz.zuVieleTreffer", ["anzahl": String(treffer.count)]))) }
        g4.felder.append(feld("effortCaps", .stapel(deckelTeile), wartet: true, breit: true))
        return seite("harnesses", symbol: "cpu", [g1, g2, g3, g4])
    }

    private func vorhersageAnzeige(_ modelle: [ModellSicht], _ modellId: String) -> String {
        guard let v = modelle.first(where: { $0.id == modellId })?.vorhersage else { return t.t("satz.vorhersageKeine") }
        let bauart = v.bauart == "entwerfer" ? t.t("wort.vorhersageEntwerfer") : t.t("wort.vorhersageEingebaut")
        let kurz = v.modell.split(separator: "/").last.map(String.init) ?? v.modell
        var s = t.t("satz.vorhersageModell", ["modell": kurz, "bauart": bauart])
        if !v.herkunft.isEmpty { s += "\n" + v.herkunft }
        return s
    }

    /// Fuehrt die Registry fuer das Modell mehrere Wege, stehen sie zur Wahl; die Rueckwahl auf den Vorgabeweg speichert LEER.
    private func vorhersageWegWahl(_ modelle: [ModellSicht], _ modellId: String, _ gewaehlt: String) -> Einstellungsfeld? {
        guard let v = modelle.first(where: { $0.id == modellId })?.vorhersage, v.wege.count > 1 else { return nil }
        let vorgabe = v.wegVorgabe.isEmpty ? v.wege[0].id : v.wegVorgabe
        let wirksam = gewaehlt.isEmpty ? vorgabe : gewaehlt
        let w = wahl("orchestratorVorhersageWeg", wirksam, v.wege.map { weg in
            Option(wert: weg.id, label: weg.id == vorgabe ? t.t("satz.vorhersageWegVorgabe", ["weg": weg.label]) : weg.label)
        }) { weg, _ in self.setze("orchestratorVorhersageWeg", .text(weg == vorgabe ? "" : weg)) }
        var teile = [w]
        if let weg = v.wege.first(where: { $0.id == wirksam }) {
            let bauart = weg.bauart == "entwerfer" ? t.t("wort.vorhersageEntwerfer") : t.t("wort.vorhersageEingebaut")
            let kurz = weg.modell.split(separator: "/").last.map(String.init) ?? weg.modell
            teile.append(klartext("orchestratorVorhersageWegModell", t.t("satz.vorhersageModell", ["modell": kurz, "bauart": bauart])))
            if !weg.herkunft.isEmpty { teile.append(klartext("orchestratorVorhersageWegHerkunft", weg.herkunft)) }
        }
        return Einstellungsfeld("vorhersagewege", .stapel(teile))
    }

    // --- Seite 4: Maschinen -------------------------------------------------

    func maschinen() -> Seite {
        var g = Gruppe(id: "maschinen.liste", titel: t.t("gruppe.maschinen.liste"))
        var zeilen: [Zeile] = []
        var eigen = Zeile(id: "maschine:local"); eigen.titel = d.machine; eigen.grund = t.t("satz.eigeneMaschine")
        zeilen.append(eigen)
        for m in d.maschinen {
            let pausiert = d.maschinenPausiert.contains(m)
            var z = Zeile(id: "maschine:\(m)")
            z.schalter = schalter("maschinePause-\(m)", !pausiert) { an, _ in
                let neu = an ? self.d.maschinenPausiert.filter { $0 != m } : self.d.maschinenPausiert + [m]
                self.setze("remoteMachinesPausiert", .liste(neu.map(JSONWert.text)))
            }
            z.schalter?.name = t.t("wort.sitzungenLaden")
            z.schalter?.info = t.t("wort.maschineLaden")
            z.titel = m
            z.grund = t.t("satz.fremdeMaschine", ["name": m])
            z.abgeschaltet = pausiert
            if let a = zustand.maschinenAntwort[m] { z.antwort = a.text; z.antwortArt = a.ok ? "gut" : (a.text == t.t("wort.frage") ? "" : "schlecht") }
            z.rechts = [
                knopf("maschinePruefen-\(m)", t.t("wort.pruefen")) { _ in self.zustand.maschinePruefen(m) },
                knopf("maschineWeg-\(m)", t.t("wort.entfernen"), warnend: true) { _ in
                    self.setze("remoteMachines", .liste(self.d.maschinen.filter { $0 != m }.map(JSONWert.text)))
                },
            ]
            z.unten = t.t("satz.fremdeLast", ["name": m])
            zeilen.append(z)
        }
        let liste = Einstellungsfeld("maschinenListe", .zeilen(zeilen, leer: ""))
        let anlegen = Einstellungsfeld("maschineAnlegen", .reihe([
            eingabe("maschineNeu", t.t("platzhalter.maschine")),
            knopf("maschineHinzufuegen", t.t("wort.hinzufuegen")) { _ in
                let name = (self.zustand.eingaben["maschineNeu"] ?? "").trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                if self.d.maschinen.contains(name) { self.zustand.melde(self.t.t("satz.maschineSchonDa", ["name": name]), "fehler"); return }
                self.zustand.eingaben["maschineNeu"] = ""
                self.setze("remoteMachines", .liste((self.d.maschinen + [name]).map(JSONWert.text)))
            },
        ]))
        g.felder.append(feld("remoteMachines", .stapel([liste, anlegen, klartext("remoteMachinesPausiertWirkung", t.t("feld.remoteMachinesPausiert.wirkung"))]),
                             schluessel: "remoteMachines", breit: true))

        var g2 = Gruppe(id: "maschinen.last", titel: t.t("gruppe.maschinen.last"))
        g2.felder.append(feld("maxWorkers", .zahl(wert: d.zahl("maxWorkers", 8), min: 1, max: 64, einheit: "Worker", setzen: { n, _ in self.setze("maxWorkers", .zahl(Double(n))) }),
                              schluessel: "maxWorkers"))
        let maschinenwahl = [Option(wert: "local", label: t.t("wort.dieseMaschine", ["name": d.machine]))] + d.maschinen.map { Option(wert: $0, label: $0) }
        g2.felder.append(feld("defaultWorkerMachine", .wahl(wert: d.text("defaultWorkerMachine", "local"), optionen: maschinenwahl,
                                                            setzen: { w, _ in self.setze("defaultWorkerMachine", .text(w)) }), schluessel: "defaultWorkerMachine", wartet: true))
        g2.felder.append(feld("workerZustellung", .wahl(wert: d.text("workerZustellung", "auto"),
                                                        optionen: ["auto", "socket", "paste"].map { Option(wert: $0, label: t.t("wort.workerZustellung.\($0)")) },
                                                        setzen: { w, _ in self.setze("workerZustellung", .text(w)) }), schluessel: "workerZustellung", wartet: true))
        return seite("maschinen", symbol: "desktopcomputer", [g, g2])
    }

    // --- Seite 5: Aufsicht und Meldungen -----------------------------------

    func aufsicht() -> Seite {
        var g1 = Gruppe(id: "aufsicht.wache", titel: t.t("gruppe.aufsicht.wache"))
        g1.felder.append(feld("contextGuardAutostart", .schalter(an: d.settings["contextGuardAutostart"]?.bool != false, setzen: { an, _ in
            if an { self.setze("contextGuardAutostart", .bool(true)); return }
            self.zustand.frage(self.t.t("frage.wacheAus.text"), tun: self.t.t("frage.wacheAus.tun")) { _, _ in self.setze("contextGuardAutostart", .bool(false)) }
        }), schluessel: "contextGuardAutostart", wartet: true))
        let orch = d.wache["orchestrator"] ?? WacheRolle(an: true, mahnenAb: 75, eingreifen: true, notbremseAb: 80)
        let wkr = d.wache["worker"] ?? WacheRolle(an: true, mahnenAb: 80, eingreifen: true, notbremseAb: nil)
        let wacheAn = { (id: String, rolle: String, an: Bool, frage: String, tun: String) -> Einstellungsfeld in
            self.feld(id, .schalter(an: an, setzen: { neu, echt in
                if neu { self.werkzeug(["command": "wache-set", "rolle": rolle, "an": true], echt); return }
                self.zustand.frage(self.t.t(frage), tun: self.t.t(tun), mitGrund: true) { grund, echtJa in
                    self.werkzeug(["command": "wache-set", "rolle": rolle, "an": false, "grund": grund], echtJa)
                }
            }), wartet: true)
        }
        g1.felder.append(wacheAn("wacheOrchAn", "orchestrator", orch.an, "frage.wacheOrchAus.text", "frage.wacheOrchAus.tun"))
        g1.felder.append(wacheAn("wacheWorkerAn", "worker", wkr.an, "frage.wacheWorkerAus.text", "frage.wacheWorkerAus.tun"))
        let mahnen = { (id: String, rolle: String, alt: Int, frage: String) -> Einstellungsfeld in
            self.feld(id, .zahl(wert: alt, min: 1, max: 99, einheit: "%", setzen: { n, echt in
                if n <= alt { self.werkzeug(["command": "wache-set", "rolle": rolle, "mahnenAb": n], echt); return }
                self.zustand.frage(self.t.t(frage, ["wert": String(n)]), tun: self.t.t("frage.mahnenHoch.tun"), mitGrund: true) { grund, echtJa in
                    self.werkzeug(["command": "wache-set", "rolle": rolle, "mahnenAb": n, "grund": grund], echtJa)
                }
            }), wartet: true)
        }
        g1.felder.append(mahnen("wacheWorkerMahnenAb", "worker", wkr.mahnenAb, "frage.mahnenHoch.worker"))
        g1.felder.append(mahnen("wacheOrchMahnenAb", "orchestrator", orch.mahnenAb, "frage.mahnenHoch.orch"))
        g1.felder.append(feld("wacheOrchEingreifen", .schalter(an: orch.eingreifen, setzen: { an, echt in
            if an { self.werkzeug(["command": "wache-set", "rolle": "orchestrator", "eingreifen": true], echt); return }
            self.zustand.frage(self.t.t("frage.eingreifenAus.text"), tun: self.t.t("frage.eingreifenAus.tun"), mitGrund: true) { grund, echtJa in
                self.werkzeug(["command": "wache-set", "rolle": "orchestrator", "eingreifen": false, "grund": grund], echtJa)
            }
        }), wartet: true))
        let notbremse = orch.notbremseAb ?? 80
        g1.felder.append(feld("wacheOrchNotbremseAb", .zahl(wert: notbremse, min: 1, max: 99, einheit: "%", setzen: { n, echt in
            if n <= notbremse { self.werkzeug(["command": "wache-set", "rolle": "orchestrator", "notbremseAb": n], echt); return }
            self.zustand.frage(self.t.t("frage.notbremseHoch.text", ["wert": String(n)]), tun: self.t.t("frage.notbremseHoch.tun"), mitGrund: true) { grund, echtJa in
                self.werkzeug(["command": "wache-set", "rolle": "orchestrator", "notbremseAb": n, "grund": grund], echtJa)
            }
        }), wartet: true))
        g1.felder.append(klartext("guardsWohnenAnderswo", t.t("satz.guardsWohnenAnderswo")))

        var g2 = Gruppe(id: "aufsicht.stillstand", titel: t.t("gruppe.aufsicht.stillstand"))
        g2.felder.append(feld("stallMinutes", .zahl(wert: d.zahl("stallMinutes", 10), min: 1, max: 120, einheit: "Minuten Stille", setzen: { n, _ in self.setze("stallMinutes", .zahl(Double(n))) }),
                              schluessel: "stallMinutes"))
        g2.felder.append(feld("guardMeldetWorkerStatus", .schalter(an: d.bool("guardMeldetWorkerStatus", false), setzen: { an, _ in self.setze("guardMeldetWorkerStatus", .bool(an)) }),
                              schluessel: "guardMeldetWorkerStatus", wartet: true))

        // Benachrichtigungen: jedes Einstellungsfeld schreibt den GANZEN Block zurueck.
        var g3 = Gruppe(id: "aufsicht.meldungen", titel: t.t("gruppe.aufsicht.meldungen"))
        let m = d.meldungen
        g3.felder.append(feld("meldungenAn", .schalter(an: m.an, setzen: { an, _ in
            if an, m.ereignisse.isEmpty, m.wege.isEmpty, let v = self.d.vorgaben["meldungen"] {
                // Beim Einschalten EINMAL den vollen Vorgabeblock schreiben (einstellungen.ts).
                self.setze("meldungen", m.mit(an: an, ereignisse: v["ereignisse"].texte, wege: v["wege"].texte, limitSchwelle: v["limitSchwelle"].int))
            } else {
                self.setze("meldungen", m.mit(an: an))
            }
        }), schluessel: "meldungen", wartet: true))
        let ereignisZeilen: [Zeile] = d.meldeEreignisse.map { e in
            let gewaehlt = m.ereignisse.contains(e)
            var z = Zeile(id: "meldung:\(e)")
            z.schalter = schalter("meldung-\(e)", gewaehlt) { an, _ in
                self.setze("meldungen", m.mit(ereignisse: an ? self.d.meldeEreignisse.filter { $0 == e || m.ereignisse.contains($0) } : m.ereignisse.filter { $0 != e }))
            }
            z.titel = t.t("meldung.\(e)"); z.abgeschaltet = !gewaehlt
            return z
        }
        g3.felder.append(feld("meldungenEreignisse", .zeilen(ereignisZeilen, leer: ""), wartet: true, breit: true, id: "meldeEreignisse"))
        let wegZeilen: [Zeile] = d.meldeWege.map { w in
            var z = Zeile(id: "weg:\(w)")
            z.schalter = schalter("weg-\(w)", m.wege.contains(w)) { an, _ in
                self.setze("meldungen", m.mit(wege: an ? self.d.meldeWege.filter { $0 == w || m.wege.contains($0) } : m.wege.filter { $0 != w }))
            }
            z.titel = t.t("weg.\(w)")
            return z
        }
        g3.felder.append(feld("meldungenWege", .zeilen(wegZeilen, leer: ""), wartet: true, breit: true))
        g3.felder.append(feld("meldungenHandyUrl", .text(wert: m.handyUrl, platzhalter: t.t("platzhalter.handyUrl"), setzen: { w, _ in self.setze("meldungen", m.mit(handyUrl: w)) }), wartet: true, breit: true))
        g3.felder.append(feld("meldungenTonDatei", .text(wert: m.tonDatei, platzhalter: t.t("platzhalter.tonDatei"), setzen: { w, _ in self.setze("meldungen", m.mit(tonDatei: w)) }), wartet: true, breit: true))
        g3.felder.append(feld("meldungenLimitSchwelle", .zahl(wert: m.limitSchwelle, min: 1, max: 99, einheit: "%", setzen: { n, _ in self.setze("meldungen", m.mit(limitSchwelle: n)) }), wartet: true))
        var testTeile: [Einstellungsfeld] = [knopf("meldungTesten", t.t("knopf.meldungTesten")) { _ in self.zustand.meldungTesten() }]
        if let r = zustand.meldungTest {
            if r.istNull {
                testTeile.append(klartext("meldungTestErgebnis", t.t("meldungTesten.laeuft")))
            } else if r["an"].bool != true {
                testTeile.append(klartext("meldungTestErgebnis", t.t("meldungTesten.hauptschalterAus")))
            } else {
                let ergebnisse = r["ergebnisse"].objekt ?? [:]
                let gewaehlt = d.meldeWege.filter { ergebnisse[$0] != nil }
                if gewaehlt.isEmpty {
                    testTeile.append(klartext("meldungTestErgebnis", t.t("meldungTesten.keinWeg")))
                } else {
                    let zeilen: [Zeile] = gewaehlt.map { weg in
                        let e = ergebnisse[weg] ?? .null
                        let ok = e["ok"].bool ?? false
                        var z = Zeile(id: "meldungTest:\(weg)"); z.titel = t.t("weg.\(weg)")
                        z.antwort = weg == "handy"
                            ? (ok ? t.t("meldungTesten.handy.ok", ["status": e["status"].zeichenkette]) : t.t("meldungTesten.handy.fehler", ["grund": e["grund"].text ?? ""]))
                            : t.t("meldungTesten.\(weg).\(ok ? "ok" : "fehler")", ["grund": e["grund"].text ?? ""])
                        z.antwortArt = ok ? "gut" : "schlecht"
                        return z
                    }
                    testTeile.append(Einstellungsfeld("meldungTestErgebnis", .zeilen(zeilen, leer: "")))
                }
            }
        }
        g3.felder.append(feld("meldungTesten", .stapel(testTeile), breit: true, id: "meldungTestenFeld"))
        return seite("aufsicht", symbol: "eye", [g1, g2, g3])
    }

    // --- Seite 6: Aussehen --------------------------------------------------

    func aussehen() -> Seite {
        var g1 = Gruppe(id: "aussehen.thema", titel: t.t("gruppe.aussehen.thema"))
        g1.felder.append(feld("thema", .wahl(wert: d.thema, optionen: ["system", "hell", "dunkel"].map { Option(wert: $0, label: t.t("wort.thema.\($0)")) },
                                             setzen: { w, _ in self.setze("thema", .text(w)) }), schluessel: "thema"))
        let farben = ["laeuft", "wartet", "fertig", "tot"].map { (zustand: $0, label: t.t("zustand.\($0)"), hex: d.zustandsfarben[$0] ?? "#888888") }
        g1.felder.append(feld("zustandsfarben", .farben(farben, setzen: { z, hex in
            var neu = self.d.zustandsfarben.mapValues(JSONWert.text); neu[z] = .text(hex)
            self.setze("zustandsfarben", .objekt(neu))
        }), schluessel: "zustandsfarben", breit: true))

        var g2 = Gruppe(id: "aussehen.terminal", titel: t.t("gruppe.aussehen.terminal"))
        g2.felder.append(feld("terminalFontSize", .zahl(wert: d.zahl("terminalFontSize", 13), min: 8, max: 32, einheit: t.t("wort.einheit.punkt"), setzen: { n, _ in self.setze("terminalFontSize", .zahl(Double(n))) }), schluessel: "terminalFontSize"))
        g2.felder.append(feld("terminalScrollLines", .zahl(wert: d.zahl("terminalScrollLines", 3), min: 1, max: 20, einheit: t.t("wort.einheit.zeilen"), setzen: { n, _ in self.setze("terminalScrollLines", .zahl(Double(n))) }), schluessel: "terminalScrollLines"))

        var g3 = Gruppe(id: "aussehen.panes", titel: t.t("gruppe.aussehen.panes"))
        g3.felder.append(feld("minWorkerPaneWidth", .zahl(wert: d.zahl("minWorkerPaneWidth", 80), min: 20, max: 1000, einheit: t.t("wort.einheit.spalten"), setzen: { n, _ in self.setze("minWorkerPaneWidth", .zahl(Double(n))) }), schluessel: "minWorkerPaneWidth"))
        g3.felder.append(feld("maxWorkerPanesPerTab", .zahl(wert: d.zahl("maxWorkerPanesPerTab", 6), min: 0, max: 64, einheit: "Panes", setzen: { n, _ in self.setze("maxWorkerPanesPerTab", .zahl(Double(n))) }), schluessel: "maxWorkerPanesPerTab", wartet: true))
        g3.felder.append(feld("workerLayout", .wahl(wert: d.text("workerLayout", "split"), optionen: ["split", "window"].map { Option(wert: $0, label: t.t("wort.workerLayout.\($0)")) },
                                                    setzen: { w, _ in self.setze("workerLayout", .text(w)) }), schluessel: "workerLayout", wartet: true))

        var g4 = Gruppe(id: "aussehen.sprache", titel: t.t("gruppe.aussehen.sprache"))
        g4.felder.append(feld("sprache", .wahl(wert: d.sprache, optionen: ["de", "en"].map { Option(wert: $0, label: t.t("wort.sprache.\($0)")) },
                                               setzen: { w, _ in self.setze("sprache", .text(w)) }), schluessel: "sprache", wartet: true, breit: true))
        // Zwei Schalter, EIN Schluessel: Orchestrator und Worker getrennt, aber eine Einstellung.
        let rollen: [Zeile] = ["orchestrator", "worker"].map { rolle in
            let an = rolle == "orchestrator" ? d.chatAnsichtVorgabeOrchestrator : d.chatAnsichtVorgabeWorker
            var z = Zeile(id: "rolle:\(rolle)")
            z.schalter = schalter("chatAnsichtVorgabe-\(rolle)", an) { neu, _ in
                var o: [String: JSONWert] = ["orchestrator": .bool(self.d.chatAnsichtVorgabeOrchestrator), "worker": .bool(self.d.chatAnsichtVorgabeWorker)]
                o[rolle] = .bool(neu)
                self.setze("chatAnsichtVorgabe", .objekt(o))
            }
            z.titel = t.t("wort.rolle.\(rolle)")
            return z
        }
        g4.felder.append(feld("chatAnsichtVorgabe", .zeilen(rollen, leer: ""), schluessel: "chatAnsichtVorgabe", wartet: true, breit: true))
        return seite("aussehen", symbol: "circle.lefthalf.filled", [g1, g2, g3, g4])
    }

    // --- Seite 7: Programm --------------------------------------------------

    func programm() -> Seite {
        var g1 = Gruppe(id: "programm.abweichungen", titel: t.t("gruppe.programm.abweichungen"))
        let liste = d.abweichungen
        let kopf = [t.t("spalte.einstellung"), t.t("spalte.beiDir"), t.t("spalte.auslieferung"), ""]
        let zeilen: [TabellenZeile] = liste.map { k in
            TabellenZeile(id: "abweichung:\(k)", zellen: [
                .text(t.t("bezeichnung.\(k)")), wertZelle(k, d.settings[k]), wertZelle(k, d.vorgaben[k]),
                .feld(knopf("zurueck-\(k)", t.t("wort.zuruecksetzen")) { _ in if let v = self.d.vorgaben[k] { self.setze(k, v) } }),
            ])
        }
        g1.felder.append(feld("abweichungen", .tabelle(kopf: kopf, zeilen: zeilen, leer: t.t("satz.keineAbweichung")), breit: true))

        // Gesichert wird, was ABWEICHT; eingesetzt ueber denselben Schreibweg wie jeder Haken.
        var g2 = Gruppe(id: "programm.sicherung", titel: t.t("gruppe.programm.sicherung"))
        var stand: [String: JSONWert] = [:]
        for k in liste { stand[k] = d.settings[k] }
        let sicherungsfeld = Einstellungsfeld("sicherungsfeld", .eingabe(platzhalter: t.t("platzhalter.sicherung"), geheim: false, mehrzeilig: true))
        let reihe = Einstellungsfeld("sicherungKnoepfe", .reihe([
            knopf("sicherungKopieren", t.t("wort.kopieren")) { _ in
                guard !liste.isEmpty else { self.zustand.melde(self.t.t("satz.sicherungLeer"), "fehler"); return }
                let roh = JSONWert.objekt(stand).zeichenkette
                self.zustand.eingaben["sicherungsfeld"] = roh
                // Kopflos nie in die Zwischenablage des Menschen (regeln/tests-und-eingriffe.md).
                if !self.zustand.kopflos { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(roh, forType: .string) }
                self.zustand.melde(self.t.t("satz.sicherungKopiert", ["zeichen": String(roh.count)]), "gut")
            },
            knopf("sicherungEinsetzen", t.t("wort.einsetzen")) { _ in
                let roh = (self.zustand.eingaben["sicherungsfeld"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !roh.isEmpty else { self.zustand.melde(self.t.t("satz.sicherungKeinText"), "fehler"); return }
                guard let o = JSONWert.lesen(Data(roh.utf8)).objekt else { self.zustand.melde(self.t.t("satz.sicherungKeinJson"), "fehler"); return }
                let eintraege = o.sorted { $0.key < $1.key }
                self.zustand.frage(self.t.t("frage.einsetzen.text", ["anzahl": String(eintraege.count)]), tun: self.t.t("frage.einsetzen.tun")) { _, _ in
                    Task { @MainActor in
                        for (k, w) in eintraege { await self.zustand.setze(k, w) }
                        self.zustand.melde(self.t.t("satz.sicherungEingesetzt", ["anzahl": String(eintraege.count)]), "gut")
                    }
                }
            },
            knopf("sicherungAllesZurueck", t.t("wort.allesZurueck"), warnend: true) { _ in
                guard !liste.isEmpty else { self.zustand.melde(self.t.t("satz.keineAbweichung"), "gut"); return }
                self.zustand.frage(self.t.t("frage.allesZurueck.text", ["anzahl": String(liste.count)]), tun: self.t.t("frage.allesZurueck.tun")) { _, _ in
                    Task { @MainActor in for k in liste { if let v = self.d.vorgaben[k] { await self.zustand.setze(k, v) } } }
                }
            },
        ]))
        g2.felder.append(feld("sicherung", .stapel([sicherungsfeld, reihe]), breit: true))

        var g3 = Gruppe(id: "programm.dateien", titel: t.t("gruppe.programm.dateien"))
        var pfadZeilen: [TabellenZeile] = d.pfade.map { TabellenZeile(id: "pfad:\($0.label)", zellen: [.text($0.label), .text($0.wert, sekundaer: true)]) }
        pfadZeilen += d.protokolle.map { TabellenZeile(id: "protokoll:\($0.label)", zellen: [.text("Protokoll: \($0.label)"), .text($0.wert, sekundaer: true)]) }
        g3.felder.append(feld("pfade", .tabelle(kopf: [], zeilen: pfadZeilen, leer: ""), breit: true, id: "pfadTabelle"))

        // Der Knopf zum gefuehrten ersten Start: echt zeigt das Sheet des
        // Mantels, ein Skript-Klick baut es nur (Erststart.swift, 3.8).
        var g4 = Gruppe(id: "programm.erststart", titel: t.t("gruppe.programm.erststart"))
        g4.felder.append(feld("erststartZeigen", .knopf(titel: t.t("wort.erneutZeigen"), warnend: false, hervorgehoben: false, klick: { echt in
            self.zustand.erststartZeigen?(echt && !self.zustand.kopflos)
        })))
        return seite("programm", symbol: "archivebox", [g1, g2, g3, g4])
    }
}

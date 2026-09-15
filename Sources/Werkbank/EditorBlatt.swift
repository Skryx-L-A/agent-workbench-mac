// Das Editor-Blatt (Auftrag 3.4): der Baustein aus 3.3 im Hauptfenster, mit
// Dateibaum, Tabs, Speichern, Auswahl an einen Pane und einem Waechter ueber
// die offenen Dateien.
//
// AUFTEILUNG WIE IN DER ELECTRON-FASSUNG (`renderer/editor-view.ts`): die
// Tab-Zeile steht als eigener Streifen UEBER der Buehne (neben Freigabeleiste
// und Tab-Streifen im senkrechten Stapel), der Editor selbst liegt AN DER
// STELLE der Kacheln -- dieselbe Zweiteilung wie dort (`#ed-tabs` in `#mitte`,
// `#ed-host` ueber `#buehne`). Eingeklappt bleibt nur der Streifen stehen und
// die Buehne hat ihren Platz zurueck; das ist der ganze Sinn des Einklappens
// (der Nutzer, 05.09.: „soll nur Platz brauchen, wenn man ihn braucht").
//
// EIN EDITOR, MEHRERE TABS. Monaco haelt je Tab ein eigenes Modell; hier haelt
// der Tab seinen TEXT und seine Cursorstelle, und beim Wechsel wird beides in
// den einen `TextKitEditor` gelegt. Ein zweiter NSTextView je Tab waere ein
// zweiter TextKit-Baum und ein zweiter Faerber (76 MB je Baustein, gemessen in
// mac/PLAN-EDITOR.md) fuer etwas, das der Mensch nie gleichzeitig sieht.
//
// GELESEN UND GESCHRIEBEN WIRD IM KERN (`awb:editor-read-file`,
// `awb:editor-write-file`): dort sitzen die Ausschlussliste und die Pfadsperre
// (editor.ts `aufloesen`), und dort gilt sie fuer BEIDE Oberflaechen. Das
// Blatt liest keine Datei selbst.
import AppKit
import SwiftUI
import WerkbankProtokoll

/// Eine offene Datei im Blatt. `absolut` ist der schreibgeschuetzte Fall
/// (Ergebnisdatei ausserhalb des Projektordners, wie `openAbsoluteTab` in
/// editor-view.ts) -- er entsteht erst mit dem Pfad-Klick aus 3.6, die Art
/// steht schon hier, damit der Tab sie nicht spaeter nachtragen muss.
struct EditorTab: Identifiable, Equatable {
    enum Art: String { case datei, absolut }
    let art: Art
    /// Projektrelativer Pfad (`datei`) bzw. voller Pfad (`absolut`) -- innerhalb der Art eindeutig.
    let key: String
    let label: String
    let abs: String
    var text: String
    var zeile: Int
    var spalte: Int
    var geaendert: Bool
    var nurLesen: Bool
    /// Die Datei wurde auf der Platte geaendert, seit sie hier steht (Waechter im Kern).
    var aufPlatte: Bool

    var id: String { "\(art.rawValue):\(key)" }
}

@MainActor
@Observable
final class EditorBlattZustand {
    @ObservationIgnored let kern: KernVerbindung
    @ObservationIgnored let optionen: Laufoptionen

    private(set) var tabs: [EditorTab] = []
    /// -1: kein Dateitab gewaehlt (die Buehne steht).
    private(set) var aktiv = -1
    private(set) var eingeklappt = false
    /// Der Ordner, dessen Baum gezeigt wird -- der der gewaehlten Sitzung bzw. des Gespraechs.
    private(set) var wurzel = ""
    private(set) var dateien: [String] = []
    private(set) var baumFehler = ""
    /// Die von Hand aufgeklappten Ordner. Der Filter klappt daneben ALLES auf,
    /// ohne diese Wahl zu ueberschreiben -- wer das Suchfeld leert, sieht seinen
    /// Baum wieder so, wie er ihn gelassen hat.
    var offeneOrdner: Set<String> = []
    var filter = "" {
        didSet { if filter != oldValue { baumNeu() } }
    }
    private(set) var baum: [BaumKnoten] = []
    private(set) var notiz = ""
    @ObservationIgnored private(set) var notizBis = Date.distantPast
    /// Der Baustein, erst beim ersten Oeffnen gebaut (Highlightr laedt einen JSContext).
    private(set) var ansicht: EditorAnsicht?

    /// Die Rueckfrage vor dem Schliessen einer geaenderten Datei -- das Fenster
    /// stellt sie (NSAlert-Sheet; kopflos `AWB_RUECKFRAGE`, wie ueberall sonst).
    @ObservationIgnored var fragen: ((String, String, String) async -> Bool)?
    /// Das Fenster soll seine Ansichten neu ordnen (Editor, Kacheln, Leerzustand).
    @ObservationIgnored var beiWechsel: (() -> Void)?

    /// Was zuletzt an den Kern gemeldet wurde und noch nicht im Modell steht --
    /// ein Takt, der schon unterwegs war, traegt den alten Wert und darf die
    /// frische Wahl nicht zuruecknehmen (editor-view.ts, `eingeklapptGemeldet`).
    @ObservationIgnored private var klappGemeldet: Bool?
    @ObservationIgnored private var gemeldeteWacht: [String] = []
    @ObservationIgnored private var ladenLaeuft = false

    init(kern: KernVerbindung, optionen: Laufoptionen) {
        self.kern = kern
        self.optionen = optionen
    }

    // MARK: Zustand

    var aktiverTab: EditorTab? { tabs.indices.contains(aktiv) ? tabs[aktiv] : nil }

    /// Fuellt der Editor gerade die Mitte? Eingeklappt tut er es nicht.
    var offen: Bool { aktiv >= 0 && !eingeklappt }

    /// Steht die Tab-Zeile (offen oder als schmale Leiste)?
    var leisteDa: Bool { !tabs.isEmpty }

    var notizSichtbar: String { notizBis > Date() ? notiz : "" }

    func melden(_ text: String) {
        notiz = text
        notizBis = Date().addingTimeInterval(4)
    }

    // MARK: Der Baum

    /// Der Ordner der Sitzung auf der Buehne -- dieselbe Regel wie in
    /// editor-view.ts (`chat?.ordner || s?.dir`): liegt ein Gespraech, ist
    /// SEIN Ordner die Wurzel.
    func nachModell() {
        let m = kern.modell
        let chat = m.chatGezeigt.isEmpty ? nil : m.chats.first { $0.id == m.chatGezeigt }
        let neu = chat?.ordner ?? kern.gewaehlteSitzung?.dir ?? ""
        if neu != wurzel {
            wurzel = neu
            dateien = []
            baum = []
            offeneOrdner = []
            Task { await dateienLaden() }
        }
        // Der gemerkte Klappzustand aus ui.json.
        let gemerkt = m.ui.editorEingeklappt
        if let g = klappGemeldet {
            if gemerkt != g { return }
            klappGemeldet = nil
        }
        if gemerkt != eingeklappt {
            Task { await stelleMerken() }
            eingeklappt = gemerkt
            beiWechsel?()
        }
    }

    @discardableResult
    func dateienLaden() async -> Bool {
        guard !wurzel.isEmpty, !ladenLaeuft else { return false }
        ladenLaeuft = true
        defer { ladenLaeuft = false }
        let a = await kern.invoke("awb:editor-list-files", [wurzel])
        guard let (liste, fehler) = Self.dateiliste(a) else {
            baumFehler = a.fehler ?? "keine Antwort"
            return false
        }
        baumFehler = fehler
        dateien = liste
        baumNeu()
        return fehler.isEmpty
    }

    /// `{ ok, value: [{rel}] }` bzw. `{ ok:false, error }` -- das Format, das
    /// `awb:editor-list-files` fuer beide Oberflaechen liefert (main.ts).
    private static func dateiliste(_ a: KernAntwort) -> (liste: [String], fehler: String)? {
        guard a.ok, let w = a.wertJSON,
              let obj = try? JSONSerialization.jsonObject(with: w) as? [String: Any] else { return nil }
        if obj["ok"] as? Bool == false { return ([], obj["error"] as? String ?? "abgelehnt") }
        let wert = obj["value"] as? [[String: Any]] ?? []
        return (wert.compactMap { $0["rel"] as? String }, "")
    }

    private func baumNeu() {
        baum = Dateibaum.bauen(Dateibaum.filtern(dateien, filter))
    }

    /// Ein gefilterter Baum steht ganz offen, sonst waeren die Treffer hinter
    /// zugeklappten Ordnern nicht zu sehen; ohne Filter gilt die Wahl der Hand.
    private var sichtbarOffen: Set<String> {
        filter.trimmingCharacters(in: .whitespaces).isEmpty ? offeneOrdner : Dateibaum.alleOrdner(baum)
    }

    var zeilen: [BaumZeile] { Dateibaum.zeilen(baum, offen: sichtbarOffen) }

    func ordnerUmschalten(_ pfad: String) {
        if offeneOrdner.contains(pfad) { offeneOrdner.remove(pfad) } else { offeneOrdner.insert(pfad) }
    }

    // MARK: Oeffnen, wechseln, schliessen

    /// Eine Datei aus dem Baum. Wer oeffnet, will sehen: ein Oeffnen hebt das
    /// Einklappen auf, auch wenn der Tab schon offen ist (editor-view.ts).
    @discardableResult
    func oeffnen(_ rel: String, zeile: Int = 0, spalte: Int = 1) async -> Bool {
        guard !wurzel.isEmpty else { melden("Kein Ordner: erst eine Sitzung wählen."); return false }
        if eingeklappt { aufklappen() }
        if let i = tabs.firstIndex(where: { $0.art == .datei && $0.key == rel }) {
            await aktivieren(i)
            if zeile > 0 { await cursorSetzen(zeile: zeile, spalte: spalte) }
            return true
        }
        melden("„\(rel)“ wird geladen …")
        let a = await kern.invoke("awb:editor-read-file", [wurzel, rel])
        guard a.ok, let w = a.wertJSON,
              let obj = try? JSONSerialization.jsonObject(with: w) as? [String: Any] else {
            melden(a.fehler ?? "Die Datei ließ sich nicht lesen.")
            return false
        }
        if obj["ok"] as? Bool == false {
            melden(obj["error"] as? String ?? "Die Datei ließ sich nicht lesen.")
            return false
        }
        guard let wert = obj["value"] as? [String: Any], let inhalt = wert["content"] as? String else {
            melden("Die Antwort trug keinen Inhalt.")
            return false
        }
        await stelleMerken()
        tabs.append(EditorTab(art: .datei, key: rel, label: Self.basisname(rel), abs: wert["abs"] as? String ?? "",
                              text: inhalt, zeile: max(1, zeile), spalte: max(1, spalte),
                              geaendert: false, nurLesen: false, aufPlatte: false))
        aktiv = tabs.count - 1
        await zeigen()
        if zeile > 0 { await cursorSetzen(zeile: zeile, spalte: spalte) }
        wachtMelden()
        melden("„\(rel)“ geöffnet.")
        beiWechsel?()
        return true
    }

    /// Ein Tab mit fertigem Inhalt, der NICHT aus dem Projektordner kommt --
    /// eine Ergebnisdatei, ein Protokoll, ein Unterschied, ein Pfad aus dem
    /// Gespraech (`openAbsoluteTab` in editor-view.ts). Gelesen hat den Inhalt
    /// der Kern; hier wird er nur gezeigt, schreibgeschuetzt.
    ///
    /// `key` unterscheidet die Sorten: der Pfad allein fuer eine Datei,
    /// `diff:<pfad>` und `auftrag:<pfad>` fuer die zweiten Klicks der
    /// Aktivitaet -- so steht der Unterschied neben der Datei, statt sie zu
    /// ersetzen (dieselben Kennungen wie in aktivitaet-view.ts).
    @discardableResult
    func oeffnenAbsolut(key: String, label: String, abs: String, text: String,
                        zeile: Int = 0, spalte: Int = 1) async -> Bool {
        if eingeklappt { aufklappen() }
        if let i = tabs.firstIndex(where: { $0.art == .absolut && $0.key == key }) {
            await stelleMerken()
            tabs[i].text = text
            aktiv = i
            await zeigen()
            if zeile > 0 { await cursorSetzen(zeile: zeile, spalte: spalte) }
            beiWechsel?()
            return true
        }
        await stelleMerken()
        tabs.append(EditorTab(art: .absolut, key: key, label: label, abs: abs, text: text,
                              zeile: max(1, zeile), spalte: max(1, spalte),
                              geaendert: false, nurLesen: true, aufPlatte: false))
        aktiv = tabs.count - 1
        await zeigen()
        if zeile > 0 { await cursorSetzen(zeile: zeile, spalte: spalte) }
        melden("„\(label)“ geöffnet.")
        beiWechsel?()
        return true
    }

    func aktivieren(_ index: Int) async {
        guard index >= -1, index < tabs.count else { return }
        await stelleMerken()
        aktiv = index
        if index >= 0 { await zeigen() }
        beiWechsel?()
    }

    /// Den Tab schliessen; eine ungesicherte Aenderung fragt vorher nach.
    @discardableResult
    func schliessen(_ index: Int) async -> Bool {
        guard tabs.indices.contains(index) else { return false }
        await stelleMerken()
        let t = tabs[index]
        if t.geaendert {
            let ja = await fragen?("„\(t.label)“ schließen?",
                                   "Die Änderungen an \(t.key) sind nicht gesichert und gehen verloren.",
                                   "Schließen") ?? false
            guard ja else { return false }
        }
        tabs.remove(at: index)
        if aktiv == index {
            aktiv = tabs.isEmpty ? -1 : min(index, tabs.count - 1)
            if aktiv >= 0 { await zeigen() }
        } else if aktiv > index {
            aktiv -= 1
        }
        wachtMelden()
        beiWechsel?()
        return true
    }

    // MARK: Speichern und der Waechter

    @discardableResult
    func speichern() async -> Bool {
        guard let t = aktiverTab else { melden("Kein Dateitab gewählt."); return false }
        guard t.art == .datei, !t.nurLesen else { melden("„\(t.label)“ ist schreibgeschützt."); return false }
        await stelleMerken()
        let inhalt = tabs[aktiv].text
        let a = await kern.invoke("awb:editor-write-file", [wurzel, t.key, inhalt])
        guard a.ok, let w = a.wertJSON,
              let obj = try? JSONSerialization.jsonObject(with: w) as? [String: Any] else {
            melden(a.fehler ?? "Nicht gespeichert.")
            return false
        }
        if obj["ok"] as? Bool == false {
            melden("Nicht gespeichert: \(obj["error"] as? String ?? "abgelehnt")")
            return false
        }
        tabs[aktiv].geaendert = false
        // Der eigene Schreibvorgang loest den Waechter aus -- das ist keine
        // fremde Aenderung, also wird die Marke gleich wieder abgeraeumt.
        tabs[aktiv].aufPlatte = false
        melden("„\(t.key)“ gespeichert.")
        return true
    }

    /// Der Kern meldet eine Aenderung auf der Platte (`awb:datei-geaendert`,
    /// `name: editor`). Neu geladen wird NICHT von selbst: in einer geaenderten
    /// Datei stuende sonst die Arbeit des Menschen nicht mehr da.
    func aufPlatteGeaendert(_ abs: String) {
        guard let i = tabs.firstIndex(where: { $0.abs == abs }) else { return }
        guard !tabs[i].aufPlatte else { return }
        tabs[i].aufPlatte = true
        melden("„\(tabs[i].label)“ wurde auf der Platte geändert.")
    }

    /// Die Datei erneut aus dem Kern lesen und die Marke abraeumen.
    @discardableResult
    func neuLaden() async -> Bool {
        guard let t = aktiverTab, t.art == .datei else { melden("Kein Dateitab gewählt."); return false }
        let a = await kern.invoke("awb:editor-read-file", [wurzel, t.key])
        guard a.ok, let w = a.wertJSON,
              let obj = try? JSONSerialization.jsonObject(with: w) as? [String: Any],
              let wert = obj["value"] as? [String: Any], let inhalt = wert["content"] as? String else {
            melden(a.fehler ?? "Die Datei ließ sich nicht neu laden.")
            return false
        }
        tabs[aktiv].text = inhalt
        tabs[aktiv].geaendert = false
        tabs[aktiv].aufPlatte = false
        tabs[aktiv].zeile = 1
        tabs[aktiv].spalte = 1
        await zeigen()
        melden("„\(t.key)“ neu geladen.")
        return true
    }

    /// Welche Dateien der Kern beobachten soll -- die vollstaendige Liste, bei
    /// jeder Aenderung. Zweimal dieselbe Liste schickt nichts.
    private func wachtMelden() {
        let liste = tabs.filter { $0.art == .datei }.map(\.key).sorted()
        guard liste != gemeldeteWacht else { return }
        gemeldeteWacht = liste
        kern.send("awb:editor-watch", [wurzel, liste])
    }

    // MARK: Einklappen

    func einklappen() {
        guard !eingeklappt, aktiv >= 0 else { return }
        Task { await stelleMerken() }
        eingeklappt = true
        klappMelden(true)
        beiWechsel?()
    }

    func aufklappen() {
        guard eingeklappt else { return }
        eingeklappt = false
        klappMelden(false)
        beiWechsel?()
        Task { await stelleWiederherstellen() }
    }

    func klappUmschalten() {
        if eingeklappt { aufklappen() } else { einklappen() }
    }

    private func klappMelden(_ wert: Bool) {
        klappGemeldet = wert
        kern.bedienung("editor-eingeklappt", wert)
    }

    // MARK: Der Baustein

    /// Den Baustein bauen (erst jetzt: Highlightr laedt einen JSContext) und
    /// den Text des gewaehlten Tabs hineinlegen.
    @discardableResult
    func bausteinBauen() -> EditorAnsicht {
        if let a = ansicht { return a }
        let a = EditorAnsicht(fassung: MacSteuerkanal.editorVorgabe, optionen: optionen)
        (a.baustein as? TextKitEditor)?.beiAenderung = { [weak self] in self?.getippt() }
        ansicht = a
        return a
    }

    private func getippt() {
        guard tabs.indices.contains(aktiv), !tabs[aktiv].geaendert else { return }
        tabs[aktiv].geaendert = true
    }

    /// Den gewaehlten Tab in den Baustein legen (Text, Sprache, Cursorstelle).
    private func zeigen() async {
        guard let t = aktiverTab else { return }
        let a = bausteinBauen()
        await a.zeigen(text: t.text, pfad: t.abs.isEmpty ? t.key : t.abs)
        await a.baustein.cursorSetzen(zeile: max(1, t.zeile), spalte: max(1, t.spalte))
    }

    /// Text und Cursorstelle des sichtbaren Editors am Tab merken, bevor er verschwindet.
    func stelleMerken() async {
        guard tabs.indices.contains(aktiv), let a = ansicht else { return }
        let c = await a.baustein.cursor()
        tabs[aktiv].zeile = c.zeile
        tabs[aktiv].spalte = c.spalte
        tabs[aktiv].text = await a.baustein.textLesen()
    }

    /// Nach dem Aufklappen dieselbe Stelle wieder herstellen.
    private func stelleWiederherstellen() async {
        guard let t = aktiverTab, let a = ansicht else { return }
        await a.baustein.cursorSetzen(zeile: max(1, t.zeile), spalte: max(1, t.spalte))
    }

    func cursorSetzen(zeile: Int, spalte: Int) async {
        guard tabs.indices.contains(aktiv) else { return }
        let a = bausteinBauen()
        await a.baustein.cursorSetzen(zeile: zeile, spalte: spalte)
        let c = await a.baustein.cursor()
        tabs[aktiv].zeile = c.zeile
        tabs[aktiv].spalte = c.spalte
    }

    /// Den Text des gewaehlten Tabs ersetzen -- der Weg einer Pruefung dorthin,
    /// wo sonst die Tastatur des Menschen steht (editor-view.ts `setValue`).
    @discardableResult
    func textSetzen(_ text: String) async -> Bool {
        guard let t = aktiverTab else { return false }
        let a = bausteinBauen()
        await a.zeigen(text: text, pfad: t.abs.isEmpty ? t.key : t.abs)
        tabs[aktiv].text = text
        tabs[aktiv].geaendert = true
        return true
    }

    func auswahlSetzen(von: Int, bis: Int) async -> Bool {
        guard aktiverTab != nil, let a = ansicht else { return false }
        await a.baustein.auswahlSetzen(von: von, bis: bis)
        return true
    }

    // MARK: Die Auswahl an einen Pane

    /// Der eine Befehl, der den Editor rechtfertigt (4c): die markierte Stelle,
    /// mit Datei und Zeilennummern, landet im Eingabefeld eines Panes.
    ///
    /// DER STEUERKANAL SCHREIBT NICHT IN EINEN ORCHESTRATOR-PANE (2026-08-06,
    /// dieselbe Grenze wie `editor sendSelection` in main.ts): der Knopf im
    /// Fenster ist der Mensch und darf; ein Aufruf ohne Menschen (kopflos, ueber
    /// `awbmac-ctl`) darf nur an einen Worker-Pane.
    func auswahlSenden(pane: String = "", echt: Bool) async -> (ok: Bool, meldung: String, pane: String, text: String) {
        guard let t = aktiverTab, let a = ansicht else {
            melden("Kein Dateitab gewählt.")
            return (false, "kein Dateitab gewaehlt", "", "")
        }
        let auswahl = await a.baustein.auswahl()
        guard !auswahl.text.isEmpty else {
            melden("Nichts markiert.")
            return (false, "nichts markiert", "", "")
        }
        let orchestrator = kern.gewaehlteSitzung?.orchestratorPane ?? ""
        let ziel = pane.isEmpty ? orchestrator : pane
        guard !ziel.isEmpty else {
            melden("Kein Orchestrator-Pane in dieser Sitzung.")
            return (false, "kein Orchestrator-Pane", "", "")
        }
        if !echt, ziel == orchestrator {
            let grund = "abgelehnt: der Steuerkanal tippt nicht in den Orchestrator-Pane. "
                + "Diesen Weg geht nur ein Mensch im Fenster (Menü „Ablage“ oder ⌘⇧↩)."
            melden("Abgelehnt: der Steuerkanal schreibt nicht in den Orchestrator-Pane.")
            return (false, grund, ziel, "")
        }
        let zeilen = auswahl.von == auswahl.bis ? "\(auswahl.von)" : "\(auswahl.von)-\(auswahl.bis)"
        let anzeige = t.art == .datei ? t.key : t.abs
        let nachricht = "\(anzeige):\(zeilen)\n\(auswahl.text)"
        let antwort = await kern.invoke("awb:editor-send-selection", [ziel, nachricht])
        guard antwort.ok, let w = antwort.wertJSON,
              let obj = try? JSONSerialization.jsonObject(with: w) as? [String: Any] else {
            let grund = antwort.fehler ?? "keine Antwort"
            melden("Nicht gesendet: \(grund)")
            return (false, grund, ziel, nachricht)
        }
        if obj["ok"] as? Bool == false {
            let grund = obj["error"] as? String ?? "abgelehnt"
            melden("Nicht gesendet: \(grund)")
            return (false, grund, ziel, nachricht)
        }
        melden("Auswahl gesendet.")
        return (true, "", ziel, nachricht)
    }

    // MARK: Auskunft fuer `awbmac-ctl ui`

    func auskunft() async -> [String: Any] {
        var cursor: [String: Any] = ["zeile": 0, "spalte": 0]
        if let a = ansicht, aktiv >= 0 {
            let c = await a.baustein.cursor()
            cursor = ["zeile": c.zeile, "spalte": c.spalte]
        }
        return [
            "gebaut": ansicht != nil,
            "offen": offen,
            "eingeklappt": eingeklappt,
            "leisteDa": leisteDa,
            "leiste": aktiverTab.map { ($0.geaendert ? "● " : "") + $0.label } ?? "",
            "aktiv": aktiv,
            "wurzel": wurzel,
            "orchestratorPane": kern.gewaehlteSitzung?.orchestratorPane ?? "",
            "tabs": tabs.map { ["key": $0.key, "art": $0.art.rawValue, "label": $0.label, "abs": $0.abs,
                                "geaendert": $0.geaendert, "aufPlatte": $0.aufPlatte, "nurLesen": $0.nurLesen] },
            "aktiverPfad": aktiverTab?.abs ?? "",
            "cursor": cursor,
            "notiz": notizSichtbar,
            "baum": ["wurzel": wurzel, "dateien": dateien.count, "filter": filter, "fehler": baumFehler,
                     "zeilen": zeilen.map { ["pfad": $0.pfad, "name": $0.name, "ordner": $0.ordner, "tiefe": $0.tiefe, "offen": $0.offen] },
                     "namen": zeilen.map(\.name)],
            "beobachtet": gemeldeteWacht,
        ]
    }

    static func basisname(_ pfad: String) -> String {
        pfad.split(separator: "/").last.map(String.init) ?? pfad
    }
}

// MARK: - Die Tab-Zeile

/// Die Tab-Zeile ueber der Buehne: „Terminal“, je Datei ein Tab mit
/// Aenderungspunkt und Schliessen-Kreuz, rechts der Winkel zum Einklappen.
/// Eingeklappt steht an ihrer Stelle die schmale Leiste (Winkel, Name, Punkt).
struct EditorTabLeiste: View {
    @Bindable var zustand: EditorBlattZustand
    /// Im Beleg zeichnen Buttons nichts (mac/PLAN.md, Auftrag 2.4) -- dann steht
    /// derselbe Wortlaut als Text.
    var beleg = false

    var body: some View {
        HStack(spacing: 6) {
            if zustand.eingeklappt, let t = zustand.aktiverTab {
                zuLeiste(t)
            } else {
                offeneLeiste
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        // Ueber die ganze Breite: ohne diesen Rahmen bleibt der NSHostingView
        // bei seiner Eigenbreite stehen und der Streifen klebt rechts (gemessen
        // am Belegbild, 06.09.).
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editor-Tabs")
        .accessibilityIdentifier("editor-tabs")
    }

    @ViewBuilder
    private func zuLeiste(_ t: EditorTab) -> some View {
        let text = (t.geaendert ? "● " : "") + t.label
        if beleg {
            Label(text, systemImage: "chevron.up")
                .labelStyle(.titleAndIcon)
                .font(.callout)
        } else {
            Button {
                zustand.aufklappen()
            } label: {
                Label(text, systemImage: "chevron.up")
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .help("Editor aufklappen")
            .accessibilityLabel("Editor aufklappen, \(t.label)\(t.geaendert ? ", ungesichert" : "")")
        }
        Spacer()
    }

    @ViewBuilder
    private var offeneLeiste: some View {
        marke(titel: "Terminal", gewaehlt: zustand.aktiv == -1, geaendert: false, index: -1)
        ForEach(Array(zustand.tabs.enumerated()), id: \.element.id) { i, t in
            marke(titel: t.label, gewaehlt: i == zustand.aktiv, geaendert: t.geaendert, index: i)
        }
        Spacer()
        if !zustand.notizSichtbar.isEmpty {
            Text(zustand.notizSichtbar)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        if zustand.aktiv >= 0 {
            if beleg {
                Image(systemName: "chevron.down")
            } else {
                Button { zustand.einklappen() } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.plain)
                    .help("Editor einklappen")
                    .accessibilityLabel("Editor einklappen")
            }
        }
    }

    @ViewBuilder
    private func marke(titel: String, gewaehlt: Bool, geaendert: Bool, index: Int) -> some View {
        let text = (geaendert ? "● " : "") + titel
        if beleg {
            Text(text)
                .fontWeight(gewaehlt ? .semibold : .regular)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        } else {
            HStack(spacing: 4) {
                Button {
                    Task { await zustand.aktivieren(index) }
                } label: {
                    Text(text).fontWeight(gewaehlt ? .semibold : .regular)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(gewaehlt ? [.isSelected] : [])
                if index >= 0 {
                    Button {
                        Task { await zustand.schliessen(index) }
                    } label: {
                        Image(systemName: "xmark").font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .help("Tab schließen")
                    .accessibilityLabel("\(titel) schließen")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(gewaehlt ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.clear), in: Capsule())
        }
    }
}

// MARK: - Der Koerper: Baum links, Editor rechts

/// Der Editor an der Stelle der Kacheln: der Dateibaum als schmale Spalte, der
/// Baustein daneben. Ein NSSplitView waere die dritte Teilung in diesem Fenster
/// (Seitenleiste, Inspektor) -- der Baum bekommt deshalb eine feste Spalte mit
/// Trennstrich, wie die Dateiliste in Xcodes Versionseditor.
@MainActor
final class EditorBlatt: NSView {
    static let baumBreite: CGFloat = 240
    let zustand: EditorBlattZustand
    private let baumHost: NSHostingView<DateibaumAnsicht>

    init(zustand: EditorBlattZustand) {
        self.zustand = zustand
        baumHost = NSHostingView(rootView: DateibaumAnsicht(zustand: zustand))
        super.init(frame: .zero)
        let ansicht = zustand.bausteinBauen()
        let trenner = NSBox()
        trenner.boxType = .separator
        for v in [baumHost, trenner, ansicht] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            baumHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            baumHost.topAnchor.constraint(equalTo: topAnchor),
            baumHost.bottomAnchor.constraint(equalTo: bottomAnchor),
            baumHost.widthAnchor.constraint(equalToConstant: Self.baumBreite),
            trenner.leadingAnchor.constraint(equalTo: baumHost.trailingAnchor),
            trenner.topAnchor.constraint(equalTo: topAnchor),
            trenner.bottomAnchor.constraint(equalTo: bottomAnchor),
            trenner.widthAnchor.constraint(equalToConstant: 1),
            ansicht.leadingAnchor.constraint(equalTo: trenner.trailingAnchor),
            ansicht.trailingAnchor.constraint(equalTo: trailingAnchor),
            ansicht.topAnchor.constraint(equalTo: topAnchor),
            ansicht.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    /// Die Flaeche der Baumspalte im Fenster -- fuer das Belegbild.
    var baumRahmen: NSRect { baumHost.convert(baumHost.bounds, to: nil) }
}

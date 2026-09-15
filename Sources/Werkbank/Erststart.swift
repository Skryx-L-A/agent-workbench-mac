// Der gefuehrte erste Start (Auftrag 3.8) als SHEET am Hauptfenster.
//
// WARUM EIN SHEET UND KEIN EIGENES FENSTER. Die Electron-Fassung braucht ein
// zweites Fenster, weil sie kein Sheet kennt (erststartfenster.ts). Auf dem Mac
// ist das Sheet genau die Form fuer diesen Fall: eine kurze, einmalige Aufgabe,
// die zu EINEM bestimmten Fenster gehoert und dessen Einstellungen setzt, mit
// klarem Anfang und Ende. Ein eigenes Fenster waere ein Gegenstand, den man
// verschieben, verstecken und liegenlassen kann -- und der erste Start ist
// nichts, was man liegenlaesst; er ist der Weg in dieses Fenster hinein. Die
// Verbrauchsseite (dieselbe Auftragszeile) entscheidet umgekehrt und aus dem
// gegenteiligen Grund: sie ist ein Bericht, den man nebenherliegen hat.
//
// DIE AUFLAGE AUS DIESEM HAUS, wie bei Einstellungs- und Sitzungsfenster:
// `bauen()` baut und liest, OHNE zu zeigen (der Weg des Steuerkanals,
// `awbmac-ctl erststart`); `zeigen()` ist der einzige Weg auf den Bildschirm
// und kopflos wirkungslos. Von selbst geht es nur beim ersten SICHTBAREN Start
// auf, und nur solange `erledigt` false ist -- dieselbe Bedingung wie im Kern.
//
// Die Regel -- welcher Schritt kommt, was ein Ueberspringen bedeutet, dass die
// Einstellungen genau einmal geschrieben werden -- liegt in
// `WerkbankProtokoll/Erststart.swift` unter `swift test`. Hier steht nur der
// Zustand und das Zeichnen.
//
// Textstile, Systemfarben, Systemakzent; keine festen Punktgroessen fuer Text,
// keine fest verdrahteten Farben, keine Emojis.
import AppKit
import SwiftUI
import WerkbankProtokoll

@MainActor
@Observable
final class ErststartZustand {
    let kern: KernVerbindung
    /// Kopflos: nie zeigen, nie schliessen -- der Zustand bleibt lesbar.
    let kopflos: Bool

    private(set) var daten: ErststartDaten?
    private(set) var texte = Texte()
    private(set) var ablauf = ErststartAblauf()
    /// Die Wahl des laufenden Schritts (erststart.ts `laufendeWahl`).
    private(set) var wahl = ""
    /// Was der Kern zuletzt zu einer Schreibung gesagt hat -- die Fusszeile.
    private(set) var status = ""
    /// Die Kontextstufen je Modell, wie sie das Einstellungsfenster holt.
    private(set) var kontextStand: [String: KontextAntwort] = [:]
    private var kontextLaeuft: Set<String> = []
    /// Bis das erste Zeichnen dem Kern gemeldet wurde (`awb:erststart-bereit`).
    private var bereitGemeldet = false
    /// Wird gerade geschrieben? Solange sperren die Knoepfe.
    private(set) var beschaeftigt = false

    init(kern: KernVerbindung, kopflos: Bool) {
        self.kern = kern
        self.kopflos = kopflos
    }

    var schritt: ErststartSchritt { ablauf.schritt }
    var abgeschlossen: Bool { ablauf.abgeschlossen }

    /// Daten und Texte holen; danach steht die Vorbelegung des ersten Schritts.
    func laden() async {
        let t = await kern.invoke("awb:erststart-texte")
        if let w = t.wertJSON { texte = Texte(json: JSONWert.lesen(w)) }
        let d = await kern.invoke("awb:erststart-daten")
        if let w = d.wertJSON { daten = ErststartDaten(json: JSONWert.lesen(w)) }
        wahlHerstellen()
        if !bereitGemeldet {
            bereitGemeldet = true
            kern.send("awb:erststart-bereit", [])
        }
    }

    /// Die Vorbelegung des laufenden Schritts -- auch sie ist eine Wahl
    /// (erststart.ts: der Kontextblock steht, bevor jemand geklickt hat).
    private func wahlHerstellen() {
        guard let d = daten else { wahl = ""; return }
        switch ablauf.schritt {
        case .maschine:
            let moeglich = ["local"] + d.maschinen
            let vor = d.vorbelegung("defaultWorkerMachine")
            wahl = moeglich.contains(vor) ? vor : "local"
        case .harness:
            let vor = d.vorbelegung("orchestratorHarness")
            wahl = d.harnesses.contains { $0.id == vor } ? vor : (d.harnesses.first?.id ?? "")
        case .modell:
            let ms = d.modelle(fuer: gewaehlterHarness)
            let vor = d.vorbelegung("orchestratorModel")
            wahl = ms.contains { $0.id == vor } ? vor : (ms.first?.id ?? "")
            kontextNachziehen()
        case .fertig:
            wahl = ""
        }
    }

    /// Das Programm, dessen Modelle der dritte Schritt zeigt: die eigene Antwort,
    /// sonst das Gesetzte, sonst die Vorgabe.
    var gewaehlterHarness: String {
        if case .text(let h)? = ablauf.antworten[.harness], !h.isEmpty { return h }
        return daten?.vorbelegung("orchestratorHarness") ?? ""
    }

    func waehlen(_ wert: String) {
        wahl = wert
        if ablauf.schritt == .modell { kontextNachziehen() }
    }

    var kontextWert: Int {
        if case .zahl(let n)? = ablauf.antworten[.kontext] { return n }
        return 0
    }

    func kontextWaehlen(_ tokens: Int) { ablauf.mitKontext(tokens) }

    /// Der Kontextblock unter der Modellwahl: nur bei einem oertlichen Modell,
    /// und die Stufen kommen erst auf Nachfrage (`awb:kontext-stufen`).
    var kontextModell: ErststartModell? {
        guard ablauf.schritt == .modell, let d = daten else { return nil }
        return d.modelle(fuer: gewaehlterHarness).first { $0.id == wahl && $0.lokal }
    }

    private func kontextNachziehen() {
        guard let m = kontextModell else {
            // Kein oertliches Modell: eine frueher gegebene Antwort geht wieder
            // weg, sonst schriebe der Abschluss eine Zahl fuer ein Modell ohne
            // waehlbares Fenster.
            ablauf.mitKontext(0)
            return
        }
        if case .sicht(let s)? = kontextStand[m.id] {
            let passt = s.stufen.contains { $0.tokens == kontextWert }
            ablauf.mitKontext(passt ? kontextWert : s.vorgabe)
            return
        }
        if kontextStand[m.id] != nil { ablauf.mitKontext(0); return }
        guard !kontextLaeuft.contains(m.id) else { return }
        kontextLaeuft.insert(m.id)
        let id = m.id
        Task { @MainActor in
            let a = await kern.invoke("awb:kontext-stufen", [id])
            kontextStand[id] = KontextAntwort.lesen(a.wertJSON)
            kontextLaeuft.remove(id)
            if wahl == id { kontextNachziehen() }
        }
    }

    /// Weiter mit der Wahl des Schritts; auf `fertig` schliesst das ab.
    func weiter() { schreiben(ablauf.weiter(wahl)) }

    /// Ueberspringen: die bestehende Vorgabe bleibt stehen.
    func ueberspringen() { schreiben(ablauf.ueberspringen()) }

    private func schreiben(_ schreibungen: [ErststartSchreibung]) {
        wahlHerstellen()
        guard !schreibungen.isEmpty else { return }
        beschaeftigt = true
        Task { @MainActor in
            var letzte = ""
            for s in schreibungen {
                let a = await kern.invoke("awb:erststart-setzen", [s.schluessel, s.wert.alsArgument])
                guard let w = a.wertJSON else { letzte = a.fehler ?? "keine Antwort"; continue }
                let j = JSONWert.lesen(w)
                if j["ok"].bool != true { letzte = j["ausgabe"].text ?? "abgelehnt" }
            }
            status = letzte
            beschaeftigt = false
            abgeschlossenMelden?()
        }
    }

    /// Das Blatt geht zu, sobald der Abschluss geschrieben ist (Fenster.swift).
    var abgeschlossenMelden: (() -> Void)?

    /// Der Satz des letzten Schritts (`fertig.satz.*`).
    var abschlussSatz: String {
        let namen: [ErststartAntwort: String] = [
            .maschine: "fertig.eintrag.maschine", .harness: "fertig.eintrag.harness",
            .modell: "fertig.eintrag.modell", .kontext: "fertig.eintrag.kontext",
        ]
        let teile = ablauf.eintraege.compactMap { (a, w) in
            namen[a].map { texte.t($0, ["0": w.alsText]) }
        }
        return teile.isEmpty ? texte.t("fertig.satz.nichtsGesetzt")
                             : texte.t("fertig.satz.gesetzt", ["0": teile.joined(separator: ", ")])
    }

    var fortschrittText: String {
        let i = ErststartSchritt.allCases.firstIndex(of: schritt) ?? 0
        return texte.t("fortschritt.schritt", ["0": String(i + 1), "1": String(ErststartSchritt.allCases.count)])
    }

    /// Das Zeichen zum Anmeldestand eines Harness (`harness.zeichen.*`).
    func anmeldeZeichen(_ id: String) -> (zeichen: String, stand: String) {
        let stand = daten?.anmeldung[id]?.stand ?? "unbekannt"
        return (texte.t("harness.zeichen.\(stand)"), texte.t("harness.stand.\(stand)"))
    }

    // MARK: Steuerkanal

    /// Ein Bedienelement ausloesen, wie ein Klick. `weiter`, `ueberspringen`,
    /// `wahl:<wert>`, `kontext:<tokens>`.
    func klick(_ knopf: String) -> Bool {
        if knopf == "weiter" { weiter(); return true }
        if knopf == "ueberspringen" { ueberspringen(); return true }
        if knopf.hasPrefix("wahl:") { waehlen(String(knopf.dropFirst(5))); return true }
        if knopf.hasPrefix("kontext:") { kontextWaehlen(Int(knopf.dropFirst(8)) ?? 0); return true }
        return false
    }

    /// Warten, bis nichts mehr beim Kern liegt -- die Schreibungen des
    /// Abschlusses UND die Frage nach den Kontextstufen. Ohne die zweite Haelfte
    /// laese eine Pruefung die Stufen, bevor `wb-kontext` geantwortet hat
    /// (gemessen 06.09.: `kontextStufen` war leer, eine Sekunde spaeter voll).
    func handlungAbwarten() async {
        for _ in 0..<400 where beschaeftigt || !kontextLaeuft.isEmpty {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    func auskunft() -> [String: Any] {
        let d = daten
        return [
            "gebaut": true,
            "geladen": d != nil,
            "erledigt": d?.erledigt ?? false,
            "schritt": schritt.rawValue,
            "index": ErststartSchritt.allCases.firstIndex(of: schritt) ?? 0,
            "fortschritt": fortschrittText,
            "abgeschlossen": abgeschlossen,
            "wahl": wahl,
            "auswahl": auswahlEintraege.map { ["wert": $0.wert, "label": $0.label, "zeichen": $0.zeichen] },
            "kontextModell": kontextModell?.id ?? "",
            "kontextWert": kontextWert,
            "kontextStufen": kontextStufen.map { ["tokens": $0.tokens, "label": $0.label, "passt": $0.passt] },
            "antworten": Dictionary(uniqueKeysWithValues: ablauf.eintraege.map { ($0.0.rawValue, $0.1.alsText) }),
            "titel": texte.t("\(schritt.rawValue).titel"),
            "unterzeile": texte.t("\(schritt.rawValue).unterzeile"),
            "hinweis": hinweis,
            "abschluss": schritt == .fertig ? abschlussSatz : "",
            "knopfWeiter": texte.t(schritt == .fertig ? "knopf.fertig" : "knopf.weiter"),
            "knopfUeberspringen": texte.t("knopf.ueberspringen"),
            "status": status,
            "sprache": texte.sprache,
        ]
    }

    /// Die Chips des laufenden Schritts -- dieselbe Liste, die das Blatt zeichnet.
    var auswahlEintraege: [(wert: String, label: String, zeichen: String)] {
        guard let d = daten else { return [] }
        switch schritt {
        case .maschine:
            guard !d.maschinen.isEmpty else { return [] }
            return (["local"] + d.maschinen).map {
                ($0, $0 == "local" ? texte.t("maschine.diese", ["0": d.machine]) : $0, "")
            }
        case .harness:
            return d.harnesses.map { ($0.id, $0.label, anmeldeZeichen($0.id).zeichen) }
        case .modell:
            return d.modelle(fuer: gewaehlterHarness).map { ($0.id, $0.label, "") }
        case .fertig:
            return []
        }
    }

    var kontextStufen: [KontextStufe] {
        guard let m = kontextModell, case .sicht(let s)? = kontextStand[m.id] else { return [] }
        return s.stufen
    }

    /// Der Hinweis, wenn ein Schritt nichts zu waehlen hat.
    var hinweis: String {
        guard let d = daten else { return "" }
        switch schritt {
        case .maschine: return d.maschinen.isEmpty ? texte.t("maschine.nurEine", ["0": d.machine]) : ""
        case .harness: return d.harnesses.isEmpty ? texte.t("harness.keine") : ""
        case .modell: return d.modelle(fuer: gewaehlterHarness).isEmpty ? texte.t("modell.keine") : ""
        case .fertig: return texte.t("fertig.satz.aendernWo")
        }
    }

    /// Der Grund zum gewaehlten Harness, den wb-state mitliefert (Messergebnis,
    /// keine Beschriftung -- er wird nicht uebersetzt).
    var anmeldeGrund: String {
        guard schritt == .harness else { return "" }
        return daten?.anmeldung[wahl]?.grund ?? ""
    }
}

// MARK: Das Blatt

struct ErststartBlatt: View {
    @Bindable var zustand: ErststartZustand
    /// Beleg-Modus: ohne AppKit-Steuerelemente, damit das Bild etwas zeigt.
    var beleg = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(zustand.texte.t("kopf.titel")).font(.title2).bold()
                Text(zustand.texte.t("kopf.unterzeile")).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text(zustand.fortschrittText).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("erststart-fortschritt")
                Text(zustand.texte.t("\(zustand.schritt.rawValue).titel")).font(.headline)
                Text(zustand.texte.t("\(zustand.schritt.rawValue).unterzeile")).font(.callout)
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !zustand.hinweis.isEmpty && zustand.schritt != .fertig {
                    Text(zustand.hinweis).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if zustand.schritt == .fertig {
                    Text(zustand.abschlussSatz).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Text(zustand.hinweis).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    chips
                    if !zustand.anmeldeGrund.isEmpty {
                        Text(zustand.anmeldeGrund).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    kontextblock
                }
            }
            Spacer(minLength: 4)
            Divider()
            fuss
        }
        .padding(20)
        .frame(width: 620, alignment: .leading)
        .accessibilityIdentifier("erststart")
    }

    /// Die Wahl als Reihe von Chips -- ein Wort und, beim Harness, ein Zeichen
    /// fuer den Anmeldestand (nie Farbe allein, abnahme.md Merkmal 5).
    @ViewBuilder private var chips: some View {
        let eintraege = zustand.auswahlEintraege
        if !eintraege.isEmpty {
            WrapReihe(eintraege.map(\.wert)) { wert in
                let e = eintraege.first { $0.wert == wert }
                let gewaehlt = wert == zustand.wahl
                let inhalt = HStack(spacing: 5) {
                    if let z = e?.zeichen, !z.isEmpty { Text(z).font(.caption) }
                    Text(e?.label ?? wert).font(.callout)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(gewaehlt ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)))
                .foregroundStyle(gewaehlt ? Color.white : Color.primary)
                if beleg {
                    inhalt
                } else {
                    Button { zustand.waehlen(wert) } label: { inhalt }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("wahl:\(wert)")
                        .accessibilityLabel("\(e?.label ?? wert)\(gewaehlt ? ", gewählt" : "")")
                }
            }
        }
    }

    @ViewBuilder private var kontextblock: some View {
        if zustand.kontextModell != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text(zustand.texte.t("kontext.titel")).font(.subheadline).bold()
                Text(zustand.texte.t("kontext.unterzeile")).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                let stufen = zustand.kontextStufen
                if stufen.isEmpty {
                    Text(zustand.texte.t("kontext.wirdErmittelt")).font(.caption).foregroundStyle(.secondary)
                } else {
                    WrapReihe(stufen.map { String($0.tokens) }) { schluessel in
                        let s = stufen.first { String($0.tokens) == schluessel }
                        let gewaehlt = Int(schluessel) == zustand.kontextWert
                        let inhalt = VStack(alignment: .leading, spacing: 1) {
                            Text(s?.label ?? schluessel).font(.callout)
                            Text(s?.passt == false ? (s?.hinweis ?? "") : zustand.texte.t("kontext.token", ["0": schluessel]))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(gewaehlt ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.quaternary)))
                        if beleg {
                            inhalt
                        } else {
                            Button { zustand.kontextWaehlen(Int(schluessel) ?? 0) } label: { inhalt }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("kontext:\(schluessel)")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var fuss: some View {
        HStack(spacing: 10) {
            Text(zustand.status).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                .accessibilityIdentifier("erststart-status")
            Spacer(minLength: 8)
            if beleg {
                Text(zustand.texte.t("knopf.ueberspringen")).font(.callout)
                    .padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(.quaternary))
                Text(zustand.texte.t(zustand.schritt == .fertig ? "knopf.fertig" : "knopf.weiter")).font(.callout)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(.tint)).foregroundStyle(Color.white)
            } else {
                Button(zustand.texte.t("knopf.ueberspringen")) { zustand.ueberspringen() }
                    .buttonStyle(.bordered).disabled(zustand.beschaeftigt)
                    .accessibilityIdentifier("ueberspringen")
                Button(zustand.texte.t(zustand.schritt == .fertig ? "knopf.fertig" : "knopf.weiter")) { zustand.weiter() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(zustand.beschaeftigt)
                    .accessibilityIdentifier("weiter")
            }
        }
    }
}

// MARK: Das Sheet am Hauptfenster

@MainActor
final class ErststartSheet {
    let zustand: ErststartZustand
    /// Das Fenster, das als Sheet haengt. Es entsteht immer -- gezeigt wird es
    /// nur ueber `zeigen()`, und kopflos gar nicht.
    let fenster: NSWindow
    private weak var haupt: NSWindow?
    private let kopflos: Bool
    private var geladen = false
    private(set) var sichtbar = false

    init(kern: KernVerbindung, kopflos: Bool, haupt: NSWindow?) {
        self.kopflos = kopflos
        self.haupt = haupt
        zustand = ErststartZustand(kern: kern, kopflos: kopflos)
        fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
                           styleMask: [.titled], backing: .buffered, defer: false)
        fenster.isReleasedWhenClosed = false
        fenster.identifier = NSUserInterfaceItemIdentifier("erststart")
        let inhalt = NSHostingController(rootView: ErststartBlatt(zustand: zustand))
        inhalt.sizingOptions = []
        fenster.contentViewController = inhalt
        // NACH dem contentViewController: er zieht das Fenster sonst auf die
        // ideale Groesse seiner Ansicht, und ein nie gezeigtes Fenster haette
        // dann keine Flaeche, in die ein Belegbild passt (dieselbe Lehre wie
        // beim Einstellungsfenster, 2.6).
        fenster.setContentSize(NSSize(width: 620, height: 460))
        zustand.abgeschlossenMelden = { [weak self] in self?.schliessenWennFertig() }
    }

    /// Bauen und laden, OHNE zu zeigen -- der Weg des Steuerkanals. Mehrfach
    /// aufrufbar; ein Ladeversuch OHNE Verbindung zaehlt nicht als geladen,
    /// sonst bliebe das Blatt fuer den Rest des Laufs leer (gemessen 06.09.:
    /// `erststartPruefen` laeuft beim Start, die Verbindung zum Kern steht dann
    /// nicht immer schon).
    func bauen() async {
        fenster.layoutIfNeeded()
        if !geladen {
            await zustand.laden()
            geladen = zustand.daten != nil
            if !zustand.texte.leer { fenster.title = zustand.texte.t("kopf.titel") }
            fenster.layoutIfNeeded()
        }
    }

    /// Der einzige Weg auf den Bildschirm. Kopflos wirkungslos.
    func zeigen() {
        guard !kopflos, !sichtbar, let eltern = haupt else { return }
        sichtbar = true
        Task { @MainActor in
            await bauen()
            eltern.beginSheet(fenster) { [weak self] _ in self?.sichtbar = false }
        }
    }

    private func schliessenWennFertig() {
        guard zustand.abgeschlossen else { return }
        if sichtbar, let eltern = haupt {
            eltern.endSheet(fenster)
            sichtbar = false
        }
    }

    func auskunft() -> [String: Any] {
        zustand.auskunft().merging(["sichtbar": sichtbar]) { a, _ in a }
    }

    /// Ein Belegbild, auch kopflos -- derselbe Weg wie beim Sitzungsfenster: der
    /// Rahmen in eine Bitmap, darueber das Blatt aus denselben Views ueber
    /// `ImageRenderer`, weil Steuerelemente ausserhalb des Bildschirms nichts
    /// zeichnen.
    func schuss(pfad: String) throws -> (breite: Int, hoehe: Int) {
        fenster.layoutIfNeeded()
        guard let inhalt = fenster.contentView, inhalt.bounds.width > 1, inhalt.bounds.height > 1,
              let rep = inhalt.bitmapImageRepForCachingDisplay(in: inhalt.bounds) else {
            throw NSError(domain: "Werkbank", code: 2, userInfo: [NSLocalizedDescriptionKey: "keine Bitmap"])
        }
        let dunkel = fenster.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            fenster.effectiveAppearance.performAsCurrentDrawingAppearance {
                fenster.backgroundColor.setFill()
                NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh).fill()
            }
            let renderer = ImageRenderer(content: ErststartBlatt(zustand: zustand, beleg: true)
                .frame(width: inhalt.bounds.width, height: inhalt.bounds.height, alignment: .topLeading)
                .environment(\.colorScheme, dunkel ? .dark : .light))
            renderer.scale = fenster.backingScaleFactor
            renderer.proposedSize = ProposedViewSize(width: inhalt.bounds.width, height: inhalt.bounds.height)
            renderer.nsImage?.draw(in: inhalt.bounds, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Werkbank", code: 3, userInfo: [NSLocalizedDescriptionKey: "kein PNG"])
        }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: pfad).deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: pfad))
        return (rep.pixelsWide, rep.pixelsHigh)
    }
}

/// Eine Reihe, die umbricht. `Layout` statt `LazyVGrid`, weil die Chips
/// verschieden breit sind und ein Raster sie auf die breiteste ziehen wuerde.
struct WrapReihe<Inhalt: View>: View {
    let schluessel: [String]
    @ViewBuilder let inhalt: (String) -> Inhalt

    init(_ schluessel: [String], @ViewBuilder inhalt: @escaping (String) -> Inhalt) {
        self.schluessel = schluessel
        self.inhalt = inhalt
    }

    var body: some View {
        FliessLayout(abstand: 6) {
            ForEach(schluessel, id: \.self) { inhalt($0) }
        }
    }
}

struct FliessLayout: Layout {
    var abstand: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let breite = proposal.width ?? 560
        let zeilen = umbrechen(subviews, breite: breite)
        let hoehe = zeilen.reduce(CGFloat(0)) { $0 + $1.hoehe + abstand }
        return CGSize(width: breite, height: max(0, hoehe - abstand))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let zeilen = umbrechen(subviews, breite: bounds.width)
        var y = bounds.minY
        for zeile in zeilen {
            var x = bounds.minX
            for i in zeile.eintraege {
                let g = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(g))
                x += g.width + abstand
            }
            y += zeile.hoehe + abstand
        }
    }

    private func umbrechen(_ subviews: Subviews, breite: CGFloat) -> [(eintraege: [Int], hoehe: CGFloat)] {
        var zeilen: [(eintraege: [Int], hoehe: CGFloat)] = []
        var laufend: [Int] = []
        var x: CGFloat = 0
        var hoehe: CGFloat = 0
        for i in subviews.indices {
            let g = subviews[i].sizeThatFits(.unspecified)
            if !laufend.isEmpty && x + g.width > breite {
                zeilen.append((laufend, hoehe))
                laufend = []; x = 0; hoehe = 0
            }
            laufend.append(i)
            x += g.width + abstand
            hoehe = max(hoehe, g.height)
        }
        if !laufend.isEmpty { zeilen.append((laufend, hoehe)) }
        return zeilen
    }
}

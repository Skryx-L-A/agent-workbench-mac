// Die Verbrauchsseite (Auftrag 3.8) als EIGENES FENSTER, Zwilling des
// Einstellungs- und des Sitzungsfensters.
//
// WARUM EIN FENSTER UND KEIN BLATT DES INSPEKTORS. Die vier Blaetter rechts
// (3.5/3.6) sind Auswahl: man sucht dort etwas aus, und das Gesuchte geht in
// der Mitte auf. Der Verbrauch ist das Gegenteil -- ein BERICHT, aus dem
// nichts aufgeht und den man neben der Werkbank liegen hat, waehrend man
// weiterarbeitet. Dazu kommt die Breite: hier stehen Tabellen mit fuenf
// Spalten nebeneinander, und der Inspektor ist die Spalte, die bei knapper
// Fensterbreite als erste weicht (`plattformen.md`). Die Electron-Fassung
// entscheidet aus denselben Gruenden ebenso (verbrauchsfenster.ts) und nennt
// ihre Masse: 1180 x 820, mindestens 900 x 600. Der gefuehrte erste Start
// (dieselbe Auftragszeile) entscheidet umgekehrt und aus dem gegenteiligen
// Grund: er ist eine einmalige Aufgabe an DIESEM Fenster, also ein Sheet.
//
// ES WIRD HIER NICHT GERECHNET. Die Zahlen kommen aus `wb-budget` ueber
// `awb:verbrauch-daten`, die Abschnitte aus `WerkbankProtokoll/Verbrauch.swift`
// (unter `swift test`), die Beschriftungen ueber `awb:verbrauch-texte` vom
// Kern. Die Wochenzeile der Kontingente kommt aus demselben `budget` des
// Modells, das der Statusfuss zeigt -- eine zweite Rechnung fuer dieselbe Zahl
// gaebe es sonst zweimal, mit zwei Gelegenheiten, auseinanderzulaufen.
//
// DIE AUFLAGE AUS DIESEM HAUS: `bauen()` baut und liest, ohne zu zeigen (der
// Weg des Steuerkanals, `awbmac-ctl verbrauch`); `zeigen()` ist der einzige Weg
// auf den Bildschirm und kopflos wirkungslos.
//
// Textstile, Systemfarben, Systemakzent; keine festen Punktgroessen fuer Text,
// keine fest verdrahteten Farben, keine Emojis.
import AppKit
import SwiftUI
import WerkbankProtokoll

@MainActor
@Observable
final class VerbrauchsZustand {
    let kern: KernVerbindung
    let kopflos: Bool

    private(set) var daten: VerbrauchDaten?
    private(set) var vergleichsDaten: VerbrauchDaten?
    private(set) var texte = Texte()
    private(set) var fehler = ""
    private(set) var laedt = false
    /// Der Zeitraum in Tagen -- die Knopfreihe oben (`zeitraum.*`).
    private(set) var tage = 7
    var auswahl = VerbrauchAuswahl()
    var vergleichAn = false
    /// Wie oft die Seite Daten geholt hat -- eine Suite zaehlt damit die Takte.
    private(set) var lesungen = 0
    private var bereitGemeldet = false

    static let zeitraeume = [1, 2, 7, 14, 30]

    init(kern: KernVerbindung, kopflos: Bool) {
        self.kern = kern
        self.kopflos = kopflos
    }

    func laden() async {
        if texte.leer {
            let t = await kern.invoke("awb:verbrauch-texte")
            if let w = t.wertJSON { texte = Texte(json: JSONWert.lesen(w)) }
        }
        laedt = true
        let a = await kern.invoke("awb:verbrauch-daten", [["tage": tage]])
        laedt = false
        lesungen += 1
        switch VerbrauchAntwort.lesen(a.wertJSON) {
        case .daten(let d):
            daten = d
            fehler = ""
        case .fehler(let f):
            // Nicht mit einer leeren Seite antworten: „nichts verbraucht" und
            // „nicht gelesen" sind zwei sehr verschiedene Auskuenfte.
            daten = nil
            fehler = f
        }
        if vergleichAn { await vergleichLaden() } else { vergleichsDaten = nil }
        if !bereitGemeldet {
            bereitGemeldet = true
            kern.send("awb:verbrauch-bereit", [])
        }
    }

    func zeitraumSetzen(_ n: Int) {
        guard n != tage else { return }
        tage = n
        vergleichsDaten = nil
        Task { @MainActor in await laden() }
    }

    func vergleichUmschalten() {
        vergleichAn.toggle()
        Task { @MainActor in
            if vergleichAn { await vergleichLaden() } else { vergleichsDaten = nil }
        }
    }

    /// Der gleich lange Zeitraum davor -- eine zweite Frage an dasselbe
    /// Werkzeug, mit `von`/`bis` statt `tage`.
    private func vergleichLaden() async {
        guard let d = daten, let z = VerbrauchVergleich.vorherigerZeitraum(von: d.von, bis: d.bis) else {
            vergleichsDaten = nil
            return
        }
        laedt = true
        let a = await kern.invoke("awb:verbrauch-daten", [["von": z.von, "bis": z.bis]])
        laedt = false
        lesungen += 1
        if case .daten(let v) = VerbrauchAntwort.lesen(a.wertJSON) { vergleichsDaten = v } else { vergleichsDaten = nil }
    }

    /// Die Wochenzeile aus demselben `budget`, das der Statusfuss zeigt.
    var woche: VerbrauchWoche? {
        guard let b = kern.modell.budget, b.wocheDa else { return nil }
        // Der Tag im Fenster steckt schon im erlaubten Anteil (Tag x 100/7,
        // wb-budget) -- er wird zurueckgerechnet, nicht ein zweites Mal aus
        // einer Uhr gebildet.
        let tag = Int((b.wocheErlaubt * 7 / 100).rounded())
        return VerbrauchWoche(verbraucht: b.wocheVerbraucht, erlaubt: b.wocheErlaubt, tag: max(1, min(7, tag)))
    }

    var abschnitte: [VerbrauchAbschnitt] {
        guard let d = daten else { return [] }
        return VerbrauchSeiten.abschnitte(daten: d, auswahl: auswahl, texte: texte,
                                          woche: woche, vergleich: vergleichAn ? vergleichsDaten : nil)
    }

    var standText: String {
        guard let d = daten else { return "" }
        return texte.t("stand", ["0": VerbrauchZahlen.zeitpunkt(d.erzeugt),
                                 "1": VerbrauchZahlen.zeitpunkt(d.von),
                                 "2": VerbrauchZahlen.zeitpunkt(d.bis)])
    }

    var harnessChips: [(id: String, tokens: Double)] { VerbrauchSeiten.harnessListe(daten?.jeModell ?? []) }
    var modellChips: [(id: String, tokens: Double)] { VerbrauchSeiten.modellListe(daten?.jeModell ?? [], auswahl) }

    // MARK: Steuerkanal

    /// `zeitraum:<tage>`, `harness:<id>`, `modell:<id>`, `vergleich`, `zuruecksetzen`, `neu`.
    func klick(_ knopf: String) -> Bool {
        if knopf.hasPrefix("zeitraum:") { zeitraumSetzen(Int(knopf.dropFirst(9)) ?? tage); return true }
        if knopf.hasPrefix("harness:") { auswahl.umschalten(harness: String(knopf.dropFirst(8))); return true }
        if knopf.hasPrefix("modell:") { auswahl.umschalten(modell: String(knopf.dropFirst(7))); return true }
        if knopf == "vergleich" { vergleichUmschalten(); return true }
        if knopf == "zuruecksetzen" { auswahl = VerbrauchAuswahl(); return true }
        if knopf == "neu" { Task { @MainActor in await laden() }; return true }
        return false
    }

    func handlungAbwarten() async {
        for _ in 0..<800 where laedt {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    func auskunft() -> [String: Any] {
        [
            "gebaut": true,
            "geladen": daten != nil,
            "fehler": fehler,
            "laedt": laedt,
            "lesungen": lesungen,
            "tage": tage,
            "stand": standText,
            "vergleich": vergleichAn,
            "vergleichGeladen": vergleichsDaten != nil,
            "auswahlHarness": auswahl.harness,
            "auswahlModell": auswahl.modell,
            "harnessChips": harnessChips.map { ["id": $0.id, "tokens": $0.tokens] },
            "modellChips": modellChips.map { ["id": $0.id, "tokens": $0.tokens] },
            "abschnitte": abschnitte.map { a in
                [
                    "id": a.id, "titel": a.titel, "hinweis": a.hinweis, "kopf": a.kopf, "fuss": a.fuss,
                    "zeilen": a.zeilen.map { z -> [String: Any] in
                        var e: [String: Any] = ["id": z.id, "zellen": z.zellen, "hinweis": z.hinweis]
                        if let anteil = z.anteil { e["anteil"] = anteil }
                        if let marke = z.marke { e["marke"] = marke }
                        return e
                    },
                ]
            },
            "sprache": texte.sprache,
        ]
    }
}

// MARK: Die Ansicht

struct VerbrauchsAnsicht: View {
    @Bindable var zustand: VerbrauchsZustand
    /// Beleg-Modus: ohne AppKit-Steuerelemente, damit das Bild etwas zeigt.
    var beleg = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            kopf
            Divider()
            if zustand.daten == nil && !zustand.fehler.isEmpty {
                fehlerkasten
            } else {
                inhalt
            }
            Divider()
            HStack {
                Text(zustand.laedt ? zustand.texte.t("laden") : zustand.standText)
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("verbrauch-stand")
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .accessibilityIdentifier("verbrauch")
    }

    private var kopf: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(zustand.texte.t("kopf.titel")).font(.title2).bold()
            Text(zustand.texte.t("kopf.unterzeile")).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            chipreihe(titel: zustand.texte.t("zeitraum.titel"),
                      eintraege: VerbrauchsZustand.zeitraeume.map { (String($0), zustand.texte.t("zeitraum.\($0)")) },
                      gewaehlt: [String(zustand.tage)], kennung: "zeitraum")
            if !zustand.harnessChips.isEmpty {
                chipreihe(titel: zustand.texte.t("filter.harness"),
                          eintraege: zustand.harnessChips.map { ($0.id, "\($0.id) · \(VerbrauchZahlen.kompakt($0.tokens))") },
                          gewaehlt: zustand.auswahl.harness, kennung: "harness")
            }
            if !zustand.modellChips.isEmpty {
                chipreihe(titel: zustand.texte.t("filter.modell"),
                          eintraege: zustand.modellChips.map { ($0.id, "\($0.id) · \(VerbrauchZahlen.kompakt($0.tokens))") },
                          gewaehlt: zustand.auswahl.modell, kennung: "modell")
            }
            HStack(spacing: 10) {
                if beleg {
                    Text(zustand.texte.t(zustand.vergleichAn ? "vergleich.aus" : "vergleich.knopf")).font(.callout)
                        .padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(.quaternary))
                } else {
                    Button(zustand.texte.t(zustand.vergleichAn ? "vergleich.aus" : "vergleich.knopf")) { zustand.vergleichUmschalten() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("vergleich")
                    if !zustand.auswahl.harness.isEmpty || !zustand.auswahl.modell.isEmpty {
                        Button(zustand.texte.t("filter.zuruecksetzen")) { zustand.auswahl = VerbrauchAuswahl() }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("zuruecksetzen")
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 10)
    }

    @ViewBuilder
    private func chipreihe(titel: String, eintraege: [(String, String)], gewaehlt: [String], kennung: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(titel).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            FliessLayout(abstand: 6) {
                ForEach(eintraege, id: \.0) { e in
                    let an = gewaehlt.contains(e.0)
                    let inhalt = Text(e.1).font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(an ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)))
                        .foregroundStyle(an ? Color.white : Color.primary)
                    if beleg {
                        inhalt
                    } else {
                        Button { _ = zustand.klick("\(kennung):\(e.0)") } label: { inhalt }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("\(kennung):\(e.0)")
                            .accessibilityLabel("\(e.1)\(an ? ", gewählt" : "")")
                    }
                }
            }
        }
    }

    private var fehlerkasten: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(zustand.texte.t("fehler.titel")).font(.headline)
            Text(zustand.fehler).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("verbrauch-fehler")
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var inhalt: some View {
        let abschnitte = zustand.abschnitte
        if beleg {
            // Im Beleg zeichnet keine ScrollView; der Ausschnitt von oben reicht,
            // um Text und Aufteilung zu zeigen (dieselbe Lehre wie beim Inspektor).
            VStack(alignment: .leading, spacing: 16) {
                ForEach(abschnitte.prefix(4)) { AbschnittsAnsicht(abschnitt: $0) }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(abschnitte) { AbschnittsAnsicht(abschnitt: $0) }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Ein Abschnitt: Ueberschrift, Satz, Tabelle, Fusszeile. Eine Zeile mit
/// `anteil` bekommt ihren Balken unter den Zellen.
struct AbschnittsAnsicht: View {
    let abschnitt: VerbrauchAbschnitt

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(abschnitt.titel).font(.headline)
                .accessibilityIdentifier("abschnitt:\(abschnitt.id)")
            if !abschnitt.hinweis.isEmpty {
                Text(abschnitt.hinweis).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !abschnitt.kopf.isEmpty {
                zeile(abschnitt.kopf, kopf: true)
            }
            ForEach(abschnitt.zeilen) { z in
                VStack(alignment: .leading, spacing: 2) {
                    zeile(z.zellen, kopf: false)
                    if let anteil = z.anteil { balken(anteil, marke: z.marke) }
                    if !z.hinweis.isEmpty {
                        Text(z.hinweis).font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !abschnitt.fuss.isEmpty {
                Text(abschnitt.fuss).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func zeile(_ zellen: [String], kopf: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            ForEach(Array(zellen.enumerated()), id: \.offset) { i, wert in
                Text(wert)
                    .font(kopf ? .caption : .callout)
                    .fontWeight(kopf ? .semibold : (i == 0 ? .regular : .regular))
                    .foregroundStyle(kopf ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : .trailing)
            }
        }
    }

    /// Ein Balken aus einer Capsule -- dieselbe Form wie die Wochenzeile des
    /// Statusfusses, aus demselben Grund: `ProgressView` zeichnet im
    /// ImageRenderer ein Sperrsymbol statt eines Balkens (gemessen 2.5).
    private func balken(_ anteil: Double, marke: Double?) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.tint)
                    .frame(width: g.size.width * min(1, max(0, anteil)))
                if let m = marke {
                    Rectangle().fill(.secondary)
                        .frame(width: 2)
                        .offset(x: g.size.width * min(1, max(0, m)) - 1)
                }
            }
        }
        .frame(height: 6)
    }
}

// MARK: Das Fenster

@MainActor
final class VerbrauchsFenster: NSObject, NSWindowDelegate {
    let zustand: VerbrauchsZustand
    let fenster: NSWindow
    /// Die ganzen Laufoptionen, nicht nur `kopflos`: `zeigen()` braucht daneben
    /// `ohneFokus` (Laufoptionen.swift, `vorZeigen`).
    private let optionen: Laufoptionen
    private var kopflos: Bool { optionen.kopflos }
    private var geladen = false
    var sichtbar: Bool { fenster.isVisible }

    init(kern: KernVerbindung, optionen: Laufoptionen) {
        self.optionen = optionen
        zustand = VerbrauchsZustand(kern: kern, kopflos: optionen.kopflos)
        // 1180 x 820, mindestens 900 x 600: die Masse der Electron-Fassung --
        // hier stehen Tabellen neben Tabellen, und ein Tagesverlauf auf 700
        // Punkten zeigt keinen Verlauf mehr.
        fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        super.init()
        fenster.title = "Verbrauch"
        fenster.minSize = NSSize(width: 900, height: 600)
        fenster.isReleasedWhenClosed = false
        fenster.titlebarSeparatorStyle = .automatic
        fenster.delegate = self
        fenster.identifier = NSUserInterfaceItemIdentifier("verbrauch")
        let inhalt = NSHostingController(rootView: VerbrauchsAnsicht(zustand: zustand))
        inhalt.sizingOptions = []
        fenster.contentViewController = inhalt
        fenster.setContentSize(NSSize(width: 1180, height: 820))
    }

    /// Bauen und laden, OHNE zu zeigen. Ein Ladeversuch ohne Verbindung zaehlt
    /// nicht als geladen (dieselbe Lehre wie beim Erststart-Blatt).
    func bauen() async {
        fenster.layoutIfNeeded()
        if !geladen {
            await zustand.laden()
            geladen = zustand.daten != nil || !zustand.fehler.isEmpty
            if !zustand.texte.leer { fenster.title = zustand.texte.t("kopf.titel") }
            fenster.layoutIfNeeded()
        }
    }

    /// Der einzige Weg auf den Bildschirm. Kopflos wirkungslos.
    func zeigen() {
        guard !kopflos else {
            Task { @MainActor in await bauen() }
            return
        }
        Task { @MainActor in
            await bauen()
            fenster.vorZeigen(ohneFokus: optionen.ohneFokus)
        }
    }

    /// Ein Belegbild, auch kopflos -- derselbe Weg wie beim Erststart-Blatt.
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
            let renderer = ImageRenderer(content: VerbrauchsAnsicht(zustand: zustand, beleg: true)
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

    func auskunft() -> [String: Any] {
        zustand.auskunft().merging(["sichtbar": sichtbar]) { a, _ in a }
    }
}

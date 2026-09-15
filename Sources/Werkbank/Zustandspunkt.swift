// DER ZUSTANDSPUNKT (Politur vom 08.09.2026, mac/PLAN.md).
//
// Befund des Nutzers an der installierten App: „ich mag die status symbole
// nicht, die Punkte von gerade sind besser". Gemeint sind die Punkte der
// Electron-Werkbank (app/src/renderer/werkbank.css, Abschnitt „Der
// Zustandspunkt"). Sie sind hier nachgebaut -- dieselbe Semantik, dieselben
// Masse, dieselben sieben Auspraegungen, nur in Punkten statt in Bildpunkten
// und mit Systemfarben statt Hexwerten.
//
// DIE FORM TRAEGT MIT, nicht die Farbe allein (abnahme.md, Merkmal 5): gefuellt
// heisst „laeuft", ein Ring heisst „laeuft anderswo", hohl heisst „aus", und
// gefuellt mit weichem Hof heisst „wartet auf Dich". Wer Farben schlecht
// unterscheidet, sieht den Unterschied trotzdem. Das WORT bleibt daneben --
// jede Zeile, die einen Punkt traegt, nennt ihren Zustand im
// `accessibilityLabel` und im Hilfeschildchen; der Punkt selbst ist fuer
// VoiceOver deshalb still.
//
// MASSE (werkbank.css): acht Punkte Durchmesser, anderthalb Punkte Ringstaerke,
// drei Punkte Hof. Sie stehen hier als Verhaeltnis zur Grundgroesse, damit der
// Punkt mit der Textgroesse des Systems waechst (abnahme.md, Merkmal 1) und in
// jeder Auspraegung gleich gross bleibt: `strokeBorder` legt den Ring nach
// innen, so wie `box-sizing: border-box` es in der Electron-Fassung tut.
import AppKit
import SwiftUI
import WerkbankProtokoll

/// Die sieben Auspraegungen des Punktes. Die Kennungen sind wortgleich mit den
/// CSS-Klassen der Electron-Fassung (`.punkt.laeuft` und die uebrigen), damit
/// eine Pruefung beide Fassungen gleich liest.
enum Punktart: String, Sendable, CaseIterable {
    /// Gefuellt: arbeitet auf dieser Maschine.
    case laeuft
    /// Gefuellt mit Hof: wartet auf eine Entscheidung des Menschen.
    case will
    /// Hohler Ring, gedaempft: da, aber ruft nicht.
    case ruhig
    /// Hohler Ring in der Tot-Farbe: beendet oder gar nicht erst gestartet.
    case aus
    /// Ring in der Lauf-Farbe: laeuft, aber nicht hier -- niemand kann hineinsehen.
    case fern
    /// Gefuellt: fertig, mit Ergebnis.
    case fertig
    /// Gefuellt, gedaempft: gewollt abgestellt, nicht ausgefallen.
    case pausiert

    /// Der Zustand einer Sitzung (renderer.ts `startfarbe`/`farbklasse`). Ein
    /// Start, der laeuft, ist das Gegenteil von „beendet" und traegt deshalb
    /// die Wartefarbe; ein gescheiterter Start bleibt in der Tot-Farbe.
    static func sitzung(_ s: SitzungsEintrag) -> Punktart {
        if s.startet && !s.startFehler { return .will }
        switch s.state {
        case "running": return .laeuft
        case "attention": return .will
        case "unreachable": return .fern
        default: return .aus
        }
    }

    /// Der Zustand eines Workers (renderer.ts `zustandFarbe`). Abweichung von
    /// der Electron-Fassung, bewusst und in mac/PLAN.md begruendet: ein
    /// FERTIGER Worker bekommt hier den Fertig-Punkt statt des ruhigen. Die
    /// Mac-Fassung hat den Unterschied bisher gezeigt (Haekchen statt Kreis),
    /// und sie soll nie weniger koennen als vorher.
    static func worker(_ state: String) -> Punktart {
        switch state {
        case "running": return .laeuft
        case "blocked", "stalled": return .will
        case "done": return .fertig
        case "unknown": return .fern
        default: return .ruhig
        }
    }

    /// Das Wort zum Punkt -- fuer Hilfeschildchen und Auskunft dort, wo die
    /// Zeile nicht ohnehin eines traegt.
    var wort: String {
        switch self {
        case .laeuft: return "läuft"
        case .will: return "wartet auf Dich"
        case .ruhig: return "ruhig"
        case .aus: return "aus"
        case .fern: return "läuft auf einer anderen Maschine"
        case .fertig: return "fertig"
        case .pausiert: return "pausiert"
        }
    }

    /// Welche der vier Zustandsfarben des Kerns diese Auspraegung traegt --
    /// oder nil fuer die beiden gedaempften, die keine eigene Farbe haben.
    /// Die Namen sind die des Kerns (`zustandsfarbenLesbar`, main/thema.ts).
    var kernfarbe: String? {
        switch self {
        case .laeuft, .fern: return "laeuft"
        case .will: return "wartet"
        case .aus: return "tot"
        case .fertig: return "fertig"
        case .ruhig, .pausiert: return nil
        }
    }

    /// DIE FARBE KOMMT AUS DEM KERN (08.09.2026, Vorgabe des Nutzers: „exakt die
    /// Punkte der Electron-Werkbank"). Der Mensch waehlt sie in den
    /// Einstellungen unter „Aussehen"; der Kern prueft sie gegen den Grund des
    /// wirksamen Erscheinungsbildes und schickt sie als `zustandsfarbenLesbar`.
    /// Bis die erste Meldung da ist -- und wenn sie ausbleibt -- gelten die
    /// Systemfarben darunter. „laeuft" ist im Haus BLAU (#4ea1ff), nicht gruen;
    /// die gruene Vorgabe hier ist nur der Rueckfall, wenn kein Kern spricht.
    @MainActor var farbe: Color {
        if let name = kernfarbe, let c = Zustandsfarben.aktuell.farbe(name) { return c }
        switch self {
        case .laeuft, .fern: return .green
        case .will: return .orange
        case .aus: return .red
        case .fertig: return .blue
        case .ruhig, .pausiert: return .secondary
        }
    }

    /// Gefuellt oder hohl -- der Teil der Unterscheidung, der ohne Farbe auskommt.
    var gefuellt: Bool {
        switch self {
        case .laeuft, .will, .fertig, .pausiert: return true
        case .ruhig, .aus, .fern: return false
        }
    }

    /// Die Ringstaerke in der Grundgroesse acht: der ferne Punkt traegt zwei
    /// statt anderthalb Punkte, damit er auch aus dem Augenwinkel als Ring
    /// lesbar bleibt (werkbank.css `.punkt.fern`).
    var ringstaerke: CGFloat { self == .fern ? 2 : 1.5 }

    /// Der weiche Hof, der den wartenden Punkt aus einer vollen Leiste heraushebt.
    var hof: Bool { self == .will }

    /// Die Form als Wort -- fuer `awbmac-ctl ui`, damit eine Pruefung nicht die
    /// Farbe am Bildpunkt nachmessen muss.
    var form: String {
        if hof { return "gefuellt-hof" }
        if gefuellt { return "gefuellt" }
        return ringstaerke > 1.5 ? "ring-dick" : "ring"
    }
}

/// Die vier Zustandsfarben, wie der Kern sie zuletzt gemeldet hat.
///
/// EINE Stelle fuer alle Punkte: `KernVerbindung` legt hier ab, was
/// `awb:thema-neu` bringt, und jeder `Zustandspunkt` liest es beim Zeichnen.
/// Ein eigener Wert je Aufrufstelle waere derselbe Wert an zwanzig Orten -- und
/// die Punkte stehen in Fenstern, die den Kern gar nicht kennen (Kachelkopf,
/// Tab-Streifen, Sitzungsfenster).
@MainActor
@Observable
final class Zustandsfarben {
    static let aktuell = Zustandsfarben()

    /// laeuft | wartet | fertig | tot -- die Namen des Kerns.
    private(set) var werte: [String: Color] = [:]
    /// 'hell' oder 'dunkel', wie der Kern es aufgeloest hat -- fuer die Auskunft.
    private(set) var wirksam = ""
    /// Die rohen Hexwerte, damit `awbmac-ctl ui` sie nennen kann.
    private(set) var hex: [String: String] = [:]

    func uebernehmen(_ t: ThemaNutzlast) {
        wirksam = t.wirksam
        hex = t.zustandsfarbenLesbar
        werte = t.zustandsfarbenLesbar.compactMapValues { Color(hex: $0) }
    }

    func farbe(_ name: String) -> Color? { werte[name] }

    /// DIE FARBE AM BILDPUNKT, nicht die im Entwurf (Zusage vom 08.09.2026:
    /// „Pixelfarbe des Punkts eines laufenden Workers == Farbe im
    /// Electron-Belegbild"). Der Punkt wird gezeichnet und dann ausgelesen:
    /// gefuellt in der Mitte, hohl auf dem Ring. So faellt auf, wenn zwischen
    /// Farbwert und Bild noch etwas dazwischenkommt -- ein Verlauf, eine
    /// Deckkraft, ein falscher Farbraum.
    static func gemessen(_ art: Punktart, dunkel: Bool) -> String {
        // IN sRGB ZEICHNEN UND IN sRGB LESEN. Ueber `nsImage` ging der Punkt
        // durch den Farbraum des Bildschirms und kam heller zurueck (gemessen
        // 08.09.: #4ea1ff hinein, #5eb3ff heraus). Der Farbwert des Kerns ist
        // sRGB; wer ihn nachmisst, muss im selben Raum messen.
        let renderer = ImageRenderer(content:
            Zustandspunkt(art: art)
                .environment(\.colorScheme, dunkel ? .dark : .light)
        )
        renderer.scale = 8
        var treffer = ""
        renderer.render { groesse, zeichnen in
            let breite = max(1, Int((groesse.width * 8).rounded()))
            let hoehe = max(1, Int((groesse.height * 8).rounded()))
            guard let raum = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: nil, width: breite, height: hoehe,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: raum,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.scaleBy(x: 8, y: 8)
            zeichnen(ctx)
            guard let daten = ctx.data else { return }
            let zeilenlaenge = ctx.bytesPerRow
            let punkte = daten.bindMemory(to: UInt8.self, capacity: zeilenlaenge * hoehe)
            // Gefuellt in der Mitte; hohl in der MITTE DES RINGES, nicht an
            // seiner Kante -- dort ist die Deckung nur halb, und die Messung
            // kam einmal leer zurueck (gemessen 08.09. im hellen Bild).
            let x = breite / 2
            let y = art.gefuellt ? hoehe / 2 : max(1, Int((art.ringstaerke * 8 / 2).rounded()))
            let i = y * zeilenlaenge + x * 4
            // Schwelle niedrig: die beiden gedaempften Auspraegungen zeichnen
            // in `.secondary`, und das ist eine halbdurchsichtige Tinte -- mit
            // 0,5 kam die Messung im hellen Bild leer zurueck.
            let a = CGFloat(punkte[i + 3]) / 255
            guard a > 0.1 else { return }
            // Vormultipliziert: durch die Deckkraft zurueckrechnen.
            let r = min(255, Int((CGFloat(punkte[i]) / a).rounded()))
            let g = min(255, Int((CGFloat(punkte[i + 1]) / a).rounded()))
            let b = min(255, Int((CGFloat(punkte[i + 2]) / a).rounded()))
            treffer = String(format: "#%02x%02x%02x", r, g, b)
        }
        return treffer
    }
}

/// Der gezeichnete Punkt. Er nimmt sich in jeder Auspraegung dieselbe
/// Layoutbreite; der Hof liegt darueber hinaus und schiebt nichts.
struct Zustandspunkt: View {
    let art: Punktart
    /// Die Grundgroesse, mitwachsend mit der Textgroesse des Systems. Acht
    /// Punkte sind das Mass der Electron-Fassung (werkbank.css) und bleiben die
    /// Vorgabe; die Seitenleiste zeichnet seit dem 08.09.2026 SECHS.
    ///
    /// Warum ein Wert je Aufrufstelle und keine neue Vorgabe fuer alle:
    /// Befund des Nutzers („zu gross und aufdringlich") gilt der Leiste, in der
    /// die Punkte dicht untereinander stehen. In einer Kachelkopfzeile steht
    /// EIN Punkt neben einem Namen, und dort war nie etwas zu gross.
    @ScaledMetric private var groesse: CGFloat

    init(art: Punktart, basis: CGFloat = 8) {
        self.art = art
        _groesse = ScaledMetric(wrappedValue: basis, relativeTo: .body)
    }

    var body: some View {
        // Alle Masse als Verhaeltnis zur Grundgroesse acht: waechst der Punkt,
        // wachsen Ring und Hof mit ihm.
        let mass = groesse / 8
        ZStack {
            if art.hof {
                Circle()
                    .fill(art.farbe.opacity(0.16))
                    .frame(width: groesse + 6 * mass, height: groesse + 6 * mass)
            }
            if art.gefuellt {
                Circle().fill(art.farbe)
            } else {
                Circle().strokeBorder(art.farbe, lineWidth: art.ringstaerke * mass)
            }
        }
        .frame(width: groesse, height: groesse)
        // In einer Zeile mit `firstTextBaseline` hat ein Kreis keine
        // Grundlinie; ohne diese Angabe legt SwiftUI seine Unterkante auf die
        // Schriftlinie und der Punkt rutscht nach oben. Die halbe Versalhoehe
        // der Grundschrift liegt rund 0,55 Punktdurchmesser ueber der
        // Grundlinie -- damit sitzt der Punkt auf der Mitte der ersten Zeile.
        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + groesse * 0.55 }
        .accessibilityHidden(true)
    }
}

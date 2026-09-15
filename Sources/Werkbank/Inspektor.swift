// DER INSPEKTOR RECHTS MIT VIER BLAETTERN (Auftraege 3.5 und 3.6, 06.09.2026).
//
// WARUM HIER UND NICHT ALS VIERTER ZWEIG DES UMSCHALTERS. Die Zweige des
// Umschalters sind, was die BUEHNE fuellt: Terminal, Gespraech, Editor. Ordner,
// Aktivitaet und Protokolle sind das Gegenteil davon -- man sucht dort etwas
// aus, und das Gesuchte geht danach in die Mitte auf. Waeren sie ein vierter
// Zweig, verdraengte der Klick genau die Liste, aus der er kam.
//
// WARUM NICHT ALS ZWEITE SPALTE LINKS. Die Electron-Fassung haengt sie als
// Schublade zwischen Sitzungsleiste und Buehne (`#schublade`). Auf dem Mac
// waeren das vier Spalten nebeneinander; Apple raet, bei knapper Breite ZUERST
// die hinteren Spalten wie den Inspektor auszublenden (`plattformen.md`,
// iPadOS/macOS) -- eine zweite Navigationsspalte neben der Seitenleiste
// konkurriert mit ihr, statt sie zu ergaenzen. Und die Sitzungsleiste ist das
// Rueckgrat dieses Fensters: sie darf nicht verschwinden, nur weil jemand einen
// Ordner ansieht. Der Inspektor steht schon (Auftrag 2.4), klappt ein, merkt
// seine Breite (`blatt-breite`) und hat seinen Knopf in der Symbolleiste; die
// vier Blaetter teilen sich das alles.
//
// Der Umschalter oben ist ein `Picker(.segmented)` -- die Form, in der Pages,
// Numbers und Xcode ihre Inspektor-Reiter zeigen. Die Kuerzel ⌥⌘1 bis ⌥⌘4
// folgen Xcodes Inspektoren.
import SwiftUI
import WerkbankProtokoll

/// Welches Blatt der Inspektor zeigt.
enum BlattWahl: String, CaseIterable, Sendable {
    case freigaben, ordner, aktivitaet, protokolle

    var titel: String {
        switch self {
        case .freigaben: "Freigaben"
        case .ordner: "Ordner"
        case .aktivitaet: "Aktivität"
        case .protokolle: "Protokolle"
        }
    }

    var symbol: String {
        switch self {
        case .freigaben: "checkmark.shield"
        case .ordner: "folder"
        case .aktivitaet: "clock.arrow.circlepath"
        case .protokolle: "doc.text.magnifyingglass"
        }
    }
}

/// Alles, was der Inspektor zeichnet, an einer Stelle -- damit das Fenster
/// EINEN Hosting-View haelt und nicht vier.
@MainActor
struct InspektorBlatt: View {
    let kern: KernVerbindung
    let oberflaeche: Oberflaeche
    let freigaben: FreigabenZustand
    let ordner: OrdnerZustand
    let aktivitaet: AktivitaetZustand
    let protokolle: ProtokolleZustand
    unowned let handlungen: Freigabehandlungen
    var beleg = false

    var body: some View {
        VStack(spacing: 0) {
            umschalter
            Divider()
            inhalt
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Im Fenster bringt der Inspektor sein Material vom System mit; im
        // Beleg gibt es keines, und der Streifen mit dem Umschalter stand
        // deshalb durchsichtig vor der dunklen Symbolleiste -- die vier Woerter
        // waren im hellen Bild grau auf schwarz (gemessen am Belegbild 06.09.).
        // Die Blaetter selbst hatten ihren Grund schon, der Rahmen nicht.
        .background(beleg ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.clear))
        .accessibilityIdentifier("inspektor")
    }

    @ViewBuilder
    private var umschalter: some View {
        if beleg {
            // Ein Picker zeichnet im ImageRenderer nichts (AppKit-gestuetzt,
            // gemessen 06.09. an Knoepfen und Textfeldern) -- im Beleg stehen
            // die vier Woerter, das gewaehlte halbfett.
            HStack(spacing: 10) {
                ForEach(BlattWahl.allCases, id: \.rawValue) { w in
                    Text(w.titel)
                        .font(.callout)
                        .fontWeight(w == oberflaeche.blatt ? .semibold : .regular)
                        .foregroundStyle(w == oberflaeche.blatt ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Picker("Blatt", selection: Binding(
                get: { oberflaeche.blatt },
                set: { oberflaeche.blatt = $0 }
            )) {
                ForEach(BlattWahl.allCases, id: \.rawValue) { w in
                    Label(w.titel, systemImage: w.symbol)
                        .labelStyle(.iconOnly)
                        .help(w.titel)
                        .tag(w)
                        .accessibilityLabel(w.titel)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .accessibilityIdentifier("inspektor-umschalter")
        }
    }

    @ViewBuilder
    private var inhalt: some View {
        switch oberflaeche.blatt {
        case .freigaben:
            FreigabenBlatt(kern: kern, zustand: freigaben, handlungen: handlungen, beleg: beleg)
        case .ordner:
            OrdnerAnsicht(zustand: ordner, beleg: beleg)
        case .aktivitaet:
            AktivitaetAnsicht(zustand: aktivitaet, beleg: beleg)
        case .protokolle:
            ProtokolleAnsicht(zustand: protokolle, beleg: beleg)
        }
    }
}

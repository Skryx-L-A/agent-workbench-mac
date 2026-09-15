// Die Maschinenkarte (Auftrag 2.5, mac/PLAN.md): eine Karte je Maschine ueber
// der Fusszeile der Seitenleiste, dauerhaft sichtbar und ohne Klick -- Name,
// Erreichbarkeit als Punkt UND Wort, Pruefstand als Viereck, Kurzzeile mit
// Sitzungen und laufenden Workern. Ein Klick auf die Karte oeffnet ihr Popover
// mit den Einzelheiten und dem Schalter „Sitzungen laden“ (`maschine-laden`).
//
// Vorbild: app/src/renderer/fuss-status.ts (Karte, `maschinenFeld`). Diese
// Datei ZEICHNET nur, was der Kern liefert (`maschinen`, `ampel`); eine
// Auslastung liefert er nicht, also steht hier auch keine.
//
// Form nach der Hausregel (apple-native-design): Flaeche in Systemfarbe,
// Rundung, kein Rahmen, keine neue Farbe ausser den Zustandsfarben; Textstile
// statt Punktgroessen, SF Symbols statt Emojis. Zustand nie als Farbe allein
// (abnahme.md, Merkmal 5): der Punkt hat eine Form UND die Kurzzeile ein Wort.
import SwiftUI
import WerkbankProtokoll

/// Was der Statusfuss ausloesen kann -- das Fenster fuehrt es aus.
@MainActor
protocol Fusshandlungen: AnyObject {
    /// Das Popover einer Karte auf oder zu (immer nur eines offen).
    func karteUmschalten(_ maschine: String)
    /// Der Schalter im Popover: die Maschine (wieder) abrufen oder pausieren.
    func maschineLaden(_ maschine: String, _ laden: Bool)
    /// Der Hinweis im Fuss ist gelesen.
    func hinweisWeg()
    /// Das Zahnrad.
    func einstellungenZeigen()
    /// Die Verbrauchszeile: sie fuehrt auf die Verbrauchsseite (Auftrag 3.8).
    func verbrauchZeigen()
    /// Die Ergebnismeldung (`awb:ergebnis`, Auftrag 3.5): oeffnen oder wegraeumen.
    func ergebnisOeffnen()
    func ergebnisWeg()
}

struct Maschinenkarte: View {
    let maschine: MaschinenStand
    let ampel: AmpelStand?
    let oberflaeche: Oberflaeche
    unowned let handlungen: Fusshandlungen
    /// Kopflos gibt es kein Popover, nur den Zustand in `oberflaeche.offeneKarte`.
    var kopflos = false
    /// Im Beleg (Fenster.schuss) steht das offene Feld unter der Karte, weil
    /// ein Popover ausserhalb des Bildschirms nichts zeichnet.
    var beleg = false

    private var offen: Bool { oberflaeche.offeneKarte == maschine.name }

    /// Die Karte ist ein Knopf (Tab erreicht sie, Leertaste oeffnet das Feld --
    /// abnahme.md, Merkmal 11); im Beleg nur ihre Flaeche, weil ein Button im
    /// ImageRenderer nichts zeichnet (gemessen 06.09., Freigabenblatt).
    var body: some View {
        Group {
            if beleg {
                karte
            } else {
                Button { handlungen.karteUmschalten(maschine.name) } label: { karte }
                    .buttonStyle(.plain)
            }
        }
        .popover(isPresented: Binding(
            get: { offen && !kopflos && !beleg },
            set: { neu in if !neu, offen { handlungen.karteUmschalten(maschine.name) } }
        ), arrowEdge: .trailing) {
            MaschinenFeld(maschine: maschine, ampel: ampel, handlungen: handlungen)
        }
        .help("Mehr zu dieser Maschine")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Maschine \(maschine.name), \(maschine.kurzzeile)"
                            + (ampel.map { ", Prüfstand \($0.farbe)" } ?? "") + ", öffnet die Einzelheiten")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("maschine:\(maschine.name)")
    }

    private var karte: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Zustandspunkt(art: Self.punkt(maschine.punktFarbe))
                Text(maschine.name)
                    .fontWeight(.semibold)
                    .foregroundStyle(maschine.pausiert ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                if maschine.pausiert {
                    // Ihr eigenes Wort, damit „pausiert“ nicht nur eine Farbe ist.
                    Text("pausiert").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if let a = ampel {
                    // Rund heisst Maschine, eckig heisst Pruefstand (fuss-status.ts).
                    Image(systemName: a.farbe == "unbekannt" ? "square" : "square.fill")
                        .foregroundStyle(Self.ampelFarbe(a.farbe))
                        .imageScale(.small)
                        .help("Prüfstand \(a.machine): \(a.befundText)")
                        .accessibilityHidden(true)
                }
            }
            Text(maschine.kurzzeile)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if beleg && offen {
                MaschinenFeld(maschine: maschine, ampel: ampel, handlungen: handlungen, beleg: true)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(offen ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quaternary.opacity(0.5))))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Die Klasse des Kerns als Punkt (fuss-status.ts): gefuellt heisst
    /// erreichbar, ein Ring heisst „noch nicht nachgesehen", hohl und rot heisst
    /// „hat nicht geantwortet", gedaempft gefuellt heisst „pausiert". Das Wort
    /// steht in der Kurzzeile darunter noch einmal.
    static func punkt(_ klasse: String) -> Punktart {
        Punktart(rawValue: klasse) ?? .ruhig
    }

    static func ampelFarbe(_ farbe: String) -> Color {
        switch farbe {
        case "rot": return .red
        case "gelb": return .yellow
        case "gruen": return .green
        default: return Color.secondary
        }
    }
}

/// Das Feld hinter der Karte: was der Kern ueber DIESE Maschine liefert, und
/// der Schalter fuer eine ferne Maschine (fuss-status.ts `maschinenFeld`).
struct MaschinenFeld: View {
    let maschine: MaschinenStand
    let ampel: AmpelStand?
    unowned let handlungen: Fusshandlungen
    /// Im Beleg kein Toggle (AppKit-gestuetzt, zeichnet im ImageRenderer nichts): sein Wortlaut.
    var beleg = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !beleg { Text(maschine.name).font(.headline) }
            VStack(alignment: .leading, spacing: 3) {
                // Drei Zustaende, drei Woerter: „pausiert“ ist ausdruecklich NICHT „nein“.
                zeile("Erreichbar", maschine.eigen ? "diese Maschine"
                      : maschine.pausiert ? "pausiert"
                      : maschine.erreichbar == nil ? "nicht nachgesehen"
                      : maschine.erreichbar == true ? "ja" : "nein")
                if !maschine.eigen && !maschine.pausiert { zeile("Letzte Antwort", maschine.alterText) }
                if !maschine.fehler.isEmpty && !maschine.pausiert { zeile("Grund", maschine.fehler) }
                zeile("Sitzungen", String(maschine.sitzungen))
                zeile("Laufende Worker", String(maschine.worker))
                if let a = ampel { zeile("Prüfstand", a.befundText) }
            }
            if !maschine.eigen {
                if beleg {
                    Label("Sitzungen laden: \(maschine.pausiert ? "aus" : "ein")",
                          systemImage: maschine.pausiert ? "square" : "checkmark.square")
                        .font(.callout)
                } else {
                    Toggle("Sitzungen laden", isOn: Binding(
                        get: { !maschine.pausiert },
                        set: { handlungen.maschineLaden(maschine.name, $0) }
                    ))
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("maschine-laden:\(maschine.name)")
                }
                Text("Ausgeschaltet wird diese Maschine nicht mehr über ssh abgefragt. Ihre Sitzungen laufen dort ungestört weiter; pausiert ist nur der Blick dieser Werkbank auf sie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(beleg ? 0 : 12)
        .frame(width: beleg ? nil : 280, alignment: .leading)
        .accessibilityIdentifier("maschinenfeld")
    }

    /// Bezeichnung links in fester Spaltenbreite (eine Layoutbreite, keine
    /// Textgroesse), Wert rechts mit Umbruch -- ein Grid nahm sich die ideale
    /// Breite des laengsten Werts und sprengte die Spalte (gemessen 06.09.).
    private func zeile(_ was: String, _ wert: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(was).foregroundStyle(.secondary).frame(width: beleg ? 84 : 104, alignment: .leading)
            Text(wert).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }

    /// Der Wortlaut des Felds fuer `awbmac-ctl ui` -- was als Text darin steht.
    static func text(_ m: MaschinenStand, _ a: AmpelStand?) -> String {
        var t = ["Erreichbar", m.eigen ? "diese Maschine" : m.pausiert ? "pausiert" : m.erreichbar == nil ? "nicht nachgesehen" : m.erreichbar == true ? "ja" : "nein"]
        if !m.eigen && !m.pausiert { t += ["Letzte Antwort", m.alterText] }
        if !m.fehler.isEmpty && !m.pausiert { t += ["Grund", m.fehler] }
        t += ["Sitzungen", String(m.sitzungen), "Laufende Worker", String(m.worker)]
        if let a { t += ["Prüfstand", a.befundText] }
        if !m.eigen { t += ["Sitzungen laden"] }
        return t.joined(separator: " ")
    }
}

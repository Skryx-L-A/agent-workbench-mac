// Der Tab-Streifen (Auftrag 2.3, mac/PLAN.md): mehr Worker, als Kacheln in
// einen Tab passen (`capacity.perTab`), werden in Tabs geschnitten -- wie
// renderer.ts `zeichneStreifen`. Der Streifen steht NUR, wenn er etwas zu
// schalten hat: ab zwei Tabs, und nur solange Worker-Kacheln auf der Buehne
// liegen (kopfzeile, 05.09.). Sonst ist der Kopf genau so hoch wie ohne ihn;
// der Streifen sitzt unter der Symbolleiste im Inhalt, neben der
// Freigabeleiste, und laesst den Fenstertitel unangetastet.
//
// Je Tab: Zustandspunkt (die dringendste Farbe seiner Worker), „Tab n" und die
// Zahl der Worker darin; das Hilfeschildchen nennt die Namen. Textstile statt
// Punktgroessen, Systemfarben, der gewaehlte Tab in der Systemakzentfarbe.
import SwiftUI
import WerkbankProtokoll

struct TabMarke: Equatable, Identifiable {
    var id: Int { nr }
    let nr: Int
    let anzahl: Int
    /// laeuft | will | fern | ruhig (renderer.ts `tabFarbe`)
    let farbe: String
    let namen: [String]

    static func farbe(fuer worker: [WorkerEintrag]) -> String {
        if worker.contains(where: { $0.state == "blocked" || $0.state == "stalled" }) { return "will" }
        if worker.contains(where: { $0.state == "running" }) { return "laeuft" }
        if worker.contains(where: { $0.state == "unknown" }) { return "fern" }
        return "ruhig"
    }

    /// Die dringendste Lage der Worker im Tab, als Punkt (renderer.ts `tabFarbe`).
    var punkt: Punktart { Punktart(rawValue: farbe) ?? .ruhig }

    var zustandWort: String {
        switch farbe {
        case "laeuft": return "läuft"
        case "will": return "wartet"
        case "fern": return "nicht einsehbar"
        default: return "ruhig"
        }
    }

    /// Wortgleich zur Electron-Fassung (`tab.marke`: „Tab {n}").
    var text: String { "Tab \(nr + 1)" }
}

struct TabStreifen: View {
    let marken: [TabMarke]
    let gewaehlt: Int
    let waehlen: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(marken) { m in
                let an = m.nr == gewaehlt
                Button {
                    waehlen(m.nr)
                } label: {
                    HStack(spacing: 5) {
                        Zustandspunkt(art: m.punkt)
                        Text(m.text)
                            .fontWeight(an ? .semibold : .regular)
                        Text("\(m.anzahl)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(an ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.clear), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(m.namen.joined(separator: ", "))
                .accessibilityLabel("\(m.text), \(m.anzahl) Worker, \(m.zustandWort)")
                .accessibilityAddTraits(an ? [.isSelected] : [])
            }
            Spacer()
            if let m = marken.first(where: { $0.nr == gewaehlt }) {
                Text(m.namen.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Worker-Tabs")
        .accessibilityIdentifier("tabstreifen")
    }
}

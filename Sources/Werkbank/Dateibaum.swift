// Der Dateibaum des Editor-Blatts (Auftrag 3.4): die Spalte links im Editor.
// Er zeigt den Ordner der Sitzung auf der Buehne, und zwar genau die Dateien,
// die `awb:editor-list-files` durchlaesst -- die Ausschlussliste sitzt im Kern
// (editor.ts `ausschlussFilter`), nicht hier; eine `.env` erscheint also gar
// nicht erst, statt nur ausgeblendet zu werden.
//
// Oben ein Suchfeld: es filtert die flache Liste (dieselbe Buchstabenfolge wie
// der Schnelloeffner der Electron-Fassung) und klappt den Baum dabei auf,
// sonst blieben die Treffer hinter zugeklappten Ordnern.
//
// Die Rechnung -- Baum bauen, Zeilen aufklappen, filtern -- liegt in
// WerkbankProtokoll/Dateibaum.swift unter `swift test`; hier wird gezeichnet.
import SwiftUI
import WerkbankProtokoll

struct DateibaumAnsicht: View {
    @Bindable var zustand: EditorBlattZustand
    /// Im Beleg zeichnen ScrollView und Textfeld nichts (mac/PLAN.md, 2.4) --
    /// dann steht dieselbe Liste ohne sie.
    var beleg = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            kopf
            Divider()
            if beleg {
                VStack(alignment: .leading, spacing: 0) { liste }
                    .padding(.vertical, 4)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) { liste }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dateibaum")
        .accessibilityIdentifier("dateibaum")
    }

    @ViewBuilder
    private var kopf: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kurzpfad)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.head)
                .help(zustand.wurzel)
            if beleg {
                Text(zustand.filter.isEmpty ? "Datei suchen" : zustand.filter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TextField("Datei suchen", text: $zustand.filter)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Datei suchen")
            }
            if !zustand.baumFehler.isEmpty {
                Text(zustand.baumFehler)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var liste: some View {
        ForEach(zustand.zeilen) { z in
            zeile(z)
        }
        if zustand.zeilen.isEmpty {
            Text(zustand.wurzel.isEmpty ? "Keine Sitzung gewählt." : "Keine Datei.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func zeile(_ z: BaumZeile) -> some View {
        let gewaehlt = !z.ordner && zustand.aktiverTab?.key == z.pfad
        let inhalt = HStack(spacing: 5) {
            Image(systemName: symbol(z))
                .foregroundStyle(z.ordner ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            Text(z.name)
                .fontWeight(gewaehlt ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(z.tiefe) * 12 + 10)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .contentShape(Rectangle())

        if beleg {
            inhalt
        } else {
            Button {
                if z.ordner {
                    zustand.ordnerUmschalten(z.pfad)
                } else {
                    Task { await zustand.oeffnen(z.pfad) }
                }
            } label: {
                inhalt
            }
            .buttonStyle(.plain)
            .help(z.pfad)
            .accessibilityLabel(z.ordner ? "Ordner \(z.name), \(z.offen ? "aufgeklappt" : "zugeklappt")" : z.name)
            .accessibilityAddTraits(gewaehlt ? [.isSelected] : [])
        }
    }

    private func symbol(_ z: BaumZeile) -> String {
        guard z.ordner else { return "doc.text" }
        return z.offen ? "folder.fill" : "folder"
    }

    /// Der Ordnername mit seinem Elternteil -- wie der Kurzpfad der Seitenleiste.
    private var kurzpfad: String {
        let teile = zustand.wurzel.split(separator: "/").map(String.init)
        guard !teile.isEmpty else { return "Kein Ordner" }
        return teile.suffix(2).joined(separator: "/")
    }
}

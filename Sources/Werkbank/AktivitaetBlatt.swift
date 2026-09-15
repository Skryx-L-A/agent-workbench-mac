// DAS AKTIVITAETS-BLATT (Auftrag 3.5): was Worker und Sitzungen erzeugt haben,
// nach WER und WANN geordnet -- kein Dateibaum, weil man einen Namen vergisst,
// aber nicht, wer etwas gemacht hat und ungefaehr wann
// (`app/src/renderer/aktivitaet-view.ts`, Quelle main/aktivitaet.ts).
//
// ZWEI KLICKS, WIE IN DER ELECTRON-FASSUNG. Der erste oeffnet den Inhalt im
// Editor (schreibgeschuetzt); ein zweiter auf DENSELBEN Eintrag zeigt mehr --
// bei einer Aenderung den Unterschied, bei einem Ergebnis den Auftrag neben dem
// Ergebnis. Gelesen wird beides im Kern (`awb:aktivitaet-read`, `-diff`,
// `-auftrag`), und dort auch geprueft: nur ein Pfad aus der zuletzt gelesenen
// Aktivitaet ist erlaubt.
//
// DER UNTERSCHIED STEHT ALS TEXT, NICHT IN ZWEI SPALTEN. Monaco bringt einen
// Diff-Editor mit; der Mantel hat EINEN Editor mit mehreren Tabs (Entscheidung
// aus 3.4: ein zweiter NSTextView waere ein zweiter TextKit-Baum und ein
// zweiter Faerber, 76 MB je Baustein). Also wird der Unterschied gerechnet
// (`WerkbankProtokoll/Unterschied.swift`, unter `swift test`) und wie ein
// `git diff` gezeigt -- dieselbe Auskunft in der Form, die zu einem Editor
// passt. Aus demselben Grund stehen Auftrag und Ergebnis untereinander in einem
// Tab statt nebeneinander in zweien.
import SwiftUI
import WerkbankProtokoll

@MainActor
@Observable
final class AktivitaetZustand {
    @ObservationIgnored let kern: KernVerbindung
    @ObservationIgnored private unowned let editor: EditorBlattZustand

    private(set) var eintraege: [AktivitaetEintrag] = []
    /// Der Eintrag, dessen Inhalt offen ist -- ein zweiter Klick DARAUF zeigt mehr.
    private(set) var aktiverPfad = ""
    private(set) var meldung = ""
    private(set) var sichtbar = false
    private(set) var lesungen = 0

    @ObservationIgnored private var letzterTakt = Date.distantPast
    /// Zehn Sekunden: die Liste liest `git log` in jedem sichtbaren Projekt --
    /// teurer als ein Ordner, und sie aendert sich in der Groessenordnung von
    /// Minuten, nicht von Sekunden.
    static let taktSekunden: TimeInterval = 10

    init(kern: KernVerbindung, editor: EditorBlattZustand) {
        self.kern = kern
        self.editor = editor
    }

    func sichtbarSetzen(_ an: Bool) {
        guard an != sichtbar else { return }
        sichtbar = an
        if an {
            letzterTakt = Date()
            kern.aktivitaetLesen()
        }
    }

    func takt() {
        guard sichtbar else { return }
        guard Date().timeIntervalSince(letzterTakt) >= Self.taktSekunden else { return }
        letzterTakt = Date()
        kern.aktivitaetLesen()
    }

    func angekommen(_ p: AktivitaetNutzlast) {
        lesungen += 1
        eintraege = p.entries
    }

    /// Jetzt nachsehen, ohne den Takt abzuwarten -- der Weg des Steuerkanals.
    func jetztLesen() {
        letzterTakt = Date()
        kern.aktivitaetLesen()
    }

    /// Der Klick auf einen Eintrag. Beim ERSTEN Mal der Inhalt, beim zweiten
    /// auf denselben Eintrag der Unterschied bzw. der Auftrag.
    @discardableResult
    func klick(_ pfad: String) async -> (ok: Bool, was: String, meldung: String) {
        guard let e = eintraege.first(where: { $0.pfad == pfad }) else {
            meldung = "Dieser Eintrag steht nicht mehr in der Liste."
            return (false, "", meldung)
        }
        if pfad == aktiverPfad {
            return e.aenderung ? await unterschied(e) : await auftrag(e)
        }
        let r = await kern.aktivitaetInhalt(pfad)
        guard r.ok else {
            meldung = r.fehler
            return (false, "", r.fehler)
        }
        await editor.oeffnenAbsolut(key: pfad, label: e.name, abs: pfad, text: r.inhalt)
        aktiverPfad = pfad
        meldung = ""
        return (true, "inhalt", "")
    }

    private func unterschied(_ e: AktivitaetEintrag) async -> (ok: Bool, was: String, meldung: String) {
        let r = await kern.aktivitaetDiff(e.pfad)
        guard r.ok else {
            meldung = r.fehler
            return (false, "", r.fehler)
        }
        let text = Unterschied.vereinheitlicht(alt: r.alt, neu: r.neu, altName: "\(e.name) vorher", neuName: "\(e.name) nachher")
        // Die Endung `.diff` waehlt die Faerbung des Bausteins; der Tab traegt
        // seine eigene Kennung, damit er die Datei daneben nicht verdraengt.
        await editor.oeffnenAbsolut(key: "diff:\(e.pfad)", label: "Unterschied: \(e.name)",
                                    abs: "\(e.pfad).diff", text: text)
        meldung = ""
        return (true, "diff", "")
    }

    private func auftrag(_ e: AktivitaetEintrag) async -> (ok: Bool, was: String, meldung: String) {
        let r = await kern.aktivitaetAuftrag(e.pfad)
        guard r.ok else {
            meldung = r.fehler
            return (false, "", r.fehler)
        }
        let text = "# Auftrag\n\n\(r.auftrag)\n\n# Ergebnis\n\n\(r.ergebnis)\n"
        await editor.oeffnenAbsolut(key: "auftrag:\(e.pfad)", label: "Auftrag: \(e.name)",
                                    abs: "\(e.pfad).auftrag.md", text: text)
        meldung = ""
        return (true, "auftrag", "")
    }

    func auskunft() -> [String: Any] {
        [
            "sichtbar": sichtbar,
            "eintraege": eintraege.count,
            "lesungen": lesungen,
            "aktiverPfad": aktiverPfad,
            "meldung": meldung,
            "zeilen": eintraege.map { ["typ": $0.typ, "wer": $0.wer, "pfad": $0.pfad, "name": $0.name,
                                       "groesse": $0.groesse, "kommentar": $0.kommentar, "sitzung": $0.sessionId] },
            "texte": eintraege.map { "\($0.wer) \($0.seitHer()) \($0.name) \($0.aenderung ? $0.kommentar : "\($0.groesse) B")" },
        ]
    }
}

// MARK: - Die Ansicht

struct AktivitaetAnsicht: View {
    let zustand: AktivitaetZustand
    var beleg = false

    var body: some View {
        Group {
            if beleg {
                VStack(alignment: .leading, spacing: 0) { inhalt.padding(10); Spacer(minLength: 0) }
            } else {
                ScrollView { inhalt.padding(10) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(beleg ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.background))
        .accessibilityIdentifier("aktivitaetblatt")
    }

    private var inhalt: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !zustand.meldung.isEmpty {
                Label(zustand.meldung, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if zustand.eintraege.isEmpty {
                Text("Noch nichts geschrieben: keine Ergebnisdatei und keine Änderung im Projektordner.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(zustand.eintraege) { e in
                    if beleg {
                        zeile(e)
                    } else {
                        Button { Task { await zustand.klick(e.pfad) } } label: { zeile(e) }
                            .buttonStyle(.plain)
                            .help(e.pfad == zustand.aktiverPfad
                                  ? "Noch einmal klicken: \(e.aenderung ? "Unterschied" : "Auftrag und Ergebnis") — \(e.pfad)"
                                  : e.pfad)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func zeile(_ e: AktivitaetEintrag) -> some View {
        // Fremder Text (Worker-Name, Commit-Botschaft, Dateiname) steht als
        // String in `Text(...)`, nie als LocalizedStringKey.
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: e.aenderung ? "pencil" : "doc.text")
                    .font(.caption).foregroundStyle(.secondary)
                Text(e.wer).fontWeight(.semibold).lineLimit(1)
                Spacer(minLength: 4)
                Text(e.seitHer()).font(.caption).foregroundStyle(.secondary)
            }
            Text(e.name).font(.callout).lineLimit(1).truncationMode(.middle)
            Text(e.aenderung ? e.kommentar : "\(e.groesse) B")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(e.pfad == zustand.aktiverPfad ? AnyShapeStyle(Color.accentColor.opacity(0.14)) : AnyShapeStyle(Color(nsColor: .quaternarySystemFill))))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(e.wer), \(e.seitHer()), \(e.name)")
    }
}

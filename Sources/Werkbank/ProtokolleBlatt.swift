// DAS PROTOKOLL-BLATT (Auftrag 3.6): Guard-Log, Hygiene-Bericht,
// Testlauf-Bericht, SESSION-STATE.md -- vier Pfade, die man sonst einzeln
// kennen muss. Eine Liste, ein Klick oeffnet die Datei schreibgeschuetzt im
// Editor (`app/src/renderer/protokolle-view.ts`).
//
// Die Liste selbst steht in den EINSTELLUNGEN (`logPaths`), nicht im Code --
// derselbe Grund wie bei der Ausschlussliste des Ordnerbaums: sichtbar und
// aenderbar. Welche Datei gelesen werden darf, entscheidet der Kern
// (`protokollLesen` prueft gegen dieselbe Liste); dieses Blatt schickt nur den
// Pfad, den es selbst aus der Liste bekommen hat.
//
// Bewusst der kleinste der drei Blaetter: keine Suche, keine Vorschau, kein
// eigenes Formular.
import SwiftUI
import WerkbankProtokoll

@MainActor
@Observable
final class ProtokolleZustand {
    @ObservationIgnored let kern: KernVerbindung
    @ObservationIgnored private unowned let editor: EditorBlattZustand

    private(set) var eintraege: [ProtokollEintrag] = []
    private(set) var meldung = ""
    private(set) var sichtbar = false
    private(set) var lesungen = 0

    @ObservationIgnored private var letzterTakt = Date.distantPast
    /// Fuenf Sekunden: die Liste ist ein `stat` je Pfad, aber ihr Zweck ist die
    /// Frage „gibt es den Bericht schon?", und die beantwortet sich in Sekunden.
    static let taktSekunden: TimeInterval = 5

    init(kern: KernVerbindung, editor: EditorBlattZustand) {
        self.kern = kern
        self.editor = editor
    }

    func sichtbarSetzen(_ an: Bool) {
        guard an != sichtbar else { return }
        sichtbar = an
        if an {
            letzterTakt = Date()
            Task { await laden() }
        }
    }

    func takt() {
        guard sichtbar else { return }
        guard Date().timeIntervalSince(letzterTakt) >= Self.taktSekunden else { return }
        letzterTakt = Date()
        Task { await laden() }
    }

    @discardableResult
    func laden() async -> Bool {
        let r = await kern.protokolleListe()
        lesungen += 1
        guard r.fehler.isEmpty else {
            meldung = r.fehler
            return false
        }
        eintraege = r.liste
        meldung = ""
        return true
    }

    @discardableResult
    func oeffnen(_ pfad: String) async -> (ok: Bool, meldung: String) {
        guard let e = eintraege.first(where: { $0.path == pfad }) else {
            meldung = "„\(Pfadlinks.kurzerPfad(pfad))“ steht nicht in der Protokoll-Liste."
            return (false, meldung)
        }
        guard e.exists else {
            meldung = "„\(e.label)“ gibt es noch nicht: \(Pfadlinks.kurzerPfad(e.path))"
            return (false, meldung)
        }
        let r = await kern.protokollLesen(e.path)
        guard r.ok else {
            meldung = r.fehler
            return (false, r.fehler)
        }
        await editor.oeffnenAbsolut(key: "protokoll:\(e.path)", label: e.label, abs: e.path, text: r.inhalt)
        meldung = ""
        return (true, "")
    }

    func auskunft() -> [String: Any] {
        [
            "sichtbar": sichtbar,
            "eintraege": eintraege.count,
            "lesungen": lesungen,
            "meldung": meldung,
            "zeilen": eintraege.map { ["label": $0.label, "pfad": $0.path, "da": $0.exists, "groesse": $0.size] },
            "texte": eintraege.map { "\($0.label) \($0.exists ? "\($0.size) B" : "fehlt") \($0.path)" },
        ]
    }
}

// MARK: - Die Ansicht

struct ProtokolleAnsicht: View {
    let zustand: ProtokolleZustand
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
        .accessibilityIdentifier("protokolleblatt")
    }

    private var inhalt: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !zustand.meldung.isEmpty {
                Label(zustand.meldung, systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if zustand.eintraege.isEmpty {
                Text("Keine Protokolle eingetragen. Die Liste steht in den Einstellungen (logPaths).")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(zustand.eintraege) { e in
                    if beleg {
                        zeile(e)
                    } else {
                        Button { Task { await zustand.oeffnen(e.path) } } label: { zeile(e) }
                            .buttonStyle(.plain)
                            .help(e.exists ? "Öffnen: \(e.path)" : "Gibt es noch nicht: \(e.path)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func zeile(_ e: ProtokollEintrag) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(e.label).fontWeight(.semibold).lineLimit(1)
                Spacer(minLength: 4)
                Text(e.exists ? "\(e.size) B" : "fehlt")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(Pfadlinks.kurzerPfad(e.path))
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.head)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(e.exists ? 1 : 0.6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .quaternarySystemFill)))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(e.label), \(e.exists ? "\(e.size) Byte" : "fehlt noch")")
    }
}

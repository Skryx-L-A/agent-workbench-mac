// Die Freigabeleiste: eine Zeile unter der Symbolleiste, solange etwas auf eine
// Entscheidung wartet (Auftrag 2.4, mac/PLAN.md). Wortlaut und Reihenfolge
// folgen der Electron-Leiste (renderer.ts `zeichneFreigaben`): wer wartet,
// worauf, in EINER Zeile ohne Pfad; Freigeben und Ablehnen ohne Pflicht zur
// Begruendung, die Begruendung klappt auf Wunsch auf; blaettern, wenn mehr als
// eine offen ist; ein Sprung zum wartenden Worker.
//
// DIE WAHRHEIT LIEGT IN DER ABLAGE, NICHT IM KLICK (freigabeleiste, 05.09.):
// die Leiste zeichnet `kern.freigaben`, sonst nichts. Eine Entscheidung geht
// an den Kern, der liest die Ablage neu und schickt den Stand -- erst der
// raeumt die Zeile ab. Wird eine Freigabe im Terminal erteilt (`wb-freigabe
// erteilen`), verschwindet die Zeile im naechsten Takt genauso.
//
// FREMDER TEXT BLEIBT TEXT (freigabenmarkup, 05.09.): Worker-Name, Befehl und
// Grund stammen aus Dateien, die ein Worker schreibt. Sie stehen in `Text(...)`
// mit einem String, nie als LocalizedStringKey mit Markdown-Deutung.
import SwiftUI
import WerkbankProtokoll

/// Was Leiste und Blatt ausloesen -- das Fenster fuehrt es aus.
@MainActor
protocol Freigabehandlungen: AnyObject {
    func entscheiden(_ f: OffeneFreigabe, annehmen: Bool, grund: String)
    func freigabenBlattZeigen()
    func workerZeigen(sitzung: String, pane: String)
}

/// Der Zustand der Leiste und des Blatts, den das Fenster und der Steuerkanal
/// teilen: welcher Eintrag vorne steht, ob die Begruendung offen ist, ihr Text.
@MainActor
@Observable
final class FreigabenZustand {
    /// Welcher der offenen Eintraege in der Leiste steht (renderer.ts `freigabeNr`).
    var nr = 0
    var begruendungOffen = false
    var grund = ""
    /// Die Begruendungen des Blatts, je Eintrag.
    var blattGruende: [String: String] = [:]
    /// Die letzte Rueckmeldung nach einer Entscheidung (Leiste und Blatt zeigen sie kurz).
    var meldung = ""
    var meldungBis = Date.distantPast

    func melden(_ text: String) {
        meldung = text
        meldungBis = Date().addingTimeInterval(4)
    }

    /// Der Eintrag, der vorne steht -- mit dem Zeiger im Bereich der Liste.
    func vorne(_ offene: [OffeneFreigabe]) -> OffeneFreigabe? {
        guard !offene.isEmpty else { return nil }
        if nr >= offene.count { nr = 0 }
        return offene[nr]
    }
}

struct FreigabeLeiste: View {
    let kern: KernVerbindung
    let zustand: FreigabenZustand
    unowned let handlungen: Freigabehandlungen

    var body: some View {
        let offene = kern.freigaben.offene
        if let f = zustand.vorne(offene) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    // Der Text ist der Weg ins Blatt: ein Klick oeffnet es.
                    Button { handlungen.freigabenBlattZeigen() } label: {
                        (Text(f.wer).bold() + Text(" wartet auf Dich · \(f.worum)").foregroundStyle(.secondary))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .buttonStyle(.plain)
                    .help("\(f.wer) · \(f.wo)\n\(f.worum)\nKlick öffnet das Freigabenblatt")
                    .accessibilityLabel("\(f.wer) wartet auf Dich, \(f.worum). Öffnet das Freigabenblatt")
                    .accessibilityIdentifier("freigabeleiste-text")
                    Spacer(minLength: 8)
                    if offene.count > 1 {
                        HStack(spacing: 2) {
                            Button { zustand.nr = (zustand.nr - 1 + offene.count) % offene.count } label: {
                                Image(systemName: "chevron.left")
                            }
                            .help("Vorige Freigabe")
                            .accessibilityLabel("Vorige Freigabe")
                            Text("\(zustand.nr + 1) von \(offene.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Button { zustand.nr = (zustand.nr + 1) % offene.count } label: {
                                Image(systemName: "chevron.right")
                            }
                            .help("Nächste Freigabe")
                            .accessibilityLabel("Nächste Freigabe")
                        }
                        .buttonStyle(.borderless)
                    }
                    Button {
                        zustand.begruendungOffen.toggle()
                    } label: {
                        Label("Begründung", systemImage: zustand.begruendungOffen ? "chevron.down" : "chevron.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless)
                    .help("Begründung aufklappen (freiwillig)")
                    .accessibilityAddTraits(zustand.begruendungOffen ? [.isSelected] : [])
                    Button("Freigeben") { entscheiden(f, true) }
                        .buttonStyle(.borderedProminent)
                        .help("Freigeben: \(f.wer)")
                    Button("Ablehnen") { entscheiden(f, false) }
                        .buttonStyle(.bordered)
                        .help("Ablehnen: \(f.wer)")
                    if !f.pane.isEmpty {
                        Button { handlungen.workerZeigen(sitzung: f.sessionId, pane: f.pane) } label: {
                            Image(systemName: "arrow.up.forward.square")
                        }
                        .buttonStyle(.borderless)
                        .help("Zu diesem Worker springen")
                        .accessibilityLabel("Zu diesem Worker springen")
                    }
                }
                .controlSize(.small)
                if zustand.begruendungOffen {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Begründung, falls Du eine hinterlassen willst …", text: Bindable(zustand).grund)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .accessibilityLabel("Begründung")
                        Text("Freiwillig. Die Entscheidung geht sofort an den Worker zurück.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !zustand.meldung.isEmpty && zustand.meldungBis > Date() {
                    Text(zustand.meldung).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Freigabeleiste, \(offene.count) offen")
        }
    }

    private func entscheiden(_ f: OffeneFreigabe, _ annehmen: Bool) {
        handlungen.entscheiden(f, annehmen: annehmen, grund: zustand.grund.trimmingCharacters(in: .whitespacesAndNewlines))
        zustand.grund = ""
    }
}

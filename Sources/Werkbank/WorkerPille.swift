// Die Pille „N laufen“ und die Worker-Liste dahinter (Auftrag 2.2, mac/PLAN.md).
//
// Die Pille sitzt in der Symbolleiste: ein Zustandspunkt (Farbe UND Zahl UND
// Wort -- abnahme.md, Merkmal 5) mit der Zahl der Worker DIESER Sitzung, die
// gerade arbeiten oder warten (renderer.ts `laufendeWorker`). Ein Klick oeffnet
// ein Popover mit der Liste: Zustand, Name, Modell, Herkunft, Tokenstand,
// Subagenten eingerueckt -- dieselben Zeilen-Views wie in Seitenleiste.swift
// (WorkerZeile, SubagentZeile), aus der Leiste herausgenommen auf des Nutzers
// Vorgabe vom 03.09. Ein Klick auf einen Worker legt seinen Pane auf die Buehne.
//
// Der Leerzustand sagt, warum nichts da ist, und was zu tun ist (abnahme.md,
// „Die Zustaende, die meistens fehlen").
//
// Textstile statt Punktgroessen, Systemfarben, der Punkt skaliert mit der Schrift.
import SwiftUI
import WerkbankProtokoll

/// Der Knopf in der Symbolleiste.
struct PilleAnsicht: View {
    let kern: KernVerbindung
    let offen: () -> Bool
    let klick: () -> Void

    var body: some View {
        let s = kern.gewaehlteSitzung
        let n = s?.laufendeWorker ?? 0
        Button(action: klick) {
            HStack(spacing: 5) {
                Zustandspunkt(art: Self.punkt(n))
                Text(Self.text(n))
                    .monospacedDigit()
                    .foregroundStyle(n > 0 ? Color.primary : Color.secondary)
            }
        }
        .buttonStyle(.bordered)
        .disabled(s == nil)
        .help("Worker dieser Sitzung, die gerade arbeiten oder warten")
        .accessibilityLabel("\(n) Worker laufen")
        .accessibilityHint("Öffnet die Worker-Liste")
        .accessibilityAddTraits(offen() ? [.isSelected] : [])
    }

    /// Wortgleich zur Electron-Fassung (`flaeche.workerLaufen`: „{n} laufen“).
    static func text(_ n: Int) -> String { "\(n) laufen" }

    /// Laufen welche, ist der Punkt gefuellt; sonst steht der ruhige Ring da
    /// (renderer.ts: `punkt ${laufend > 0 ? 'laeuft' : 'ruhig'}`).
    static func punkt(_ n: Int) -> Punktart { n > 0 ? .laeuft : .ruhig }
}

/// Die Liste im Popover.
struct WorkerListe: View {
    let kern: KernVerbindung
    unowned let handlungen: Sitzungshandlungen
    /// Nach einem Klick auf einen Worker: das Popover schliessen.
    var danach: () -> Void = {}

    var body: some View {
        let s = kern.gewaehlteSitzung
        let worker = s?.flacheWorker ?? []
        VStack(alignment: .leading, spacing: 8) {
            Text("Worker")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let s, !(worker.isEmpty && s.orphanSubagents.isEmpty) {
                let fremd = s.fern(eigene: kern.modell.machine) ? s.machine : ""
                ForEach(worker) { w in
                    let kind = s.istKind(w)
                    let kinder = worker.filter { $0.requestedBy == w.name && s.istKind($0) }.count
                    Button {
                        guard !w.paneId.isEmpty else { return }
                        handlungen.workerZeigen(sitzung: s.id, pane: w.paneId)
                        danach()
                    } label: {
                        WorkerZeile(worker: w, kind: kind, kinder: kinder, maschine: fremd)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(w.paneId.isEmpty)
                    ForEach(w.subagents) { sub in
                        Button {
                            guard !sub.paneId.isEmpty else { return }
                            handlungen.workerZeigen(sitzung: s.id, pane: sub.paneId)
                            danach()
                        } label: {
                            SubagentZeile(subagent: sub)
                                .padding(.leading, kind ? 16 : 0)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(sub.paneId.isEmpty)
                    }
                }
                ForEach(s.orphanSubagents) { sub in
                    SubagentZeile(subagent: sub, elternlos: true)
                }
            } else {
                ContentUnavailableView {
                    Label("Keine Worker", systemImage: "person.2.slash")
                } description: {
                    Text(Self.leerText)
                }
            }
        }
        .padding()
        .frame(minWidth: 320, idealWidth: 380, alignment: .topLeading)
        .accessibilityIdentifier("workerliste")
    }

    /// Der Leerzustand mit dem naechsten Schritt (Auftrag 2.2).
    static let leerText = "In dieser Sitzung läuft gerade kein Worker. Ein neuer entsteht im Orchestrator mit „claude-worker <name> …“."
}
